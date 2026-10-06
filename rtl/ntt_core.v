// ntt_core.v - in-place NTT / INTT accelerator for Kyber (ML-KEM) and Dilithium (ML-DSA).
//
// Parameters
//   SCHEME : 0 = Kyber     (q = 3329,    W = 12, 7-layer incomplete NTT)
//            1 = Dilithium (q = 8380417, W = 23, 8-layer complete NTT)
//   RED    : 0 = Barrett, 1 = Montgomery modular reduction
//   P      : butterflies per clock (1, 2, 4 or 8)
//
// Memory: 256 coefficients over NB = 2P single-read/single-write banks.
//   bank(i)   = XOR-fold of address i in B-bit fields (B = log2 NB)
//   offset(i) = i >> B
// In each cycle the 2P coefficients touched differ only in B address bits that
// cover every residue mod B, so they always land in distinct banks: no conflicts
// in any layer, for loads, or for unloads (2P consecutive coefficients).
//
// Operation (one polynomial at a time):
//   start (+inverse) -> LOAD 256/2P beats -> COMPUTE layers -> UNLOAD 256/2P beats -> done
//   Each layer issues 128/P cycles then drains the 6-cycle read+butterfly pipeline.
//
// Data order matches the pq-crystals reference: forward NTT takes normal order and
// returns bit-reversed order; inverse takes bit-reversed and returns normal order
// (fully scaled, standard domain, all values in [0,q)).
//
`timescale 1ns/1ps
`include "ntt_defs.vh"
module ntt_core #(
    parameter SCHEME = 0,
    parameter RED    = 0,
    parameter P      = 2,
    parameter W      = `NTT_W(SCHEME)
) (
    input  wire               clk,
    input  wire               rst_n,
    // control
    input  wire               start,
    input  wire               inverse,
    output wire               busy,
    output reg                done,
    // coefficient input: lane l of beat n is coefficient n*2P + l
    input  wire               in_valid,
    output wire               in_ready,
    input  wire [2*P*W-1:0]   in_data,
    // coefficient output: same lane ordering
    output reg                out_valid,
    input  wire               out_ready,
    output wire [2*P*W-1:0]   out_data
);
`include "ntt_params.vh"

    // ------------------------------------------------------------------
    // Derived sizes
    // ------------------------------------------------------------------
    localparam integer NB    = 2 * P;                                   // banks
    localparam integer B     = (P == 1) ? 1 : (P == 2) ? 2 : (P == 4) ? 3 : 4;
    localparam integer AW    = 8 - B;                                   // bank address bits
    localparam integer DEPTH = 1 << AW;                                 // words per bank
    localparam integer CYC   = 128 / P;                                 // issue cycles / layer
    localparam integer BEATS = DEPTH;                                   // I/O beats / polynomial
    localparam integer BF_LAT = 5;
    localparam integer DRAIN  = 1 + BF_LAT;                             // read + butterfly
    localparam integer K_MIN  = 8 - LAYERS;                             // smallest butterfly distance exponent

    localparam [1:0] S_IDLE = 2'd0, S_LOAD = 2'd1, S_COMP = 2'd2, S_UNLOAD = 2'd3;

    // ------------------------------------------------------------------
    // Address helpers (all evaluated with constant structure)
    // ------------------------------------------------------------------
    // XOR-fold: address bit p contributes to bank bit (p mod B)
    function [B-1:0] bank_of(input [7:0] idx);
        integer p;
        begin
            bank_of = {B{1'b0}};
            for (p = 0; p < 8; p = p + 1)
                bank_of[p % B] = bank_of[p % B] ^ idx[p];
        end
    endfunction

    // Index of the 'a' operand of lane l in issue cycle c of the layer with distance 2^kk.
    //   bit kk                       : 0 (butterfly bit)
    //   bits r < B, r != kk mod B    : lane number bits
    //   all other bits               : cycle counter bits
    function [7:0] lane_idx(input integer kk, input [7:0] c, input [7:0] l);
        integer p, nf, nl;
        begin
            lane_idx = 8'd0; nf = 0; nl = 0;
            for (p = 0; p < 8; p = p + 1) begin
                if (p == kk)
                    lane_idx[p] = 1'b0;
                else if ((p < B) && (p != (kk % B))) begin
                    lane_idx[p] = l[nl]; nl = nl + 1;
                end else begin
                    lane_idx[p] = c[nf]; nf = nf + 1;
                end
            end
        end
    endfunction

    // ------------------------------------------------------------------
    // Control state
    // ------------------------------------------------------------------
    reg  [1:0]  state;
    reg         inv_r;
    reg  [7:0]  cnt;          // load beat / issue cycle counter
    reg  [3:0]  li;           // layer index
    reg         draining;
    reg  [2:0]  dcnt;
    reg  [7:0]  ucnt;         // unload beats issued

    wire [2:0]  k     = inv_r ? (K_MIN[2:0] + li[2:0]) : (3'd7 - li[2:0]);
    wire        issue = (state == S_COMP) && !draining;
    wire        in_fire  = in_valid && in_ready;
    wire        rd_fire  = (state == S_UNLOAD) && (ucnt < BEATS) && (!out_valid || out_ready);

    assign in_ready = (state == S_LOAD);
    assign busy     = (state != S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; inv_r <= 1'b0; cnt <= 8'd0; li <= 4'd0;
            draining <= 1'b0; dcnt <= 3'd0; ucnt <= 8'd0;
            out_valid <= 1'b0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
            S_IDLE: if (start) begin
                inv_r <= inverse; cnt <= 8'd0; state <= S_LOAD;
            end
            S_LOAD: if (in_fire) begin
                if (cnt == BEATS - 1) begin
                    cnt <= 8'd0; li <= 4'd0; draining <= 1'b0; state <= S_COMP;
                end else
                    cnt <= cnt + 8'd1;
            end
            S_COMP: if (!draining) begin
                if (cnt == CYC - 1) begin
                    cnt <= 8'd0; draining <= 1'b1; dcnt <= 3'd0;
                end else
                    cnt <= cnt + 8'd1;
            end else begin
                dcnt <= dcnt + 3'd1;
                if (dcnt == DRAIN - 1) begin
                    draining <= 1'b0;
                    if (li == LAYERS - 1) begin
                        ucnt <= 8'd0; out_valid <= 1'b0; state <= S_UNLOAD;
                    end else
                        li <= li + 4'd1;
                end
            end
            S_UNLOAD: begin
                if (rd_fire) begin
                    ucnt <= ucnt + 8'd1;
                    out_valid <= 1'b1;
                end else if (out_ready)
                    out_valid <= 1'b0;
                if ((ucnt == BEATS) && out_valid && out_ready) begin
                    state <= S_IDLE; done <= 1'b1;
                end
            end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Per-layer address / twiddle-index generation: build every layer's
    // wiring at elaboration time, select with the runtime k.
    // ------------------------------------------------------------------
    wire [8*8*P-1:0] ia_all;     // [(kk*P + l)*8 +: 8]
    wire [8*8*P-1:0] tw_all;
    genvar gk, gl;
    generate
        for (gk = 0; gk < 8; gk = gk + 1) begin : g_k
            for (gl = 0; gl < P; gl = gl + 1) begin : g_l
                localparam [7:0] LANE = gl;
                wire [7:0] ia = lane_idx(gk, cnt, LANE);
                assign ia_all[(gk*P + gl)*8 +: 8] = ia;
                assign tw_all[(gk*P + gl)*8 +: 8] = (8'd128 >> gk) | (ia >> (gk + 1));
            end
        end
    endgenerate

    // ------------------------------------------------------------------
    // Lanes: address decode, twiddle ROM, write-back metadata pipeline
    // ------------------------------------------------------------------
    wire [NB*W-1:0]  bank_rdata;              // [j*W +: W]
    wire [P*B-1:0]   iss_bank_a, iss_bank_b;  // issue-cycle bank ids
    wire [P*AW-1:0]  iss_off_a,  iss_off_b;
    wire [P*W-1:0]   bf_a, bf_b;              // butterfly outputs
    wire [P*B-1:0]   wb_bank_a, wb_bank_b;    // write-back stage bank ids
    wire [P*AW-1:0]  wb_off_a,  wb_off_b;

    // write-back valid: issue delayed by DRAIN cycles
    reg [DRAIN-1:0] vpipe;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) vpipe <= {DRAIN{1'b0}};
        else        vpipe <= {vpipe[DRAIN-2:0], issue};
    wire wb_valid = vpipe[DRAIN-1];

    generate
        for (gl = 0; gl < P; gl = gl + 1) begin : g_lane
            wire [7:0] idx_a = ia_all[(k*P + gl)*8 +: 8];
            wire [7:0] idx_b = idx_a | (8'd1 << k);
            wire [7:0] twi   = tw_all[(k*P + gl)*8 +: 8];

            assign iss_bank_a[gl*B +: B]   = bank_of(idx_a);
            assign iss_bank_b[gl*B +: B]   = bank_of(idx_b);
            assign iss_off_a[gl*AW +: AW]  = idx_a[7:B];
            assign iss_off_b[gl*AW +: AW]  = idx_b[7:B];

            // twiddle ROM, output registered alongside the bank read
            wire [W-1:0] tw_rom;
            reg  [W-1:0] tw_r;
            ntt_tw_rom #(.SCHEME(SCHEME), .RED(RED), .W(W)) u_rom (
                .idx (twi), .inv (inv_r), .w (tw_rom)
            );
            always @(posedge clk) tw_r <= tw_rom;

            // read-stage bank select (which bank returns a / b for this lane)
            reg [B-1:0] rsel_a, rsel_b;
            always @(posedge clk) begin
                rsel_a <= iss_bank_a[gl*B +: B];
                rsel_b <= iss_bank_b[gl*B +: B];
            end

            ntt_butterfly #(.SCHEME(SCHEME), .RED(RED), .W(W)) u_bf (
                .clk   (clk),
                .inv   (inv_r),
                .a     (bank_rdata[rsel_a*W +: W]),
                .b     (bank_rdata[rsel_b*W +: W]),
                .w     (tw_r),
                .a_out (bf_a[gl*W +: W]),
                .b_out (bf_b[gl*W +: W])
            );

            // write-back address pipeline (DRAIN deep, matches read + butterfly latency)
            reg [B-1:0]  pba [0:DRAIN-1];
            reg [B-1:0]  pbb [0:DRAIN-1];
            reg [AW-1:0] poa [0:DRAIN-1];
            reg [AW-1:0] pob [0:DRAIN-1];
            integer s;
            always @(posedge clk) begin
                pba[0] <= iss_bank_a[gl*B +: B];  pbb[0] <= iss_bank_b[gl*B +: B];
                poa[0] <= iss_off_a[gl*AW +: AW]; pob[0] <= iss_off_b[gl*AW +: AW];
                for (s = 1; s < DRAIN; s = s + 1) begin
                    pba[s] <= pba[s-1]; pbb[s] <= pbb[s-1];
                    poa[s] <= poa[s-1]; pob[s] <= pob[s-1];
                end
            end
            assign wb_bank_a[gl*B +: B]  = pba[DRAIN-1];
            assign wb_bank_b[gl*B +: B]  = pbb[DRAIN-1];
            assign wb_off_a[gl*AW +: AW] = poa[DRAIN-1];
            assign wb_off_b[gl*AW +: AW] = pob[DRAIN-1];
        end
    endgenerate

    // ------------------------------------------------------------------
    // Banks with read / write crossbars
    // ------------------------------------------------------------------
    reg  [NB-1:0]    b_re, b_we;
    reg  [NB*AW-1:0] b_raddr, b_waddr;
    reg  [NB*W-1:0]  b_wdata;
    integer j, l;

    always @(*) begin
        b_re = {NB{1'b0}}; b_we = {NB{1'b0}};
        b_raddr = {NB*AW{1'b0}}; b_waddr = {NB*AW{1'b0}}; b_wdata = {NB*W{1'b0}};
        for (j = 0; j < NB; j = j + 1) begin
            // ---- read port ----
            if (state == S_UNLOAD) begin
                b_re[j] = rd_fire;
                b_raddr[j*AW +: AW] = ucnt[AW-1:0];
            end else begin
                for (l = 0; l < P; l = l + 1) begin
                    if (iss_bank_a[l*B +: B] == j) begin
                        b_re[j] = issue; b_raddr[j*AW +: AW] = iss_off_a[l*AW +: AW];
                    end
                    if (iss_bank_b[l*B +: B] == j) begin
                        b_re[j] = issue; b_raddr[j*AW +: AW] = iss_off_b[l*AW +: AW];
                    end
                end
            end
            // ---- write port ----
            if (state == S_LOAD) begin
                for (l = 0; l < NB; l = l + 1) begin
                    if (bank_of({cnt[AW-1:0], l[B-1:0]}) == j) begin
                        b_we[j] = in_fire;
                        b_waddr[j*AW +: AW] = cnt[AW-1:0];
                        b_wdata[j*W +: W]   = in_data[l*W +: W];
                    end
                end
            end else begin
                for (l = 0; l < P; l = l + 1) begin
                    if (wb_bank_a[l*B +: B] == j) begin
                        b_we[j] = wb_valid; b_waddr[j*AW +: AW] = wb_off_a[l*AW +: AW];
                        b_wdata[j*W +: W] = bf_a[l*W +: W];
                    end
                    if (wb_bank_b[l*B +: B] == j) begin
                        b_we[j] = wb_valid; b_waddr[j*AW +: AW] = wb_off_b[l*AW +: AW];
                        b_wdata[j*W +: W] = bf_b[l*W +: W];
                    end
                end
            end
        end
    end

    genvar gj;
    generate
        for (gj = 0; gj < NB; gj = gj + 1) begin : g_bank
            ntt_bank #(.W(W), .DEPTH(DEPTH), .AW(AW)) u_bank (
                .clk   (clk),
                .re    (b_re[gj]),
                .raddr (b_raddr[gj*AW +: AW]),
                .rdata (bank_rdata[gj*W +: W]),
                .we    (b_we[gj]),
                .waddr (b_waddr[gj*AW +: AW]),
                .wdata (b_wdata[gj*W +: W])
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Output lane routing: lane l of the beat comes from bank_of({beat, l})
    // ------------------------------------------------------------------
    generate
        for (gl = 0; gl < NB; gl = gl + 1) begin : g_out
            localparam [7:0] LANE = gl;
            reg [B-1:0] osel;
            wire [7:0] oidx = {ucnt[AW-1:0], LANE[B-1:0]};
            always @(posedge clk) if (rd_fire) osel <= bank_of(oidx);
            assign out_data[gl*W +: W] = bank_rdata[osel*W +: W];
        end
    endgenerate

endmodule

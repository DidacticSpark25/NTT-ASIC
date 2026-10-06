// ntt_modmul.v - pipelined modular multiplier, r = a*b mod q (Barrett)
//                                            or r = a*b*R^-1 mod q (Montgomery, R = 2^W).
//
// Inputs a, b in [0,q). Output fully reduced to [0,q). Latency: 3 cycles.
//
//   stage 1 : p = a*b                                       (W x W multiply)
//   stage 2 : Barrett    t = (p*M) >> 2W                     (2W x (W+1), high half)
//             Montgomery m = (p mod R)*(-q^-1) mod R         (W x W, low half)
//   stage 3 : Barrett    r = p - t*q   (only low W+1 bits needed, r < 2q)
//             Montgomery r = (p + m*q) >> W
//             one conditional subtract of q
//
`timescale 1ns/1ps
`include "ntt_defs.vh"
module ntt_modmul #(
    parameter SCHEME = 0,         // 0 = kyber, 1 = dilithium
    parameter RED    = 0,         // 0 = barrett, 1 = montgomery
    parameter W      = `NTT_W(SCHEME)
) (
    input  wire                 clk,
    input  wire [W-1:0]         a,
    input  wire [W-1:0]         b,
    output reg  [W-1:0]         r
);
`include "ntt_params.vh"

    localparam [W-1:0] QV = Q;

    // ---------------- stage 1: full product ----------------
    reg [2*W-1:0] p1;
    always @(posedge clk) p1 <= a * b;

    generate
    if (RED == 0) begin : g_barrett
        localparam [W:0] MV = BAR_M;
        // ------------- stage 2: quotient estimate -------------
        wire [3*W:0]  pm   = p1 * MV;
        reg  [W-1:0]  t2;              // t < q
        reg  [W:0]    plo2;            // p mod 2^(W+1)
        always @(posedge clk) begin
            t2   <= pm[3*W-1:2*W];     // >> BAR_K (= 2W); t < q so bit 3W is always 0
            plo2 <= p1[W:0];
        end
        // ------------- stage 3: remainder + correction --------
        wire [2*W-1:0] tq   = t2 * QV;
        wire [W:0]     rr   = plo2 - tq[W:0];       // exact because 0 <= p - t*q < 2q < 2^(W+1)
        wire [W:0]     rsub = rr - {1'b0, QV};
        always @(posedge clk) r <= rsub[W] ? rr[W-1:0] : rsub[W-1:0];
    end else begin : g_montgomery
        localparam [W-1:0] QN = MONT_QN;
        // ------------- stage 2: m = (p mod R) * (-q^-1) mod R --
        wire [2*W-1:0] mq = p1[W-1:0] * QN;
        reg  [W-1:0]   m2;
        reg  [2*W-1:0] p2;
        always @(posedge clk) begin
            m2 <= mq[W-1:0];
            p2 <= p1;
        end
        // ------------- stage 3: t = (p + m*q) / R ----------------
        wire [2*W-1:0] mqf  = m2 * QV;
        wire [2*W:0]   s    = p2 + mqf;             // low W bits are zero by construction
        wire [W:0]     t    = s[2*W:W];             // t < 2q
        wire [W:0]     tsub = t - {1'b0, QV};
        always @(posedge clk) r <= tsub[W] ? t[W-1:0] : tsub[W-1:0];
    end
    endgenerate
endmodule

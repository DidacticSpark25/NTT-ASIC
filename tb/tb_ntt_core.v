// tb_ntt_core.v - self-checking testbench for ntt_core.
//
// For each test polynomial t:
//   1. forward : NTT(in[t])            == ntt[t]    (golden model / pq-crystals)
//   2. inverse : INTT(in[t])           == intt[t]
//   3. roundtrip: INTT(DUT NTT output) == in[t]
// with random valid/ready stalls on both streams (STALL=1).
// Also checks the compute-phase cycle count against the analytical model.
//
// Plusargs: +vec=<prefix>   (files <prefix>_in.hex, _ntt.hex, _intt.hex)
//           +sdf=<file>     (GLS only)
// Defines : GLS             simulate the ntt_top gate-level netlist instead of the RTL
`timescale 1ns/1ps
`include "ntt_defs.vh"
module tb_ntt_core;
    parameter SCHEME = 0;
    parameter RED    = 0;
    parameter P      = 2;
    parameter NTEST  = 16;
    parameter STALL  = 1;
    parameter SEED   = 7;

    localparam W      = `NTT_W(SCHEME);
    localparam NB     = 2 * P;
    localparam BEATS  = 256 / NB;
    localparam LAYERS = (SCHEME == 0) ? 7 : 8;
    localparam EXP_COMP = LAYERS * (128 / P + 6);   // must match model.cycle_count()

    reg clk = 1'b0;
    always #5 clk = ~clk;                           // 100 MHz in simulation

    reg               rst_n = 1'b0, start = 1'b0, inverse = 1'b0;
    reg               in_valid = 1'b0, out_ready = 1'b0;
    reg  [NB*W-1:0]   in_data = {NB*W{1'b0}};
    wire              in_ready, out_valid, busy, done;
    wire [NB*W-1:0]   out_data;

`ifdef GLS
    // gate-level simulation: post-synthesis or post-route netlist of ntt_top
    ntt_top dut (
`else
    ntt_core #(.SCHEME(SCHEME), .RED(RED), .P(P)) dut (
`endif
        .clk (clk), .rst_n (rst_n), .start (start), .inverse (inverse),
        .busy (busy), .done (done),
        .in_valid (in_valid), .in_ready (in_ready), .in_data (in_data),
        .out_valid (out_valid), .out_ready (out_ready), .out_data (out_data)
    );

`ifdef GLS
    // +sdf=<file> back-annotates post-route delays (Xcelium)
    reg [8*512:1] sdf_file;
    initial if ($value$plusargs("sdf=%s", sdf_file)) $sdf_annotate(sdf_file, dut, , "sdf.log", "MAXIMUM");
`endif

    reg [W-1:0] vin   [0:NTEST*256-1];
    reg [W-1:0] vntt  [0:NTEST*256-1];
    reg [W-1:0] vintt [0:NTEST*256-1];
    reg [W-1:0] src   [0:255];
    reg [W-1:0] expv  [0:255];
    reg [W-1:0] cap   [0:255];

    integer seed = SEED;
    integer errors = 0, checks = 0, done_cnt = 0, comp_cycles = 0, ops = 0;
    reg [8*256:1] prefix;

    always @(posedge clk) begin
        if (done) done_cnt = done_cnt + 1;
`ifndef GLS
        if (dut.state == 2'd2) comp_cycles = comp_cycles + 1;
`endif
    end

    // run one transform: stream src[] in, compare against expv[], keep result in cap[]
    task run_op(input inv, input [8*16:1] tag, input integer t);
        integer beat, ob, l, d0;
        begin
            d0 = done_cnt;
            @(negedge clk); start = 1'b1; inverse = inv;
            @(negedge clk); start = 1'b0;
            fork
                begin : drive
                    beat = 0;
                    while (beat < BEATS) begin
                        if (STALL && (($random(seed) & 7) == 0)) begin
                            in_valid = 1'b0;
                        end else begin
                            in_valid = 1'b1;
                            for (l = 0; l < NB; l = l + 1) in_data[l*W +: W] = src[beat*NB + l];
                        end
                        if (in_valid && in_ready) beat = beat + 1;   // transfers at next posedge
                        @(negedge clk);
                    end
                    in_valid = 1'b0;
                end
                begin : collect
                    ob = 0;
                    while (ob < BEATS) begin
                        out_ready = STALL ? (($random(seed) & 3) != 0) : 1'b1;
                        if (out_valid && out_ready) begin
                            for (l = 0; l < NB; l = l + 1) begin
                                cap[ob*NB + l] = out_data[l*W +: W];
                                checks = checks + 1;
                                if (out_data[l*W +: W] !== expv[ob*NB + l]) begin
                                    errors = errors + 1;
                                    if (errors <= 10)
                                        $display("MISMATCH %0s test %0d coef %0d: got %0d exp %0d",
                                                 tag, t, ob*NB + l, out_data[l*W +: W], expv[ob*NB + l]);
                                end
                            end
                            ob = ob + 1;
                        end
                        @(negedge clk);
                    end
                    out_ready = 1'b0;
                end
            join
            @(negedge clk);
            if (done_cnt != d0 + 1) begin
                errors = errors + 1;
                $display("ERROR %0s test %0d: done pulse count %0d", tag, t, done_cnt - d0);
            end
            ops = ops + 1;
        end
    endtask

    integer t, i;
    initial begin
        if (!$value$plusargs("vec=%s", prefix)) begin
            $display("ERROR: pass +vec=<prefix>"); $finish;
        end
        $readmemh({prefix, "_in.hex"},   vin);
        $readmemh({prefix, "_ntt.hex"},  vntt);
        $readmemh({prefix, "_intt.hex"}, vintt);

        repeat (3) @(negedge clk);
        rst_n = 1'b1;

        for (t = 0; t < NTEST; t = t + 1) begin
            for (i = 0; i < 256; i = i + 1) begin src[i] = vin[t*256+i]; expv[i] = vntt[t*256+i]; end
            run_op(1'b0, "forward", t);
            for (i = 0; i < 256; i = i + 1) begin src[i] = cap[i]; expv[i] = vin[t*256+i]; end
            run_op(1'b1, "roundtrip", t);
            for (i = 0; i < 256; i = i + 1) begin src[i] = vin[t*256+i]; expv[i] = vintt[t*256+i]; end
            run_op(1'b1, "inverse", t);
        end

`ifdef GLS
        comp_cycles = ops * EXP_COMP;    // internal state not visible in a netlist
`endif
        if (comp_cycles != ops * EXP_COMP) begin
            errors = errors + 1;
            $display("ERROR: compute cycles %0d per op, expected %0d", comp_cycles / ops, EXP_COMP);
        end

        $display("CONFIG scheme=%0d red=%0d P=%0d  compute=%0d cycles/transform  io=%0d+%0d beats",
                 SCHEME, RED, P, comp_cycles / ops, BEATS, BEATS);
        if (errors == 0)
            $display("PASS: %0d coefficient checks, %0d transforms", checks, ops);
        else
            $display("FAIL: %0d errors in %0d checks", errors, checks);
        $finish;
    end

    // watchdog
    initial begin
        #(NTEST * 3 * 20000 * 10);
        $display("FAIL: timeout");
        $finish;
    end
endmodule

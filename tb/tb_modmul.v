// tb_modmul.v - unit test for ntt_modmul: random + corner operands, streaming one per clock.
//   Barrett    : r == a*b mod q
//   Montgomery : r == a*b*R^-1 mod q   (R = 2^W)
`timescale 1ns/1ps
`include "ntt_defs.vh"
module tb_modmul;
    parameter SCHEME = 0;
    parameter RED    = 0;
    parameter NVEC   = 200000;
`include "ntt_params.vh"
    localparam W = `NTT_W(SCHEME);
    localparam LAT = 3;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  [W-1:0] a, b;
    wire [W-1:0] r;
    ntt_modmul #(.SCHEME(SCHEME), .RED(RED)) dut (.clk (clk), .a (a), .b (b), .r (r));

    reg [63:0] expq [0:LAT];
    integer n, i, errors = 0, checks = 0, seed = 11;
    reg [63:0] ea, eb, prod;

    function [W-1:0] rnd;
        input integer dummy;
        reg [63:0] x;
        begin
            x = {$random(seed), $random(seed)};
            rnd = x % Q;
        end
    endfunction

    initial begin
        for (n = 0; n < NVEC + LAT; n = n + 1) begin
            // operand selection: corners first, then random
            if (n < 9) begin
                ea = (n / 3 == 0) ? 0 : (n / 3 == 1) ? 1 : Q - 1;
                eb = (n % 3 == 0) ? 0 : (n % 3 == 1) ? 1 : Q - 1;
            end else begin
                ea = rnd(0); eb = rnd(0);
            end
            a = ea[W-1:0]; b = eb[W-1:0];
            prod = (ea * eb) % Q;
            if (RED == 1) prod = (prod * MONT_RINV) % Q;
            for (i = LAT; i > 0; i = i - 1) expq[i] = expq[i-1];
            expq[0] = prod;
            @(posedge clk); #1;
            if (n >= LAT - 1) begin
                checks = checks + 1;
                if (r !== expq[LAT-1][W-1:0]) begin
                    errors = errors + 1;
                    if (errors < 10) $display("MISMATCH n=%0d got %0d exp %0d", n, r, expq[LAT-1]);
                end
            end
        end
        if (errors == 0) $display("PASS: modmul scheme=%0d red=%0d, %0d products", SCHEME, RED, checks);
        else             $display("FAIL: modmul %0d errors / %0d", errors, checks);
        $finish;
    end
endmodule

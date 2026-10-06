// ntt_butterfly.v - unified Cooley-Tukey / Gentleman-Sande butterfly, 5-stage pipeline.
//
//   forward (CT) : a' = a + b*w          b' = a - b*w
//   inverse (GS) : a' = (a + b)/2        b' = ((a - b)/2) * w
//
// The /2 in every GS layer folds the final 1/2^layers INTT scaling into the
// butterflies, so no separate scaling pass (or extra multiplier) is needed.
// "/2 mod q" is a shift plus a conditional add of q.
//
// Pipeline (latency 5, one butterfly per clock, no stalls):
//   S1 pre-add/halve  ->  S2..S4 modular multiply  ->  S5 post-add/sub
//
`timescale 1ns/1ps
`include "ntt_defs.vh"
module ntt_butterfly #(
    parameter SCHEME = 0,
    parameter RED    = 0,
    parameter W      = `NTT_W(SCHEME)
) (
    input  wire         clk,
    input  wire         inv,      // 0 = CT (forward), 1 = GS (inverse)
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    input  wire [W-1:0] w,
    output reg  [W-1:0] a_out,
    output reg  [W-1:0] b_out
);
`include "ntt_params.vh"
    localparam [W-1:0] QV = Q;

    // ---------------- modular add / sub / halve (combinational) ----------------
    function [W-1:0] addq(input [W-1:0] x, input [W-1:0] y);
        reg [W:0] s, d;
        begin
            s = x + y;
            d = s - {1'b0, QV};
            addq = d[W] ? s[W-1:0] : d[W-1:0];
        end
    endfunction

    function [W-1:0] subq(input [W-1:0] x, input [W-1:0] y);
        reg [W:0] d;
        begin
            d = {1'b0, x} - {1'b0, y};
            subq = d[W] ? (d[W-1:0] + QV) : d[W-1:0];
        end
    endfunction

    function [W-1:0] halfq(input [W-1:0] x);
        reg [W:0] s;
        begin
            s = x[0] ? ({1'b0, x} + {1'b0, QV}) : {1'b0, x};
            halfq = s[W:1];
        end
    endfunction

    // ---------------- S1: pre-add (GS) or pass-through (CT) ----------------
    reg [W-1:0] x1, y1, w1;
    reg         inv1;
    always @(posedge clk) begin
        x1   <= inv ? halfq(addq(a, b)) : a;
        y1   <= inv ? halfq(subq(a, b)) : b;
        w1   <= w;
        inv1 <= inv;
    end

    // ---------------- S2..S4: modular multiply y1 * w1 ----------------
    wire [W-1:0] prod;
    ntt_modmul #(.SCHEME(SCHEME), .RED(RED), .W(W)) u_mul (
        .clk (clk), .a (y1), .b (w1), .r (prod)
    );

    reg [W-1:0] x2, x3, x4;
    reg         inv2, inv3, inv4;
    always @(posedge clk) begin
        x2 <= x1;   inv2 <= inv1;
        x3 <= x2;   inv3 <= inv2;
        x4 <= x3;   inv4 <= inv3;
    end

    // ---------------- S5: post-add/sub (CT) or pass-through (GS) ----------------
    always @(posedge clk) begin
        a_out <= inv4 ? x4   : addq(x4, prod);
        b_out <= inv4 ? prod : subq(x4, prod);
    end
endmodule

// ntt_top.v - synthesis top. Configuration comes from ntt_cfg.vh, which the flow
// generates per run (flow/scripts/mk_cfg.sh) into the build directory:
//     `define NTT_SCHEME 0    // 0 = kyber, 1 = dilithium
//     `define NTT_RED    0    // 0 = barrett, 1 = montgomery
//     `define NTT_P      2    // butterflies per clock
// Keeping the top-level name fixed makes every Genus/Innovus script config-agnostic.
`timescale 1ns/1ps
`include "ntt_defs.vh"
`include "ntt_cfg.vh"
module ntt_top (
    input  wire                                   clk,
    input  wire                                   rst_n,
    input  wire                                   start,
    input  wire                                   inverse,
    output wire                                   busy,
    output wire                                   done,
    input  wire                                   in_valid,
    output wire                                   in_ready,
    input  wire [2*`NTT_P*`NTT_W(`NTT_SCHEME)-1:0] in_data,
    output wire                                   out_valid,
    input  wire                                   out_ready,
    output wire [2*`NTT_P*`NTT_W(`NTT_SCHEME)-1:0] out_data
);
    ntt_core #(.SCHEME(`NTT_SCHEME), .RED(`NTT_RED), .P(`NTT_P)) u_core (
        .clk (clk), .rst_n (rst_n),
        .start (start), .inverse (inverse), .busy (busy), .done (done),
        .in_valid (in_valid), .in_ready (in_ready), .in_data (in_data),
        .out_valid (out_valid), .out_ready (out_ready), .out_data (out_data)
    );
endmodule

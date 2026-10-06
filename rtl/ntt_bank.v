// ntt_bank.v - one coefficient bank: 1 synchronous read port + 1 write port.
// gpdk045 ships no memory compiler, so banks are flip-flop register files.
// Swap this module for an SRAM macro wrapper when one is available.
`timescale 1ns/1ps
module ntt_bank #(
    parameter W     = 12,
    parameter DEPTH = 128,
    parameter AW    = 7
) (
    input  wire          clk,
    input  wire          re,
    input  wire [AW-1:0] raddr,
    output reg  [W-1:0]  rdata,
    input  wire          we,
    input  wire [AW-1:0] waddr,
    input  wire [W-1:0]  wdata
);
    reg [W-1:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        if (re) rdata <= mem[raddr];
    end
endmodule

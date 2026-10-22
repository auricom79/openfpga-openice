// SPDX-License-Identifier: MIT
// 80 MHz system / 40 MHz PSRAM backend, DDR64 Avalon interface.
// Only power_reset drives reset; game reset preserves loaded ROMs and BCR.
`timescale 1ns/1ps
module wolf_pocket_psram #(parameter integer POWER_CYCLES=12000)(
    input wire clk,reset,
    input wire [28:0] ddram_addr,
    input wire [7:0] ddram_burstcnt,ddram_be,
    input wire ddram_rd,ddram_we,
    input wire [63:0] ddram_din,
    output wire ddram_busy,ddram_dout_ready,fault,
    output wire [63:0] ddram_dout,
    output wire [21:16] cram0_a,cram1_a,
    inout wire [15:0] cram0_dq,cram1_dq,
    input wire cram0_wait,cram1_wait,
    output wire cram0_clk,cram0_adv_n,cram0_cre,cram0_ce0_n,cram0_ce1_n,
    output wire cram0_oe_n,cram0_we_n,cram0_ub_n,cram0_lb_n,
    output wire cram1_clk,cram1_adv_n,cram1_cre,cram1_ce0_n,cram1_ce1_n,
    output wire cram1_oe_n,cram1_we_n,cram1_ub_n,cram1_lb_n
);
    wire mem_req,mem_chip,mem_writing,mem_ready,mem_done,mem_rvalid;
    wire [22:0] mem_address;
    wire [5:0] mem_length;
    wire [15:0] mem_wdata,mem_rdata;
    wire [1:0] mem_be;
    wire [4:0] mem_windex;
    wire [3:0] configured;
    wolf_pocket_memory bridge(.*);
    wolf_pocket_psram40 #(.POWER_CYCLES(POWER_CYCLES)) physical(
        .clk(clk),.reset(reset),.req(mem_req),.chip(mem_chip),.writing(mem_writing),
        .address(mem_address),.length(mem_length),.wdata(mem_wdata),.wbe(mem_be),
        .ready(mem_ready),.done(mem_done),.rvalid(mem_rvalid),.rdata(mem_rdata),
        .windex(mem_windex),.*);
endmodule

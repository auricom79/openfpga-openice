`timescale 1ns/1ps

module wolf_pocket_system (
    input wire clk, power_reset, game_reset, ce_pix,
    input wire [31:0] cont1_key,cont2_key,cont3_key,cont4_key,status,
    input wire load_active,load_valid,
    input wire [1:0] load_index,
    input wire [24:0] load_addr,
    input wire [7:0] load_data,
    output wire load_ready,
    output wire writes_idle,
    output wire fault,
    input wire nvram_busy,nvram_ext_en,nvram_ext_wr,
    input wire [15:0] nvram_ext_addr,
    input wire [7:0] nvram_ext_wdata,
    output wire [7:0] nvram_ext_rdata,
    output wire nvram_cpu_write,
    output wire [7:0] vid_r,vid_g,vid_b,
    output wire hsync,vsync,hblank,vblank,de,
    output wire signed [15:0] audio_l,audio_r,
    output wire [31:0] pc_dbg,
    output wire illegal_dbg,
    inout wire [15:0] SDRAM_DQ,
    output wire [12:0] SDRAM_A,
    output wire [1:0] SDRAM_BA,
    output wire SDRAM_DQML,SDRAM_DQMH,SDRAM_nCS,SDRAM_nRAS,SDRAM_nCAS,SDRAM_nWE,SDRAM_CKE,
    output wire [28:0] ddram_addr,
    output wire [7:0] ddram_burstcnt,ddram_be,
    output wire ddram_rd,ddram_we,
    output wire [63:0] ddram_din,
    input wire ddram_busy,ddram_dout_ready,mem_fault,
    input wire [63:0] ddram_dout
);

    reg [18:0] pixels=0;
    wire running=!power_reset && !game_reset && !load_active;
    always @(posedge clk) if(!running) pixels<=0; else if(ce_pix) pixels<=pixels+1'b1;
    assign load_ready=load_active && !power_reset;
    assign writes_idle=1'b1;
    assign fault=1'b0;
    assign vid_r=8'h19;assign vid_g=8'h72;assign vid_b=8'hc4;
    assign hsync=running && pixels[8:0]>=9'd480;
    assign vsync=running && pixels>=19'd300000 && pixels<19'd300512;
    assign de=running && pixels[8:0]<9'd400 && !vsync;
    assign hblank=!de;assign vblank=vsync;
    assign audio_l=16'h1234;assign audio_r=16'hdcba;
    assign nvram_ext_rdata=0;assign nvram_cpu_write=0;assign pc_dbg=0;assign illegal_dbg=0;
    assign ddram_addr=0;assign ddram_burstcnt=0;assign ddram_be=0;
    assign ddram_rd=0;assign ddram_we=0;assign ddram_din=0;
endmodule

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

    assign ddram_busy=0;assign ddram_dout_ready=0;assign ddram_dout=0;assign fault=0;
endmodule
module wolf_pocket_pll(input wire refclk,output reg clk_sys=0,output reg clk_sdram=0,
    output reg clk_pixel=0,output reg clk_pixel_90=0,output reg locked=0);
    always #6.25 clk_sys=~clk_sys;
    initial begin #8.984;forever #6.25 clk_sdram=~clk_sdram;end
    always #62.5 clk_pixel=~clk_pixel;
    initial begin #31.25;forever #62.5 clk_pixel_90=~clk_pixel_90;end
    initial #200 locked=1;
endmodule
module pin_ddio_clk(input wire datain_h,datain_l,outclock,output wire dataout);
    assign dataout=outclock ? datain_h : datain_l;
endmodule

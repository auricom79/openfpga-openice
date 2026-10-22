// SPDX-License-Identifier: MIT
// Experimental engine subsystem, not an APF core_top or a deployable Pocket core.
// clk must be 80 MHz and ce_pix 8 MHz. The external loader must hold load_active
// across ALL three ROM streams and clock-cross inputs before presenting them here.
// A valid byte is consumed on load_valid && load_ready. Hold it stable until then.
// External DDR64 backend handles physical PSRAM bursts; game reset preserves it.
`default_nettype none
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
    wire [63:0] inputs;
    wolf_pocket_inputs controls(.clk(clk),.reset(power_reset),.cont1_key(cont1_key),
        .cont2_key(cont2_key),.cont3_key(cont3_key),.cont4_key(cont4_key),
        .status(status),.inputs(inputs));
    wire prog_wait,gfx_ack,gfx_idle,dcs_ack,engine_writes_idle;
    reg load_fault=0;
    wire valid_range = load_index==0 ? load_addr<25'h100000 :
                       load_index==1 ? load_addr<25'h1000000 :
                       load_index==2 ? load_addr<25'h400000 :
                                       load_addr==0 && load_data==0;
    always @(posedge clk) begin
        if(power_reset)load_fault<=0;
        else if(load_valid && (!load_active || !valid_range))load_fault<=1;
    end
    assign fault=load_fault|mem_fault;
    wire valid_byte=load_active && load_valid && valid_range && !fault && !power_reset;
    assign load_ready=load_active && valid_range && !fault && !power_reset &&
                      (load_index==0 ? !prog_wait : load_index==1 ? gfx_ack :
                       load_index==2 ? dcs_ack : 1'b1);
    wire [24:0] prog_addr=25'h0c0000+{6'd0,load_addr[18:0]};
    wire [15:0] prog_data=load_addr[19] ? {load_data,8'd0} : {8'd0,load_data};
    wire [1:0] prog_be=load_addr[19] ? 2'b10 : 2'b01;
    wire [24:0] gfx_addr;
    wolf_gfx_interleave interleave(.mk3_layout_i(1'b0),.lin_addr(load_addr),.dest_addr(gfx_addr));
    // Accepted writes can remain buffered after the client's final beat.
    // APF setup may finish only when the common backend is physically idle.
    assign writes_idle=engine_writes_idle && !ddram_busy && !ddram_rd && !ddram_we;
    wolf_top #(.ROM_HEX(""),
        .PIC_RESPONSE_BYTES(128'h0000_4A0E_A018_4580_0614_C3B2_0301_8444),
        .PIC_STATUS_DELAY(1'b0),.WWF_IO_SHUFFLE(1'b0)) engine (
        .clk(clk),.clk_cpu(clk),.ce_pix(ce_pix),.clk_snd(1'b0),
        // gfx_idle also drops during ordinary graphics reads. The loader waits
        // for engine_writes_idle before releasing load_active; using gfx_idle
        // as a runtime reset would restart the CPU on its first cache miss.
        .rst(game_reset|power_reset|load_active|fault),
        .rst_pon(game_reset|power_reset),.sdram_por(power_reset),
        .inputs(inputs),.status(status),.game_profile(3'd0),
        .nvram_busy(nvram_busy),.nvram_ext_en(nvram_ext_en),.nvram_ext_wr(nvram_ext_wr),
        .nvram_ext_addr(nvram_ext_addr),.nvram_ext_wdata(nvram_ext_wdata),
        .nvram_ext_rdata(nvram_ext_rdata),.nvram_cpu_write(nvram_cpu_write),
        .ioctl_download(load_active),.ioctl_wr(valid_byte && load_index==0 && !prog_wait),
        .ioctl_addr(prog_addr),.ioctl_dout(prog_data),.ioctl_be(prog_be),.ioctl_wait(prog_wait),
        .pocket_download_idle(engine_writes_idle),
        .snd_dl_wr(1'b0),.snd_dl_addr(18'd0),.snd_dl_data(8'd0),
        .dcs_dl_active(load_active),.dcs_dl_wr(valid_byte && load_index==2),
        .dcs_dl_addr(load_addr[21:0]),.dcs_dl_data(load_data),.dcs_dl_ack(dcs_ack),
        .gfx_dl_wr(valid_byte && load_index==1),.gfx_dl_addr(gfx_addr),
        .gfx_dl_data(load_data),.gfx_dl_ack(gfx_ack),.gfx_dl_idle(gfx_idle),
        .SDRAM_DQ(SDRAM_DQ),.SDRAM_A(SDRAM_A),.SDRAM_BA(SDRAM_BA),
        .SDRAM_DQML(SDRAM_DQML),.SDRAM_DQMH(SDRAM_DQMH),.SDRAM_nCS(SDRAM_nCS),
        .SDRAM_nRAS(SDRAM_nRAS),.SDRAM_nCAS(SDRAM_nCAS),.SDRAM_nWE(SDRAM_nWE),.SDRAM_CKE(SDRAM_CKE),
        .DDRAM_ADDR(ddram_addr),.DDRAM_BURSTCNT(ddram_burstcnt),.DDRAM_RD(ddram_rd),
        .DDRAM_DIN(ddram_din),.DDRAM_BE(ddram_be),.DDRAM_WE(ddram_we),
        .DDRAM_BUSY(ddram_busy),.DDRAM_DOUT(ddram_dout),.DDRAM_DOUT_READY(ddram_dout_ready),
        .vid_r(vid_r),.vid_g(vid_g),.vid_b(vid_b),.hsync(hsync),.vsync(vsync),
        .hblank(hblank),.vblank(vblank),.de(de),.audio_l(audio_l),.audio_r(audio_r),
        .pc_dbg(pc_dbg),.illegal_dbg(illegal_dbg)
    );
endmodule
`default_nettype wire

// Pocket wrapper derived from the official open-fpga core-template interface.
// Experimental integration; hardware testing on Pocket is still pending.
//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used


assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;



// Only cartridge/link/unused SRAM tie-offs above are inherited from the template.
wire clk_sys,clk_sdram,clk_pixel,clk_pixel_90,pll_locked;
wolf_pocket_pll clocks(.refclk(clk_74a),.clk_sys(clk_sys),.clk_sdram(clk_sdram),
    .clk_pixel(clk_pixel),.clk_pixel_90(clk_pixel_90),.locked(pll_locked));
(* async_reg="true" *) reg [2:0] por_mem=7,por_bridge=7,por_pixel=7;
always @(posedge clk_sys or negedge pll_locked)
    if(!pll_locked) por_mem<=7; else por_mem<={por_mem[1:0],1'b0};
always @(posedge clk_74a or negedge pll_locked)
    if(!pll_locked) por_bridge<=7; else por_bridge<={por_bridge[1:0],1'b0};
always @(posedge clk_pixel or negedge pll_locked)
    if(!pll_locked) por_pixel<=7; else por_pixel<={por_pixel[1:0],1'b0};
wire reset_n,allcomplete,loader_done,loader_fault,engine_fault;
wire [31:0] cmd_data;
wire target_read,target_ack,target_done;
wire [2:0] target_error;
wire [15:0] target_id;
wire [31:0] target_offset,target_address,target_length;
(* async_reg="true" *) reg run_meta=0,run_sync=0,lf_meta=0,lf_sync=0;
(* async_reg="true" *) reg ef_meta=0,ef_sync=0;
always @(posedge clk_sys) begin
    run_meta<=reset_n;run_sync<=run_meta;
    lf_meta<=loader_fault;lf_sync<=lf_meta;
end
always @(posedge clk_74a) begin ef_meta<=engine_fault;ef_sync<=ef_meta;end
always @* begin
    bridge_rd_data=0;
    if(bridge_addr[31:24]==8'hF8) bridge_rd_data=cmd_data;
    else if(bridge_addr==32'h20000000)
        bridge_rd_data={29'd0,ef_sync,loader_fault,loader_done};
end
// APF asks 0082 even before opening a deferred slot. Acknowledge readiness;
// deferload in data.json keeps payload transfer under the chunk loader control.
core_bridge_cmd commands(
    .clk(clk_74a),.reset_n(reset_n),.bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),.bridge_rd(bridge_rd),.bridge_rd_data(cmd_data),
    .bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
    .status_boot_done(!por_bridge[2]),.status_setup_done(!por_bridge[2]),
    .status_running(reset_n && loader_done && !loader_fault && !ef_sync),
    .dataslot_requestread(),.dataslot_requestread_id(),
    .dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b0),
    .dataslot_requestwrite(),.dataslot_requestwrite_id(),.dataslot_requestwrite_size(),
    .dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),
    .dataslot_update(),.dataslot_update_id(),.dataslot_update_size(),
    .dataslot_allcomplete(allcomplete),
    .rtc_epoch_seconds(),.rtc_date_bcd(),.rtc_time_bcd(),.rtc_valid(),
    .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),
    .savestate_maxloadsize(32'd0),.savestate_start(),.savestate_start_ack(1'b0),
    .savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
    .savestate_load(),.savestate_load_ack(1'b0),.savestate_load_busy(1'b0),
    .savestate_load_ok(1'b0),.savestate_load_err(1'b0),.osnotify_inmenu(),
    .target_dataslot_read(target_read),.target_dataslot_write(1'b0),
    .target_dataslot_getfile(1'b0),.target_dataslot_openfile(1'b0),
    .target_dataslot_ack(target_ack),.target_dataslot_done(target_done),
    .target_dataslot_err(target_error),.target_dataslot_id(target_id),
    .target_dataslot_slotoffset(target_offset),.target_dataslot_bridgeaddr(target_address),
    .target_dataslot_length(target_length),.target_buffer_param_struct(32'd0),
    .target_buffer_resp_struct(32'd0),.datatable_addr(10'd0),.datatable_wren(1'b0),
    .datatable_data(32'd0),.datatable_q()
);
wire load_active,load_valid,load_ready,writes_idle;
wire [1:0] load_index;
wire [24:0] load_addr;
wire [7:0] load_data;
wolf_pocket_loader loader(
    .clk_bridge(clk_74a),.reset_bridge(por_bridge[2]),.clk_mem(clk_sys),.reset_mem(por_mem[2]),
    .start(allcomplete),.bridge_wr(bridge_wr),.bridge_addr(bridge_addr),.bridge_wr_data(bridge_wr_data),
    .target_read(target_read),.target_id(target_id),.target_offset(target_offset),
    .target_address(target_address),.target_length(target_length),.target_ack(target_ack),
    .target_done(target_done),.target_error(target_error),.done(loader_done),.fault(loader_fault),
    .load_active(load_active),.load_valid(load_valid),.load_index(load_index),.load_addr(load_addr),
    .load_data(load_data),.load_ready(load_ready),.writes_idle(writes_idle)
);
wire ce_pix;
wolf_pocket_pixel_enable pixel_enable(
    .clk_sys(clk_sys),.clk_pixel(clk_pixel),.ce_pix(ce_pix));
wire [7:0] r,g,b;
wire hs,vs,de;
wire signed [15:0] left,right;
wire [28:0] ddram_addr;
wire [7:0] ddram_burstcnt,ddram_be;
wire [63:0] ddram_din,ddram_dout;
wire ddram_rd,ddram_we,ddram_busy,ddram_dout_ready,mem_fault;
wire game_reset=!run_sync || lf_sync;
wolf_pocket_system system_core(
    .clk(clk_sys),.power_reset(por_mem[2]),.game_reset(game_reset),.ce_pix(ce_pix),
    .cont1_key(cont1_key),.cont2_key(cont2_key),.cont3_key(cont3_key),.cont4_key(cont4_key),
    .status(32'd0),.load_active(load_active),.load_valid(load_valid),.load_index(load_index),
    .load_addr(load_addr),.load_data(load_data),.load_ready(load_ready),.writes_idle(writes_idle),
    .fault(engine_fault),.nvram_busy(1'b0),.nvram_ext_en(1'b0),.nvram_ext_wr(1'b0),
    .nvram_ext_addr(16'd0),.nvram_ext_wdata(8'd0),.nvram_ext_rdata(),.nvram_cpu_write(),
    .vid_r(r),.vid_g(g),.vid_b(b),.hsync(hs),.vsync(vs),.hblank(),.vblank(),.de(de),
    .audio_l(left),.audio_r(right),.pc_dbg(),.illegal_dbg(),
    .SDRAM_DQ(dram_dq),.SDRAM_A(dram_a),.SDRAM_BA(dram_ba),
    .SDRAM_DQML(dram_dqm[0]),.SDRAM_DQMH(dram_dqm[1]),.SDRAM_nCS(),
    .SDRAM_nRAS(dram_ras_n),.SDRAM_nCAS(dram_cas_n),.SDRAM_nWE(dram_we_n),.SDRAM_CKE(dram_cke),
    .ddram_addr(ddram_addr),.ddram_burstcnt(ddram_burstcnt),.ddram_be(ddram_be),
    .ddram_rd(ddram_rd),.ddram_we(ddram_we),.ddram_din(ddram_din),
    .ddram_busy(ddram_busy),.ddram_dout(ddram_dout),.ddram_dout_ready(ddram_dout_ready),.mem_fault(mem_fault)
);
// The Pocket SDRAM has no external CS pin. Donor CS is permanently asserted.
// The donor's sparse 9-column mapping uses half of the mobile SDRAM's 64 MiB.
pin_ddio_clk dram_clock(.datain_h(1'b1),.datain_l(1'b0),.outclock(clk_sdram),.dataout(dram_clk));
wolf_pocket_psram psram_backend(
    .clk(clk_sys),.reset(por_mem[2]),
    .ddram_addr(ddram_addr),.ddram_burstcnt(ddram_burstcnt),.ddram_be(ddram_be),
    .ddram_rd(ddram_rd),.ddram_we(ddram_we),.ddram_din(ddram_din),
    .ddram_busy(ddram_busy),.ddram_dout(ddram_dout),.ddram_dout_ready(ddram_dout_ready),.fault(mem_fault),
    .cram0_a(cram0_a),.cram0_dq(cram0_dq),.cram0_wait(cram0_wait),.cram0_clk(cram0_clk),.cram0_adv_n(cram0_adv_n),.cram0_cre(cram0_cre),.cram0_ce0_n(cram0_ce0_n),.cram0_ce1_n(cram0_ce1_n),.cram0_oe_n(cram0_oe_n),.cram0_we_n(cram0_we_n),.cram0_ub_n(cram0_ub_n),.cram0_lb_n(cram0_lb_n),
    .cram1_a(cram1_a),.cram1_dq(cram1_dq),.cram1_wait(cram1_wait),.cram1_clk(cram1_clk),.cram1_adv_n(cram1_adv_n),.cram1_cre(cram1_cre),.cram1_ce0_n(cram1_ce0_n),.cram1_ce1_n(cram1_ce1_n),.cram1_oe_n(cram1_oe_n),.cram1_we_n(cram1_we_n),.cram1_ub_n(cram1_ub_n),.cram1_lb_n(cram1_lb_n)
);
assign video_rgb_clock=clk_pixel;
assign video_rgb_clock_90=clk_pixel_90;
assign video_skip=0;
wolf_pocket_video video(.clk_pixel(clk_pixel),.reset(por_pixel[2]),
    .r(r),.g(g),.b(b),.hs(hs),.vs(vs),.de(de),.rgb(video_rgb),
    .apf_hs(video_hs),.apf_vs(video_vs),.apf_de(video_de));
wolf_pocket_audio sound(.clk_bridge(clk_74a),.reset_bridge(por_bridge[2]),
    .clk_mem(clk_sys),.reset_mem(por_mem[2]),
    .left(game_reset || load_active ? 16'sd0 : left),
    .right(game_reset || load_active ? 16'sd0 : right),
    .mclk(audio_mclk),.lrck(audio_lrck),.dac(audio_dac));
endmodule
`default_nettype wire

// wolf_video_top.sv — Wolf-unit (UMK3) video subsystem. FORK of yunit_video_top.sv.
//
// Combines wolf_video (VRAM word -> 15-bit palette index -> RGB, 34010-programmed
// raster) with yunit_scanline (double-buffered VRAM line fetch over the SDRAM scan_*
// channel). yunit_scanline transparently serves wolf_video's
// per-pixel 1-clk vram_raddr from the scan channel — this wrapper is the SEAM the
// EMU-TOP plan flags as the primary integration risk (Gate 2).
//
// Deltas vs Y-unit (yunit_video_top):
//   - wolf_video (not yunit_video): 15-bit pal_raddr (NO pen_map6 fold), 400x254 timing.
//   - disp_row0 is the live 34010 DPYADR-derived row. The TMS
//     VSBLNK pulse phase-locks wolf_video; bounded blank-time publication then passes
//     the same committed page to yunit_scanline so scanout and prefetch change together.
//   - scan_addr stays [17:0] for the first flash (SDRAM VRAM path); the display reads
//     rows 0..509 which fit 18 bits. (Widens to [18:0] only in the DDR3 VRAM phase.)
//
// The scanline loader receives the committed row dynamically. This is required for
// DPYSTRT page 256; a static FIRST_ROW=0 splices the old page into the top of a frame.
`timescale 1ns/1ps
`default_nettype none
module wolf_video_top
  import wolf_pkg::*;
#(
  parameter int H_ACT=400, H_FP=5, H_SYNC=43, H_BP=58,
  parameter int V_ACT=254, V_FP=15, V_SYNC=3, V_BP=17,
  parameter logic [11:0] COL_TAP=56,   // DPYTAP<<1 (wolf_video.sv); NCOL must cover [COL_TAP,COL_TAP+H_ACT)
  parameter int NCOL=400,       // entries to prefetch per row (>= visible cols H_ACT)
  parameter int FLIP_SETTLE_CYCLES=128,
  parameter int FLIP_PREFETCH_LINES=4,
  parameter bit USE_TMS_RASTER_SYNC=0,
  // Pocket PSRAM scan reads carry their own write-publication fence. A global
  // busy may instead describe erasing the page the game has just hidden.
  parameter bit WAIT_FOR_RENDER_IDLE=1
)(
  input  logic        clk,
  input  logic        rst,
  input  logic        ce_pix,
  input  logic        raster_vblank_start, // TMS34010 VSBLNK edge; phase-locks hardware scanout
  input  logic [FB_ADDR_W-1:0] disp_row0,   // 34010 DPYADR-derived display base row
  input  logic        wr_busy,              // VRAM write path draining
  input  logic        blit_busy,            // DMA is still producing the page, including write-free gaps
  // palette read (15-bit index -> xRGB1555, to the emu's palette BRAM; 1-clk registered)
  output logic [14:0] pal_raddr,
  input  logic [15:0] pal_rdata,
  // SDRAM scanout read channel (to the arbiter / vram backend)
  output logic        scan_req,
  output logic [18:0] scan_addr,
  input  logic [15:0] scan_data,
  input  logic        scan_ack,
  output logic [FB_ADDR_W-1:0] active_row0_diag,
  output logic publication_pending,
  // video output
  output logic [7:0]  vid_r, vid_g, vid_b,
  output logic        hsync, vsync, hblank, vblank, de,
  output logic        vblank_irq
);
  // wolf_video <-> yunit_scanline per-pixel VRAM read
  logic [FB_ADDR_W-1:0] vram_raddr, active_row0; logic [15:0] vram_rdata;
  logic vblank_i;
  // Retain the donor policy where explicitly required. On Pocket, DPYADR owns
  // page selection: unrelated rendering must not retain the previous front page.
  // The scan backend still orders reads after accepted writes using its fence.
  wire render_busy = WAIT_FOR_RENDER_IDLE &&
                     ((wr_busy === 1'b1) || (blit_busy === 1'b1));
  assign active_row0_diag = active_row0;

  wolf_video #(
    .H_ACT(H_ACT), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
    .V_ACT(V_ACT), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
    .COL_TAP(COL_TAP), .FLIP_SETTLE_CYCLES(FLIP_SETTLE_CYCLES),
    .FLIP_PREFETCH_LINES(FLIP_PREFETCH_LINES), .USE_TMS_RASTER_SYNC(USE_TMS_RASTER_SYNC)
  ) u_video (
    .clk(clk), .rst(rst), .ce_pix(ce_pix), .raster_vblank_start(raster_vblank_start),
    .disp_row0(disp_row0), .wr_busy(render_busy),
    .active_row0(active_row0), .publication_pending(publication_pending), .vram_raddr(vram_raddr), .vram_rdata(vram_rdata),
    .pal_raddr(pal_raddr), .pal_rdata(pal_rdata),
    .vid_r(vid_r), .vid_g(vid_g), .vid_b(vid_b),
    .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank_i), .de(de),
    .vblank_irq(vblank_irq));
  assign vblank = vblank_i;

  yunit_scanline #(
    .FB_ADDR_W(FB_ADDR_W), .NCOL(NCOL), .FIRST_ROW(0), .ROW_ADDR_W(9)
  ) u_scan (
    .clk(clk), .rst(rst), .ce_pix(ce_pix), .vblank(vblank_i),
    // MAME's Wolf scanline callback masks (rowaddr<<9) with 0x3fe00, so the
    // physical VRAM row and the line-buffer tag are both nine bits. This matters
    // for Open Ice page 0: DPYADR=000c transforms to rowaddr=0xfff, whose first
    // displayed physical row is 0x1ff. Passing ten low bits tagged that fetch as
    // 0x3ff while vram_raddr requested 0x1ff, selecting the wrong prefetched row.
    .frame_row0(active_row0[8:0]),
    .vram_raddr(vram_raddr), .vram_rdata(vram_rdata),
    .scan_req(scan_req), .scan_addr(scan_addr), .scan_data(scan_data), .scan_ack(scan_ack));
endmodule
`default_nettype wire

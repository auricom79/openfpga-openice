// yunit_pkg.sv — Williams Y-unit (Smash T.V.) constants: memory map, DMA
// blitter register set, draw modes, palette/video geometry.
//
// Single home for magic numbers. Values
// are cited to docs/HARDWARE-REFERENCE.md and the MAME driver mirrored under
// docs/mame-ref/.
//
// NOTE on address units: the region bases below are the TMS34010 *logical*
// addresses as MAME's midyunit main_map presents them (docs/mame-ref/
// midyunit.cpp:184). birdybro's core drives a bit-address on `mem_addr`; the
// exact logical→bit shift is pinned in Phase 1 when yunit_mem is wired and
// sim-checked against the 34010 boot. Region *decode* keys on the high bits,
// which distinguish the regions regardless of the shift.

`default_nettype none

package yunit_pkg;

  // ---- Main-board memory map (34010 logical, MAME convention) ----------
  localparam logic [31:0] YMAP_VRAM_BASE     = 32'h0000_0000; // 0x00000000-0x001FFFFF  vram_r/w
  localparam logic [31:0] YMAP_RAM_BASE      = 32'h0100_0000; // 0x01000000-0x010FFFFF  main DRAM
  localparam logic [31:0] YMAP_CMOS_BASE     = 32'h0140_0000; // 0x01400000-0x0140FFFF  NVRAM (paged)
  localparam logic [31:0] YMAP_PAL_BASE      = 32'h0180_0000; // 0x01800000-0x0181FFFF  palette
  localparam logic [31:0] YMAP_DMA_BASE      = 32'h01A0_0000; // 0x01A00000-0x01A0009F  blitter regs (mirror +0x80000)
  localparam logic [31:0] YMAP_INPUT_BASE    = 32'h01C0_0000; // 0x01C00000-0x01C0005F  inputs
  localparam logic [31:0] YMAP_PROT_BASE     = 32'h01C0_0060; // 0x01C00060-0x01C0007F  protection_r / cmos_enable_w
  localparam logic [31:0] YMAP_SOUND_BASE    = 32'h01E0_0000; // 0x01E00000-0x01E0001F  cvsd_sound_w
  localparam logic [31:0] YMAP_CTRL_BASE     = 32'h01F0_0000; // 0x01F00000-0x01F0001F  control_w
  localparam logic [31:0] YMAP_GFX_BASE      = 32'h0200_0000; // 0x02000000-0x05FFFFFF  gfx ROM window
  localparam logic [31:0] YMAP_MAINDATA_BASE = 32'hFF80_0000; // 0xFF800000-0xFFFFFFFF  program ROM

  // ---- Control register (control_w) bit fields -------------------------
  // docs/mame-ref/midyunit_v.cpp:190
  localparam int CTRL_CMOS_PAGE_HI = 7;   // bits [7:6] CMOS page (*0x1000)
  localparam int CTRL_CMOS_PAGE_LO = 6;
  localparam int CTRL_VIDEOBANK    = 5;   // VRAM byte-lane select
  localparam int CTRL_AUTOERASE_N  = 4;   // /autoerase enable (active low)
  localparam int CTRL_LED_N        = 2;
  localparam int CTRL_WD_DAT       = 1;   // watchdog data
  localparam int CTRL_WD_CLK       = 0;   // watchdog clock

  // ---- DMA blitter register indices (dma_r/dma_w) ----------------------
  // docs/mame-ref/midyunit_v.cpp:22. Typed [3:0] so they can be compared to
  // a 4-bit reg address without constant part-selects (Icarus portability).
  localparam logic [3:0] DMA_COMMAND  = 4'd0; // bit15 trigger/busy; b5 flipY; b4 flipX; [3:0] mode
  localparam logic [3:0] DMA_ROWBYTES = 4'd1;
  localparam logic [3:0] DMA_OFFSETLO = 4'd2;
  localparam logic [3:0] DMA_OFFSETHI = 4'd3;
  localparam logic [3:0] DMA_XSTART   = 4'd4;
  localparam logic [3:0] DMA_YSTART   = 4'd5;
  localparam logic [3:0] DMA_WIDTH    = 4'd6;
  localparam logic [3:0] DMA_HEIGHT   = 4'd7;
  localparam logic [3:0] DMA_PALETTE  = 4'd8;
  localparam logic [3:0] DMA_COLOR    = 4'd9;
  localparam int         DMA_NREGS    = 16; // register file size (only 0..9 used)

  localparam int DMA_CMD_TRIG_BIT   = 15; // COMMAND bit15
  localparam int DMA_CMD_FLIPY_BIT  = 5;
  localparam int DMA_CMD_FLIPX_BIT  = 4;

  // ---- Frame-buffer geometry -------------------------------------------
  localparam int FB_W       = 512; // columns
  localparam int FB_H       = 512; // rows
  localparam int FB_ADDR_W  = 18;  // 512*512 = 0x40000 words
  localparam int FB_ROWSHIFT= 9;   // row * 512 (dma_draw: ty*512 ; scanline: rowaddr<<9)

  // ---- Palette / pixel depth (Smash T.V. = 6bpp) -----------------------
  // pen_map 6bit (midyunit_v.cpp:86): idx = ((w & 0xC000)>>8) | (w & 0x0F3F)
  localparam logic [15:0] PALETTE_MASK_6BIT = 16'h0FFF; // 4096 entries
  // xRGB-1555: 0 RRRRR GGGGG BBBBB  (paletteram_w, midyunit_v.cpp:247)

  // 6-bit pen map for a 16-bit frame-buffer word → 12-bit palette index.
  // MAME: ((w & 0xC000)>>8) | (w & 0x0F3F)
  //   result[11:8] = w[11:8]; result[7:6] = w[15:14]; result[5:0] = w[5:0]
  function automatic logic [11:0] pen_map6(input logic [15:0] w);
    pen_map6 = {w[11:8], w[15:14], w[5:0]};
  endfunction

  // xRGB-1555 → 8:8:8 (pal5bit replicate: {c,c[4:2]})
  function automatic logic [23:0] rgb555_to_888(input logic [15:0] c);
    logic [4:0] r5, g5, b5;
    begin
      r5 = c[14:10]; g5 = c[9:5]; b5 = c[4:0];
      rgb555_to_888 = {r5, r5[4:2], g5, g5[4:2], b5, b5[4:2]};
    end
  endfunction

endpackage

`default_nettype wire

// wolf_pkg.sv — Midway Wolf-unit (UMK3) constants: memory map, DMA blitter
// register set, palette/video geometry. FORK of yunit_pkg.sv (Williams Y-unit).
//
// UMK3 is the Wolf unit; MAME's midwunit_video_device INHERITS midtunit_video_device.
// The Wolf/T-unit DMA register layout is DIFFERENT from Y-unit's (index 0 is
// DMA_LRSKIP here, DMA_COMMAND here is index 1 — vs Y-unit DMA_COMMAND=0).
//
// Sources (vendored gospel): mame-gospel/midway/midwunit.cpp (main_map :113-127),
// midtunit_v.h (DMA enum :88-108), midtunit_v.cpp (dma_w register_map + trigger).
// Addresses are TMS34010 *logical* addresses as MAME's midwunit main_map presents
// them; region decode keys on the high bits (shift pinned when wolf_mem is wired).

`default_nettype none

package wolf_pkg;

  // ---- Main-board memory map (34010 logical, midwunit.cpp main_map) --------
  localparam logic [31:0] WMAP_VRAM_BASE     = 32'h0000_0000; // 0x00000000-0x003FFFFF  vram_r/w (4MB — 2x Y-unit)
  localparam logic [31:0] WMAP_RAM_BASE      = 32'h0100_0000; // 0x01000000-0x013FFFFF  main DRAM (4MB — m_mainram)
  localparam logic [31:0] WMAP_CMOS_BASE     = 32'h0140_0000; // 0x01400000-0x0145FFFF  NVRAM (FLAT/unpaged — m_nvram)
  localparam logic [31:0] WMAP_CMOSEN_BASE   = 32'h0148_0000; // 0x01480000-0x014FFFFF  cmos_enable_w
  localparam logic [31:0] WMAP_SECURITY_BASE = 32'h0160_0000; // 0x01600000-0x0160001F  security_r/w (midway_serial_pic)
  localparam logic [31:0] WMAP_SOUND_BASE    = 32'h0168_0000; // 0x01680000-0x0168001F  sound_r/w (DCS, not CVSD)
  localparam logic [31:0] WMAP_IO_BASE       = 32'h0180_0000; // 0x01800000-0x0187FFFF  io_r/io_w (inputs, DIPs, WATCHDOG/STATUS — boot poll)
  localparam logic [31:0] WMAP_PAL_BASE      = 32'h0188_0000; // 0x01880000-0x018FFFFF  palette (32768-color, palette_device::write16)
  localparam logic [31:0] WMAP_DMA_BASE      = 32'h01A0_0000; // 0x01A00000-0x01A000FF  blitter regs (mirror +0x80000) — base same as Y-unit
  localparam logic [31:0] WMAP_CTRL_BASE     = 32'h01B0_0000; // 0x01B00000-0x01B0001F  midwunit_control_r/w
  localparam logic [31:0] WMAP_GFX_BASE      = 32'h0200_0000; // 0x02000000-0x06FFFFFF  gfx ROM window (32MB region)
  localparam logic [31:0] WMAP_MAINDATA_BASE = 32'hFF80_0000; // 0xFF800000-0xFFFFFFFF  program ROM

  // ---- Control register (midwunit_control_w @ 0x01B00000) bit fields -------
  // RESOLVED 2026-07-27 — this TODO was STALE and cost an investigation. The body
  // of midwunit_control_w IS vendored: mame-gospel/midway/midtunit_v.cpp:370-385.
  // The bits are PINNED (in wolf_mem.sv:23, not here — no constants needed):
  //   videobank = bit 11   ("(m_midtunit_control >> 11) & 1", :383)
  //   gfxbank   = bits 9:8 ("0x800000 * ((m_midtunit_control >> 8) & 3)", :380)
  // NOTE THE FORK HAZARD, since it is the §4 classic and it IS handled: T-unit's
  // midtunit_control_w uses videobank = bit 5 and gfxbank from bit 7 (:365-366).
  // Wolf is bit 11 / bits 9:8. Do not "correct" wolf_mem back to the donor's bits.
  // There is NO /autoerase bit in midwunit_control_w — that is a Y-unit feature
  // (midyunit_v.cpp); do not go looking for one here.

  // ---- DMA blitter register indices (midtunit_v.h enum :88-108) ------------
  // *** index 0 is DMA_LRSKIP, NOT DMA_COMMAND. *** A blit fires on a write whose
  // register_map[regbank][offset] == DMA_COMMAND(1) with bit-15 set.
  localparam logic [4:0] DMA_LRSKIP   = 5'd0;
  localparam logic [4:0] DMA_COMMAND  = 5'd1;  // bit15 = go/trigger; bpp=[14:12]; b5 yflip; [3:0] mode (0xC = fill)
  localparam logic [4:0] DMA_OFFSETLO = 5'd2;
  localparam logic [4:0] DMA_OFFSETHI = 5'd3;
  localparam logic [4:0] DMA_XSTART   = 5'd4;
  localparam logic [4:0] DMA_YSTART   = 5'd5;
  localparam logic [4:0] DMA_WIDTH    = 5'd6;  // & 0x3ff
  localparam logic [4:0] DMA_HEIGHT   = 5'd7;  // & 0x3ff
  localparam logic [4:0] DMA_PALETTE  = 5'd8;  // & 0x7f00
  localparam logic [4:0] DMA_COLOR    = 5'd9;  // & 0xff
  localparam logic [4:0] DMA_SCALE_X  = 5'd10; // 0 => 0x100 (1.0)
  localparam logic [4:0] DMA_SCALE_Y  = 5'd11;
  localparam logic [4:0] DMA_TOPCLIP  = 5'd12;
  localparam logic [4:0] DMA_BOTCLIP  = 5'd13;
  localparam logic [4:0] DMA_UNKNOWN_E= 5'd14;
  localparam logic [4:0] DMA_CONFIG   = 5'd15; // bit5 selects register bank
  localparam logic [4:0] DMA_LEFTCLIP = 5'd16; // pseudo-register
  localparam logic [4:0] DMA_RIGHTCLIP= 5'd17; // pseudo-register
  localparam int         DMA_NREGS    = 18;

  localparam int DMA_CMD_TRIG_BIT = 15; // COMMAND bit15 = go

  // offset(0..15) -> regnum, per DMA_CONFIG[5]. midtunit_v.cpp dma_w register_map.
  // regbank = (dma_register[DMA_CONFIG] >> 5) & 1. Bank differs only at offset 12/13.
  //   bank0: {0,1,2,3,4,5,6,7,8,9,10,11,16,17,14,15}
  //   bank1: {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15}
  function automatic logic [4:0] dma_regmap(input logic bank, input logic [3:0] off);
    case (off)
      4'd12:   dma_regmap = bank ? DMA_TOPCLIP : DMA_LEFTCLIP;   // 12 -> 12 (bank1) or 16 (bank0)
      4'd13:   dma_regmap = bank ? DMA_BOTCLIP : DMA_RIGHTCLIP;  // 13 -> 13 (bank1) or 17 (bank0)
      default: dma_regmap = {1'b0, off};                          // 0..11, 14, 15 identity
    endcase
  endfunction

  // ---- Frame-buffer geometry (midtunit_v.cpp: m_local_videoram[0x80000], 16bpp,
  //      row stride 512 words: d = &videoram[sy*512]) -------------------------
  localparam int FB_WORDS    = 32'h0008_0000; // 0x80000 16-bit words (~1MB) — 2x Y-unit
  localparam int FB_ADDR_W   = 19;
  localparam int FB_ROWSHIFT = 9;             // row * 512
  // NOTE(wolf_video): visible geometry ~400x254; framebuffer is double-buffered
  // top/bottom. Pin exact visible window + buffer-swap when wolf_video is wired.

  // ---- Palette / pixel depth (Wolf = 32768-color / 15-bit, DIRECT index) ----
  // Framebuffer 16bpp word directly indexes the palette; NO 6-bit pen fold
  // (Y-unit's pen_map6 is dropped). VRAM word = {palette_bank[15:8], gfx_pix[7:0]}
  // written by the blitter (midtunit_v.cpp:265: data | (DMA_PALETTE<<8)).
  localparam int PAL_ENTRIES = 32768;

  // xRGB-1555 -> 8:8:8 (pal5bit replicate) — reused verbatim from Y-unit.
  function automatic logic [23:0] rgb555_to_888(input logic [15:0] c);
    logic [4:0] r5, g5, b5;
    begin
      r5 = c[14:10]; g5 = c[9:5]; b5 = c[4:0];
      rgb555_to_888 = {r5, r5[4:2], g5, g5[4:2], b5, b5[4:2]};
    end
  endfunction

  // gfx bits-per-pixel for a blit = (command >> 12) & 7 (measured 4-6; treat 0 as 8).
  function automatic logic [3:0] dma_bpp(input logic [15:0] command);
    logic [2:0] b;
    begin
      b = command[14:12];
      dma_bpp = (b == 3'd0) ? 4'd8 : {1'b0, b};
    end
  endfunction

endpackage

`default_nettype wire

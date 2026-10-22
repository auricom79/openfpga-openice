// wolf_video.sv — Midway Wolf-unit (UMK3 / T-unit) video scanout: frame buffer
// -> palette -> RGB888. FORK of yunit/yunit_video.sv.
//
// Gospel (vendored MAME, cited file:line):
//   Pixel/scanout — midway/midtunit_v.cpp scanline_update :846-855
//     src = &m_local_videoram[(params->rowaddr << 9) & 0x3fe00];
//     int coladdr = params->coladdr << 1;
//     for (x = heblnk; x < hsblnk; x++) dest[x] = src[coladdr++ & 0x1ff] & 0x7fff;
//   The IND16 dest holds the 15-bit PALETTE INDEX (& 0x7fff). palette->RGB is
//   done by the palette device at output.
//   Palette — midway/midwunit.cpp:643 : PALETTE(... xRGB_555 ...) 32768 entries;
//     :122-ish palette_device::write16, standard MAME xRGB-1555. Conversion =
//     pal5bit replicate (R={c[14:10],c[14:12]} etc.), done here by
//     wolf_pkg::rgb555_to_888.
//
// *** THE WOLF DELTA vs Y-unit *** (measured 2026-07-06, see wolf_video header
// in project notes): the framebuffer 16-bit word DIRECTLY indexes the 32768-entry
// palette as a 15-bit index — there is NO 6-bit pen fold (Y-unit's pen_map6 is
// DROPPED). So pal_raddr = vram_rdata[14:0] (widened 12->15 bits). Everything
// else in the scanout pixel/palette pipeline is IDENTICAL to Y-unit:
//   vram_raddr = (rowaddr<<9)&0x3fe00 + (x & 0x1ff)   (512-col wrap)
//   with rowaddr = base_row + scanline (the 34010's +1/line DPYADR progression).
//
// Raster ownership: on the Wolf unit the TMS34010 OWNS the display timing (MAME
// registers TMS340X0_SCANLINE_IND16_CB with the 34010; midwunit.cpp:647
// set_raw(8_MHz, 506,101,501,289,20,274) "from TMS340 registers"). Unlike Smash
// T.V. (external timing), the geometry here is the programmed 34010 regs. This
// block owns the free-running raster (H/V counters) to that geometry and takes
// the per-frame display base as an INPUT so the game's DOUBLE-BUFFER swap
// (DPYSTRT 0xFFFC<->0xEFFC => base row 0<->256, ~54 swaps/s) drives it.
//
// Two external-register read stages (vram_rdata, pal_rdata) + one output reg =
// 3 pipeline stages; de/sync are delayed by 3 to stay aligned with the color.

`default_nettype none

module wolf_video
  import wolf_pkg::*;
#(
  // Timing = MAME 0.280 midwunit set_raw (midwunit.cpp:647): pixclock 8 MHz, htotal 506,
  // hbend(heblnk) 101, hbstart(hsblnk) 501, vtotal 289, vbend(veblnk) 20, vbstart(vsblnk) 274.
  //   => active 400x254; refresh 8e6/(506*289) = 54.707 Hz.
  // FP/SYNC/BP CORRECTED from the actual T-unit CRTC register program (NBA Hangtime
  // SRC/MAIN.ASM:1122-1130, same Wolf/T-unit GSP hardware family as UMK3): HESYNC=02Bh=43,
  // HEBLNK=HEBLNKINIT=65h=101, HSBLNK=1F5h=501, HTOTAL=1F9h+1=506; VESYNC=3, VEBLNK=20,
  // VSBLNK=274, VTOTAL=288+1=289. Per tms34010.cpp get_display_params/SMART_IOREG, one
  // line/frame is regions [0,HESYNC)=SYNC, [HESYNC,HEBLNK)=BACK PORCH, [HEBLNK,HSBLNK)=ACTIVE,
  // [HSBLNK,HTOTAL+1)=FRONT PORCH (wrap). Rotated to this module's ACTIVE-first hc=0 framing:
  //   H_FP = HTOTAL(506)-HSBLNK(501) = 5;  H_SYNC = HESYNC-0 = 43;  H_BP = HEBLNK-HESYNC = 58.
  //   V_FP = VTOTAL(289)-VSBLNK(274) = 15; V_SYNC = VESYNC-0 = 3;   V_BP = VEBLNK-VESYNC = 17.
  // A prior version guessed BP=0 (assumed sync wraps directly to active-start, i.e. HEBLNK==
  // HESYNC) — false: HEBLNK-HESYNC=58, a real 58-cycle back porch the old split dropped
  // entirely, likely the cause of the right-edge clip seen on cab (mistimed hsync leaves the
  // downstream scaler no settle margin before active, and 48 (wrong FP) vs 5 (true FP) pushes
  // sync tens of cycles later in the line than the real raster).
  parameter int H_ACT  = 400,   // visible pixels (HSBLNK-HEBLNK = 501-101); VRAM 512 cols, 0..399 shown
  parameter int H_FP   = 5,
  parameter int H_SYNC = 43,
  parameter int H_BP   = 58,
  parameter int V_ACT  = 254,   // visible lines (VSBLNK-VEBLNK = 274-20)
  parameter int V_FP   = 15,
  parameter int V_SYNC = 3,
  parameter int V_BP   = 17,
  parameter logic [11:0] COL_TAP = 56,   // DPYTAP=28 (MAIN.ASM:1150) << 1; a real module param (not
                                 // buried in a localparam) so callers can size their VRAM
                                 // prefetch window to cover [COL_TAP, COL_TAP+H_ACT) instead
                                 // of silently under-fetching (see wolf_top.sv NCOL).
  parameter int FLIP_SETTLE_CYCLES = 128,
  parameter int FLIP_PREFETCH_LINES = 4,
  parameter bit USE_TMS_RASTER_SYNC = 0
)(
  input  logic        clk,
  input  logic        rst,
  input  logic        ce_pix,       // pixel-clock enable
  input  logic        raster_vblank_start, // exact TMS34010 edge entering VSBLNK

  // Per-frame display base row derived from the live 34010 DPYADR. The
  // integration point computes base = (DPYADR ^ 0xfffc) >> 4 (get_display_params,
  // tms34010.cpp:1150-1152; DPYCTL bit10=0 so the XOR is active). UMK3 uses 0/256;
  // Open Ice uses 0xfff/0x0fd before the physical row mask. Latched at the game's
  // in-vblank DPYADR override selects the page for the coming active frame.
  input  logic [FB_ADDR_W-1:0] disp_row0,
  input  logic                 wr_busy,   // VRAM write path draining -> gate the flip (commit-timing)

  // Frame-buffer read (registered, 1-clk latency): word address -> videoram word.
  output logic                 publication_pending, // new producers must preserve the old front page
  output logic [FB_ADDR_W-1:0] active_row0, // page actually committed for scanout/prefetch
  output logic [FB_ADDR_W-1:0] vram_raddr,
  input  logic [15:0]          vram_rdata,
  // Palette read (registered, 1-clk latency): 15-bit index -> xRGB1555.
  output logic [14:0]          pal_raddr,
  input  logic [15:0]          pal_rdata,

  // Video output (aligned with the 3-stage pipeline).
  output logic [7:0]  vid_r, vid_g, vid_b,
  output logic        hsync, vsync,
  output logic        hblank, vblank,
  output logic        de,
  output logic        vblank_irq    // 1-clk pulse at start of vertical blank
);

  localparam int H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
  localparam int V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;

  // ---- raster counters (stage 0) ---------------------------------------
  logic [11:0] hc, vc;
  logic        s0_de, s0_hs, s0_vs, s0_hb, s0_vb;
  logic [11:0] s0_x, s0_y;

  // Per-frame display base. In hardware the TMS34010 pulse phase-locks this raster to the
  // same VSBLNK edge that loads DPYADR from DPYSTRT. Without that lock, the game can publish
  // the next page against one raster while this block samples it against another and display
  // the page while its large blit rectangles are still being painted.
  localparam [7:0] FLIP_SETTLE = FLIP_SETTLE_CYCLES[7:0]; // ~16us at default; < one hardware line
  localparam int FLIP_COMMIT_LIMIT = V_TOTAL - FLIP_PREFETCH_LINES;
  logic [FB_ADDR_W-1:0] base_row, disp_row0_pend;
  logic        flip_armed;
  logic        flip_wait_drain;
  logic        tms_blank_window;
  logic [7:0]  flip_settle;
  wire wr_busy_i = (wr_busy === 1'b1);
  wire raster_sync_i = USE_TMS_RASTER_SYNC && (raster_vblank_start === 1'b1);
  wire local_frame_start = !USE_TMS_RASTER_SYNC && (hc == H_TOTAL-1) && (vc == V_ACT-1);
  wire frame_start = raster_sync_i || local_frame_start;
  assign active_row0 = base_row;
  // Physical row identity is nine bits. Include a newly observed request before
  // the next pixel tick so a CPU producer cannot slip through that sampling gap.
  assign publication_pending =
      (flip_armed && (disp_row0_pend[8:0] != base_row[8:0])) ||
      (USE_TMS_RASTER_SYNC && (tms_blank_window || raster_sync_i) &&
       (disp_row0[8:0] != base_row[8:0]));

  always_ff @(posedge clk) begin
    if (rst) begin
      hc <= '0; vc <= '0; vblank_irq <= 1'b0; base_row <= '0;
      disp_row0_pend <= '0; flip_armed <= 1'b0; flip_wait_drain <= 1'b0;
      flip_settle <= FLIP_SETTLE; tms_blank_window <= 1'b0;
    end else begin
      // A serialized producer can retire and accept the next GO on adjacent
      // SYS edges. Remember that drain even if it occurs between pixel ticks.
      // Once observed for this armed page, later work on the newly hidden
      // page must not restart the drain wait. Page re-arming below wins.
      if (flip_armed && flip_wait_drain && !wr_busy_i) begin
        flip_wait_drain <= 1'b0;
        flip_settle <= FLIP_SETTLE;
      end
      if (ce_pix) begin
      vblank_irq <= 1'b0;
      if (raster_sync_i) begin
        // TMS HCOUNT=0 is the start of sync. This module rotates the raster to
        // ACTIVE-first coordinates, so the equivalent point is H_ACT+H_FP.
        // VCOUNT has just entered VSBLNK; the vertical coordinate advances to
        // V_ACT when the horizontal back porch reaches the next active start.
        hc <= H_ACT + H_FP;
        vc <= V_ACT - 1;
        tms_blank_window <= 1'b1;
      end else if (hc == H_TOTAL-1) begin
        hc <= '0;
        if (vc == V_TOTAL-1) begin
          vc <= '0;
          tms_blank_window <= 1'b0;
        end
        else vc <= vc + 12'd1;
      end else hc <= hc + 12'd1;

      if (frame_start) begin
        vblank_irq      <= 1'b1;
        disp_row0_pend  <= disp_row0;
        flip_armed      <= 1'b1;
        flip_wait_drain <= wr_busy_i;
        flip_settle     <= FLIP_SETTLE;
      end else if (USE_TMS_RASTER_SYNC && tms_blank_window &&
                   (disp_row0 != disp_row0_pend)) begin
        // Wolf software writes DPYADR during the display interrupt to override
        // the automatic DPYSTRT load for this frame. Follow that page change
        // inside blanking, then require it to remain stable for the posting delay.
        disp_row0_pend  <= disp_row0;
        flip_armed      <= 1'b1;
        flip_wait_drain <= wr_busy_i;
        flip_settle     <= FLIP_SETTLE;
      end else if (flip_armed) begin
        // Wait for writes already outstanding at the page boundary. Once that
        // drain edge arrives, the settle is one-shot: later writes belong to
        // the newly hidden page and must not postpone this flip a whole frame.
        if (flip_wait_drain) begin
          if (!wr_busy_i) begin
            flip_wait_drain <= 1'b0;
            flip_settle <= FLIP_SETTLE;
          end
        end else if (flip_settle != 8'd0) begin
          flip_settle <= flip_settle - 8'd1;
        end else if (s0_vb && (vc < FLIP_COMMIT_LIMIT)) begin
          // Reserve the final blank lines for both scan buffers to prefetch,
          // while allowing a harmless first-line miss to recover this frame.
          base_row <= disp_row0_pend;
          flip_armed <= 1'b0;
        end
      end
      end
    end
  end

  // active-region flags + pixel (x,y) at stage 0
  always_comb begin
    s0_x  = hc;
    s0_y  = vc;
    s0_de = (hc < H_ACT) && (vc < V_ACT);
    s0_hb = (hc >= H_ACT);
    s0_vb = (vc >= V_ACT);
    // sync sits after the front porch
    s0_hs = (hc >= H_ACT + H_FP) && (hc < H_ACT + H_FP + H_SYNC);
    s0_vs = (vc >= V_ACT + V_FP) && (vc < V_ACT + V_FP + V_SYNC);
  end

  // frame-buffer address: ((rowaddr<<9) & 0x3fe00) + ((x + coltap) & 0x1ff).
  // This is exactly midtunit_v.cpp:848 src = &videoram[(rowaddr<<9)&0x3fe00] with
  // rowaddr = base_row + scanline (the measured +1-per-line DPYADR progression)
  // and the src[coladdr++ & 0x1ff] 512-col wrap (:854), coladdr STARTING at
  // params->coladdr<<1 (tms34010.cpp:1153 get_display_params), NOT 0. FB_ROWSHIFT=9.
  // COL_TAP: params->coladdr = ((dpyadr&0x7c)<<4) | (DPYTAP&0x3fff); the DPYTAP term is
  // a fixed boot-time GSP register (NBA Hangtime SRC/MAIN.ASM:1150, same T-unit gspioinit_t
  // table as the CRTC regs, WRITE-ONCE, never reprogrammed elsewhere in that source) =
  // 28 -> coladdr contribution 28<<1 = 56 = exactly (512-400)/2, i.e. the visible 400-wide
  // window is CENTERED in the 512-col VRAM, not left-aligned at column 0. Dropping this
  // (assumed column 0 = first visible pixel) reads the wrong 400-col sub-window: content
  // meant for the true window's right side falls outside ours and is lost — the observed
  // cab right-edge text clip. (The dpyadr&0x7c term is display-cycle-dependent — omitted
  // here as a simplification; DPYTAP dominates. Revisit only if a smaller residual
  // horizontal jitter remains after this fix.)
  // The & 0x3fe00 mask is transcribed VERBATIM from :848 — it drops rowaddr bits
  // >= 9 (rowaddr >= 0x200), so the row base wraps within the first 0x3fe00 words
  // of videoram. It is a no-op for UMK3's normal 0/256 bases but is required for
  // Open Ice's page-0 rowaddr=0xfff (physical row 511). The line-prefetch wrapper
  // must use the same nine-bit physical-row identity.
  assign vram_raddr = FB_ADDR_W'((((base_row + s0_y) << FB_ROWSHIFT) & 32'h3fe00)
                                 + ((s0_x + COL_TAP) & 12'h1ff));

  // Three register stages from s0: vram_rdata (external BRAM), pal_rdata
  // (external BRAM), and the vid_* output register. Delay control signals by 3.
  logic s1_de,s1_hs,s1_vs,s1_hb,s1_vb;
  logic s2_de,s2_hs,s2_vs,s2_hb,s2_vb;
  always_ff @(posedge clk) begin
    if (rst) begin
      s1_de<=0;s1_hs<=0;s1_vs<=0;s1_hb<=0;s1_vb<=0;
      s2_de<=0;s2_hs<=0;s2_vs<=0;s2_hb<=0;s2_vb<=0;
    end else if (ce_pix) begin
      s1_de<=s0_de; s1_hs<=s0_hs; s1_vs<=s0_vs; s1_hb<=s0_hb; s1_vb<=s0_vb;
      s2_de<=s1_de; s2_hs<=s1_hs; s2_vs<=s1_vs; s2_hb<=s1_hb; s2_vb<=s1_vb;
    end
  end

  // WOLF DELTA: the VRAM word IS the 15-bit palette index (midtunit_v.cpp:854
  // dest = src[...] & 0x7fff). No pen_map6 fold. Widened pal_raddr 12 -> 15 bits.
  assign pal_raddr = vram_rdata[14:0];              // stage: direct index (comb)

  logic [23:0] rgb;
  assign rgb = rgb555_to_888(pal_rdata);            // stage: xRGB1555 -> 888 (comb)

  // ---- final output register (aligned with s2_*) -----------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      de<=0; hsync<=0; vsync<=0; hblank<=0; vblank<=0;
      vid_r<=0; vid_g<=0; vid_b<=0;
    end else if (ce_pix) begin
      de<=s2_de; hsync<=s2_hs; vsync<=s2_vs; hblank<=s2_hb; vblank<=s2_vb;
      vid_r <= s2_de ? rgb[23:16] : 8'h00;
      vid_g <= s2_de ? rgb[15:8]  : 8'h00;
      vid_b <= s2_de ? rgb[7:0]   : 8'h00;
    end
  end

endmodule

`default_nettype wire

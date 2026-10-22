// -----------------------------------------------------------------------------
// tms34010_video.sv
//
// Video timing generator for the TMS34010 (1988 User's Guide §"Video Timing",
// the HESYNC/HEBLNK/HSBLNK/HTOTAL and V* registers). Free-running horizontal
// and vertical counters, advanced at the DOT rate by the `ce` enable, produce
// HSYNC/VSYNC and the blanking signal, plus a display-interrupt strobe.
//
//   HCOUNT increments once per `ce` (dot-clock enable) tick; when HCOUNT ==
//   HTOTAL it wraps to 0 and the horizontal sync interval restarts. On each
//   HCOUNT wrap, VCOUNT increments; when VCOUNT == VTOTAL it wraps to 0 (a new
//   frame). Because `ce` is the pixel-clock enable, HCOUNT runs at the dot rate,
//   VCOUNT at the line rate, and DPYINT_PULSE fires once per FRAME -- exactly as
//   the real CRTC and MAME (midwunit PIXEL_CLOCK = 8 MHz).
//
//   HSYNC is asserted while HCOUNT < HESYNC (the sync interval that begins at
//   the HTOTAL wrap). HBLANK is asserted while HCOUNT < HEBLNK (the leading
//   blank, including the sync interval) or HCOUNT >= HSBLNK (the trailing
//   blank); the visible region is HEBLNK..HSBLNK. The vertical signals are the
//   analogous compares on VCOUNT. BLANK is asserted when either axis is
//   blanking. DPYINT_PULSE is a one-clock strobe at the start of the scan line
//   whose number equals DPYINT (the display-interrupt line).
//
// Scope (Task 0097 — standalone; P00xx — dot-clock `ce` gating): a clean,
// synthesizable timing block. The spec resets HCOUNT on the VCLK FALLING edge;
// this synchronous design uses the rising edge throughout (assumption A0003
// reset/clock style) and advances on the `ce` enable instead of a raw VCLK.
//
// Spec source:
//   third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf
//   §"Video Timing"; HESYNC page 5-?, HEBLNK page 5-?.
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_video
  import tms34010_pkg::*;
(
  input  wire logic        clk,        // core clock (clk_sys). Counters advance on `ce`, NOT every clk.
  input  wire logic        rst,
  // Pixel-clock ENABLE. Real HW clocks these counters at VCLK (the dot clock);
  // here `clk` is the fast core clock and `ce` is a 1-clk-wide enable at the dot
  // rate (Arcade-SmashTV.sv: 96 MHz / 12 = 8 MHz = midwunit PIXEL_CLOCK). Gating
  // every counter on `ce` makes HCOUNT tick per DOT, VCOUNT per LINE, and
  // DPYINT_PULSE once per FRAME at the DPYINT line -- matching the TMS34010 CRTC
  // that MAME models. Without it (the fork-inherited bug) DPYINT fired at the
  // core clock = ~12x too fast, derailing NBA/UMK3 init before the RAM
  // interrupt-dispatch table is built. An UNCONNECTED `ce` (legacy unit TBs that
  // do not drive it) defaults HIGH = full-rate = the original behavior, so those
  // TBs are unaffected; the `=== 1'b0` guard collapses to plain equality in
  // synthesis (the real path always drives ce 0/1). Same pattern as `lint1_in`.
  input  wire logic        ce,

  // Horizontal timing registers.
  input  wire logic [15:0] hesync,     // end of horizontal sync
  input  wire logic [15:0] heblnk,     // end of horizontal blank (display starts)
  input  wire logic [15:0] hsblnk,     // start of horizontal blank
  input  wire logic [15:0] htotal,     // total - 1 line length (HCOUNT wrap)
  // Vertical timing registers.
  input  wire logic [15:0] vesync,     // end of vertical sync
  input  wire logic [15:0] veblnk,     // end of vertical blank
  input  wire logic [15:0] vsblnk,     // start of vertical blank
  input  wire logic [15:0] vtotal,     // total - frame length (VCOUNT wrap)
  // Display-interrupt scan line.
  input  wire logic [15:0] dpyint,

  output logic [15:0] hcount,
  output logic [15:0] vcount,
  output logic        hsync,      // 1 = within the horizontal sync interval
  output logic        vsync,      // 1 = within the vertical sync interval
  output logic        hblank,     // 1 = horizontal blanking
  output logic        vblank,     // 1 = vertical blanking
  output logic        blank,      // 1 = blanked (either axis)
  output logic        dpyint_pulse,// one-clock strobe at the DPYINT scan line start
  output logic        vblank_start // one-clock strobe on the edge entering VSBLNK
);

  // Bound each equality group to six inputs, then reduce six matches in
  // parallel. This preserves all 16-bit programmable line lengths without
  // serially folding another equality group into an intermediate reduction.
  (* keep *) wire [5:0] hwrap_group_match;
  for (genvar h = 0; h < 5; h = h + 1) begin : hwrap_compare_group
    assign hwrap_group_match[h] = (hcount[3*h +: 3] == htotal[3*h +: 3]);
  end
  assign hwrap_group_match[5] = (hcount[15] == htotal[15]);
  (* keep *) wire hwrap = &hwrap_group_match;

  // Compare both possible next-line values in parallel. VTOTAL then selects
  // one Boolean result instead of selecting 16 bits before another compare.
  // This preserves the exact raster/DPYADR edge, including 16-bit wraparound.
  logic vwrap;
  logic next_line_matches;
  assign vwrap = (vcount == vtotal);
  // Increment-and-compare per nibble. A carry enters a nibble precisely
  // when all lower counter bits are one. Both equality results are formed
  // in parallel, so no sixteen-bit carry chain precedes the comparison.
  wire [3:0] increment_carry = {&vcount[11:0], &vcount[7:0], &vcount[3:0], 1'b1};
  (* keep *) wire [3:0] increment_nibble_match;
  for (genvar n = 0; n < 4; n = n + 1) begin : increment_compare_nibble
    wire equal_same = (vcount[4*n +: 4] == vsblnk[4*n +: 4]);
    wire equal_next = ((vcount[4*n +: 4] + 4'd1) == vsblnk[4*n +: 4]);
    assign increment_nibble_match[n] = increment_carry[n] ? equal_next : equal_same;
  end
  (* keep *) wire increment_matches = &increment_nibble_match;
  assign next_line_matches = vwrap ? (vsblnk == 16'd0) : increment_matches;

  // Dot-clock enable. Unconnected `ce` (legacy TBs) -> HIGH (full rate); a driven
  // `ce` passes straight through. Synthesis sees `== 1'b0` (z/x cannot exist).
  logic ce_eff;
  assign ce_eff = (ce === 1'b0) ? 1'b0 : 1'b1;

  always_ff @(posedge clk) begin
    if (rst) begin
      hcount <= 16'd0;
      vcount <= 16'd0;
    end else if (ce_eff) begin
      if (hwrap) begin
        hcount <= 16'd0;
        if (vcount == vtotal) begin
          vcount <= 16'd0;
        end else begin
          vcount <= vcount + 16'd1;
        end
      end else begin
        hcount <= hcount + 16'd1;
      end
    end
  end

  // Sync / blank window compares (combinational).
  assign hsync  = (hcount < hesync);
  assign vsync  = (vcount < vesync);
  assign hblank = (hcount < heblnk) || (hcount >= hsblnk);
  assign vblank = (vcount < veblnk) || (vcount >= vsblnk);
  assign blank  = hblank || vblank;

  // Display interrupt: a ONE-clock strobe at the start of the scan line whose
  // number equals DPYINT. HCOUNT==0 now dwells for (clk/ce) cycles per line, so
  // it is ALSO gated on ce_eff -> high for exactly one clk on the ce-tick that
  // holds HCOUNT==0 at VCOUNT==DPYINT, i.e. once per frame. (At full rate ce_eff
  // is constant 1 and HCOUNT==0 lasts one clk, reproducing the original strobe.)
  assign dpyint_pulse = ce_eff && (hcount == 16'd0) && (vcount == dpyint);

  // The 34010 loads DPYADR from DPYSTRT at the start of VSBLNK. Export the
  // exact counter edge so external scanout shares that frame boundary.
  // Keep the raster-only condition independent of the half-cycle pixel CE.
  // The final gate then contains only CE and one precomputed predicate.
  (* keep *) wire vblank_edge_ready = hwrap && (htotal != 16'd0)
                      && (vtotal != 16'd0) && next_line_matches;
  assign vblank_start = ce_eff && vblank_edge_ready;

endmodule : tms34010_video

`default_nettype wire

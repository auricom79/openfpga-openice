// wolf_diag_geom_overlay.sv — GEOMETRY INSTRUMENT (+define+DIAG_GEOM): screen-as-ruler.
//
// PURPOSE (Rampage WT "squished screen" localization): every digital video input to this
// core is proven byte-identical to the cab-proven UMK3 (7 measurements + a live MAME CRTC
// trace: rmpgwt programs the SAME 400px active / HTOTAL=506 raster as umk3). So the horizontal
// compression is NOT in any readable code path. This overlay MEASURES the actual signal on the
// cab to split the last fork the static proofs cannot:
//   A) the FPGA's active window / timing is wrong        -> the ruler grid itself looks compressed
//   B) the content the CPU/blitter painted is narrow     -> grid spans full width, game text does not
//   C) downstream MiSTer scaler / HDMI / display aspect  -> grid full-width & even, but whole frame squished
//
// It draws, composited OVER the live game (so you still see the boot/DCS screen):
//   * a full-active-width GRATICULE: white vertical line every 50 active pixels, grey horizontal
//     line every 32 active lines, RED line at active column 0 (left edge). Evenly-spaced ticks
//     across the WHOLE screen = the FPGA active window is correct; ticks bunched narrow = the
//     compression is in the output timing/scale, not the game.
//   * a top-left HEX PANEL of the per-frame MEASURED geometry (3 hex digits each):
//       row0 YELLOW  AW  = active width  (count of DE high per line)   expect 190 (=400)
//       row1 CYAN    HB  = !HBlank width (count of HBlank low)         expect == AW (else DE/HBlank disagree)
//       row2 GREEN   LT  = line total    (ce_pix between HSync edges)  expect 1FA (=506)
//       row3 ORANGE  CMN = min non-black active column this frame      content LEFT edge
//       row4 MAGENTA CMX = max non-black active column this frame      content RIGHT edge
//       row5 WHITE   AH  = active height (lines with DE high)          expect  FE (=254)
//   Read CMN/CMX vs AW: if [CMN,CMX] spans ~0..190 the content is full-width (=> case A/C, output/scaler);
//   if it sits in a narrow sub-range (e.g. 0..0C8) the BLITTER painted it compressed (=> case B, content).
//
// Self-contained: derives everything from the game raster (de/hblank/vblank/hsync + RGB). No core
// debug taps, no wolf_top plumbing. Mutually exclusive with DIAG_BOOT (both drive the ov_* bus).
`default_nettype none
module wolf_diag_geom_overlay (
  input  logic        clk, ce_pix, rst,
  input  logic [7:0]  g_r, g_g, g_b,
  input  logic        g_hs, g_vs, g_hb, g_vb, g_de,
  output logic [7:0]  vid_r, vid_g, vid_b,
  output logic        hsync, vsync, hblank, vblank, de
);
  // ---- 3x5 hex font (shared shape with smashtv_diag2_overlay) ----------------
  function automatic [14:0] glyph(input [3:0] v);
    case (v)
      4'h0: glyph=15'b111_101_101_101_111;  4'h1: glyph=15'b010_110_010_010_111;
      4'h2: glyph=15'b111_001_111_100_111;  4'h3: glyph=15'b111_001_111_001_111;
      4'h4: glyph=15'b101_101_111_001_001;  4'h5: glyph=15'b111_100_111_001_111;
      4'h6: glyph=15'b111_100_111_101_111;  4'h7: glyph=15'b111_001_001_010_010;
      4'h8: glyph=15'b111_101_111_101_111;  4'h9: glyph=15'b111_101_111_001_111;
      4'hA: glyph=15'b111_101_111_101_101;  4'hB: glyph=15'b110_101_110_101_110;
      4'hC: glyph=15'b111_100_100_100_111;  4'hD: glyph=15'b110_101_101_101_110;
      4'hE: glyph=15'b111_100_111_100_111;  default: glyph=15'b111_100_111_100_100; // F
    endcase
  endfunction
  function automatic logic fpix(input [3:0] d, input [1:0] col, input [2:0] row);
    logic [14:0] g; logic [2:0] rb; g=glyph(d);
    case (row) 3'd0:rb=g[14:12]; 3'd1:rb=g[11:9]; 3'd2:rb=g[8:6]; 3'd3:rb=g[5:3]; default:rb=g[2:0]; endcase
    fpix = (col==2'd0)?rb[2] : (col==2'd1)?rb[1] : rb[0];
  endfunction

  // ---- active-space raster tracking (gx = active col, gy = active line) ------
  logic [11:0] gx, gy;
  logic de_q, vb_q, hs_q;
  // per-line counters (reset at HSync rising)
  logic [11:0] de_cnt, hb_cnt, line_pix; logic saw_de;
  // per-line holders (the last active line of the frame is representative)
  logic [11:0] awidth_ln, hblow_ln, ltotal_ln;
  // per-frame counters
  logic [11:0] frame_lines, deh_lines, cmin_acc, cmax_acc;
  // stable per-frame latched measurements (what the panel shows)
  logic [11:0] m_awidth, m_hbcnt, m_ltotal, m_cmin, m_cmax, m_aheight;
  // graticule counters
  logic [5:0]  grat_x;   // 0..49  -> vertical tick every 50 active px
  logic [5:0]  grat_y;   // 0..31  -> horizontal tick every 32 active lines

  wire nonblack = |{g_r, g_g, g_b};
  wire hs_rise  = g_hs & ~hs_q;
  wire vb_rise  = g_vb & ~vb_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      gx<=0; gy<=0; de_q<=0; vb_q<=0; hs_q<=0;
      de_cnt<=0; hb_cnt<=0; line_pix<=0; saw_de<=0;
      awidth_ln<=0; hblow_ln<=0; ltotal_ln<=0;
      frame_lines<=0; deh_lines<=0; cmin_acc<=12'hFFF; cmax_acc<=0;
      m_awidth<=0; m_hbcnt<=0; m_ltotal<=0; m_cmin<=0; m_cmax<=0; m_aheight<=0;
      grat_x<=0; grat_y<=0;
    end else if (ce_pix) begin
      de_q<=g_de; vb_q<=g_vb; hs_q<=g_hs;

      // ---- display coords + graticule phase ----
      if (vb_rise) begin
        gy<=0; gx<=0; grat_y<=0; grat_x<=0;
      end else if (g_de) begin
        gx<=gx+12'd1;
        grat_x <= (grat_x==6'd49) ? 6'd0 : grat_x+6'd1;
      end else if (de_q && !g_de) begin        // active line just ended
        gx<=0; grat_x<=0;
        gy<=gy+12'd1;
        grat_y <= (grat_y==6'd31) ? 6'd0 : grat_y+6'd1;
      end

      // ---- per-line measurement counters ----
      line_pix <= line_pix + 12'd1;             // free-run within the line
      if (g_de)  begin de_cnt<=de_cnt+12'd1; saw_de<=1'b1; end
      if (!g_hb) hb_cnt<=hb_cnt+12'd1;

      // content horizontal extent (min/max non-black active column)
      if (g_de && nonblack) begin
        if (gx < cmin_acc) cmin_acc<=gx;
        if (gx > cmax_acc) cmax_acc<=gx;
      end

      // ---- line boundary (HSync rising): fold per-line, bump per-frame ----
      if (hs_rise) begin
        ltotal_ln <= line_pix;                  // full line length
        if (saw_de) begin
          awidth_ln  <= de_cnt;
          hblow_ln   <= hb_cnt;
          deh_lines  <= deh_lines + 12'd1;
        end
        frame_lines <= frame_lines + 12'd1;
        de_cnt<=0; hb_cnt<=0; line_pix<=0; saw_de<=0;
      end

      // ---- frame boundary (VBlank rising): latch stable, reset accumulators ----
      if (vb_rise) begin
        m_awidth  <= awidth_ln;
        m_hbcnt   <= hblow_ln;
        m_ltotal  <= ltotal_ln;
        m_aheight <= deh_lines;
        m_cmin    <= (cmax_acc==0) ? 12'd0 : cmin_acc;   // 0 if the frame was all black
        m_cmax    <= cmax_acc;
        frame_lines<=0; deh_lines<=0; cmin_acc<=12'hFFF; cmax_acc<=0;
      end
    end
  end

  // ---- hex panel (top-left): 6 rows x 3 digits, 4x-scaled 3x5 font -----------
  // glyph cell 12x20 (font*4); digit advance 16; row pitch 28. Panel origin (6,6).
  localparam int PX=6, PY=6;
  wire in_box = (gx>=PX) && (gx<PX+48) && (gy>=PY) && (gy<PY+6*28);
  wire [11:0] lx = gx - PX[11:0];
  wire [11:0] ly = gy - PY[11:0];
  wire [1:0]  digit = lx[5:4];              // lx>>4, 0..2 (need <3)
  wire [3:0]  dx    = lx[3:0];              // lx&15, glyph col if <12
  // select row + its value by vertical band (row pitch 28, glyph 20 tall)
  logic [11:0] rowval; logic [2:0] rowsel; logic in_rowband; logic [11:0] rytop;
  always_comb begin
    in_rowband=1'b0; rowsel=3'd0; rytop=12'd0; rowval=12'd0;
    if      (ly<12'd20)               begin in_rowband=1; rowsel=0; rytop=12'd0;  rowval=m_awidth;  end
    else if (ly>=12'd28 && ly<12'd48) begin in_rowband=1; rowsel=1; rytop=12'd28; rowval=m_hbcnt;   end
    else if (ly>=12'd56 && ly<12'd76) begin in_rowband=1; rowsel=2; rytop=12'd56; rowval=m_ltotal;  end
    else if (ly>=12'd84 && ly<12'd104)begin in_rowband=1; rowsel=3; rytop=12'd84; rowval=m_cmin;    end
    else if (ly>=12'd112&& ly<12'd132)begin in_rowband=1; rowsel=4; rytop=12'd112;rowval=m_cmax;    end
    else if (ly>=12'd140&& ly<12'd160)begin in_rowband=1; rowsel=5; rytop=12'd140;rowval=m_aheight; end
  end
  wire [11:0] ry   = ly - rytop;            // 0..19 within the glyph
  wire [2:0]  frow = ry[4:2];               // ry>>2, 0..4
  wire [1:0]  fcol = dx[3:2];               // dx>>2, 0..2
  wire [3:0]  nyb  = rowval >> ({1'b0,(2'd2-digit)}<<2);   // digit 0=hi .. 2=lo
  wire        glyph_on = in_box && in_rowband && (digit<2'd3) && (dx<4'd12)
                         && (frow<3'd5) && fpix(nyb, fcol, frow);
  logic [23:0] rowcol;
  always_comb case (rowsel)
    3'd0: rowcol=24'hFFFF00;  // AW  yellow
    3'd1: rowcol=24'h00FFFF;  // HB  cyan
    3'd2: rowcol=24'h00FF00;  // LT  green
    3'd3: rowcol=24'hFF8000;  // CMN orange
    3'd4: rowcol=24'hFF00FF;  // CMX magenta
    default: rowcol=24'hFFFFFF;// AH  white
  endcase

  // ---- graticule ----
  wire vtick = (grat_x==6'd0);
  wire htick = (grat_y==6'd0);
  wire ledge = (gx==12'd0);                 // active left edge marker (red)

  // ---- composite (registered, aligned with g_de) ----
  always_ff @(posedge clk) begin
    if (rst) begin
      de<=0; hsync<=0; vsync<=0; hblank<=0; vblank<=0;
      vid_r<=0; vid_g<=0; vid_b<=0;
    end else if (ce_pix) begin
      de<=g_de; hsync<=g_hs; vsync<=g_vs; hblank<=g_hb; vblank<=g_vb;
      if (!g_de) begin
        vid_r<=8'h00; vid_g<=8'h00; vid_b<=8'h00;
      end else if (in_box) begin
        if (glyph_on) begin vid_r<=rowcol[23:16]; vid_g<=rowcol[15:8]; vid_b<=rowcol[7:0]; end
        else          begin vid_r<=8'h00; vid_g<=8'h00; vid_b<=8'h30; end   // navy panel bg
      end else if (ledge) begin
        vid_r<=8'hFF; vid_g<=8'h00; vid_b<=8'h00;                            // left-edge (col 0) red
      end else if (vtick) begin
        vid_r<=8'hFF; vid_g<=8'hFF; vid_b<=8'hFF;                            // every-50px vertical
      end else if (htick) begin
        vid_r<=8'h80; vid_g<=8'h80; vid_b<=8'h80;                            // every-32ln horizontal
      end else begin
        vid_r<=g_r; vid_g<=g_g; vid_b<=g_b;                                  // live game underneath
      end
    end
  end
endmodule
`default_nettype wire

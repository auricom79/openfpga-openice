// wolf_faceoff_diag_overlay.sv -- Open Ice opening-faceoff render map.
//
// This is an observation-only diagnostic. It never changes DMA requests,
// framebuffer writes, page publication, scanout addresses, or audio. The DMA
// supplies one event for each in-clip destination pixel that its walker retires.
// Four sticky maps are collected independently for Open Ice's two 254-line
// framebuffer pages, then latched once per video frame:
//
//   blue    no DMA destination pixel reached this tile
//   magenta DMA traversed the tile, but every observed pixel was skipped
//   red     writes reached the tile, but no nonzero COPY source pixel did
//   yellow  COLOR/fill writes reached the tile, but no nonzero COPY did
//   green   at least one nonzero COPY source pixel reached the tile
//
// A four-pixel 64x32 tile border plus a corner badge is painted, so the live
// game remains visible. A permanent five-color key across the top makes a
// diagnostic build visually unmistakable even before the first DMA event.
// The map shown over a page is the render evidence captured during the
// preceding frame, which matches the game's hidden-page build followed by page
// publication.
//
// Open Ice page rows come directly from its observed DPYADR pair:
//   page 0 base 511: physical rows 511,0..252
//   page 1 base 253: physical rows 253..506
// Rows 507..510 are outside both 254-line display pages and are ignored.

`default_nettype none
module wolf_faceoff_diag_overlay #(
  parameter int H_ACT = 400,
  parameter int V_ACT = 254,
  parameter logic [11:0] COL_TAP = 56
)(
  input  logic        clk,
  input  logic        rst,
  input  logic        ce_pix,
  input  logic        enable,

  input  logic        px_evt,
  input  logic [9:0]  px_x,
  input  logic [8:0]  px_y,
  input  logic        px_write,
  input  logic        px_copy_nz,
  input  logic        px_color,
  input  logic [18:0] active_row0,

  input  logic [7:0]  g_r, g_g, g_b,
  input  logic        g_hs, g_vs, g_hb, g_vb, g_de,
  output logic [7:0]  vid_r, vid_g, vid_b,
  output logic        hsync, vsync, hblank, vblank, de
);
  localparam logic [8:0] PAGE0_BASE = 9'd511;
  localparam logic [8:0] PAGE1_BASE = 9'd253;

  // Physical destination -> Open Ice page-relative 400x254 coordinate.
  wire px_page0 = (px_y == PAGE0_BASE) || (px_y <= 9'd252);
  wire px_page1 = (px_y >= PAGE1_BASE) && (px_y <= 9'd506);
  wire [8:0] px_rel_y = px_page0 ? (px_y + 9'd1)
                                  : (px_y - PAGE1_BASE);
  wire px_x_visible = (px_x >= COL_TAP) &&
                      (px_x < (COL_TAP + H_ACT));
  wire px_y_visible = px_page0 || px_page1;
  wire px_visible = px_evt && px_x_visible && px_y_visible &&
                    (px_rel_y < V_ACT);
  wire [9:0] px_rel_x = px_x - COL_TAP;
  wire [2:0] px_tile_x = px_rel_x[8:6];
  wire [2:0] px_tile_y = px_rel_y[7:5];
  wire [6:0] px_tile = {px_page1, px_tile_y, px_tile_x};

  // One 64-tile map per page. The live maps describe the page currently being
  // built; the show maps are stable for a full displayed frame.
  logic [127:0] live_seen, live_write, live_copy_nz, live_color;
  logic [127:0] show_seen, show_write, show_copy_nz, show_color;
  logic vb_q;
  wire vb_rise = g_vb && !vb_q;

  always_ff @(posedge clk) begin
    if (rst) begin
      live_seen    <= '0;
      live_write   <= '0;
      live_copy_nz <= '0;
      live_color   <= '0;
      show_seen    <= '0;
      show_write   <= '0;
      show_copy_nz <= '0;
      show_color   <= '0;
      vb_q         <= 1'b0;
    end else begin
      if (ce_pix)
        vb_q <= g_vb;

      if (ce_pix && vb_rise) begin
        show_seen    <= live_seen;
        show_write   <= live_write;
        show_copy_nz <= live_copy_nz;
        show_color   <= live_color;
        live_seen    <= '0;
        live_write   <= '0;
        live_copy_nz <= '0;
        live_color   <= '0;
      end

      // Ordered after the frame clear so an event coincident with vb_rise
      // starts the next capture instead of being discarded.
      if (px_visible) begin
        live_seen[px_tile] <= 1'b1;
        if (px_write)
          live_write[px_tile] <= 1'b1;
        if (px_copy_nz)
          live_copy_nz[px_tile] <= 1'b1;
        if (px_color)
          live_color[px_tile] <= 1'b1;
      end
    end
  end

  // Active-space raster coordinate. It is used only to select a diagnostic
  // tile; all game video and timing signals otherwise pass through unchanged.
  logic [8:0] gx;
  logic [7:0] gy;
  logic de_q;
  always_ff @(posedge clk) begin
    if (rst) begin
      gx   <= 9'd0;
      gy   <= 8'd0;
      de_q <= 1'b0;
    end else if (ce_pix) begin
      de_q <= g_de;
      if (g_vb) begin
        gx <= 9'd0;
        gy <= 8'd0;
      end else if (g_de) begin
        if (!de_q)
          gx <= 9'd0;
        else
          gx <= gx + 9'd1;
      end else if (de_q) begin
        gx <= 9'd0;
        if (gy < V_ACT-1)
          gy <= gy + 8'd1;
      end
    end
  end

  wire display_page1 = (active_row0[8:0] == PAGE1_BASE);
  wire [2:0] show_tile_x = gx[8:6];
  wire [2:0] show_tile_y = gy[7:5];
  wire [6:0] show_tile = {display_page1, show_tile_y, show_tile_x};
  wire tile_seen    = show_seen[show_tile];
  wire tile_write   = show_write[show_tile];
  wire tile_copy_nz = show_copy_nz[show_tile];
  wire tile_color   = show_color[show_tile];

  logic [23:0] class_rgb;
  always_comb begin
    if (!tile_seen)
      class_rgb = 24'h0060FF;       // blue: no destination traversal
    else if (!tile_write)
      class_rgb = 24'hFF00FF;       // magenta: traversed, all skipped
    else if (tile_copy_nz)
      class_rgb = 24'h00FF40;       // green: nonzero source COPY reached tile
    else if (tile_color)
      class_rgb = 24'hFFFF00;       // yellow: fill/COLOR only
    else
      class_rgb = 24'hFF2000;       // red: writes, but copied source stayed zero
  end

  wire tile_border = (gx[5:0] < 6'd4) || (gy[4:0] < 5'd4);
  wire tile_badge  = (gx[5:0] < 6'd14) && (gy[4:0] < 5'd14);
  wire key_bar = (gy < 8'd10) && (gx < 9'd160);
  logic [23:0] key_rgb;
  always_comb begin
    case (gx[7:5])
      3'd0: key_rgb = 24'h0060FF; // no traversal
      3'd1: key_rgb = 24'hFF00FF; // skipped
      3'd2: key_rgb = 24'hFF2000; // zero source
      3'd3: key_rgb = 24'hFFFF00; // color/fill
      default: key_rgb = 24'h00FF40; // nonzero copy
    endcase
  end
  wire paint_diag  = enable && g_de &&
                     (key_bar || tile_border || tile_badge);

  always_comb begin
    hsync  = g_hs;
    vsync  = g_vs;
    hblank = g_hb;
    vblank = g_vb;
    de     = g_de;
    if (paint_diag) begin
      vid_r = key_bar ? key_rgb[23:16] : class_rgb[23:16];
      vid_g = key_bar ? key_rgb[15:8]  : class_rgb[15:8];
      vid_b = key_bar ? key_rgb[7:0]   : class_rgb[7:0];
    end else begin
      vid_r = g_r;
      vid_g = g_g;
      vid_b = g_b;
    end
  end
endmodule
`default_nettype wire

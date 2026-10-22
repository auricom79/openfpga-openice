// wolf_video_post.sv -- final Wolf RGB/control handoff.
//
// The Rampage bring-up tree temporarily carried an unfinished CRT-offset stage here.
// Its "vline" counter advanced on every pixel enable rather than once per scanline,
// blanking 15 of every 269 pixel clocks. Because 269 does not divide the 506-clock
// line, those black runs walked across successive rows as diagonal dashes.
//
// No offset was actually selectable: both H and V offsets were hard-wired to zero,
// and the programmed Rampage active area is the native Wolf 400x254 raster. Keep the
// final handoff transparent, matching the shipped UMK3 Wolf path. The old stage is
// retained only as a mutation so the exact cabinet-shaped failure remains testable.
`timescale 1ns/1ps
`default_nettype none
module wolf_video_post #(
  parameter int H_ACT = 400,
  parameter int V_ACT = 254
)(
  input  logic       clk,
  input  logic       ce_pix,
  input  logic [7:0] vid_r_pre, vid_g_pre, vid_b_pre,
  input  logic       hsync_pre, vsync_pre, hblank_pre, vblank_pre, de_pre,
  output logic [7:0] vid_r, vid_g, vid_b,
  output logic       hsync, vsync, hblank, vblank, de
);
`ifdef MUT_PIXEL_RATE_VLINE
  // Exact unfinished Rampage post-stage retained as a fail-before mutation.
  logic [7:0] rgb_r_h[0:15], rgb_g_h[0:15], rgb_b_h[0:15];
  logic de_h[0:15];
  integer i;
  always_ff @(posedge clk) if (ce_pix) begin
    rgb_r_h[0] <= vid_r_pre;
    rgb_g_h[0] <= vid_g_pre;
    rgb_b_h[0] <= vid_b_pre;
    de_h[0] <= de_pre && !hblank_pre;
    for (i = 1; i < 16; i = i + 1) begin
      rgb_r_h[i] <= rgb_r_h[i-1];
      rgb_g_h[i] <= rgb_g_h[i-1];
      rgb_b_h[i] <= rgb_b_h[i-1];
      de_h[i] <= de_h[i-1];
    end
  end

  logic hsync_r1, hsync_r2, hsync_r3;
  logic vsync_r1, vsync_r2, vsync_r3;
  logic hblank_r1, hblank_r2, hblank_r3;
  logic vblank_r1, vblank_r2, vblank_r3;
  always_ff @(posedge clk) if (ce_pix) begin
    hsync_r1 <= hsync_pre;   vsync_r1 <= vsync_pre;
    hblank_r1 <= hblank_pre; vblank_r1 <= vblank_pre;
    hsync_r2 <= hsync_r1;    vsync_r2 <= vsync_r1;
    hblank_r2 <= hblank_r1;  vblank_r2 <= vblank_r1;
    hsync_r3 <= hsync_r2;    vsync_r3 <= vsync_r2;
    hblank_r3 <= hblank_r2;  vblank_r3 <= vblank_r2;
  end

  logic [8:0] vline_cnt;
  wire vline_en = !vblank_r3 && (vline_cnt < V_ACT);
  always_ff @(posedge clk) if (ce_pix) begin
    if (vsync_r3 || vline_cnt >= (V_ACT + 15))
      vline_cnt <= 9'd0;
    else if (!vblank_r3)
      vline_cnt <= vline_cnt + 9'd1; // BUG: pixel-rate, not line-rate
  end

  logic [11:0] hpix_cnt;
  wire hpix_en = (hpix_cnt < H_ACT) && !hblank_r3;
  always_ff @(posedge clk) if (ce_pix) begin
    if (hblank_r3 || hpix_cnt >= H_ACT)
      hpix_cnt <= 12'd0;
    else if (!vblank_r3)
      hpix_cnt <= hpix_cnt + 12'd1;
  end

  assign vid_r = (hpix_en && vline_en) ? rgb_r_h[8] : 8'h00;
  assign vid_g = (hpix_en && vline_en) ? rgb_g_h[8] : 8'h00;
  assign vid_b = (hpix_en && vline_en) ? rgb_b_h[8] : 8'h00;
  assign de = de_h[8] && hpix_en && vline_en;
  assign hsync = hsync_r3;
  assign vsync = vsync_r3;
  assign hblank = hblank_r3;
  assign vblank = vblank_r3;
`else
  // Production: transparent handoff, identical in shape to shipped UMK3.
  assign vid_r = vid_r_pre;
  assign vid_g = vid_g_pre;
  assign vid_b = vid_b_pre;
  assign hsync = hsync_pre;
  assign vsync = vsync_pre;
  assign hblank = hblank_pre;
  assign vblank = vblank_pre;
  assign de = de_pre;
`endif
endmodule
`default_nettype wire

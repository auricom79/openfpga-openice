// smashtv_diag2_overlay.sv — BOOT INSTRUMENT v4 (+define+DIAG_BOOT): DERAIL CAPTURE.
//
// The on-screen PC display IS our SignalTap. v4 freezes the exact moment the CPU derails
// (PC first leaves the R_ROM code region) and paints it, so we read the wild jump straight
// off the cab instead of guessing in sim:
//   top strip  : color bars (video/clock sanity)
//   status bar : GREEN = still running (not derailed yet) / RED = DERAILED (capture frozen)
//   LED strip  : 10 boot-gate lanes (P0019) — localize WHERE boot stalls in ONE cab photo:
//                lane0 core_rst(green=released)  1 sdram_ready  2 unp_done  3 dl-done(green=idle)
//                lane4 no-illegal(green=clean)   5 cpu_req  6 mem_ack  7 int1  8 vblank  9 CPU_CE
//                lanes 0-4 = steady level (green healthy / red not); lanes 5-9 = ACTIVITY
//                (green only if the signal toggled both 0 and 1 within the frame = alive; red=stuck).
//                Lane 9 (CPU_CE) is the P0019 crux: green proves the /4 clock-enable is pulsing.
//   hex row 1  : RESET-VECTOR / CULPRIT PC (8 hex) — first ack'd read; FFE0F5C0 = ROM reached CPU
//   hex row 2  : CULPRIT OPCODE (right 4 hex) — the instruction word there
//   hex row 3  : DERAIL TARGET (8 hex) — where it jumped TO (the bad address)
//   hex row 4  : LIVE PC       (8 hex, ~2 Hz) — where the CPU is now
// Read the LED strip + rows off the screen -> we KNOW which permutation the cab is in.
`default_nettype none
module smashtv_diag2_overlay
#(
  parameter int H_ACT=410, H_FP=6,  H_SYNC=40, H_BP=50,
  parameter int V_ACT=256, V_FP=13, V_SYNC=8,  V_BP=12
)(
  input  logic        clk, ce_pix, rst,
  input  logic        core_rst, sdram_ready, unp_done, ioctl_download,
  input  logic        cpu_req, mem_ack, int1, vblank_irq,
  input  logic        cpu_ce,          // P0019 /4 clock-enable pulse (liveness lane 9)
  input  logic [31:0] pc,
  input  logic        illegal,
  input  logic        derailed,
  input  logic [31:0] culprit_pc,
  input  logic [15:0] culprit_instr,
  input  logic [31:0] derail_pc,
  // GAME VIDEO passthrough (2026-07-11): the overlay now COMPOSITES — it draws the diag scaled
  // into the top-left QUADRANT (~1/4 area) and shows the real game everywhere else, so you can
  // read the numbers AND see which scene (select/fight) you are on. Fed the core's live raster.
  input  logic [7:0]  g_r, g_g, g_b,
  input  logic        g_hs, g_vs, g_hb, g_vb, g_de,
  output logic [7:0]  vid_r, vid_g, vid_b,
  output logic        hsync, vsync, hblank, vblank, de
);
  localparam int H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;
  localparam int V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;

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
  function automatic fpix(input [3:0] d, input [2:0] col, input [2:0] row);
    logic [14:0] g; logic [2:0] rb; g=glyph(d);
    case (row) 3'd0:rb=g[14:12]; 3'd1:rb=g[11:9]; 3'd2:rb=g[8:6]; 3'd3:rb=g[5:3]; default:rb=g[2:0]; endcase
    fpix = (col==3'd0)?rb[2] : (col==3'd1)?rb[1] : (col==3'd2)?rb[0] : 1'b0;
  endfunction

  // Track the GAME's active raster (gx,gy) from its de/vblank. The diag renders into the top-left
  // quadrant using VIRTUAL full-frame coords hc=gx<<1, vc=gy<<1 (the existing 410x256 layout maps
  // 1:1 into a ~205x128 quadrant = ~1/4 area). s0_de (hc<H_ACT && vc<V_ACT) then IS "in the diag
  // quadrant"; outside it the game passes through so you can see which scene you're on.
  logic [11:0] gx, gy; logic de_q, vb_q; logic [23:0] frame;
  logic [31:0] pc_q, pc_qq, pc_show;
  always_ff @(posedge clk) begin
    if (rst) begin gx<=0; gy<=0; de_q<=0; vb_q<=0; frame<=0; pc_q<=0; pc_qq<=0; pc_show<=0; end
    else if (ce_pix) begin
      de_q<=g_de; vb_q<=g_vb; pc_q<=pc; pc_qq<=pc_q;
      if (g_vb && !vb_q) begin gy<=12'd0; gx<=12'd0; frame<=frame+24'd1;  // vblank rising = new frame
        if (frame[4:0]==5'd0) pc_show<=pc_qq; end
      else if (g_de) gx<=gx+12'd1;                                        // active pixel
      else if (de_q && !g_de) begin gx<=12'd0; gy<=gy+12'd1; end          // line end -> next row
    end
  end
  wire [11:0] hc = gx << 1;      // virtual full-frame column (diag layout space)
  wire [11:0] vc = gy << 1;      // virtual full-frame row
  wire s0_de = (hc<H_ACT) && (vc<V_ACT);     // = inside the top-left diag quadrant

  // ---- boot-gate LED strip (P0019): per-frame activity detect + sticky illegal -------------
  // Activity lanes (cpu_req/mem_ack/int1/vblank/cpu_ce) go GREEN only if the signal was seen
  // BOTH high and low within a frame (toggling = alive); a stuck signal stays RED. cpu_ce is
  // sampled on clk so its 1-in-4 pulse reliably registers. Steady lanes use the live level.
  wire frame_tick = ce_pix && g_vb && !vb_q;   // game vblank rising = per-frame boundary
  logic a1_req,a0_req, a1_ack,a0_ack, a1_i1,a0_i1, a1_vb,a0_vb, a1_ce,a0_ce;
  logic alive_req, alive_ack, alive_i1, alive_vb, alive_ce, illegal_sticky;
  always_ff @(posedge clk) begin
    if (rst) begin
      a1_req<=0; a0_req<=0; a1_ack<=0; a0_ack<=0; a1_i1<=0; a0_i1<=0;
      a1_vb<=0; a0_vb<=0; a1_ce<=0; a0_ce<=0;
      alive_req<=0; alive_ack<=0; alive_i1<=0; alive_vb<=0; alive_ce<=0; illegal_sticky<=0;
    end else begin
      if (illegal)    illegal_sticky<=1'b1;
      if (cpu_req)    a1_req<=1'b1; else a0_req<=1'b1;
      if (mem_ack)    a1_ack<=1'b1; else a0_ack<=1'b1;
      if (int1)       a1_i1 <=1'b1; else a0_i1 <=1'b1;
      if (vblank_irq) a1_vb <=1'b1; else a0_vb <=1'b1;
      if (cpu_ce)     a1_ce <=1'b1; else a0_ce <=1'b1;
      if (frame_tick) begin
        alive_req<=a1_req&a0_req; a1_req<=1'b0; a0_req<=1'b0;
        alive_ack<=a1_ack&a0_ack; a1_ack<=1'b0; a0_ack<=1'b0;
        alive_i1 <=a1_i1 &a0_i1;  a1_i1 <=1'b0; a0_i1 <=1'b0;
        alive_vb <=a1_vb &a0_vb;  a1_vb <=1'b0; a0_vb <=1'b0;
        alive_ce <=a1_ce &a0_ce;  a1_ce <=1'b0; a0_ce <=1'b0;
      end
    end
  end
  // LED strip geometry: 10 lanes just below the status bar (vc 44..51), ~41px each w/ 2px gutter.
  localparam int LEDW = H_ACT/10;
  wire in_leds = (vc>=12'd44) && (vc<12'd52);
  wire [3:0] led_lane = (hc<LEDW)?4'd0:(hc<2*LEDW)?4'd1:(hc<3*LEDW)?4'd2:(hc<4*LEDW)?4'd3:
                        (hc<5*LEDW)?4'd4:(hc<6*LEDW)?4'd5:(hc<7*LEDW)?4'd6:(hc<8*LEDW)?4'd7:
                        (hc<9*LEDW)?4'd8:4'd9;
  wire [11:0] led_x = hc - (led_lane*LEDW);
  wire led_body = (led_x>=12'd2) && (led_x < (LEDW-2));
  logic led_good;
  always_comb case (led_lane)
    4'd0: led_good = ~core_rst;         // green once the boot gate releases
    4'd1: led_good =  sdram_ready;
    4'd2: led_good =  unp_done;
    4'd3: led_good = ~ioctl_download;   // green once the ROM download finishes
    4'd4: led_good = ~illegal_sticky;   // red if an illegal opcode EVER executed
    4'd5: led_good =  alive_req;
    4'd6: led_good =  alive_ack;
    4'd7: led_good =  alive_i1;
    4'd8: led_good =  alive_vb;
    default: led_good = alive_ce;       // lane 9 = CPU_CE liveness (P0019 crux)
  endcase

  // color bars (top eighth)
  localparam int HE=H_ACT/8;
  logic [7:0] cbr,cbg,cbb;
  wire [2:0] barx=(hc<HE)?3'd0:(hc<2*HE)?3'd1:(hc<3*HE)?3'd2:(hc<4*HE)?3'd3:(hc<5*HE)?3'd4:(hc<6*HE)?3'd5:(hc<7*HE)?3'd6:3'd7;
  always_comb case (barx)
    3'd0:{cbr,cbg,cbb}={8'hFF,8'hFF,8'hFF}; 3'd1:{cbr,cbg,cbb}={8'hFF,8'hFF,8'h00};
    3'd2:{cbr,cbg,cbb}={8'h00,8'hFF,8'hFF}; 3'd3:{cbr,cbg,cbb}={8'h00,8'hFF,8'h00};
    3'd4:{cbr,cbg,cbb}={8'hFF,8'h00,8'hFF}; 3'd5:{cbr,cbg,cbb}={8'hFF,8'h00,8'h00};
    3'd6:{cbr,cbg,cbb}={8'h00,8'h00,8'hFF}; default:{cbr,cbg,cbb}={8'h20,8'h20,8'h20};
  endcase

  // 4 hex rows: pick the row's value by vertical band
  logic [31:0] rowval; logic in_hex; logic [11:0] ry0;
  always_comb begin
    in_hex=1'b0; rowval=32'd0; ry0=12'd0;
    if      (vc>=12'd52  && vc<12'd96 ) begin in_hex=1'b1; ry0=12'd52;  rowval=culprit_pc;               end
    else if (vc>=12'd100 && vc<12'd144) begin in_hex=1'b1; ry0=12'd100; rowval={16'h0000,culprit_instr}; end
    else if (vc>=12'd148 && vc<12'd192) begin in_hex=1'b1; ry0=12'd148; rowval=derail_pc;                end
    else if (vc>=12'd200 && vc<12'd244) begin in_hex=1'b1; ry0=12'd200; rowval=pc_show;                  end
  end
  localparam int PX0=77;
  wire        hxin  = (hc>=PX0) && (hc<PX0+256);
  wire [7:0]  hrx   = hc - PX0[11:0];
  wire [2:0]  hdig  = hrx[7:5];
  wire [1:0]  hfcol = hrx[4:3];
  wire [11:0] hry12 = vc - ry0;         // 0..43 within the row band
  wire [2:0]  hfrow = hry12[5:3];
  wire [4:0]  hsh   = {2'b0,(3'd7-hdig)} << 2;
  wire [3:0]  hnyb  = rowval >> hsh;
  wire        hex_on= in_hex && hxin && (hfcol<2'd3) && (hfrow<3'd5) && fpix(hnyb, {1'b0,hfcol}, hfrow);

  wire in_status = (vc>=12'd24) && (vc<12'd44);
  wire live_col  = (hc == frame[8:0]);

  always_ff @(posedge clk) if (ce_pix) begin
    de<=g_de; hsync<=g_hs; vsync<=g_vs; hblank<=g_hb; vblank<=g_vb;   // GAME timing passthrough
    if (!g_de)               begin vid_r<=8'd0; vid_g<=8'd0; vid_b<=8'd0; end  // outside active video
    else if (!s0_de)         begin vid_r<=g_r;  vid_g<=g_g;  vid_b<=g_b;  end  // GAME (outside diag quadrant)
    else if (vc<12'd20)      begin vid_r<=cbr; vid_g<=cbg; vid_b<=cbb; end
    else if (live_col)       begin vid_r<=8'hFF; vid_g<=8'hFF; vid_b<=8'hFF; end
    else if (in_status)      begin  // derailed=red, running=green
      if (derailed) begin vid_r<=8'hC0; vid_g<=8'h00; vid_b<=8'h00; end
      else          begin vid_r<=8'h00; vid_g<=8'hC0; vid_b<=8'h00; end
    end
    else if (in_leds) begin         // 10 boot-gate lanes (green=good/alive, red=bad/stuck)
      if (led_body) begin
        if (led_good) begin vid_r<=8'h00; vid_g<=8'hE0; vid_b<=8'h00; end
        else          begin vid_r<=8'hE0; vid_g<=8'h00; vid_b<=8'h00; end
      end else        begin vid_r<=8'h00; vid_g<=8'h00; vid_b<=8'h00; end
    end
    else if (in_hex) begin
      if (hex_on)            begin vid_r<=8'hFF; vid_g<=8'hFF; vid_b<=8'h00; end
      else                   begin vid_r<=8'h10; vid_g<=8'h10; vid_b<=8'h30; end
    end
    else                     begin vid_r<=8'h08; vid_g<=8'h08; vid_b<=8'h08; end
  end
endmodule
`default_nettype wire

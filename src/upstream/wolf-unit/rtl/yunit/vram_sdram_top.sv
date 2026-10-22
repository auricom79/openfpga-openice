// vram_sdram_top.sv — Phase 6 W1f: the whole VRAM-in-SDRAM subsystem behind ONE 16-bit
// SDRAM channel. Multiplexes the VRAM accessors — CPU field RMW (vram_sdram), the blitter
// fb write (fire-and-forget -> given an fb_ack so the blitter self-paces), and (added next)
// the autoerase row-copy — via a grant-held transaction arbiter. Swaps in for yunit_mem's
// 2-port BRAM VRAM engine once proven. Priority: CPU field > fb write (they are time-
// disjoint in practice — the CPU polls, not draws, during blits).
`timescale 1ns/1ps
`default_nettype none
module vram_sdram_top #(
  parameter int VRAMW     = 32'h40000,
  parameter int SD_AW     = 21,
  parameter [SD_AW-1:0] VRAM_BASE = '0
)(
  input  logic         clk,
  input  logic         rst,
  // CPU field access (passthrough to vram_sdram)
  input  logic         req,
  input  logic         we,
  input  logic [27:0]  widx,
  input  logic [3:0]   boff,
  input  logic [5:0]   sz,
  input  logic [31:0]  wd,
  input  logic         videobank,
  input  logic [15:0]  dma_palette,
  output logic [31:0]  rdata,
  output logic         done,
  // blitter framebuffer write (fire req; wait for fb_ack before the next)
  input  logic         fb_we,
  input  logic [18:0]  fb_addr,
  input  logic [15:0]  fb_wdata,
  output logic         fb_ack,
  // autoerase sweep trigger (frame-paced); caller gates on the CONTROL /autoerase enable
  input  logic         erase_start,
  input  logic [8:0]   erase_row0,
  input  logic [9:0]   erase_lines,
  output logic         erase_busy,
  // video scanout READ channel (highest priority = real-time). The video module owns the
  // line-buffer + row-burst sequencing (W3) and drives this raw read channel.
  input  logic         scan_req,       // read request (held until scan_ack)
  input  logic [18:0]  scan_addr,      // VRAM entry to read
  output logic [15:0]  scan_data,      // read data (valid at scan_ack)
  output logic         scan_ack,
  // shared single-word SDRAM channel
  output logic [SD_AW-1:0] sd_addr,
  output logic [15:0]  sd_din,
  output logic [1:0]   sd_be,
  output logic         sd_rd,
  output logic         sd_wr,
  input  logic [15:0]  sd_dout,
  input  logic         sd_ack
);
  // per-requester ack routing (declared up-front — Questa requires declaration-before-use).
  logic c_ack_i, f_ack_i, ae_ack_i;
  // ---- CPU field engine ----
  logic [SD_AW-1:0] c_addr; logic [15:0] c_din; logic [1:0] c_be; logic c_rd, c_wr, c_active;
  vram_sdram #(.VRAMW(VRAMW), .SD_AW(SD_AW), .VRAM_BASE(VRAM_BASE)) u_cpu (
    .clk(clk), .rst(rst), .req(req), .we(we), .widx(widx), .boff(boff), .sz(sz),
    .wd(wd), .videobank(videobank), .dma_palette(dma_palette), .rdata(rdata), .done(done),
    .active(c_active),
    .sd_addr(c_addr), .sd_din(c_din), .sd_be(c_be), .sd_rd(c_rd), .sd_wr(c_wr),
    .sd_dout(sd_dout), .sd_ack(c_ack_i));

  // ---- blitter fb writer: buffer ONE fb_we (on its RISING edge — the blitter now HOLDS
  // fb_we while waiting for fb_ack, so edge-detect avoids re-latching the same write),
  // write it, ack ----
  logic [18:0] f_a; logic [15:0] f_d; logic f_pending, fb_we_d;
  always_ff @(posedge clk) begin
    if (rst) begin f_pending <= 1'b0; fb_ack <= 1'b0; fb_we_d <= 1'b0; end
    else begin
      fb_ack  <= 1'b0;
      fb_we_d <= fb_we;
      if (!f_pending) begin
        if (fb_we & ~fb_we_d) begin f_a <= fb_addr; f_d <= fb_wdata; f_pending <= 1'b1; end
      end else if (f_ack_i) begin
        f_pending <= 1'b0; fb_ack <= 1'b1;
      end
    end
  end

  // ---- autoerase: row-copy sweep (src row 510|parity -> dst row; skip rows 510/511) ----
  // Per entry: read src -> write dst, over SDRAM (2 transactions). Frame-paced background;
  // lowest arbiter priority (yields to CPU field + fb write).
  localparam logic [1:0] AE_IDLE=2'd0, AE_RD=2'd1, AE_WR=2'd2, AE_ADV=2'd3;
  logic [1:0] ae; logic er_run; logic [8:0] er_row, er_x; logic [9:0] er_left; logic [15:0] er_data;
  wire [17:0] ae_src = {8'hFF, er_row[0], er_x};
  wire [17:0] ae_dst = {er_row, er_x};
  wire ae_skip = (er_row == 9'd510) || (er_row == 9'd511);
  wire ae_rd_req = (ae == AE_RD) & ~ae_skip;
  wire ae_wr_req = (ae == AE_WR);
  assign erase_busy = er_run;
  always_ff @(posedge clk) begin
    if (rst) begin ae <= AE_IDLE; er_run <= 1'b0; end
    else case (ae)
      AE_IDLE: if (erase_start && erase_lines != 10'd0) begin
                 er_run <= 1'b1; er_row <= erase_row0 - 9'd1; er_x <= 9'd0;
                 er_left <= erase_lines + 10'd1; ae <= AE_RD;
               end
      AE_RD:   if (ae_skip)        ae <= AE_ADV;              // never erase the pattern rows
               else if (ae_ack_i) begin er_data <= sd_dout; ae <= AE_WR; end
      AE_WR:   if (ae_ack_i)       ae <= AE_ADV;              // dst written
      AE_ADV:  begin
                 if (er_x == 9'd511) begin
                   er_x <= 9'd0; er_row <= er_row + 9'd1; er_left <= er_left - 10'd1;
                   if (er_left <= 10'd1) begin er_run <= 1'b0; ae <= AE_IDLE; end
                   else ae <= AE_RD;
                 end else begin er_x <= er_x + 9'd1; ae <= AE_RD; end
               end
      default: ae <= AE_IDLE;
    endcase
  end

  // ---- grant-held transaction arbiter (scanout > CPU field > fb > autoerase) ----
  // scanout is highest = real-time (must deliver pixels every line); its per-line traffic
  // is bounded (one row) so it can't starve the others. All non-scanout requesters can
  // wait (CPU/blitter stall gracefully; autoerase is background).
  wire cpu_req = c_rd | c_wr;
  wire fb_req  = f_pending;
  wire ae_req  = ae_rd_req | ae_wr_req;
  logic [2:0] gnt; logic gnt_held; logic [2:0] gnt_r; logic bubble;
  always_comb begin
    if (gnt_held)      gnt = gnt_r;
    else if (bubble)   gnt = 3'd0;     // 1-cycle gap: drops sd_rd/sd_wr so the next
    else if (scan_req) gnt = 3'd1;     //   transaction gets a clean rising edge (the
    else if (cpu_req)  gnt = 3'd2;     //   model edge-accepts; back-to-back rd->wr would
    else if (fb_req)   gnt = 3'd3;     //   otherwise keep (rd|wr) high and stall)
    else if (ae_req)   gnt = 3'd4;
    else               gnt = 3'd0;
  end
  always_ff @(posedge clk) begin
    if (rst) begin gnt_held <= 1'b0; gnt_r <= 3'd0; bubble <= 1'b0; end
    else begin
      bubble <= 1'b0;
      if (!gnt_held) begin
        if (!bubble && gnt != 3'd0) begin gnt_held <= 1'b1; gnt_r <= gnt; end
      end else if (sd_ack) begin
        gnt_held <= 1'b0; bubble <= 1'b1;   // transaction done -> gap -> re-arbitrate
      end
    end
  end

  // ---- route the granted requester to the shared SDRAM port; ack back to it only ----
  always_comb begin
    sd_addr = '0; sd_din = 16'h0; sd_be = 2'b00; sd_rd = 1'b0; sd_wr = 1'b0;
    c_ack_i = 1'b0; f_ack_i = 1'b0; ae_ack_i = 1'b0; scan_ack = 1'b0;
    case (gnt)
      3'd1: begin                        // scanout read (highest priority)
        sd_addr = VRAM_BASE + {{(SD_AW-19){1'b0}}, scan_addr}; sd_be = 2'b00; sd_rd = scan_req;
        scan_ack = sd_ack;
      end
      3'd2: begin                        // CPU field
        sd_addr = c_addr; sd_din = c_din; sd_be = c_be; sd_rd = c_rd; sd_wr = c_wr;
        c_ack_i = sd_ack;
      end
      3'd3: begin                        // fb write (full-word)
        sd_addr = VRAM_BASE + {{(SD_AW-19){1'b0}}, f_a}; sd_din = f_d; sd_be = 2'b11; sd_wr = f_pending;
        f_ack_i = sd_ack;
      end
      3'd4: begin                        // autoerase: read src / write dst (full-word)
        if (ae_rd_req) begin sd_addr = VRAM_BASE + {{(SD_AW-18){1'b0}}, ae_src}; sd_be = 2'b00; sd_rd = 1'b1; end
        else           begin sd_addr = VRAM_BASE + {{(SD_AW-18){1'b0}}, ae_dst}; sd_din = er_data; sd_be = 2'b11; sd_wr = 1'b1; end
        ae_ack_i = sd_ack;
      end
      default: ;
    endcase
  end
  assign scan_data = sd_dout;            // valid at scan_ack
endmodule
`default_nettype wire

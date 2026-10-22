// yunit_scanline.sv — Phase 6 W3: double-buffered VRAM line fetch for scanout. Sits between
// yunit_video (per-pixel vram_raddr, expects vram_rdata 1 clk later) and the SDRAM scan_*
// read channel. Invariant: buf[disp] holds the display row, buf[~disp] holds the NEXT row
// (prefetched). A loader fills whichever buffer is stale. On a row advance the buffers swap
// (the next-row prefetch becomes the display). yunit_video is UNCHANGED.
//
// VRAM entry index = (row << 9) | col (512 cols/row); scan_addr reads VRAM entries.
`timescale 1ns/1ps
`default_nettype none
module yunit_scanline #(
  parameter int FB_ADDR_W = 18,
  parameter int NCOL      = 512,     // entries to prefetch per row (>= visible cols)
  parameter int FIRST_ROW = 0,       // VRAM row displayed at frame top (= DISP_ROW0)
  // Physical Midway VRAM has 512 rows. Keep the line-buffer identity at nine
  // bits even when a caller widens FB_ADDR_W for CPU/DMA address spill.
  parameter int ROW_ADDR_W = 9
)(
  input  logic         clk,
  input  logic         rst,
  input  logic         ce_pix,                 // pixel-clock enable (gates the readout only)
  input  logic         vblank,                 // frame boundary: reprime for the top row
  input  logic [ROW_ADDR_W-1:0] frame_row0,     // committed physical first row (DPYSTRT page)
  input  logic [FB_ADDR_W-1:0] vram_raddr,     // (row<<9)|col  (from yunit_video)
  output logic [15:0]  vram_rdata,             // registered, 1 ce_pix latency (matches BRAM model)
  output logic         scan_req,
  output logic [18:0]  scan_addr,
  input  logic [15:0]  scan_data,
  input  logic         scan_ack
);
  localparam int ROWW = ROW_ADDR_W;
  wire [ROWW-1:0] req_row = vram_raddr[9+ROWW-1:9];
  wire [8:0]      req_col = vram_raddr[8:0];

  (* ramstyle = "no_rw_check, M10K" *) logic [15:0] lb [0:1023];
  logic disp_sel;
  logic [ROWW-1:0] disp_row;   // (declared before sel_now: Questa/Quartus need decl-before-use)
  // Select the buffer COMBINATIONALLY: if the raster row has already advanced past disp_row
  // (the registered swap lands next edge), read the prefetched (next-row) buffer NOW -- else
  // the first pixel of each row would read the stale buffer (1-clk swap latency artifact).
  wire sel_now = (req_row == disp_row) ? disp_sel : ~disp_sel;
  // ce_pix-gated read: advance the readout once per pixel, exactly like the BRAM model that
  // yunit_video's 3-stage (vram_rdata -> pal_rdata -> vid) pipeline was validated against.
  // An every-clk read collapses the pipeline and shifts color vs de by ~2 pixels.
  always_ff @(posedge clk) if (ce_pix) vram_rdata <= lb[{sel_now, req_col}];

  // which row each buffer currently holds (+ valid)
  logic [ROWW-1:0] buf_row [0:1]; logic buf_valid [0:1];
  wire  [ROWW-1:0] next_row = disp_row + 1'b1;

  // loader: bursts `tgt_row` into buffer `tgt_sel`
  logic loading, tgt_sel; logic [ROWW-1:0] tgt_row; logic [8:0] li;
  logic vbl_q;

  // is either buffer stale vs the invariant (disp_sel=disp_row, ~disp_sel=next_row)?
  wire disp_stale = !buf_valid[disp_sel] || (buf_row[disp_sel] != disp_row);
  wire load_stale = !buf_valid[~disp_sel] || (buf_row[~disp_sel] != next_row);

  always_ff @(posedge clk) begin
    if (rst) begin
      loading<=1'b0; scan_req<=1'b0; disp_sel<=1'b0; disp_row<='0;
      buf_valid[0]<=1'b0; buf_valid[1]<=1'b0; vbl_q<=1'b0;
    end else begin
      vbl_q <= vblank;
      // vblank START (rising): prime rows frame_row0 / frame_row0+1 during the blank so they
      // are valid BEFORE the active region — which is at the top (vc=0), with no vertical
      // back porch, so row 0 displays immediately at frame top. Priming at vblank FALL would
      // race the load against the first pixels of row 0.
      if ((!vbl_q && vblank) || (vblank && (frame_row0 != disp_row))) begin
        // frame_row0 can commit after vblank begins while posted VRAM writes settle.
        // Reprime again inside blanking when that happens; never chase a page in active video.
        disp_sel<=1'b0; disp_row<=frame_row0; buf_valid[0]<=1'b0; buf_valid[1]<=1'b0;
        loading<=1'b0; scan_req<=1'b0;   // drop req so the first new request re-edges (model edge-accepts)
      end else begin
        if (!vblank && (req_row != disp_row)) begin
          // row advanced -> the prefetched next-row buffer becomes the display
          disp_sel<=~disp_sel; disp_row<=req_row;
        end

        // start a load when idle and a buffer is stale (display first, then next-row prefetch)
        if (!loading) begin
          if (disp_stale)      begin tgt_sel<=disp_sel;  tgt_row<=disp_row; li<=9'd0; loading<=1'b1; end
          else if (load_stale) begin tgt_sel<=~disp_sel; tgt_row<=next_row; li<=9'd0; loading<=1'b1; end
        end else begin
          if (scan_req && scan_ack) begin
            lb[{tgt_sel, li}] <= scan_data;
            scan_req <= 1'b0;
            if (li == NCOL-1) begin loading<=1'b0; buf_row[tgt_sel]<=tgt_row; buf_valid[tgt_sel]<=1'b1; end
            else li <= li + 9'd1;
          end else if (!scan_req) scan_req <= 1'b1;
        end
      end
    end
  end
  assign scan_addr = {tgt_row[8:0], li};
endmodule
`default_nettype wire

// vram_sdram.sv — Phase 6 W1f: CPU VRAM field access (byte-lane / videobank) sequenced
// over a SINGLE 16-bit SDRAM req/ack channel. This is the USE_HW_VRAM CPU path with the
// 2-port BRAM backing replaced by ONE latency-tolerant SDRAM port (srg320 ch2-style).
// The byte-lane MATH is copied verbatim from yunit_mem's proven vram_w/vram_r engine —
// only the memory access is serialized + wait-on-ack (any SDRAM latency works).
//
//   VRAM read  (never straddles, measured): read e0,e1 -> form 16-bit word -> extract field.
//   VRAM write (RMW): read the target entries (old bytes) -> byte-lane merge -> write back.
//     sz<=8 : 1 entry (ea = (widx<<1)+boff[3])
//     sz<=16: 2 entries (e0,e1 = word widx)
//     sz>16 : 4 entries (e0,e1 + e2,e3 = word widx+1)   [wr never straddles >2 words]
//
// One access per `req` pulse; `done` pulses when complete (rdata valid for reads).
`timescale 1ns/1ps
`default_nettype none
module vram_sdram #(
  parameter int VRAMW     = 32'h40000,        // VRAM entries (512x512)
  parameter int SD_AW     = 21,               // SDRAM word-address width
  parameter [SD_AW-1:0] VRAM_BASE = '0        // VRAM word base in SDRAM
)(
  input  logic         clk,
  input  logic         rst,
  // field-access request (latched on req while idle)
  input  logic         req,                   // 1-cycle start pulse
  input  logic         we,                    // 1=write (RMW), 0=read
  input  logic [27:0]  widx,                  // 34010 VRAM word index (= addr[31:4], WB_VRAM=0)
  input  logic [3:0]   boff,                  // bit offset within the word
  input  logic [5:0]   sz,                    // field width (bits)
  input  logic [31:0]  wd,                    // write data
  input  logic         videobank,             // plane select (CONTROL bit5)
  input  logic [15:0]  dma_palette,           // blitter palette reg (folded into writes)
  output logic [31:0]  rdata,                 // read result (valid at done)
  output logic         done,                  // 1-cycle completion strobe
  output logic         active,                // 1 while an access is in progress (for arbitration)
  // single-word SDRAM channel (req held until ack)
  output logic [SD_AW-1:0] sd_addr,
  output logic [15:0]  sd_din,
  output logic [1:0]   sd_be,
  output logic         sd_rd,
  output logic         sd_wr,
  input  logic [15:0]  sd_dout,
  input  logic         sd_ack
);
  // latched request
  logic        we_l, vb_l; logic [27:0] wi; logic [3:0] bo; logic [5:0] szl;
  logic [31:0] wd_l; logic [15:0] pal_l;

  // entry geometry (from the latched request). e0/e1 = word wi; e2/e3 = word wi+1.
  wire [18:0] e0 = (wi << 1);            wire [18:0] e1 = (wi << 1) + 19'd1;
  wire [18:0] e2 = ((wi+28'd1) << 1);    wire [18:0] e3 = ((wi+28'd1) << 1) + 19'd1;
  wire [18:0] ea = (wi << 1) + {18'd0, bo[3]};
  wire v01   = (((wi<<1)+28'd1) < VRAMW);
  wire v23   = ((((wi+28'd1)<<1)+28'd1) < VRAMW);
  wire vea_v = ((wi<<1)+{27'd0,bo[3]}) < VRAMW;

  // captured old entry values
  logic [15:0] o0, o1, o2, o3;
  // An <=8-bit access reads only the selected `ea`, always capturing it in o0
  // (idx==0). Using o1 for an odd entry merged an unrelated stale low byte.
  wire [7:0] oea = o0[7:0];
  // byte-lane merged new values (verbatim from yunit_mem)
  wire [15:0] vnew0  = vb_l ? {pal_l[7:0],  wd_l[7:0]}   : {wd_l[7:0],   o0[7:0]};
  wire [15:0] vnew1  = vb_l ? {pal_l[15:8], wd_l[15:8]}  : {wd_l[15:8],  o1[7:0]};
  wire [15:0] vnew2  = vb_l ? {pal_l[7:0],  wd_l[23:16]} : {wd_l[23:16], o2[7:0]};
  wire [15:0] vnew3  = vb_l ? {pal_l[15:8], wd_l[31:24]} : {wd_l[31:24], o3[7:0]};
  wire [15:0] vnewea = vb_l ? {(bo[3]?pal_l[15:8]:pal_l[7:0]), wd_l[7:0]} : {wd_l[7:0], oea};
  // read field extract
  wire [15:0] vword = vb_l ? {o1[7:0], o0[7:0]} : {o1[15:8], o0[15:8]};
  wire [47:0] rmask = (48'd1 << szl) - 48'd1;

  // access plan: reads first, then writes. counts + per-index addr/data/valid.
  wire [2:0] nread  = we_l ? (szl<=6'd8 ? 3'd1 : szl<=6'd16 ? 3'd2 : 3'd4) : 3'd2;
  wire [2:0] nwrite = we_l ? (szl<=6'd8 ? 3'd1 : szl<=6'd16 ? 3'd2 : 3'd4) : 3'd0;
  wire is8 = we_l & (szl<=6'd8);

  // read/write address + validity by index (0..3). case (not chained ternary — the
  // spaceless `i==2'd0?e0` form trips Questa's lexer, though iverilog tolerated it).
  function automatic logic [18:0] raddr(input [1:0] i);
    if (is8) raddr = ea;
    else case (i) 2'd0: raddr=e0; 2'd1: raddr=e1; 2'd2: raddr=e2; default: raddr=e3; endcase
  endfunction
  function automatic logic rvalid(input [1:0] i);
    if (is8) rvalid = vea_v;
    else rvalid = (i < 2'd2) ? v01 : v23;
  endfunction
  function automatic logic [18:0] waddr(input [1:0] i);
    if (is8) waddr = ea;
    else case (i) 2'd0: waddr=e0; 2'd1: waddr=e1; 2'd2: waddr=e2; default: waddr=e3; endcase
  endfunction
  function automatic logic [15:0] wdata(input [1:0] i);
    if (is8) wdata = vnewea;
    else case (i) 2'd0: wdata=vnew0; 2'd1: wdata=vnew1; 2'd2: wdata=vnew2; default: wdata=vnew3; endcase
  endfunction
  function automatic logic wvalid(input [1:0] i);
    if (is8) wvalid = vea_v;
    else wvalid = (i < 2'd2) ? v01 : v23;
  endfunction

  typedef enum logic [1:0] { S_IDLE, S_RD, S_WR, S_FIN } st_t;
  st_t st; logic [2:0] idx;    // 0..4 (nread/nwrite can be 4) — MUST be 3-bit to exit the loop
  assign active = (st != S_IDLE);

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= S_IDLE; done <= 1'b0; sd_rd <= 1'b0; sd_wr <= 1'b0; idx <= 2'd0;
    end else begin
      done <= 1'b0;
      case (st)
        S_IDLE: begin
          sd_rd <= 1'b0; sd_wr <= 1'b0;
          if (req) begin
            we_l<=we; wi<=widx; bo<=boff; szl<=sz; wd_l<=wd; vb_l<=videobank; pal_l<=dma_palette;
            idx <= 2'd0;
            st  <= S_RD;                       // every access starts by reading (RMW / read)
          end
        end
        S_RD: begin
          if (idx >= nread) begin              // reads done
            sd_rd <= 1'b0;
            if (we_l) begin idx <= 2'd0; st <= S_WR; end
            else st <= S_FIN;
          end else if (!rvalid(idx)) begin     // OOB entry -> reads as 0, skip
            case (idx) 2'd0:o0<=16'h0; 2'd1:o1<=16'h0; 2'd2:o2<=16'h0; default:o3<=16'h0; endcase
            idx <= idx + 2'd1;
          end else if (sd_ack) begin           // captured this entry
            case (idx) 2'd0:o0<=sd_dout; 2'd1:o1<=sd_dout; 2'd2:o2<=sd_dout; default:o3<=sd_dout; endcase
            sd_rd <= 1'b0;
            idx <= idx + 2'd1;
          end else begin
            sd_addr <= VRAM_BASE + raddr(idx); sd_be <= 2'b00; sd_rd <= 1'b1;
          end
        end
        S_WR: begin
          if (idx >= nwrite) begin
            sd_wr <= 1'b0; st <= S_FIN;
          end else if (!wvalid(idx)) begin     // OOB entry -> drop the write
            idx <= idx + 2'd1;
          end else if (sd_ack) begin
            sd_wr <= 1'b0; idx <= idx + 2'd1;
          end else begin
            sd_addr <= VRAM_BASE + waddr(idx); sd_din <= wdata(idx); sd_be <= 2'b11; sd_wr <= 1'b1;
          end
        end
        S_FIN: begin
          rdata <= 32'((({32'h0, vword} >> bo) & rmask));   // read result (ignored for writes)
          done  <= 1'b1;
          st    <= S_IDLE;
        end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire

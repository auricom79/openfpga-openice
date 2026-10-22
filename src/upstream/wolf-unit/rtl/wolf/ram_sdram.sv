// ram_sdram.sv — plain 1:1-word CPU field access to the WOLF main RAM in SDRAM, sequenced over
// ONE 16-bit req/ack channel. Structural clone of rtl/yunit/vram_sdram.sv's FSM (latch on req,
// run over sd_rd/sd_wr held-until-ack, pulse done, `active` for arbitration) but with the field
// engine's PLAIN word math — NO VRAM byte-lane fold, NO videobank/dma_palette. A 34010 field
// spans up to 3 consecutive 16-bit words w0=rel, w1=rel+1, w2=rel+2.
//
// Field math is byte-exact vs wolf_mem's win_s/merged_s (wolf_mem.sv:499-500 rmask/smask/lastb,
// :965-968 win/merge, :992-994 write-back gates):
//   read : fetch the touched words -> win={w2,w1,w0} (OOB=0) -> rdata=(win>>boff)&rmask
//   write: RMW the touched words   -> merged=(win&~smask)|((wd<<boff)&smask) -> write back
// `widx` in is REGION-RELATIVE (wolf_mem passes widx-WB_RAM); the arbiter adds RAMW_BASE, so
// RAM_BASE stays 0 here (mirrors how vram_sdram keeps VRAM_BASE=0 and the arb adds VRAMW_BASE).
`timescale 1ns/1ps
`default_nettype none
module ram_sdram #(
  parameter int RAMW = 32'h40000,             // RAM words (0x40000 = 4 Mbit)
  parameter int SD_AW = 25,                    // SDRAM word-address width
  parameter [SD_AW-1:0] RAM_BASE = '0          // kept 0; the arbiter adds RAMW_BASE
)(
  input  logic         clk,
  input  logic         rst,
  input  logic         req,                    // 1-cycle start pulse (latched while idle)
  input  logic         we,                     // 1=write (RMW), 0=read
  input  logic [27:0]  widx,                   // region-relative word index (rel)
  input  logic [3:0]   boff,                   // bit offset within the word window
  input  logic [5:0]   sz,                     // field width (bits)
  input  logic [31:0]  wd,                     // write data
  output logic [31:0]  rdata,                  // read result (valid at done)
  output logic         done,                   // 1-cycle completion strobe
  output logic         active,                 // 1 while an access is in progress
  output logic [SD_AW-1:0] sd_addr,
  output logic [15:0]  sd_din,
  output logic [1:0]   sd_be,
  output logic         sd_rd,
  output logic         sd_wr,
  input  logic [15:0]  sd_dout,
  input  logic         sd_ack
);
  logic        we_l; logic [27:0] wi; logic [3:0] bo; logic [5:0] szl; logic [31:0] wd_l;

  // window word indices + validity (rel, rel+1, rel+2)
  wire [27:0] w0 = wi;  wire [27:0] w1 = wi + 28'd1;  wire [27:0] w2 = wi + 28'd2;
  wire v0 = (w0 < RAMW[27:0]);  wire v1 = (w1 < RAMW[27:0]);  wire v2 = (w2 < RAMW[27:0]);

  // field math (byte-exact vs wolf_mem)
  wire [5:0]  lastb  = bo + szl - 6'd1;
  wire [2:0]  ntouch = (lastb < 6'd16) ? 3'd1 : (lastb < 6'd32) ? 3'd2 : 3'd3;
  wire [47:0] rmask  = (48'd1 << szl) - 48'd1;
  wire [47:0] smask  = rmask << bo;

  logic [15:0] o0, o1, o2;                      // captured window words
  wire [47:0] win    = {v2?o2:16'h0, v1?o1:16'h0, v0?o0:16'h0};
  wire [47:0] merged = (win & ~smask) | (({16'h0, wd_l} << bo) & smask);

  function automatic logic [27:0] wsel(input [1:0] i);
    case (i) 2'd0: wsel=w0; 2'd1: wsel=w1; default: wsel=w2; endcase
  endfunction
  function automatic logic vsel(input [1:0] i);
    case (i) 2'd0: vsel=v0; 2'd1: vsel=v1; default: vsel=v2; endcase
  endfunction
  function automatic logic [15:0] msel(input [1:0] i);
    case (i) 2'd0: msel=merged[15:0]; 2'd1: msel=merged[31:16]; default: msel=merged[47:32]; endcase
  endfunction

  typedef enum logic [1:0] { S_IDLE, S_RD, S_WR, S_FIN } st_t;
  st_t st; logic [2:0] idx;                     // 0..3
  assign active = (st != S_IDLE);

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= S_IDLE; done <= 1'b0; sd_rd <= 1'b0; sd_wr <= 1'b0; idx <= 3'd0;
      o0 <= 16'h0; o1 <= 16'h0; o2 <= 16'h0;
    end else begin
      done <= 1'b0;
      case (st)
        S_IDLE: begin
          sd_rd <= 1'b0; sd_wr <= 1'b0;
          if (req) begin
            we_l<=we; wi<=widx; bo<=boff; szl<=sz; wd_l<=wd;
            o0<=16'h0; o1<=16'h0; o2<=16'h0;
            idx <= 3'd0; st <= S_RD;             // every access reads first (read / RMW)
          end
        end
        S_RD: begin
          if (idx >= ntouch) begin               // window captured
            sd_rd <= 1'b0;
            if (we_l) begin idx <= 3'd0; st <= S_WR; end else st <= S_FIN;
          end else if (!vsel(idx[1:0])) begin    // OOB entry reads as 0
            case (idx[1:0]) 2'd0:o0<=16'h0; 2'd1:o1<=16'h0; default:o2<=16'h0; endcase
            idx <= idx + 3'd1;
          end else if (sd_ack) begin
            case (idx[1:0]) 2'd0:o0<=sd_dout; 2'd1:o1<=sd_dout; default:o2<=sd_dout; endcase
            sd_rd <= 1'b0; idx <= idx + 3'd1;
          end else begin
            sd_addr <= RAM_BASE + wsel(idx[1:0]); sd_be <= 2'b00; sd_rd <= 1'b1;
          end
        end
        S_WR: begin
          if (idx >= ntouch) begin
            sd_wr <= 1'b0; st <= S_FIN;
          end else if (!vsel(idx[1:0])) begin    // OOB entry -> drop write
            idx <= idx + 3'd1;
          end else if (sd_ack) begin
            sd_wr <= 1'b0; idx <= idx + 3'd1;
          end else begin
            sd_addr <= RAM_BASE + wsel(idx[1:0]); sd_din <= msel(idx[1:0]); sd_be <= 2'b11; sd_wr <= 1'b1;
          end
        end
        S_FIN: begin
          rdata <= 32'((win >> bo) & rmask);     // read result (ignored for writes)
          done  <= 1'b1;
          st    <= S_IDLE;
        end
        default: st <= S_IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire

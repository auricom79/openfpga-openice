/*  Smash T.V. — VRAM DDR3 agent (Phase 0: single-beat write + burst read loopback).

    Owns the DE10-Nano HPS DDR3 f2h_sdram1 Avalon master (the DDRAM_* port) for the
    Y-unit VRAM. Folds the two HARDWARE-PROVEN Night Slashers v1.3 FSMs into one agent:
      - write handshake  = jtnslasher_objld.v S_WR   (hold WE until !busy; burstcnt=1)
      - burst read + beat = jtnslasher_objddr.v F_REQ/F_RCV (hold RD until !busy, then
        consume exactly BURSTCNT dout_ready beats).

    Phase 0 is a bring-up LOOPBACK: a tst_* request interface writes a 64-bit word and
    reads it back, proving the Avalon handshake, the {4'd3,...} region, and the no-CDC
    clocking against a FAITHFUL behavioral DDR3 model (sim/ddr3_avalon_model.sv). The
    tst_burstcnt input lets the same agent issue the multi-beat read P1's scanout row-
    burst will need.

    CLOCKING (verified sys_top.v:603,1811 + sysmem.sv:203,325,311,421-423): the emu drives
    DDRAM_CLK = clk_sys, and that same clock feeds the whole ram1 f2sdram bridge + safe-
    terminator. So this agent runs on clk (=clk_sys) with the DDR port in the SAME domain
    -> NO CDC (unlike NS which ran objddr on clk_rom). RESET = sdram_por (P0022 power-on),
    NOT the core reset, so the persistent DDR path keeps running across ioctl_download.

    ADDRESS UNITS (NS + jtframe_ddr_model): DDRAM_ADDR is a 64-bit-BEAT index (8 bytes/word),
    +1 per beat. VRAM_DDR_BASE = 29'h6400000 = byte 0x32000000 (800 MB), region nibble 4'd3,
    clear of NS obj0 (0x30000000) / obj1 (0x31000000). tst_addr is the beat offset within the
    VRAM window; the agent adds VRAM_DDR_BASE.
*/
`default_nettype none
module stv_vram_ddr_agent #(
    parameter [28:0] VRAM_DDR_BASE = 29'h6400000   // byte 0x32000000, region {4'd3,...}
)(
    input wire             clk,          // = clk_sys (96 MHz); DDR port shares this domain (no CDC)
    input wire             sdram_por,    // P0022 power-on reset (active high), NOT core rst

    // ---- request interface (single-OUTSTANDING; writes now BURST-capable) ----
    input wire             tst_wr_req,   // pulse: write BURST of tst_burstcnt beats @ (BASE+tst_addr)
    input wire             tst_rd_req,   // pulse: read tst_burstcnt beats from (VRAM_DDR_BASE+tst_addr)
    input wire      [25:0] tst_addr,     // beat offset within the VRAM DDR window
    input wire      [63:0] tst_wdata,    // 64-bit write payload
    input wire      [ 7:0] tst_be,       // byte-enable for the write (8'hFF = full word)
    input wire      [ 7:0] tst_burstcnt, // burst length for READ or WRITE (>=1; 1 = single beat)
    output reg [63:0] tst_rdata,    // captured read beat (updated each returned beat)
    output reg        tst_rd_valid, // 1-cycle pulse when tst_rdata holds a fresh beat
    output reg        tst_busy,     // agent mid-transaction (write pending OR read draining)
    // Persistent write-retirement metadata. These signals are reset only by sdram_por, like the
    // agent itself, so the scan publication tracker cannot lose a write when core rst interrupts
    // L2 after the bridge has accepted the command. tst_wr_done means bridge acceptance, not DRAM
    // publication; the caller must still read back the final address/data before exposing scanout.
    output reg        tst_wr_done,
    output reg [25:0] tst_wr_base,
    output reg [ 7:0] tst_wr_count,
    output reg [63:0] tst_wr_last_data,
    // WRITE-BURST streaming (Avalon requires a valid beat every !busy cycle): the caller
    // presents the CURRENT beat on tst_wdata (FWFT/show-ahead); each tst_wnext pulse = that
    // beat was accepted -> present the NEXT beat by the following cycle. Only meaningful
    // while tst_busy for a write burst. For a 1-beat write it never pulses.
    output wire       tst_wnext,

    // ---- DDR3 Avalon master (widths per Arcade-SmashTV.sv:77-86 / NS objddr/objld) ----
    output reg [28:0] ddram_addr,     // Avalon beat address
    output reg [ 7:0] ddram_burstcnt, // beats in this transaction
    output reg        ddram_rd,       // read request, held until !busy (objddr F_REQ)
    output reg        ddram_we,       // write request, held until !busy (objld S_WR)
    output wire[63:0] ddram_din,      // write data (comb from tst_wdata during a burst)
    output reg [ 7:0] ddram_be,       // write byte-enable
    input wire             ddram_busy,     // Avalon waitrequest: master must not change cmd while high
    input wire      [63:0] ddram_dout,     // read data, valid only when ddram_dout_ready
    input wire             ddram_dout_ready// read data-valid, one pulse per beat
);

    localparam ST_IDLE=3'd0, ST_WR=3'd1, ST_RD_REQ=3'd2, ST_RD_RCV=3'd3, ST_WRB=3'd4;
    reg [2:0] state;
    reg [63:0] ddram_din_r;   // single-beat / idle write data (registered)
    reg [7:0] beat;     // read beats consumed
    reg [7:0] bcnt;     // latched burst length for the read
    // during a burst the slave takes the FWFT head every !busy cycle; else the reg path
    assign ddram_din = (state == ST_WRB) ? tst_wdata : ddram_din_r;
    // pop the FWFT source the SAME cycle a beat is accepted (comb, so din tracks in time).
    // Gate on ddram_we too (a beat transfers only on we && !waitrequest) so the phantom first
    // ST_WRB cycle (we not yet asserted) never pops the source — matches the accept gate below.
    assign tst_wnext = (state == ST_WRB) && ddram_we && !ddram_busy && (beat != bcnt - 8'd1);
    always @(posedge clk) begin
        if (sdram_por) begin
            state <= ST_IDLE; beat <= 8'd0; bcnt <= 8'd1;
            ddram_addr <= 29'd0; ddram_burstcnt <= 8'd1;
            ddram_rd <= 1'b0; ddram_we <= 1'b0; ddram_din_r <= 64'd0; ddram_be <= 8'hFF;
            tst_rdata <= 64'd0; tst_rd_valid <= 1'b0; tst_busy <= 1'b0;
            tst_wr_done <= 1'b0; tst_wr_base <= 26'd0; tst_wr_count <= 8'd1;
            tst_wr_last_data <= 64'd0;
        end else begin
            // defaults (re-raised inside states as needed) — matches NS objddr:121 / objld:58
            ddram_rd     <= 1'b0;
            ddram_we     <= 1'b0;
            tst_rd_valid <= 1'b0;
            tst_wr_done  <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (tst_wr_req) begin
                        ddram_addr <= VRAM_DDR_BASE + {3'd0, tst_addr};
                        ddram_be   <= tst_be;
                        tst_busy   <= 1'b1;
                        tst_wr_base  <= tst_addr;
                        tst_wr_count <= (tst_burstcnt == 8'd0) ? 8'd1 : tst_burstcnt;
                        if (tst_burstcnt <= 8'd1) begin        // single beat (backward compat)
                            ddram_din_r    <= tst_wdata;
                            ddram_burstcnt <= 8'd1;
                            state          <= ST_WR;
                        end else begin                          // WRITE BURST (lfbuf protocol)
                            ddram_burstcnt <= tst_burstcnt;     // beats presented ONCE, slave auto-incs addr
                            bcnt           <= tst_burstcnt;
                            beat           <= 8'd0;
                            state          <= ST_WRB;          // ddram_din = tst_wdata (comb) from here
                        end
                    end else if (tst_rd_req) begin
                        // guard burstcnt==0 (illegal on the real port): treat as 1 beat so the
                        // beat counter can never wrap to 0xFF and stall the agent 256 beats.
                        ddram_addr     <= VRAM_DDR_BASE + {3'd0, tst_addr};
                        ddram_burstcnt <= (tst_burstcnt == 8'd0) ? 8'd1 : tst_burstcnt;
                        bcnt           <= (tst_burstcnt == 8'd0) ? 8'd1 : tst_burstcnt;
                        beat           <= 8'd0;
                        ddram_rd       <= 1'b1;          // raise RD (registered; seen next cycle)
                        tst_busy       <= 1'b1;
                        state          <= ST_RD_REQ;
                    end
                end
                ST_WR: begin                              // objld S_WR: hold WE until accepted
                    ddram_we <= 1'b1;
                    if (ddram_we && !ddram_busy) begin
                        ddram_we <= 1'b0; tst_busy <= 1'b0; state <= ST_IDLE;
                        tst_wr_last_data <= ddram_din_r; tst_wr_done <= 1'b1;
                    end
                end
                ST_WRB: begin                             // WRITE BURST: hold WE, one beat / !busy cycle
                    ddram_we <= 1'b1;                      // held across the whole burst
                    // Gate the accept on ddram_we (registered) being ACTUALLY asserted, like ST_WR
                    // does — NOT on !ddram_busy alone. In the first ST_WRB cycle ddram_we is still 0
                    // (raised for next cycle), and a slave/arbiter that reports !busy in that cycle
                    // (wolf_ddr3_arb drives busy=a_req=0 when this side is ungranted AND we hasn't
                    // asserted yet) would otherwise be counted as a PHANTOM beat0 -> the agent runs
                    // one beat ahead of the slave and tears down early, so the slave's final beat
                    // commits stale din. The bare model holds busy=1 when idle so it hid this; the
                    // arb seam exposed it (tb_wolf_replay_contend tail-beat shift after the arb fix).
                    if (ddram_we && !ddram_busy) begin     // slave took ddram_din(=tst_wdata head) THIS cycle
                        if (beat == bcnt - 8'd1) begin     // last beat accepted
                            ddram_we <= 1'b0; tst_busy <= 1'b0; state <= ST_IDLE;
                            tst_wr_last_data <= tst_wdata; tst_wr_done <= 1'b1;
                        end
                        beat <= beat + 8'd1;               // tst_wnext (comb) already popped the source
                    end
                end
                ST_RD_REQ: begin                          // objddr F_REQ: hold RD until !busy
                    if (ddram_busy) ddram_rd <= 1'b1;
                    else            state    <= ST_RD_RCV;
                end
                ST_RD_RCV: begin                          // objddr F_RCV: consume BURSTCNT beats
                    if (ddram_dout_ready) begin
                        tst_rdata    <= ddram_dout;
                        tst_rd_valid <= 1'b1;
                        if (beat == bcnt - 8'd1) begin
                            tst_busy <= 1'b0; state <= ST_IDLE;
                        end
                        beat <= beat + 8'd1;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire

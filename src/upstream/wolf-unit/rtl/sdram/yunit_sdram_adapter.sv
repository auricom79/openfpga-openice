// yunit_sdram_adapter.sv — bridges the yunit arbiter's single-word SDRAM port (held
// request sd_rd/sd_wr until sd_ack) to the stock Sorgelig sdram_stock controller (edge-
// triggered we/rd + a `ready` level that drops on accept and rises on completion).
//
// Arbiter word address -> controller BYTE address: ctl_addr = {sd_addr[23:0], 1'b0}
// (16-bit accesses need addr[0]=0; SmashTV never uses word 2^24+). Read data is valid
// when the controller's `ready` rises after the request; we latch it and pulse sd_ack.
// startup_done latches the controller's first `ready` (init complete) -> sdram_ready.
`timescale 1ns/1ps
`default_nettype none
module yunit_sdram_adapter (
  input  logic         clk,
  input  logic         rst,
  // arbiter side (drop-in for the old sdram_phy port)
  input  logic [24:0]  sd_addr,   // WORD address
  input  logic [15:0]  sd_din,
  input  logic [1:0]   sd_be,
  input  logic         sd_rd,
  input  logic         sd_wr,
  output logic [15:0]  sd_dout,
  output logic         sd_ack,
  output logic         sdram_ready,   // sticky: controller finished power-up init
  // stock controller side
  output logic [24:0]  ctl_addr,
  output logic [15:0]  ctl_din,
  output logic [1:0]   ctl_wtbt,
  output logic         ctl_rd,
  output logic         ctl_we,
  input  logic [15:0]  ctl_dout,
  input  logic         ctl_ready
);
  logic startup_done;
  typedef enum logic [1:0] { A_IDLE, A_SETTLE, A_WAIT, A_ACK } astate_t;
  astate_t astate;

  always_ff @(posedge clk) begin
    if (rst) begin
      astate <= A_IDLE; ctl_rd <= 1'b0; ctl_we <= 1'b0; sd_ack <= 1'b0; startup_done <= 1'b0;
    end else begin
      sd_ack <= 1'b0; ctl_rd <= 1'b0; ctl_we <= 1'b0;      // pulses / defaults
      if (ctl_ready) startup_done <= 1'b1;                  // first ready = init done (sticky)
      case (astate)
        A_IDLE:
          if ((sd_rd | sd_wr) & ctl_ready & startup_done) begin
            ctl_addr <= {sd_addr[23:0], 1'b0};              // word -> byte, addr[0]=0
            ctl_din  <= sd_din;
            ctl_wtbt <= sd_be;
            ctl_rd   <= sd_rd;                              // 1-cycle pulse -> rising edge
            ctl_we   <= sd_wr;
            astate   <= A_SETTLE;
          end
        A_SETTLE: astate <= A_WAIT;                         // let `ready` drop on accept
        A_WAIT:                                             // ready rises -> op complete
          if (ctl_ready) begin
            sd_dout <= ctl_dout;                            // read data valid at ready
            sd_ack  <= 1'b1;                                // 1-cycle ack to the arbiter
            astate  <= A_ACK;
          end
        A_ACK: astate <= A_IDLE;                            // arbiter drops req + bubbles
      endcase
    end
  end

  assign sdram_ready = startup_done;
endmodule
`default_nettype wire

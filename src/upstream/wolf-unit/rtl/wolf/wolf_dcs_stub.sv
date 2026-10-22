// wolf_dcs_stub.sv -- minimal host-mailbox model for the deferred UMK3 DCS core.
// It models the input/output latch status at io_r case 4 (host address 0x0187FFC0)
// and the one boot-time response needed by the Wolf main program.
//
// SCOPE: host latches plus the measured UMK3 version transaction only. There is no DAC or
// ADSP-2105 execution -- that remains the separate effort at D:/deck/fpga/umk3/dcs-core.
// wolf_pic.sv (the other half of this same io_r case-4 word, bits[15:12]) is untouched.
//
// ---- Gospel (mame-gospel/dcs/dcs.cpp) ----
// dcs_audio_device::control_r() (dcs.cpp:1442-1453) returns m_latch_control directly for our
// board: UMK3/midwunit.cpp:654 instantiates DCS_AUDIO_8K -> dcs_audio_device(..., REV_DCS1)
// (dcs.cpp:2509); the REV_DCS1P5 special case at dcs.cpp:1450 ("== 1 check breaks mk3") does
// NOT apply to REV_DCS1, so the full m_latch_control passes through unmodified (this matches
// the comment already in wolf_top.sv that this stub replaces).
//   LCTRL_OUTPUT_EMPTY = 0x400  (bit10)     LCTRL_INPUT_EMPTY = 0x800  (bit11)   (dcs.cpp:174-175)
//
// Host WRITE path (a sound-command byte): midwunit_m.cpp:379 sound_w() -> dcs.data_w() (only
// ACCESSING_BITS_0_7) -> dcs_delayed_data_w() (dcs.cpp:1503-1520) which:
//   - asserts the ADSP's IRQ2 (NOT modeled here -- no ADSP core in this project)
//   - SET_INPUT_FULL()  (dcs.cpp:1516)                 -> clears bit11 (INPUT_EMPTY -> 0)
// wolf_mem.sv already taps this host write 1:1 as the `snd_data_wr` 1-clk strobe
// (wolf_mem.sv:1213-1216, R_SOUND region == 0x01680000, midwunit_m.cpp:379).
//
// "DCS side" consume (the ADSP reading the byte back out): dcs_audio_device::device_start()
// (dcs.cpp:789) sets `m_auto_ack = true` for the "non-RAM based" board class -- DCS_AUDIO_8K/
// REV_DCS1 (our board) is exactly this class (contrast dcs2_audio_device::device_start(),
// dcs.cpp:852, which defaults m_auto_ack=false for the RAM-based DCS2/DSIO/DENVER boards used
// by OTHER Midway titles, not UMK3). With auto_ack, input_latch_r() (dcs.cpp:1555-1564) itself
// calls input_latch_ack_w() (dcs.cpp:1544-1552) -> SET_INPUT_EMPTY() the INSTANT the (real,
// UNMODELED) ADSP-2105 executes that read -- i.e. driven by real ADSP interrupt-latency +
// firmware timing this project does NOT emulate (that's dcs-core's job, not this one).
//
// We deliberately do NOT fabricate an ADSP-2105 cycle count for that latency (no gospel citation
// exists for "how many core clocks until the ADSP gets to it" without actually running the ADSP).
// Instead: ACK_DELAY is a small, explicit, NAMED constant -- long enough that a back-to-back host
// poll CAN occasionally still observe INPUT-FULL (this is what the real board does: measured in
// mame-gospel/trace/measure_inputs.txt, the io_r case-4 poll at 34010 PC FFB5A310 (true
// instruction start FFB5A2E0, see the MOVE @187FFC4h,A1 3-word decode) saw val=1400 (bit11=0,
// INPUT FULL) ONCE and val=1C00 (bit11=1, idle) TWICE across 3 reads during the char-select
// portrait build) -- but it is explicitly NOT claimed to be ADSP-cycle-exact.
//
// Reset: dcs_reset() (dcs.cpp:572-593) unconditionally does SET_INPUT_EMPTY()+SET_OUTPUT_EMPTY()
// (dcs.cpp:585-586) -> idle (0xC00). wolf_mem's `snd_reset` is a LEVEL, active-HIGH "DCS held in
// reset" signal (io_w case1: `snd_reset <= wd_q[4]`, wolf_mem.sv) that corresponds to the
// held-reset state. MAME passes ~D[4] to reset_w(), whose input polarity is opposite the
// active-HIGH reset line used here: D[4]=1 calls reset_w(0) and holds the ADSP, while D[4]=0
// calls reset_w(1) and releases it. So: while snd_reset is asserted, force idle; it only starts
// reacting to writes once released (matching the gospel: reset_w(1) CLEAR_LINEs the ADSP).
//
// ---- Measured UMK3 boot/version transaction ----
// mame-gospel/trace/bootera_real.txt records the real board-facing sequence:
//   host writes 03,E7; status becomes 0x800 (input empty, output full); host reads 02;
//   status returns to 0xC00; host continues with 04,3D.
// NBA Hangtime's same-hardware source independently identifies decimal track 999 (0x03E7) as
// the revision request (nba-hangtime/SRC/DIAG.ASM:748-775). The response byte 0x02 is therefore
// the smallest measured proxy that lets UMK3 complete its sound-version diagnostic while the
// full DCS remains deferred. data_r() auto-ack empties the output latch (dcs.cpp:1626-1639).
`default_nettype none

module wolf_dcs_stub #(
  parameter int ACK_DELAY = 4   // core clocks the input latch stays FULL after a write before the
                                 // modeled auto-ack fires. A deliberately-small, NAMED approximation
                                 // of dcs.cpp's m_auto_ack path -- NOT an ADSP-2105 cycle count.
)(
  input  logic        clk,
  input  logic         rst,         // core power-on reset
  input  logic         snd_reset,   // wolf_mem's DCS reset line (active-HIGH = held in reset)
  input  logic         snd_data_wr, // 1-clk strobe: host wrote a sound-command byte (wolf_mem.sv:1216)
  input  logic [7:0]   snd_data_i,  // byte written by the host
  input  logic         snd_data_rd, // 1-clk strobe: host consumed snd_rdata
  output logic [7:0]   snd_rdata,   // dcs.data_r() proxy
  output logic [15:0]  snd_stat     // -> io_r case4 low 12 bits (dcs.control_r(), dcs.cpp:1452)
);

  localparam int CW = (ACK_DELAY <= 1) ? 1 : $clog2(ACK_DELAY + 1);
  localparam logic [CW-1:0] ACK_LOAD = (ACK_DELAY <= 1) ? {CW{1'b0}} : ACK_DELAY - 1;

  logic               input_full;   // 1 = INPUT_EMPTY bit currently CLEAR (latch full/unconsumed)
  logic               output_full;  // 1 = OUTPUT_EMPTY bit currently CLEAR (reply available)
  logic [CW-1:0]      ack_cnt;
  logic [7:0]         prev_cmd;
  logic [7:0]         output_data;
  logic               reply_pending;

  always_ff @(posedge clk) begin
    if (rst || snd_reset) begin
      // dcs_reset() (dcs.cpp:585-586): SET_INPUT_EMPTY()+SET_OUTPUT_EMPTY().
      input_full    <= 1'b0;
      output_full   <= 1'b0;
      ack_cnt       <= '0;
      prev_cmd      <= 8'h00;
      output_data   <= 8'hFF;
      reply_pending <= 1'b0;
    end else begin
      // data_r() with auto-ack consumes the DCS-to-host output latch.
      if (snd_data_rd)
        output_full <= 1'b0;

      if (snd_data_wr) begin
        // dcs_delayed_data_w() (dcs.cpp:1516): SET_INPUT_FULL(). A fresh write always
        // re-arms the countdown and replaces the input byte.
        input_full    <= 1'b1;
        ack_cnt       <= ACK_LOAD;
        reply_pending <= (prev_cmd == 8'h03) && (snd_data_i == 8'hE7);
        prev_cmd      <= snd_data_i;
      end else if (input_full) begin
        if (ack_cnt == '0) begin
          input_full <= 1'b0;                       // modeled input auto-ack
          if (reply_pending) begin
            output_data   <= 8'h02;
            output_full   <= 1'b1;                  // output_latch_w(): SET_OUTPUT_FULL
            reply_pending <= 1'b0;
          end
        end else begin
          ack_cnt <= ack_cnt - 1'b1;
        end
      end
    end
  end

  // Bits[15:12] are wolf_top's PIC status and are not ours to drive.
  assign snd_stat  = {4'h0, ~input_full, ~output_full, 10'h000};
  assign snd_rdata = output_full ? output_data : 8'hFF;

endmodule

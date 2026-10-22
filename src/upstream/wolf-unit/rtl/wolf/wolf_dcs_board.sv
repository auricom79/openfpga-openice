// wolf_dcs_board.sv -- UMK3 DCS host-board wrapper around the standalone
// synthesizable ADSP-2105 core. The host interface follows the Hangtime/Open
// Ice assembly contract: byte-at-a-time commands, status bits 10/11, a real
// output-read acknowledgment, and an active-high board reset.
//
// The ADSP core drains an autobuffer quickly into dac_ce/dac_sample once a
// 31.25 kHz slot says a buffer half is due. That burst is an internal transfer,
// not the external DAC waveform, so this wrapper queues it and exposes one
// signed mono sample per slot. A 1024-sample FIFO provides four 256-sample
// halves of headroom without changing the core's producer timing.
`default_nettype none
module wolf_dcs_board #(
    parameter integer CLK_HZ = 80000000,
    parameter integer DCS_CORE_HZ = 32000000,
    parameter DCS_PMFILE = "pm.hex",
    parameter integer PCM_AW = 10,      // 1024 samples
    // Fade the first 2^N samples after each board reset. At DCS1's 31.25 kHz
    // rate the default is 32.768 ms. This is a one-shot de-click envelope,
    // not a cabinet-volume or permanent PCM gain control.
    parameter integer STARTUP_RAMP_BITS = 10,
    // A live Wolf host-reset can arrive while the external DAC is holding a
    // non-zero sample. Decay that held sample over 2^N DAC slots instead of
    // cutting it to zero on an arbitrary 80 MHz clock.
    parameter integer RESET_FADE_BITS = 8
) (
    input  logic        clk,
    input  logic        rst,

    // Main-CPU side (wolf_memsys sound taps)
    input  logic        host_reset,     // active high: DCS held/reset
    input  logic        host_cmd_wr,
    input  logic [7:0]  host_cmd_data,
    input  logic        host_resp_rd,
    output logic [7:0]  host_resp_data,
    output logic [15:0] host_status,

    // Packed U2|U3|U4|U5 sound-ROM beat port (4 MB / 8 = 2^19 beats)
    output logic        rom_req,
    output logic [18:0] rom_addr,
    input  logic        rom_rdy,
    input  logic [63:0] rom_q,

    output logic signed [15:0] audio,

    // Bring-up observability. These are passive taps and do not alter the
    // board contract or the DSP execution path.
    output logic        dbg_valid,
    output logic        dbg_unimpl,
    output logic        dbg_pcm_push,
    output logic [13:0] dbg_pc
);
    localparam integer DAC_DIV = CLK_HZ / 31250;
    localparam integer PCM_N   = 1 << PCM_AW;

    logic [15:0] host_response;
    logic [13:0] dcs_ppc;
    logic        dcs_valid, dcs_unimpl;
    logic [15:0] dcs_sample;
    logic        dcs_sample_we;
    logic [15:0] dcs_status;

    // The fitted Wolf system clock is 80 MHz. Keep the instruction-atomic ADSP
    // model at its planned 32 MHz average enable rate with a phase accumulator
    // (2 enables per 5 clocks at 80 MHz; 1 per 3 at a 96 MHz sim override).
    // This is a clock enable, not a generated clock domain.
    // Reduce the constant rational rate before elaborating the accumulator.
    // p_original = GCD * p_reduced at every reachable edge, including reset;
    // therefore the comparator and every enabled cycle remain identical.
    function automatic integer phase_rate_gcd(input integer a, input integer b);
        integer remainder;
        begin
            while (b != 0) begin
                remainder = a % b;
                a = b;
                b = remainder;
            end
            phase_rate_gcd = a;
        end
    endfunction
    // Outside the intended positive sub-clock rate, retain the original
    // arithmetic scaling rather than silently alter parameter behavior.
    localparam integer DCS_PHASE_GCD =
        (DCS_CORE_HZ > 0 && DCS_CORE_HZ < CLK_HZ) ?
        phase_rate_gcd(CLK_HZ, DCS_CORE_HZ) : 1;
    localparam integer DCS_PHASE_MOD_INT = CLK_HZ / DCS_PHASE_GCD;
    localparam integer DCS_PHASE_W = $clog2(DCS_PHASE_MOD_INT);
    localparam logic [DCS_PHASE_W:0] DCS_PHASE_STEP = DCS_CORE_HZ / DCS_PHASE_GCD;
    localparam logic [DCS_PHASE_W:0] DCS_PHASE_MOD  = DCS_PHASE_MOD_INT;
    logic [DCS_PHASE_W-1:0] dcs_phase;
    logic [DCS_PHASE_W:0] dcs_phase_sum;
    wire dcs_ce = (dcs_phase_sum >= DCS_PHASE_MOD);
    always_comb dcs_phase_sum = {1'b0, dcs_phase} + DCS_PHASE_STEP;
    always_ff @(posedge clk) begin
        if (rst)
            dcs_phase <= '0;
        else if (dcs_ce)
            dcs_phase <= dcs_phase_sum - DCS_PHASE_MOD;
        else
            dcs_phase <= dcs_phase_sum[DCS_PHASE_W-1:0];
    end

    // A clock-enable, not another clock domain. The fitted 80 MHz clock gives
    // 80,000,000 / 31,250 = 2,560 clocks per output sample exactly.
    logic [$clog2(DAC_DIV)-1:0] dac_div_ctr;
    wire dac_slot_ce = (dac_div_ctr == DAC_DIV-1);
    always_ff @(posedge clk) begin
        if (rst)
            dac_div_ctr <= '0;
        else if (dac_slot_ce)
            dac_div_ctr <= '0;
        else
            dac_div_ctr <= dac_div_ctr + 1'b1;
    end

    // A DAC slot is a one-clk event. Hold a slot that lands in the inactive
    // half of the DCS CE cadence until the next ADSP step; a slot that is
    // already aligned is consumed immediately and is not replayed.
    logic dac_slot_pending;
    wire  dcs_dac_ce = dac_slot_ce | dac_slot_pending;
    always_ff @(posedge clk) begin
        if (rst)
            dac_slot_pending <= 1'b0;
        else if (dac_slot_ce)
            dac_slot_pending <= !dcs_ce;
        else if (dcs_ce)
            dac_slot_pending <= 1'b0;
    end

    // Main-CPU mailbox strobes are one clk wide. Hold the request internally,
    // but present it to the ADSP for exactly ONE dcs_ce-aligned clock. The ADSP
    // mailbox sampler itself runs on every clk (architectural execution alone
    // is CE-gated), so exposing cmd_pending as a level duplicates every byte.
    logic       cmd_pending, resp_rd_pending;
    logic [7:0] cmd_pending_data;
    always_ff @(posedge clk) begin
        if (rst || host_reset) begin
            cmd_pending     <= 1'b0;
            cmd_pending_data <= 8'h00;
            resp_rd_pending <= 1'b0;
        end else begin
            if (host_cmd_wr) begin
                cmd_pending      <= 1'b1;
                cmd_pending_data <= host_cmd_data;
            end else if (cmd_pending && dcs_ce)
                cmd_pending <= 1'b0;

            if (host_resp_rd)
                resp_rd_pending <= 1'b1;
            else if (resp_rd_pending && dcs_ce)
                resp_rd_pending <= 1'b0;
        end
    end

    adsp2105 #(
        .PMFILE(DCS_PMFILE), .EXT_ROM(1), .CORE_CE_EN(1), .PCM_STREAM(1)
    ) u_adsp (
        .clk(clk), .rst(rst), .core_ce(dcs_ce), .host_rst(host_reset),
        .host_cmd_w(cmd_pending && dcs_ce), .host_cmd_data({8'h00, cmd_pending_data}),
        .host_status_r(dcs_status), .host_response_r(host_response),
        .host_resp_rd(resp_rd_pending && dcs_ce),
        .rom_ddr_req(rom_req), .rom_ddr_addr(rom_addr),
        .rom_ddr_rdy(rom_rdy), .rom_ddr_q(rom_q),
        .dac_ce_in(dcs_dac_ce),
        .o_ppc(dcs_ppc), .o_valid(dcs_valid), .o_unimpl(dcs_unimpl),
        .dac_sample(dcs_sample), .dac_ce(dcs_sample_we)
    );
    assign host_resp_data = host_response[7:0];
    assign host_status = dcs_status;
    assign dbg_valid = dcs_valid;
    assign dbg_unimpl = dcs_unimpl;
    assign dbg_pcm_push = dcs_sample_we;
    assign dbg_pc = dcs_ppc;

    // Producer (ADSP drain) and consumer (external DAC slot) share clk. The
    // core has no backpressure pin, so retain a generous power-of-two queue;
    // overflow should be impossible at the measured producer/consumer rate.
    logic [15:0] pcm_fifo [0:PCM_N-1];
    logic [PCM_AW-1:0] pcm_wp, pcm_rp;
    logic [PCM_AW:0]   pcm_used;
    wire pcm_push = dcs_sample_we && (pcm_used != PCM_N);
    wire pcm_pop  = dac_slot_ce && (pcm_used != 0);

    localparam logic [STARTUP_RAMP_BITS:0] STARTUP_GAIN_FULL =
        {1'b1, {STARTUP_RAMP_BITS{1'b0}}};
    logic [STARTUP_RAMP_BITS:0] startup_gain;
    wire signed [15:0] pcm_head = $signed(pcm_fifo[pcm_rp]);
    wire signed [STARTUP_RAMP_BITS+1:0] startup_gain_signed =
        $signed({1'b0, startup_gain});
    wire signed [STARTUP_RAMP_BITS+17:0] startup_product =
        pcm_head * startup_gain_signed;

    logic host_reset_d;
    logic reset_fade_active;
    logic [15:0] reset_fade_step;
    localparam logic [16:0] RESET_FADE_ROUND =
        (17'd1 << RESET_FADE_BITS) - 1'b1;
    wire [16:0] reset_fade_magnitude =
        audio[15] ? ({1'b0, ~audio} + 1'b1) : {1'b0, audio};
    // Ceiling division guarantees bounded convergence even for low-level
    // samples, while using only a shift and add (no second audio multiplier).
    wire [16:0] reset_fade_rounded =
        reset_fade_magnitude + RESET_FADE_ROUND;
    wire [15:0] reset_fade_step_next =
        reset_fade_rounded >> RESET_FADE_BITS;

    always_ff @(posedge clk) begin
        if (rst) begin
            pcm_wp   <= '0;
            pcm_rp   <= '0;
            pcm_used <= '0;
            audio    <= '0;
            startup_gain <= '0;
            host_reset_d <= 1'b0;
            reset_fade_active <= 1'b0;
            reset_fade_step <= '0;
        end else begin
            host_reset_d <= host_reset;

            // Capture the actual held DAC level on the rising edge.  The
            // fade continues even if the host-reset strobe is short.
            if (host_reset && !host_reset_d) begin
                if (audio != 0) begin
                    reset_fade_active <= 1'b1;
                    reset_fade_step <= reset_fade_step_next;
                end else begin
                    reset_fade_active <= 1'b0;
                    reset_fade_step <= '0;
                end
            end

            if (host_reset) begin
                pcm_wp   <= '0;
                pcm_rp   <= '0;
                pcm_used <= '0;
                startup_gain <= '0;
            end else begin
                if (pcm_push) begin
                    pcm_fifo[pcm_wp] <= dcs_sample;
                    pcm_wp <= pcm_wp + 1'b1;
                end
                if (pcm_pop) begin
                    // While the old held sample fades, consume new DSP output
                    // without publishing it. This keeps the FIFO bounded and
                    // lets the ordinary startup ramp begin from exact silence.
                    if (!reset_fade_active) begin
                        if (startup_gain != STARTUP_GAIN_FULL) begin
                            audio <= startup_product >>> STARTUP_RAMP_BITS;
                            // ADVANCE ON AUDIBLE SAMPLES, NOT ON DAC SLOTS
                            // (2026-07-27, cabinet: loud blip when the DCS comes
                            // online, all seven Wolf titles).
                            //
                            // This counter used to increment on EVERY pcm_pop,
                            // i.e. every 31.25 kHz slot from board reset. MEASURED
                            // with real Open Ice firmware booting from the sound
                            // ROM (sim/run_wolf_dcs_boot_samples.sh): the DSP
                            // pushes 0 non-silent samples in the first 4096 slots.
                            // So the envelope reached FULL GAIN after 1024 slots
                            // (32.768 ms) while the DSP was still silent, and by
                            // the time real audio arrived it was published
                            // unramped -- the de-click envelope expired before the
                            // event it exists to cover.
                            //
                            // Gating the increment on a non-zero sample makes the
                            // envelope cover the first 1024 AUDIBLE samples, which
                            // is what STARTUP_RAMP_BITS was always documented to
                            // mean. During silent boot the gain holds at 0 and the
                            // published sample is 0 * pcm_head = silence, so
                            // nothing is delayed or attenuated that was audible.
                            if (pcm_head != 16'sh0000)
                                startup_gain <= startup_gain + 1'b1;
                        end else begin
                            // Full-gain bypass is exact: normal game audio is
                            // not multiplied or attenuated after startup.
                            audio <= pcm_head;
                        end
                    end
                    pcm_rp <= pcm_rp + 1'b1;
                end
                unique case ({pcm_push, pcm_pop})
                    2'b10: pcm_used <= pcm_used + 1'b1;
                    2'b01: pcm_used <= pcm_used - 1'b1;
                    default: ;
                endcase
            end

            // This assignment has priority over a coincident FIFO pop. Audio
            // therefore changes only at the external 31.25 kHz DAC cadence.
            if (reset_fade_active && dac_slot_ce) begin
                if (!audio[15]) begin
                    if ({1'b0, audio} <= {1'b0, reset_fade_step}) begin
                        audio <= '0;
                        reset_fade_active <= 1'b0;
                    end else begin
                        audio <= $signed(audio) -
                                 $signed({1'b0, reset_fade_step});
                    end
                end else begin
                    if (reset_fade_magnitude <= {1'b0, reset_fade_step}) begin
                        audio <= '0;
                        reset_fade_active <= 1'b0;
                    end else begin
                        audio <= $signed(audio) +
                                 $signed({1'b0, reset_fade_step});
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire

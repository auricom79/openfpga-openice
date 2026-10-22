// wolf_ddr3_arb.sv — 2-way grant-held Avalon arbiter sharing the ONE physical HPS DDR3 port
// (DDRAM_*) between two independent single-outstanding requesters: VRAM (stv_vram_ddr_top,
// priority — per-frame-deadline scanout traffic) and GFX (wolf_gfx_ddr_top — best-effort
// blit-time reads + one-time boot-copy writes). Each requester subsystem embeds its OWN
// stv_vram_ddr_agent instance and believes it owns the whole Avalon master; this module sits
// between them and the physical port so they don't collide. Grant-held (matches the SDRAM
// arbiter's proven style throughout this project): once a side is granted, it keeps the port
// until ITS OWN rd/we request line drops (the underlying agent is single-outstanding, so a
// held grant spans exactly one full transaction). While NOT granted, a side's busy is tied
// HIGH (never falsely completes) and dout_ready tied low.
`default_nettype none
module wolf_ddr3_arb #(
    parameter bit HONOR_B_ALLOW = 1'b0
) (
    input  logic         clk,
    input  logic         b_allow,

    // requester A = VRAM (priority)
    input  logic [28:0]  a_addr,
    input  logic [ 7:0]  a_burstcnt,
    input  logic         a_rd,
    input  logic         a_we,
    input  logic [63:0]  a_din,
    input  logic [ 7:0]  a_be,
    output logic         a_busy,
    output logic [63:0]  a_dout,
    output logic         a_dout_ready,

    // requester B = GFX
    input  logic [28:0]  b_addr,
    input  logic [ 7:0]  b_burstcnt,
    input  logic         b_rd,
    input  logic         b_we,
    input  logic [63:0]  b_din,
    input  logic [ 7:0]  b_be,
    output logic         b_busy,
    output logic [63:0]  b_dout,
    output logic         b_dout_ready,

    // physical Avalon master (-> DDRAM_* top-level pins)
    output logic [28:0]  ddram_addr,
    output logic [ 7:0]  ddram_burstcnt,
    output logic         ddram_rd,
    output logic         ddram_we,
    output logic [63:0]  ddram_din,
    output logic [ 7:0]  ddram_be,
    input  logic         ddram_busy,
    input  logic [63:0]  ddram_dout,
    input  logic         ddram_dout_ready
);
    // Grant-hold to TRUE completion, not just the request pulse. The two directions signal
    // "burst done" DIFFERENTLY, so each has its own release condition (latched gnt_wr picks it):
    //   WRITE : the agent HOLDS `we` high across every beat of an Avalon burst write (one beat
    //           streamed per !busy cycle) and drops it the cycle the LAST beat is accepted. So
    //           the correct release is simply "we deasserted." A first cut released on the first
    //           accepted beat (`!ddram_busy` while `we`) — fine for a 1-beat write, but a burst
    //           then de-grants after beat 0, ddram_din/ddram_we fall to the ungranted default 0
    //           while the slave is still streaming -> beats 1..N-1 commit 0000 and the counters
    //           desync (the C-lane W-BURST corruption: consecutive-beat runs shift + tail-zero,
    //           caught by tb_wolf_replay_contend f200, invisible in the agent+model isolation
    //           gate which has no arb seam). A second cut counted !busy beats via beats_left, but
    //           the agent drops `we` ON the last beat's accept cycle, so the counter comes up one
    //           short and wedges the grant in G_A (tb_wolf_ddr3_arb burst-write test). Gating on
    //           we-deassert tracks the agent's own contract exactly — no off-by-one.
    //   READ  : `rd` DROPS the instant the request is ACCEPTED (busy drops while rd=1), then the
    //           agent still needs `burstcnt` dout_ready beats to arrive with rd/we BOTH 0.
    //           Releasing on rd|we drop cuts dout_ready off mid-burst and hangs the requester
    //           (tb_wolf_ddr3_arb: agent stuck in RD_RCV). So track the outstanding beat count
    //           (beats_left, latched at grant) and release only once it reaches zero.
    localparam [1:0] G_NONE=2'd0, G_A=2'd1, G_B=2'd2;
    logic [1:0] gnt;
    logic [7:0] beats_left;
    logic       gnt_wr;      // the current grant is a WRITE (release on we-deassert, not dout_ready)

    wire a_req = a_rd | a_we;
    wire b_req = b_rd | b_we;
    wire b_eligible = !HONOR_B_ALLOW || b_allow;

    always_ff @(posedge clk) begin
        case (gnt)
            G_NONE: begin
                if (a_req) begin
                    gnt <= G_A; gnt_wr <= a_we;
                    if (a_rd) beats_left <= (a_burstcnt == 8'd0) ? 8'd1 : a_burstcnt;
                end else if (b_req && b_eligible) begin
                    gnt <= G_B; gnt_wr <= b_we;
                    if (b_rd) beats_left <= (b_burstcnt == 8'd0) ? 8'd1 : b_burstcnt;
                end
            end
            G_A: begin
                if (gnt_wr) begin                                   // WRITE: hold until the agent drops we
                    if (!a_we) gnt <= G_NONE;
                end else if (ddram_dout_ready) begin               // READ drain: 1 beat / dout_ready
                    if (beats_left <= 8'd1) gnt <= G_NONE;
                    else beats_left <= beats_left - 8'd1;
                end
            end
            G_B: begin
                if (gnt_wr) begin
                    if (!b_we) gnt <= G_NONE;
                end else if (ddram_dout_ready) begin
                    if (beats_left <= 8'd1) gnt <= G_NONE;
                    else beats_left <= beats_left - 8'd1;
                end
            end
            default: gnt <= G_NONE;
        endcase
    end

    always_comb begin
        unique case (gnt)
            G_A: begin
                ddram_addr = a_addr; ddram_burstcnt = a_burstcnt;
                ddram_rd = a_rd; ddram_we = a_we; ddram_din = a_din; ddram_be = a_be;
            end
            G_B: begin
                ddram_addr = b_addr; ddram_burstcnt = b_burstcnt;
                ddram_rd = b_rd; ddram_we = b_we; ddram_din = b_din; ddram_be = b_be;
            end
            default: begin
                ddram_addr = 29'd0; ddram_burstcnt = 8'd0;
                ddram_rd = 1'b0; ddram_we = 1'b0; ddram_din = 64'd0; ddram_be = 8'd0;
            end
        endcase

        // busy=1 only while NOT granted AND actively requesting (make it wait for its turn);
        // busy=0 when idle (a_req/b_req=0) so a completed side's OWN busy latch can clear --
        // holding busy=1 unconditionally when ungranted deadlocks an agent whose tst_busy
        // computation expects busy to eventually drop once it stops requesting (found via sim,
        // not assumed: tb_wolf_ddr3_arb hung with the naive "always busy when ungranted" form).
        a_busy       = (gnt == G_A) ? ddram_busy : a_req;
        a_dout       = ddram_dout;
        a_dout_ready = (gnt == G_A) ? ddram_dout_ready : 1'b0;

        b_busy       = (gnt == G_B) ? ddram_busy : b_req;
        b_dout       = ddram_dout;
        b_dout_ready = (gnt == G_B) ? ddram_dout_ready : 1'b0;
    end
endmodule
`default_nettype wire

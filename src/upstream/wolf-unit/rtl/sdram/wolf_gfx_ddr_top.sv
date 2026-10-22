// wolf_gfx_ddr_top.sv — packed gfx ROM in HPS DDR3, drop-in for wolf_dma's byte-granular
// src_req/src_addr/src_data/src_ack port PLUS the CPU-direct gfx-window read (cgfx, the
// ROM-checksum/self-test path) PLUS the boot-copy download write stream. Follows the
// memory-partition decision (gfx ROM -> DDR3, cold/read-only/burst-friendly, kept off the
// primary SDRAM which is already committed to main RAM + VRAM) and reuses
// stv_vram_ddr_agent.sv VERBATIM — the same proven, FAITHFUL (posted-write,
// cfg_maxburst/cfg_gapevery-hardened) DDR3 Avalon primitive already cab-confirmed on the
// VRAM path, unmodified: it's a generic word-addressed single-outstanding read/write agent.
//
// GFX_DDR_BASE = 29'h6800000 (byte 0x34000000): clear of VRAM_DDR_BASE (29'h6400000 =
// byte 0x32000000, ~512KB footprint) with room to spare inside the region-3 HPS-DDR3
// window (0x30000000-0x3FFFFFFF, {4'd3,...} per stv_vram_ddr_agent's region_check).
//
// ---------------------------------------------------------------------------------------
// RESET DOMAINS (P0022 — the reason this file was rewritten after the first cab flash):
// core reset (rst) is HIGH during the entire ioctl download BY CONSTRUCTION
// (wolf_top core_rst = rst | ~sdram_ready | ioctl_download | ~unp_done). The first cut
// gated the boot-copy write FSM on `rst || !dl_active` -> the write path was FROZEN for
// exactly the window it exists to serve. THE fix P0022 canonized on Smash TV: everything
// that must capture download data lives on sdram_por (2-FF-synced ~locked, LOW during any
// post-lock download); only post-reset CONSUMER-side handshake lines gate on rst.
//   - write front-end + agent owner FSM : sdram_por  (must run while rst is high)
//   - read front-ends (src, cgfx)       : rst        (their requesters don't exist before
//                                                     rst drops; a de-granted mid-flight
//                                                     read is completed + dropped by the
//                                                     owner, never wedged — see below)
//
// ARBITRATION (replaces the first cut's fragile `dl_active` phase latch, which dropped in
// the PLL-lock->HPS-download idle gap and gated the write side off before data arrived):
// per-TRANSACTION priority arb for the ONE single-outstanding agent:
//     download write beat  >  blitter read (src)  >  CPU gfx-window read (cgfx)
// No phase assumptions: writes only occur during download (rst high -> no read requests),
// reads only after, but the arb is safe even if that ever overlapped. The owner FSM runs
// every transaction to TRUE completion (gate-the-FSM-not-the-output: it never sequences on
// a requester that may have been reset away mid-flight — a read whose requester vanished
// completes at the agent and the result is simply dropped).
//
// FIRST CUT (deliberately simple, no cache): each byte request costs one single-beat
// (8-byte) DDR3 read, byte-lane-selected from the 64-bit beat. wolf_dma's field-read
// cadence (S_SKB0/S_SKB1/S_PXB0/S_PXB1, one src_req at a time) and wolf_mem's 6-byte
// window fetch both tolerate arbitrary ack latency by construction. Add a line-cache ONLY
// if a real measurement shows DDR3-starvation (ship-and-measure doctrine).
//
// WRITES = write-combine + RMW FULL-BEAT (be=FF). Two constraints force this shape:
//  (1) The interleave transform makes the download's dest addresses STRIDE-4 (dest =
//      base + chip_off*4 + lane), never densely filling a beat — an "accumulate 8 then
//      commit on addr[2:0]==7" scheme silently drops every lane whose pattern misses ==7
//      (the first cut's bug; its roundtrip TB pushed sequential addresses and missed it).
//  (2) Partial byte-enables DO NOT WORK on this port: f2h_sdram1 DROPS per-byte BE on
//      1-beat writes — CAB-MEASURED on Smash TV (STV P1.5 `8f49cd4`, the reason
//      ddr3_avalon_model has cfg_ignore_be; the VRAM path's RMW+full-beat design is the
//      canonized fix, P1.5+P1.6). So every flush is read-beat -> merge lanes -> write
//      full beat be=FF.
// The write-combine buffer merges the stream's natural same-beat pairs (bytes 2k/2k+1 of
// a chip land in one beat at lanes L and L+4) into ONE RMW per pair; an idle-timeout
// (~64 cycles) flushes a straggler. The posted-write stale-read hazard (STV P1.6) is
// closed by 1-DEEP SAME-BEAT WRITE FORWARDING in the owner FSM: a flush targeting the
// beat of the LAST flush merges against the remembered written data and SKIPS the RMW
// read entirely (never re-read a just-written beat). Depth 1 is sufficient because the
// bridge posts at most one write at a time (a second write forces the first to commit —
// same single-deep model STV P1.6 proved on the cab for the VRAM path). NOTE an earlier
// revision claimed the hazard was "structurally avoided" because a timeout period (64)
// exceeded posting latency — arithmetically FALSE (cfg_write_lat max is 255); the
// adversarial verifier CONFIRMED the stale-read with a differential probe (timeout-split
// pair, gap 150 fails / 400 passes) before this forwarding fix. The e2e TB now drains the
// FIFO first so its timeout-split case truly splits, and runs cfg_write_lat=255 +
// cfg_ignore_be=1 (the measured bridge behavior).
`default_nettype none
module wolf_gfx_ddr_top #(
    parameter [28:0] GFX_DDR_BASE = 29'h6800000,
    parameter bit USE_STREAM_HINT = 1'b0,
`ifdef POCKET
    parameter bit DIRECT_PREFETCH = 1'b1
`else
    parameter bit DIRECT_PREFETCH = 1'b0
`endif
)(
    input  logic         clk,
    input  logic         rst,          // core rst — read front-ends only
    input  logic         sdram_por,    // P0022 power-on reset — agent + write path + owner

    // wolf_dma byte-granular source port (blitter)
    input  logic         src_req,
    input  logic [31:0]  src_addr,     // linear BYTE address into the gfx ROM
    input  logic         src_active,   // unscaled source-consuming command active
    input  logic         src_stream,   // dense unity 8-bpp look-ahead hint
    output logic [7:0]   src_data,
    output logic         src_ack,
    output logic         dcs_safe,     // safe window for a lower-priority DCS beat

    // CPU-direct gfx-window byte read (wolf_mem ext fetch; gfxbank already applied there)
    input  logic         cg_req,
    input  logic [25:0]  cg_addr,      // BYTE address into the gfx ROM (bank offset included)
    output logic [7:0]   cg_data,
    output logic         cg_ack,

    // boot-copy byte-granular write port (already interleave-transformed by the caller)
    input  logic         dl_wr,
    input  logic [24:0]  dl_addr,      // linear BYTE address into the gfx ROM (0..0x1FFFFFF)
    input  logic [7:0]   dl_data,
    output logic         dl_ack,       // pulses once dl_data has been accepted
    output logic         dl_idle,      // combine buffer and DDR owner fully drained

    // observability (DIAG builds; harmless constants otherwise)
    output logic [25:0]  dbg_wbeats,   // committed byte-writes (full umk3 download = 0x1400000)
    output logic [15:0]  dbg_srd,      // completed blitter reads
    output logic [15:0]  dbg_cgrd,     // completed cgfx reads

    // DDR3 Avalon master (widths per Arcade-SmashTV.sv / stv_vram_ddr_agent)
    output logic [28:0]  ddram_addr,
    output logic [ 7:0]  ddram_burstcnt,
    output logic         ddram_rd,
    output logic         ddram_we,
    output logic [63:0]  ddram_din,
    output logic [ 7:0]  ddram_be,
    input  logic         ddram_busy,
    input  logic [63:0]  ddram_dout,
    input  logic         ddram_dout_ready
`ifdef DIAG_FLIP
    ,
    // GFX READ-BACK / content audit (2026-07-12): separate the WRITE side (did the download store
    // the right BYTES, not just the right count) from the READ side (does the blitter get real data
    // back from each region on silicon). dl_cksum = sum of every gfx byte written (diff vs the MAME
    // umk3_gfx.hex byte-sum). grp_read/grp_nz = per-4MB-region {was read, returned non-zero} masks
    // (bit5 = the 0x1400000 group-4 sprite chips). g4_cksum = sum of group-4 bytes the blitter reads.
    output logic [31:0]  dbg_dl_cksum,
    output logic [7:0]   dbg_grp_read,
    output logic [7:0]   dbg_grp_nz,
    output logic [31:0]  dbg_g4_cksum
`endif
);

    logic        tst_rd_req, tst_wr_req;
    logic [25:0] tst_addr;
    logic [63:0] tst_wdata;
    logic [ 7:0] tst_burstcnt;
    logic [63:0] tst_rdata;
    logic        tst_rd_valid, tst_busy;

    stv_vram_ddr_agent #(.VRAM_DDR_BASE(GFX_DDR_BASE)) u_agent (
        .clk(clk), .sdram_por(sdram_por),
        .tst_wr_req(tst_wr_req), .tst_rd_req(tst_rd_req),
        .tst_addr(tst_addr), .tst_wdata(tst_wdata), .tst_be(8'hFF), .tst_burstcnt(tst_burstcnt),
        .tst_rdata(tst_rdata), .tst_rd_valid(tst_rd_valid), .tst_busy(tst_busy),
        .ddram_addr(ddram_addr), .ddram_burstcnt(ddram_burstcnt),
        .ddram_rd(ddram_rd), .ddram_we(ddram_we),
        .ddram_din(ddram_din), .ddram_be(ddram_be),
        .ddram_busy(ddram_busy), .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready));

    // ---- write front-end: write-combine buffer (sdram_por domain) -------------------------
    // Bytes are acked into the combine buffer immediately (register latch); a flush to DDR3
    // (RMW, owner FSM below) triggers when a byte for a DIFFERENT beat arrives or the
    // buffer sits idle for WFLUSH_IDLE cycles. Bytes acked-but-unflushed live only in
    // wc_* — safe: the only reset that can hit mid-download is sdram_por (full restart).
    localparam [7:0] WFLUSH_IDLE = 8'd64;
    logic        wc_valid;
    logic [21:0] wc_beat;      // beat index = dl_addr[24:3]
    logic [7:0]  wc_mask;      // which lanes hold fresh download bytes
    logic [63:0] wc_data;
    logic [7:0]  widle_cnt;
    wire  [21:0] dl_beat  = dl_addr[24:3];
    wire         wc_same  = wc_valid && (dl_beat == wc_beat);
    logic        wr_taking;    // comb, from owner: latching wc_* THIS cycle
    wire         wflush_req = wc_valid &&
                              ((dl_wr && !dl_ack && !wc_same) || (widle_cnt >= WFLUSH_IDLE));
    always_ff @(posedge clk) begin
        if (sdram_por) begin
            wc_valid <= 1'b0; wc_beat <= 22'd0; wc_mask <= 8'd0; wc_data <= 64'd0;
            dl_ack <= 1'b0; widle_cnt <= 8'd0; dbg_wbeats <= 26'd0;
`ifdef DIAG_FLIP
            dbg_dl_cksum <= 32'd0;
`endif
        end else begin
            dl_ack <= 1'b0;
            if (wc_valid && widle_cnt != 8'hFF) widle_cnt <= widle_cnt + 8'd1;
            if (wr_taking) begin
                // owner latched wc_* this edge; clear so the next byte starts fresh.
                // Byte-accept is blocked this cycle (guard below) so nothing merges into
                // a buffer the owner has already copied.
                wc_valid <= 1'b0;
                wc_mask  <= 8'd0;
            end else if (dl_wr && !dl_ack && (!wc_valid || wc_same)) begin
                wc_beat                       <= dl_beat;
                wc_mask[dl_addr[2:0]]         <= 1'b1;
                wc_data[dl_addr[2:0]*8 +: 8]  <= dl_data;
                wc_valid   <= 1'b1;
                dl_ack     <= 1'b1;
                widle_cnt  <= 8'd0;
                dbg_wbeats <= dbg_wbeats + 26'd1;   // bytes accepted (== pushes when clean)
`ifdef DIAG_FLIP
                dbg_dl_cksum <= dbg_dl_cksum + {24'd0, dl_data};   // running byte-sum of the WRITE
`endif
            end
        end
    end

    // ---- read front-ends (rst domain) + 8-byte line cache ---------------------------------
    // THROUGHPUT: the first cut served ONE byte per full DDR3 round-trip (~25-30 cycles).
    // Real Wolf hardware reads gfx ROM 32 bits per access — game code fires blits assuming
    // that speed, so a ~50-100x-slower fetch path leaves big blits still running when the
    // game issues its next command (the cab's snow-then-wedge signature). Fix: ONE 8-byte
    // line (single-beat fill — see LINE SIZE below) shared by src + cgfx. Fetches are sequential,
    // so hits (served in 2 cycles, no DDR3 traffic) dominate ~31/32. The gfx region is
    // read-only after boot — the only writes are the boot-copy flushes, which happen while
    // rst holds the front-ends in reset AND invalidate the line anyway (belt + braces).
    //
    // Handshake: requesters hold req LEVEL until ack and may take a cycle to drop it after
    // the ack pulse — the 1-cycle cooldown prevents re-arming on that stale req (same
    // timing contract as the first cut's A_ACK bubble, proven against wolf_dma in the
    // ddr3-realgfx sim; wolf_mem's M_GFX uses an explicit 1-cycle-gap reissue that matches).
    // LINE SIZE (cab lesson, gfx4): the first cut of this cache filled a 32-byte line with
    // a 4-beat burst read — and the FIRST fill after reset release killed the core on
    // silicon (one glitch frame then eternal black; download clean; every sim gate green).
    // The 4-beat burst on this B-side path is the only post-reset transaction shape the
    // cab had never proven; single-beat reads ran for minutes (gfx2). So: 8-byte line,
    // single-beat fill — the EXACT cab-proven shape — at 7/8 the hit rate. Do not widen
    // the line again without first reproducing the wedge in a hardened bridge model.
    // Current demand line plus four completed sequential prefetch beats.  The
    // depth is deliberately in CACHE STORAGE, not in the Avalon transaction:
    // every fill remains one cabinet-proven 8-byte read.  Keeping 32 bytes of
    // runway lets the owner issue the next single beat before the DMA consumes
    // the preceding line, so a short DCS grant cannot turn every line crossing
    // into a demand stall.
    localparam integer PF_DEPTH = 4;
    logic [PF_DEPTH-1:0] pf_valid;
    logic [21:0] pf_tag [0:PF_DEPTH-1];
    logic [63:0] pf_data [0:PF_DEPTH-1];
    logic [21:0] pf_target;
    logic [2:0]  pf_left;
    logic [2:0]  pf_goal;
    // Keep the DMA and CPU demand lines independent.  Open Ice reads graphics
    // metadata through cgfx while the DMA is consuming long, sequential rink
    // spans.  A shared demand line lets each CPU miss evict the DMA's current
    // beat, turning almost every following source byte into another DDR miss.
    // The physical transaction shape is unchanged: both caches are still
    // filled by one cabinet-proven 8-byte Avalon read.
    logic        src_line_valid;
    logic [21:0] src_line_tag;        // byte_addr[24:3] (one beat)
    logic [63:0] src_line_data;       // 1 beat
    logic        cg_line_valid;
    logic [21:0] cg_line_tag;
    logic [63:0] cg_line_data;
    wire src_hit = src_line_valid && (src_addr[24:3] == src_line_tag);
    logic        src_pf_hit;
    logic [PF_DEPTH-1:0] src_pf_hit_by_slot_w;
    logic [1:0]  src_pf_slot_w;
    logic [63:0] src_pf_data_w;
    always_comb begin
        src_pf_hit = 1'b0;
        src_pf_hit_by_slot_w = '0;
        src_pf_slot_w = 2'd0;
        src_pf_data_w = 64'd0;
        // Every fill writes slot pf_target[1:0]. Thus a valid line's low
        // tag bits equal its slot: this is a direct-mapped cache, even though
        // the original implementation searched all four tags in parallel.
        if (DIRECT_PREFETCH) begin
            src_pf_slot_w = src_addr[4:3];
            // Compare tags before the late slot choice: same direct-mapped
            // truth table, without a 20-bit tag mux before the comparator.
            for (int p = 0; p < PF_DEPTH; p++)
                src_pf_hit_by_slot_w[p] = pf_valid[p] &&
                                         (src_addr[24:5] == pf_tag[p][21:2]);
            src_pf_hit = src_pf_hit_by_slot_w[src_addr[4:3]];
            src_pf_data_w = pf_data[src_addr[4:3]];
        end else for (int p = 0; p < PF_DEPTH; p++) begin
            if (pf_valid[p] && (src_addr[24:3] == pf_tag[p])) begin
                src_pf_hit = 1'b1;
                src_pf_slot_w = p[1:0];
                src_pf_data_w = pf_data[p];
            end
        end
    end
    wire cg_hit  = cg_line_valid && (cg_addr[24:3] == cg_line_tag);

    // TIMING (why the serve path is PIPELINED): packing tag-compare + the 256-bit 32:1
    // byte mux + ack into ONE cycle regressed the build's worst setup slack from -0.765ns
    // (cab-tolerated) to -1.332ns / TNS -70 → instant silicon death (gfx3 cab flash:
    // one frame then black; every cycle-accurate sim green — sims don't model nanoseconds).
    // Stage 1 registers the hit decision + selected byte; stage 2 drives data+ack. Costs
    // one cycle per hit (3-cycle turnaround, still ~10x the round trip) — both consumers
    // tolerate arbitrary latency by construction.
    logic        src_hit_q, cg_hit_q;    // stage-1: hit registered
    logic [24:0] src_qaddr, cg_qaddr;    // stage-1: WHICH address was sampled — the serve
                                         // guard must match the LIVE address, not just see
                                         // "a hit": consecutive addresses share a line, so
                                         // a stale hit bit passes while byte_q still holds
                                         // the PREVIOUS request's byte (the exact one-
                                         // request-lag failure the e2e gate caught: every
                                         // read returned its predecessor's data)
    logic [7:0]  src_byte_q, cg_byte_q;  // stage-1: line byte registered
    logic        src_pend, cg_pend;
    logic        src_cool, cg_cool;
    logic        src_done, cg_done;      // pulses from owner: line fill complete
    logic        src_pf_served;          // registered pulse: front-end consumed a pf line
    logic [1:0]  src_pf_served_slot;
    always_ff @(posedge clk) begin
        if (rst) begin
            src_pend <= 1'b0; cg_pend <= 1'b0;
            src_cool <= 1'b0; cg_cool <= 1'b0;
            src_pf_served <= 1'b0;
            src_pf_served_slot <= 2'd0;
            src_hit_q <= 1'b0; cg_hit_q <= 1'b0;
            src_qaddr <= 25'd0; cg_qaddr <= 25'd0;
            src_byte_q <= 8'h00; cg_byte_q <= 8'h00;
            src_ack <= 1'b0;  cg_ack <= 1'b0;
            src_data <= 8'h00; cg_data <= 8'h00;
            dbg_srd <= 16'd0; dbg_cgrd <= 16'd0;
`ifdef DIAG_FLIP
            dbg_grp_read <= 8'd0; dbg_grp_nz <= 8'd0; dbg_g4_cksum <= 32'd0;
`endif
        end else begin
            src_ack  <= 1'b0;
            cg_ack   <= 1'b0;
            src_pf_served <= 1'b0;
            // Slot is payload for the registered served pulse below. Capture
            // every cycle so the DMA request/kill cone gates only that pulse.
            // All owner uses of this slot require src_pf_served from the same
            // sampling edge; changing the slot with that pulse low is inert.
            src_pf_served_slot <= src_pf_slot_w;
            src_cool <= src_ack;   // cooldown = the cycle AFTER the ack pulse
            cg_cool  <= cg_ack;
            // Payload may follow the live cache selection while ACK is low.
            // Keep the DMA's request/kill cone on the handshake only: a hit
            // captures the same live byte, and a completed miss captures the
            // registered byte selected by the existing pending state.
            src_data <= src_pend ? src_byte_q :
                        (src_hit ? src_line_data[src_addr[2:0]*8 +: 8]
                                 : src_pf_data_w[src_addr[2:0]*8 +: 8]);
            // stage 1: evaluate hit + select the byte + REMEMBER the sampled address
            src_hit_q  <= src_hit;
            cg_hit_q   <= cg_hit;
            src_qaddr  <= src_addr[24:0];
            cg_qaddr   <= cg_addr[24:0];
            src_byte_q <= src_line_data[src_addr[2:0]*8 +: 8];
            cg_byte_q  <= cg_line_data[cg_addr[2:0]*8 +: 8];
            // The cabinet-safe line is now one 64-bit beat, so the DMA's 8:1
            // byte selection can be registered directly on a hit. This removes
            // the obsolete 32-byte-cache pipeline delay while keeping ack/data
            // registered. CPU gfx-window reads retain the guarded two-stage path.
            if (!src_pend && src_req && !src_ack && !src_cool) begin
                if (src_hit || src_pf_hit) begin
                    src_ack  <= 1'b1;
                    // The owner promotes a directly-served prefetch on the
                    // following cycle.  Registering this event keeps the
                    // live DMA address/tag cone out of the owner controls.
                    src_pf_served <= src_pf_hit && !src_hit;
                    dbg_srd  <= dbg_srd + 16'd1;
`ifdef DIAG_FLIP
                    dbg_grp_read[src_addr[24:22]] <= 1'b1;                          // region read
                    if ((src_hit ? src_line_data[src_addr[2:0]*8 +: 8]
                                 : src_pf_data_w[src_addr[2:0]*8 +: 8]) != 8'd0)
                        dbg_grp_nz[src_addr[24:22]] <= 1'b1;                        // returned data
                    if (src_addr[24:22] == 3'd5)
                        dbg_g4_cksum <= dbg_g4_cksum +
                            {24'd0, (src_hit ? src_line_data[src_addr[2:0]*8 +: 8]
                                               : src_pf_data_w[src_addr[2:0]*8 +: 8])};
`endif
                end else src_pend <= 1'b1;
            end
            if (!cg_pend && cg_req && !cg_ack && !cg_cool) begin
                if (cg_hit && cg_hit_q && (cg_qaddr == cg_addr[24:0])) begin
                    cg_data  <= cg_byte_q;
                    cg_ack   <= 1'b1;
                    dbg_cgrd <= dbg_cgrd + 16'd1;
                end else if (!cg_hit) cg_pend <= 1'b1;
            end
            if (src_pend && src_done) begin
                // Post-fill serve: the selected demand line settled last
                // cycle; use the registered byte.
                // path too (src_byte_q was computed from the freshly-filled line last edge)
                src_ack  <= 1'b1; src_pend <= 1'b0;
                dbg_srd  <= dbg_srd + 16'd1;
`ifdef DIAG_FLIP
                dbg_grp_read[src_qaddr[24:22]] <= 1'b1;                          // region read (post-fill)
                if (src_byte_q != 8'd0) dbg_grp_nz[src_qaddr[24:22]] <= 1'b1;
                if (src_qaddr[24:22] == 3'd5) dbg_g4_cksum <= dbg_g4_cksum + {24'd0, src_byte_q};
`endif
            end
            if (cg_pend && cg_done) begin
                cg_data  <= cg_byte_q;
                cg_ack   <= 1'b1; cg_pend <= 1'b0;
                dbg_cgrd <= dbg_cgrd + 16'd1;
            end
        end
    end

    // ---- agent owner FSM (sdram_por domain — must serve flushes while rst is high) --------
    // One transaction at a time, run to TRUE completion. Priority: flush > src > cgfx.
    // Flush = RMW: read the beat, merge the combine-buffer lanes, write the FULL beat
    // (be=FF — partial BE is cab-refuted on this bridge, STV P1.5). If a read's requester
    // was reset away mid-flight (src_pend/cg_pend cleared by rst), the owner still drains
    // the agent to completion and the done pulse lands on nothing.
    localparam [3:0] O_IDLE=4'd0, O_FRD=4'd1, O_FRDW=4'd2, O_FWR=4'd3, O_FWW=4'd4,
                     O_RISSUE=4'd5, O_RWAIT=4'd6, O_GAP=4'd7, O_PISSUE=4'd8, O_PWAIT=4'd9;
    logic [3:0]  ost;
    logic        o_is_src;        // which read port owns the in-flight line fill
    logic        o_done_pend;     // fill finished; pulse done from O_GAP (see O_RWAIT)
    // SRC next-line PREFETCH (fill-path only — the serve pipeline + single-beat fill shape are
    // UNCHANGED, so none of the 3 documented cab-death modes are touched: no burst fill, no serve
    // collapse, no address-guard change). After a src line fills, read the NEXT sequential line into
    // a 1-beat buffer in the background (lowest arb priority). A src miss for that line then PROMOTES
    // it (line <= pf, no DDR3 round-trip), hiding the row-crossing miss latency (own-gfx-inflight,
    // ~29% of the read stall). gfx is read-only post-boot, so a speculative next-line read is safe;
    // a flush to the buffered line invalidates it (belt+braces).
    logic [21:0] o_line;          // line being filled = byte_addr[24:3] (one beat)
    logic [21:0] wl_beat;         // latched flush target
    logic [7:0]  wl_mask;
    logic [63:0] wl_data;
    // 1-deep same-beat write forwarding (STV P1.6): the beat + full data of the LAST
    // completed flush. A new flush to the same beat merges against this and skips the
    // RMW read (whose result could be STALE inside the bridge's write-posting window).
    logic        fwd_valid;
    logic [21:0] fwd_beat;
    logic [63:0] fwd_data;
    // A miss is visible one cycle before src_pend/cg_pend register it.  Keep
    // speculative prefetch from stealing that demand's transaction slot.
    // These signals are used only at prefetch ISSUE arbitration.  They must
    // not control O_PWAIT response registers or direct promotion; those paths
    // are registered below after measured timing failures on the live cone.
    wire src_live_miss_w = src_req && !src_hit && !src_pf_hit;
    wire cg_live_miss_w  = cg_req && !cg_hit;
    wire stream_prefetch_w = USE_STREAM_HINT && src_stream;
    logic       pf_pend_hit_w;
    logic [1:0] pf_pend_slot_w;
    logic [2:0] pf_valid_count_w;
    logic [2:0] pf_valid_after_consume_w;
    logic [2:0] pf_next_goal_w;
    logic [2:0] pf_refill_after_consume_w;
    always_comb begin
        pf_pend_hit_w = 1'b0;
        pf_pend_slot_w = 2'd0;
        pf_valid_count_w = 3'd0;
        for (int p = 0; p < PF_DEPTH; p++) begin
            if (pf_valid[p]) pf_valid_count_w = pf_valid_count_w + 3'd1;
            if (!DIRECT_PREFETCH && pf_valid[p] && (src_qaddr[24:3] == pf_tag[p])) begin
                pf_pend_hit_w = 1'b1;
                pf_pend_slot_w = p[1:0];
            end
        end
        if (DIRECT_PREFETCH) begin
            pf_pend_slot_w = src_qaddr[4:3];
            pf_pend_hit_w = pf_valid[src_qaddr[4:3]] &&
                            (src_qaddr[24:5] == pf_tag[src_qaddr[4:3]][21:2]);
        end
        pf_valid_after_consume_w = (pf_valid_count_w != 3'd0)
                                   ? (pf_valid_count_w - 3'd1) : 3'd0;
        // Start each source run conservatively with the original one-line
        // look-ahead. Only repeated sequential promotions grow the runway
        // (1 -> 2 -> 4), avoiding four wasted reads on short/random sprites.
        if (stream_prefetch_w)
            pf_next_goal_w = (pf_goal < 3'd2) ? 3'd2 : 3'd4;
        else if (USE_STREAM_HINT && src_active)
            pf_next_goal_w = 3'd2;
        else
            pf_next_goal_w = 3'd1;
        if (pf_next_goal_w > pf_valid_after_consume_w)
            pf_refill_after_consume_w =
                pf_next_goal_w - pf_valid_after_consume_w;
        else
            pf_refill_after_consume_w = 3'd0;
    end
    // DCS is normally free to use every idle DDR slot. During a dense source
    // run, wait until at least three completed future lines are buffered; one
    // DCS single-beat transaction can then retire while the DMA consumes that
    // runway instead of destroying the next-line look-ahead.
    assign dcs_safe = !USE_STREAM_HINT || !src_active ||
                      ((pf_left == 3'd0) &&
                       (pf_valid_count_w >= (src_stream ? 3'd3 : 3'd2)));
    // The CPU gfx window shares this owner with the DMA, unlike DCS which is
    // gated by the outer arbiter.  Apply the same runway rule here: CPU reads
    // remain fully available between source runs, and get fair slots during a
    // long run once the next source beats are safely prefetched.
    // ---- STARVATION ESCAPE ---------------------------------------------------
    // MEASURED DEFECT (tb_wolf_gfx_cg_starve.sv, with a valid control):
    //     src_active=1, src_req=0 -> cg NEVER acked in 5,000 cycles
    //     src_active=0 (control)  -> the same cg read acked in 24 cycles
    // src_active stays HIGH through a paused/halted walker -- wolf_dma.sv:833
    // gates src_req off on paused_r / walker_halted_r while busy_r keeps
    // src_active asserted -- but pf_valid_count only grows on SEQUENTIAL source
    // promotions (:416-419). With no promotions arriving the runway sits at
    // pf_goal=1 / pf_valid_count=1 / pf_left=0, so the (>= 3) term above is
    // PERMANENTLY UNREACHABLE and the CPU gfx window is starved indefinitely.
    // Production-reachable: a mid-blit DGO=0 pause on an 8-bpp unscaled command.
    //
    // GATE THE EDGE, NOT THE STATE. The guard exists to protect an ACTIVELY
    // CONSUMING run's look-ahead; a guard that holds for an entire MODE becomes
    // a deadlock in a mode that is never left. So track whether the source is
    // really consuming rather than merely active: if no source request has
    // arrived for SRC_IDLE_MAX cycles the run is stalled, there is no
    // look-ahead left to protect, and the CPU must be served. During a genuine
    // dense run src_req recurs every few cycles and never reaches the bound, so
    // the runway protection is unchanged.
    // (Class note: this is the 4th "predicate a legal transition makes
    // permanently false" in this family -- NARC's B_DRAIN livelock, Wolf's flip
    // drain discard, this, and Open Ice's own DMA queue-count underflow.)
    localparam int SRC_IDLE_MAX = 16;
    logic [4:0] src_idle_cnt;
    always_ff @(posedge clk) begin
        if (sdram_por)                     src_idle_cnt <= 5'd0;
        else if (!src_active || src_req)   src_idle_cnt <= 5'd0;
        else if (src_idle_cnt < SRC_IDLE_MAX[4:0])
                                           src_idle_cnt <= src_idle_cnt + 5'd1;
    end
    wire src_stalled_w = (src_idle_cnt >= SRC_IDLE_MAX[4:0]);
    // NOTE: dcs_safe carries the same structural exposure, but DCS is gated by
    // the outer arbiter and its starvation has NOT been measured. Not changing
    // an unmeasured path -- flagged for a separate, gated fix.
    wire cg_safe_w = !USE_STREAM_HINT || !src_active || dcs_safe || src_stalled_w;
    // The two promotion branches are mutually exclusive. Select their slot
    // before reading the wide payload/tag rather than duplicating both muxes.
    wire [1:0] pf_promote_slot_w = (src_pf_served && pf_valid[src_pf_served_slot])
                                     ? src_pf_served_slot : pf_pend_slot_w;
    wire [63:0] pf_promote_data_w = pf_data[pf_promote_slot_w];
    wire [21:0] pf_promote_tag_w = pf_tag[pf_promote_slot_w];
    assign wr_taking = (ost == O_IDLE) && wflush_req;
    always_ff @(posedge clk) begin
        if (sdram_por) begin
            ost <= O_IDLE; o_is_src <= 1'b0; o_done_pend <= 1'b0; o_line <= 22'd0;
            wl_beat <= 22'd0; wl_mask <= 8'd0; wl_data <= 64'd0;
            fwd_valid <= 1'b0; fwd_beat <= 22'd0; fwd_data <= 64'd0;
            pf_valid <= '0; pf_target <= 22'd0; pf_left <= 3'd0; pf_goal <= 3'd1;
            for (int p = 0; p < PF_DEPTH; p++) begin
                pf_tag[p] <= 22'd0;
                pf_data[p] <= 64'd0;
            end
            src_line_valid <= 1'b0; src_line_tag <= 22'd0; src_line_data <= 64'd0;
            cg_line_valid <= 1'b0; cg_line_tag <= 22'd0; cg_line_data <= 64'd0;
            tst_rd_req <= 1'b0; tst_wr_req <= 1'b0;
            src_done <= 1'b0; cg_done <= 1'b0;
        end else begin
            tst_rd_req <= 1'b0;
            tst_wr_req <= 1'b0;
            src_done <= 1'b0;
            cg_done  <= 1'b0;
            case (ost)
                O_IDLE: begin
                    if (wflush_req) begin   // wr_taking: snapshot the buffer this edge
                        wl_beat <= wc_beat; wl_mask <= wc_mask;
                        if (fwd_valid && (wc_beat == fwd_beat)) begin
                            // FORWARDING HIT: merge against the beat we just wrote —
                            // re-reading it from DDR3 inside the posting window would
                            // return STALE data and the be=FF write-back would erase the
                            // previous flush's bytes (verifier-confirmed, gap-150 probe).
                            for (int i = 0; i < 8; i++)
                                wl_data[8*i +: 8] <= wc_mask[i] ? wc_data[8*i +: 8]
                                                                : fwd_data[8*i +: 8];
                            ost <= O_FWR;   // skip the RMW read
                        end else begin
                            wl_data <= wc_data;
                            ost <= O_FRD;
                        end
                    end
                    // !done guards: after a fill, done pulses one cycle before the front-
                    // end's pend clear becomes visible here — granting on that stale pend
                    // launches a spurious REFILL of the just-served address, and its
                    // eventual done then serves the NEXT request from the WRONG line
                    // (found via tb_cg_probe: every post-first cg fill served the previous
                    // line's byte; the e2e gate caught it as 100% cg mismatches).
                    else if (src_pf_served && pf_valid[src_pf_served_slot]) begin
                        // The front-end served a prefetched line on the
                        // preceding edge. Promote it, retain the other future
                        // lines, and refill the one consumed slot. A jump into
                        // the window discards the now-behind entries and starts
                        // a fresh four-line runway.
                        src_line_data <= (DIRECT_PREFETCH ? pf_promote_data_w : pf_data[src_pf_served_slot]);
                        src_line_valid <= 1'b1;
                        src_line_tag <= (DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[src_pf_served_slot]);
                        if (src_line_valid &&
                            ((DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[src_pf_served_slot]) == (src_line_tag + 22'd1))) begin
                            pf_valid[src_pf_served_slot] <= 1'b0;
                            pf_goal <= pf_next_goal_w;
                            pf_left <= pf_refill_after_consume_w;
                        end else begin
                            pf_valid <= '0;
                            pf_target <= (DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[src_pf_served_slot]) + 22'd1;
                            pf_left <= 3'd1;
                            pf_goal <= 3'd1;
                        end
                    end
                    else if (src_pend && !src_done) begin
                        o_is_src <= 1'b1; o_line <= src_qaddr[24:3];
                        if (pf_pend_hit_w) begin  // PROMOTE a prefetched line (no DDR3 read)
                            src_line_data <= (DIRECT_PREFETCH ? pf_promote_data_w : pf_data[pf_pend_slot_w]);
                            src_line_valid <= 1'b1;
                            src_line_tag <= (DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[pf_pend_slot_w]);
                            if (src_line_valid &&
                                ((DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[pf_pend_slot_w]) == (src_line_tag + 22'd1))) begin
                                pf_valid[pf_pend_slot_w] <= 1'b0;
                                pf_goal <= pf_next_goal_w;
                                pf_left <= pf_refill_after_consume_w;
                            end else begin
                                pf_valid <= '0;
                                pf_target <= src_qaddr[24:3] + 22'd1;
                                pf_left <= 3'd1;
                                pf_goal <= 3'd1;
                            end
                            o_done_pend <= 1'b1; ost <= O_GAP;
                        end else ost <= O_RISSUE;
                    end
                    else if (cg_pend && !cg_done && cg_safe_w) begin
                        o_is_src <= 1'b0;
                        o_line <= cg_addr[24:3];
                        ost <= O_RISSUE;
                    end
                    // Lowest priority: extend the sequential runway. Each
                    // transaction remains exactly one 8-byte Avalon read.
                    else if ((pf_left != 3'd0) && !src_live_miss_w &&
                             !(cg_live_miss_w && cg_safe_w))
                        ost <= O_PISSUE;
                end
                // flush RMW: read the shared beat...
                O_FRD:  begin tst_rd_req <= 1'b1; ost <= O_FRDW; end
                O_FRDW: if (tst_rd_valid) begin
                    // ...merge: fresh lanes keep the download bytes, others the DDR3 beat
                    for (int i = 0; i < 8; i++)
                        if (!wl_mask[i]) wl_data[8*i +: 8] <= tst_rdata[8*i +: 8];
                    ost <= O_FWR;
                end
                // ...and write the FULL beat back (be=FF)
                O_FWW:  if (!tst_busy && !tst_wr_req) begin
                    fwd_valid <= 1'b1;      // remember the beat just written (full data)
                    fwd_beat  <= wl_beat;
                    fwd_data  <= wl_data;
                    // a flush may write into the cached line — invalidate (front-ends are
                    // in reset during downloads anyway; this is belt + braces)
                    if (src_line_valid && (wl_beat == src_line_tag))
                        src_line_valid <= 1'b0;
                    if (cg_line_valid && (wl_beat == cg_line_tag))
                        cg_line_valid <= 1'b0;
                    for (int p = 0; p < PF_DEPTH; p++)
                        if (pf_valid[p] && (wl_beat == pf_tag[p])) pf_valid[p] <= 1'b0;
                    ost <= O_GAP;
                end
                O_FWR:  begin tst_wr_req <= 1'b1; ost <= O_FWW; end
                // Demand-line fill: ONE single-beat read into the selected
                // source or CPU cache.
                // Single-beat is deliberate — the cab-proven transaction shape (see header).
                O_RISSUE: begin tst_rd_req <= 1'b1; ost <= O_RWAIT; end
                O_RWAIT: if (tst_rd_valid) begin
                    if (o_is_src) begin
                        src_line_data  <= tst_rdata;
                        src_line_valid <= 1'b1;
                        src_line_tag   <= o_line;
                        // An uncached demand establishes a new sequential
                        // window; old prefetched lines belong to the preceding
                        // source run and must not consume runway slots.
                        pf_valid <= '0;
                        pf_target <= o_line + 22'd1;
                        pf_left <= 3'd1;
                        pf_goal <= 3'd1;
                    end else begin
                        cg_line_data  <= tst_rdata;
                        cg_line_valid <= 1'b1;
                        cg_line_tag   <= o_line;
                    end
                    o_done_pend <= 1'b1;   // done pulses from O_GAP, one cycle later —
                                           // the pipelined serve path (src/cg_byte_q)
                                           // needs the fresh line visible one full
                                           // cycle before the done-triggered serve
                    ost <= O_GAP;
                end
                O_GAP: begin            // 1-cyc bubble: lets pend/ack/byte_q settle
                    if (o_done_pend) begin
                        if (o_is_src) src_done <= 1'b1;
                        else          cg_done  <= 1'b1;
                        o_done_pend <= 1'b0;
                    end
                    ost <= O_IDLE;
                end
                // background next-line prefetch: ONE single-beat read into the pf buffer (no done
                // pulse — it serves no requester; the eventual PROMOTE in O_IDLE does the serve).
                O_PISSUE: begin
                    // A request can arrive after O_IDLE selected prefetch but
                    // before the DDR command is issued. Yield without traffic.
                    if (wflush_req || src_pend || src_live_miss_w ||
                        ((cg_pend || cg_live_miss_w) && cg_safe_w))
                        ost <= O_IDLE;
                    else begin
                        tst_rd_req <= 1'b1;
                        ost <= O_PWAIT;
                    end
                end
                O_PWAIT:  if (tst_rd_valid) begin
                    // If a registered demand caught an already-issued
                    // prefetch for this exact line, promote it immediately.
                    // A same-edge fresh demand is deliberately stored in the
                    // pf buffer first and promoted from O_IDLE next cycle;
                    // that rare bubble keeps live DMA address/tag logic out of
                    // this response register's enable path.
                    if (src_pend && (src_qaddr[24:3] == pf_target)) begin
                        src_line_data <= tst_rdata;
                        src_line_valid <= 1'b1;
                        src_line_tag <= pf_target;
                        pf_valid <= '0;
                        pf_target <= pf_target + 22'd1;
                        pf_left <= 3'd1;
                        pf_goal <= 3'd1;
                        o_is_src <= 1'b1;
                        o_done_pend <= 1'b1;
                        ost <= O_GAP;
                    end else begin
                        pf_data[pf_target[1:0]] <= tst_rdata;
                        pf_tag[pf_target[1:0]] <= pf_target;
                        pf_valid[pf_target[1:0]] <= 1'b1;
                        pf_target <= pf_target + 22'd1;
                        if (pf_left != 3'd0) pf_left <= pf_left - 3'd1;
                        ost <= O_IDLE;
                    end
                end
                default: ost <= O_IDLE;
            endcase
        end
    end

    // agent request mux: flush states target the latched beat; line fills read the line's
    // beat. EVERYTHING is single-beat (burstcnt pinned 1) — see the line-size cab lesson.
    wire fsel = (ost == O_FRD) || (ost == O_FRDW) || (ost == O_FWR) || (ost == O_FWW);
    wire psel = (ost == O_PISSUE) || (ost == O_PWAIT);
    assign tst_addr     = fsel ? {4'd0, wl_beat} : psel ? {4'd0, pf_target} : {4'd0, o_line};
    assign tst_burstcnt = 8'd1;
    assign tst_wdata    = wl_data;
    assign dl_idle      = !wc_valid && (ost == O_IDLE) && !tst_busy
                        && !tst_rd_req && !tst_wr_req;
endmodule
`default_nettype wire

// stv_vram_ddr_top.sv — VRAM-in-DDR3 subsystem (P1). Drop-in for vram_sdram_top: same
// accessor ports, but VRAM lives in the HPS DDR3 (f2h_sdram1) — freeing the SDRAM port so
// the scanout no longer starves the CPU.
//
// INCREMENT 2 (this file): the scanout is now served by a ROW-BURST CACHE (the bandwidth win).
// yunit_scanline still issues one scan_req per
// column; on the first miss of a row the cache bursts the WHOLE row (128 beats = 512 entries)
// from DDR3 in ONE transaction, then serves every column of that row from a 128x64b BRAM at a
// ~2-clk hit. So a line costs ~1 burst instead of 512 single reads.
//
// Three requesters share the single DDR3 agent (single-outstanding), muxed by a grant-held L2
// arbiter (scanout burst = priority; it is real-time but rare — once per row):
//   A = the proven vram_sdram_top (CPU field RMW + blitter fb + autoerase) with its scanout
//       port tied off; its single 16-bit sd_* word port is translated to single-beat DDR3
//       accesses via the 4:1 packing (entry>>2 = beat, entry[1:0] = lane, 2-byte lane BE).
//   B = the scanout row cache: burst-fills a row, serves scan_req from cache.
//   C = the blitter write combiner/FIFO: full-beat burst drains plus guarded partial RMW.
//   D = the SRT (TMS34010 shift-register-transfer, P0027 sideband) row-pair engine:
//       latch  = 256-beat burst READ (1024 entries = 2 VRAM rows) into a 256x64 buffer,
//       transfer = 256-beat burst WRITE of that buffer — both in <=BMAX-beat sub-bursts
//       (the B-side fill pattern). D parks behind a drained C combiner/FIFO and an idle
//       A accessor (a_block conventions), is outranked by B, fires the scan-cache
//       invalidation with its true 2-row span on transfers, participates in wr_busy,
//       and issues through the SAME agent so the tst_wr_done scan fence sees its writes.
//
// 4:1 packing: entry = (row<<9)|col ; beat = entry>>2 ; lane = entry[1:0]. A 512-entry row =
// 128 contiguous beats at beat_base = row<<7. Reset: accessor engines + A/B/L2 on core rst;
// the persistent DDR agent on sdram_por (P0022).
`default_nettype none
module stv_vram_ddr_top #(
`ifdef POCKET
    parameter bit CACHED_FIFO_RUN = 1'b1,
    parameter bit MLAB_WRITE_FIFO = 1'b1,
`else
    parameter bit CACHED_FIFO_RUN = 1'b0,
    parameter bit MLAB_WRITE_FIFO = 1'b0,
`endif
    parameter int VRAMW = 32'h40000,
    parameter [28:0] VRAM_DDR_BASE = 29'h6400000,
    parameter int POSTED_WRITE_GUARD = 255
)(
    input  logic         clk,
    input  logic         rst,
    input  logic         sdram_por,
    // CPU field access
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
    // blitter framebuffer write
    input  logic         fb_we,
    input  logic [18:0]  fb_addr,
    input  logic [15:0]  fb_wdata,
    output logic         fb_ack,
    output logic         wr_busy,     // write path still draining (combiner/FIFO/C-lane) — for the blit-done handshake
    output logic [2:0]   dbg_cst,     // DIAG: C-lane drain FSM state (C_IDLE/C_RD/C_MRG/C_WR/C_BURST) — pin the wedge point
    // autoerase sweep
    input  logic         erase_start,
    input  logic [8:0]   erase_row0,
    input  logic [9:0]   erase_lines,
    output logic         erase_busy,
    // video scanout read
    input  logic         scan_req,
    input  logic [18:0]  scan_addr,
    output logic [15:0]  scan_data,
    output logic         scan_ack,
    // SRT (shift-register-transfer) row-pair op — P0027 sideband, D lane.
    // srt_req is a 1-cycle pulse (like the accessor req); srt_entry is the base ENTRY
    // index (= CPU word index << 1; the caller guarantees beat alignment, entry[1:0]==0).
    // srt_we=0: LATCH — burst-read 1024 entries into the row buffer; srt_e0e1 returns
    // {entry base+1, entry base+0} for the caller's A0033 rdata. srt_we=1: TRANSFER —
    // burst-write the buffer to 1024 entries at srt_entry. srt_done pulses when the op
    // has retired to the agent (write fully accepted / read fully returned).
    input  logic         srt_req,
    input  logic         srt_we,
    input  logic [18:0]  srt_entry,
    output logic         srt_done,
    output logic [31:0]  srt_e0e1,
    // DDR3 Avalon master
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
    function automatic logic [7:0] lane_be(input [1:0] l);
        case (l) 2'd0: lane_be=8'h03; 2'd1: lane_be=8'h0C; 2'd2: lane_be=8'h30; default: lane_be=8'hC0; endcase
    endfunction

    // ================= A: proven accessors (scanout tied off) -> single 16b sd_* port =========
    logic [20:0] sd_addr;  logic [15:0] sd_din;  logic [1:0] sd_be;  logic sd_rd, sd_wr;
    logic [15:0] sd_dout;  logic sd_ack;
    vram_sdram_top #(.VRAMW(VRAMW), .SD_AW(21), .VRAM_BASE(21'd0)) u_acc (
        .clk(clk), .rst(rst),
        .req(req), .we(we), .widx(widx), .boff(boff), .sz(sz), .wd(wd),
        .videobank(videobank), .dma_palette(dma_palette), .rdata(rdata), .done(done),
        .fb_we(1'b0), .fb_addr(19'd0), .fb_wdata(16'd0), .fb_ack(),   // W-THRU2: fb bypasses the sd path
        .erase_start(erase_start), .erase_row0(erase_row0), .erase_lines(erase_lines), .erase_busy(erase_busy),
        .scan_req(1'b0), .scan_addr(19'd0), .scan_data(), .scan_ack(),
        .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_rd(sd_rd), .sd_wr(sd_wr),
        .sd_dout(sd_dout), .sd_ack(sd_ack) );

    // A-side request to the L2 arbiter (levels held until *_done)
    logic        a_start, a_wr;
    logic [25:0] a_addr;
    logic [63:0] a_wdata;
    logic [ 7:0] a_be;
    logic        a_done, a_rd_valid;   // driven by L2
    logic [63:0] a_rdata;              // driven by L2
    logic [1:0]  a_lane;
    logic [15:0] rmw_din;              // write data held across the read-modify-write
    logic [63:0] rmw_beat;             // the beat being merged (DDR read OR the write-forward copy)
    // WRITE = READ-MODIFY-WRITE of the shared 64-bit beat (4 VRAM entries/beat), be=FF, PLUS a 1-deep
    // WRITE/READ FORWARD of the last beat this side wrote. Two silicon hazards motivate it:
    //   (a) BE: a masked single-beat write relies on the bridge honoring per-byte write-enables on a
    //       1-beat burst, which the real f2h_sdram1 does NOT -> full-beat be=FF write instead.
    //   (b) POSTED WRITES: the bridge accepts a write before the data lands, so a per-entry RMW that
    //       RE-READS the beat for the next entry can read STALE DDR data and clobber the neighbor.
    //       This failed the cab's VRAM self-test ("RAM CHIPS BAD"): the game writes all 4 entries of
    //       every beat back-to-back. FORWARDING makes same-beat accesses use the local copy (fwd_beat)
    //       instead of re-reading DDR -> correct independent of commit latency. The full-beat write
    //       still goes to DDR every time (persist + scanout). Sim's DDR model commits instantly so it
    //       exposed NEITHER hazard -- the same charitable-oracle gap for both.
    wire  [63:0] rmw_merged = (a_lane==2'd0) ? {rmw_beat[63:16], rmw_din}
                            : (a_lane==2'd1) ? {rmw_beat[63:32], rmw_din, rmw_beat[15:0]}
                            : (a_lane==2'd2) ? {rmw_beat[63:48], rmw_din, rmw_beat[31:0]}
                            :                  {rmw_din, rmw_beat[47:0]};
    logic [63:0] fwd_beat;             // local copy of the last beat this side wrote
    logic [25:0] fwd_addr;  logic fwd_valid;
    // C keeps the equivalent copy for framebuffer writes. Both paths consult both
    // copies so a posted A->C or C->A update to adjacent lanes cannot restore old DDR.
    logic [63:0] c_fwd;  logic [16:0] c_fwd_beat;  logic c_fwd_v;
    wire         a_own_fwd_hit = fwd_valid && (fwd_addr == a_addr);
    wire         c_to_a_fwd_hit = c_fwd_v && (c_fwd_beat == a_addr[16:0]);
    wire         fwd_hit = a_own_fwd_hit || c_to_a_fwd_hit;
    wire [63:0]  a_fwd_data = a_own_fwd_hit ? fwd_beat : c_fwd;
    localparam [2:0] A_IDLE=3'd0, A_DRAIN=3'd1, A_WAIT=3'd2, A_ACK=3'd3,
                     A_RMW_RD=3'd4, A_RMW_MRG=3'd5;
    logic [2:0] ats;
    logic       a_op_wr;
    logic       c_busy;
    logic       c_start, c_wr;         // C-lane request to L2 (declared here: the A FSM
                                       // below consumes them — ModelSim requires
                                       // declaration before use; body in the C section)
    wire        a_block = (ats != A_IDLE); // park new C writes until this accessor op completes
    // ATOMIC RMW: the CPU RMW is read-then-write across TWO L2 grants; A drops a_start between
    // them (L2 bubbles to IDLE). Without a lock, C (higher L2 priority than A) can WRITE the very
    // beat A just read into its rmw_beat -> A's write-back then clobbers C with the stale base.
    // Single-beat C drains a 1-beat window (rarely lands on A's beat); an 8-beat burst holds the
    // port long enough to reliably hit it (contention-gate DATA corruption, 2026-07-11). a_rmw_lock
    // spans read-done -> write-accepted and makes A outrank C in the L2 (B/scanout still outranks A).
    logic a_rmw_lock;
    always_ff @(posedge clk) begin
        if (rst) begin
            ats<=A_IDLE; a_start<=1'b0; a_wr<=1'b0; a_addr<=26'd0; a_wdata<=64'd0; a_be<=8'd0;
            a_lane<=2'd0; rmw_din<=16'd0; rmw_beat<=64'd0; sd_ack<=1'b0; sd_dout<=16'd0;
            fwd_beat<=64'd0; fwd_addr<=26'd0; fwd_valid<=1'b0; a_rmw_lock<=1'b0; a_op_wr<=1'b0;
        end else begin
            sd_ack <= 1'b0;
            // W-THRU2: a C (fb-combine) write can supersede the beat A remembers;
            // never let A merge a CPU RMW into a stale forward copy.
            if (c_start && c_wr) fwd_valid <= 1'b0;
            case (ats)
                A_IDLE: begin
                    if (sd_rd || sd_wr) begin
                        // Capture the accessor request, then drain/park C before deciding whether
                        // to forward or read DDR. Deciding here races a C write that is still queued.
                        a_lane<=sd_addr[1:0]; a_addr<={9'd0,sd_addr[18:2]};
                        rmw_din<=sd_din; a_op_wr<=sd_wr; ats<=A_DRAIN;
                    end
                end
                A_DRAIN: begin
                    if (!c_busy) begin
                        if (!a_op_wr && fwd_hit) begin  // READ-FORWARD: newest accepted write
                            case (a_lane)
                                2'd0: sd_dout<=a_fwd_data[15:0]; 2'd1: sd_dout<=a_fwd_data[31:16];
                                2'd2: sd_dout<=a_fwd_data[47:32]; default: sd_dout<=a_fwd_data[63:48];
                            endcase
                            sd_ack<=1'b1; ats<=A_ACK;
                        end else if (!a_op_wr) begin
                            a_wr<=1'b0; a_start<=1'b1; ats<=A_WAIT;
                        end else if (fwd_hit) begin     // WRITE-FORWARD: merge newest accepted write
                            rmw_beat<=a_fwd_data; a_rmw_lock<=1'b1; ats<=A_RMW_MRG; // lock C out of this beat too
                        end else begin
                            a_wr<=1'b0; a_start<=1'b1; a_rmw_lock<=1'b1; ats<=A_RMW_RD;
                        end
                    end
                end
                A_WAIT: begin                   // completion of a plain READ (sd_rd) OR the RMW full-beat WRITE
                    if (a_rd_valid) case (a_lane)
                        2'd0: sd_dout<=a_rdata[15:0]; 2'd1: sd_dout<=a_rdata[31:16];
                        2'd2: sd_dout<=a_rdata[47:32]; default: sd_dout<=a_rdata[63:48];
                    endcase
                    if (a_done) begin a_start<=1'b0; a_wr<=1'b0; a_rmw_lock<=1'b0; sd_ack<=1'b1; ats<=A_ACK; end
                end
                A_RMW_RD: begin                 // RMW step 1: read the shared beat from DDR (miss, a_wr=0)
                    if (a_rd_valid) rmw_beat<=a_rdata;
                    // LOCK A above C now: the merged write-back MUST land before any C write to this
                    // beat. a_start still drops for the 1-cyc bubble, but a_rmw_lock keeps C out.
                    if (a_done) begin a_start<=1'b0; a_rmw_lock<=1'b1; ats<=A_RMW_MRG; end
                end
                A_RMW_MRG: begin                // RMW step 2: merge the lane, write the FULL beat + remember it
                    a_wdata<=rmw_merged; a_be<=8'hFF; a_wr<=1'b1; a_start<=1'b1; ats<=A_WAIT;
                    fwd_beat<=rmw_merged; fwd_addr<=a_addr; fwd_valid<=1'b1;
                end
                A_ACK: ats<=A_IDLE;            // 1-cyc bubble so sd_rd/sd_wr clear
                default: ats<=A_IDLE;
            endcase
        end
    end

    // ================= B: scanout row-burst cache ============================================
    (* ramstyle="no_rw_check" *) logic [63:0] rc [0:127];   // one row = 128 beats x 4 entries
    logic [9:0]  rc_row;  logic rc_valid;
    logic [9:0]  b_fill_row;              // row latched for all sub-bursts of one fill
    logic        b_fill_dirty;            // a writer touched this row while it was filling
    logic        cache_wr_evt;
    logic [9:0]  cache_wr_row0, cache_wr_row1;
    wire         rc_write_hit = cache_wr_evt &&
                                ((rc_row == cache_wr_row0) || (rc_row == cache_wr_row1));
    wire         fill_write_hit = cache_wr_evt &&
                                  ((b_fill_row == cache_wr_row0) || (b_fill_row == cache_wr_row1));
    wire  [9:0]  req_row = scan_addr[18:9];   // continuous (NOT `logic = ...`, which is init-only)
    wire  [8:0]  req_col = scan_addr[8:0];
    logic [63:0] rc_q;  wire [6:0] rc_raddr = req_col[8:2];  logic [1:0] rc_rlane;
    always_ff @(posedge clk) rc_q <= rc[rc_raddr];          // reads the CURRENT scan col's beat (1 clk)

    logic        b_start;
    logic [25:0] b_addr;
    logic [7:0]  b_burstlen;           // per-sub-burst length (to L2)
    logic        b_done, b_rd_valid;   // driven by L2
    logic [63:0] b_rdata;              // driven by L2
    logic [7:0]  fillbeat;
    // A row = 128 beats, but the REAL HPS f2sdram UNDER-DELIVERS a burst longer than its max
    // (NS ran 32-beat bursts on HW; the 128-beat request stalled the fill on silicon -> the
    // pulsing-line-on-white hang, reproduced in tb_vram_ddr_xdiff with the 32-cap oracle). Fill
    // the row in <=BMAX sub-bursts, re-requesting from wherever fillbeat reached.
    localparam [7:0] BMAX = 8'd32;
    localparam [2:0] B_IDLE=3'd0, B_REQ=3'd1, B_FILL=3'd2, B_HIT=3'd3, B_WAIT=3'd4;
    logic [2:0] bts;
`ifdef POCKET
    // PSRAM takes nearly one raster line to fill rc. Overlap the downstream
    // scanline copy with that fill; waiting for all 128 beats first costs another
    // 456 per-pixel handshakes and misses the Pocket's 63.25 us line deadline.
    // Only expose beats already written, with a full registered RAM read cycle.
    // The writer-invalidation rules below still prevent serving a dirty fill.
    wire pocket_scan_available =
        (rc_valid && !rc_write_hit && rc_row==req_row) ||
        ((bts==B_REQ || bts==B_FILL) && !b_fill_dirty && !fill_write_hit &&
         b_fill_row==req_row && fillbeat>{1'b0,req_col[8:2]});
    logic [1:0] pocket_scan_state;
    logic [18:0] pocket_scan_addr;
    always_ff @(posedge clk) begin
        if(rst) begin
            pocket_scan_state<=0; pocket_scan_addr<=0;
            scan_ack<=0; scan_data<=0;
        end else begin
            scan_ack<=0;
            // The payload is consumed only with scan_ack. Keep its register
            // independent of the late writer-invalidation/availability cone;
            // the unchanged ACK checks still cancel stale or retargeted reads.
                        case(pocket_scan_addr[1:0])
                            0: scan_data<=rc_q[15:0]; 1: scan_data<=rc_q[31:16];
                            2: scan_data<=rc_q[47:32]; 3: scan_data<=rc_q[63:48];
                        endcase
            case(pocket_scan_state)
                0: if(scan_req && pocket_scan_available) begin
                    pocket_scan_addr<=scan_addr;
                    pocket_scan_state<=1;
                end
                1: begin
                    // A vblank retarget or a concurrent write cancels this read.
                    if(scan_req && scan_addr==pocket_scan_addr && pocket_scan_available) begin
                        scan_ack<=1; pocket_scan_state<=2;
                    end else pocket_scan_state<=0;
                end
                2: if(!scan_req)pocket_scan_state<=0;
                default: pocket_scan_state<=0;
            endcase
        end
    end
`endif
    always_ff @(posedge clk) begin
        if (rst) begin
            bts<=B_IDLE; b_start<=1'b0; b_addr<=26'd0; b_burstlen<=8'd0;
            rc_valid<=1'b0; rc_row<=10'd0; b_fill_row<=10'd0; b_fill_dirty<=1'b0;
            fillbeat<=8'd0; rc_rlane<=2'd0;
`ifndef POCKET
            scan_ack<=1'b0; scan_data<=16'd0;
`endif
        end else begin
`ifndef POCKET
            scan_ack <= 1'b0;
`endif
            case (bts)
                B_IDLE: if (scan_req) begin
`ifdef POCKET
                    if (!rc_valid || rc_write_hit || rc_row!=req_row) begin
                        fillbeat<=8'd0; b_fill_row<=req_row; b_fill_dirty<=1'b0; bts<=B_REQ;
                    end
`else
                    if (rc_valid && !rc_write_hit && (rc_row==req_row)) begin // HIT (rc_raddr comb -> rc_q aligned by B_HIT)
                        rc_rlane<=req_col[1:0]; bts<=B_HIT;
                    end else begin                                   // MISS -> fill the row in <=BMAX sub-bursts
                        fillbeat<=8'd0; b_fill_row<=req_row; b_fill_dirty<=1'b0; bts<=B_REQ;
                    end
`endif
                end
                B_REQ: begin                                        // set up the next sub-burst from fillbeat
                    // scan_addr can retarget at vblank while an old request is draining.
                    // Keep every sub-burst and the final cache tag on the original row.
                    b_addr     <= {9'd0, b_fill_row, 7'd0} + {18'd0, fillbeat}; // beat_base + beats already filled
                    b_burstlen <= ((8'd128 - fillbeat) > BMAX) ? BMAX : (8'd128 - fillbeat);
                    b_start    <= 1'b1; bts <= B_FILL;
                end
                B_FILL: begin
                    if (b_rd_valid) begin
                        rc[fillbeat[6:0]] <= b_rdata;
                        fillbeat <= fillbeat + 8'd1;
                    end
                    if (b_done) begin                               // sub-burst complete
                        b_start <= 1'b0;
                        if (fillbeat >= 8'd128) begin
                            if (b_fill_dirty || fill_write_hit) rc_valid<=1'b0;
                            else begin rc_valid<=1'b1; rc_row<=b_fill_row; end
                            bts<=B_IDLE;
                        end
                        else bts <= B_REQ;                          // more of the row to fetch
                    end
                end
`ifndef POCKET
                B_HIT: begin                                          // rc_q valid now
                    case (rc_rlane)
                        2'd0: scan_data<=rc_q[15:0]; 2'd1: scan_data<=rc_q[31:16];
                        2'd2: scan_data<=rc_q[47:32]; default: scan_data<=rc_q[63:48];
                    endcase
                    scan_ack<=1'b1; bts<=B_WAIT;
                end
                B_WAIT: if (!scan_req) bts<=B_IDLE;   // ONE ack per request: wait for the consumer to drop
                                                      // scan_req before re-arming, else B_IDLE re-detects the
                                                      // still-high scan_req as a 2nd hit -> double-serve ->
                                                      // the next column reads this column's beat (col shift).
`endif
                default: bts<=B_IDLE;
            endcase
            // Never serve a warm row, or publish a just-filled row, across a write to it.
            // The next held scan request refills after the writer/page-settle path completes.
            if (rc_write_hit) rc_valid <= 1'b0;
            if ((bts == B_REQ || bts == B_FILL) && fill_write_hit) b_fill_dirty <= 1'b1;
        end
    end

    // ================= D: SRT row-pair engine — declarations ==================================
    // (FSM body lives after the L2 arbiter: it consumes ats/c_busy/posted_guard. Declared
    // here so the C combiner's a_block-convention gates below can also honor d_block.)
    (* ramstyle="no_rw_check" *) logic [63:0] dbuf [0:255];   // 1024 entries = one SRT row pair
    logic [16:0] d_base_beat;          // srt_entry >> 2 (beat-aligned base)
    logic        d_op_we;              // latched srt_we
    logic [8:0]  d_fill;               // beats read (latch) / streamed (transfer), 0..256
    logic        d_start, d_wr;        // D-lane request to L2 (level held per sub-burst)
    logic [25:0] d_addr;
    logic [7:0]  d_blen;
    logic        d_done, d_rd_valid;   // driven by L2
    logic [63:0] dbuf_q;               // registered FWFT head for the write burst
    wire         d_burst_next;         // L2: agent accepted a non-final write-burst beat
    logic [31:0] srt_e0e1_r;
    assign srt_e0e1 = srt_e0e1_r;
    localparam [2:0] D_IDLE=3'd0, D_DRAIN=3'd1, D_RREQ=3'd2, D_RFILL=3'd3,
                     D_WREQ=3'd4, D_WSTREAM=3'd5, D_FIN=3'd6;
    logic [2:0] dst;
    // a pending SRT op forces the same combiner drain/park an A op does (contract (a)).
    wire d_block = (dst != D_IDLE);
    wire d_cache_wr_evt = d_start && d_wr;      // per-sub-burst level, like a_cache_wr_evt

    // ================= C: W-THRU2 fb beat write-combine =======================================
    // The blitter fb stream previously rode the 16-bit sd channel: EVERY pixel cost a
    // full-beat RMW pair (~25 clk/px effective) -- the dominant term in the measured frame
    // budget (median attract frame 179k px vs 1.755M cycles). Blit rows are sx-sequential
    // (either direction), so 4 entries/beat combine naturally: FULL beats write with NO
    // RMW read (be=FF, the bridge-safe full-beat pattern, cf. the dl path); partial beats
    // (row edges) RMW. Ordering: the CPU sd lane is gated on a drained combiner (L2 below);
    // a 1-deep own-write forward covers C's partial-flush-after-flush hazard; A's fwd_beat
    // is invalidated on any C write (A must never merge a CPU RMW into a stale copy).
    logic [16:0] wc_beat;      // entry[18:2]
    logic [3:0]  wc_mask;
    logic [63:0] wc_data;
    logic [7:0]  wc_idle;
    localparam [7:0] FB_WFLUSH_IDLE = 8'd64;
    logic        fb_we_d;
    logic        fb_pend;    // held request the combiner could not accept at its edge
    wire  [16:0] fb_beat = fb_addr[18:2];
    wire         fb_same = (wc_mask != 4'd0) && (fb_beat == wc_beat);
    wire         fb_new  = fb_we & ~fb_we_d;          // dma holds fb_we until fb_ack
    wire         fb_req  = fb_new | fb_pend;          // live request (edge or parked)
    // a pending CPU accessor op (a_block) FORCES a drain and parks new fb accepts for its
    // duration — without this the sustained fb stream never leaves the combiner empty
    // and the CPU lane starves (contention-gate DEADLOCK, caught 2026-07-10).
    wire         wc_flush_req = (wc_mask != 4'd0) &&
                                ((fb_req && !fb_same) || (wc_idle >= FB_WFLUSH_IDLE) || a_block || d_block);
    // (c_start / c_wr declared up in the A section — used by the A FSM's fwd invalidate)
    logic [25:0] c_addr;
    logic [63:0] c_wdata;
    logic [7:0]  c_be;
    logic        c_done, c_rd_valid;                   // driven by L2
    logic [63:0] c_rdata;                              // driven by L2
    logic [3:0]  cf_mask;  logic [63:0] cf_data;  logic [16:0] cf_beat;  // latched flush job
    localparam [2:0] C_IDLE=3'd0, C_RD=3'd1, C_MRG=3'd2, C_WR=3'd3, C_BURST=3'd4;
    logic [2:0] cst;
    // WRITE FIFO: completed beats {mask,beat,data} queue here so the combiner (and the blitter's
    // per-pixel fb_ack) never wait on the flush round-trip (combiner->L2->agent->arb->DDR3->back,
    // ~12 clk, the measured 23% write stall). The cst FSM drains the FIFO in the background; the
    // blit only stalls if the FIFO fills (drain can't keep up = truly bandwidth-bound, which the
    // idealized-DDR3 experiment says we are NOT). Sequential blit rows never revisit a beat, so
    // FIFO entries are distinct beats -> a partial-beat RMW never reads a beat still queued.
    localparam int WF_DEPTH = 16;                      // holds a burst's worth (SCAN_MAX=8) + slack; 16:1
    localparam int WF_AW    = 4;                       // muxes vs 32:1 keeps the FIFO off the clk_sys crit path
    logic [3:0]  wf_mask [0:WF_DEPTH-1];
    logic [16:0] wf_beat [0:WF_DEPTH-1];
    logic [63:0] wf_data [0:WF_DEPTH-1];
    localparam bit USE_MLAB_FIFO = MLAB_WRITE_FIFO && CACHED_FIFO_RUN;
    // The head pipeline is consumed only while C is idle. During a burst,
    // the same asynchronous port streams c_bp instead. After the burst pops
    // wf_rptr, hd_valid enforces the original complete head-read cycle.
    // Masks/link bits stay separate because run detection observes them in
    // parallel; the 81-bit beat/data payload needs only this one read port.
    (* ramstyle="MLAB, no_rw_check" *) logic [80:0] wf_payload [0:WF_DEPTH-1];
    // Whether each pushed full beat continues the previous full beat. The
    // head's own link is never used, including after empty/reset or wrap.
    // Checking adjacent links gives the same leading run as head +/- k,
    // without several wide asynchronous reads from the address FIFO.
    logic wf_up [0:WF_DEPTH-1], wf_down [0:WF_DEPTH-1];
    logic [16:0] wf_last_beat;
    logic wf_last_full;
    logic [WF_AW:0] wf_wptr, wf_rptr;                  // +1 bit for full/empty disambiguation
    wire wf_empty = (wf_wptr == wf_rptr);
    wire wf_full  = (wf_wptr[WF_AW-1:0] == wf_rptr[WF_AW-1:0]) && (wf_wptr[WF_AW] != wf_rptr[WF_AW]);
    assign c_busy = (cst != C_IDLE) || (wc_mask != 4'd0) || !wf_empty;
    // wr_busy covers framebuffer C writes plus the full A-side CPU/autoerase write RMW,
    // including its read and merge phases, until the bridge has accepted the write. NOTE: on the real
    // DDRAM (HPS f2h_sdram) bus this is bridge-ACCEPT, not DRAM-LAND (no write-response exists).
    // wolf_video adds the measured posted-write settle before publishing a new display page.
    assign wr_busy = c_busy || sd_wr || (a_block && a_op_wr) || (d_block && d_op_we);   // (d): SRT transfer holds wr_busy
    assign dbg_cst = cst;    // DIAG: expose the C-lane FSM state to pin C_RD (RMW read) vs C_WR (drain)
    function automatic [63:0] lane_merge(input [63:0] base, input [63:0] neu, input [3:0] m);
        lane_merge = {m[3] ? neu[63:48] : base[63:48], m[2] ? neu[47:32] : base[47:32],
                      m[1] ? neu[31:16] : base[31:16], m[0] ? neu[15:0]  : base[15:0]};
    endfunction
    wire [WF_AW-1:0] wf_wp = wf_wptr[WF_AW-1:0];
    wire [WF_AW-1:0] wf_rp = wf_rptr[WF_AW-1:0];
    wire same_or_empty = (wc_mask == 4'd0) || fb_same;
    // ---- BURST DRAIN: drain a consecutive full-beat run as ONE Avalon burst so the (high-latency,
    // real f2h) bridge round-trip is paid once per run, not per beat. The blit keeps pushing to the
    // FIFO during the burst (decoupled) -> combines the FIFO's no-stall with burst amortization.
    // (reuses the module-level BMAX=32 — the scanout-proven cab-safe A-side burst cap)
    logic        c_is_burst;                           // current C flush is a multi-beat burst
    logic [7:0]  c_blen;                               // burst length in beats
    logic [16:0] c_burst_last_r;                       // captured with burst base/length
    logic [25:0] c_burst_addr;                         // burst base (LOWEST) beat address
    logic        c_dir;                                // burst DATA order: 0=ascending(rp up), 1=descending(rp+len-1 down)
    logic [WF_AW-1:0] c_bp;                            // burst data-read index (FWFT; steps +/-1 per beat)
    logic [7:0]  wf_idle;                              // cycles since the last FIFO push (drain-timeout)
    wire  [WF_AW:0] wf_occ = wf_wptr - wf_rptr;         // FIFO occupancy
    wire [WF_AW-1:0] wf_payload_raddr = (cst == C_BURST) ? c_bp : wf_rp;
    wire [80:0] wf_payload_q = wf_payload[wf_payload_raddr];
    wire wf_accept_pixel = fb_req && !a_block && !d_block && same_or_empty;
    wire wf_payload_push = !rst && !wf_accept_pixel && (wc_mask != 0) && !wf_full &&
                            ((fb_req && !a_block && !d_block && !fb_same) ||
                             (wc_idle >= FB_WFLUSH_IDLE) || a_block || d_block);
    // A single syntactic writer is required for Quartus RAM inference.
    always_ff @(posedge clk)
        if (USE_MLAB_FIFO && wf_payload_push)
            wf_payload[wf_wp] <= {wc_beat,wc_data};
    wire  [63:0] c_burst_data = USE_MLAB_FIFO ? wf_payload_q[63:0] : wf_data[c_bp];          // streamed head (ascending or descending order)
    wire         c_burst_next;                          // agent accepted a burst beat
    wire         a_cache_wr_evt = a_start && a_wr;
    wire         c_cache_wr_evt = c_start && c_wr;
    wire [16:0]  c_cache_first = c_is_burst ? c_burst_addr[16:0] : c_addr[16:0];
    wire [16:0]  c_cache_last = c_is_burst
                                  ? c_burst_last_r
                                  : c_addr[16:0];
    // D: an SRT transfer always rewrites the full 2-row pair (rows 2k, 2k+1) — every
    // sub-burst fires the invalidation with that TRUE span (contract (c)).
    assign cache_wr_evt  = a_cache_wr_evt || c_cache_wr_evt || d_cache_wr_evt;
    assign cache_wr_row0 = a_cache_wr_evt ? a_addr[16:7]
                         : d_cache_wr_evt ? d_base_beat[16:7]
                         :                  c_cache_first[16:7];
    assign cache_wr_row1 = a_cache_wr_evt ? a_addr[16:7]
                         : d_cache_wr_evt ? (d_base_beat[16:7] + 10'd1)
                         :                  c_cache_last[16:7];
    // BIDIRECTIONAL consecutive FULL-beat run from the head. UMK3 flips sprites (dst sx DESCENDS,
    // wolf_dma:614/658/686) so a mirrored row pushes DESCENDING beats -> must be detected + bursted
    // (streamed reversed) too, else half of MK's sprites never burst. Ascending Avalon burst always
    // starts at the LOWEST beat.
    wire head_full = (wf_mask[wf_rp] == 4'hF);
    wire pair_asc  = (wf_occ >= 2) && head_full && (CACHED_FIFO_RUN ? wf_up[wf_rp+1'b1] : ((wf_mask[wf_rp+1'b1]==4'hF) && (wf_beat[wf_rp+1'b1]==wf_beat[wf_rp]+17'd1)));
    wire pair_desc = (wf_occ >= 2) && head_full && (CACHED_FIFO_RUN ? wf_down[wf_rp+1'b1] : ((wf_mask[wf_rp+1'b1]==4'hF) && (wf_beat[wf_rp+1'b1]==wf_beat[wf_rp]-17'd1)));
    // SCAN_MAX 8->4 (2026-07-12): the 8-way parallel FIFO scan fanning out of wf_rptr was the
    // dominant setup-critical path (wf_rptr -> Mux85 array-read -> Add10 -> run_len_r, ROUTING-bound,
    // -1.30ns and seed-insensitive). Halving the scan width halves that fanout/congestion. Max burst
    // is now 4 beats (still amortizes the bridge round-trip 4:1 vs single-beat); throughput cost is
    // modest and does not change the coarse starvation-vs-commit blit-count discrimination. NOTE: the
    // eventual throughput-critical FIX build should instead PIPELINE the detector (register the array
    // reads) to keep SCAN_MAX=8; this trim is the low-risk unblock for the measurement build.
    // (casez pattern width is tied to SCAN_MAX — update both together.)
    localparam int SCAN_MAX = 4;                        // max sub-burst = consecutive full beats from the head
    logic [7:0]          run_len;
    logic [SCAN_MAX-1:0] cons;                          // cons[k]=1: beat rp+k is full AND consecutive (head +/- k)
    integer k;
    always_comb begin
        if (CACHED_FIFO_RUN) begin
            cons[0] = (wf_occ != 0) && head_full;
            for (k = 1; k < SCAN_MAX; k = k + 1)
                cons[k] = cons[k-1] && (k < wf_occ) &&
                          (pair_asc ? wf_up[wf_rp + k[WF_AW-1:0]] :
                           pair_desc && wf_down[wf_rp + k[WF_AW-1:0]]);
        end else begin
        for (k = 0; k < SCAN_MAX; k = k + 1)
            cons[k] = (k < wf_occ) && (wf_mask[wf_rp + k[WF_AW-1:0]] == 4'hF) &&
                      ( pair_asc  ? (wf_beat[wf_rp + k[WF_AW-1:0]] == (wf_beat[wf_rp] + k[16:0])) :
                        pair_desc ? (wf_beat[wf_rp + k[WF_AW-1:0]] == (wf_beat[wf_rp] - k[16:0])) :
                                    (k == 0) );
        end
        casez (cons)                                    // leading-consecutive-ones count (find first 0 from LSB)
            4'b???0: run_len = 8'd0;                    // head not a full beat
            4'b??01: run_len = 8'd1;
            4'b?011: run_len = 8'd2;
            4'b0111: run_len = 8'd3;
            default: run_len = 8'd4;                    // all SCAN_MAX consecutive (cons==4'hF)
        endcase
    end
    // LAZY drain: for a run, wait until it's sealed (a non-consecutive beat follows) or the FIFO is
    // near full or the blit paused -> long bursts (whole rows) that amortize the bridge round-trip.
    wire wf_nearfull = (wf_occ >= (WF_DEPTH-4));
    // PIPELINE the FIFO-head read (timing 2026-07-11): the drain FSM consumes REGISTERED head fields,
    // not live 16:1 muxes off wf_rptr. That turned the wf_rptr->c_wdata path (14.66ns, -4.2 setup) into
    // hd_data(reg)->c_wdata(reg). hd_valid stalls the drain the ONE cycle after a pop / push-into-empty
    // while hd_*/run_len_r re-settle (wf_rptr changed, or the FIFO was empty last cycle).
    logic [63:0] hd_data;  logic [16:0] hd_beat;  logic [3:0] hd_mask;
    logic [7:0]  run_len_r;  logic pair_asc_r, pair_desc_r;
    logic [WF_AW:0] wf_rptr_q;  logic wf_ne_q;
    wire c_own_fwd_hit = c_fwd_v && (c_fwd_beat == hd_beat);
    wire a_to_c_fwd_hit = fwd_valid && (fwd_addr[16:0] == hd_beat);
    wire [63:0] c_fwd_data = c_own_fwd_hit ? c_fwd : fwd_beat;
    wire hd_full    = (hd_mask == 4'hF);
    wire hd_valid   = !wf_empty && (wf_rptr == wf_rptr_q) && wf_ne_q;
    wire drain_go_r = hd_full ? ((run_len_r < wf_occ) || wf_nearfull || (wf_idle >= FB_WFLUSH_IDLE) || a_block || d_block) : 1'b1;
    always_ff @(posedge clk) begin
        if (rst) begin
            wc_beat<=17'd0; wc_mask<=4'd0; wc_data<=64'd0; wc_idle<=8'd0;
            fb_we_d<=1'b0; fb_ack<=1'b0; fb_pend<=1'b0;
            c_start<=1'b0; c_wr<=1'b0; c_addr<=26'd0; c_wdata<=64'd0; c_be<=8'd0;
            c_fwd<=64'd0; c_fwd_beat<=17'd0; c_fwd_v<=1'b0;
            cf_mask<=4'd0; cf_data<=64'd0; cf_beat<=17'd0; cst<=C_IDLE;
            wf_wptr<=0; wf_rptr<=0; wf_last_beat<=0; wf_last_full<=0;
            c_is_burst<=1'b0; c_burst_last_r<=17'd0; c_blen<=8'd1; c_burst_addr<=26'd0; c_dir<=1'b0; c_bp<=0; wf_idle<=8'd0;
            hd_data<=64'd0; hd_beat<=17'd0; hd_mask<=4'd0; run_len_r<=8'd0;
            pair_asc_r<=1'b0; pair_desc_r<=1'b0; wf_rptr_q<=0; wf_ne_q<=1'b0;
        end else begin
            fb_ack  <= 1'b0;
            fb_we_d <= fb_we;
            // An A-side full-beat write supersedes C's remembered beat.
            if (a_start && a_wr) c_fwd_v <= 1'b0;
            // pipeline registers: continuously track the FIFO head + its run detection (1-cycle lag)
            hd_data <= USE_MLAB_FIFO ? wf_payload_q[63:0] : wf_data[wf_rp];
            hd_beat <= USE_MLAB_FIFO ? wf_payload_q[80:64] : wf_beat[wf_rp];
            hd_mask <= wf_mask[wf_rp];
            run_len_r <= run_len;  pair_asc_r <= pair_asc;  pair_desc_r <= pair_desc;
            wf_rptr_q <= wf_rptr;  wf_ne_q <= !wf_empty;
            if (wc_mask != 4'd0 && wc_idle != 8'hFF) wc_idle <= wc_idle + 8'd1;
            if (wf_idle != 8'hFF) wf_idle <= wf_idle + 8'd1;   // reset on any FIFO push below
            if (fb_new) fb_pend <= 1'b1;                 // default: park a fresh request (accept clears it)
            // ---- combiner: accept pixel and/or PUSH the completed beat to the write FIFO ----
            if (fb_req && !a_block && !d_block && same_or_empty) begin // same-beat merge / start-into-empty
                fb_pend <= 1'b0; fb_ack <= 1'b1; wc_idle <= 8'd0;
                wc_beat <= fb_beat;
                wc_mask[fb_addr[1:0]] <= 1'b1;
                wc_data[fb_addr[1:0]*16 +: 16] <= fb_wdata;
            end else if (fb_req && !a_block && !d_block && (wc_mask != 4'd0) && !fb_same && !wf_full) begin
                // different beat + FIFO room: PUSH the old beat, START a fresh combiner with this pixel
                wf_mask[wf_wp] <= wc_mask;
                if (!USE_MLAB_FIFO) begin
                    wf_beat[wf_wp] <= wc_beat; wf_data[wf_wp] <= wc_data;
                end
                if (CACHED_FIFO_RUN) begin
                    wf_up[wf_wp] <= wf_last_full && (&wc_mask) && (wc_beat == wf_last_beat + 17'd1);
                    wf_down[wf_wp] <= wf_last_full && (&wc_mask) && (wc_beat == wf_last_beat - 17'd1);
                    wf_last_beat <= wc_beat; wf_last_full <= &wc_mask;
                end
                wf_wptr <= wf_wptr + 1'b1;  wf_idle <= 8'd0;
                fb_pend <= 1'b0; fb_ack <= 1'b1; wc_idle <= 8'd0;
                wc_beat <= fb_beat;
                wc_mask <= (4'd1 << fb_addr[1:0]);
                wc_data[fb_addr[1:0]*16 +: 16] <= fb_wdata;
            end else if ((wc_mask != 4'd0) && !wf_full && ((wc_idle >= FB_WFLUSH_IDLE) || a_block || d_block)) begin
                // idle-timeout / CPU-op drain: PUSH the lingering beat, no pixel accepted this cycle
                wf_mask[wf_wp] <= wc_mask;
                if (!USE_MLAB_FIFO) begin
                    wf_beat[wf_wp] <= wc_beat; wf_data[wf_wp] <= wc_data;
                end
                if (CACHED_FIFO_RUN) begin
                    wf_up[wf_wp] <= wf_last_full && (&wc_mask) && (wc_beat == wf_last_beat + 17'd1);
                    wf_down[wf_wp] <= wf_last_full && (&wc_mask) && (wc_beat == wf_last_beat - 17'd1);
                    wf_last_beat <= wc_beat; wf_last_full <= &wc_mask;
                end
                wf_wptr <= wf_wptr + 1'b1;  wf_idle <= 8'd0;
                wc_mask <= 4'd0;
            end
            // The single-beat payload is observed only after a C launch. Let it
            // track the registered FIFO head while idle, independently of the
            // pointer/occupancy/drain decision. On the launch edge it captures
            // exactly the former qualified value, then holds for the full write.
            // Bursts stream their own payload; an RMW overwrites it in C_RD.
            if (cst == C_IDLE) begin
`ifdef PARTIAL_BE_WRITE
                c_wdata <= hd_data;
`else
                c_wdata <= hd_full ? hd_data : lane_merge(c_fwd_data, hd_data, hd_mask);
`endif
            end
            // ---- drain the FIFO: BURST a consecutive run (asc or desc), else single-beat write / RMW ----
            if ((cst == C_IDLE) && hd_valid && drain_go_r) begin
                if (hd_full) begin                                         // FULL beat at head (registered)
                    if (run_len_r >= 8'd2) begin                           // BURST the run (pay the round-trip ONCE)
                        c_blen <= run_len_r;  c_is_burst <= 1'b1;  c_wr <= 1'b1;  c_start <= 1'b1;  cst <= C_BURST;
                        c_fwd_v <= 1'b0;                                    // burst writes many beats -> drop the 1-deep fwd
                        if (pair_asc_r) begin                              // ascending: stream rp -> up, base = head
                            c_dir <= 1'b0;  c_bp <= wf_rp;
                            c_burst_addr <= {9'd0, hd_beat};
                            // Capture the span in the launch cycle. Cache
                            // invalidation must not recompute a 17-bit sum
                            // before row comparison and scanout enables.
                            c_burst_last_r <= hd_beat + {9'd0,run_len_r} - 17'd1;
                        end else begin                                     // descending (flipped): stream rp+len-1 -> down
                            c_dir <= 1'b1;  c_bp <= wf_rp + run_len_r[WF_AW-1:0] - 1'b1;
                            // base = LOWEST beat = head - (run_len-1); zero-extend run_len_r to 17b.
                            c_burst_addr <= {9'd0, (hd_beat - ({9'd0, run_len_r} - 17'd1))};
                            c_burst_last_r <= hd_beat;
                        end
                        // wf_rptr pops the whole run at C_BURST completion (NOT per-beat)
                    end else begin                                         // lone full beat -> single-beat write
                        wf_rptr <= wf_rptr + 1'b1;
                        c_addr <= {9'd0, hd_beat};  c_be <= 8'hFF;
                        c_wr <= 1'b1;  c_start <= 1'b1;  cst <= C_WR;
                        c_fwd <= hd_data;  c_fwd_beat <= hd_beat;  c_fwd_v <= 1'b1;
                    end
                end else begin                                             // PARTIAL beat
`ifdef PARTIAL_BE_WRITE
                    // N64-STYLE (2026-07-14): write the partial byte-enables DIRECTLY as a single beat —
                    // NO RMW read, NO fwd-merge. This DELETES C_RD (the character-wedge state) entirely;
                    // busy can't hang because there is no read to stall. Correctness relies on the f2h
                    // bridge honoring per-byte BE on a 1-beat write = a live re-test of P1.5(a) (the N64
                    // ships doing exactly this). If (a) is real the partial pixels drop (holey chars) BUT
                    // the CPU does NOT freeze -> a clean visible discriminator, never worse than today.
                    wf_rptr <= wf_rptr + 1'b1;
                    c_addr <= {9'd0, hd_beat};
                    c_be   <= {{2{hd_mask[3]}}, {2{hd_mask[2]}}, {2{hd_mask[1]}}, {2{hd_mask[0]}}};
                    c_wr <= 1'b1;  c_start <= 1'b1;  cst <= C_WR;
`else
                    if (c_own_fwd_hit || a_to_c_fwd_hit) begin             // shared A/C write fwd
                        cf_mask <= hd_mask;  cf_data <= hd_data;  cf_beat <= hd_beat;
                        wf_rptr <= wf_rptr + 1'b1;
                        c_addr <= {9'd0, hd_beat};  c_be <= 8'hFF;
                        c_wr <= 1'b1;  c_start <= 1'b1;  cst <= C_WR;
                        c_fwd <= lane_merge(c_fwd_data, hd_data, hd_mask);  c_fwd_beat <= hd_beat;
                        c_fwd_v <= 1'b1;
                    end else begin                                         // RMW read first
                        cf_mask <= hd_mask;  cf_data <= hd_data;  cf_beat <= hd_beat;
                        wf_rptr <= wf_rptr + 1'b1;
                        c_addr <= {9'd0, hd_beat};  c_wr <= 1'b0;  c_start <= 1'b1;  cst <= C_RD;
                    end
`endif
                end
            end
            case (cst)
                C_RD: begin
                    if (c_rd_valid) c_wdata <= lane_merge(c_rdata, cf_data, cf_mask);
                    if (c_done) begin c_start <= 1'b0; cst <= C_MRG; end
                end
                C_MRG: begin                               // issue the merged full-beat write
                    c_addr <= {9'd0, cf_beat};  c_be <= 8'hFF;  c_wr <= 1'b1;  c_start <= 1'b1;
                    c_fwd <= c_wdata;  c_fwd_beat <= cf_beat;  c_fwd_v <= 1'b1;
                    cst <= C_WR;
                end
                C_WR: if (c_done) begin c_start <= 1'b0; c_wr <= 1'b0; cst <= C_IDLE; end
                C_BURST: begin
                    if (c_burst_next) c_bp <= c_dir ? (c_bp - 1'b1) : (c_bp + 1'b1);  // stream next beat
                    if (c_done) begin
                        c_start <= 1'b0; c_wr <= 1'b0; c_is_burst <= 1'b0;
                        wf_rptr <= wf_rptr + {1'b0, c_blen[WF_AW-1:0]};   // pop the whole run at once
                        // Remember the tail for immediate forwarding. A non-tail revisit is held
                        // by posted_guard until the measured bridge posting window expires.
                        c_fwd <= c_burst_data;
                        c_fwd_beat <= c_burst_last_r;
                        c_fwd_v <= 1'b1;
                        cst <= C_IDLE;
                    end
                end
                default: ;
            endcase
        end
    end

    // ================= L2 arbiter: A (single beat) vs B (128-beat burst) -> agent =============
    logic        tst_wr_req, tst_rd_req;
    logic [25:0] tst_addr;
    logic [63:0] tst_wdata_lat, tst_rdata;             // latched single-beat write value
    wire  [63:0] tst_wdata;                            // agent write data: live FIFO head during a burst
    wire         tst_wnext;                            // agent: a burst beat was accepted
    logic [ 7:0] tst_be, tst_burstcnt;
    logic        tst_rd_valid, tst_busy;
    logic        tst_wr_done;
    logic [25:0] tst_wr_base;
    logic [ 7:0] tst_wr_count;
    logic [63:0] tst_wr_last_data;

    logic [2:0] l_gnt;   // 0=A, 1=B, 2=C (fb write-combine + burst drain), 3=scan fence readback, 4=D (SRT)
    localparam [1:0] L_IDLE=2'd0, L_ACCEPT=2'd1, L_RUN=2'd2, L_DONE=2'd3;
    logic [1:0] ls;
    logic       l_write, l_burst_write;
    logic [7:0] posted_guard;
    logic [16:0] posted_base, posted_last;
    // Scan publication is qualified by an exact readback of the final accepted beat, not by a
    // guessed acceptance-to-DRAM timer. The tracker is persistent across core rst because the DDR
    // agent is persistent too. One last-address/data pair is sufficient per dirty region because
    // transactions are single-outstanding and every later accepted write orders every older one.
    // Advance an already-dirty region's proof on later writes to any region: otherwise a later
    // transaction could overwrite an old cross-boundary proof address and make it never match.
    logic [3:0]  scan_dirty;
    logic [16:0] scan_fence_addr [0:3];
    logic [63:0] scan_fence_expect [0:3];
    logic [1:0]  scan_fence_page;
    wire  [16:0] retired_write_base = tst_wr_base[16:0];
    wire  [16:0] retired_write_last = tst_wr_base[16:0] + {{9{1'b0}},tst_wr_count} - 17'd1;
    wire  [ 1:0] retired_page_first = retired_write_base[16:15];
    wire  [ 1:0] retired_page_last  = retired_write_last[16:15];
    wire  [ 3:0] retired_page_mask  = (4'b0001 << retired_page_first) |
                                       (4'b0001 << retired_page_last);
    wire         fence_complete_evt = (ls == L_RUN) && !tst_busy && (l_gnt == 3'd3);
    wire         fence_match_evt = fence_complete_evt && tst_rd_valid &&
                                   (tst_rdata == scan_fence_expect[scan_fence_page]);
    // Retain the old 2047-cycle policy only as a mutation oracle. It is not on the production
    // coherence path and is pruned in synthesis; sim/run_ddr3.sh rewires a mutant to prove that
    // this estimate fails when physical publication is delayed beyond 2047 clocks.
    localparam int LEGACY_SCAN_POSTED_GUARD = 2047;
    localparam int LEGACY_SCAN_GW = $clog2(LEGACY_SCAN_POSTED_GUARD + 1);
    localparam [LEGACY_SCAN_GW-1:0] LEGACY_SCAN_GUARD_RELOAD = LEGACY_SCAN_POSTED_GUARD;
    logic [LEGACY_SCAN_GW-1:0] scan_legacy_guard [0:3];
    // Burst-write posted-range tracking generalized to ANY granted burst write (C or D):
    // tst_addr/tst_burstcnt are the values latched at grant — identical to the old
    // c_burst_addr/c_blen for C bursts, and they also cover D's SRT transfer sub-bursts.
    wire  [16:0] completed_burst_base = tst_addr[16:0];
    wire  [16:0] completed_burst_last = tst_addr[16:0] + {{9{1'b0}}, tst_burstcnt} - 17'd1;
    wire a_posted_hazard = (posted_guard != 8'd0) &&
                           (a_addr[16:0] >= posted_base) && (a_addr[16:0] <= posted_last);
    wire c_posted_hazard = (posted_guard != 8'd0) &&
                           (c_addr[16:0] >= posted_base) && (c_addr[16:0] <= posted_last);
    // A cold row fill is blocked only by writes to its 256-row region. Before the fill, grant 3
    // polls the exact final beat until the value physically read from DDR equals what was accepted.
    wire b_publication_pending = scan_dirty[b_fill_row[9:8]];
    wire b_retire_collision = tst_wr_done && retired_page_mask[b_fill_row[9:8]];
    assign tst_wdata    = (l_gnt==3'd2 && c_is_burst) ? c_burst_data
                        : (l_gnt==3'd4)               ? dbuf_q
                        :                               tst_wdata_lat;
    assign c_burst_next = (l_gnt==3'd2 && c_is_burst && ls==L_RUN) && tst_wnext;
    assign d_burst_next = (l_gnt==3'd4 && ls==L_RUN) && tst_wnext;

    wire issue_slot = (ls == L_IDLE) && !tst_busy;
    wire a_eligible = a_start && (a_wr || !a_posted_hazard);
    wire c_eligible = c_start && (c_wr || !c_posted_hazard);
    wire grant_fence = issue_slot && b_start && !b_retire_collision && b_publication_pending;
    wire grant_b = issue_slot && b_start && !b_retire_collision && !b_publication_pending;
    wire grant_c = issue_slot && !b_start && !a_rmw_lock && c_eligible;
    wire grant_d = issue_slot && !b_start && !a_rmw_lock && !c_eligible && d_start;
    wire grant_a = issue_slot && !b_start && a_eligible &&
                   (a_rmw_lock || (!c_eligible && !d_start && !c_busy));
    wire grant_any = grant_a || grant_b || grant_c || grant_d || grant_fence;
    wire grant_c_burst = grant_c && c_is_burst;
    wire grant_c_single = grant_c && !c_is_burst;
    wire grant_write = (grant_a && a_wr) || (grant_c && (c_is_burst || c_wr)) ||
                       (grant_d && d_wr);
    wire [25:0] issue_addr = ({26{grant_a}} & a_addr) |
                             ({26{grant_b}} & b_addr) |
                             ({26{grant_c_single}} & c_addr) |
                             ({26{grant_c_burst}} & c_burst_addr) |
                             ({26{grant_d}} & d_addr) |
                             ({26{grant_fence}} & {9'd0,scan_fence_addr[b_fill_row[9:8]]});
    wire [7:0] issue_length = ({8{grant_a || grant_c_single || grant_fence}} & 8'd1) |
                              ({8{grant_b}} & b_burstlen) |
                              ({8{grant_c_burst}} & c_blen) |
                              ({8{grant_d}} & d_blen);

    integer pg;
    always_ff @(posedge clk) begin
        if (sdram_por) begin
            scan_dirty <= 4'b0000;
            for (pg=0; pg<4; pg=pg+1) begin
                scan_fence_addr[pg] <= 17'd0;
                scan_fence_expect[pg] <= 64'd0;
                scan_legacy_guard[pg] <= {LEGACY_SCAN_GW{1'b0}};
            end
        end else begin
            for (pg=0; pg<4; pg=pg+1)
                if (|scan_legacy_guard[pg]) scan_legacy_guard[pg] <= scan_legacy_guard[pg] - 1'b1;
            if (fence_match_evt) scan_dirty[scan_fence_page] <= 1'b0;
            if (tst_wr_done)
                for (pg=0; pg<4; pg=pg+1)
                    if (scan_dirty[pg] || retired_page_mask[pg]) begin
                        scan_dirty[pg] <= 1'b1;
                        scan_fence_addr[pg] <= retired_write_last;
                        scan_fence_expect[pg] <= tst_wr_last_data;
                        if (retired_page_mask[pg])
                            scan_legacy_guard[pg] <= LEGACY_SCAN_GUARD_RELOAD;
                    end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            ls<=L_IDLE; l_gnt<=3'd0; l_write<=1'b0; l_burst_write<=1'b0;
            posted_guard<=8'd0; posted_base<=17'd0; posted_last<=17'd0;
            scan_fence_page<=2'd0;
            tst_rd_req<=1'b0; tst_wr_req<=1'b0;
            tst_addr<=26'd0; tst_wdata_lat<=64'd0; tst_be<=8'd0; tst_burstcnt<=8'd1;
            a_done<=1'b0; b_done<=1'b0;
        end else begin
            tst_rd_req<=1'b0; tst_wr_req<=1'b0; a_done<=1'b0; b_done<=1'b0; c_done<=1'b0; d_done<=1'b0;
            if (posted_guard != 8'd0) posted_guard <= posted_guard - 8'd1;
            // Prepare single-write data whenever the agent can accept.
            // Writes never depend on the read-after-posted-write hazard test.
            // If a read/fence wins, this value is unconsumed; the next write
            // replaces it on the same grant edge as before. Keep the exact
            // original arbitration and request cadence, but remove the long
            // posted_guard -> eligible -> grant_any cone from 64 data FF enables.
            if (issue_slot) begin
                tst_wdata_lat <= (!a_rmw_lock && c_start && !c_is_burst && c_wr)
                                   ? c_wdata : a_wdata;
            end
            case (ls)
                // Gate acceptance on the agent actually being IDLE. The agent runs on sdram_por while
                // A/B/C/L2 run on core rst (P0022 split): a core_rst pulse mid-burst snaps L2 to L_IDLE
                // while the agent keeps draining its pre-reset transaction. Without this guard L2 would
                // pulse a req the busy agent ignores, then mistake the OLD transaction's tst_busy for
                // its own acceptance and fabricate a completion for an access that never issued
                // ([[lessons_gate_fsm_not_output]] — never sequence on a busy you do not own). Waiting
                // for !tst_busy makes the orphaned burst drain (its beats are dropped: a_rd_valid/
                // b_rd_valid are gated on ls==L_RUN) before any fresh command is issued.
                L_IDLE: if (grant_any) begin
                    // One-hot masked data mux avoids a late hazard comparator
                    // traversing five nested requester address muxes.
                    l_gnt <= ({3{grant_b}} & 3'd1) | ({3{grant_c}} & 3'd2) |
                             ({3{grant_fence}} & 3'd3) | ({3{grant_d}} & 3'd4);
                    l_write <= grant_write;
                    l_burst_write <= grant_c_burst || (grant_d && d_wr);
                    tst_addr <= issue_addr;
                    tst_burstcnt <= issue_length;
                    tst_wr_req <= grant_write;
                    tst_rd_req <= !grant_write;
                    if (grant_fence) scan_fence_page <= b_fill_row[9:8];
                    if (grant_a && a_wr) tst_be <= a_be;
                    if (grant_c_single && c_wr) tst_be <= c_be;
                    if (grant_c_burst || (grant_d && d_wr)) tst_be <= 8'hff;
                    ls <= L_ACCEPT;
                end
                L_ACCEPT: if (tst_busy) ls<=L_RUN;            // agent accepted the transaction
                L_RUN: if (!tst_busy) begin                  // transaction complete
                        if (l_gnt==3'd1) b_done<=1'b1;
                        else if (l_gnt==3'd2) c_done<=1'b1;
                        else if (l_gnt==3'd0) a_done<=1'b1;
                        else if (l_gnt==3'd4) d_done<=1'b1;
                        if (l_write && l_burst_write) begin
                            posted_guard <= POSTED_WRITE_GUARD[7:0];
                            // Keep every burst that can still be posted. Widening one interval is
                            // conservative, but it cannot forget an older disjoint burst when a
                            // newer burst completes inside the same acceptance-to-land window.
                            if (posted_guard != 8'd0) begin
                                posted_base <= (completed_burst_base < posted_base) ? completed_burst_base : posted_base;
                                posted_last <= (completed_burst_last > posted_last) ? completed_burst_last : posted_last;
                            end else begin
                                posted_base <= completed_burst_base;
                                posted_last <= completed_burst_last;
                            end
                        end
                        ls<=L_DONE;
                    end
                L_DONE: ls<=L_IDLE;                           // bubble: requester clears its start level before re-arbitrate
                default: ls<=L_IDLE;
            endcase
        end
    end
    // route read beats to the granted consumer
    assign a_rd_valid = (l_gnt==3'd0) && (ls==L_RUN) && tst_rd_valid;
    assign b_rd_valid = (l_gnt==3'd1) && (ls==L_RUN) && tst_rd_valid;
    assign c_rd_valid = (l_gnt==3'd2) && (ls==L_RUN) && tst_rd_valid;
    assign d_rd_valid = (l_gnt==3'd4) && (ls==L_RUN) && tst_rd_valid;
    assign a_rdata = tst_rdata;
    assign b_rdata = tst_rdata;
    assign c_rdata = tst_rdata;

    // ================= D: SRT row-pair engine — FSM (declarations above the C section) =======
    // Latch  (srt_we=0): 1024 entries = 256 beats read into dbuf via 8 x BMAX-beat
    //   sub-bursts (the B fill pattern); the FIRST beat's low 32 bits are the two base
    //   entries (beat-aligned base) -> srt_e0e1 for the caller's A0033 rdata.
    // Transfer (srt_we=1): 256 beats written from dbuf via 8 x BMAX-beat sub-bursts,
    //   streamed FWFT (dbuf_q registered show-ahead; d_burst_next pops).
    // Ordering: D_DRAIN parks behind a drained C (c_busy==0 and accepts parked via
    //   d_block) and an idle A accessor (ats==A_IDLE — also covers an in-flight A RMW,
    //   contract (a)); a latch READ additionally waits out posted_guard so it cannot
    //   observe a burst write the bridge accepted but has not landed. Writes go through
    //   the same agent, so tst_wr_done arms the scan fence (contract (e)) and the
    //   completed-burst posted range covers a subsequent A/C RMW read (L2 above).
`ifdef SYNTHESIS
    wire srt_go = srt_req;
`else
    wire srt_go = (srt_req === 1'b1);   // hosts that predate the port leave it unconnected (z)
`endif
    wire [8:0] d_fill_rd_n = d_fill + (d_rd_valid ? 9'd1 : 9'd0);
    // dbuf ports (one always block per port for M10K inference)
    wire [7:0] dbuf_ra = d_burst_next ? (d_fill[7:0] + 8'd1) : d_fill[7:0];
    always_ff @(posedge clk) dbuf_q <= dbuf[dbuf_ra];
    always_ff @(posedge clk) if (d_rd_valid && !d_op_we) dbuf[d_fill[7:0]] <= tst_rdata;
    always_ff @(posedge clk) begin
        if (rst) begin
            dst<=D_IDLE; d_start<=1'b0; d_wr<=1'b0; d_addr<=26'd0; d_blen<=8'd1;
            d_fill<=9'd0; d_base_beat<=17'd0; d_op_we<=1'b0; srt_done<=1'b0; srt_e0e1_r<=32'd0;
        end else begin
            srt_done <= 1'b0;
            case (dst)
                D_IDLE: if (srt_go) begin
                    d_base_beat <= srt_entry[18:2];
                    d_op_we     <= srt_we;
                    d_fill      <= 9'd0;
                    dst         <= D_DRAIN;
                end
                D_DRAIN: if (!c_busy && (ats == A_IDLE) && (d_op_we || (posted_guard == 8'd0)))
                    dst <= d_op_we ? D_WREQ : D_RREQ;
                D_RREQ: begin                                  // next read sub-burst from d_fill
                    d_addr  <= {9'd0, d_base_beat} + {17'd0, d_fill};
                    d_blen  <= ((9'd256 - d_fill) > {1'b0, BMAX}) ? BMAX : 8'((9'd256 - d_fill));
                    d_wr    <= 1'b0;  d_start <= 1'b1;  dst <= D_RFILL;
                end
                D_RFILL: begin
                    if (d_rd_valid) begin
                        if (d_fill == 9'd0) srt_e0e1_r <= tst_rdata[31:0];  // entries base+0/+1
                        d_fill <= d_fill_rd_n;
                    end
                    if (d_done) begin                          // sub-burst complete
                        d_start <= 1'b0;
                        dst <= (d_fill_rd_n >= 9'd256) ? D_FIN : D_RREQ;
                    end
                end
                D_WREQ: begin                                  // next write sub-burst from d_fill
                    d_addr  <= {9'd0, d_base_beat} + {17'd0, d_fill};
                    d_blen  <= ((9'd256 - d_fill) > {1'b0, BMAX}) ? BMAX : 8'((9'd256 - d_fill));
                    d_wr    <= 1'b1;  d_start <= 1'b1;  dst <= D_WSTREAM;
                end
                D_WSTREAM: begin
                    if (d_burst_next) d_fill <= d_fill + 9'd1; // agent accepted a non-final beat
                    if (d_done) begin                          // final beat accepted (no wnext for it)
                        d_start <= 1'b0;  d_wr <= 1'b0;
                        d_fill  <= d_fill + 9'd1;
                        dst <= ((d_fill + 9'd1) >= 9'd256) ? D_FIN : D_WREQ;
                    end
                end
                D_FIN: begin srt_done <= 1'b1; dst <= D_IDLE; end
                default: dst <= D_IDLE;
            endcase
        end
    end

    stv_vram_ddr_agent #(.VRAM_DDR_BASE(VRAM_DDR_BASE)) u_agent (
        .clk(clk), .sdram_por(sdram_por),
        .tst_wr_req(tst_wr_req), .tst_rd_req(tst_rd_req), .tst_addr(tst_addr),
        .tst_wdata(tst_wdata), .tst_be(tst_be), .tst_burstcnt(tst_burstcnt),
        .tst_rdata(tst_rdata), .tst_rd_valid(tst_rd_valid), .tst_busy(tst_busy), .tst_wnext(tst_wnext),
        .tst_wr_done(tst_wr_done), .tst_wr_base(tst_wr_base), .tst_wr_count(tst_wr_count),
        .tst_wr_last_data(tst_wr_last_data),
        .ddram_addr(ddram_addr), .ddram_burstcnt(ddram_burstcnt), .ddram_rd(ddram_rd), .ddram_we(ddram_we),
        .ddram_din(ddram_din), .ddram_be(ddram_be),
        .ddram_busy(ddram_busy), .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready) );
endmodule
`default_nettype wire

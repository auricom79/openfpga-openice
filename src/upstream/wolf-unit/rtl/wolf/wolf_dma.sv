// wolf_dma.sv — Midway T-unit / Wolf-unit (UMK3) SCALING DMA blitter.
//
// FORK of yunit_dma.sv: reuses its FSM shell, register-file + busy/blit_irq
// discipline, fb_ack self-pacing, Icarus-portability style (constant selects
// hoisted to continuous-assign wires) and default_nettype hygiene. The
// register decode and the ENTIRE draw engine are new — a faithful RTL
// transcription of MAME's templated T/Wolf scaling blitter.
//
// Gospel (vendored MAME, mame-gospel/midway/):
//   dma_w register decode + trigger + state fill : midtunit_v.cpp:695-836
//   dma_draw template (8.8 fixed-point engine)   : midtunit_v.cpp:431-610
//   EXTRACTGEN portable byte form                : midtunit_v.cpp:427
//   dispatch tables (mode -> Zero/NonZero/XFlip) : midtunit_v.ipp:11-81
//     (cross-checked against the log_bitmap map at midtunit_v.cpp:874-890 —
//      the two agree for every mode 0..15)
//   completion (dma_done)                        : midtunit_v.cpp:624-628
//   dma_r offset-0 -> register-1 quirk           : midtunit_v.cpp:638-645
//   DMA register enum                            : midtunit_v.h:88-108
//   XPOSMASK=0x3ff / YPOSMASK=0x1ff              : midtunit_v.h:76-77
//   op_type_t {SKIP=0,COLOR=1,COPY=2}            : midtunit_v.h:57-59
//
// gfx_rom_large: the Wolf-unit video device is LARGE — midwunit_video_device's
// constructor sets m_gfx_rom_large = true (midtunit_v.cpp:70; T-unit MK2 also
// sets it via set_gfx_rom_large(true), midtunit.cpp:656). Therefore the
// small-ROM fixup "gfxoffset >= 0x2000000 -> -= 0x2000000" (midtunit_v.cpp:
// 753-754) does NOT apply on Wolf. It is kept behind the GFX_ROM_LARGE
// parameter (default 1 = Wolf) so a T-unit host could reuse this module; at
// the default the branch is inert.
//
// Source port: byte-granular req/ack over the PACKED gfx ROM byte space.
// EXTRACTGEN (midtunit_v.cpp:427) reads base[o>>3] and base[(o>>3)+1] (o in
// BITS); we fetch BOTH bytes for every extract (two sequential single-byte
// fetches, states *B0 then *B1), even when (o&7)+bpp <= 8 would only need the
// first — exactly mirroring the portable EXTRACTGEN which always reads both.
// This keeps the TB stub trivial (combinational: ack=req, data=gfx[addr],
// out-of-range reads return 0). NOTE for the future SDRAM adapter: requests
// are issued back-to-back (req stays high across an address change from byte0
// to byte1); a registered slave must ack the CURRENT address, not a stale one.
//
// Faithfulness notes (transcribed, not "fixed"):
//  * The Skip-path preskip shift is '<< (preskip + 8)' at the row head
//    (midtunit_v.cpp:465) but '<< preskip' (no +8) in the Scale+Skip multi-row
//    source skip-ahead (midtunit_v.cpp:601). Both transcribed EXACTLY.
//  * sx wraps &0x3ff (:543-545) and the destination word index is d[sx] off
//    d = &videoram[sy*512] (:499) — sx in [512,0x3ff] therefore writes at
//    sy*512+sx WITHOUT re-masking sx to 511 (it bleeds into the next rows'
//    address space, exactly like MAME).
//  * dma_r does NOT go through register_map: it reads m_dma_register[offset]
//    raw, with offset 0 mapped to register 1 (:638-645). Reads of offsets
//    12/13 therefore always return TOPCLIP/BOTCLIP storage, whatever CONFIG
//    bit5 says.
//  * A skipdma (source offset out of range, :759-762) draws nothing but STILL
//    completes: MAME schedules dma_done even on the skipdma path (:834-835),
//    so busy falls, COMMAND bit15 clears and blit_irq asserts.
//  * Mode field 0 (and 0x10 = mode 0 + XFlip) dispatches dma_draw_none
//    (midtunit_v.ipp:50/66): no pixels, but the blit still completes.
//
// RTL-only divergences (impossible to express against MAME's CPU-synchronous
// blit, documented for honesty):
//  * MAME draws the whole blit inside the dma_w call; register writes during
//    our multi-cycle draw update the register file but cannot affect the
//    in-flight blit (all state is latched at S_SETUP) — observably identical
//    for any MAME-expressible sequence.
//  * A COMMAND trigger while busy resumes a documented first DGO halt. After
//    an irrevocable second-zero kill, the first replacement GO is frozen and
//    launched when private traffic drains; other busy triggers are ignored
//    (registers still write and blit_irq still clears per :715).
//  * TIMED_IRQ_PUMP optionally exposes MAME's approximate 41ns-per-pixel
//    dma_done cadence (:835) to software for unity-scale commands even while
//    this serialized renderer is still working. Later GOs are retained in the
//    ordered queue. COMMAND/busy and the page-flip fence remain tied to actual
//    render + write-drain completion, so software can never display a partially
//    committed page. Scaled commands retain physical-completion IRQ semantics.
//  * COMMAND reads return the stored DGO bit, matching dma_r and allowing a
//    stopped transfer to read clear while private source/write traffic drains.
//    busy remains a separate internal/output lifetime and dma_done still clears
//    stored bit15 at normal completion (:626).
//  * DMA2 DGO stop semantics are observable only in this multi-cycle RTL:
//    the first DGO=0 pauses after any active source/fb transaction, DGO=1
//    resumes the preserved FSM, and a second DGO=0 kills without dma_done.
//
// Verified by sim/tb_wolf_dma.sv (Icarus, -g2012).

`default_nettype none

module wolf_dma
  import wolf_pkg::*;
#(
  // Wolf-unit: m_gfx_rom_large = true (midtunit_v.cpp:70). 0 = small (T-unit
  // MK1 etc.), enables the 0x2000000 fixup at midtunit_v.cpp:753-754.
  parameter bit GFX_ROM_LARGE = 1'b1,
  // Wolf software pipelines its DMA queue from completion interrupts and has
  // bounded assembly waits derived from the original device cadence. At 80MHz,
  // 41ns/pixel is 3.28 clocks/pixel; use the division-free 105/32 (3.28125)
  // approximation. Default off keeps standalone unit tests cycle-compatible;
  // wolf_memsys enables it for the production Wolf CPU path.
  parameter bit TIMED_IRQ_PUMP = 1'b0,
  // The Pocket memory backend cannot always sustain the ASIC cadence.
  // Keep the cadence as a minimum, but publish completion only after the
  // pixels and downstream writes have retired. This prevents a fictitious
  // completion from overflowing the queued draw descriptors.
`ifdef POCKET
  parameter bit RETIRE_IRQ_FENCE = 1'b1,
`else
  parameter bit RETIRE_IRQ_FENCE = 1'b0,
`endif
  // The CPU-visible cadence can run ahead of this serialized renderer.  When
  // that happens, Hangtime's end-of-list watchdog writes two consecutive
  // DGO=0 words after MAME/the ASIC have already drawn the submitted command.
  // On this implementation the same pair can arrive while that command is
  // still physical work.  Production enables a narrow compatibility rule:
  // the first zero retains the real halt semantics, but its immediately
  // following mate resumes instead of killing only when a modeled completion
  // is still pending or captured commands remain queued.  Standalone DMA/DGO
  // tests leave this disabled and retain the literal halt/kill contract.
  parameter bit DRAIN_QUEUED_ON_STOP = 1'b0,
  // Realistic f2h DDR latency can accumulate more than 96 component GOs in
  // the measured attract burst. Keep the full captured frame inside this
  // power-of-two M10K queue, with room for DCS contention and latency jitter.
  parameter integer NORMAL_Q_DEPTH = 256,
  // If selected by the CPU bus adapter, a new ordinary GO waits for the
  // preceding descriptor/write path to retire. STOP/resume semantics remain.
  parameter bit WAIT_GO_RETIRED = 1'b0,
  // With a ready/valid CPU adapter, accept writes here so STOP and a safe
  // resume can be decoded before the publication-only GO admission path.
  // Default0 preserves the legacy already-accepted reg_we interface.
  parameter bit REG_WRITE_BACKPRESSURE = 1'b0,
  // The current pixel and look-ahead cache probes are used in disjoint FSM
  // phases. Selecting their address before the tag comparators avoids three
  // complete copies of the two-entry cache lookup on the Pocket FPGA.
`ifdef POCKET
  parameter bit SHARED_SOURCE_LOOKUP = 1'b1,
  parameter bit COMPACT_DIVIDER = 1'b1,
  parameter bit SHARED_WALKER_ARITH = 1'b1,
  parameter bit COMPACT_WALKER = 1'b1,
  parameter bit SHARED_COMMAND_IMAGE = 1'b1
`else
  parameter bit SHARED_SOURCE_LOOKUP = 1'b0,
  parameter bit COMPACT_DIVIDER = 1'b0,
  parameter bit SHARED_WALKER_ARITH = 1'b0,
  parameter bit COMPACT_WALKER = 1'b0,
  parameter bit SHARED_COMMAND_IMAGE = 1'b0
`endif
)
(
  input  logic        clk,
  input  logic        rst,           // sync, active-high

  // CPU register interface (addr = CPU-visible dma_w/dma_r offset 0..15).
  input  logic        reg_we,
  input  logic  [3:0] reg_addr,
  input  logic [15:0] reg_wdata,
  output logic [15:0] reg_rdata,
  // Ready for the proposed register word, independent of reg_we. A CPU bus
  // adapter may hold the word while low, and pulse reg_we only on acceptance.
  output logic        reg_ready,
  input  logic        go_hold, // publication barrier; paused current work may resume

  // Packed-gfx source read: one BYTE at linear byte index src_addr.
  output logic        src_req,
  output logic [31:0] src_addr,
  output logic        src_active,    // unscaled source-consuming command active
  output logic        src_stream,    // dense unity 8-bpp source run (cache look-ahead hint)
  input  logic  [7:0] src_data,
  input  logic        src_ack,

  // Frame-buffer write: 16-bit word at word index (sy*512 + sx), sx unmasked
  // beyond 511 (midtunit_v.cpp:499 + :543-545). Full 19-bit wolf address.
  output logic        fb_we,
  output logic [FB_ADDR_W-1:0] fb_addr,
  output logic [15:0] fb_wdata,
  input  logic        fb_ack,        // write accepted. Tie 1'b1 for BRAM; the
                                     // SDRAM path drives it multi-cycle so the
                                     // blitter self-paces (yunit_dma pattern).
  // HANDSHAKE FIX (2026-07-11): fb_ack means "write ACCEPTED into the DDR3 write-FIFO", NOT
  // "committed to VRAM". The game (NBA Hangtime MAIN.ASM:641 dirqdraw + UNZIP.ASM:217
  // movie_waitdma) WAITS for DMACTRL bit15/blit_irq before flipping the page, so a "done" that
  // fires while the FIFO is still draining -> the game flips a half-written page (cab: fights
  // draw incomplete, no characters). wr_busy = the write path is still draining (c_busy from
  // stv_vram_ddr_top). Hold busy + defer blit_irq until it clears => "done" means COMMITTED.
  // Tie 1'b0 for BRAM (instant commit).
  input  logic        wr_busy,

  // Status
  output logic        busy,          // private physical renderer/write-drain busy;
                                     // CPU-visible COMMAND[15] is reg_rdata
  output logic        blit_irq,      // set on completion (dma_done :627),
                                     // cleared on any COMMAND write (:715)
  output logic [15:0] dma_palette,   // DMA_PALETTE reg -> wolf_mem vram_w
                                     // byte-lane fold (midtunit_v.cpp:265/283)
  output logic        dbg_q_overflow,
  output logic [8:0]  dbg_q_highwater
`ifdef DIAG_FACEOFF
  ,
  // Opening-faceoff render classifier. One pulse is emitted for every
  // in-clip destination pixel retired by the walker, including transparent
  // pixels that intentionally do not enter the framebuffer write FIFO.
  // Observability only: these outputs do not alter the renderer or its queues.
  output logic        diag_px_evt,
  output logic [9:0]  diag_px_x,
  output logic [8:0]  diag_px_y,
  output logic        diag_px_write,
  output logic        diag_px_copy_nz,
  output logic        diag_px_color
`endif
`ifdef DIAG_FLIP
  ,
  // BLIT-COMMAND CAPTURE (2026-07-12): raw taps at the blit trigger so wolf_top can track the
  // running-max source blit and diff it vs the MAME golden command trace. src={SAGH,SAGL}; if the
  // game issues the correct high-gfx source for character/portrait blits these reach deep, if a
  // reg-pair drop or state bug truncates them they stay low.
  output logic        dbg_blit_trig,   // blit triggered this cycle
  output logic [31:0] dbg_blit_src,    // {r_offhi, r_offlo} = source address of the triggering blit
  output logic [31:0] dbg_blit_wh,     // {r_width, r_height} of the triggering blit
  output logic [15:0] dbg_blit_cmd,    // the triggering DMA_COMMAND value
  output logic        dbg_exec_start,  // one cycle in S_SETUP for every launched command
  output logic        dbg_exec_done,   // one cycle after that command's writes have drained
  output logic [31:0] dbg_exec_src     // setup-selected source (queue/restart/live aware)
`endif
);

  // ---- pixel op codes (midtunit_v.h:57-59 op_type_t) ---------------------
  localparam logic [1:0] OP_SKIP  = 2'd0;
  localparam logic [1:0] OP_COLOR = 2'd1;
  localparam logic [1:0] OP_COPY  = 2'd2;

  // ---- Register file -----------------------------------------------------
  logic [15:0] regf [DMA_NREGS];
  logic        busy_r;
  logic        cadence_valid_r;
  logic [17:0] cadence_x_reload_r;
  logic [17:0] cadence_x_rem_r;
  logic [17:0] cadence_y_rem_r;
  logic [15:0] cadence_xstep_r;
  logic [15:0] cadence_ystep_r;
  logic [6:0]  cadence_phase_r;
  // DMA2.DOC DGO semantics. halt_pending_r seeks the next source-safe walker
  // boundary; walker_halted_r freezes there while queued writes drain;
  // paused_r marks the fully drained halt; kill_pending_r tracks a second zero.
  logic        halt_pending_r;
  logic        walker_halted_r;
  logic        paused_r;
  logic        kill_pending_r;
  // A replacement GO may arrive while the second-zero kill is still waiting
  // for an asserted source/write request to finish. The same snapshot also
  // preserves the first normal busy-time GO; MAME submits adjacent component
  // blits before the preceding modeled DMA timer has expired.
  logic [15:0] restart_regf [DMA_NREGS];
  logic        restart_pending_r;
  logic        setup_from_restart_r;
  // MAME's fight/attract bursts can stack mirrored background components
  // deeply. At the measured silicon-shaped DDR latency, a 96-entry queue
  // overflowed and discarded 15 commands even though the frame met deadline.
  localparam integer NORMAL_Q_PTR_W = $clog2(NORMAL_Q_DEPTH);
  localparam integer NORMAL_Q_CNT_W = $clog2(NORMAL_Q_DEPTH + 1);
  localparam integer NORMAL_Q_WORD_W = DMA_NREGS * 16;
  (* ramstyle = "M10K, no_rw_check" *)
  logic [NORMAL_Q_WORD_W-1:0] normal_q_mem [0:NORMAL_Q_DEPTH-1];
  logic [NORMAL_Q_WORD_W-1:0] normal_q_push_word;
  logic [NORMAL_Q_WORD_W-1:0] normal_launch_word;
  logic [NORMAL_Q_WORD_W-1:0] launch_image_r;
  logic [NORMAL_Q_PTR_W-1:0] normal_q_wptr, normal_q_rptr;
  logic [NORMAL_Q_CNT_W-1:0] normal_q_count;
  // Retained for SignalTap/post-fit inspection. Overflow is sticky until core
  // reset; high-water covers the complete run rather than one queued burst.
  (* preserve *) logic normal_q_overflow_r;
  (* preserve *) logic [NORMAL_Q_CNT_W-1:0] normal_q_highwater_r;
  logic        setup_from_normal_q_r;
  // Explicit wrap keeps non-power-of-two parameter overrides safe too.
  wire normal_q_wptr_last = (normal_q_wptr == NORMAL_Q_DEPTH-1);
  wire normal_q_rptr_last = (normal_q_rptr == NORMAL_Q_DEPTH-1);

  integer qi;
  always_comb begin
    for (qi = 0; qi < DMA_NREGS; qi = qi + 1)
      normal_q_push_word[qi*16 +: 16] = regf[qi];
    // COMMAND is the write that triggers this snapshot, so its new value is
    // not visible in regf until after the same clock edge.
    normal_q_push_word[DMA_COMMAND*16 +: 16] = reg_wdata;
  end

  // Constant-select helpers (continuous assigns; safe on Icarus).
  wire [15:0] cmd_reg  = regf[DMA_COMMAND];
  wire [15:0] r_lrskip = regf[DMA_LRSKIP];
  wire [15:0] r_offlo  = regf[DMA_OFFSETLO];
  wire [15:0] r_offhi  = regf[DMA_OFFSETHI];
  wire [15:0] r_xstart = regf[DMA_XSTART];
  wire [15:0] r_ystart = regf[DMA_YSTART];
  wire [15:0] r_width  = regf[DMA_WIDTH];
  wire [15:0] r_height = regf[DMA_HEIGHT];
  wire [15:0] r_pal    = regf[DMA_PALETTE];
  wire [15:0] r_color  = regf[DMA_COLOR];
  wire [15:0] r_scalex = regf[DMA_SCALE_X];
  wire [15:0] r_scaley = regf[DMA_SCALE_Y];
  wire [15:0] r_top    = regf[DMA_TOPCLIP];
  wire [15:0] r_bot    = regf[DMA_BOTCLIP];
  wire [15:0] r_left   = regf[DMA_LEFTCLIP];
  wire [15:0] r_right  = regf[DMA_RIGHTCLIP];
  wire [15:0] r_config = regf[DMA_CONFIG];

  // regbank = (dma_register[DMA_CONFIG] >> 5) & 1 (midtunit_v.cpp:702);
  // regnum = register_map[regbank][offset] (:697-706) via wolf_pkg::dma_regmap.
  wire        cfg_bank  = r_config[5];
  wire [4:0]  regnum_w  = dma_regmap(cfg_bank, reg_addr);
  wire        wdata_trig = reg_wdata[DMA_CMD_TRIG_BIT];
  wire        reg_write_accepted_w = reg_we && (!REG_WRITE_BACKPRESSURE || reg_ready);
  wire        command_w  = reg_write_accepted_w && (regnum_w == DMA_COMMAND);
  wire        offered_go_w = reg_we && (regnum_w == DMA_COMMAND) && wdata_trig;
  // Trigger ONLY when the write lands on DMA_COMMAND and the NEW command has
  // bit15 (:709-717; COMBINE_DATA with mem_mask=0xffff = full-word replace,
  // so the new command IS reg_wdata).
  wire        trig_w    = command_w && wdata_trig;
  logic       timeout_stop_armed_r;
  logic [5:0] timeout_stop_age_r;
  // reg_ready is always1 for STOP: proposed_go_w contains wdata_trig.
  // Decoding from the offer removes the unrelated pixel/publication cone.
  wire        stop_w_raw = reg_we && (regnum_w == DMA_COMMAND) && !wdata_trig;
  wire        timeout_stop_context_w = DRAIN_QUEUED_ON_STOP && busy_r &&
                                        ((normal_q_count != 0) || cadence_valid_r);
  wire        timeout_pair_resume_w = stop_w_raw && timeout_stop_armed_r;
  wire        queued_stop_defer_w = timeout_pair_resume_w;
  wire        stop_w    = stop_w_raw && !timeout_pair_resume_w;
  // Every conjunct in reg_ready is true in this resume context. Other GOs,
  // including kill/replacement traffic, keep the original acceptance gate.
  wire        resume_context_w = busy_r && !kill_pending_r &&
                                  (paused_r || halt_pending_r || walker_halted_r);
  wire        resume_go_w = resume_context_w ? offered_go_w : trig_w;
  wire        resume_w  = resume_go_w || timeout_pair_resume_w;

  // MAME schedules dma_done from the SCALED output geometry:
  //   ((width << 8) / xstep) * ((height << 8) / ystep)
  // (midtunit_v.cpp:820-835). Keep the same count without synthesizing two
  // variable dividers: fixed-point remainders retire floor(width_fp/xstep)
  // pixel ticks per row and floor(height_fp/ystep) rows. This also keeps the
  // game's adjacent timeout-stop pair in the compatibility context for large
  // scaled Motaro/fatality components instead of killing the active blit.
  wire [15:0] cadence_xstep_w = (r_scalex != 16'h0000) ? r_scalex : 16'h0100;
  wire [15:0] cadence_ystep_w = (r_scaley != 16'h0000) ? r_scaley : 16'h0100;
  wire [17:0] cadence_width_fp_w  = {r_width[9:0], 8'h00};
  wire [17:0] cadence_height_fp_w = {r_height[9:0], 8'h00};
  wire        cadence_nonzero_w =
      (cadence_width_fp_w >= {2'b00, cadence_xstep_w}) &&
      (cadence_height_fp_w >= {2'b00, cadence_ystep_w});
  wire        cadence_start_w = TIMED_IRQ_PUMP && trig_w && (cadence_nonzero_w || RETIRE_IRQ_FENCE);
  // Seed with dimension-step+1. With the <=step terminal comparison this
  // retires floor(dimension/step) ticks for both divisible and non-divisible
  // fixed-point dimensions, exactly matching MAME's integer divisions.
  wire [17:0] cadence_x_init_w =
      cadence_width_fp_w - {2'b00, cadence_xstep_w} + 18'd1;
  wire [17:0] cadence_y_init_w =
      cadence_height_fp_w - {2'b00, cadence_ystep_w} + 18'd1;
  wire        cadence_immediate_w =
      TIMED_IRQ_PUMP && trig_w && !cadence_nonzero_w;
  // One geometric pixel consumes 105/32 clocks. Accumulating 32 phase units
  // per clock and retiring a pixel at 105 gives ceil(pixels*105/32) exactly,
  // without putting WIDTH*HEIGHT*105 multipliers on the COMMAND-write path.
  wire [7:0]  cadence_phase_next_w = {1'b0, cadence_phase_r} + 8'd32;
  wire        cadence_pixel_tick_w = (cadence_phase_next_w >= 8'd105);
  wire        cadence_time_elapsed_w =
      TIMED_IRQ_PUMP && cadence_valid_r && cadence_pixel_tick_w &&
      (cadence_x_rem_r <= {2'b00, cadence_xstep_r}) &&
      (cadence_y_rem_r <= {2'b00, cadence_ystep_r});

`ifdef DIAG_FLIP
  assign dbg_blit_trig = trig_w;
  assign dbg_blit_src  = {r_offhi, r_offlo};   // {SAGH, SAGL} at the trigger
  assign dbg_blit_wh   = {r_width, r_height};
  assign dbg_blit_cmd  = reg_wdata;            // the triggering DMA_COMMAND (bit15 set)
`endif

  assign busy        = busy_r;
  assign dma_palette = r_pal;
  assign dbg_q_overflow  = normal_q_overflow_r;
  assign dbg_q_highwater = normal_q_highwater_r;

  // dma_r: offset 0 reads as register 1 (midtunit_v.cpp:638-645); reads do
  // NOT use register_map and return the stored register verbatim. In
  // particular, DGO reads zero immediately after STOP even if this RTL still
  // has a private source/write handshake to retire before the kill is safe.
  wire [3:0]  eff_raddr = (reg_addr == 4'd0) ? 4'd1 : reg_addr;
  wire [14:0] cmd_lo15  = cmd_reg[14:0];
  assign reg_rdata = regf[{1'b0, eff_raddr}];

  // ---- FSM ---------------------------------------------------------------
  typedef enum logic [4:0] {
    S_IDLE, S_TRIG, S_SETUP, S_ROWCHK,   // S_TRIG (2026-07-12): 1-cycle wait so regf[COMMAND] is
    S_SKB0, S_SKB1, S_SKDIV, S_SKMUL, S_SKAPP, // row-head skip byte (Skip=1)
    S_ROWPREP,                        // y-clip + endskip clamp
    S_RPDIV, S_RPMUL, S_RPAPP, S_RPGAP, // startskip: seq-divide, *xstep, apply, timing gap
    S_PIX, S_PXB0, S_PXB1, S_WR,      // pixel loop
    S_RAMUL0, S_RAMUL1, S_ROWADV,     // row advance: reg operands, *bpp, apply
    S_SACHK, S_SAB0, S_SAB1,          // Scale+Skip multi-row skip-ahead
    S_SAMUL0, S_SAMUL1, S_SAAPP,      //   ... reg operand, *bpp, apply
    S_DONE
  } state_t;
  state_t state, state_n;

  // Four queued writes decouple the pixel walker from the level-held
  // framebuffer request. The writer pops one entry into registered outputs,
  // holds it through fb_ack, then necessarily spends a full cycle with fb_we
  // low before it can pop the next entry.
  localparam int FBQ_DEPTH = 4;
  logic [FB_ADDR_W-1:0] fbq_addr [0:FBQ_DEPTH-1];
  logic [15:0]          fbq_data [0:FBQ_DEPTH-1];
  logic [1:0]           fbq_wptr_r, fbq_rptr_r;
  logic [2:0]           fbq_count_r;
  logic                 fb_writer_active_r;
  wire                  fbq_empty_w = (fbq_count_r == 3'd0);
  wire                  fbq_full_w  = (fbq_count_r == 3'd4);
  wire                  fb_writer_idle_w = !fb_writer_active_r && !fb_we;
  wire                  local_writes_drained_w = fbq_empty_w && fb_writer_idle_w;

  // A stop may not withdraw an asserted source request. Once that request is
  // acknowledged, walker_halted_r freezes its successor before another source
  // request or framebuffer enqueue can begin. The independent writer continues
  // until every already-queued write has been acknowledged.
  // src_req also covers the overlapped unity-8bpp prefetch in S_WR/S_PIX.
  // Treat any asserted request as a source wait so DGO stop/kill cannot
  // withdraw it before acknowledgement or change its address mid-transaction.
  wire source_wait_w = src_req;
  wire walker_boundary_w = !source_wait_w || src_ack;

  wire first_stop_w  = stop_w && busy_r && !paused_r &&
                       !halt_pending_r && !walker_halted_r && !kill_pending_r;
  wire second_stop_w = stop_w && busy_r &&
                       (paused_r || halt_pending_r || walker_halted_r || kill_pending_r);
  wire halt_request_w = halt_pending_r || first_stop_w;
  wire kill_request_w = kill_pending_r || second_stop_w;

  // A DGO=1 command wins while the first halt is seeking/draining its safe
  // boundary. A second zero is irrevocable: queued-but-unissued writes may be
  // discarded, but an asserted writer request and source request both finish.
  wire stop_boundary_enter_w = !resume_w && !walker_halted_r && !paused_r &&
                               (halt_request_w || kill_request_w) && walker_boundary_w;
  wire stop_source_advance_w = stop_boundary_enter_w && source_wait_w && src_ack;
  wire walker_kill_safe_w = walker_halted_r || paused_r || walker_boundary_w;
  wire kill_enter_w = !resume_w && kill_request_w && walker_kill_safe_w &&
                      !fb_writer_active_r;
  wire pause_enter_w = !resume_go_w && !kill_request_w && !paused_r &&
                       (walker_halted_r || stop_boundary_enter_w) &&
                       local_writes_drained_w;
  // Boolean reduction of the stop/kill gates. Under !paused&&!halted,
  // boundary && !(src_req&&src_ack) reduces to !src_req. Keeping the request
  // term shallow avoids serial kill/boundary gates on every walker enable.
  wire fsm_step_w = !paused_r && !walker_halted_r &&
                    (resume_w ||
                     ((!(halt_request_w || kill_request_w) || source_wait_w) &&
                      (!kill_request_w || fb_writer_active_r ||
                       (source_wait_w && !src_ack))));
  // A source-free state has no in-flight request to drain. Use this exact
  // specialization only where the FSM guarantees src_req=0 (S_DONE below).
  // This removes the unsensitizable ix->pix_remain->src_req path from the
  // wide queued-command launch register and M10K read-address enables.
  wire nosrc_step_w = !paused_r && !walker_halted_r &&
                      (resume_w || !(halt_request_w || kill_request_w));

  // In the six explicit source-wait states, source_wait_w is exactly one
  // whenever the walker is neither paused nor halted. Specialize the step
  // gate there, and use nosrc_step_w in source-free states. This avoids the
  // S_PIX cache-miss cone driving unrelated setup/row register enables.
  // The dynamic S_PIX/S_WR actions retain the full fsm_step_w contract.
  wire srcstate_step_w = !paused_r && !walker_halted_r &&
                         (resume_w || !kill_request_w ||
                          fb_writer_active_r || !src_ack);

  // The empty IDLE cleanup has no source request (src_req is state-qualified).
  // Specialize its priority gate so the queue read pointer does not receive
  // the pixel-cache -> stop-boundary -> pause cone for an IDLE-only reset.
  // kill_enter_w remains unchanged, preserving an active transfer's drain.
  wire normal_q_idle_clear_w = !busy_r && (state == S_IDLE) &&
      (kill_pending_r || (!resume_w &&
       (paused_r || !local_writes_drained_w ||
        (!walker_halted_r && !halt_pending_r))));
  wire normal_q_clear_w = kill_enter_w || normal_q_idle_clear_w;

  // ---- Latched blit parameters (S_SETUP; dma_w:721-796) ------------------
  // Constant per command; keeps the source request path free of a pixel-width adder.
  logic [3:0]         straddle_limit_c;
  logic [3:0]         bpp_c;                 // (command>>12)&7, 0 => 8 (:722, .ipp:12)
  logic [1:0]         zero_c, nz_c;          // op table (.ipp:49-81)
  logic               need_px_c;             // pixel value needed by the ops
  logic               xflip_c, yflip_c, skip_c, scale_c;
  logic [1:0]         preskip_c, postskip_c; // :734-735
  logic [15:0]        xstep_c, ystep_c;      // :736-737 (0 -> 0x100)
  logic [9:0]         width_c, xpos_c;       // :725,:727
  logic [9:0]         height_c;              // :728
  logic [15:0]        pal16_c, color16_c;    // :729-730, dma_draw:437-438
  logic [8:0]         topclip_c, botclip_c;  // :740-741
  logic [9:0]         leftclip_c, rightclip_c; // :742-743
  logic signed [31:0] startskip_c, endskip_c;  // :787-796
  logic [31:0]        offset_r;              // row-base source offset, BITS (:436)
  logic [31:0]        o_r;                   // working source offset, BITS (:454)
  // Cursors start at zero and advance only while below a 10-bit size
  // shifted by eight. One 16-bit step can overshoot to at most 327422.
  // A signed 20-bit value retains the original signed comparisons.
  localparam integer CURSOR_W = COMPACT_WALKER ? 20 : 32;
  // width_fp can be (width - 16-bit endskip)<<8, minimum -16776960.
  localparam integer WIDTH_FP_W = COMPACT_WALKER ? 25 : 32;
  logic signed [CURSOR_W-1:0] ix, iy;                // 8.8 fixed-point cursors (:440,:452)
  logic signed [WIDTH_FP_W-1:0] width_fp;              // width<<8, post/endskip-adjusted (:450)
  logic [9:0]         sx;                    // dest column, &XPOSMASK (:451)
  logic [8:0]         sy;                    // dest row, &YPOSMASK (:439)
  logic signed [31:0] pre_r, post_r;         // row skip-byte pre/post, fp (:465,:474)
  logic [7:0]         b0_r;                  // fetched byte base[o>>3]
  logic [7:0]         b1_r;                  // byte base[(o>>3)+1] (cache-hit path; the
                                             // fetch path still uses live src_data)
  // ---- W-THRU1: 2-entry src byte cache (fetch reduction) --------------------
  // The draw loop fetched TWO bytes per pixel unconditionally; the real UMK3
  // blits run bpp 4/6 where consecutive pixels SHARE source bytes, and a byte-
  // aligned field (o_lo3+bpp<=8) never needs byte1 at all. Cache the last two
  // distinct fetched bytes (gfx ROM is read-only: no invalidation hazard) and
  // skip handshakes on hits: 2x (bpp8) .. 4x (bpp4) fewer src round trips.
  // Field math is UNCHANGED — the window is just sourced from cache when valid.
  logic [31:0] bc_prev0, bc_prev1; // cached tag minus one, for second-byte probes
  logic [31:0] bc_a0, bc_a1;   // byte addresses (most recent first)
  logic [7:0]  bc_d0, bc_d1;
  logic        bc_v0, bc_v1;
  logic [7:0]         skipval_r;             // EXTRACTGEN(0xff) result
  logic [7:0]         px_r;                  // EXTRACTGEN(mask) result
  // Skip-ahead rows are ty-1, where an 8.8 carry from a 16-bit step
  // yields at most 256 rows. Decrement is issued only for a nonzero count.
  localparam integer SA_COUNT_W = COMPACT_WALKER ? 8 : 32;
  logic [SA_COUNT_W-1:0] sa_cnt;                // remaining skip-ahead rows
  // The unity-8bpp look-ahead address is formed while entering S_WR and then
  // launched from these registers.  Besides matching the state transition
  // naturally, this keeps the o_r + byte-select cone out of the same 80 MHz
  // cycle as the DDR cache tag compare / promotion controls.
  logic [31:0]        fast_src_prefetch_addr_r;
  logic               fast_src_prefetch_ready_r;
  logic               fast_src_carry_r;       // hold the S_WR request/address until ack
  logic [31:0]        src_state_addr_r;        // address registered on entry to a fetch state
  logic               src_early_valid_r;       // registered address is valid already in S_PIX
  // ---- shared sequential unsigned divider (radix-2 restoring, 32-cycle) ----
  // Replaces the two combinational '/' sites (tx_skip = pre/xstep :466 and
  // tx2 = (ss_diff/xstep)*xstep :486). A 32/32 COMBINATIONAL divide (~3800-cell
  // Div1) was the design Fmax bottleneck: a ~90ns cloud on the once-per-row
  // ix->o_r startskip path. Sequencing it costs ~32 idle cycles per skip/
  // startskip row-head (negligible vs a hundreds-of-cycle pixel loop) and is
  // bit-identical: floor(num/den) == Verilog '/' == the model's '//' (operands
  // are non-negative and den=xstep>=1 always, xstep_w :736 never 0).
  logic [4:0]         state_q1;              // previous state (div-start edge)
  logic               drun;                  // divider iterating
  logic [5:0]         dcnt;                  // remaining bit steps
  localparam integer QUOT_W = COMPACT_WALKER ? 16 : 32;
  logic [QUOT_W-1:0] dquo;
  wire [18:0] dquo_mul_w = dquo;
  logic [31:0]        dnum, dden; // dividend shift / divisor / quotient
  // Every restoring step leaves remainder < divisor, whose maximum is 65535.
  // Keep the shifted trial value one bit wider to retain the carry.
  localparam integer DIV_REM_W = COMPACT_DIVIDER ? 16 : 32;
  logic [DIV_REM_W-1:0] drem;
  wire [DIV_REM_W:0] drem_trial_w = {drem, dnum[31]};
  // Divider numerators are pre_skip<=30720 or startskip_fp-ix<=65280.
  // Both the quotient and quotient*xstep therefore fit in sixteen bits.
  wire [31:0] txm_u32_w = txm_r;
  logic [QUOT_W-1:0] txm_r;                 // dquo*xstep, pre-multiplied (:471,:487)

  // ---- row-advance multiply pacing ----------------------------------------
  // The per-row source-pointer advances (:580,:590,:600 etc.) were combinational
  // multiplies fed by long compute chains (ty_w = f(iy,ystep), w2_ns/w3_ns) all
  // in one cycle. With the divide gone these became the Fmax bottleneck
  // (offset_r -10.7ns, o_r -6.1ns). They run ONCE PER ROW, so we sequence them:
  // S_SETUP precomputes rowbits = width*bpp (constant per blit); the pre-states
  // register the narrowed operands and then the *bpp products, so the apply
  // states (S_ROWADV / S_SAAPP) are pure adds. Bit-identical (bounded operands).
  logic               clip_gap;              // timing bubble: forces >=2 cycles between an
                                             // ix write and any clip-run o_r consume, making
                                             // the sdc ix->o_r multicycle-2 architecturally
                                             // safe (see S_PIX TIMING comment)
  logic [13:0]        rowbits_r;             // width_c * bpp_c (:580 factor)
  logic [8:0]         tyr_r;                 // ty_w, scale row count (<=256)
  logic [10:0]        w2p_r, w3p_r;          // (w2_ns/w3_ns > 0 ? : 0), <=width
  logic [31:0]        radv_r;                // tyr_r * rowbits_r (:590)
  logic [31:0]        w2adv_r, w3adv_r;      // w2p_r/w3p_r * bpp_c (:576,:604)

  // ---- S_SETUP decode (comb from the accepted command image; dma_w) -------
  // Normal commands consume regf after S_TRIG. A GO queued behind an
  // irrevocable kill consumes the frozen image captured on that GO instead.
  // Keep these as explicit muxes: Icarus does not reliably synthesize a
  // variable-index unpacked-array read from an automatic function here.
  wire [15:0] s_cmd     = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_COMMAND*16 +: 16] : cmd_reg) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_COMMAND*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_COMMAND] : cmd_reg);
  wire [15:0] s_lrskip  = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_LRSKIP*16 +: 16] : r_lrskip) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_LRSKIP*16 +: 16]  : setup_from_restart_r ? restart_regf[DMA_LRSKIP]  : r_lrskip);
  wire [15:0] s_offlo   = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_OFFSETLO*16 +: 16] : r_offlo) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_OFFSETLO*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_OFFSETLO] : r_offlo);
  wire [15:0] s_offhi   = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_OFFSETHI*16 +: 16] : r_offhi) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_OFFSETHI*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_OFFSETHI] : r_offhi);
  wire [15:0] s_xstart  = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_XSTART*16 +: 16] : r_xstart) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_XSTART*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_XSTART] : r_xstart);
  wire [15:0] s_ystart  = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_YSTART*16 +: 16] : r_ystart) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_YSTART*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_YSTART] : r_ystart);
  wire [15:0] s_width   = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_WIDTH*16 +: 16] : r_width) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_WIDTH*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_WIDTH] : r_width);
  wire [15:0] s_height  = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_HEIGHT*16 +: 16] : r_height) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_HEIGHT*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_HEIGHT] : r_height);
  wire [15:0] s_pal     = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_PALETTE*16 +: 16] : r_pal) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_PALETTE*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_PALETTE] : r_pal);
  wire [15:0] s_color   = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_COLOR*16 +: 16] : r_color) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_COLOR*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_COLOR] : r_color);
  wire [15:0] s_scalex  = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_SCALE_X*16 +: 16] : r_scalex) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_SCALE_X*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_SCALE_X] : r_scalex);
  wire [15:0] s_scaley  = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_SCALE_Y*16 +: 16] : r_scaley) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_SCALE_Y*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_SCALE_Y] : r_scaley);
  wire [15:0] s_top     = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_TOPCLIP*16 +: 16] : r_top) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_TOPCLIP*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_TOPCLIP] : r_top);
  wire [15:0] s_bot     = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_BOTCLIP*16 +: 16] : r_bot) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_BOTCLIP*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_BOTCLIP] : r_bot);
  wire [15:0] s_left    = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_LEFTCLIP*16 +: 16] : r_left) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_LEFTCLIP*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_LEFTCLIP] : r_left);
  wire [15:0] s_right   = SHARED_COMMAND_IMAGE ?
      ((setup_from_normal_q_r || setup_from_restart_r) ? launch_image_r[DMA_RIGHTCLIP*16 +: 16] : r_right) :
      (setup_from_normal_q_r ? normal_launch_word[DMA_RIGHTCLIP*16 +: 16] : setup_from_restart_r ? restart_regf[DMA_RIGHTCLIP] : r_right);

  wire [3:0]  mode_w     = s_cmd[3:0];
  wire        xflip_w    = s_cmd[4];         // XFlip enters the dispatch as
                                               // (command&0x1f) bit4 (.ipp:66-81)
  wire        yflip_w    = s_cmd[5];         // :733
  wire        lrsplit_w  = s_cmd[6];         // :787 (command & 0x40)
  wire        skip_w     = s_cmd[7];         // :813/:822 (command & 0x80)
  wire [1:0]  preskip_w  = s_cmd[9:8];       // :734
  wire [1:0]  postskip_w = s_cmd[11:10];     // :735
  wire [3:0]  bpp_w      = dma_bpp(s_cmd);   // :722 + .ipp:12 (bpp 0 => 8)
  wire [15:0] xstep_w    = (s_scalex == 16'd0) ? 16'h0100 : s_scalex; // :736
  wire [15:0] ystep_w    = (s_scaley == 16'd0) ? 16'h0100 : s_scaley; // :737
  wire        scale_w    = (xstep_w != 16'h0100) || (ystep_w != 16'h0100); // :811

  // mode -> (Zero, NonZero) per the dispatch-table construction,
  // midtunit_v.ipp:49-81 (confirmed identical to midtunit_v.cpp:874-890).
  logic [1:0] zero_w, nz_w;
  always_comb begin
    case (mode_w)
      4'h1:         begin zero_w = OP_COPY;  nz_w = OP_SKIP;  end // P0   (.ipp:51)
      4'h2:         begin zero_w = OP_SKIP;  nz_w = OP_COPY;  end // P1   (.ipp:52)
      4'h3:         begin zero_w = OP_COPY;  nz_w = OP_COPY;  end // P0P1 (.ipp:53)
      4'h4, 4'h5:   begin zero_w = OP_COLOR; nz_w = OP_SKIP;  end // C0   (.ipp:54-55)
      4'h6, 4'h7:   begin zero_w = OP_COLOR; nz_w = OP_COPY;  end // C0P1 (.ipp:56-57)
      4'h8, 4'hA:   begin zero_w = OP_SKIP;  nz_w = OP_COLOR; end // C1   (.ipp:58,60)
      4'h9, 4'hB:   begin zero_w = OP_COPY;  nz_w = OP_COLOR; end // P0C1 (.ipp:59,61)
      4'hC, 4'hD,
      4'hE, 4'hF:   begin zero_w = OP_COLOR; nz_w = OP_COLOR; end // C0C1 (.ipp:62-65)
      default:      begin zero_w = OP_SKIP;  nz_w = OP_SKIP;  end // 0 = none (.ipp:50/66)
    endcase
  end
  wire draw_none_w = (mode_w == 4'h0);
  // pixel value is read when the two ops differ (:519) or when both are COPY
  // (:513-514); both-COLOR never touches the source pixel (:511-512).
  wire need_px_w = (zero_w != nz_w) || (zero_w == OP_COPY);

  // gfxoffset determination (:745-763)
  wire [31:0] gfxoff0 = (mode_w == 4'hC) ? 32'd0                    // :749-750
                                         : {s_offhi, s_offlo};      // :746
  wire [31:0] gfxoff1 = ((GFX_ROM_LARGE == 1'b0) && (gfxoff0 >= 32'h0200_0000))
                        ? (gfxoff0 - 32'h0200_0000) : gfxoff0;      // :753-754 (inert on Wolf)
  wire [31:0] gfxoff2 = (gfxoff1 >= 32'hF800_0000)
                        ? (gfxoff1 - 32'hF800_0000) : gfxoff1;      // :755-756
  wire        skipdma_w = (gfxoff2 >= 32'h1000_0000);               // :757-762

  // startskip/endskip split on command&0x40 (:787-796)
  wire [31:0] startskip_w = lrsplit_w ? {24'd0, s_lrskip[7:0]}  : 32'd0;            // :789 / :794
  wire [31:0] endskip_w   = lrsplit_w ? {24'd0, s_lrskip[15:8]} : {16'd0, s_lrskip}; // :790 / :795

  // Constant part-selects hoisted out of always_ff (Icarus portability, per
  // the yunit_dma convention).
  wire [9:0] w_width10  = s_width[9:0];    // :727 (& 0x3ff)
  // This small unsigned product has the same14-bit context as rowbits_r.
  // Keep it in logic so setup's command-image mux need not feed a DSP.
  (* multstyle = "logic" *) wire [13:0] rowbits_setup_w;
  assign rowbits_setup_w = w_width10 * bpp_w;
  wire [9:0] w_height10 = s_height[9:0];   // :728 (& 0x3ff)
  wire [9:0] w_xpos10   = s_xstart[9:0];   // :725 (& XPOSMASK)
  wire [8:0] w_ypos9    = s_ystart[8:0];   // :726 (& YPOSMASK)
  wire [7:0] w_color8   = s_color[7:0];    // :730 (& 0xff)
  wire [8:0] w_top9     = s_top[8:0];      // :740 (& 0x1ff)
  wire [8:0] w_bot9     = s_bot[8:0];      // :741 (& 0x1ff)
  wire [9:0] w_left10   = s_left[9:0];     // :742 (& 0x3ff)
  wire [9:0] w_right10  = s_right[9:0];    // :743 (& 0x3ff)

  // ---- Draw-engine combinational helpers ----------------------------------
  wire [31:0] xstep32   = {16'd0, xstep_c};
  wire signed [31:0] xstep_s = $signed({16'd0, xstep_c});
  wire [31:0] bpp32     = {28'd0, bpp_c};
  wire [31:0] width32   = {22'd0, width_c};
  wire signed [31:0] height_fp = $signed({22'd0, height_c}) <<< 8;  // :434

  // EXTRACTGEN window (portable form, :427): bytes base[o>>3], base[(o>>3)+1].
  wire [31:0] o_byte0 = {3'b000, o_r[31:3]};
  wire [31:0] o_byte1 = o_byte0 + 32'd1;
  wire [2:0]  o_lo3   = o_r[2:0];
  // b1 side: live fetch during S_PXB1, else the cache-latched b1_r (don't-care
  // when !px_straddle — those bits are shifted/masked away below).
  // live during EVERY state that consumes the arriving byte1 (pixel, row-head
  // skip, scale skip-ahead); cache-latched b1_r otherwise.
  wire [7:0]  b1_eff   = ((state == S_PXB1) || (state == S_SKB1) || (state == S_SAB1))
                         ? src_data : b1_r;
  wire [15:0] win_now  = {b1_eff, b0_r};         // b1 | b0 latched
  wire [15:0] win_sh   = win_now >> o_lo3;
  wire [7:0]  byte_now = win_sh[7:0];            // EXTRACTGEN(0xff)
  wire [8:0]  maskfull = (9'd1 << bpp_c) - 9'd1; // (1<<bpp)-1 (:442)
  // W-THRU1: does the field spill into byte1? bpp_c is 1..8, o_lo3 0..7.
  wire        px_straddle = {1'b0, o_lo3} > straddle_limit_c;
  // Look-ahead is consumed only by the write state or a clipped pixel
  // advance. All actual pixel/skip fetches probe the current source address.
  // Both consumers below capture only on an actual next-pixel advance.
  // The current-pixel probe is separate, so selecting o_r in unused cycles
  // only inserted the late clip decision ahead of this address/tag cone.
  // Every write/clip advance has an intervening pixel or gap cycle.
  // Register the selected next pointer there for both scaled and unscaled
  // draws, so neither pointer addition precedes the cache-tag comparisons
  // in the address-capture cycle. This reuses the existing look-ahead
  // register and adds no cycle. Current-pixel probes remain live.
  logic [31:0] scaled_lookup_o_r;
  always_ff @(posedge clk) begin
    if (rst) scaled_lookup_o_r <= 32'd0;
    else scaled_lookup_o_r <= scale_c ? sc_next_o_w : ns_next_o_w;
  end
  wire [31:0] lookup_o_w = scaled_lookup_o_r;
  wire [31:0] lookup_byte0_w = {3'b000, lookup_o_w[31:3]};
  wire [31:0] lookup_byte1_w = lookup_byte0_w + 32'd1;
  // Partition the full tag equality into independently kept byte groups.
  // This changes only the combinational tree, not a bit, valid gate or cycle.
  (* keep = "true" *) wire [3:0] lookup_cache0_equal_byte_w;
  (* keep = "true" *) wire [3:0] lookup_cache1_equal_byte_w;
  for (genvar lookup_cache_chunk = 0; lookup_cache_chunk < 4; lookup_cache_chunk++) begin : lookup_cache_equal_bytes
    assign lookup_cache0_equal_byte_w[lookup_cache_chunk] =
        bc_a0[8*lookup_cache_chunk +: 8] == lookup_byte0_w[8*lookup_cache_chunk +: 8];
    assign lookup_cache1_equal_byte_w[lookup_cache_chunk] =
        bc_a1[8*lookup_cache_chunk +: 8] == lookup_byte0_w[8*lookup_cache_chunk +: 8];
  end
  wire lookup_hit0_w = (bc_v0 && (&lookup_cache0_equal_byte_w)) ||
                       (bc_v1 && (&lookup_cache1_equal_byte_w));
  // Keep the four independent byte comparisons as a balanced tree. The
  // fitted wide equality otherwise serializes late next-offset bits through
  // seven LUT levels before the source-address register's byte select.
  // All32 bits remain compared, including the previous-address wrap bits.
  (* keep = "true" *) wire [3:0] lookup_prev0_equal_byte_w;
  (* keep = "true" *) wire [3:0] lookup_prev1_equal_byte_w;
  for (genvar lookup_chunk = 0; lookup_chunk < 4; lookup_chunk++) begin : lookup_equal_bytes
    assign lookup_prev0_equal_byte_w[lookup_chunk] =
        bc_prev0[8*lookup_chunk +: 8] == lookup_byte0_w[8*lookup_chunk +: 8];
    assign lookup_prev1_equal_byte_w[lookup_chunk] =
        bc_prev1[8*lookup_chunk +: 8] == lookup_byte0_w[8*lookup_chunk +: 8];
  end
  wire lookup_hit1_w = (bc_v0 && (&lookup_prev0_equal_byte_w)) ||
                       (bc_v1 && (&lookup_prev1_equal_byte_w));
  wire lookup_straddle_w = {1'b0, lookup_o_w[2:0]} > straddle_limit_c;
  wire [31:0] lookup_req_addr_w = lookup_hit0_w && lookup_straddle_w && !lookup_hit1_w
                                  ? lookup_byte1_w : lookup_byte0_w;
  // Current probes must not depend on the following pixel's scaled pointer.
  // S_PIX/current fetches only use o_r; look-ahead has its separate probe above.
  // This removes an unsensitizable next-pointer path through src_req -> STOP.
  wire hit0 = (bc_v0 && (bc_a0 == o_byte0)) || (bc_v1 && (bc_a1 == o_byte0));
  wire hit1 = (bc_v0 && (bc_prev0 == o_byte0)) || (bc_v1 && (bc_prev1 == o_byte0));
  wire [7:0] hitd0 = (bc_v0 && (bc_a0 == o_byte0)) ? bc_d0 : bc_d1;
  wire [7:0] hitd1 = (bc_v0 && (bc_prev0 == o_byte0)) ? bc_d0 : bc_d1;
  wire        need_f0 = !hit0;
  wire        need_f1 = px_straddle && !hit1;
  wire [31:0] cur_req_addr_w = (!need_f0 && need_f1) ? o_byte1 : o_byte0;
  // Unscaled draws know the following source position during S_WR. Precompute
  // its first missing byte into src_state_addr_r so the following S_PIX can
  // launch immediately from a register, retaining the old overlap without a
  // live o_r -> GFX cache path.
  wire [31:0] ns_next_o_w = o_r + bpp32;
  wire [31:0] ns_next_byte0_w = {3'b000, ns_next_o_w[31:3]};
  wire [31:0] ns_next_byte1_w = ns_next_byte0_w + 32'd1;
  wire ns_next_straddle_w = {1'b0, ns_next_o_w[2:0]} > straddle_limit_c;
  wire ns_next_hit0_w = (bc_v0 && (bc_a0 == ns_next_byte0_w)) ||
                        (bc_v1 && (bc_a1 == ns_next_byte0_w));
  wire ns_next_hit1_w = (bc_v0 && (bc_a0 == ns_next_byte1_w)) ||
                        (bc_v1 && (bc_a1 == ns_next_byte1_w));
  wire ns_next_need0_w = !ns_next_hit0_w;
  wire ns_next_need1_w = ns_next_straddle_w && !ns_next_hit1_w;
  wire [31:0] ns_next_req_addr_w = (!ns_next_need0_w && ns_next_need1_w)
                                     ? ns_next_byte1_w : ns_next_byte0_w;
  wire [7:0]  pixmask  = maskfull[7:0];
  // cache-only window (S_PIX -> S_WR direct path: both bytes from cache). Declared AFTER
  // hitd0/hitd1/pixmask (Questa FSE 25.1std enforces declaration-before-use for wires
  // referenced in another continuous assign — see wolf_top.sv's P0019 comment for the same
  // rule cited elsewhere in this project). Pure reorder; the synthesized combinational logic
  // is unchanged (no dependency cycle — hitd0/hitd1/pixmask never reference win_cache/px_cache).
  wire [15:0] win_cache = {hitd1, hitd0};
  wire [7:0]  px_cache  = (win_cache >> o_lo3) & {8'd0, pixmask};
  wire [7:0]  px_now   = byte_now & pixmask;     // EXTRACTGEN(mask)

  // S_SKAPP: row-head skip byte application (:461-476)
  wire [4:0]  presh_w   = {3'd0, preskip_c}  + 5'd8;  // '<< (preskip + 8)' (:465)
  wire [4:0]  postsh_w  = {3'd0, postskip_c} + 5'd8;  // '<< (postskip + 8)' (:474)
  wire [31:0] pre_fp_w  = {28'd0, skipval_r[3:0]} << presh_w;
  wire [31:0] post_fp_w = {28'd0, skipval_r[7:4]} << postsh_w;
  wire [9:0]  tx_skip10 = dquo[9:0];  // low bits of tx = pre/xstep quotient (:467)

  // S_ROWPREP: y clip (:480), startskip (:484-489), endskip clamp (:491-493)
  wire        y_clip_w  = (sy < topclip_c) || (sy > botclip_c);
  wire signed [31:0] ss_fp   = startskip_c <<< 8;     // startskip << 8 (:448)
  wire [31:0] ss_diff_w = $unsigned(ss_fp - ix);      // guarded by ix < ss_fp

  // Sequential-divider control. Unity xstep has an exact shift quotient and an
  // exact dividend product, so it bypasses both the divider and multiply state.
  // Other xsteps retain the 32-cycle divider path unchanged.
  wire        entering_skdiv = (state == S_SKDIV) && (state_q1 != S_SKDIV);
  wire        entering_rpdiv = (state == S_RPDIV) && (state_q1 != S_RPDIV);
  wire        xstep_unity_w = (xstep_c == 16'h0100);
  wire        fast_skdiv_w = entering_skdiv && xstep_unity_w;
  wire        fast_rpdiv_w = entering_rpdiv && xstep_unity_w;
  wire        div_go   = (entering_skdiv | entering_rpdiv) && !xstep_unity_w;
  wire [31:0] div_num  = entering_skdiv ? pre_fp_w : ss_diff_w;
  wire [31:0] div_den  = xstep32;
  wire        div_busy = drun | div_go;
  wire signed [31:0] we_lim = $signed(width32) - endskip_c; // width - endskip (:492)

  // S_PIX / S_WR: per-pixel clip (:506) and advance (:542-559)
  wire        pix_remain = (ix < width_fp);           // :503 (signed)
  wire        in_clip    = (sx >= leftclip_c) && (sx <= rightclip_c); // :506
  wire [31:0] ix_u = $unsigned(ix);
  wire [16:0] dx_fp_sum_w = {9'd0, ix[7:0]} + {1'b0, xstep_c};
  wire [31:0] dx_w = SHARED_WALKER_ARITH ? {23'd0, dx_fp_sum_w[16:8]} :
                     ((ix_u + xstep32) >> 8) - (ix_u >> 8); // :555-557
  // dx = integer(xstep) + carry(fraction(ix)+fraction(xstep)). The two
  // products depend only on command parameters. Register them during the
  // existing SETUP/ROWCHK/ROWPREP lead-in; pixel scheduling is unchanged.
  logic [11:0] sc_step_floor_r, sc_step_ceil_r;
  wire [11:0] sc_step_base_w = xstep_c[15:8] * bpp_c;
  always_ff @(posedge clk) begin
    if (rst) begin sc_step_floor_r <= 0; sc_step_ceil_r <= 0; end
    else begin
      sc_step_floor_r <= sc_step_base_w;
      sc_step_ceil_r <= sc_step_base_w + {8'd0,bpp_c};
    end
  end
  wire [8:0] sc_fraction_sum_w = {1'b0,ix[7:0]} + {1'b0,xstep_c[7:0]};
  wire [11:0] sc_step_bits_w = sc_fraction_sum_w[8] ? sc_step_ceil_r : sc_step_floor_r;
  wire [31:0] sc_next_o_w = o_r + {20'd0,sc_step_bits_w};
  wire [31:0] sc_next_byte0_w = {3'b000, sc_next_o_w[31:3]};
  wire [31:0] sc_next_byte1_w = sc_next_byte0_w + 32'd1;
  wire sc_next_straddle_w = {1'b0, sc_next_o_w[2:0]} > straddle_limit_c;
  wire sc_next_hit0_w = (bc_v0 && (bc_a0 == sc_next_byte0_w)) ||
                        (bc_v1 && (bc_a1 == sc_next_byte0_w));
  wire sc_next_hit1_w = (bc_v0 && (bc_a0 == sc_next_byte1_w)) ||
                        (bc_v1 && (bc_a1 == sc_next_byte1_w));
  wire sc_next_need0_w = !sc_next_hit0_w;
  wire sc_next_need1_w = sc_next_straddle_w && !sc_next_hit1_w;
  wire [31:0] sc_next_req_addr_w = (!sc_next_need0_w && sc_next_need1_w)
                                     ? sc_next_byte1_w : sc_next_byte0_w;
  // Sequential unity 8-bpp draws dominate the missing Hangtime/UMK3 backdrop
  // cases. Start the next byte during the current pixel's write state so the
  // registered one-beat GFX cache can answer while the walker advances. The
  // next S_PIX consumes that response directly; misses fall through to the
  // ordinary held-request states with no change to field extraction.
  wire signed [31:0] ix_next_unity_w = ix + 32'sd256;
  wire [9:0] sx_next_unity_w = xflip_c ? (sx - 10'd1) : (sx + 10'd1);
  wire next_unity_in_clip_w = (sx_next_unity_w >= leftclip_c) &&
                              (sx_next_unity_w <= rightclip_c);
  wire [31:0] o_next_bpp8_w = o_r + 32'd8;
  wire [31:0] o_next_byte0_w = {3'b000, o_next_bpp8_w[31:3]};
  wire [31:0] o_next_byte1_w = o_next_byte0_w + 32'd1;
  wire fast_src_prefetch_w = (state == S_WR) &&
                             !fbq_full_w && fast_src_prefetch_ready_r;
  wire [31:0] fast_src_prefetch_addr_w = fast_src_prefetch_addr_r;
  wire pix_src_demand_w = (state == S_PIX) && pix_remain && in_clip &&
                          need_px_c && (need_f0 || need_f1);

  // S_WR: pixel op resolution (:508-538)
  wire [1:0]  op_eff_w   = (zero_c == nz_c) ? zero_c
                          : ((px_r != 8'd0) ? nz_c : zero_c);
  wire        do_write_w = (op_eff_w != OP_SKIP);
  // COLOR writes color=pal|color (:438,:512,:525); COPY writes pixel|pal
  // (:514,:527) — for a zero pixel that equals pal (:536).
  wire [15:0] pix_data_w = (op_eff_w == OP_COLOR) ? color16_c
                                                  : ({8'd0, px_r} | pal16_c);
  // d = &videoram[sy*512]; d[sx] (:499). sx NOT re-masked to 511.
  wire [FB_ADDR_W-1:0] fb_addr_w =
      ({{(FB_ADDR_W-9){1'b0}}, sy} << FB_ROWSHIFT) + {{(FB_ADDR_W-10){1'b0}}, sx};

  // S_WR is the sole FIFO producer. The writer consumes only entries that
  // were already present at the start of the cycle; a full FIFO therefore
  // backpressures S_WR for one cycle even if the writer pops concurrently.
  wire fbq_push_w = fsm_step_w && (state == S_WR) && do_write_w && !fbq_full_w;
  wire fbq_discard_w = kill_request_w;
  wire fbq_pop_w = !fb_writer_active_r && !fbq_empty_w && !kill_request_w;
  wire fbq_backpressure_w = (state == S_WR) && do_write_w && fbq_full_w;
  wire dma_done_ready_w = local_writes_drained_w && !wr_busy;
`ifdef DIAG_FACEOFF
  // Match the exact pixel-retirement condition in S_WR. A write blocked by a
  // full local FIFO is reported only when it can really advance; a skipped
  // pixel reports immediately because it consumes no bandwidth.
  assign diag_px_evt     = fsm_step_w && (state == S_WR) &&
                           (!do_write_w || !fbq_full_w);
  assign diag_px_x       = sx;
  assign diag_px_y       = sy;
  assign diag_px_write   = do_write_w;
  assign diag_px_copy_nz = (op_eff_w == OP_COPY) && (px_r != 8'd0);
  assign diag_px_color   = (op_eff_w == OP_COLOR);
`endif
`ifdef DIAG_FLIP
  // Qualify both markers with the same walker step that consumes the state.
  // This keeps a diagnostic event one-shot even if pause/halt holds the FSM.
  assign dbg_exec_start = (state == S_SETUP) && fsm_step_w;
  assign dbg_exec_done  = (state == S_DONE) && dma_done_ready_w && fsm_step_w;
  assign dbg_exec_src   = {s_offhi, s_offlo};
`endif
  // Retiring one serialized command is distinct from completing the entire
  // queued burst. Internal handoffs keep COMMAND[15], busy, and IRQ state
  // intact; software-visible completion occurs only after the final image.
  wire blit_retire_w = (state == S_DONE) && dma_done_ready_w && nosrc_step_w;
  wire normal_pop_w = blit_retire_w && !trig_w && !restart_pending_r &&
                      (normal_q_count != 0);
  wire final_done_w = blit_retire_w && !trig_w && !restart_pending_r &&
                      (normal_q_count == 0);
  wire cadence_complete_w = cadence_time_elapsed_w &&
                            (!RETIRE_IRQ_FENCE || !busy_r || final_done_w);
  wire normal_push_context_w = busy_r && !kill_pending_r &&
                               !paused_r && !walker_halted_r && !halt_pending_r;
  wire proposed_go_w = (regnum_w == DMA_COMMAND) && wdata_trig;
  // Do not depend on reg_we here: a stalled GO must NOT suppress normal_pop_w
  // or the retiring command could never free a full queue. The one-slot kill
  // replacement image also must not be overwritten by another proposed GO.
  wire publication_blocks_go = (go_hold === 1'b1) &&
                               !(busy_r && !kill_pending_r && (paused_r || walker_halted_r || halt_pending_r));
  assign reg_ready = !proposed_go_w ||
                     (!publication_blocks_go && (!normal_push_context_w || (!WAIT_GO_RETIRED && (normal_q_count < NORMAL_Q_DEPTH))) &&
                      !(kill_pending_r && restart_pending_r));
  wire normal_push_eligible_w = trig_w && normal_push_context_w;
  wire normal_push_w = normal_push_eligible_w &&
                       (normal_q_count < NORMAL_Q_DEPTH);
  wire normal_overflow_w = normal_push_eligible_w &&
                           (normal_q_count == NORMAL_Q_DEPTH);

  // S_ROWADV: row advance (:562-608)
  wire [31:0] iy_u = $unsigned(iy);
  wire [16:0] ty_fp_sum_w = {9'd0, iy[7:0]} + {1'b0, ystep_c};
  wire [31:0] ty_w = SHARED_WALKER_ARITH ? {23'd0, ty_fp_sum_w[16:8]} :
                    ((iy_u + {16'd0, ystep_c}) >> 8) - (iy_u >> 8); // :585-587
  // width - ((pre + post) >> 8): shared by noscale+skip (:575) and the first
  // skip-ahead row (:595); pre/post are the fp-scaled row-head values.
  wire signed [31:0] w2_ns    = $signed(width32) - ((pre_r + post_r) >>> 8);

  // S_SAAPP: subsequent skip-ahead rows (:597-605). NOTE: '<< preskip' with
  // NO +8 here (:601-602) — transcribed exactly as MAME has it, do not
  // "normalize" to the row-head +8 form.
  wire [31:0]        pre2_w  = {28'd0, skipval_r[3:0]} << preskip_c;   // :601
  wire [31:0]        post2_w = {28'd0, skipval_r[7:4]} << postskip_c;  // :602
  wire signed [31:0] w3_ns   = $signed(width32) - $signed(pre2_w) - $signed(post2_w); // :603

  // The source walker changes only one pointer per selected FSM action.
  // Sharing the adders keeps their carry chains out of each state's data mux.
  // The start-skip product has only QUOT_W-8 by four useful input bits.
  // Keep this small product in logic to avoid a cascaded 32-bit DSP path
  // ahead of the source-pointer adder. Zero extension preserves all bits.
  (* multstyle = "logic" *) wire [QUOT_W-5:0] rp_skip_bits_w =
      txm_r[QUOT_W-1:8] * bpp_c;
  logic [31:0] walker_o_delta_w;
  always_comb begin
    case (state)
      S_SKAPP:  walker_o_delta_w = 32'd8;
      S_RPAPP:  walker_o_delta_w = rp_skip_bits_w;
      S_ROWADV: walker_o_delta_w = 32'd8 + w2adv_r;
      S_SAAPP:  walker_o_delta_w = 32'd8 + w3adv_r;
      default:  walker_o_delta_w = scale_c ? {20'd0,sc_step_bits_w} : bpp32;
    endcase
  end
  wire [31:0] walker_o_sum_w = ((state == S_ROWADV) ? offset_r : o_r) + walker_o_delta_w;
  wire [31:0] walker_offset_delta_w = scale_c ? radv_r :
                                      skip_c ? (32'd8 + w2adv_r) : {18'd0,rowbits_r};
  wire [31:0] walker_offset_sum_w = offset_r + walker_offset_delta_w;
  wire [31:0] walker_ix_delta_w = ((state == S_SKAPP) || (state == S_RPAPP)) ? txm_r :
                                  scale_c ? {16'd0,xstep_c} : 32'd256;
  wire signed [31:0] walker_ix_sum_w = ix + $signed(walker_ix_delta_w);
  wire signed [31:0] walker_iy_sum_w = iy + $signed(scale_c ? {16'd0,ystep_c} : 32'd256);
  wire [9:0] walker_sx_delta_w = (state == S_SKAPP) ? tx_skip10 : 10'd1;
  wire [9:0] walker_sx_sum_w = sx + (walker_sx_delta_w ^ {10{xflip_c}}) + {9'd0,xflip_c};

  // ---- next-state ----------------------------------------------------------
  always_comb begin
    state_n = state;
    case (state)
      S_IDLE:    if (trig_w) state_n = S_TRIG;
      // S_TRIG: DEFECT-A FIX (2026-07-12) — regf[COMMAND] is written AT the trigger; S_SETUP consumes
      // the skipdma_w/draw_none_w cone (32-bit mux+add+compare) combinationally from cmd_reg. Going
      // straight S_IDLE->S_SETUP made regf[COMMAND]->state a REAL 1-cycle path that sdram.sdc:118
      // relaxes to multicycle-2 (true only for the 14 data regs, programmed early). The fitter was
      // licensed to ~20.8ns on a path that captures in one 10.4ns cycle -> silicon mis-capture ->
      // skipdma_w wrongly asserts on complex (sprite) cones -> S_SETUP->S_DONE = blit skipped, zero
      // writes (cab: portraits absent while fills draw). This wait state makes cmd_reg stable a full
      // cycle before S_SETUP, so the path is genuinely 2 cycles = the multicycle-2 license is honest.
      S_TRIG:    state_n = S_SETUP;
      // skipdma (:759-762) and mode 0 (draw_none, .ipp:50/66) draw nothing
      // but still complete (:834-835 schedules dma_done either way).
      S_SETUP:   if (skipdma_w || draw_none_w) state_n = S_DONE;
                 else                          state_n = S_ROWCHK;
      S_ROWCHK:  if (iy < height_fp) begin                         // :446
                   if (skip_c) state_n = S_SKB0; else state_n = S_ROWPREP;
                 end else state_n = S_DONE;
      S_SKB0:    if (src_ack) state_n = S_SKB1;
      S_SKB1:    if (src_ack) state_n = S_SKDIV;
      S_SKDIV:   if (xstep_unity_w) state_n = S_SKAPP;
                  else if (!div_busy) state_n = S_SKMUL;  // wait: dquo = pre/xstep
      S_SKMUL:   state_n = S_SKAPP;                 // form txm_r = dquo*xstep
      S_SKAPP:   state_n = S_ROWPREP;
      S_ROWPREP: if (y_clip_w)        state_n = S_RAMUL0;  // :480-481 (row still advances)
                 else if (ix < ss_fp) state_n = S_RPDIV;   // startskip (:484)
                 else                 state_n = S_PIX;
      S_RPDIV:   if (xstep_unity_w) state_n = S_RPAPP;
                  else if (!div_busy) state_n = S_RPMUL;  // wait: dquo = ss_diff/xstep
      S_RPMUL:   state_n = S_RPAPP;                 // form txm_r = dquo*xstep
      // S_RPAPP writes o_r. Keep one full edge between that write and the
      // first S_PIX source-address capture so the scaled-next-offset cone is
      // a genuine two-cycle path without changing any draw address or order.
      S_RPAPP:   state_n = S_RPGAP;
      S_RPGAP:   state_n = S_PIX;
      S_PIX:     if (!pix_remain)      state_n = S_RAMUL0;        // :503 -> row advance
                 else if (!in_clip)    state_n = S_PIX;            // clipped: advance only
                 // A request launched from the preceding S_WR can already be
                 // returning here. Consume it without entering a wait state.
                 else if (need_px_c && need_f0 && src_ack) begin
                   if (need_f1) state_n = S_PXB1;
                   else         state_n = S_WR;
                 end
                 else if (need_px_c && need_f1 && src_ack)
                   state_n = S_WR;
                 // W-THRU1: skip handshakes the cache can serve
                 else if (need_px_c && need_f0) state_n = S_PXB0;
                 else if (need_px_c && need_f1) state_n = S_PXB1;  // b0 cached, b1 not
                 else                  state_n = S_WR;             // fill/no-read or full hit
      S_PXB0:    if (src_ack) begin  // W-THRU1: byte1 only if needed
                   if (need_f1) state_n = S_PXB1; else state_n = S_WR;
                 end
      S_PXB1:    if (src_ack) state_n = S_WR;
      // Resolve one pixel locally. Transparent pixels advance immediately;
      // write-producing pixels advance once the local FIFO has room.
      S_WR:      if (do_write_w && fbq_full_w) state_n = S_WR; else state_n = S_PIX;
      S_RAMUL0:  state_n = S_RAMUL1;               // reg tyr_r, w2p_r
      S_RAMUL1:  state_n = S_ROWADV;               // reg radv_r, w2adv_r
      S_ROWADV:  if (scale_c && skip_c && (tyr_r != 9'd0)) state_n = S_SACHK;
                 else                                      state_n = S_ROWCHK; // :592
      S_SACHK:   if (sa_cnt == 32'd0) state_n = S_ROWCHK; else state_n = S_SAB0; // :597
      S_SAB0:    if (src_ack) state_n = S_SAB1;
      S_SAB1:    if (src_ack) state_n = S_SAMUL0;
      S_SAMUL0:  state_n = S_SAMUL1;               // reg w3p_r
      S_SAMUL1:  state_n = S_SAAPP;                // reg w3adv_r
      S_SAAPP:   state_n = S_SACHK;
      S_DONE:    if (!dma_done_ready_w) state_n = S_DONE;
                  // Every GO accepted in S_DONE is snapshotted into the normal
                  // queue. Stay here on that edge, even when the old blit has
                  // drained, then launch the oldest queued image next cycle.
                  // Besides preserving ordering, this keeps downstream
                  // wr_busy out of the wide queue-register write-enable cone.
                  else if (trig_w) state_n = S_DONE;
                  else if (trig_w || restart_pending_r || (normal_q_count != 0)) state_n = S_TRIG;
                  else             state_n = S_IDLE;      // hazard as S_IDLE; route through S_TRIG too
      default:   state_n = S_IDLE;
    endcase

  end

  // source fetch request/address (byte-granular)
  assign src_req  = !paused_r && !walker_halted_r &&
                    (fast_src_prefetch_w ||
                     ((fast_src_carry_r || src_early_valid_r) &&
                      (state == S_PIX) && pix_src_demand_w) ||
                     (state == S_SKB0) || (state == S_SKB1) ||
                     (state == S_PXB0) || (state == S_PXB1) ||
                     (state == S_SAB0) || (state == S_SAB1));
  assign src_addr = fast_src_prefetch_w ? fast_src_prefetch_addr_w :
                    fast_src_carry_r    ? fast_src_prefetch_addr_w :
                                          src_state_addr_r;
  // Scheduling hint only: source address, data, and handshake semantics stay
  // unchanged. These long sequential runs can safely fill several independent
  // one-beat cache entries ahead of the walker.
  assign src_active = busy_r && need_px_c && !scale_c;
  assign src_stream = src_active && (bpp_c == 4'd8);

  // Every software-visible dma_done clears stored COMMAND bit15 before it
  // asserts IRQ (midtunit_v.cpp:624-627). The private renderer can remain
  // busy behind this boundary; `busy` is the page-publication/write-drain
  // fence, while reg_rdata is the ASIC status consumed by game software.
  // A same-edge CPU COMMAND write is ordered last and starts the next modeled
  // command exactly as MAME's dma_w does.
  // The private renderer retires far earlier than the modeled device cadence
  // (a small command in ~332 clocks where MAME still owes ~3380). Publishing
  // completion on that physical edge raises LINT1 -> INTPEND.X1P early, so
  // Open Ice's DMA ISR preempts the DISPLAY producer loop and consumes the
  // descriptor queue before it is written. While the cadence still owes an
  // IRQ, physical retirement stays private and does not cancel the cadence.
  wire        sw_final_done_w = final_done_w &&
                                !(TIMED_IRQ_PUMP && cadence_valid_r);
  wire        done_clear_w = sw_final_done_w || cadence_complete_w;
  // A COMMAND write has last priority over cadence Y. In its absence,
  // trig_w, stop_w and timeout_pair_resume_w are all zero. Specializing the
  // retirement predicate for that branch avoids feeding the late accepted-GO
  // / publication gate through the physical-done decoder and back to Y clear.
  // The renderer, IRQ and every other counter retain their original logic.
  wire cadence_retire_uncommanded_w = (state == S_DONE) &&
      local_writes_drained_w && !wr_busy && !paused_r && !walker_halted_r &&
      !halt_pending_r && !kill_pending_r && !restart_pending_r &&
      (normal_q_count == 0);
  wire cadence_y_end_uncommanded_w =
      (cadence_retire_uncommanded_w && !cadence_valid_r) ||
      (cadence_time_elapsed_w &&
       (!RETIRE_IRQ_FENCE || !busy_r || cadence_retire_uncommanded_w));
  always_ff @(posedge clk) begin
    if (rst) cadence_y_rem_r <= 18'd0;
    else if (TIMED_IRQ_PUMP) begin
      if (command_w)
        cadence_y_rem_r <= (wdata_trig && cadence_nonzero_w) ? cadence_y_init_w : 18'd0;
      else if (cadence_y_end_uncommanded_w)
        cadence_y_rem_r <= 18'd0;
      else if (cadence_valid_r && cadence_pixel_tick_w &&
               (cadence_x_rem_r <= {2'b00, cadence_xstep_r}) &&
               (cadence_y_rem_r > {2'b00, cadence_ystep_r}))
        cadence_y_rem_r <= cadence_y_rem_r - {2'b00, cadence_ystep_r};
    end else if (fsm_step_w && (state == S_DONE) && nosrc_step_w && sw_final_done_w)
      cadence_y_rem_r <= 18'd0;
  end

  wire [4:0]  done_idx_w = DMA_COMMAND;
  wire [15:0] done_val_w = {1'b0, cmd_lo15};

  // A queued launch and a replacement after kill never overlap: normal_pop
  // requires !trig_w, while replacement capture requires trig_w. Both images
  // are consumed only by S_SETUP, so one bank replaces the two 288-bit banks.
  always_ff @(posedge clk) begin
    if (rst) launch_image_r <= '0;
    else if (SHARED_COMMAND_IMAGE) begin
      if (trig_w && kill_pending_r && !restart_pending_r)
        launch_image_r <= normal_q_push_word;
      else if (normal_pop_w)
        launch_image_r <= normal_q_mem[normal_q_rptr];
    end
  end

  // ---- ordered local framebuffer-write FIFO + registered writer ---------
  // Popping transfers an entry into the output registers; that entry is no
  // longer in the FIFO but remains protected by fb_writer_active_r until ack.
  // Since a pop can only occur while inactive, an ack edge can only deassert
  // fb_we; the next assertion is at least one complete clock later.
  always_ff @(posedge clk) begin
    if (rst) begin
      fbq_wptr_r <= 2'd0;
      fbq_rptr_r <= 2'd0;
      fbq_count_r <= 3'd0;
      fb_writer_active_r <= 1'b0;
      fb_we <= 1'b0;
      fb_addr <= '0;
      fb_wdata <= 16'd0;
    end else begin
      if (fb_writer_active_r) begin
        if (fb_ack) begin
          fb_writer_active_r <= 1'b0;
          fb_we <= 1'b0;
        end
      end else begin
        fb_we <= 1'b0;
        if (fbq_pop_w) begin
          fb_writer_active_r <= 1'b1;
          fb_we <= 1'b1;
          fb_addr <= fbq_addr[fbq_rptr_r];
          fb_wdata <= fbq_data[fbq_rptr_r];
        end
      end

      if (fbq_discard_w) begin
        fbq_rptr_r <= fbq_wptr_r;
        fbq_count_r <= 3'd0;
      end else begin
        if (fbq_push_w) begin
          fbq_addr[fbq_wptr_r] <= fb_addr_w;
          fbq_data[fbq_wptr_r] <= pix_data_w;
          fbq_wptr_r <= fbq_wptr_r + 2'd1;
        end
        if (fbq_pop_w)
          fbq_rptr_r <= fbq_rptr_r + 2'd1;

        case ({fbq_push_w, fbq_pop_w})
          2'b10: fbq_count_r <= fbq_count_r + 3'd1;
          2'b01: fbq_count_r <= fbq_count_r - 3'd1;
          default: ;
        endcase
      end
    end
  end

  // ---- sequential unsigned divider (radix-2 restoring, MSB-first) ---------
  // dquo <- floor(div_num / div_den) over 32 steps, started by the div_go pulse
  // (S_SKDIV / S_RPDIV entry) and consumed after div_busy falls. state_q1 holds
  // the prior state so div_go fires exactly once per divide. den = xstep >= 1
  // always, so no divide-by-zero. Bit-identical to the old combinational '/'.
  always_ff @(posedge clk) begin
    if (rst) begin
      state_q1 <= 5'd0;                        // S_IDLE
      drun <= 1'b0; dcnt <= 6'd0;
      dnum <= 32'd0; dden <= 32'd0; drem <= 32'd0; dquo <= 32'd0;
    end else if (kill_enter_w) begin
      state_q1 <= 5'd0;
      drun <= 1'b0; dcnt <= 6'd0;
      dnum <= 32'd0; dden <= 32'd0; drem <= 32'd0; dquo <= 32'd0;
    end else if (!paused_r && !walker_halted_r &&
                 !stop_boundary_enter_w && !pause_enter_w) begin
      state_q1 <= state;
      if (fast_skdiv_w) begin
        drun <= 1'b0; dcnt <= 6'd0;
        dquo <= pre_fp_w >> 8;
      end else if (fast_rpdiv_w) begin
        drun <= 1'b0; dcnt <= 6'd0;
        dquo <= ss_diff_w >> 8;
      end else if (div_go) begin
        drun <= 1'b1; dcnt <= 6'd32;
        dnum <= div_num; dden <= div_den;
        drem <= 32'd0;   dquo <= 32'd0;
      end else if (drun) begin
        if (drem_trial_w >= dden) begin
          drem <= drem_trial_w - dden;
          dquo <= {dquo[QUOT_W-2:0], 1'b1};
        end else begin
          drem <= drem_trial_w;
          dquo <= {dquo[QUOT_W-2:0], 1'b0};
        end
        dnum <= {dnum[30:0], 1'b0};
        dcnt <= dcnt - 6'd1;
        if (dcnt == 6'd1) drun <= 1'b0;
      end
    end
  end

  // ---- registers -----------------------------------------------------------
  integer i;
  always_ff @(posedge clk) begin
    if (rst) begin
      state    <= S_IDLE;
      blit_irq <= 1'b0;
      busy_r   <= 1'b0;
      cadence_valid_r <= 1'b0;
      cadence_x_reload_r <= 18'd0;
      cadence_x_rem_r <= 18'd0;
      cadence_xstep_r <= 16'h0100;
      cadence_ystep_r <= 16'h0100;
      cadence_phase_r <= 7'd0;
      timeout_stop_armed_r <= 1'b0;
      timeout_stop_age_r <= 6'd0;
      halt_pending_r <= 1'b0;
      walker_halted_r <= 1'b0;
      paused_r       <= 1'b0;
      kill_pending_r <= 1'b0;
      restart_pending_r <= 1'b0;
      setup_from_restart_r <= 1'b0;
      normal_q_wptr <= '0;
      normal_q_rptr <= '0;
      normal_q_count <= '0;
      normal_q_overflow_r <= 1'b0;
      normal_q_highwater_r <= '0;
      normal_launch_word <= '0;
      setup_from_normal_q_r <= 1'b0;
      for (i = 0; i < DMA_NREGS; i = i + 1) begin
        regf[i] <= 16'h0000;
        restart_regf[i] <= 16'h0000;
      end
      straddle_limit_c <= 4'd8;
      bpp_c <= 4'd0; zero_c <= OP_SKIP; nz_c <= OP_SKIP; need_px_c <= 1'b0;
      xflip_c <= 1'b0; yflip_c <= 1'b0; skip_c <= 1'b0; scale_c <= 1'b0;
      preskip_c <= 2'd0; postskip_c <= 2'd0;
      xstep_c <= 16'h0100; ystep_c <= 16'h0100;
      width_c <= 10'd0; height_c <= 10'd0; xpos_c <= 10'd0;
      pal16_c <= 16'd0; color16_c <= 16'd0;
      topclip_c <= 9'd0; botclip_c <= 9'd0;
      leftclip_c <= 10'd0; rightclip_c <= 10'd0;
      startskip_c <= 32'sd0; endskip_c <= 32'sd0;
      offset_r <= 32'd0; o_r <= 32'd0;
      ix <= 32'sd0; iy <= 32'sd0; width_fp <= 32'sd0; clip_gap <= 1'b1;
      sx <= 10'd0; sy <= 9'd0;
      pre_r <= 32'sd0; post_r <= 32'sd0;
      b0_r <= 8'd0; b1_r <= 8'd0; skipval_r <= 8'd0; px_r <= 8'd0;
      fast_src_prefetch_addr_r <= 32'd0;
      fast_src_prefetch_ready_r <= 1'b0;
      fast_src_carry_r <= 1'b0;
      src_state_addr_r <= 32'd0;
      src_early_valid_r <= 1'b0;
      bc_prev0 <= 32'hFFFFFFFE; bc_prev1 <= 32'hFFFFFFFE;
      bc_a0 <= 32'hFFFFFFFF; bc_a1 <= 32'hFFFFFFFF; bc_d0 <= 8'd0; bc_d1 <= 8'd0;
      bc_v0 <= 1'b0; bc_v1 <= 1'b0;
      sa_cnt <= 32'd0; txm_r <= 32'd0;
      rowbits_r <= 14'd0; tyr_r <= 9'd0; w2p_r <= 11'd0; w3p_r <= 11'd0;
      radv_r <= 32'd0; w2adv_r <= 32'd0; w3adv_r <= 32'd0;
    end else begin
      state <= state_n;

      // MAIN.ASM's timeout pair is two adjacent CPU stores (13 MAME CPU
      // clocks in the captured UI frame).  Keep the recognition window short
      // so an intentional later second stop still performs a true kill.
      if (trig_w || !busy_r) begin
        timeout_stop_armed_r <= 1'b0;
        timeout_stop_age_r <= 6'd0;
      end else if (timeout_pair_resume_w) begin
        timeout_stop_armed_r <= 1'b0;
        timeout_stop_age_r <= 6'd0;
      end else if (stop_w_raw && timeout_stop_context_w) begin
        timeout_stop_armed_r <= 1'b1;
        timeout_stop_age_r <= 6'd63;
      end else if (timeout_stop_armed_r) begin
        if (timeout_stop_age_r == 6'd0)
          timeout_stop_armed_r <= 1'b0;
        else
          timeout_stop_age_r <= timeout_stop_age_r - 6'd1;
      end

      // Software-visible completion cadence. A same-edge COMMAND write is
      // deliberately handled later and therefore clears this IRQ/starts the
      // next interval, matching dma_w's clear-before-GO ordering. The
      // retirement fence holds the terminal count until physical completion;
      // if physical completion wins first, the cadence retains its deadline.
      if (TIMED_IRQ_PUMP && cadence_valid_r) begin
        if (cadence_pixel_tick_w) begin
          cadence_phase_r <= cadence_phase_next_w - 8'd105;
          if (cadence_x_rem_r <= {2'b00, cadence_xstep_r}) begin
            if (cadence_y_rem_r <= {2'b00, cadence_ystep_r}) begin
              if (cadence_complete_w) begin
                cadence_valid_r <= 1'b0;
                cadence_x_rem_r <= 18'd0;
                blit_irq <= 1'b1;
              end
            end else begin
              cadence_x_rem_r <= cadence_x_reload_r;
            end
          end else begin
            cadence_x_rem_r <= cadence_x_rem_r -
                                {2'b00, cadence_xstep_r};
          end
        end else begin
          cadence_phase_r <= cadence_phase_next_w[6:0];
        end
      end

      // Once the walker reaches a stop boundary, hold it before its next
      // action. An acknowledged source request is consumed exactly once and
      // freezes in its successor while the local writer drains independently.
      if (paused_r || walker_halted_r) state <= state;
      if (stop_boundary_enter_w)
        state <= stop_source_advance_w ? state_n : state;
      if (kill_enter_w)
        state <= restart_pending_r ? S_TRIG : S_IDLE;
      if (kill_enter_w)
        fast_src_carry_r <= 1'b0;
      if (kill_enter_w)
        src_early_valid_r <= 1'b0;

      if (fsm_step_w) begin
        // Register the following pixel's source address on the edge that
        // enters S_WR.  S_WR still launches the request for the entire next
        // cycle, so this adds no fetch latency; it only inserts the physical
        // timing boundary missing from the first streaming implementation.
        if ((state != S_WR) && (state_n == S_WR)) begin
          fast_src_prefetch_addr_r <= (o_next_bpp8_w[2:0] != 3'd0)
                                      ? o_next_byte1_w : o_next_byte0_w;
          fast_src_prefetch_ready_r <= need_px_c && !scale_c &&
                                       (bpp_c == 4'd8) &&
                                       (ix_next_unity_w < width_fp) &&
                                       next_unity_in_clip_w;
        end else if ((state == S_WR) && (state_n != S_WR)) begin
          fast_src_prefetch_ready_r <= 1'b0;
        end

        // A streaming request starts during S_WR from the registered look-
        // ahead address. If it has not acknowledged by the S_WR->S_PIX edge,
        // keep that exact address selected through the ordinary wait states.
        if ((state == S_WR) && (state_n != S_WR) && fast_src_prefetch_w)
          fast_src_carry_r <= 1'b1;
        if (fast_src_carry_r && src_ack)
          fast_src_carry_r <= 1'b0;

        // ROW BOUNDARY: no source address may survive it. midtunit_v.cpp:454
        // declares `uint32_t o = offset;` INSIDE the height loop, so the source
        // bit pointer is RELOADED from the row base on every row; how far the
        // previous row actually drew is irrelevant to where the next one reads.
        // A carried look-ahead violates that. It only bites when the row ENDS
        // EARLY -- i.e. when the endskip clamp (:491-493) truncates the drawn
        // span below the full width -- because only then does the carried
        // address differ from the next row's base. Open Ice's rink is the case:
        // width 860, endskip 460, so 400 of 860 are drawn and the carry points
        // 460 pixels short of row N+1's start. Every row after the first then
        // begins from the wrong source data.
        // Rink-only in practice because this look-ahead is bpp==8 gated (:1087)
        // and the rink is the ONLY 8-bpp blit in the game -- which is why one
        // object class vanished while every 4-bpp sprite drew correctly.
        // Gate: sim/run_wolf_dma_matrix.sh rink_8bpp_endskip460_w860_h8
        //       (passes with this, FAILS without it; 4-bpp same-geometry and
        //        endskip-0 controls pass either way, proving it is bpp-gated).
        if (state_n == S_ROWPREP) begin
          fast_src_carry_r          <= 1'b0;
          fast_src_prefetch_ready_r <= 1'b0;
        end

        // Preload an address for the existing S_PIX request opportunity. Row
        // entry uses the current pointer; a write/clip advance uses the
        // following pointer, whose add and cache lookup terminate here in the
        // DMA rather than crossing into the GFX cache. The scaled pointer cone
        // has the same explicit two-cycle walker spacing as the o_r update;
        // rtl/sdram.sdc scopes that allowance only to this local register.
        if ((state == S_ROWPREP) && (state_n == S_PIX)) begin
          src_state_addr_r <= cur_req_addr_w;
          src_early_valid_r <= 1'b1;
        end else if ((state == S_WR) && (state_n == S_PIX)) begin
          src_state_addr_r <= SHARED_SOURCE_LOOKUP ? lookup_req_addr_w :
                              (scale_c ? sc_next_req_addr_w : ns_next_req_addr_w);
          src_early_valid_r <= 1'b1;
        end else if ((state == S_PIX) && pix_remain && !in_clip &&
                     !clip_gap) begin
          src_state_addr_r <= SHARED_SOURCE_LOOKUP ? lookup_req_addr_w :
                              (scale_c ? sc_next_req_addr_w : ns_next_req_addr_w);
          src_early_valid_r <= 1'b1;
        end else if ((state == S_RPAPP) ||
                     ((state_n == S_WR) && (state != S_WR))) begin
          src_early_valid_r <= 1'b0;
        end

        // Capture every non-streaming source address on the transition into
        // its existing fetch state. No FSM cycle is added; this prevents the
        // o_r/need/cache-tag cone from spanning DMA and GFX in one clock.
        if ((state == S_ROWCHK) && (state_n == S_SKB0))
          // S_ROWCHK publishes o_r <= offset_r on this same edge. Use the
          // already-stable row base here rather than the preceding row's o_r.
          src_state_addr_r <= {3'b000, offset_r[31:3]};
        else if ((state == S_SKB0) && src_ack)
          src_state_addr_r <= o_byte1;
        else if ((state == S_PIX) && !fast_src_carry_r) begin
          if (state_n == S_PXB0)      src_state_addr_r <= o_byte0;
          else if (state_n == S_PXB1) src_state_addr_r <= o_byte1;
        end else if ((state == S_PXB0) && src_ack && (state_n == S_PXB1))
          src_state_addr_r <= o_byte1;
        else if ((state == S_SACHK) && (state_n == S_SAB0))
          src_state_addr_r <= o_byte0;
        else if ((state == S_SAB0) && src_ack)
          src_state_addr_r <= o_byte1;

      end // shared source-address preparation

        case (state)
        // ---- latch the whole dma_state (dma_w:721-796) --------------------
        S_SETUP: if (nosrc_step_w) begin
          straddle_limit_c <= 4'd8 - bpp_w;
          bpp_c       <= bpp_w;
          zero_c      <= zero_w;
          nz_c        <= nz_w;
          need_px_c   <= need_px_w;
          xflip_c     <= xflip_w;
          yflip_c     <= yflip_w;
          skip_c      <= skip_w;
          scale_c     <= scale_w;
          preskip_c   <= preskip_w;
          postskip_c  <= postskip_w;
          xstep_c     <= xstep_w;                 // :736
          ystep_c     <= ystep_w;                 // :737
          width_c     <= w_width10;               // :727 (& 0x3ff)
          rowbits_r   <= rowbits_setup_w;        // width*bpp, precomputed (:580,:590)
          height_c    <= w_height10;              // :728 (& 0x3ff)
          xpos_c      <= w_xpos10;                // :725 (& XPOSMASK)
          pal16_c     <= s_pal & 16'h7f00;        // :729
          color16_c   <= (s_pal & 16'h7f00) | {8'd0, w_color8}; // :730,:438
          topclip_c   <= w_top9;                  // :740 (& 0x1ff)
          botclip_c   <= w_bot9;                  // :741
          leftclip_c  <= w_left10;                // :742 (& 0x3ff)
          rightclip_c <= w_right10;               // :743
          startskip_c <= $signed(startskip_w);    // :787-796
          endskip_c   <= $signed(endskip_w);
          offset_r    <= gfxoff2;                 // :758 (bits)
          sy          <= w_ypos9;                 // :726 (& YPOSMASK), :439
          iy          <= 32'sd0;                  // :440
          pre_r       <= 32'sd0;
          post_r      <= 32'sd0;
          clip_gap    <= 1'b1;
        end

        // ---- outer loop head: while (iy < height) (:446) -------------------
        S_ROWCHK: if (nosrc_step_w) begin
          if (iy < height_fp) begin
            width_fp <= $signed(width32) <<< 8;   // :450
            sx       <= xpos_c;                   // :451
            ix       <= 32'sd0;                   // :452
            o_r      <= offset_r;                 // :454
          end
        end

        // ---- Skip: leading EXTRACTGEN(0xff) byte (:459-477) ----------------
        S_SKB0: if (srcstate_step_w) if (src_ack) b0_r <= src_data;
        S_SKB1: if (srcstate_step_w) if (src_ack) skipval_r <= byte_now;
        S_SKDIV: if (nosrc_step_w) if (xstep_unity_w) txm_r <= pre_fp_w;
        // dquo (=pre/xstep) ready after S_SKDIV; pre-multiply by xstep here so
        // S_SKAPP's ix advance is a plain add (keeps the mul off the hot path).
        S_SKMUL: if (nosrc_step_w) txm_r <= dquo_mul_w * xstep_c;   // tx * xstep (:471), == dquo*xstep32
        S_SKAPP: if (nosrc_step_w) begin
          pre_r    <= $signed(pre_fp_w);          // :465
          post_r   <= $signed(post_fp_w);         // :474
          // sx +- tx, & XPOSMASK (:467-470); 10-bit wrap == &0x3ff
          sx       <= SHARED_WALKER_ARITH ? walker_sx_sum_w : (xflip_c ? (sx - tx_skip10) : (sx + tx_skip10));
          ix       <= SHARED_WALKER_ARITH ? walker_ix_sum_w : (ix + $signed(txm_u32_w));               // :471
          width_fp <= width_fp - $signed(post_fp_w);     // :475
          o_r      <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + 32'd8);                       // :462
        end

        // ---- y clip / end skip clamp (:480,:491-493). startskip (:484-488) is
        //      now sequenced through S_RPDIV/S_RPMUL/S_RPAPP (seq-divide). The
        //      clamp is independent of the ix/o_r startskip advance, so doing it
        //      here (before the divide) is equivalent to the fused :484-493.
        S_ROWPREP: if (nosrc_step_w) begin
          if (!y_clip_w) begin
            if ((width_fp >>> 8) > we_lim)        // :492
              width_fp <= we_lim <<< 8;           // :493
          end
        end
        S_RPDIV: if (nosrc_step_w) if (xstep_unity_w) txm_r <= ss_diff_w;
        S_RPMUL: if (nosrc_step_w) txm_r <= dquo_mul_w * xstep_c;   // tx2 = (ss_diff/xstep)*xstep
        S_RPAPP: if (nosrc_step_w) begin
          ix  <= SHARED_WALKER_ARITH ? walker_ix_sum_w : (ix + $signed(txm_u32_w));             // :487
          o_r <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + (rp_skip_bits_w));    // :488
          clip_gap <= 1'b1;                       // ix just changed -> bubble before any
                                                  // clip-advance consumes it (see TIMING)
        end

        // ---- pixel loop: while (ix < width) (:503-559) ---------------------
        // TIMING (measured, gfx5 STA): the ix -> dx_w -> *bpp -> o_r chain is ~11ns,
        // the single deepest cluster in the whole design (191 of the top 200 failing
        // paths at 96 MHz). Between REAL pixels the FSM spaces updates by >=2 cycles
        // (PXB0/PXB1/WR ack waits), but a CLIP RUN advanced every cycle — the one
        // back-to-back case. clip_gap forces every clip advance (and the first after
        // any other ix writer) onto every OTHER cycle, so rtl/sdram.sdc can declare
        // the chain multicycle-2 SAFELY. Cost: clipped pixels skip at half rate
        // (<=width extra cycles per clipped row-edge — noise vs the pixel loop).
        S_PIX: if (fsm_step_w) begin
          // W-THRU1 latches for the reduced-fetch paths (drawn pixel only)
          if (pix_remain && in_clip && need_px_c) begin
            if (hit0)                b0_r <= hitd0;   // cache serves byte0
            if (px_straddle && hit1) b1_r <= hitd1;   // cache serves byte1
            if (!need_f0 && !need_f1) px_r <= px_cache; // full hit: S_PIX -> S_WR direct
            // A unity-8bpp prefetch launched in the preceding S_WR may be
            // returning on this edge. The current cache state supplies the
            // other byte (when the field straddles); capture the exact same
            // EXTRACTGEN result that S_PXB0/S_PXB1 would have produced.
            if (src_ack && (need_f0 || need_f1)) begin
              if (need_f0) begin
                b0_r <= src_data;
                if (!need_f1)
                  px_r <= (({b1_r, src_data} >> o_lo3) & {8'd0, pixmask});
              end else begin
                b1_r <= src_data;
                px_r <= (({src_data, hitd0} >> o_lo3) & {8'd0, pixmask});
              end
            end
          end
          if (pix_remain && !in_clip) begin
            if (clip_gap) clip_gap <= 1'b0;       // bubble: let the o_r adder settle
            else begin
              // clipped pixel: no read/write, pointers still advance (:541-559)
              sx <= SHARED_WALKER_ARITH ? walker_sx_sum_w : (xflip_c ? (sx - 10'd1) : (sx + 10'd1));
              clip_gap <= 1'b1;
              if (!scale_c) begin
                ix  <= SHARED_WALKER_ARITH ? walker_ix_sum_w : (ix + 32'sd256);             // :550
                o_r <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + bpp32);               // :551
              end else begin
                ix  <= SHARED_WALKER_ARITH ? walker_ix_sum_w : (ix + xstep_s);              // :556
                o_r <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + {20'd0,sc_step_bits_w}); // :558 (narrowed: dx<=256, ==dx_w*bpp32)
              end
            end
          end
        end

        S_PXB0: if (srcstate_step_w) if (src_ack) begin
          b0_r <= src_data;
          // W-THRU1: byte1 fully cached (or not needed) -> compute the pixel NOW
          // from {b1_r-or-dontcare, arriving b0}; S_PXB1 is skipped.
          if (!need_f1) px_r <= (({b1_r, src_data} >> o_lo3) & {8'd0, pixmask});
        end
        S_PXB1: if (srcstate_step_w) if (src_ack) px_r <= px_now;      // EXTRACTGEN(mask) (:519)

        S_WR: if (fsm_step_w) begin
          if (!do_write_w || !fbq_full_w) begin   // enqueued (or transparent) -> advance
            sx <= SHARED_WALKER_ARITH ? walker_sx_sum_w : (xflip_c ? (sx - 10'd1) : (sx + 10'd1)); // :542-545
            clip_gap <= 1'b1;                     // bubble before a clip-advance consumes
                                                  // the ix written here (see S_PIX TIMING)
            if (!scale_c) begin
              ix  <= SHARED_WALKER_ARITH ? walker_ix_sum_w : (ix + 32'sd256);               // :550
              o_r <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + bpp32);                 // :551
            end else begin
              ix  <= SHARED_WALKER_ARITH ? walker_ix_sum_w : (ix + xstep_s);                // :556
              o_r <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + {20'd0,sc_step_bits_w});   // :558 (narrowed: dx<=256, ==dx_w*bpp32)
            end
          end
        end

        // ---- row advance (:562-608): operands paced into registers so the
        //      apply is a pure add. S_RAMUL0 narrows/registers ty & w2 operands,
        //      S_RAMUL1 forms the *bpp products, S_ROWADV applies. -------------
        S_RAMUL0: if (nosrc_step_w) begin
          tyr_r <= ty_w[8:0];                              // scale row count (:585)
          w2p_r <= (w2_ns > 32'sd0) ? w2_ns[10:0] : 11'd0; // :575 positive part
        end
        S_RAMUL1: if (nosrc_step_w) begin
          radv_r  <= tyr_r * rowbits_r;   // ty*width*bpp (:590), operands registered
          w2adv_r <= w2p_r * bpp_c;       // w2*bpp (:576)
        end
        S_ROWADV: if (nosrc_step_w) begin
          sy <= yflip_c ? (sy - 9'd1) : (sy + 9'd1); // :564-567, & YPOSMASK
          if (!scale_c) begin
            iy <= SHARED_WALKER_ARITH ? walker_iy_sum_w : (iy + 32'sd256);                  // :570
            if (skip_c) offset_r <= SHARED_WALKER_ARITH ? walker_offset_sum_w : (offset_r + 32'd8 + w2adv_r);       // :573-576
            else        offset_r <= SHARED_WALKER_ARITH ? walker_offset_sum_w : (offset_r + {18'd0, rowbits_r});    // :580 width*bpp
          end else begin
            iy <= SHARED_WALKER_ARITH ? walker_iy_sum_w : (iy + $signed({16'd0, ystep_c})); // :586
            if (!skip_c)
              offset_r <= SHARED_WALKER_ARITH ? walker_offset_sum_w : (offset_r + radv_r);                          // :590 ty*width*bpp
            else if (tyr_r != 9'd0) begin
              // first skipped row uses THIS row's fp pre/post (:594-596)
              o_r    <= SHARED_WALKER_ARITH ? walker_o_sum_w : (offset_r + 32'd8 + w2adv_r);
              sa_cnt <= {23'd0, tyr_r} - 32'd1;  // 'else if (ty--)' (:592)
            end
            // ty == 0: offset unchanged (source row re-drawn)
          end
        end

        // ---- Scale+Skip multi-row source skip-ahead (:592-607) --------------
        S_SACHK: if (nosrc_step_w) if (sa_cnt == 32'd0) offset_r <= o_r;  // :606
        S_SAB0: if (srcstate_step_w)  if (src_ack) b0_r <= src_data;
        S_SAB1: if (srcstate_step_w)  if (src_ack) skipval_r <= byte_now;    // :599
        S_SAMUL0: if (nosrc_step_w) w3p_r   <= (w3_ns > 32'sd0) ? w3_ns[10:0] : 11'd0; // :603 positive part
        S_SAMUL1: if (nosrc_step_w) w3adv_r <= w3p_r * bpp_c;                          // :604 w3*bpp
        S_SAAPP: if (nosrc_step_w) begin
          o_r    <= SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + 32'd8 + w3adv_r);                // :600,:604
          sa_cnt <= sa_cnt - 32'd1;                       // while (ty--) (:597)
        end

        // ---- completion (dma_done :624-628) ---------------------------------
        // GATED on both local and downstream write paths: all local entries
        // must be issued and acknowledged, fb_we must be low, and wr_busy must
        // fall before the completion IRQ is emitted.
        S_DONE: if (nosrc_step_w) if (final_done_w) begin
          busy_r   <= 1'b0;   // private write-drain fence falls either way
          if (sw_final_done_w) begin
            blit_irq <= 1'b1;   // m_dma_irq_cb(ASSERT_LINE) (:627)
            cadence_valid_r <= 1'b0;
            cadence_x_reload_r <= 18'd0;
            cadence_x_rem_r <= 18'd0;
            cadence_phase_r <= 7'd0;
          end
        end

          default: ;
        endcase

      // W-THRU1 cache maintenance: every served src byte enters the 2-entry
      // cache (src_addr is this FSM's own request address, so it is exactly
      // the byte just served). Same-address refresh keeps entry order.
      if (src_req && src_ack) begin
        if (bc_v0 && (bc_a0 == src_addr)) bc_d0 <= src_data;
        else begin
          bc_prev1 <= bc_prev0; bc_prev0 <= src_addr - 32'd1;
          bc_a1 <= bc_a0; bc_d1 <= bc_d0; bc_v1 <= bc_v0;
          bc_a0 <= src_addr; bc_d0 <= src_data; bc_v0 <= 1'b1;
        end
      end

      // Completion and a non-COMMAND CPU write both land. CPU is ordered last,
      // so a same-cycle COMMAND write wins over the completion clear.
      if (done_clear_w) regf[done_idx_w] <= done_val_w;
      if (reg_write_accepted_w) regf[regnum_w] <= reg_wdata;
      // Legacy zero-quotient commands complete immediately. With the
      // retirement fence, zero counters instead retain a valid cadence until
      // all older and current physical work has drained (zero is a minimum).
      if (command_w && cadence_immediate_w && !RETIRE_IRQ_FENCE)
        regf[DMA_COMMAND] <= {1'b0, reg_wdata[14:0]};

      // The second zero has already made the old transfer irrevocably dead.
      // If its replacement GO arrives before the outstanding source/write
      // handshake can retire, retain the exact command image at that edge.
      // COMMAND itself must use reg_wdata because regf updates after this edge.
      if (trig_w && kill_pending_r && !restart_pending_r) begin
        for (i = 0; i < DMA_NREGS; i = i + 1)
          restart_regf[i] <= regf[i];
        restart_regf[DMA_COMMAND] <= reg_wdata;
        restart_pending_r <= 1'b1;
      end

      // Preserve ordinary busy-time GOs in a small FIFO. MAME accepts each
      // component command immediately; a one-entry snapshot still dropped
      // later commands during the measured select-screen bursts. S_DONE GOs
      // always take this path, including the exact downstream-drain edge, so
      // the queue enable depends only on local registered control.
      if (normal_push_w) begin
        normal_q_mem[normal_q_wptr] <= normal_q_push_word;
        normal_q_wptr <= normal_q_wptr_last ? '0 : (normal_q_wptr + 1'b1);
        normal_q_count <= normal_q_count + 1'b1;
        if ((normal_q_count + 1'b1) > normal_q_highwater_r)
          normal_q_highwater_r <= normal_q_count + 1'b1;
      end
      if (normal_overflow_w) normal_q_overflow_r <= 1'b1;

      // Every write landing on DMA_COMMAND clears the DMA IRQ (:715), trigger
      // or not; a bit15 write from IDLE/DONE starts a blit (:713-717).
      if (command_w) begin
        blit_irq <= 1'b0;
        if (TIMED_IRQ_PUMP) begin
          cadence_valid_r <= cadence_start_w;
          cadence_x_reload_r <= (cadence_start_w && cadence_nonzero_w) ? cadence_x_init_w : 18'd0;
          cadence_x_rem_r <= (cadence_start_w && cadence_nonzero_w) ? cadence_x_init_w : 18'd0;
          cadence_xstep_r <= cadence_xstep_w;
          cadence_ystep_r <= cadence_ystep_w;
          cadence_phase_r <= 7'd0;
          if (cadence_immediate_w && !RETIRE_IRQ_FENCE)
            blit_irq <= 1'b1;
        end
        if (state == S_IDLE) busy_r <= wdata_trig;
        else if ((state == S_DONE) && trig_w && !paused_r &&
                 !halt_pending_r && !walker_halted_r && !kill_pending_r)
          busy_r <= 1'b1;
      end

      // A normal queued GO launches through a registered head image. The
      // queue is popped only after the current blit has fully drained.
      if (normal_pop_w) begin
        normal_launch_word <= normal_q_mem[normal_q_rptr];
        normal_q_rptr <= normal_q_rptr_last ? '0 : (normal_q_rptr + 1'b1);
        normal_q_count <= normal_q_count - 1'b1;
        setup_from_normal_q_r <= 1'b1;
        busy_r <= 1'b1;
        blit_irq <= 1'b0;
      end

      // DGO control priority: one resumes a first-stop seek/drain or a paused
      // transfer. Once a second zero is pending, it remains a kill because its
      // unissued FIFO entries may already have been discarded.
      if (resume_w && !kill_pending_r) begin
        halt_pending_r <= 1'b0;
        walker_halted_r <= 1'b0;
        paused_r       <= 1'b0;
        kill_pending_r <= 1'b0;
      end else if (kill_enter_w) begin
        halt_pending_r <= 1'b0;
        walker_halted_r <= 1'b0;
        paused_r       <= 1'b0;
        kill_pending_r <= 1'b0;
        restart_pending_r <= 1'b0;
        setup_from_restart_r <= restart_pending_r;
        normal_q_wptr <= '0;
        normal_q_count <= '0;
        setup_from_normal_q_r <= 1'b0;
        busy_r         <= restart_pending_r;
        blit_irq       <= 1'b0;
      end else if (pause_enter_w) begin
        halt_pending_r <= 1'b0;
        walker_halted_r <= 1'b0;
        paused_r       <= 1'b1;
        kill_pending_r <= 1'b0;
      end else begin
        if (first_stop_w) halt_pending_r <= 1'b1;
        if (second_stop_w) kill_pending_r <= 1'b1;
        if (stop_boundary_enter_w) walker_halted_r <= 1'b1;
        if (!busy_r && (state == S_IDLE)) begin
          halt_pending_r <= 1'b0;
          walker_halted_r <= 1'b0;
          paused_r       <= 1'b0;
          kill_pending_r <= 1'b0;
          restart_pending_r <= 1'b0;
          setup_from_restart_r <= 1'b0;
          normal_q_wptr <= '0;
          normal_q_count <= '0;
          setup_from_normal_q_r <= 1'b0;
        end
      end

      if (normal_q_clear_w) normal_q_rptr <= '0;

      // The queued image is needed through the S_SETUP edge only; every
      // per-blit field has been latched by then.
      if (fsm_step_w && (state == S_SETUP))
        setup_from_restart_r <= 1'b0;
      if (fsm_step_w && (state == S_SETUP))
        setup_from_normal_q_r <= 1'b0;
    end
  end

  // synthesis translate_off
  // Timing-contract check for the scaled look-ahead cone. sim_ix_age_r counts
  // full intervening clk edges since the last ix write. Every RTL condition
  // that selects sc_next_req_addr_w must see at least one intervening edge
  // (launch -> intervening state/gap -> capture = a two-cycle path).
  logic [2:0] sim_ix_age_r;
  wire sim_ix_write_w = fsm_step_w && (
      ((state == S_ROWCHK) && (iy < height_fp)) ||
      (state == S_SKAPP) ||
      (state == S_RPAPP) ||
      ((state == S_PIX) && pix_remain && !in_clip && !clip_gap) ||
      ((state == S_WR) && (!do_write_w || !fbq_full_w))
  );
  wire sim_scaled_lookahead_capture_w = fsm_step_w && scale_c && (
      ((state == S_WR) && (state_n == S_PIX)) ||
      ((state == S_PIX) && pix_remain && !in_clip && !clip_gap)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      sim_ix_age_r <= 3'd7;
    end else begin
      if (fsm_step_w && SHARED_SOURCE_LOOKUP &&
          (((state == S_WR) && (state_n == S_PIX)) ||
           ((state == S_PIX) && pix_remain && !in_clip && !clip_gap)) &&
          scaled_lookup_o_r !== (scale_c ? sc_next_o_w : ns_next_o_w))
        $fatal(1, "Look-ahead pipeline consumed an unstable next pointer");
      if (sim_scaled_lookahead_capture_w && (sim_ix_age_r < 3'd1))
        $fatal(1, "wolf_dma: scaled look-ahead captured before ix two-cycle gap");

      if (sim_ix_write_w)
        sim_ix_age_r <= 3'd0;
      else if (sim_ix_age_r != 3'd7)
        sim_ix_age_r <= sim_ix_age_r + 3'd1;
    end
  end
  // synthesis translate_on

`ifndef SYNTHESIS
  always @(posedge clk) if (!rst) begin
    case (state)
      S_PXB0, S_PXB1, S_SAB0, S_SAB1, S_SKB0, S_SKB1:
        assert (srcstate_step_w == fsm_step_w) else $fatal(1,"Source-state step differs");
      S_SETUP, S_ROWCHK, S_SKDIV, S_SKMUL, S_SKAPP, S_ROWPREP, S_RPDIV, S_RPMUL, S_RPAPP, S_RAMUL0, S_RAMUL1, S_ROWADV, S_SACHK, S_SAMUL0, S_SAMUL1, S_SAAPP, S_DONE:
        assert (nosrc_step_w == fsm_step_w) else $fatal(1,"Source-free step differs");
      default: ;
    endcase
  end
`endif
endmodule

`default_nettype wire

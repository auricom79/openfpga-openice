// wolf_top.sv — the synthesizable Midway WOLF-unit (UMK3) core. FORK of yunit_top.sv,
// REBASED on it to inherit the cab-proven silicon fixes VERBATIM: P0019 (CPU on `clk`+
// cpu_ce, no async CDC), P0022 (sdram_por-domained persistent capture path), the P0020
// 512-deep download FIFO, and the reset-vector/derail diag. Wolf deltas layered on top:
//
//   tms34010_core  <-> wolf_memsys (CPU + wolf_dma blitter + wolf memory map + internal
//                      wolf_pic; SYNTHESIS externalizes gfx AND prog-ROM to SDRAM via cpu_gfx)
//   yunit_sdram_arb + sdram_stock : all SDRAM traffic on one MT48LC16M16 word port
//   wolf_video_top  : VRAM(SDRAM) -> line buffer -> 15-bit palette -> RGB (400x254)
//   wolf_palram     : 32768-color palette mirror (video read port)
//   sound (DCS/ADSP-2105) : NET-NEW, DEFERRED for the first flash (audio muted).
//
// Clocking: `clk` runs CPU (gated by cpu_ce) / memory / SDRAM / video; `ce_pix` gates the
// raster. clk_snd / rst_pon are unused this phase (DCS deferred).
`default_nettype none
module wolf_top
  import yunit_pkg::*;
  import tms34010_pkg::*;
#(
  parameter ROM_HEX = "umk3_maindata.hex",
  parameter logic [127:0] PIC_RESPONSE_BYTES =
      128'h2B1E_4A0E_0217_6C60_B408_2509_DB01_9AF6,
  parameter bit WWF_IO_SHUFFLE = 1'b0,
  parameter bit PIC_STATUS_DELAY = 1'b1,
  parameter bit TIMED_IRQ_PUMP = 1'b1,
  // video geometry — WOLF (UMK3): 400x254, 34010-programmed raster (wolf_video)
  parameter int H_ACT=400, H_FP=5, H_SYNC=43, H_BP=58,
  parameter int V_ACT=254, V_FP=15, V_SYNC=3, V_BP=17,
  parameter logic [11:0] COL_TAP=56,   // DPYTAP<<1 (wolf_video.sv); NCOL below must cover it
  parameter int DISP_ROW0=0,
  // SDRAM word-address map. WOLF prog ROM is 0x80000 words (u54/u63) vs the Y-unit donor's
  // 0x20000, spanning [0xC0000,0x140000) -> VRAM MUST sit ABOVE it. The donor's 0xE0000
  // would land INSIDE the wolf prog ROM and the blitter/scanout would corrupt program code
  // (the classic fork size-constant bug). Map:
  //   gfx  [0x000000,0x0C0000)   (GFX_BYTES 0x180000 B; deferred/empty on the 1st flash)
  //   rom  [0x0C0000,0x140000)   (ROM_WORDS 0x80000; wolf_mem SDRAM_ROMB = GFX_PIXELS 0x180000)
  //   vram [0x140000,0x180000)   (0x40000 W; scan_addr[17:0])
  //   ram  [0x180000,0x1C0000)   (0x40000 W; main RAM in SDRAM under USE_SDRAM_RAM — off BRAM)
  parameter [24:0] GFXW_BASE = 25'h000000,
  parameter [24:0] ROMW_BASE = 25'h0C0000,
  parameter [24:0] VRAMW_BASE= 25'h140000,
  parameter [24:0] RAMW_BASE = 25'h180000,
  parameter [23:0] GFX_BYTES = 24'h180000,       // == wolf_mem SDRAM_ROMB (cgfx gfx/rom split)
  parameter [24:0] SCRATCH_WBASE = 25'h120000,   // (unused: wolf 1st flash defers the gfx unpack)
  parameter [23:0] PLANE_WORDS   = 24'h30000     // (unused, as above)
)(
  input  logic        clk,        // core clock (memory + SDRAM + video logic), fitted 80 MHz
  input  logic        clk_cpu,    // UNUSED since P0019: the CPU now runs on `clk` gated by a
                                   // 1-in-4 clock-enable (cpu_ce) instead of this async /4 tap.
                                   // Port kept so the emu wiring is unchanged (easy revert).
  input  logic        ce_pix,     // pixel-clock enable (video raster)
  input  logic        clk_snd,    // ~12 MHz sound-board clock
  input  logic        rst,        // core reset (active high)
  input  logic        rst_pon,    // power-on reset (sound board full init)
  input  logic        sdram_por,  // P0022: TRUE power-on (synchronized ~locked) for the PERSISTENT
                                  // SDRAM/download subsystem. Unlike `rst`/`rst_pon` it is LOW during
                                  // any ROM download (which always follows PLL lock), so the capture
                                  // path (FIFO+arb+adapter+phy) keeps running even if the framework
                                  // holds RESET high across the download -> the black-screen root cause.

  input  logic [63:0] inputs,     // {DSW, IN2, IN1, IN0}, active-low
  input  logic [31:0] status,     // OSD menu status (bit 7 = CRT geometry enable, etc.)
  input  logic [2:0]  game_profile, // MRA index-3 runtime Wolf game selector

  // MiSTer index-4 persistence side port for the 48 KiB Wolf CMOS image.
  input  logic        nvram_busy,
  input  logic        nvram_ext_en,
  input  logic        nvram_ext_wr,
  input  logic [15:0] nvram_ext_addr,
  input  logic [7:0]  nvram_ext_wdata,
  output logic [7:0]  nvram_ext_rdata,
  output logic        nvram_cpu_write,

  // ioctl ROM download -> SDRAM word writes (gfx@GFXW_BASE, prog ROM@ROMW_BASE).
  // The MRA/loader presents a linear WORD address matching the SDRAM layout.
  input  logic        ioctl_download,  // held high during ROM load (holds the CPU in reset)
  input  logic        ioctl_wr,
  input  logic [24:0] ioctl_addr,   // SDRAM word address (gfx planes -> scratch, prog ROM)
  input  logic [15:0] ioctl_dout,
  input  logic [1:0]  ioctl_be,     // byte lane(s): 11=packed plane word, 01/10=interleaved ROM
  output logic        ioctl_wait,
  output wire         pocket_download_idle,

  // MRA sound-ROM download (BYTE stream, clk domain). addr[17:16]=chip (0=U4 1=U19
  // 2=U20), addr[15:0]=byte within the 64KB chip. Routed to the CVSD board's BRAMs.
  input  logic        snd_dl_wr,
  input  logic [17:0] snd_dl_addr,
  input  logic [7:0]  snd_dl_data,

  // DCS1 sound ROM download: packed byte stream U2|U3|U4|U5 (4 MB). This
  // remains separate from the legacy CVSD-shaped snd_dl_* port above.
  input  logic        dcs_dl_active,
  input  logic        dcs_dl_wr,
  input  logic [21:0] dcs_dl_addr,
  input  logic [7:0]  dcs_dl_data,
  output logic        dcs_dl_ack,

  // USE_DDR3_GFX only: gfx ROM boot-copy (byte stream, clk domain, ALREADY interleave-
  // transformed by the emu top's wolf_gfx_interleave). NO phase/active signal — the gfx
  // DDR3 block arbitrates write-vs-read per transaction (the first cut's dl_active latch
  // dropped in the PLL-lock->download idle gap and gated the write path off; see
  // wolf_gfx_ddr_top.sv header). Unused/tied off when USE_DDR3_GFX is undefined.
  input  logic        gfx_dl_wr,
  input  logic [24:0] gfx_dl_addr,
  input  logic [7:0]  gfx_dl_data,
  output logic        gfx_dl_ack,
  output logic        gfx_dl_idle,

  // SDRAM (MT48LC16M16) pins
  inout  wire  [15:0] SDRAM_DQ,
  output logic [12:0] SDRAM_A,
  output logic [1:0]  SDRAM_BA,
  output logic        SDRAM_DQML, SDRAM_DQMH,
  output logic        SDRAM_nCS, SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE,
  output logic        SDRAM_CKE,
  // NOTE: SDRAM_CLK is NOT a port here — the emu forwards it from clk_sdram (outclk_1,
  // -3515ps) directly to the pin, matching rtl/sdram.sdc (general[1]) and the proven
  // tecmo/jtframe cores. Keeping it out of the core avoids double-driving the pin.

  // HPS DDR3 (f2h_sdram1) Avalon master. Ports are UNCONDITIONAL (the emu is Quartus-native,
  // NOT sv2v'd, so it cannot see USE_DDR3_VRAM) — under USE_DDR3_VRAM they carry VRAM traffic;
  // otherwise they are tied off to 0 inside. DDRAM_CLK is driven by the emu (= clk_sys, no CDC).
  output logic [28:0] DDRAM_ADDR,
  output logic [7:0]  DDRAM_BURSTCNT,
  output logic        DDRAM_RD,
  output logic [63:0] DDRAM_DIN,
  output logic [7:0]  DDRAM_BE,
  output logic        DDRAM_WE,
  input  logic        DDRAM_BUSY,
  input  logic [63:0] DDRAM_DOUT,
  input  logic        DDRAM_DOUT_READY,

  // video out
  output logic [7:0]  vid_r, vid_g, vid_b,
  output logic        hsync, vsync, hblank, vblank, de,

  // audio out (signed PCM)
  output logic signed [15:0] audio_l, audio_r,

  // debug
  output logic [31:0] pc_dbg,
  output logic        illegal_dbg,
  // boot-instrument taps (observability only; read by the DIAG_BOOT overlay). Unconnected
  // in the normal build — pure outputs, no behavioral effect.
  output logic        dbg_core_rst,
  output logic        dbg_sdram_ready,
  output logic        dbg_unp_done,
  output logic        dbg_cpu_req,
  output logic        dbg_mem_ack,
  output logic        dbg_int1,
  output logic        dbg_vblank_irq,
  output logic        dbg_cpu_ce,          // P0019: CPU clock-enable pulse (liveness tap for the
                                           // DIAG_BOOT overlay — proves the /4 CE is actually pulsing)
  // derail capture (frozen at the FIRST time the PC leaves R_ROM = the wild jump)
  output logic        dbg_derailed,
  output logic [31:0] dbg_culprit_pc,     // last valid code PC = the instruction that jumped
  output logic [15:0] dbg_culprit_instr,  // opcode at the culprit
  output logic [31:0] dbg_derail_pc,       // where it jumped TO (the bad target)
  // P0020 download audit: dropped vs accepted FIFO pushes (see the iol_* block below).
  output logic [31:0] dbg_iol_drop,        // # download words DROPPED on FIFO overflow (>0 = hps_io outran backpressure)
  output logic [31:0] dbg_iol_wrs,         // # download words ACCEPTED into the FIFO (should reach ~0xD0000)
  // gfx-DDR3 pipeline audit (DIAG_GFX overlay; constants 0 unless USE_DDR3_GFX)
  output logic [25:0] dbg_gfx_wbeats,      // DDR3 byte-writes committed (full download = 0x1400000)
  output logic [15:0] dbg_gfx_srd,         // blitter gfx reads served (>0 = sprites are being fetched)
  output logic [15:0] dbg_gfx_cgrd,        // CPU gfx-window reads served (>0 = checksum path live)
  output logic        dbg_dma_q_overflow,  // sticky: a component GO arrived while the queue was full
  output logic [8:0]  dbg_dma_q_highwater  // maximum queued component GOs since reset
);
  // Hold the CPU / memory / video in reset until the SDRAM controller has finished
  // its power-up init (the real MiSTer pattern: the core waits for SDRAM ready +
  // ROM load). Without this the CPU's first fetch rises DURING init and the phy's
  // rising-edge accept misses it -> the held request deadlocks. The SDRAM phy +
  // arbiter run on the raw `rst` so init can proceed while the core is held.
  // sdram_ready is driven by the stock-SDRAM adapter (sticky: it latches the controller's
  // first `ready` = power-up init complete). The adapter + sdram_stock run on raw `rst`.
  logic sdram_ready;
  // Boot-time SDRAM scratch for the raw gfx planes (see yunit_gfx_unpack): plane0 @
  // SCRATCH_WBASE, plane1 @ +PLANE_WORDS, plane2 @ +2*PLANE_WORDS (module parameters).
  // unp_done: gfx unpack complete. 1 in sim (the tb preloads flat gfx directly);
  // in synth it rises only after the boot-time planar->flat pass finishes.
  logic unp_done;
  // Hold the core during ROM download AND the subsequent gfx-unpack pass: SDRAM stays
  // initialized (ready) so the ioctl/unpack channels can write it, while the CPU/video
  // wait until the ROMs are loaded and the gfx is unpacked. DCS ROM download is also
  // held until its byte FIFO and DDR writer are fully drained.
  wire  dcs_dl_busy;
  wire  nvram_busy_active = (nvram_busy === 1'b1);
  wire  core_rst = rst | ~sdram_ready | ioctl_download | dcs_dl_active |
                   dcs_dl_busy | ~unp_done | nvram_busy_active;

  // ---- CPU on clk + clock-enable (P0019: NO separate async clk_cpu) -----------
  // HISTORY: the CPU used to run on a separate clk_cpu (~24 MHz) PLL tap, with
  // yunit_mem_cdc as a real clock-domain crossing to memsys (clk 96 MHz). That
  // passed zero-delay sim but FAILED on silicon. clk_cpu is clk/4 from the SAME PLL
  // (phase-locked, NOT truly async), yet the SDC declared it asynchronous, so STA
  // never timed the CPU<->memsys crossing and the fitter routed those paths freely
  // -> the CPU read back garbage for its reset vector on the cab while the live PC
  // (clk-sampled) marched. FIX: run the CPU on `clk` gated by a 1-in-4 clock-enable
  // (cpu_ce) so it advances at the identical ~24 MHz rate but on a SINGLE clock.
  // The memory adapter now uses its SAME_CLOCK path: requests launch on cpu_ce,
  // memsys completion is observed at full clk rate, and the response is held until
  // the next cpu_ce. No synchronizer delay remains because no domain crossing exists.
  // The long CPU combinational path (~30 MHz max) gets 4 clk periods via a
  // 4:1 multicycle in rtl/sdram.sdc (cpu_ce -> memsys and back).
  // ---------------------------------------------------------------------------
  // LOAD-BEARING: two Wolf safety properties live in THIS divider, not in the
  // core, and neither is visible from the core's own sources. Gate that guards
  // both: tools/wolf_ce_cadence_gate.py (mutation-tested; run it after any
  // change here).
  //
  //  1. TIMING. rtl/sdram.sdc:59-67 claims `-setup 4` on the CPU register group.
  //     That is only honest because this is a UNIFORM modulo divider: every gap
  //     is exactly 4 (or 5 on the Rampage profile). Do NOT convert it to a
  //     fractional / average-exact enable (accumulator + threshold) to hit a
  //     board frequency more closely. T-unit took the same P0019 architecture
  //     with a FRACTIONAL enable (acc += 125 / fire at >= 384): its gaps
  //     alternate 3 and 4, so its honest multicycle is 3, not 4.
  //     (T-unit later RETRACTED the claim that this explains their -1.835 ns
  //     setup failure -- that arithmetic was computed against a stale report and
  //     their real critical path is a quasi-static config register with
  //     Relationship 10.416, i.e. a single-cycle path. The CADENCE point stands
  //     on its own; the failure-number corroboration does NOT. Do not cite it.)
  //     Wolf's guaranteed gap is 4 and the SDC claims 4: there is NO margin.
  //     That is measured HERE, against this divider and rtl/sdram.sdc, and does
  //     not depend on T-unit's numbers.
  //
  //  2. RESET (P0028). The shared tms34010 gates 21 `always_ff @(posedge clk)`
  //     blocks with `if (ce_cpu !== 1'b0)`, which also swallows their reset.
  //     Wolf never executes that defect ONLY because `if (rst) ce_div <= 0`
  //     below pins the divider to its active phase, so cpu_ce is held HIGH for
  //     the whole reset window and every reset assignment runs. Making this a
  //     free-running counter ("a divider doesn't need a reset") arms the defect
  //     at all 21 sites at once; the first symptom would be a WARM reset on a
  //     cabinet that restores nothing. Same applies to rtl/yunit/yunit_mem_cdc.sv:60.
  //
  // Both hazards are silent: no simulation fails and the core is untouched.
  // ---------------------------------------------------------------------------
  logic [2:0] ce_div;
  logic       rampage_profile;
  always_comb begin
    rampage_profile = 1'b0;
    case (game_profile)
      3'd6:    rampage_profile = 1'b1;
      default: rampage_profile = 1'b0;
    endcase
  end
  always_ff @(posedge clk) begin
    if (rst)
      ce_div <= 3'd0;
    else if (ce_div == (rampage_profile ? 3'd4 : 3'd3))
      ce_div <= 3'd0;
    else
      ce_div <= ce_div + 3'd1;
  end
  wire cpu_ce = (ce_div == 3'd0); // 20 MHz normally; 16 MHz for Rampage

  // Reset synchronizer into clk, shared by the core AND the CDC (both single-clock now).
  // core_rst is a raw combinational term; reclocking its deassertion into clk gives clean
  // recovery/removal on all CPU-side flops. memsys/arb keep raw core_rst (never crossed).
  logic core_rst_sys_m, core_rst_sys;
  always_ff @(posedge clk) begin core_rst_sys_m <= core_rst; core_rst_sys <= core_rst_sys_m; end
  // int1 (DMA-done LINT1, the blit-queue pump) is generated by u_sys on clk — already in
  // the CPU's clock domain now, so it drives the core directly (sampled on cpu_ce edges).
  logic int1;

  // CPU memory interface (clk, advanced by cpu_ce)
  logic cpu_req, cpu_we; logic [ADDR_WIDTH-1:0] cpu_addr; logic [FIELD_SIZE_WIDTH-1:0] cpu_size;
  logic [DATA_WIDTH-1:0] cpu_wdata, cpu_rdata; logic cpu_ack;
  logic cpu_srt;   // SRT sideband (P0027): asserted with cpu_req, held until cpu_ack
  core_state_t state_w; instr_word_t instr_w;

  logic [15:0] dpystrt_w;   // P0024 tap: DPYSTRT -> display double-buffer base row
  logic [15:0] dpyadr_w;    // live display address; game writes this to apply the flip now
  logic        tms_vblank_start; // exact internal-raster DPYADR load edge
  // Phase 2B: dynamic display geometry from TMS34010
  logic [15:0] disp_heblnk, disp_hsblnk, disp_veblnk, disp_vsblnk;

  tms34010_core u_core (
    .clk(clk), .ce_cpu(cpu_ce), .ce_pix(ce_pix), .rst(core_rst_sys),
    .mem_req(cpu_req), .mem_we(cpu_we), .mem_addr(cpu_addr), .mem_size(cpu_size),
    .mem_wdata(cpu_wdata), .mem_rdata(cpu_rdata), .mem_ack(cpu_ack),
    .mem_srt(cpu_srt),
    .state_o(state_w), .pc_o(pc_dbg), .instr_word_o(instr_w),
    .illegal_opcode_o(illegal_dbg), .dpystrt_o(dpystrt_w),
    .dpyadr_o(dpyadr_w),
    .vblank_start_o(tms_vblank_start), .lint1_in(int1),
    .heblnk_o(disp_heblnk), .hsblnk_o(disp_hsblnk),
    .veblnk_o(disp_veblnk), .vsblnk_o(disp_vsblnk));

  // memsys-domain memory interface (clk); fed by the CDC's memsys side
  logic mem_req, mem_we; logic [ADDR_WIDTH-1:0] mem_addr; logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0] mem_wdata, mem_rdata; logic mem_ack;
  // SRT sideband follows the request AROUND the sameclock adapter (no donor edit —
  // yunit_mem_cdc/sameclock are shared with the Y-unit/STV chassis). The adapter
  // latches its request payload at the cpu_ce edge it accepts c_req; latching the
  // srt qualifier at EVERY cpu_ce is equivalent, because the core asserts mem_srt
  // combinationally WITH mem_req and holds it until mem_ack (rtl/tms34010/
  // changelog.md 'Sideband contract') — so the value registered at the accept edge
  // is stable by the time wolf_mem samples it with m_req one clk later.
  logic mem_srt_r;
  always_ff @(posedge clk) begin
    if (core_rst_sys) mem_srt_r <= 1'b0;
    else if (cpu_ce)  mem_srt_r <= cpu_srt;
  end

  yunit_mem_sameclock #(.AW(ADDR_WIDTH), .DW(DATA_WIDTH), .SW(FIELD_SIZE_WIDTH)) u_memcdc (
    .clk_cpu(clk), .ce_cpu(cpu_ce), .rst_cpu(core_rst_sys),
    .c_req(cpu_req), .c_we(cpu_we), .c_addr(cpu_addr), .c_size(cpu_size), .c_wdata(cpu_wdata),
    .c_ack(cpu_ack), .c_rdata(cpu_rdata),
    .clk_sys(clk), .rst_sys(core_rst_sys),
    .m_req(mem_req), .m_we(mem_we), .m_addr(mem_addr), .m_size(mem_size), .m_wdata(mem_wdata),
    .m_rdata(mem_rdata), .m_ack(mem_ack));

  // ---- memsys external channels ----------------------------------------------
  logic        src_req;  logic [31:0] src_addr;  logic [7:0] src_data;  logic src_ack;   // wolf: 32-bit gfx src
  logic        src_active;
  logic        src_stream;
  logic        cgfx_rd;  logic [25:0] cgfx_addr; logic [7:0] cgfx_data; logic cgfx_ack;
  logic        cgfx_is_rom;   // 1=prog ROM(SDRAM u_arb) 0=gfx(DDR3 u_gfxddr): cgfx read demux key
`ifdef USE_DDR3_GFX
  // cgfx read-response demux: program-ROM reads served by the SDRAM arbiter (u_arb), gfx-image
  // reads by DDR3 (u_gfxddr). Only ONE is requested at a time (gated by cgfx_is_rom on each
  // side), so select the byte/ack back to wolf_mem on the same flag. (Declared here, ahead of
  // u_arb/u_gfxddr, for Questa's declaration-before-continuous-assign rule.)
  logic [7:0] arb_cgfx_data, gfx_cgfx_data;
  logic       arb_cgfx_ack,  gfx_cgfx_ack;
  assign cgfx_data = cgfx_is_rom ? arb_cgfx_data : gfx_cgfx_data;
  assign cgfx_ack  = cgfx_is_rom ? arb_cgfx_ack  : gfx_cgfx_ack;
`endif
  logic        scan_req; logic [18:0] scan_addr; logic [15:0] scan_data; logic scan_ack;
  // WOLF 1st flash: VRAM on SDRAM (DDR3 deferred). Declare the vsd channel + tie the DDR3
  // master off (wolf_memsys owns VRAM over the SDRAM arb; the DDR3 port is wired to the HPS
  // by the emu but carries nothing this phase).
  logic [24:0] vsd_addr; logic [15:0] vsd_din, vsd_dout; logic [1:0] vsd_be;
  logic        vsd_rd, vsd_wr, vsd_ack;
  // main-RAM SDRAM channel (USE_SDRAM_RAM: the 4 Mbit RAM lives in SDRAM @RAMW_BASE, not BRAM)
  logic [24:0] rsd_addr; logic [15:0] rsd_din, rsd_dout; logic [1:0] rsd_be;
  logic        rsd_rd, rsd_wr, rsd_ack;
`ifdef USE_DDR3_GFX
  // gfx ROM on DDR3 too -> VRAM's ddram_* goes through wolf_ddr3_arb's "A" (priority) side
  // instead of driving DDRAM_* directly; GFX is "B". Declared here (ahead of wolf_memsys
  // below) so both that instantiation and the arbiter block further down can see them.
  wire [28:0] vram_ddram_addr; wire [7:0] vram_ddram_bc; wire vram_ddram_rd, vram_ddram_we;
  wire [63:0] vram_ddram_din; wire [7:0] vram_ddram_be; wire vram_ddram_busy;
  wire [63:0] vram_ddram_dout; wire vram_ddram_dready;
`endif
`ifndef USE_DDR3_VRAM
  // No DDR3 VRAM -> the DDRAM_* Avalon master is unused; tie it off. Under USE_DDR3_VRAM
  // the memsys's DDR VRAM agent drives these (see the u_sys instantiation below). GFX can
  // also own DDRAM_* independently, so only tie the port off when neither feature is active.
`ifndef USE_DDR3_GFX
  assign DDRAM_ADDR=29'd0; assign DDRAM_BURSTCNT=8'd0; assign DDRAM_RD=1'b0;
  assign DDRAM_DIN=64'd0;  assign DDRAM_BE=8'd0;       assign DDRAM_WE=1'b0;
`endif
`endif
  logic        erase_busy, blit_busy;
  wire  [2:0]  dbg_vram_cst;   // DIAG: C-lane drain FSM state (from stv_vram_ddr_top) — pin the wedge
  logic        publication_pending;
  logic        vram_wr_busy;   // VRAM write path draining (from memsys) -> DPYSTRT flip gate
  // DCS sound-status LATCH half of io_r case4 (0x0187FFC0 low bits) — wolf_dcs_stub.sv, a small
  // DYNAMIC model (write sets input-full, modeled auto-ack clears it; see that file's header for
  // the dcs.cpp gospel citations). Replaces the old frozen 16'h0C00 constant. wolf_pic (bits
  // [15:12], the OTHER half of the same word) is untouched.
  logic        snd_data_wr_w, snd_data_rd_w, snd_reset_w;
  logic [7:0]  snd_data_wdata_w, snd_rdata_w;
  logic [15:0] snd_stat_w;
  logic signed [15:0] dcs_audio;
`ifdef USE_DDR3_GFX
  wire        dcs_rom_req, dcs_rom_rdy;
  wire [18:0] dcs_rom_addr;
  wire [63:0] dcs_rom_q;
  wire [28:0] dcs_ddram_addr; wire [7:0] dcs_ddram_bc; wire dcs_ddram_rd, dcs_ddram_we;
  wire [63:0] dcs_ddram_din;  wire [7:0] dcs_ddram_be; wire dcs_ddram_busy;
  wire [63:0] dcs_ddram_dout; wire dcs_ddram_dready;

  wolf_dcs_board u_dcs_board (
    .clk(clk), .rst(core_rst), .host_reset(snd_reset_w),
    .host_cmd_wr(snd_data_wr_w), .host_cmd_data(snd_data_wdata_w),
    .host_resp_rd(snd_data_rd_w), .host_resp_data(snd_rdata_w),
    .host_status(snd_stat_w),
    .rom_req(dcs_rom_req), .rom_addr(dcs_rom_addr),
    .rom_rdy(dcs_rom_rdy), .rom_q(dcs_rom_q),
    .audio(dcs_audio));

  wolf_dcs_ddr_top u_dcs_ddr (
    .clk(clk), .sdram_por(sdram_por),
    .dl_wr(dcs_dl_wr), .dl_addr(dcs_dl_addr), .dl_data(dcs_dl_data),
    .dl_ack(dcs_dl_ack), .dl_busy(dcs_dl_busy),
    .rom_req(dcs_rom_req), .rom_addr(dcs_rom_addr),
    .rom_rdy(dcs_rom_rdy), .rom_q(dcs_rom_q),
    .ddram_addr(dcs_ddram_addr), .ddram_burstcnt(dcs_ddram_bc),
    .ddram_rd(dcs_ddram_rd), .ddram_we(dcs_ddram_we),
    .ddram_din(dcs_ddram_din), .ddram_be(dcs_ddram_be),
    .ddram_busy(dcs_ddram_busy), .ddram_dout(dcs_ddram_dout),
    .ddram_dout_ready(dcs_ddram_dready));
`else
  wolf_dcs_stub u_dcs_stub (
    .clk(clk), .rst(core_rst),
    .snd_reset(snd_reset_w), .snd_data_wr(snd_data_wr_w), .snd_data_i(snd_data_wdata_w),
    .snd_data_rd(snd_data_rd_w), .snd_rdata(snd_rdata_w), .snd_stat(snd_stat_w)
  );
  assign dcs_dl_ack  = 1'b0;
  assign dcs_dl_busy = 1'b0;
  assign dcs_audio   = '0;
`endif
  // palette write-tap (wolf: 15-bit palette index, 32768-color)
  logic        palv_we_a, palv_we_b; logic [14:0] palv_aa, palv_ba; logic [15:0] palv_awd, palv_bwd;

  // autoerase: whole-frame sweep triggered at vblank (post-scanout model, frame-
  // gate verified). row0 = DISP_ROW0, lines = V_ACT.
  logic vblank_irq;

  // Full 0x40000-word (4 Mbit) main RAM — now lives in SDRAM (USE_SDRAM_RAM, auto-on under SYNTHESIS
  // in wolf_mem/wolf_memsys), so it no longer has to fit BRAM. wolf_mem's ram_sdram sequences the
  // field RMW onto the rsd_* channel below → the SDRAM arbiter @RAMW_BASE. (Measured demand ~4.3 MB/s
  // — trivial vs the ~120 MB/s burst ceiling; ~22% CPU stall is the ship-and-measure tradeoff.)
`ifdef DIAG_FLIP
  wire        dbg_blit_trig;   // blit-command capture taps from wolf_dma (via wolf_memsys)
  wire [31:0] dbg_blit_src, dbg_blit_wh;
  wire [15:0] dbg_blit_cmd;
  wire        dbg_exec_start, dbg_exec_done;
  wire [31:0] dbg_exec_src;
  wire [31:0] dbg_dl_cksum, dbg_g4_cksum;   // gfx read-back taps from wolf_gfx_ddr_top
  wire [7:0]  dbg_grp_read, dbg_grp_nz;
  wire        dbg_fb_we, dbg_fb_ack;        // blitter VRAM-write taps from wolf_memsys
  wire [18:0] dbg_fb_addr;
  wire [15:0] dbg_fb_wdata;
`endif
  wolf_memsys #(
    .ROM_HEX(ROM_HEX), .RAM_WORDS(32'h40000),
    .PIC_RESPONSE_BYTES(PIC_RESPONSE_BYTES),
    .WWF_IO_SHUFFLE(WWF_IO_SHUFFLE),
    .PIC_STATUS_DELAY(PIC_STATUS_DELAY),
    .TIMED_IRQ_PUMP(TIMED_IRQ_PUMP)
  ) u_sys (
    .clk(clk), .rst(core_rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .mem_srt(mem_srt_r),
    .src_req(src_req), .src_addr(src_addr), .src_active(src_active),
    .src_stream(src_stream),
    .src_data(src_data), .src_ack(src_ack),
    .inputs(inputs), .game_profile(game_profile), .int1(int1),
    // DCS sound: audio DATA/DAC/ADSP-2105 execution is still DEFERRED (separate project,
    // D:/deck/fpga/umk3/dcs-core) but the host-visible STATUS-LATCH half of io_r case4 is now a
    // faithful DYNAMIC model (wolf_dcs_stub.sv, instantiated above as u_dcs_stub) instead of a
    // frozen constant. It was found (this session) that a real poll during the char-select
    // portrait BUILD (34010 PC FFB5A310/FFB5A2E0, mame-gospel/trace/measure_inputs.txt) observes
    // snd_stat TRANSITION (0xC00 idle <-> 0x400 input-full) across 3 reads — a frozen 0x0C00 can
    // never reproduce that. See wolf_dcs_stub.sv's header for the full dcs.cpp gospel citations
    // (control_r()/data_w()/m_auto_ack) and mame-gospel/trace/picpoll.txt for the earlier
    // boot-time poll (a DIFFERENT PC, FFBBEC80) that established snd_stat is a don't-care there.
    //  snd_rdata = dcs.data_r()&0xFF (midwunit_m.cpp:364-370). With no DCS data path modeled the
    //    data latch never fills; stub 0xFF (idle/pulled-up bus, all-inactive) rather than
    //    0x00 (a real DCS response byte value the boot could mistake for a reply). UNCHANGED —
    //    out of scope (status bits only, per wolf_dcs_stub.sv header).
    .snd_data_wr(snd_data_wr_w), .snd_data_o(snd_data_wdata_w),
    .snd_data_rd(snd_data_rd_w), .snd_reset(snd_reset_w),
    .snd_rdata(snd_rdata_w), .snd_stat(snd_stat_w),
    // Security PIC: wolf_memsys has an INTERNAL wolf_pic; external ports tied off (cf. boot TB).
    .pic_wr(), .pic_wdata(), .pic_reset(),
    .pic_rdata(8'h00), .pic_status(4'h0),
    .watchdog_kick(),
    .gfxbank_o(),                                    // gfx deferred -> quadrant select unused
    // autoerase INERT on Wolf (no autoerase_line — VRAM clears via explicit DMA fills). The
    // SDRAM VRAM backend (vram_sdram_top) has NO internal autoerase enable gate, so the CALLER
    // must tie the trigger off; else a full sweep wipes VRAM with pattern rows 510/511 AND steals
    // SDRAM bandwidth EVERY vblank (scanout-starvation class). Matches all 4 wolf TBs.
    .erase_start(1'b0), .erase_row0(9'd0), .erase_lines(10'd0),
    .erase_busy(erase_busy), .blit_busy(blit_busy), .vram_wr_busy(vram_wr_busy),
`ifdef POCKET
    .publication_hold(publication_pending),
`else
    .publication_hold(1'b0),
`endif
    .nvram_ext_en(nvram_ext_en), .nvram_ext_wr(nvram_ext_wr),
    .nvram_ext_addr(nvram_ext_addr), .nvram_ext_wdata(nvram_ext_wdata),
    .nvram_ext_rdata(nvram_ext_rdata), .nvram_cpu_write(nvram_cpu_write),
    .dbg_vram_cst(dbg_vram_cst),
    .dbg_dma_q_overflow(dbg_dma_q_overflow), .dbg_dma_q_highwater(dbg_dma_q_highwater),
`ifdef DIAG_FACEOFF
    .diag_px_evt(diag_px_evt), .diag_px_x(diag_px_x), .diag_px_y(diag_px_y),
    .diag_px_write(diag_px_write), .diag_px_copy_nz(diag_px_copy_nz),
    .diag_px_color(diag_px_color),
`endif
`ifdef DIAG_FLIP
    .dbg_blit_trig(dbg_blit_trig), .dbg_blit_src(dbg_blit_src),
    .dbg_blit_wh(dbg_blit_wh), .dbg_blit_cmd(dbg_blit_cmd),
    .dbg_exec_start(dbg_exec_start), .dbg_exec_done(dbg_exec_done), .dbg_exec_src(dbg_exec_src),
    .dbg_fb_we(dbg_fb_we), .dbg_fb_ack(dbg_fb_ack), .dbg_fb_addr(dbg_fb_addr), .dbg_fb_wdata(dbg_fb_wdata),
`endif
    // external gfx/ROM read (CPU gfx window) — serves BOTH gfx (empty, deferred) AND prog ROM
    .cpu_gfx_rd(cgfx_rd), .cpu_gfx_raddr(cgfx_addr), .cpu_gfx_rdata(cgfx_data), .cpu_gfx_rack(cgfx_ack),
    .cpu_gfx_is_rom(cgfx_is_rom),
    // VRAM SDRAM channel + video scanout (memsys's fb_ack is internal — not a port)
    .scan_req(scan_req), .scan_addr(scan_addr), .scan_data(scan_data), .scan_ack(scan_ack),
`ifdef USE_DDR3_VRAM
    .sdram_por(sdram_por),
`ifdef USE_DDR3_GFX
    .ddram_addr(vram_ddram_addr), .ddram_burstcnt(vram_ddram_bc), .ddram_rd(vram_ddram_rd), .ddram_we(vram_ddram_we),
    .ddram_din(vram_ddram_din), .ddram_be(vram_ddram_be),
    .ddram_busy(vram_ddram_busy), .ddram_dout(vram_ddram_dout), .ddram_dout_ready(vram_ddram_dready),
`else
    .ddram_addr(DDRAM_ADDR), .ddram_burstcnt(DDRAM_BURSTCNT), .ddram_rd(DDRAM_RD), .ddram_we(DDRAM_WE),
    .ddram_din(DDRAM_DIN), .ddram_be(DDRAM_BE),
    .ddram_busy(DDRAM_BUSY), .ddram_dout(DDRAM_DOUT), .ddram_dout_ready(DDRAM_DOUT_READY),
`endif
`else
    .vsd_addr(vsd_addr), .vsd_din(vsd_din), .vsd_be(vsd_be), .vsd_rd(vsd_rd), .vsd_wr(vsd_wr),
    .vsd_dout(vsd_dout), .vsd_ack(vsd_ack),
`endif
    // main-RAM SDRAM channel (USE_SDRAM_RAM)
    .rsd_addr(rsd_addr), .rsd_din(rsd_din), .rsd_be(rsd_be), .rsd_rd(rsd_rd), .rsd_wr(rsd_wr),
    .rsd_dout(rsd_dout), .rsd_ack(rsd_ack),
    // palette write-tap (15-bit index)
    .palv_we_a(palv_we_a), .palv_aa(palv_aa), .palv_awd(palv_awd),
    .palv_we_b(palv_we_b), .palv_ba(palv_ba), .palv_bwd(palv_bwd));

  // ---- video subsystem -------------------------------------------------------
  logic [14:0] pal_raddr; logic [15:0] pal_rdata;
  logic [7:0] vid_r_pre, vid_g_pre, vid_b_pre;
  logic hsync_pre, vsync_pre, hblank_pre, vblank_pre, de_pre;
  logic [FB_ADDR_W-1:0] active_row0_diag;
`ifdef DIAG_FACEOFF
  logic        diag_px_evt;
  logic [9:0]  diag_px_x;
  logic [8:0]  diag_px_y;
  logic        diag_px_write, diag_px_copy_nz, diag_px_color;
`endif
  wolf_video_top #(
    .H_ACT(H_ACT), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
    .V_ACT(V_ACT), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
    .COL_TAP(COL_TAP),
    .USE_TMS_RASTER_SYNC(1),
`ifdef POCKET
    // CPU GO admission is serialized on Pocket. Require its outstanding
    // descriptor/write path to retire before publishing; wolf_video remembers
    // even a one-SYS-cycle drain between descriptors. Backend readback fences
    // still establish ordering of accepted writes before scan reads.
    .WAIT_FOR_RENDER_IDLE(1),
`endif
    .NCOL(H_ACT + COL_TAP)             // prefetch [0,H_ACT+COL_TAP): covers reads at
                                        // (COL_TAP..COL_TAP+H_ACT-1); yunit_scanline's
                                        // loader always starts filling at column 0, so
                                        // NCOL=H_ACT alone (pre-COL_TAP bandwidth choice)
                                        // undershoots and leaves the tail uninitialized.
  ) u_video (
    .clk(clk), .rst(core_rst), .ce_pix(ce_pix),
    .raster_vblank_start(tms_vblank_start),
    // DPYADR double-buffer: row = (DPYADR ^ 0xfffc) >> 4 (MAME get_display_params,
    // tms34010.cpp:1150-1152). Hardware loads it from DPYSTRT at VSBLNK and the game
    // may override it during blanking. UMK3 uses rows 0/256; Open Ice's 000c/f02c
    // values produce rows 0xfff/0x0fd before MAME's physical 9-bit VRAM-row mask.
    .disp_row0(19'((dpyadr_w ^ 16'hfffc) >> 4)),
    .wr_busy(vram_wr_busy), .blit_busy(blit_busy),
                              // busy gating is a per-platform publication policy
    .pal_raddr(pal_raddr), .pal_rdata(pal_rdata),
    .scan_req(scan_req), .scan_addr(scan_addr), .scan_data(scan_data), .scan_ack(scan_ack),
    .active_row0_diag(active_row0_diag), .publication_pending(publication_pending),
    .vid_r(vid_r_pre), .vid_g(vid_g_pre), .vid_b(vid_b_pre),
    .hsync(hsync_pre), .vsync(vsync_pre), .hblank(hblank_pre), .vblank(vblank_pre), .de(de_pre),
    .vblank_irq(vblank_irq));

  // ---- palette mirror (video read port) --------------------------------------
  wolf_palram #(.AW(15)) u_pal (
    .clk(clk), .rst(core_rst),
    .we_a(palv_we_a), .aa(palv_aa), .awd(palv_awd),
    .we_b(palv_we_b), .ba(palv_ba), .bwd(palv_bwd),
    .raddr(pal_raddr), .rdata(pal_rdata));

`ifdef DIAG_FACEOFF
  logic [7:0] face_r, face_g, face_b;
  logic face_hs, face_vs, face_hb, face_vb, face_de;
  wolf_faceoff_diag_overlay #(
    .H_ACT(H_ACT), .V_ACT(V_ACT), .COL_TAP(COL_TAP)
  ) u_faceoff_diag (
    // Diagnostic RBFs must identify themselves on the screen immediately,
    // matching the established DIAG_BOOT/DIAG_GEOM delivery contract. Do not
    // hide the instrument behind a new OSD bit.
    .clk(clk), .rst(core_rst), .ce_pix(ce_pix), .enable(1'b1),
    .px_evt(diag_px_evt), .px_x(diag_px_x), .px_y(diag_px_y),
    .px_write(diag_px_write), .px_copy_nz(diag_px_copy_nz),
    .px_color(diag_px_color), .active_row0(active_row0_diag),
    .g_r(vid_r_pre), .g_g(vid_g_pre), .g_b(vid_b_pre),
    .g_hs(hsync_pre), .g_vs(vsync_pre), .g_hb(hblank_pre),
    .g_vb(vblank_pre), .g_de(de_pre),
    .vid_r(face_r), .vid_g(face_g), .vid_b(face_b),
    .hsync(face_hs), .vsync(face_vs), .hblank(face_hb),
    .vblank(face_vb), .de(face_de));
`else
  wire [7:0] face_r = vid_r_pre;
  wire [7:0] face_g = vid_g_pre;
  wire [7:0] face_b = vid_b_pre;
  wire face_hs = hsync_pre;
  wire face_vs = vsync_pre;
  wire face_hb = hblank_pre;
  wire face_vb = vblank_pre;
  wire face_de = de_pre;
`endif

  // The abandoned CRT-offset stage used to blank 15 of every 269 PIXELS because
  // its vline counter advanced at pixel rate. The resulting gaps walked across the
  // 506-pixel raster as the cabinet's diagonal black dashes. No offset was selectable
  // (both controls were hard-wired zero), so use the shipped-UMK3 transparent handoff.
  wolf_video_post #(.H_ACT(H_ACT), .V_ACT(V_ACT)) u_video_post (
    .clk(clk), .ce_pix(ce_pix),
    .vid_r_pre(face_r), .vid_g_pre(face_g), .vid_b_pre(face_b),
    .hsync_pre(face_hs), .vsync_pre(face_vs),
    .hblank_pre(face_hb), .vblank_pre(face_vb), .de_pre(face_de),
    .vid_r(vid_r), .vid_g(vid_g), .vid_b(vid_b),
    .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank), .de(de));

  // ---- SDRAM arbiter + physical controller -----------------------------------
  logic [24:0] sd_addr; logic [15:0] sd_din, sd_dout; logic [1:0] sd_be; logic sd_rd, sd_wr, sd_ack;
  logic        iol_ack;

  // ioctl SDRAM-write path + HPS backpressure via a FIFO. hps_io does NOT gate its byte
  // stream on ioctl_wait — the ARM polls ioctl_wait (HPS_BUS[37]) and pauses with a ROUND-
  // TRIP LATENCY of many clks (bus + software). Meanwhile sdram_stock writes each ROM byte
  // slowly (ACTIVATE+WRITE+auto-precharge, ~12 clk). During that latency MANY bytes arrive:
  // a single latch (or a 1-deep skid) DROPS them — measured with +IOLSTRESS: 33% lost at
  // latency 2, 50% at 3, 72% at 6 -> Swiss-cheesed program ROM -> the CPU reads ~0 and
  // marches from 0 (the exact cab capture). So buffer the download in a FIFO deep enough to
  // absorb the HPS round-trip, and assert ioctl_wait at a high-water mark that leaves enough
  // headroom for the still-in-flight bytes. (+IOLSTRESS shows this FIFO loses 0 up to L~256.)
  localparam int IOL_AW  = 9;                       // 512-deep
  localparam int IOL_HWM = 256;                     // wait high-water mark (256 slots headroom)
  logic [42:0] iol_fifo [0:(1<<IOL_AW)-1];          // {addr[24:0], din[15:0], be[1:0]}
  logic [IOL_AW:0] iol_wp, iol_rp;
  wire  [IOL_AW:0] iol_occ   = iol_wp - iol_rp;
  wire             iol_full  = (iol_occ == (1<<IOL_AW));
  wire             iol_empty = (iol_wp == iol_rp);
  logic        iol_hold;
  logic [24:0] iol_addr_r; logic [15:0] iol_din_r; logic [1:0] iol_be_r;
  // P0020 download audit: dbg_iol_drop counts pushes DROPPED on FIFO overflow (should be 0 if
  // ioctl_wait backpressure holds); dbg_iol_wrs counts pushes ACCEPTED (should reach the total
  // FIFO-bound download word count ~0xD0000). Displayed on the DIAG_BOOT overlay to prove/refute
  // "the program ROM reads 0 because the download drops words on real hps_io latency".
  logic [31:0] iol_drop_cnt, iol_wr_cnt;
  always_ff @(posedge clk) begin
    if (sdram_por) begin iol_wp <= '0; iol_rp <= '0; iol_hold <= 1'b0; iol_drop_cnt <= '0; iol_wr_cnt <= '0; end
    else begin
      // PUSH a download word (dropped only on true overflow — prevented by ioctl_wait)
      if (ioctl_wr && !iol_full) begin
        iol_fifo[iol_wp[IOL_AW-1:0]] <= {ioctl_addr, ioctl_dout, ioctl_be};
        iol_wp <= iol_wp + 1'b1;
        iol_wr_cnt <= iol_wr_cnt + 1'b1;                 // accepted push
      end
      else if (ioctl_wr && iol_full) iol_drop_cnt <= iol_drop_cnt + 1'b1;  // OVERFLOW DROP
      // DRAIN: free the live slot on ack; (re)load it from the FIFO whenever it is free
      if (iol_hold && iol_ack) iol_hold <= 1'b0;
      if ((!iol_hold || (iol_hold && iol_ack)) && !iol_empty) begin
        {iol_addr_r, iol_din_r, iol_be_r} <= iol_fifo[iol_rp[IOL_AW-1:0]];
        iol_hold <= 1'b1;
        iol_rp   <= iol_rp + 1'b1;
      end
    end
  end
  assign ioctl_wait = (iol_occ >= IOL_HWM[IOL_AW:0]);
  // Pocket must drain all three writers before releasing the arcade engine.
  assign pocket_download_idle = iol_empty && !iol_hold && gfx_dl_idle && !dcs_dl_busy;

  // gfx-unpack master (boot only). unp_rd/wr/addr/din come FROM the unpack FSM; its
  // dout/ack are driven from the shared boot iol channel below.
  logic        unp_rd, unp_wr, unp_ack;
  logic [24:0] unp_addr; logic [15:0] unp_din, unp_dout;

  // Boot SDRAM channel = ioctl download (write, via the iol_hold latch) MUXED WITH the
  // gfx-unpack (rd+wr) — disjoint in time (download drains, THEN unpack runs; the unpack
  // start is gated on iol_hold==0 below). Folding them into the arbiter's single iol
  // channel keeps the run-time sd_addr mux 4-way (was 5 with a separate unp channel),
  // shortening the scan_req -> SDRAM_A address path.
  wire        boot_unp   = unp_rd | unp_wr;
  wire        b_iol_rd   = unp_rd;
  wire        b_iol_wr   = boot_unp ? unp_wr   : iol_hold;
  wire [24:0] b_iol_addr = boot_unp ? unp_addr : iol_addr_r;
  wire [15:0] b_iol_din  = boot_unp ? unp_din  : iol_din_r;
  wire [1:0]  b_iol_be   = boot_unp ? 2'b11    : iol_be_r;
  wire [15:0] iol_dout;
  assign unp_dout = iol_dout;
  assign unp_ack  = iol_ack & boot_unp;

  yunit_sdram_arb #(
    .SD_AW(25), .GFXW_BASE(GFXW_BASE), .ROMW_BASE(ROMW_BASE),
    .VRAMW_BASE(VRAMW_BASE), .RAMW_BASE(RAMW_BASE), .GFX_BYTES(GFX_BYTES)
  ) u_arb (
    .clk(clk), .rst(sdram_por),                 // P0022: persistent SDRAM subsystem -> POR, not core rst
`ifdef USE_DDR3_VRAM
    // VRAM moved to DDR3 -> the SDRAM arbiter's VRAM channel is unused (this is the whole point:
    // SDRAM now serves only cgfx/prog-ROM/boot-IOL, so scanout no longer starves the CPU).
    .vsd_addr(25'd0), .vsd_din(16'd0), .vsd_be(2'd0), .vsd_rd(1'b0), .vsd_wr(1'b0),
    .vsd_dout(), .vsd_ack(),
`else
    .vsd_addr(vsd_addr), .vsd_din(vsd_din), .vsd_be(vsd_be), .vsd_rd(vsd_rd), .vsd_wr(vsd_wr),
    .vsd_dout(vsd_dout), .vsd_ack(vsd_ack),
`endif
    // main-RAM SDRAM channel (USE_SDRAM_RAM) — RAM stays on SDRAM even under USE_DDR3_VRAM
    .rsd_addr(rsd_addr), .rsd_din(rsd_din), .rsd_be(rsd_be), .rsd_rd(rsd_rd), .rsd_wr(rsd_wr),
    .rsd_dout(rsd_dout), .rsd_ack(rsd_ack),
`ifdef USE_DDR3_GFX
    // Only GFX moved to DDR3. wolf_mem's ONE cgfx read port carries BOTH gfx-image reads
    // (-> DDR3) AND program-ROM reads (program ROM stays in SDRAM @SDRAM_ROMB — the download
    // writes maincpu u54/u63 to SDRAM; only gfx index-1 goes to DDR3). Demux on cgfx_is_rom
    // (region==R_ROM, latched at fetch launch) — NOT on address: gfx bank-0 [0,0x800000)
    // overlaps program ROM [0x180000,...). ROM reads -> this SDRAM arbiter cgfx port with the
    // SAME addressing as the non-DDR3 path (proven); gfx reads -> u_gfxddr below. Serving ALL
    // cgfx (incl. ROM) from DDR3 was the boot bug: the reset-vector fetch hit never-loaded DDR3
    // and read 0 -> CPU ran from ~0 in VRAM (cab p0020diag: row1=0, live PC in R_VRAM).
    // The blitter SRC channel is DDR3-only (gfx source) -> stays tied off here.
    .cgfx_rd(cgfx_rd & cgfx_is_rom), .cgfx_addr(cgfx_addr[23:0]),
    .cgfx_data(arb_cgfx_data), .cgfx_ack(arb_cgfx_ack),
    .src_rd(1'b0), .src_addr(24'd0), .src_data(), .src_ack(),
`else
    .cgfx_rd(cgfx_rd), .cgfx_addr(cgfx_addr[23:0]), .cgfx_data(cgfx_data), .cgfx_ack(cgfx_ack),
    .src_rd(src_req), .src_addr(src_addr), .src_data(src_data), .src_ack(src_ack),
`endif
    .iol_rd(b_iol_rd), .iol_wr(b_iol_wr), .iol_addr(b_iol_addr), .iol_din(b_iol_din),
    .iol_be(b_iol_be), .iol_dout(iol_dout), .iol_ack(iol_ack),
    .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_rd(sd_rd), .sd_wr(sd_wr),
    .sd_dout(sd_dout), .sd_ack(sd_ack));

`ifdef USE_DDR3_GFX
  // ---- gfx ROM on DDR3 (2-way arbiter shares the ONE physical DDRAM_* port with VRAM) ------
  // (vram_ddram_* declared earlier, ahead of the wolf_memsys instantiation that also uses them)
  wire [28:0] gfx_ddram_addr;  wire [7:0] gfx_ddram_bc;  wire gfx_ddram_rd,  gfx_ddram_we;
  wire [63:0] gfx_ddram_din;   wire [7:0] gfx_ddram_be;  wire gfx_ddram_busy;
  wire [63:0] gfx_ddram_dout;  wire gfx_ddram_dready;
  wire gfx_dcs_safe;
  // Preserve the proven VRAM/GFX arbiter intact, then add DCS as a second,
  // lower-priority outer client.
  wire [28:0] vg_ddram_addr; wire [7:0] vg_ddram_bc; wire vg_ddram_rd, vg_ddram_we;
  wire [63:0] vg_ddram_din;  wire [7:0] vg_ddram_be; wire vg_ddram_busy;
  wire [63:0] vg_ddram_dout; wire vg_ddram_dready;

  wolf_gfx_ddr_top #(.USE_STREAM_HINT(1'b1)) u_gfxddr (
    .clk(clk), .rst(core_rst), .sdram_por(sdram_por),
    .src_req(src_req), .src_addr(src_addr), .src_active(src_active),
    .src_stream(src_stream),
    .src_data(src_data), .src_ack(src_ack), .dcs_safe(gfx_dcs_safe),
    .cg_req(cgfx_rd & ~cgfx_is_rom), .cg_addr(cgfx_addr), .cg_data(gfx_cgfx_data), .cg_ack(gfx_cgfx_ack),
    .dl_wr(gfx_dl_wr), .dl_addr(gfx_dl_addr), .dl_data(gfx_dl_data), .dl_ack(gfx_dl_ack),
    .dl_idle(gfx_dl_idle),
    .dbg_wbeats(dbg_gfx_wbeats), .dbg_srd(dbg_gfx_srd), .dbg_cgrd(dbg_gfx_cgrd),
    .ddram_addr(gfx_ddram_addr), .ddram_burstcnt(gfx_ddram_bc),
    .ddram_rd(gfx_ddram_rd), .ddram_we(gfx_ddram_we),
    .ddram_din(gfx_ddram_din), .ddram_be(gfx_ddram_be),
    .ddram_busy(gfx_ddram_busy), .ddram_dout(gfx_ddram_dout), .ddram_dout_ready(gfx_ddram_dready)
`ifdef DIAG_FLIP
    , .dbg_dl_cksum(dbg_dl_cksum), .dbg_grp_read(dbg_grp_read)
    , .dbg_grp_nz(dbg_grp_nz), .dbg_g4_cksum(dbg_g4_cksum)
`endif
  );

  wolf_ddr3_arb u_ddr3arb (
    .clk(clk),
`ifdef USE_DDR3_VRAM
    .a_addr(vram_ddram_addr), .a_burstcnt(vram_ddram_bc), .a_rd(vram_ddram_rd), .a_we(vram_ddram_we),
    .a_din(vram_ddram_din), .a_be(vram_ddram_be),
    .a_busy(vram_ddram_busy), .a_dout(vram_ddram_dout), .a_dout_ready(vram_ddram_dready),
`else
    .a_addr(29'd0), .a_burstcnt(8'd0), .a_rd(1'b0), .a_we(1'b0),
    .a_din(64'd0), .a_be(8'd0), .a_busy(), .a_dout(), .a_dout_ready(),
`endif
    .b_addr(gfx_ddram_addr), .b_burstcnt(gfx_ddram_bc), .b_rd(gfx_ddram_rd), .b_we(gfx_ddram_we),
    .b_din(gfx_ddram_din), .b_be(gfx_ddram_be),
    .b_busy(gfx_ddram_busy), .b_dout(gfx_ddram_dout), .b_dout_ready(gfx_ddram_dready),
    .ddram_addr(vg_ddram_addr), .ddram_burstcnt(vg_ddram_bc), .ddram_rd(vg_ddram_rd), .ddram_we(vg_ddram_we),
    .ddram_din(vg_ddram_din), .ddram_be(vg_ddram_be),
    .ddram_busy(vg_ddram_busy), .ddram_dout(vg_ddram_dout), .ddram_dout_ready(vg_ddram_dready));

  wolf_ddr3_arb #(.HONOR_B_ALLOW(1'b1)) u_ddr3arb_dcs (
    .clk(clk), .b_allow(gfx_dcs_safe),
    .a_addr(vg_ddram_addr), .a_burstcnt(vg_ddram_bc), .a_rd(vg_ddram_rd), .a_we(vg_ddram_we),
    .a_din(vg_ddram_din), .a_be(vg_ddram_be),
    .a_busy(vg_ddram_busy), .a_dout(vg_ddram_dout), .a_dout_ready(vg_ddram_dready),
    .b_addr(dcs_ddram_addr), .b_burstcnt(dcs_ddram_bc), .b_rd(dcs_ddram_rd), .b_we(dcs_ddram_we),
    .b_din(dcs_ddram_din), .b_be(dcs_ddram_be),
    .b_busy(dcs_ddram_busy), .b_dout(dcs_ddram_dout), .b_dout_ready(dcs_ddram_dready),
    .ddram_addr(DDRAM_ADDR), .ddram_burstcnt(DDRAM_BURSTCNT), .ddram_rd(DDRAM_RD), .ddram_we(DDRAM_WE),
    .ddram_din(DDRAM_DIN), .ddram_be(DDRAM_BE),
    .ddram_busy(DDRAM_BUSY), .ddram_dout(DDRAM_DOUT), .ddram_dout_ready(DDRAM_DOUT_READY));
`else
  assign gfx_dl_ack     = 1'b0;   // gfx_dl_* unused in this config (SDRAM-based gfx, or gfx deferred)
  assign gfx_dl_idle    = 1'b1;
  assign dbg_gfx_wbeats = 26'd0;
  assign dbg_gfx_srd    = 16'd0;
  assign dbg_gfx_cgrd   = 16'd0;
`endif

  // ---- gfx planar->flat unpack (boot only) -----------------------------------
  // Synth: run the pass once when the ROM download drops, holding the core (via
  // unp_done) until it completes. Sim: the tb preloads the flat gfx directly, so we
  // tie unp_done=1 and leave the unp channel idle (identical to the proven boot tb).
  // WOLF first flash: DISABLE the gfx unpack. yunit_gfx_unpack is Y-unit-specific (its
  // planar->flat encoding); wolf's gfx format differs AND gfx is DEFERRED (empty gfx SDRAM
  // region), so running it would be wrong and pointless — worse, its SCRATCH base now sits
  // inside the wolf prog ROM. Tie unp_done=1 (the core boots as soon as the prog-ROM download
  // drains + SDRAM is ready) and leave the unp channel idle. A wolf-specific unpack lands when
  // gfx is wired in a later phase.
  assign unp_done = 1'b1;
  assign unp_rd = 1'b0; assign unp_wr = 1'b0; assign unp_addr = 25'd0; assign unp_din = 16'd0;

  // ---- stock SDRAM controller (Sorgelig) + arbiter adapter ----------------------
  // Replaces the hand-rolled sdram_phy. The stock controller forwards SDRAM_CLK via a DDIO
  // I/O cell (not a fabric assign) and uses the DE10-proven CAS-latency read capture — the
  // fix for reads landing in the wrong window on real silicon. The adapter bridges the
  // arbiter's held sd_rd/sd_wr/ack handshake to the controller's edge we/rd + `ready` level.
  // `init`=rst (level high during reset); the controller runs its power-up sequence when it
  // drops. sdram_ready comes from the adapter (latches the controller's first ready).
  logic [24:0] ctl_addr; logic [15:0] ctl_din, ctl_dout; logic [1:0] ctl_wtbt;
  logic        ctl_rd, ctl_we, ctl_ready;

  yunit_sdram_adapter u_sdadapt (
    .clk(clk), .rst(sdram_por),                 // P0022: persistent SDRAM subsystem -> POR, not core rst
    .sd_addr(sd_addr), .sd_din(sd_din), .sd_be(sd_be), .sd_rd(sd_rd), .sd_wr(sd_wr),
    .sd_dout(sd_dout), .sd_ack(sd_ack), .sdram_ready(sdram_ready),
    .ctl_addr(ctl_addr), .ctl_din(ctl_din), .ctl_wtbt(ctl_wtbt),
    .ctl_rd(ctl_rd), .ctl_we(ctl_we), .ctl_dout(ctl_dout), .ctl_ready(ctl_ready));

  sdram_stock u_sdram (
    .init(sdram_por), .clk(clk),                // P0022: SDRAM inits once at true power-on, not core rst
    .addr(ctl_addr), .din(ctl_din), .wtbt(ctl_wtbt), .we(ctl_we), .rd(ctl_rd),
    .dout(ctl_dout), .ready(ctl_ready),
    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
    .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE));

  // ---- sound: DCS (ADSP-2105) DEFERRED for the WOLF first flash — audio muted -----
  // Wolf's sound is the net-new DCS, not the Y-unit CVSD. It is not wired for the first
  // flash: wolf_memsys's snd_* taps are open and audio is silent. clk_snd / snd_dl_* /
  // rst_pon remain unused inputs (kept so the emu wiring is unchanged).
  assign audio_l = dcs_audio;
  assign audio_r = dcs_audio;

  // ---- boot-instrument taps (DIAG_BOOT overlay reads these; harmless in normal build) ----
  assign dbg_core_rst    = core_rst;
  assign dbg_sdram_ready = sdram_ready;
  assign dbg_unp_done    = unp_done;
  assign dbg_cpu_req     = cpu_req;
  assign dbg_mem_ack     = mem_ack;
  assign dbg_int1        = int1;         // DMA-done interrupt to the CPU (blit-queue pump)
  assign dbg_vblank_irq  = vblank_irq;   // display/vblank interrupt (per-frame)
  assign dbg_cpu_ce      = cpu_ce;       // P0019: /4 CPU clock-enable pulse (liveness)
  assign dbg_iol_drop    = iol_drop_cnt; // P0020: download words dropped on FIFO overflow
  assign dbg_iol_wrs     = iol_wr_cnt;   // P0020: download words accepted into the FIFO

  // ---- COMBINED reset-vector + derail capture (clk + cpu_ce, i.e. the CPU's step) -------
  // After the FIFO download fix, answer BOTH questions in one flash. Overlay 4 hex rows:
  //   row1 dbg_culprit_pc    = RESET-VECTOR VALUE the CPU read (first ack'd read).
  //                            FFE0F5C0 => ROM finally LANDED + CPU reads it (download fixed);
  //                            0000/garbage => ROM still not reaching the CPU (download or read).
  //   row2 dbg_culprit_instr = derail CULPRIT PC[15:0] (last valid code PC before it jumped)
  //   row3 dbg_derail_pc     = derail TARGET (where PC jumped OUT of the R_ROM code region)
  //   row4 (overlay live PC) = where the CPU is NOW
  //   status: GREEN = running / not derailed (if PC advances in-region, CPU runs -> video bug);
  //           RED   = derailed (rows 2/3 show the death site).
`ifdef DIAG_FLIP
`ifdef DIAG_BACKDROP
  // NBA Hangtime gameplay backdrop oracle. CODE113L BAKGND.ASM submits
  // source 0x001f509f once per hidden-page build. Production DMA converts
  // that bit address to byte source 0x0003ea13 and must consume 12,313 bytes
  // while accepting 6,864 nontransparent framebuffer writes.
  logic        bd_active, bd_vblank_q, bd_seen_done;
  logic [15:0] bd_go_total, bd_exec_total, bd_done_total;
  logic [15:0] bd_go_frame, bd_exec_frame, bd_go_last, bd_exec_last;
  logic [15:0] bd_src_count, bd_fb_count, bd_src_last, bd_fb_last;
  wire bd_go_evt = dbg_blit_trig && (dbg_blit_src == 32'h001f509f);
  wire bd_exec_evt = dbg_exec_start && (dbg_exec_src == 32'h001f509f);
  always_ff @(posedge clk) begin
    if (core_rst_sys) begin
      bd_active<=1'b0; bd_vblank_q<=1'b0; bd_seen_done<=1'b0;
      bd_go_total<=16'd0; bd_exec_total<=16'd0; bd_done_total<=16'd0;
      bd_go_frame<=16'd0; bd_exec_frame<=16'd0; bd_go_last<=16'd0; bd_exec_last<=16'd0;
      bd_src_count<=16'd0; bd_fb_count<=16'd0; bd_src_last<=16'd0; bd_fb_last<=16'd0;
      dbg_derailed<=1'b0; dbg_culprit_pc<=32'd0; dbg_culprit_instr<=16'd0; dbg_derail_pc<=32'd0;
    end else begin
      bd_vblank_q <= vblank_irq;
      if (vblank_irq && !bd_vblank_q) begin
        bd_go_last <= bd_go_frame; bd_exec_last <= bd_exec_frame;
        bd_go_frame <= 16'd0; bd_exec_frame <= 16'd0;
      end
      if (bd_go_evt) begin
        if (bd_go_total != 16'hffff) bd_go_total <= bd_go_total + 16'd1;
        if (bd_go_frame != 16'hffff) bd_go_frame <= bd_go_frame + 16'd1;
      end
      if (bd_exec_evt) begin
        bd_active <= 1'b1; bd_src_count <= 16'd0; bd_fb_count <= 16'd0;
        if (bd_exec_total != 16'hffff) bd_exec_total <= bd_exec_total + 16'd1;
        if (bd_exec_frame != 16'hffff) bd_exec_frame <= bd_exec_frame + 16'd1;
      end
      if (bd_active && src_req && src_ack && bd_src_count != 16'hffff)
        bd_src_count <= bd_src_count + 16'd1;
      if (bd_active && dbg_fb_we && dbg_fb_ack && bd_fb_count != 16'hffff)
        bd_fb_count <= bd_fb_count + 16'd1;
      if (bd_active && dbg_exec_done) begin
        bd_active <= 1'b0; bd_seen_done <= 1'b1;
        bd_src_last <= bd_src_count; bd_fb_last <= bd_fb_count;
        if (bd_done_total != 16'hffff) bd_done_total <= bd_done_total + 16'd1;
      end
      // row1: cumulative issued|launched; row2: last-frame issued|launched
      // (expected 0101); row3: source bytes|accepted pixels (30191AD0).
      dbg_culprit_pc    <= {bd_go_total, bd_exec_total};
      dbg_culprit_instr <= {bd_go_last[7:0], bd_exec_last[7:0]};
      dbg_derail_pc     <= {bd_src_last, bd_fb_last};
      dbg_derailed      <= bd_seen_done &&
                           ((bd_src_last != 16'h3019) || (bd_fb_last != 16'h1ad0));
    end
  end
`else
  // ---- FLIP-RACE diagnostic (+define+DIAG_FLIP) — reuses the DIAG_BOOT overlay verbatim ----
  // Blit engine + scanout are proven correct in sim; the remaining suspect is the double-buffer
  // page-flip racing uncommitted DDR3 writes. blit_busy is COMMIT-GATED (held high until the
  // write path drains). So blit_busy HIGH at the DPYSTRT flip = the game flipped WHILE the
  // blitter was still committing = the empty-rectangle race. Overlay read-off (attract demo
  // exercises the double-buffer, no input needed):
  //   status: RED  = at least one DPYSTRT flip happened while blit_busy was high (RACE CONFIRMED)
  //           GREEN = every flip saw blit_busy low (handshake holds -> bug is elsewhere/commit)
  //   row1 dbg_culprit_pc    = {raced_flips[15:0], total_flips[15:0]}
  //   row2 dbg_culprit_instr = max blit_busy cycles in one frame (commit load; 0 = blitter idle)
  //   row3 dbg_derail_pc     = {busy_cyc_max[15:0], 15'd0, blit_busy_now}
  // v2: free-running, vblank-INDEPENDENT busy count + sticky busy_ever. v1 gated busy_cyc_max on the
  // vblank_irq edge -> read 0 whether blit_busy was stuck-low OR just never sampled (ambiguous). Now
  // "does blit_busy EVER pulse?" is unambiguous. Overlay read-off (attract demo, no input):
  //   status: RED = a DPYSTRT flip caught blit_busy high (race) / GREEN = no such flip
  //   row1 = {raced_flips[31:16], total_flips[15:0]}
  //   row2 = flags: bit0 = blit_busy NOW, bit1 = busy_ever (EVER high), bit2 = raced_sticky
  //          -> 0000 = blit_busy NEVER high (stuck-low; game never waits = the bug); 0002+ = it pulses
  //   row3 = busy_total = free-running count of blit_busy-high cycles (0 = stuck low)
  // REPURPOSED 2026-07-11: flip-race is RESOLVED (raced=0 across 2 cab reads -> the game DOES
  // wait; it never flips while blit_busy). The open question is now commit-timing vs PUMP
  // STARVATION: does the core ISSUE as many blits/frame as MAME (golden: select 136 avg / 200
  // peak, fight 90/142)? Count blit_busy edges/frame: rising = blit trigger (issued), falling =
  // blit commit-complete. Reset+latch each frame at vblank_irq; track PEAK across frames.
  //   row1 dbg_culprit_pc    = {trig_peak[15:0], cmpl_peak[15:0]}   <- PEAK issued|completed /frame
  //   row2 dbg_culprit_instr = {trig_last[7:0], cmpl_last[7:0]}     <- LIVE issued|completed /frame
  //   row3 dbg_derail_pc     = {blit_busy_now,7'0,trig_total[23:0]} <- busy-now flag + running total
  // FIX 2026-07-12: vblank_irq is a MULTI-CYCLE level on clk (ce_pix-wide) -> the old `if(vblank_irq)`
  // re-latched trig_last every cycle it was high, clobbering it to 0 after the first (reset) cycle.
  // Edge-detect it so the per-frame latch fires ONCE. row2 now carries the live per-frame rate: read
  // it DURING a fight -- ~8C/5A (140/90) => not starved (commit-timing); ~00/00 or busy_now stuck =>
  // the CPU is stalled on the write path (starvation/wedge). Peak (row1) survives the old bug (0>peak
  // is false) so 199|199 is trustworthy = the core CAN do ~200 somewhere (select).
  // REPURPOSED 2026-07-12 (3): INPUT side fully proven on silicon (command, gfx write byte-perfect,
  // gfx READ from the portrait region (group 4) returns real data). Yet the cell shows marble = the
  // portrait pixels were never WRITTEN. This taps the blitter's VRAM WRITE (destination side) — the
  // one untested link. fb_we = a pixel write; fb_wdata != 0 = a non-transparent (real sprite) pixel.
  // Per frame, peak-tracked; diff vs MAME's char-select fb-write count.
  //   row1 dbg_culprit_pc    = {fb_nz_peak[15:0], fb_tot_peak[15:0]} -- peak NON-ZERO | TOTAL fb
  //        writes/frame. cab_nz << MAME => engine outputs TRANSPARENT despite good gfx (read-data/mode);
  //        cab_nz ~= MAME => pixels ARE written => a land/buffer/display problem downstream of the write.
  //   row2 dbg_culprit_instr = fb_addr_max[18:3] -- coarse top VRAM addr of a non-zero write (which
  //        buffer/rows the sprite pixels land in; buffer B = high addrs).
  //   row3 dbg_derail_pc     = fb_nz_total -- running non-zero write count (sanity, climbs if writing).
  //   row4 (overlay live PC) = where the CPU is now
  // REPURPOSED 2026-07-12 (4), RETARGETED 2026-07-13 (silent audit): the prior fb-write counter
  // SATURATED at 0xFFFF (bg fill alone is ~100k px/frame). The (4) version isolated "region-5" blits
  // on the theory that region 5 = portraits -- WRONG per a corrected MAME capture (mame-gospel/trace/
  // audit_sel2.txt + audit_fight.txt, scene-proven via snap_audit2/snap_fight PNGs): region 5 is the
  // TEXT-GLYPH class (renders fine, 2,768 writes/frame); real char-select portraits are 48x52 blits
  // (cmd F042/8042) using CMD BIT6 + nonzero DMA_LRSKIP -- the ONLY char-select blit class with bit6
  // set (68 blits / 3 frames in the corrected capture, zero false positives against 176 total blits).
  // 0x2A0E=10,766 from the old region-5-qualified counter was therefore a TEXT measurement wearing a
  // "portrait" label, coincidentally close to a MAME reference (13,735) that was ALSO mislabeled (an
  // attract-mode text page, not char-select) -- both numbers real, comparison meaningless. See memory
  // lessons_scene_identity_goldens. RETARGETED to the verified discriminator: bit6 (dbg_blit_cmd[6]),
  // latched at trigger. NOTE: fight-phase sprites carry NEITHER bit6 nor LRSKIP (audit_fight.txt,
  // 0/500 frames) -- this counter reads 0 in fight by construction; it is a CHAR-SELECT-ONLY portrait
  // instrument. Corrected MAME reference for THIS scene: 22 blits / 51,479 writes/frame (bit6-qualified,
  // steady char-select). Still lacks destination-address instrumentation (dbg_fb_addr is wired but
  // unused here) -- splitting by dbg_fb_addr[17] (buffer half) is the recommended NEXT diag, not done
  // in this build.
  // READ+WRITE COMBINED (2026-07-13, STV src-byte-latch technique folded in): the deeper audit proved
  // source DATA byte-exact + engine bit-exact in sim, cornering the fault to the SILICON gfx-READ path.
  // This measures BOTH sides of a portrait (bit6) blit in ONE flash: what the DDR3 gfx read RETURNS
  // (src_ack/src_data, tapped at wolf_top) and whether the engine WRITES (fb_we/ack). src_* are the
  // wolf_top-level gfx-read wires (this file:212) shared by wolf_dma + wolf_gfx_ddr_top -> src_data at
  // src_ack IS the byte the silicon DDR3 gfx path returned. Reuses the 3 existing overlay ports (no new
  // top-level port -> no diag/loopback-top port-sync break) and the single DIAG_FLIP macro.
  //   row1 dbg_culprit_pc    = {srd_nz_peak[15:0], srd_tot_peak[15:0]} -- READ side, per-frame peak of
  //        source bytes returned during portrait blits. CAVEAT (STV, banked in [[lessons_scene_identity_goldens]]):
  //        "nz<<tot" is NOT a root-cause signal by itself -- source gfx legitimately contains transparent
  //        (zero) bytes, so a HEALTHY blit's nz/tot ratio is graphic-dependent. Compare to the MAME GOLDEN
  //        ratio, not to tot. GOLDEN for THESE char-select portraits = 99.9% nonzero (measured over their
  //        source footprints in umk3_gfx.hex -- they are fully OPAQUE dense 7bpp, so the healthy read is
  //        nz~=tot with a WIDE clean gap to broken). READ: srd_nz ~= srd_tot (~99.9%) => gfx read returns
  //        REAL data => read FINE, look downstream/write. srd_nz ~0 (ratio << 99.9%) => silicon gfx read
  //        returns ZEROS for portrait SAGs => ROOT CAUSE = gfx-read path (the cornered suspect). NOTE: if
  //        ever armed on FIGHTERS (bit7-skip-compressed, real transparent runs) the golden ratio is far
  //        below 99.9% and graphic-specific -- MUST capture the per-blit golden then, don't reuse this number.
  //   row2 dbg_culprit_instr = {src_addr_cap[7:0], srcb[7:0]} -- STV single-byte latch: the first source
  //        byte (low 8b) of a portrait blit + low byte of its source address (high 8b), spot-check vs the
  //        MAME golden byte at that SAG (portrait grp2 window is nonzero structured data, not 00/FF).
  //   row3 dbg_derail_pc     = portrait_nz_total -- WRITE side (portrait6b's metric): running NON-ZERO
  //        portrait fb writes. climbs => engine emits pixels; stays ~0 => engine outputs nothing (which,
  //        with a healthy row1 READ, would mean the mode-2 write-nonzero saw good source but wrote 0 --
  //        contradiction, reopens engine; with a dead row1 READ, confirms read-starved engine).
  //   row4 (overlay live PC) = CPU liveness.
  // ===== OBJECT-TABLE PROBE (2026-07-14) — is the char-select DISPLAY LIST built with F042 portraits? =====
  // MAME (portrait_tablebuild.txt): char-select portraits are RAM display-list objects at 0x0102F000+,
  // each {cmd=F042/8042, src=05/06xxxxxx, W=0x30 H=0x34}; the draw loop READS each object's cmd+source
  // from RAM every frame, then the dispatcher fires the blit. Command-census already proved 0 cmd-0x42
  // blits ISSUE on the cab. This watches what the CPU READS from RAM to split the two remaining causes:
  // ===== HANG-CONFIRM PROBE (2026-07-14) — is busy actually STUCK (real downstream wedge), or does the
  // draw just stop (upstream, like STV's fillcap concern)? Before touching the SHARED write path, prove
  // the wedge. Tracks the MAX consecutive cycles blit_busy (commit-gated DMA busy the CPU polls) and
  // vram_wr_busy (the DDR3 write drain) stay high, + the command of the blit that hung. A normal blit
  // holds busy ~thousands of clks; a WEDGE holds it MILLIONS (never clears). Uses only fast registered
  // taps (blit_busy/vram_wr_busy/dbg_blit_cmd) -> no cpu_rdata route, no cpu_ce gate needed.
  //   row1 = blit_busy_hold_max. HUGE (>~0x00F00000) => busy WEDGES => downstream busy-hang CONFIRMED
  //          (CPU spins on it). ~thousands => NOT a hang => draw stops UPSTREAM (pivot to command-gen).
  //   row2 = 0x0X42 = {stuck C-lane state X | cmd low byte}. X pins the wedge: 1=C_RD (RMW READ never
  //          returns c_done => read-after-write fence is the fix), 3=C_WR / 4=C_BURST (drain never
  //          completes). low byte 42 = the character blit (confirms it's the char write wedging).
  //   row3 = vram_wr_busy_hold_max. HUGE => wedge is the C-lane WRITE DRAIN (stv_vram_ddr_top);
  //          ~normal while row1 huge => wedge is in the wolf_dma FSM, not the DDR3 write.
  //   row4 (overlay live PC) = CPU liveness (expect the FF8044E0 busy-poll if hung).
  logic [31:0] bb_hold, bb_hold_max, wb_hold, wb_hold_max;
  logic [15:0] bb_cmd_max;
  logic [2:0]  bb_cst_max;                                    // C-lane FSM state captured at the longest hold
  always_ff @(posedge clk) begin
    if (core_rst_sys) begin
      bb_hold<=32'd0; bb_hold_max<=32'd0; wb_hold<=32'd0; wb_hold_max<=32'd0; bb_cmd_max<=16'd0; bb_cst_max<=3'd0;
      dbg_derailed<=1'b0; dbg_culprit_pc<=32'd0; dbg_culprit_instr<=16'd0; dbg_derail_pc<=32'd0;
    end else begin
      if (blit_busy) begin if (bb_hold != 32'hFFFFFFFF) bb_hold <= bb_hold + 32'd1; end
      else bb_hold <= 32'd0;
      if (bb_hold > bb_hold_max) begin bb_hold_max <= bb_hold; bb_cmd_max <= dbg_blit_cmd; bb_cst_max <= dbg_vram_cst; end
      if (vram_wr_busy) begin if (wb_hold != 32'hFFFFFFFF) wb_hold <= wb_hold + 32'd1; end
      else wb_hold <= 32'd0;
      if (wb_hold > wb_hold_max) wb_hold_max <= wb_hold;
      dbg_derailed      <= 1'b0;
      dbg_culprit_pc    <= bb_hold_max;                         // row1: max consecutive clks blit_busy held high (wedge = huge)
      dbg_culprit_instr <= {5'b0, bb_cst_max, bb_cmd_max[7:0]}; // row2: 0x0X42 = {C-lane state X | cmd byte 42}
      dbg_derail_pc     <= wb_hold_max;                         // row3: max consecutive clks vram_wr_busy held high
    end
  end
`endif
`elsif DIAG_ILLEGAL
  // Freeze the first opcode rejected by the TMS34010 decoder. illegal_dbg is
  // registered in the core during CORE_DECODE. On the following cpu_ce step,
  // instr_w still holds that opcode and pc_dbg is its already-advanced PC.
  //   row1 = address of rejected opcode
  //   row2 = rejected 16-bit opcode
  //   row3 = PC after its 16-bit fetch
  always_ff @(posedge clk) if (cpu_ce) begin
    if (core_rst_sys) begin
      dbg_derailed      <= 1'b0;
      dbg_culprit_pc    <= 32'd0;
      dbg_culprit_instr <= 16'd0;
      dbg_derail_pc     <= 32'd0;
    end else if (!dbg_derailed && illegal_dbg) begin
      dbg_derailed      <= 1'b1;
      dbg_culprit_pc    <= pc_dbg - 32'h0000_0010;
      dbg_culprit_instr <= instr_w;
      dbg_derail_pc     <= pc_dbg;
    end
  end
`elsif DIAG_GFX
  // VRAM READ-BACK (2026-07-12) — is the sprite CONTENT actually in the VRAM scanout reads? Count
  // non-background VRAM indices (pal_raddr != 0) over the active frame. Compare cab-SELECT vs the
  // MAME-SELECT reference: cab << MAME => sprite content MISSING from VRAM (the WRITE or the group-4
  // gfx READ failed on silicon); cab ~= MAME => content is IN VRAM but not shown (palette/scanout).
  //   row1 dbg_culprit_pc = non-bg VRAM pixels / frame  <- THE READ-BACK
  //   row2 dbg_culprit_instr = gfx PUSHES >>10  (emu-top DIAG_GFX route; full = 0x5000 = 20MB)
  //   row3 dbg_derail_pc     = {idx, gfx COMMITTED >>10, ...} (route) -> pushes==committed = 0 drops
  logic        vblank_qg;
  logic [31:0] vram_nz_frame, vram_nz_last;
  always_ff @(posedge clk) begin
    if (core_rst_sys) begin
      vblank_qg<=1'b0; vram_nz_frame<=32'd0; vram_nz_last<=32'd0;
      dbg_derailed<=1'b0; dbg_culprit_pc<=32'd0; dbg_culprit_instr<=16'd0; dbg_derail_pc<=32'd0;
    end else begin
      vblank_qg <= vblank_irq;
      if (ce_pix && de && (pal_raddr != 15'd0)) vram_nz_frame <= vram_nz_frame + 32'd1;
      if (vblank_irq & ~vblank_qg) begin vram_nz_last <= vram_nz_frame; vram_nz_frame <= 32'd0; end
      dbg_derailed      <= 1'b0;
      dbg_culprit_pc    <= vram_nz_last;   // row1: non-bg VRAM pixels/frame (the READ-BACK)
      dbg_culprit_instr <= 16'd0;          // row2 overridden by emu-top DIAG_GFX route (gfx pushes)
      dbg_derail_pc     <= 32'd0;          // row3 overridden by emu-top DIAG_GFX route (gfx committed)
    end
  end
`elsif DIAG_SRT
  // ---- SRT sideband instrument (+define+DIAG_SRT; rides the DIAG_BOOT overlay like
  // DIAG_FLIP/DIAG_ILLEGAL — the emu top auto-enables DIAG_BOOT and passes these rows
  // through verbatim). Taps the CPU-side memory bus at wolf_top (cpu_req/cpu_ack/
  // cpu_we/cpu_srt at cpu_ce steps): one count per ACKED SRT-converted access.
  //   row1 dbg_culprit_pc    = {latches_LAST_frame[15:0], transfers_LAST_frame[15:0]}
  //        NBA Hangtime DIRQ expectation: 0001|007F once per displayed frame.
  //   row2 dbg_culprit_instr = {14'd0, srt_seen_sticky, srt_now}
  //        srt_seen_sticky = an SRT access has been ACKED since reset — the sticky
  //        "DPYCTL bit 11 seen" indicator (the core only converts while bit11=1; the
  //        raw DPYCTL value itself is internal to the core, so this proxy is the
  //        HW-observable form: 0 here with a black hidden page = the game never
  //        enabled SRT / the conversion never fired; 1 = the sideband is live).
  //   row3 dbg_derail_pc     = {latch_total[15:0], transfer_total[15:0]} (running).
  //   row4 (overlay live PC) = CPU liveness.
  // Status stays GREEN (dbg_derailed=0) — this is a counter instrument, not a trap.
  logic        srt_vb_q, srt_seen;
  logic [15:0] srt_l_frame, srt_t_frame, srt_l_last, srt_t_last;
  logic [15:0] srt_l_total, srt_t_total;
  wire         srt_evt = cpu_req && cpu_ack && cpu_srt;  // acked SRT access (once per op:
                                                         // c_ack clears at the next cpu_ce)
  always_ff @(posedge clk) begin
    if (core_rst_sys) begin
      srt_vb_q<=1'b0; srt_seen<=1'b0;
      srt_l_frame<=16'd0; srt_t_frame<=16'd0; srt_l_last<=16'd0; srt_t_last<=16'd0;
      srt_l_total<=16'd0; srt_t_total<=16'd0;
      dbg_derailed<=1'b0; dbg_culprit_pc<=32'd0; dbg_culprit_instr<=16'd0; dbg_derail_pc<=32'd0;
    end else begin
      srt_vb_q <= vblank_irq;
      if (vblank_irq && !srt_vb_q) begin
        srt_l_last  <= srt_l_frame;  srt_t_last  <= srt_t_frame;
        srt_l_frame <= 16'd0;        srt_t_frame <= 16'd0;
      end
      if (cpu_ce && srt_evt) begin
        srt_seen <= 1'b1;
        if (!cpu_we) begin
          if (srt_l_frame != 16'hFFFF) srt_l_frame <= srt_l_frame + 16'd1;
          if (srt_l_total != 16'hFFFF) srt_l_total <= srt_l_total + 16'd1;
        end else begin
          if (srt_t_frame != 16'hFFFF) srt_t_frame <= srt_t_frame + 16'd1;
          if (srt_t_total != 16'hFFFF) srt_t_total <= srt_t_total + 16'd1;
        end
      end
      dbg_derailed      <= 1'b0;
      dbg_culprit_pc    <= {srt_l_last, srt_t_last};
      dbg_culprit_instr <= {14'd0, srt_seen, cpu_srt};
      dbg_derail_pc     <= {srt_l_total, srt_t_total};
    end
  end
`else
  logic [1:0]  rd_cnt;
  logic        ack_q;
  logic        d_started;
  logic [31:0] d_prevpc;
  always_ff @(posedge clk) if (cpu_ce) begin
    if (core_rst_sys) begin
      dbg_derailed<=1'b0; rd_cnt<=2'd0; ack_q<=1'b0; d_started<=1'b0; d_prevpc<=32'hFFFFFFFF;
      dbg_culprit_pc<=32'hDEADBEEF; dbg_culprit_instr<=16'hDEAD; dbg_derail_pc<=32'hDEADBEEF;
    end else begin
      // (A) RESET-VECTOR value = the FIRST ack'd read (row1: did the ROM land?)
      ack_q <= cpu_ack;
      if (cpu_ack && !ack_q && !cpu_we && rd_cnt==2'd0) begin
        dbg_culprit_pc <= cpu_rdata; rd_cnt <= 2'd1;
      end
      // (B) DERAIL: freeze the first time PC leaves the R_ROM code region (pc[31:23]==9'h1FF)
      if (pc_dbg !== d_prevpc) begin
        d_prevpc <= pc_dbg;
        if (pc_dbg[31:23]==9'h1FF) d_started <= 1'b1;
        else if (d_started && !dbg_derailed && (^pc_dbg !== 1'bx)) begin
          dbg_derailed      <= 1'b1;
          dbg_derail_pc     <= pc_dbg;            // row3: derail TARGET (bad address)
          dbg_culprit_instr <= d_prevpc[15:0];    // row2: last valid code PC low16 (jumped FROM)
        end
      end
    end
  end
`endif
endmodule
`default_nettype wire

// wolf_memsys.sv — Midway Wolf-unit (UMK3) memory subsystem: wolf_mem + wolf_dma
// glued into one slave on the TMS34010 core's request-valid memory interface.
//
// FORK of yunit/yunit_memsys.sv. Same structural role: this is the block the CPU
// talks to. It routes
//   - the DMA blitter register region (0x01A00000, mirror +0x80000) -> wolf_dma
//   - everything else                                               -> wolf_mem
// and wires the blitter back into VRAM: wolf_dma.fb_* -> wolf_mem VRAM write port,
// wolf_dma.dma_palette -> wolf_mem CPU vram_w byte-lane fold.
//
// WOLF DELTAS vs the Y-unit donor (all cited to wolf_pkg / wolf_mem / wolf_dma):
//  - DMA register FSM decode is the SAME address scheme (reg offset = addr[7:4],
//    32-bit field write splits into reg N low + reg N+1 high). wolf_dma applies the
//    Wolf/T-unit dma_regmap (DMA_CONFIG[5] bank) + trigger internally, so the FSM
//    here is unchanged except reg_addr is a raw 0..15 offset (wolf_dma maps it).
//  - wolf_mem exposes DIFFERENT register taps than yunit_mem: DCS byte sound latch
//    (snd_data_wr/snd_data_o/snd_reset + snd_rdata/snd_stat), MIDWAY_SERIAL_PIC
//    security (pic_wr/pic_wdata/pic_reset + pic_rdata/pic_status), watchdog_kick,
//    and CONTROL gfxbank_o. These are surfaced as ports; the top ties the sound/PIC
//    inputs to sane constants during CMOS-gated bring-up (per wolf_mem header).
//  - src_addr is 32-bit (wolf_dma packed-gfx byte index is [31:0], vs Y-unit [23:0]).
//  - autoerase is RETAINED INERT in wolf_mem (Wolf has no autoerase_line); the
//    erase_* ports are kept for structural parity and left drivable by the top.
//
// Interrupts (P0016 semantics, inherited): DMA-done ASSERTS wolf_dma.blit_irq (MAME
// dma_callback), any DMA COMMAND write CLEARS it (MAME dma_w). That is
// wolf_dma.blit_irq -> the int1 output -> tms34010_core.lint1_in. The game's
// blit-queue pump ISR (INT1 vector) depends on it.

`default_nettype none

// Mirror wolf_mem's synthesis auto-defines so the guarded ports/wiring here match.
`ifdef SYNTHESIS
  `ifndef USE_EXT_GFX
    `define USE_EXT_GFX
  `endif
  `ifndef USE_EXT_ROM
    `define USE_EXT_ROM
  `endif
  `ifndef USE_SDRAM_VRAM
    `define USE_SDRAM_VRAM
  `endif
  `ifndef USE_SDRAM_RAM
    `define USE_SDRAM_RAM
  `endif
  `ifndef USE_HW_RAM
    `define USE_HW_RAM
  `endif
`endif
`ifdef USE_EXT_GFX
  `define YM_EXT_RD
`endif
`ifdef USE_EXT_ROM
  `ifndef YM_EXT_RD
    `define YM_EXT_RD
  `endif
`endif

module wolf_memsys
  import wolf_pkg::*;
#(
  // Program-ROM sizing (the wolf boot TB pins the umk3_maindata layout: the whole
  // 0xFF800000-0xFFFFFFFF window is 0x80000 words == the maincpu region, mapped 1:1,
  // so ROM_WORDS=0x80000 and ROM_PROG_OFF=0). Defaults keep tb_wolf_mem-style hosts.
  parameter int          ROM_WORDS    = 32'h80000,
  parameter logic [27:0] ROM_PROG_OFF = 28'h0,
  parameter int          RAM_WORDS    = 32'h40000,   // main-RAM words -> wolf_mem. DE10 M10K FIT KNOB:
                                                     // full 0x40000 (4Mbit=~512 M10K) exceeds BRAM; wolf_top
                                                     // shrinks it for the 1st flash (real fix = RAM->SDRAM).
  parameter              ROM_HEX      = "umk3_maindata.hex",
  parameter              GFX_HEX      = "build/umk3_gfx.hex",
  parameter              CMOS_HEX     = "build/umk3_cmos.hex", // sim-only warm-CMOS seed
                                                              // (only used under `ifdef WOLF_CMOS_SEED)
  // sim-only near-blit seed HEX paths (only used under `ifdef WOLF_NEARBLIT_SEED);
  // passed straight through to wolf_mem's seed block.
  parameter              NB_VRAM_HEX  = "../../mame-gospel/trace/nearblit/vram.hex",
  parameter              NB_RAM_HEX   = "../../mame-gospel/trace/nearblit/ram.hex",
  parameter              NB_PAL_HEX   = "../../mame-gospel/trace/nearblit/pal.hex",
  parameter              NB_CMOS_HEX  = "../../mame-gospel/trace/nearblit/cmos.hex",
  // wolf_pic response profile. Byte 0 is bits [7:0]. The default remains the
  // captured UMK3 response; game-specific simulation/top levels may override it.
  parameter logic [127:0] PIC_RESPONSE_BYTES =
      128'h2B1E_4A0E_0217_6C60_B408_2509_DB01_9AF6,
  parameter bit          WWF_IO_SHUFFLE = 1'b0,
  // Preserve the modeled Wolf/MAME completion cadence used by the
  // cabinet-working UMK3 SRT renderer. Open Ice's source submits the next rink
  // descriptor from DIRQ, so queue overflow/high-water telemetry remains
  // exposed for cabinet validation instead of silently changing IRQ cadence.
  parameter bit          TIMED_IRQ_PUMP = 1'b1,
  // Pocket's serialized renderer can lag software's explicit GO bursts.
  // Extend the CPU register write handshake instead of dropping descriptors.
`ifdef POCKET
  parameter bit          DMA_REG_BACKPRESSURE = 1'b1,
  parameter bit          DMA_GO_WAIT_RETIRED = 1'b1,
`else
  parameter bit          DMA_REG_BACKPRESSURE = 1'b0,
  parameter bit          DMA_GO_WAIT_RETIRED = 1'b0,
`endif
  // MK3/Open Ice/WWF/NBA use MAME's development-PIC/base serial protocol,
  // whose status bit follows the serial clock immediately. UMK3 and Rampage
  // use an emulated PIC16C57 and retain the measured firmware turnaround.
  parameter bit          PIC_STATUS_DELAY = 1'b1,
  // PIC status turnaround (io_r case4 bit12 assert TIMING), MAME-diffed to
  // picstat.txt: COLD = one-shot post-reset PIC-firmware boot (~865k cyc, keeps the
  // fresh-CMOS io-poll spinning through the boot-smoke window); WARM = steady-state
  // per-byte turnaround (~3184 cyc). Parameterized so the connectivity TB can shrink
  // COLD to exercise the gate quickly; boot/blit hosts keep the faithful defaults.
  parameter int          PIC_COLD_TURN = 865560,
  parameter int          PIC_WARM_TURN = 3184
)(
  input  logic        clk,
  input  logic        rst,

  // CPU (TMS34010 core) request-valid memory interface.
  input  logic        mem_req,
  input  logic        mem_we,
  input  logic [31:0] mem_addr,          // bit address
  input  logic  [5:0] mem_size,          // field width 1..32
  input  logic [31:0] mem_wdata,
  output logic [31:0] mem_rdata,
  output logic        mem_ack,
  // SRT sideband (TMS34010 P0027): request qualifier, asserted WITH mem_req when
  // DPYCTL bit 11 converts a graphics pixel access. Passed through to wolf_mem
  // (contract there). Never asserted for the R_DMA register region by the game;
  // wolf_mem z-guards it, so legacy hosts may leave the port unconnected.
  input  logic        mem_srt,
  input  logic        publication_hold, // blocks only new framebuffer-producing requests

  // Unpacked-gfx source (to external gfx ROM / SDRAM): 1 byte/pixel. 32-bit byte
  // index (wolf_dma packed-gfx offset space is 32-bit, vs Y-unit 24).
  output logic        src_req,
  output logic [31:0] src_addr,
  output logic        src_active,
  output logic        src_stream,
  input  logic  [7:0] src_data,
  input  logic        src_ack,

  // Player inputs: packed {port3, port2, port1, port0}, all ACTIVE-LOW.
  input  logic [63:0] inputs,
  // Runtime game selected by MRA index 3:
  // 0 Open Ice, 1 WWF, 2 MK3, 3 UMK3, 4 Hangtime, 5 Maximum, 6 Rampage.
  // Legacy testbenches may leave it open and retain the elaboration parameters.
  input  logic [2:0]  game_profile,

  // DMA-done interrupt line -> TMS34010 LINT1 (wolf_dma.blit_irq; P0016 semantics).
  output logic        int1,

  // ---- Sound: DCS byte latch (0x01680000 sound_r/w) ----------------------------
  output logic        snd_data_wr,       // 1-clk strobe: data_w(snd_data_o)
  output logic [7:0]  snd_data_o,        // sound command byte (D[7:0])
  output logic        snd_data_rd,       // 1-clk strobe: host read dcs.data_r()
  output logic        snd_reset,         // active-HIGH DCS reset (io_w case1: D[4])
  input  logic [7:0]  snd_rdata,         // dcs.data_r()    -> R_SOUND read
  input  logic [15:0] snd_stat,          // dcs.control_r() -> io_r case4 low bits

  // ---- Security: MIDWAY_SERIAL_PIC (0x01600000 security_r/w) --------------------
  output logic        pic_wr,            // 1-clk strobe: pic.write(pic_wdata)
  output logic [7:0]  pic_wdata,         // security_w D[7:0]
  output logic        pic_reset,         // io_w case1 bit5
  input  logic [7:0]  pic_rdata,         // pic.read()     -> R_SECURITY read
  input  logic [3:0]  pic_status,        // pic.status_r() -> io_r case4 bits 15:12

  // ---- Watchdog (io_w case3 strobe) --------------------------------------------
  output logic        watchdog_kick,

  // ---- CONTROL taps ------------------------------------------------------------
  output logic [1:0]  gfxbank_o,         // control[9:8]: 8MB gfx quadrant select

  // Autoerase sweep trigger (retained INERT on Wolf; drivable by the top).
  input  logic        erase_start,
  input  logic [8:0]  erase_row0,
  input  logic [9:0]  erase_lines,
  output logic        erase_busy,

  // Byte-wide MiSTer/MAME-compatible Wolf CMOS persistence side port.
  input  logic        nvram_ext_en,
  input  logic        nvram_ext_wr,
  input  logic [15:0] nvram_ext_addr,
  input  logic [7:0]  nvram_ext_wdata,
  output logic [7:0]  nvram_ext_rdata,
  output logic        nvram_cpu_write,

  // Observability
  output logic        vram_wr_busy,  // VRAM write path draining (accept-level) -> DPYSTRT flip gate
  output logic [2:0]  dbg_vram_cst,  // DIAG: C-lane drain FSM state passthrough (pin the wedge)
  output logic        blit_busy,
  output logic        dbg_dma_q_overflow,
  output logic [8:0]  dbg_dma_q_highwater
`ifdef DIAG_FACEOFF
  , output logic        diag_px_evt
  , output logic [9:0]  diag_px_x
  , output logic [8:0]  diag_px_y
  , output logic        diag_px_write
  , output logic        diag_px_copy_nz
  , output logic        diag_px_color
`endif
`ifdef DIAG_FLIP
  , output logic        dbg_blit_trig   // blit-command capture taps (from wolf_dma)
  , output logic [31:0] dbg_blit_src
  , output logic [31:0] dbg_blit_wh
  , output logic [15:0] dbg_blit_cmd
  , output logic        dbg_exec_start
  , output logic        dbg_exec_done
  , output logic [31:0] dbg_exec_src
  , output logic        dbg_fb_we       // blitter VRAM WRITE tap (destination side)
  , output logic        dbg_fb_ack      // write-accept handshake (count ACKED writes, not held cycles)
  , output logic [18:0] dbg_fb_addr
  , output logic [15:0] dbg_fb_wdata
`endif
`ifdef YM_EXT_RD
  // CPU read-only external port (gfx/ROM in SDRAM) — exposed to the top controller.
  , output logic        cpu_gfx_rd
  , output logic [25:0] cpu_gfx_raddr   // [25:24] nonzero only under USE_DDR3_GFX gfxbank
  , input  logic [7:0]  cpu_gfx_rdata
  , input  logic        cpu_gfx_rack
  , output logic        cpu_gfx_is_rom  // 1=prog ROM(SDRAM) 0=gfx(DDR3): top-level cgfx demux key
`endif
`ifdef USE_SDRAM_VRAM
  // VRAM SDRAM channel + video scanout read port — exposed to the top controller/video.
  , input  logic        scan_req
  , input  logic [18:0] scan_addr
  , output logic [15:0] scan_data
  , output logic        scan_ack
`ifdef USE_DDR3_VRAM
  , input  logic        sdram_por   // P0022 POR for the DDR3 VRAM agent (scanout off SDRAM)
  , output logic [28:0] ddram_addr
  , output logic [7:0]  ddram_burstcnt
  , output logic        ddram_rd
  , output logic        ddram_we
  , output logic [63:0] ddram_din
  , output logic [7:0]  ddram_be
  , input  logic        ddram_busy
  , input  logic [63:0] ddram_dout
  , input  logic        ddram_dout_ready
`else
  , output logic [24:0] vsd_addr
  , output logic [15:0] vsd_din
  , output logic [1:0]  vsd_be
  , output logic        vsd_rd
  , output logic        vsd_wr
  , input  logic [15:0] vsd_dout
  , input  logic        vsd_ack
`endif
`endif
`ifdef USE_SDRAM_RAM
  // main-RAM SDRAM channel (from wolf_mem/ram_sdram) -> the top controller's arbiter
  , output logic [24:0] rsd_addr
  , output logic [15:0] rsd_din
  , output logic [1:0]  rsd_be
  , output logic        rsd_rd
  , output logic        rsd_wr
  , input  logic [15:0] rsd_dout
  , input  logic        rsd_ack
`endif
`ifdef USE_HW_RAM
  // Palette write-tap -> video scanout mirror (wolf_palram, in wolf_top).
  , output logic        palv_we_a
  , output logic [14:0] palv_aa
  , output logic [15:0] palv_awd
  , output logic        palv_we_b
  , output logic [14:0] palv_ba
  , output logic [15:0] palv_bwd
`endif
);

  // ---- DMA-region detect (0x01A00000 and its 0x080000 mirror) -----------
  // Both 0x01A00000 and 0x01A80000 live under top-12-bits == 0x01a (wolf_mem's
  // decode also routes 0x01a -> R_DMA). Same key as the Y-unit donor.
  wire is_dma_now = (mem_addr[31:20] == 12'h01A);

  // ---- wolf_mem (all non-DMA regions) -----------------------------------
  logic        mem_req_m;
  logic [31:0] mem_rdata_m;
  logic        mem_ack_m;

  // ---- wolf_pic (Midway serial-PIC security chip) INTERNAL LOOP ---------
  // The PIC handshake is now closed END-TO-END inside wolf_memsys: wolf_mem's
  // security_w/reset write taps (pic_wr/pic_wdata/pic_reset) drive wolf_pic, and
  // wolf_pic's response byte + status feed BACK into wolf_mem's R_SECURITY read
  // (io_r case4 bit12 + security_r). The external pic_rdata/pic_status INPUT ports
  // are retained for structural parity / a future external override but are no
  // longer the source wolf_mem reads — pic_rdata_int/pic_status_int are.
  logic [7:0] pic_rdata_int;   // wolf_pic.resp_data -> wolf_mem R_SECURITY read
  logic       pic_status_raw;  // wolf_pic.status    (immediate clock-bit mirror)
  logic       pic_status_int;  // turnaround-GATED status -> wolf_mem io_r case4 bit12
  logic       wwf_io_shuffle_active;
  logic       pic_status_delay_active;

  always_comb begin
    wwf_io_shuffle_active = WWF_IO_SHUFFLE;
    pic_status_delay_active = PIC_STATUS_DELAY;
    case (game_profile)
      3'd1: begin
        wwf_io_shuffle_active = 1'b1;
        pic_status_delay_active = 1'b0;
      end
      3'd0, 3'd2, 3'd4, 3'd5:
        pic_status_delay_active = 1'b0;
      3'd3, 3'd6:
        pic_status_delay_active = 1'b1;
      default: begin
        wwf_io_shuffle_active = WWF_IO_SHUFFLE;
        pic_status_delay_active = PIC_STATUS_DELAY;
      end
    endcase
  end

  // ---- wolf_dma blitter -------------------------------------------------
  logic        dma_reg_we;
  logic        dma_reg_offer;
  logic        dma_reg_ready;
  logic  [3:0] dma_reg_addr;
  logic [15:0] dma_reg_wdata;
  logic [15:0] dma_reg_rdata;
  logic        dma_fb_we;
  logic [FB_ADDR_W-1:0] dma_fb_addr;
  logic [15:0] dma_fb_wdata;
  logic [15:0] dma_palette;

  // blitter fb write completion: SDRAM path drives it from wolf_mem; BRAM path = 1-cycle.
`ifdef USE_SDRAM_VRAM
  logic mem_fb_ack;
  wire  dma_fb_ack = mem_fb_ack;
  logic dma_wr_busy;                 // VRAM write path draining (from wolf_mem) -> gates blit "done"
`else
  wire  dma_fb_ack = 1'b1;
  wire  dma_wr_busy = 1'b0;          // BRAM: fb_ack already means committed
`endif
  // The backend busy rises only after wolf_mem has decoded the CPU request.
  // Include the accepted CPU write during that gap, until its ACK. wolf_mem
  // samples mem_req only in M_IDLE; an admitted transaction is never stopped.
  logic cpu_vram_write_pending;
  wire cpu_vram_now = (mem_addr[31:22] == 10'd0);
  wire publication_hold_i = DMA_REG_BACKPRESSURE && (publication_hold === 1'b1);
  always_ff @(posedge clk) begin
    if (rst) cpu_vram_write_pending <= 1'b0;
    else if (mem_ack_m) cpu_vram_write_pending <= 1'b0;
    else if (mem_req_m && mem_we && cpu_vram_now)
      cpu_vram_write_pending <= 1'b1;
  end
  assign vram_wr_busy = dma_wr_busy || (DMA_REG_BACKPRESSURE && cpu_vram_write_pending);  // expose to wolf_top -> wolf_video DPYSTRT flip gate

  wolf_mem #(
    .ROM_WORDS(ROM_WORDS), .ROM_PROG_OFF(ROM_PROG_OFF), .RAM_WORDS(RAM_WORDS),
    .ROM_HEX(ROM_HEX), .GFX_HEX(GFX_HEX), .CMOS_HEX(CMOS_HEX),
    .NB_VRAM_HEX(NB_VRAM_HEX), .NB_RAM_HEX(NB_RAM_HEX),
    .NB_PAL_HEX(NB_PAL_HEX), .NB_CMOS_HEX(NB_CMOS_HEX),
    .WWF_IO_SHUFFLE(WWF_IO_SHUFFLE)
  ) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req_m), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata_m), .mem_ack(mem_ack_m),
    .mem_srt(mem_srt),
    .fb_we(dma_fb_we), .fb_addr(dma_fb_addr), .fb_wdata(dma_fb_wdata),
    .dma_palette(dma_palette),
    .inputs(inputs),
    .wwf_io_shuffle_i(wwf_io_shuffle_active),
    .snd_data_wr(snd_data_wr), .snd_data_o(snd_data_o), .snd_data_rd(snd_data_rd),
    .snd_reset(snd_reset),
    .snd_rdata(snd_rdata), .snd_stat(snd_stat),
    .pic_wr(pic_wr), .pic_wdata(pic_wdata), .pic_reset(pic_reset),
    // R_SECURITY read + io_r case4 bit12 sourced from the INTERNAL wolf_pic loop.
    .pic_rdata(pic_rdata_int), .pic_status({3'h0, pic_status_int}),
    .watchdog_kick(watchdog_kick), .gfxbank_o(gfxbank_o),
    .erase_start(erase_start), .erase_row0(erase_row0),
    .erase_lines(erase_lines), .erase_busy(erase_busy),
    .nvram_ext_en(nvram_ext_en), .nvram_ext_wr(nvram_ext_wr),
    .nvram_ext_addr(nvram_ext_addr), .nvram_ext_wdata(nvram_ext_wdata),
    .nvram_ext_rdata(nvram_ext_rdata), .nvram_cpu_write(nvram_cpu_write)
`ifdef USE_SDRAM_VRAM
    // dbg_vram_cst (VRAM-SDRAM C-lane drain FSM passthrough) only EXISTS on wolf_mem's port
    // list under USE_SDRAM_VRAM (wolf_mem.sv's whole VRAM-SDRAM port block is `ifdef`-guarded);
    // connecting it unconditionally here made this instantiation fail to elaborate in the
    // default (no USE_SDRAM_VRAM) config — a latent bug, only surfaced now that a Questa
    // integration TB is compiling wolf_memsys WITHOUT that define for the first time.
    , .dbg_vram_cst(dbg_vram_cst)
`endif
`ifdef YM_EXT_RD
    , .gfx_rd(cpu_gfx_rd), .gfx_raddr(cpu_gfx_raddr),
      .gfx_rdata(cpu_gfx_rdata), .gfx_rack(cpu_gfx_rack), .cgfx_is_rom(cpu_gfx_is_rom)
`endif
`ifdef USE_SDRAM_VRAM
    , .fb_ack(mem_fb_ack)
    , .fb_wr_busy(dma_wr_busy)
    , .scan_req(scan_req), .scan_addr(scan_addr), .scan_data(scan_data), .scan_ack(scan_ack)
`ifdef USE_DDR3_VRAM
    , .sdram_por(sdram_por)
    , .ddram_addr(ddram_addr), .ddram_burstcnt(ddram_burstcnt), .ddram_rd(ddram_rd), .ddram_we(ddram_we)
    , .ddram_din(ddram_din), .ddram_be(ddram_be)
    , .ddram_busy(ddram_busy), .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready)
`else
    , .vsd_addr(vsd_addr), .vsd_din(vsd_din), .vsd_be(vsd_be), .vsd_rd(vsd_rd), .vsd_wr(vsd_wr)
    , .vsd_dout(vsd_dout), .vsd_ack(vsd_ack)
`endif
`endif
`ifdef USE_SDRAM_RAM
    , .rsd_addr(rsd_addr), .rsd_din(rsd_din), .rsd_be(rsd_be), .rsd_rd(rsd_rd), .rsd_wr(rsd_wr)
    , .rsd_dout(rsd_dout), .rsd_ack(rsd_ack)
`endif
`ifdef USE_HW_RAM
    , .palv_we_a(palv_we_a), .palv_aa(palv_aa), .palv_awd(palv_awd)
    , .palv_we_b(palv_we_b), .palv_ba(palv_ba), .palv_bwd(palv_bwd)
`endif
  );
`ifndef USE_SDRAM_VRAM
  assign dbg_vram_cst = 3'd0;   // no VRAM-SDRAM C-lane drain FSM to report in this config
`endif

  wolf_dma #(
    .TIMED_IRQ_PUMP(TIMED_IRQ_PUMP),
    .WAIT_GO_RETIRED(DMA_GO_WAIT_RETIRED),
    .REG_WRITE_BACKPRESSURE(DMA_REG_BACKPRESSURE),
    .DRAIN_QUEUED_ON_STOP(1'b1)
  ) u_dma (
    .clk(clk), .rst(rst),
    .reg_we(dma_reg_offer), .reg_addr(dma_reg_addr),
    .reg_wdata(dma_reg_wdata), .reg_rdata(dma_reg_rdata), .reg_ready(dma_reg_ready), .go_hold(publication_hold_i),
    .src_req(src_req), .src_addr(src_addr), .src_active(src_active),
    .src_stream(src_stream),
    .src_data(src_data), .src_ack(src_ack),
    .fb_we(dma_fb_we), .fb_addr(dma_fb_addr), .fb_wdata(dma_fb_wdata),
    .fb_ack(dma_fb_ack),   // SDRAM: wolf_mem.fb_ack (blitter self-paces); BRAM: 1'b1
    .wr_busy(dma_wr_busy), // blit "done" waits for the write path to commit (not just accept)
    .busy(blit_busy), .blit_irq(int1), .dma_palette(dma_palette),  // P0016: -> LINT1
    .dbg_q_overflow(dbg_dma_q_overflow), .dbg_q_highwater(dbg_dma_q_highwater)
`ifdef DIAG_FACEOFF
    , .diag_px_evt(diag_px_evt), .diag_px_x(diag_px_x), .diag_px_y(diag_px_y)
    , .diag_px_write(diag_px_write), .diag_px_copy_nz(diag_px_copy_nz)
    , .diag_px_color(diag_px_color)
`endif
`ifdef DIAG_FLIP
    , .dbg_blit_trig(dbg_blit_trig), .dbg_blit_src(dbg_blit_src)
    , .dbg_blit_wh(dbg_blit_wh), .dbg_blit_cmd(dbg_blit_cmd)
    , .dbg_exec_start(dbg_exec_start), .dbg_exec_done(dbg_exec_done), .dbg_exec_src(dbg_exec_src)
`endif
  );
`ifdef DIAG_FLIP
  assign dbg_fb_we = dma_fb_we; assign dbg_fb_ack = dma_fb_ack;
  assign dbg_fb_addr = dma_fb_addr; assign dbg_fb_wdata = dma_fb_wdata;
`endif

  // ---- wolf_pic instance + host-bus glue (closes the PIC handshake loop) ----
  // Three bus taps drive the FSM (WOLF_PIC_SPEC.md §1, midwunit_m.cpp):
  //   command write : pic_wr / pic_wdata          (wolf_mem security_w tap, :347)
  //   response read : resp_re (pulse on a security_r ACK)   (security_r, :338)
  //   reset         : reset_w / reset_val          (io_w case1 bit5, :80-81)
  //
  // resp_re — the read() side-effect. midwayic.cpp:196-204 read() sets m_status=1
  // (guarded by !side_effects_disabled(), i.e. only on a REAL bus read). So pulse
  // resp_re for exactly one cycle on each genuine security_r read completion: the
  // RISING edge of mem_ack for a non-write access to the R_SECURITY base
  // (0x01600000, mem_addr[31:4]==0x0160000; bit19=0 => SECURITY not SOUND). A DUT
  // debug/speculative read never acks, so this matches MAME's side-effect gating.
  //
  // reset_w — MAME calls reset_w(newword & 0x20) on EVERY io_w case1 write
  // (midwunit_m.cpp:80), resetting iff bit5 set (midwayic.cpp:181 state-true=reset).
  // wolf_mem drives pic_reset as a LEVEL (=wd_q[5], latched, held across writes), so
  // a level connection to wolf_pic.reset_w/reset_val would pin the FSM in reset while
  // bit5 stays high. Convert to the MAME event: pulse reset_w for one cycle on the
  // 0->1 edge of pic_reset (reset_val=1 there => FSM zeroes); a 1->0 edge pulses with
  // reset_val=0 (a no-op in wolf_pic). This reproduces "reset on a write carrying
  // bit5=1" without a spurious hold. (Behavior guarded by the boot/PIC gates.)
  logic pic_ack_q;         // prior-cycle security-read ack (edge detect)
  logic pic_reset_q;       // prior-cycle pic_reset level (edge detect)
  wire  sec_rd_now = mem_req && !mem_we && !is_dma_now
                     && (mem_addr[31:4] == 28'h0160000) && mem_ack;
  wire  pic_resp_re = sec_rd_now && !pic_ack_q;      // 1-cyc pulse on the read ACK edge
  wire  pic_reset_w = pic_reset ^ pic_reset_q;       // 1-cyc pulse on ANY pic_reset edge

  always_ff @(posedge clk) begin
    if (rst) begin
      pic_ack_q   <= 1'b0;
      pic_reset_q <= 1'b0;
    end else begin
      pic_ack_q   <= sec_rd_now;
      pic_reset_q <= pic_reset;
    end
  end

  logic [7:0] pic_rdata_param, pic_rdata_dev, pic_rdata_umk3, pic_rdata_rwt;
  logic       pic_status_param, pic_status_dev, pic_status_umk3, pic_status_rwt;

  // All four tiny protocol engines receive the same bus events. The selected
  // profile only multiplexes their response ROM, so game identity cannot
  // perturb the proven serial state/timing machinery.
  wolf_pic #(.RESPONSE_BYTES(PIC_RESPONSE_BYTES)) u_pic_param (
    .clk(clk), .rst(rst),
    .cmd_we(pic_wr), .cmd_data(pic_wdata),
    .resp_re(pic_resp_re),
    .reset_w(pic_reset_w), .reset_val(pic_reset),
    .resp_data(pic_rdata_param), .status(pic_status_param)
  );
  wolf_pic #(.RESPONSE_BYTES(
      128'h0000_4A0E_A018_4580_0614_C3B2_0301_8444)) u_pic_dev528 (
    .clk(clk), .rst(rst),
    .cmd_we(pic_wr), .cmd_data(pic_wdata),
    .resp_re(pic_resp_re),
    .reset_w(pic_reset_w), .reset_val(pic_reset),
    .resp_data(pic_rdata_dev), .status(pic_status_dev)
  );
  wolf_pic #(.RESPONSE_BYTES(
      128'h2B1E_4A0E_0217_6C60_B408_2509_DB01_9AF6)) u_pic_umk3 (
    .clk(clk), .rst(rst),
    .cmd_we(pic_wr), .cmd_data(pic_wdata),
    .resp_re(pic_resp_re),
    .reset_w(pic_reset_w), .reset_val(pic_reset),
    .resp_data(pic_rdata_umk3), .status(pic_status_umk3)
  );
  wolf_pic #(.RESPONSE_BYTES(
      128'h8C09_69CD_2519_7F61_D70D_4110_1003_085B)) u_pic_rwt (
    .clk(clk), .rst(rst),
    .cmd_we(pic_wr), .cmd_data(pic_wdata),
    .resp_re(pic_resp_re),
    .reset_w(pic_reset_w), .reset_val(pic_reset),
    .resp_data(pic_rdata_rwt), .status(pic_status_rwt)
  );

  always_comb begin
    pic_rdata_int = pic_rdata_param;
    pic_status_raw = pic_status_param;
    case (game_profile)
      3'd0, 3'd1, 3'd2, 3'd4, 3'd5: begin
        pic_rdata_int = pic_rdata_dev;
        pic_status_raw = pic_status_dev;
      end
      3'd3: begin
        pic_rdata_int = pic_rdata_umk3;
        pic_status_raw = pic_status_umk3;
      end
      3'd6: begin
        pic_rdata_int = pic_rdata_rwt;
        pic_status_raw = pic_status_rwt;
      end
      default: begin
        pic_rdata_int = pic_rdata_param;
        pic_status_raw = pic_status_param;
      end
    endcase
  end

  // ---- PIC status TURNAROUND gate (io_r case4 bit12 TIMING) ------------------
  // wolf_pic transcribes the BASE serial device, whose status = (data>>4)&1 asserts
  // IMMEDIATELY (midwayic.cpp:212). UMK3 uses the EMU device (wunit_picemu,
  // midwunit.cpp:666-670), whose status comes from a real PIC16C57 running firmware
  // (midwayic.cpp:309 write_c bit6) — so its bit12 asserts on a measured DELAY. The
  // VALUES are identical (architect-ratified, WOLF_PIC_SPEC.md §0); only the TIMING
  // differs, so the delay lives HERE in the wrapper, not in wolf_pic (guardrail).
  //
  // MAME-diffed cadence (mame-gospel/trace/picstat.txt BIT12 waveform):
  //   * COLD start (one-shot post-reset PIC boot): PIC_W#1 @cyc=15272, first
  //     BIT12 0->1 @cyc=880832 => ~865,560 cyc settle. This is why the FRESH-CMOS
  //     io-poll (@FFBBEC80) SPINS the entire 8000-PC golden window (bit12 stays 0):
  //     the boot writes 0x10 but the PIC has not finished booting, so the poll never
  //     releases in-window. REQUIRED to keep run_questa_wolf_boot.sh 8000/8000.
  //   * WARM steady-state (per serial byte, cyc>5.06M): each PIC_W drops bit12
  //     (picstat "BIT12 1->0 on every PIC_W"), re-asserting ~3150-3184 cyc later.
  // Model: a one-shot COLD delay after reset, then the short WARM turnaround per
  // write. bit12 drops on every pic_wr and re-asserts when the counter elapses. This
  // reproduces both the boot-smoke spin and the downstream serial read-back release.
  //
  // HW-FIT: a 20-bit down-counter + 2 flags — trivial on Cyclone V (no BRAM/DSP; a
  // ~865k reload is a plain compile-time constant, the counter is one adder).
  // (PIC_COLD_TURN / PIC_WARM_TURN are module parameters; see the header.)
  logic [19:0] pic_turn_cnt;
  logic        pic_cold;                  // 1 until the first post-reset assert
  logic        pic_gate;                  // gated status FF (io_r case4 bit12)

  always_ff @(posedge clk) begin
    if (rst) begin
      pic_turn_cnt <= PIC_COLD_TURN[19:0];
      pic_cold     <= 1'b1;
      pic_gate     <= 1'b0;
    end else if (pic_reset_w && pic_reset) begin
      // PIC reset edge (io_w case1 bit5=1): re-arm the cold boot delay.
      pic_turn_cnt <= PIC_COLD_TURN[19:0];
      pic_cold     <= 1'b1;
      pic_gate     <= 1'b0;
    end else if (pic_wr) begin
      // Any security_w drops bit12 and restarts the turnaround (WARM once booted).
      pic_gate     <= 1'b0;
      pic_turn_cnt <= pic_cold ? PIC_COLD_TURN[19:0] : PIC_WARM_TURN[19:0];
    end else if (pic_turn_cnt != 20'd0) begin
      pic_turn_cnt <= pic_turn_cnt - 20'd1;
    end else begin
      // Turnaround elapsed: let wolf_pic's status through (bit12 asserts).
      pic_gate <= pic_status_raw;
      pic_cold <= 1'b0;                   // first assert clears cold -> WARM thereafter
    end
  end

  // io_r case4 bit12 = the gated status. (wolf_pic.status_raw carries the VALUE; the
  // gate carries MAME's assert TIMING.) AND with raw so a wolf_pic reset (status low)
  // forces bit12 low immediately regardless of the counter.
  assign pic_status_int = pic_status_delay_active
                        ? (pic_gate & pic_status_raw)
                        : pic_status_raw;

  // ---- DMA register access FSM ------------------------------------------
  // The DMA registers are 16-bit at word-aligned bit addresses (reg offset =
  // addr[7:4]). The 34010 memory system splits a >16-bit field write into
  // consecutive word writes, so a 32-bit field write to offset N updates offset N
  // (low word) AND N+1 (high word) — MAME calls dma_w twice. wolf_dma maps the
  // raw offset (0..15) to a regnum via dma_regmap(DMA_CONFIG[5]) and triggers on a
  // DMA_COMMAND write with bit15; the FSM here only sequences the two word writes.
  typedef enum logic [1:0] { D_IDLE, D_LO, D_HI, D_ACKR } dstate_t;
  dstate_t dstate;
  logic [31:0] d_addr_q;
  logic        d_we_q;
  logic [31:0] d_wd_q;
  logic  [5:0] d_sz_q;
  logic        dma_ack;

  wire d_second = (dstate == D_HI);
  assign dma_reg_addr  = d_second ? (d_addr_q[7:4] + 4'd1) : d_addr_q[7:4];
  assign dma_reg_wdata = d_second ? d_wd_q[31:16]          : d_wd_q[15:0];
  wire dma_word_accept = !DMA_REG_BACKPRESSURE || dma_reg_ready;
  assign dma_reg_offer = (dstate == D_LO) || (dstate == D_HI);
  assign dma_reg_we = dma_reg_offer && dma_word_accept;

  always_ff @(posedge clk) begin
    if (rst) begin
      dstate  <= D_IDLE;
      dma_ack <= 1'b0;
    end else begin
      unique case (dstate)
        D_IDLE: begin
          dma_ack <= 1'b0;
          if (mem_req && is_dma_now && !mem_ack) begin
            d_addr_q <= mem_addr;
            d_we_q   <= mem_we;
            d_wd_q   <= mem_wdata;
            d_sz_q   <= mem_size;
            dstate   <= mem_we ? D_LO : D_ACKR;
          end
        end
        D_LO: if (dma_word_accept)
                    dstate <= (d_sz_q > 6'd16) ? D_HI : D_ACKR;
        D_HI: if (dma_word_accept) dstate <= D_ACKR;
        D_ACKR: begin dma_ack <= 1'b1; dstate <= D_IDLE; end
        default: dstate <= D_IDLE;
      endcase
    end
  end

  // ---- output mux -------------------------------------------------------
  // Route the request: DMA region -> the DMA FSM (mem_req_m held low so
  // wolf_mem ignores it); everything else -> wolf_mem.
  assign mem_req_m = mem_req && !is_dma_now &&
                     !(publication_hold_i && cpu_vram_now && mem_we);
  assign mem_ack   = is_dma_now ? dma_ack : mem_ack_m;
  assign mem_rdata = is_dma_now ? {16'h0000, dma_reg_rdata} : mem_rdata_m;

endmodule

`default_nettype wire

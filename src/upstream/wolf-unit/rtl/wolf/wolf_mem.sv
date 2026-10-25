// wolf_mem.sv — Midway Wolf-unit (UMK3) memory controller / bit-address decoder.
//
// FORK of yunit_mem.sv (Williams Y-unit / Smash T.V.). The TMS34010 field-access
// engine (1..32-bit field at any bit address, 3-word straddle RMW), the M_ACK FSM,
// the VRAM byte-lane engine, and all the Phase-6 HW backends (USE_HW_RAM/VRAM,
// USE_SDRAM_VRAM, external gfx/rom fetch) are REUSED VERBATIM. Only the region
// DECODE and the region HANDLERS change per the Wolf memory map. Every region
// behavior is cited to vendored MAME gospel (mame-gospel/midway/): midwunit.cpp
// (main_map :113-127), midwunit_m.cpp (io/cmos/security/sound machine bodies),
// midtunit_v.cpp (vram_r/w byte-lane, midwunit_control_w :370). Constants live in
// rtl/pkg/wolf_pkg.sv. See rtl/wolf/WOLF_MEM_PLAN.md.
//
// Address model (same as Y-unit): word_idx = mem_addr[31:4], bit_off = mem_addr[3:0].
// MAME's midwunit map values ARE these bit-addresses directly. No shift.
//
// KEY DIFFERENCES FROM Y-UNIT (all gospel-grounded):
//  - CMOS is FLAT (m_nvram[offset]) — NO Y-unit paging — and cmos_w is GATED by a
//    ONE-SHOT write-enable latch set by a write to CMOSEN (0x01480000).
//  - Regions 0x014/0x016/0x018 each share a top-12-bit megabyte with a sibling; an
//    a_q[19] sub-decode splits them (CMOS/CMOSEN, SECURITY/SOUND, IO/PAL).
//  - I/O is the boot-gating region (io_r/io_w with ioshuffle); case 4 = status word
//    ((pic_status<<12) | dcs_control). Sound is DCS (byte latch), not CVSD.
//  - CONTROL @0x01B00000: videobank = bit 11 (not bit 5); gfxbank = bits 9:8; there
//    is NO cmos-page and NO autoerase (T/Wolf video has no autoerase_line — the
//    framebuffer clears via explicit DMA fills). The autoerase engine below is
//    RETAINED INERT (autoerase never set) to keep the VRAM field engine untouched.
//  - Palette is 32768-color DIRECT (15-bit), 1 word/entry.
//
// NOTE: this is a functional model (single-cycle 3-word window). The real HW
// memory controller (SDRAM, multi-cycle) is Phase 6; the field semantics here
// are the contract it must preserve.

`default_nettype none

// Phase-6 external-read machinery guard: shared FSM/ports for serving CPU
// read-only regions (GFX, program ROM) from an external memory (SDRAM). Active
// if EITHER region is externalized. SYNTHESIS implies both. USE_EXT_GFX /
// USE_EXT_ROM alone drive the focused equivalence TBs (tb_yunit_gfx/tb_yunit_rom).
`ifdef SYNTHESIS
  `ifndef USE_EXT_GFX
    `define USE_EXT_GFX
  `endif
  `ifndef USE_EXT_ROM
    `define USE_EXT_ROM
  `endif
  `ifndef USE_HW_RAM
    `define USE_HW_RAM
  `endif
  `ifndef USE_SDRAM_VRAM
    `define USE_SDRAM_VRAM
  `endif
  `ifndef USE_SDRAM_RAM
    `define USE_SDRAM_RAM
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
// VRAM has two synthesizable backends: USE_HW_VRAM (2-port BRAM — the sim-testable
// intermediate) and USE_SDRAM_VRAM (vram_sdram_top — the real DE10 path; SYNTHESIS picks
// this since 4Mbit VRAM won't fit BRAM). YM_VRAM_HW = either -> the functional VRAM
// accessors (read_word R_VRAM, the R_VRAM write case, blitter fb_we, autoerase) are
// guarded out and handled by the selected backend.
`ifdef USE_HW_VRAM
  `define YM_VRAM_HW
`endif
`ifdef USE_SDRAM_VRAM
  `ifndef YM_VRAM_HW
    `define YM_VRAM_HW
  `endif
`endif

module wolf_mem
  import wolf_pkg::*;
#(
  parameter int ROM_WORDS  = 32'h20000,  // program-ROM words backed internally (sim); the wolf
                                         // boot TB sets this + ROM_PROG_OFF to the umk3_maindata
                                         // layout. Real program window 0xFF800000-0xFFFFFFFF.
  parameter logic [27:0] ROM_PROG_OFF = 28'h60000, // program's region-word offset (TB-tunable)
  parameter int RAM_WORDS  = 32'h40000,  // main RAM = MAME m_mainram 0x01000000-0x013FFFFF
                                         // (0x400000 bit-addrs / 16 = 0x40000 words = 512KB;
                                         // 4x the Y-unit region). Decode is subtract+compare
                                         // (NOT masked) -> addrs >= size fall through to unmapped.
  parameter int VRAM_WORDS = 32'h80000,  // local_videoram ENTRIES (MAME m_local_videoram[0x80000]):
                                         // each 34010 VRAM word maps to 2 entries (offset*2). 2x Y-unit.
  parameter int PAL_WORDS  = 32'h8000,   // palette RAM: region 0x01880000-0x018FFFFF = 0x8000 words
                                         // = 32768 DIRECT 15-bit colors (Wolf drops Y-unit's 6bpp fold)
  parameter int CMOS_WORDS = 32'h6000,   // battery NVRAM, FLAT (region 0x01400000-0x0145FFFF = 0x6000 words)
  parameter int GFX_PIXELS = 32'h180000, // unpacked gfx-ROM pixels (sim window; real gfx -> SDRAM/DDR3)
  parameter     ROM_HEX    = "umk3_maindata.hex",
  parameter     GFX_HEX    = "build/umk3_gfx.hex", // unpacked 1 byte/pixel (make_gfx_hex.py)
  parameter     CMOS_HEX   = "build/umk3_cmos.hex", // sim-only WARM CMOS seed (make_cmos_hex.py);
                                                    // ONLY loaded under `ifdef WOLF_CMOS_SEED
  // sim-only NEAR-BLIT seed (nearblit_dump.lua): the 4 writable regions dumped from
  // MAME at cyc~166M, one 34010 word per line at stride 16. ONLY loaded under
  // `ifdef WOLF_NEARBLIT_SEED. See the seed block below (mirrors the CMOS_SEED hook).
  parameter     NB_VRAM_HEX = "../../mame-gospel/trace/nearblit/vram.hex",
  parameter     NB_RAM_HEX  = "../../mame-gospel/trace/nearblit/ram.hex",
  parameter     NB_PAL_HEX  = "../../mame-gospel/trace/nearblit/pal.hex",
  parameter     NB_CMOS_HEX = "../../mame-gospel/trace/nearblit/cmos.hex",
  // WWF WrestleMania installs a game-specific physical-to-logical I/O address
  // shuffler. All other Wolf games retain the reset identity map.
  parameter bit WWF_IO_SHUFFLE = 1'b0
)(
  input  logic        clk,
  input  logic        rst,

  input  logic        mem_req,
  input  logic        mem_we,
  input  logic [31:0] mem_addr,          // bit address
  input  logic  [5:0] mem_size,          // field width 1..32
  input  logic [31:0] mem_wdata,
  output logic [31:0] mem_rdata,
  output logic        mem_ack,
  // SRT sideband (TMS34010 P0027, rtl/tms34010/changelog.md 'Sideband contract'):
  // asserted WITH mem_req when DPYCTL bit 11 converts a graphics PIXEL access.
  //   mem_srt && !mem_we (LATCH):    copy 1024 consecutive FULL 16-bit VRAM ENTRIES
  //     (palette-high bytes INCLUDED — midtunit_v.cpp:330-333 to_shiftreg memcpy of
  //     2*512 u16 at entry index bitaddr>>3) starting at entry 2*(mem_addr>>4) into
  //     the row buffer; ack with rdata = the normal CPU-visible word read at mem_addr
  //     (A0033: MAME returns m_shiftreg[0]; the game discards the PIXT result).
  //   mem_srt && mem_we (TRANSFER):  copy the row buffer to 1024 entries at
  //     2*(mem_addr>>4); mem_wdata/mem_size DISCARDED (midtunit_v.cpp:336-339);
  //     ack only when the copy has RETIRED to the backing store (a subsequent CPU
  //     access must see it). Raw addresses, no extra row alignment. SRT on any
  //     non-VRAM region executes as a NORMAL access (+ a sim warning — the game
  //     never does it). Legacy hosts may leave this port unconnected (z-guarded).
  input  logic        mem_srt,

  // Blitter VRAM write port (yunit_dma fb_*): writes a full 16-bit
  // {palette,pixel} local_videoram word at a PIXEL index, bypassing the
  // videobank byte-lane (matches MAME dma_draw's direct local_videoram store).
  input  logic                  fb_we,
  input  logic [FB_ADDR_W-1:0]  fb_addr,
  input  logic [15:0]           fb_wdata,
  // Blitter DMA_PALETTE reg — the CPU vram_w byte-lane folds this into the
  // plane it is NOT writing (MAME midyunit_v.cpp:140-142). 0 until wired.
  input  logic [15:0]           dma_palette,
  // Player inputs. Packed {port3, port2, port1, port0}, all ACTIVE-LOW (idle =
  // all-ones). MAME io_r cases 0-3 return m_ports[0..3] (IN0/IN1/IN2/DSW). See
  // midwunit.cpp INPUT_PORTS mk3 (IN0 = P1/P2 joy + HP/Blk/HK, IN1 = LP/LK/Run, DSW).
  input  logic [63:0]           inputs,
  // One-RBF master override. Legacy simulations may leave this open and keep
  // using the WWF_IO_SHUFFLE elaboration parameter.
  input  logic                  wwf_io_shuffle_i,

  // ---- Sound: DCS byte latch (0x01680000 sound_r/w, midwunit_m.cpp:364/379) ----
  // sound_w -> m_dcs->data_w(data & 0xff); io_w case1 bit4 resets the DCS. sound_r
  // -> m_dcs->data_r() & 0xff (snd_rdata). io_r case4 status = m_dcs->control_r()
  // (snd_stat). These are the host-side DCS glue signals; wolf_dcs_board consumes
  // the same byte-latch/reset contract in the integrated core.
  output logic                  snd_data_wr,   // 1-clk strobe: data_w(snd_data_o)
  output logic [7:0]            snd_data_o,    // sound command byte (D[7:0])
  output logic                  snd_data_rd,   // 1-clk strobe: host read dcs.data_r()
  output logic                  snd_reset,     // active-HIGH DCS reset (io_w case1: D[4])
  input  logic [7:0]            snd_rdata,     // dcs.data_r()    -> R_SOUND read
  input  logic [15:0]           snd_stat,      // dcs.control_r() -> io_r case4 low bits

  // ---- Security: MIDWAY_SERIAL_PIC (0x01600000 security_r/w, midwunit_m.cpp:338) --
  // Behavioral stub for bring-up (PIC is read ~17x during boot, not the boot gate;
  // the gate is CMOS). A real serial-PIC model attaches here later.
  output logic                  pic_wr,        // 1-clk strobe: pic.write(pic_wdata)
  output logic [7:0]            pic_wdata,      // security_w D[7:0]
  output logic                  pic_reset,     // io_w case1 bit5 (active-low reset)
  input  logic [7:0]            pic_rdata,      // pic.read()     -> R_SECURITY read
  input  logic [3:0]            pic_status,     // pic.status_r() -> io_r case4 bits 15:12

  // ---- Watchdog (io_w case3 strobe; MAME leaves it a no-op) --------------------
  output logic                  watchdog_kick, // 1-clk pulse on an io_w case3 write

  // ---- CONTROL taps (midwunit_control_w, midtunit_v.cpp:370) -------------------
  output logic [1:0]            gfxbank_o,     // control[9:8]: 8MB gfx quadrant select

  // ---- Autoerase sweep trigger (MAME midyunit_v.cpp:534-560) -------------
  // MAME erases each displayed VRAM row right after it is scanned (one row
  // behind the beam: scanline_update:554 calls autoerase_line(rowaddr-1),
  // and :558-559 erases the FINAL row via a timer one line later), filling
  // it with the 512-word pattern the game keeps in VRAM row 510 (even target
  // rows) / 511 (odd target rows) — autoerase_line:539. Gated on the CONTROL
  // register /autoerase bit (control_w:235, active LOW, captured below).
  //
  // This port is the frame-paced form: pulse erase_start ONCE at the end of
  // visible scanout with the displayed window (erase_row0 = the rowaddr of
  // the first visible scanline, erase_lines = visible line count) and the
  // engine sweeps rows (erase_row0-1) .. (erase_row0+erase_lines-1) mod 512,
  // which is exactly MAME's per-frame erased set. The Phase-6 (HW-honest)
  // form is scanline-paced: yunit_video pulses this once per scanline with
  // erase_row0 = that line's rowaddr, erase_lines = 0 special-cased — or
  // simply re-uses this engine with a 1-row window per hsync. Left unconnected
  // (legacy TBs) erase_start floats z and the engine never starts.
  input  logic                  erase_start,   // 1-clk pulse: run one sweep
  input  logic [8:0]            erase_row0,    // first DISPLAYED VRAM row
  input  logic [9:0]            erase_lines,   // visible scanline count
  output logic                  erase_busy,

  // MiSTer index-4 NVRAM side port. The wrapper holds the game in reset while
  // this byte port writes CMOS; uploads are read-only and may run live.
  input  logic                  nvram_ext_en,
  input  logic                  nvram_ext_wr,
  input  logic [15:0]           nvram_ext_addr,
  input  logic [7:0]            nvram_ext_wdata,
  output logic [7:0]            nvram_ext_rdata,
  output logic                  nvram_cpu_write
`ifdef YM_EXT_RD
  // Phase 6 W1: external read-only-region port (SDRAM-backed). The unpacked gfx
  // array (1.5 MB) and program ROM (256 KB) OOM Quartus as on-chip RAM, so the CPU
  // read-only windows — R_GFX (boot ROM-checksum; blitter reads gfx via src_*) and
  // R_ROM (instruction fetch + ROM data) — are fetched byte-by-byte through the
  // arbiter/SDRAM. ONE port: CPU R_GFX and R_ROM serialize through this FSM.
  // SDRAM byte layout: gfx @ 0, program ROM @ SDRAM_ROMB (= gfx byte size).
  , output logic        gfx_rd      // read request (held until gfx_rack)
  , output logic [25:0] gfx_raddr   // external byte address (gfx or ROM region; [25:24]
                                    // only nonzero under USE_DDR3_GFX gfxbank — the legacy
                                    // SDRAM arb consumes [23:0], bit-identical)
  , input  logic [7:0]  gfx_rdata   // read byte
  , input  logic        gfx_rack    // data-valid strobe
  , output logic        cgfx_is_rom // 1 = this ext fetch is program ROM (SDRAM), 0 = gfx
                                    // (DDR3). Latched at fetch launch (region==R_ROM) and held
                                    // for the whole 6-byte fetch. The top-level cgfx demux keys
                                    // on THIS (not address): gfx bank-0 [0,0x800000) overlaps
                                    // program ROM [SDRAM_ROMB,...) so an address compare is
                                    // ambiguous. Only consumed under USE_DDR3_GFX; harmless else.
`endif
`ifdef USE_SDRAM_VRAM
  // Phase 6 W1f: VRAM lives in SDRAM (4Mbit won't fit BRAM). vram_sdram_top multiplexes
  // CPU field RMW + blitter fb writes + autoerase + scanout onto ONE 16-bit SDRAM channel.
  , output logic        fb_ack      // blitter write accepted (self-paces the blitter)
  , output logic        fb_wr_busy  // VRAM write path still draining (blit-done handshake gate)
  , output logic [2:0]  dbg_vram_cst // DIAG: C-lane drain FSM state passthrough (pin the wedge)
  , input  logic        scan_req    // video scanout read request (held until scan_ack)
  , input  logic [18:0] scan_addr   // VRAM entry to read
  , output logic [15:0] scan_data   // scanout read data (valid at scan_ack)
  , output logic        scan_ack
`ifdef USE_DDR3_VRAM
  // VRAM off the shared SDRAM -> HPS DDR3 Avalon master (stv_vram_ddr_top). This is the
  // scanout-starvation fix: scanout + CPU-VRAM + fb no longer contend for SDRAM.
  , input  logic        sdram_por   // P0022 power-on reset for the persistent DDR3 agent
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
  , output logic [24:0] vsd_addr    // VRAM SDRAM word address (channel out)
  , output logic [15:0] vsd_din
  , output logic [1:0]  vsd_be
  , output logic        vsd_rd
  , output logic        vsd_wr
  , input  logic [15:0] vsd_dout
  , input  logic        vsd_ack
`endif
`endif
`ifdef USE_SDRAM_RAM
  // Main RAM (0x40000 words = 4 Mbit) lives in SDRAM too — it won't fit BRAM alongside the
  // 32768-colour palettes. ram_sdram (CPU-only: no blitter fb, no scanout, no autoerase)
  // sequences the field RMW over its own 16-bit SDRAM channel; the arbiter adds RAMW_BASE.
  , output logic [24:0] rsd_addr
  , output logic [15:0] rsd_din
  , output logic [1:0]  rsd_be
  , output logic        rsd_rd
  , output logic        rsd_wr
  , input  logic [15:0] rsd_dout
  , input  logic        rsd_ack
`endif
`ifdef USE_HW_RAM
  // Phase 6 W3: palette write-tap for the video scanout mirror (yunit_palram). The
  // palette BRAM's two ports are consumed by the CPU field engine, so the video keeps
  // a mirror updated from these strobes. Port A = word0, port B = word1 (a >=17-bit
  // palette field writes both the same cycle; a 33-bit-spanning field writes word2 on
  // port A a cycle later, i.e. another palv_we_a pulse).
  , output logic        palv_we_a
  , output logic [14:0] palv_aa
  , output logic [15:0] palv_awd
  , output logic        palv_we_b
  , output logic [14:0] palv_ba
  , output logic [15:0] palv_bwd
`endif
);

  // ---- Region encoding --------------------------------------------------
  // Y-unit R_INPUT/R_PROT dropped; Wolf adds R_CMOSEN, R_IO, R_SECURITY. The
  // is_hwram/MEASURE_ACCESS blocks key on R_RAM/R_PAL/R_CMOS by NAME, so the
  // numeric renumber is safe.
  localparam logic [3:0] R_NONE=4'd0, R_VRAM=4'd1, R_RAM=4'd2, R_CMOS=4'd3,
                         R_CMOSEN=4'd4, R_PAL=4'd5, R_DMA=4'd6, R_IO=4'd7,
                         R_SECURITY=4'd8, R_SOUND=4'd9, R_CTRL=4'd10, R_GFX=4'd11,
                         R_ROM=4'd12;

  // Region-base word indices (base >> 4).
  localparam logic [27:0] WB_RAM  = 28'(WMAP_RAM_BASE      >> 4); // 0x0100000
  localparam logic [27:0] WB_ROM  = 28'(WMAP_MAINDATA_BASE >> 4); // 0x0FF80000
  localparam logic [27:0] WB_VRAM = 28'(WMAP_VRAM_BASE     >> 4); // 0x0000000
  localparam logic [27:0] WB_PAL  = 28'(WMAP_PAL_BASE      >> 4); // 0x0188000
  localparam logic [27:0] WB_CMOS = 28'(WMAP_CMOS_BASE     >> 4); // 0x0140000
  localparam logic [27:0] WB_IO   = 28'(WMAP_IO_BASE       >> 4); // 0x0180000
  localparam logic [27:0] WB_SEC  = 28'(WMAP_SECURITY_BASE >> 4); // 0x0160000
  localparam logic [27:0] WB_GFX  = 28'(WMAP_GFX_BASE      >> 4); // 0x0200000
  // (ROM_PROG_OFF is now a module parameter — the wolf boot TB pins the umk3 layout.)

  // ---- Backing stores ---------------------------------------------------
`ifndef USE_EXT_ROM
  logic [15:0] rom  [0:ROM_WORDS-1];     // program ROM (externalized to SDRAM under USE_EXT_ROM)
`endif
  // ramstyle no_rw_check: infer M10K without read-during-write bypass. Required
  // for Quartus 17.0 to infer these as block RAM instead of register-exploding.
  //
  // *** AUDIT THIS PER ARRAY, NOT PER ATTRIBUTE (2026-07-27). ***
  // The original justification -- "the field engine never reads+writes the same
  // entry in one cycle" -- is an argument about THE DMA ONLY. It was TRUE when
  // written and has since been silently inherited by consumers it never
  // contemplated. That is a PROCESS defect, not just an RTL one: a justification
  // written against one port and never re-audited when a second port was added.
  // Gladiator's framing, and it is the transferable half -- audit as "LIST EVERY
  // PORT ON THIS ARRAY AND NAME THE ONE THE JUSTIFICATION COVERS", never as
  // `grep no_rw_check`, because the defect appears LATER in cores where the
  // attribute is currently correct.
  //
  // Status per array:
  //   ram   [:317] CPU/field engine only. Justification HOLDS.
  //   vram  [:320] compiled out under USE_SDRAM_VRAM / DDR3 VRAM builds; when
  //                present, audit the scanout port before trusting the hint.
  //   pal   [:325] JUSTIFICATION DOES NOT HOLD. Three consumers:
  //                  :820 port A writes pal[pal_aa] and reads pal[pal_aa] IN THE
  //                       SAME CYCLE (structural same-address RDW, not incidental)
  //                  :821 port B, identical shape
  //                  :593 async CPU read via read_word
  //                With no_rw_check the fitter may pick
  //                READ_DURING_WRITE_MODE_MIXED_PORTS = DONT_CARE, documented
  //                UNDEFINED, while Verilog models deterministic old-data -- so
  //                no bench here can exhibit it. See wolf_palram.sv, where the
  //                same defect on a cleaner 1W/1R array is already fixed.
  //   nvram [:369] CPU only. Justification HOLDS.
  //
  // NOT changed here yet, deliberately: `pal` has 3+ access points, so dropping
  // the hint can flip inference between M10K and registers, and that consequence
  // is only visible in a MAP report. Quartus is frozen -- do this as ONE change
  // with a build behind it, and check READ_DURING_WRITE_MODE_MIXED_PORTS for
  // this RAM in the report rather than assuming.
`ifndef USE_SDRAM_RAM
  (* ramstyle = "no_rw_check" *) logic [15:0] ram  [0:RAM_WORDS-1];  // main RAM in BRAM (moved to SDRAM under USE_SDRAM_RAM)
`endif
`ifndef USE_SDRAM_VRAM
  (* ramstyle = "no_rw_check" *) logic [15:0] vram [0:VRAM_WORDS-1]; // 512x512 {palette_hi, pixel_lo}
`endif
`ifndef YM_VRAM_HW
  logic [15:0] srt_fbuf [0:1023];    // SRT row-pair buffer (functional model, sim-only path)
`endif
  (* ramstyle = "no_rw_check" *) logic [15:0] pal  [0:PAL_WORDS-1];  // palette RAM (xRGB1555)
`ifndef USE_EXT_GFX
  logic  [7:0] gfx  [0:GFX_PIXELS-1];    // unpacked gfx ROM (1 byte/pixel, 6bpp); CPU window @0x02000000
`endif

  // Wolf video/control state (MAME midtunit_v.cpp midwunit_control_w:370 + vram_r/w).
  logic        videobank = 1'b0;         // CONTROL bit 11: 1 = pixel plane, 0 = palette-base plane
  logic  [1:0] gfxbank   = 2'd0;         // CONTROL bits 9:8: 8MB gfx quadrant (m_gfxbank_offset)
  logic [15:0] control_word = 16'd0;     // last CONTROL word (midwunit_control_r returns it)
  // MAME midwunit_m.cpp m_ioshuffle[16]. WWF writes selector 0..4 to
  // physical I/O offset 0; every selector first restores i%8, then overrides
  // five physical offsets. Keeping the literal table makes reads and writes
  // share exactly the same mapping.
  logic [2:0] ioshuffle [0:15];
  logic       wwf_io_shuffle_active;
  always_comb begin
    wwf_io_shuffle_active = WWF_IO_SHUFFLE;
    case (wwf_io_shuffle_i)
      1'b1:    wwf_io_shuffle_active = 1'b1;
      default: wwf_io_shuffle_active = WWF_IO_SHUFFLE;
    endcase
  end
  // CMOS one-shot write-enable latch: set by a write to CMOSEN (0x01480000,
  // cmos_enable_w), consumed by the next CMOS write (cmos_w). midwunit_m.cpp:26/32.
  logic        cmos_we   = 1'b0;
  logic        hw_cmos_write_ok = 1'b0;
  wire         nvram_ext_active = (nvram_ext_en === 1'b1);
  wire         nvram_ext_write = nvram_ext_active &&
                                  (nvram_ext_wr === 1'b1) &&
                                  (nvram_ext_addr < (CMOS_WORDS * 2));
  assign gfxbank_o = gfxbank;
  // Autoerase: T/Wolf video has NO autoerase_line (midtunit_v.cpp) — this stays 0
  // FOREVER so the retained (Y-unit) autoerase engine never triggers. The frame
  // buffer is cleared by explicit DMA fills. Kept only to preserve the VRAM engine.
  logic        autoerase = 1'b0;         // (never set on Wolf)

  // Autoerase engine state (see the erase engine block in the clocked process).
  logic        er_run  = 1'b0;           // sweep in progress
  logic  [8:0] er_row;                   // current target row (mod 512)
  logic  [8:0] er_x;                     // column within the row
  logic  [9:0] er_left;                  // rows remaining (incl. current)
`ifndef USE_SDRAM_VRAM
  assign erase_busy = er_run;            // (SDRAM path: vram_sdram_top drives erase_busy)
`endif
  (* ramstyle = "no_rw_check" *) logic [15:0] nvram [0:CMOS_WORDS-1]; // battery NVRAM
`ifndef SYNTHESIS
  // sim-only preload; in synthesis the arrays init to 0 (BRAM) and ROMs load via
  // the framework ioctl download (Phase 6 W5). Quartus can't run the big for-loops
  // (>5000 iters) or $readmemh with sim paths, so guard the whole block out.
  initial begin
    // sim-only preload; ROM_HEX is generated from the user's ROM (see sim/).
    // Zero the writable stores so words the TB hasn't written read back as 0, not
    // X — matching sim_memory_model. (Uninitialized X in an unread window word
    // otherwise X-propagates through the shift/mask under Icarus.)
`ifndef USE_SDRAM_RAM
    for (int i = 0; i < RAM_WORDS;  i++) ram[i]  = 16'h0000;  // (SDRAM RAM: the TB preloads its sdram_model; 0 by default)
`endif
`ifndef USE_SDRAM_VRAM
    for (int i = 0; i < VRAM_WORDS; i++) vram[i] = 16'h0000;
`endif
`ifndef YM_VRAM_HW
    for (int i = 0; i < 1024; i++) srt_fbuf[i] = 16'h0000;
`endif
    for (int i = 0; i < PAL_WORDS;  i++) pal[i]  = 16'h0000;
    for (int i = 0; i < CMOS_WORDS; i++) nvram[i] = 16'h0000;
`ifdef WOLF_CMOS_SEED
    // SIM-ONLY warm-CMOS seed: overrides the zero-init above with a captured MAME
    // battery image so the boot leaves the virgin-CMOS io-poll and blits a real
    // frame. Macro-gated OFF by default -> changes NO default init and NO HW/RTL
    // behavior (the fresh-CMOS PC-diff boot gate stays byte-identical). Guarded
    // exactly like GFX_HEX below. On HW this same BRAM is filled by hps_io nvram
    // persistence (Phase 6), not $readmemh. Packing: CMOS word i = {8'h00, byte},
    // one byte-valued MAME m_nvram entry per word (midwunit_m.cpp:48 cmos_r ->
    // m_nvram[offset]; make_cmos_hex.py).
    $readmemh(CMOS_HEX, nvram);
`endif
`ifdef WOLF_NEARBLIT_SEED
    // SIM-ONLY NEAR-BLIT seed: overwrite the 4 writable stores with MAME's state
    // captured ~936k cyc BEFORE the first factory-init blit (nearblit_dump.lua at
    // cyc~166.3M). With the CPU regfile/PC/ST force in the TB, this lets the boot
    // run ONLY the ~2M-cycle tail to the blit instead of the forbidden 167M grind.
    // Macro-gated OFF by default -> changes NO default init, NO HW/RTL behavior
    // (fresh-CMOS PC-diff gate stays byte-identical). On HW these BRAMs fill via
    // hps_io nvram + the running boot, never $readmemh.
    // Packing (nearblit_dump.lua: read_u16(base + i*16), one 34010 word per line):
    //   RAM  : ram[i]  = word i           (direct; wolf_mem ram[rel] is the 16b word)
    //   PAL  : pal[i]  = word i           (direct; pal[rel] direct)
    //   CMOS : nvram[i]= {8'h00, byte}    (cmos.hex lines are 00xx; direct)
    //   VRAM : MAME midtunit_vram_r(offset*=2) videobank=1 returns
    //          {vram[2i+1][7:0], vram[2i][7:0]} == wolf_mem's R_VRAM decode
    //          (wolf_mem.sv:404). So split each dumped word across two entries'
    //          LOW bytes: vram[2i]=word[7:0], vram[2i+1]=word[15:8]. High bytes
    //          (palette plane) are unrecoverable from the videobank=1 dump -> 0;
    //          the factory-init blit WRITES vram, it does not read the hi plane.
    begin
      integer nb_i;
`ifndef USE_SDRAM_RAM
      $readmemh(NB_RAM_HEX,  ram);   // (SDRAM RAM: seed the TB's sdram_model instead)
`endif
      $readmemh(NB_PAL_HEX,  pal);
      $readmemh(NB_CMOS_HEX, nvram);
`ifndef USE_SDRAM_VRAM
      begin
        // temp holds the dumped 34010 words; split into the two byte-lane entries.
        logic [15:0] nb_vram_tmp [0:(VRAM_WORDS/2)-1];
        for (nb_i = 0; nb_i < VRAM_WORDS/2; nb_i++) nb_vram_tmp[nb_i] = 16'h0000;
        $readmemh(NB_VRAM_HEX, nb_vram_tmp);
        for (nb_i = 0; nb_i < VRAM_WORDS/2; nb_i++) begin
          vram[(nb_i<<1)]     = {8'h00, nb_vram_tmp[nb_i][7:0]};
          vram[(nb_i<<1)+1]   = {8'h00, nb_vram_tmp[nb_i][15:8]};
        end
      end
`endif
    end
`endif
`ifndef USE_EXT_ROM
    $readmemh(ROM_HEX, rom);
`endif
`ifndef USE_EXT_GFX
    for (int i = 0; i < GFX_PIXELS; i++) gfx[i]  = 8'h00;
    $readmemh(GFX_HEX, gfx);   // unpacked gfx ROM; harmless no-op if the file is absent
`endif
  end
`endif

  // ---- Request latch / FSM ---------------------------------------------
  // FSM states (plain localparams so guarded extra states compose cleanly):
  //  M_IDLE/M_ACK    : always. M_GFX : external gfx/rom fetch (YM_EXT_RD).
  //  M_HR1/M_HR2/M_HW2 : clocked-BRAM window read / 3rd-word / 3rd-word-write
  //                      for the CPU field engine (USE_HW_RAM / USE_HW_VRAM).
  localparam logic [4:0] M_IDLE=5'd0, M_ACK=5'd1, M_GFX=5'd2,
                         M_HR1=5'd3, M_HR2=5'd4, M_HFIN=5'd5, M_HW2=5'd6,
                         // VRAM clocked BRAM engine (USE_HW_VRAM)
                         M_VRD=5'd7, M_VWR0=5'd8, M_VWR1=5'd9, M_VWW0=5'd10, M_VWW1=5'd11,
                         // VRAM SDRAM engine (USE_SDRAM_VRAM): pulse req -> wait done
                         M_VSD=5'd12,
                         // RAM SDRAM engine (USE_SDRAM_RAM): pulse req -> wait done (mirrors M_VSD)
                         M_RSD=5'd15,
                         // field-engine merge/extract pipeline stage (timing closure @96 MHz)
                         M_HFIN2=5'd13,
                         // non-BRAM (INPUT/PROT/CTRL) read extract pipeline stage
                         M_RDLY=5'd14,
                         // registered external-byte window -> field extract
                         M_GFIN=5'd16,
                         // SRT sideband engines (P0027 Phase 2):
                         //   M_SRB  = sequential 1024-entry latch/transfer over the
                         //            2-port BRAM VRAM (USE_HW_VRAM)
                         //   M_SRTD = DDR3 D-lane op in flight (USE_DDR3_VRAM)
                         M_SRB=5'd17, M_SRTD=5'd18;
  logic [4:0] state;
`ifdef YM_EXT_RD
  logic [25:0] gfx_base;      // current external byte cursor (advanced only after ACK)
  logic [2:0]  gfx_cnt;       // current byte in the 1..6-byte field window
  logic [2:0]  gfx_last;      // final byte needed by {boff,size}
  logic [47:0] gfx_win;       // little-endian fetched bytes; unused high bytes stay zero
  logic [47:0] gfx_win_with_byte;
  // SDRAM byte layout: gfx region @ 0, program ROM region @ SDRAM_ROMB.
  localparam logic [25:0] SDRAM_ROMB = 26'(GFX_PIXELS);   // = gfx byte size (0x180000)

  // Insert the just-returned byte before testing for completion. Keeping this
  // explicit avoids a variable part-select on the external-ROM timing path.
  always_comb begin
    gfx_win_with_byte = gfx_win;
    case (gfx_cnt)
      3'd0: gfx_win_with_byte[ 7: 0] = gfx_rdata;
      3'd1: gfx_win_with_byte[15: 8] = gfx_rdata;
      3'd2: gfx_win_with_byte[23:16] = gfx_rdata;
      3'd3: gfx_win_with_byte[31:24] = gfx_rdata;
      3'd4: gfx_win_with_byte[39:32] = gfx_rdata;
      3'd5: gfx_win_with_byte[47:40] = gfx_rdata;
      default: ;
    endcase
  end
`endif

  logic [31:0] a_q;
  logic        we_q;
  logic [31:0] wd_q;
  logic  [5:0] sz_q;
  logic        srt_q;    // SRT sideband qualifier, latched with the request (P0027)

  // region + geometry from the latched address
  wire [27:0] widx  = a_q[31:4];
  wire  [3:0] boff  = a_q[3:0];
  wire  [5:0] sz    = sz_q;

  logic [3:0] region;
  always_comb begin
    // Decode on high bits of the bit-address. Several Wolf regions share a
    // top-12-bit megabyte -> an a_q[19] sub-decode splits the low/high half
    // (a_q[19:16] = 0x0..7 vs 0x8..F). See WOLF_MEM_PLAN.md §1.
    unique casez (a_q[31:20])
      12'h000,12'h001,12'h002,12'h003: region = R_VRAM;    // 0x00000000-0x003FFFFF (4MB)
      12'h010,12'h011,12'h012,12'h013: region = R_RAM;     // 0x01000000-0x013FFFFF (4MB)
      12'h014: region = a_q[19] ? R_CMOSEN : R_CMOS;       // 0x0140 CMOS / 0x0148 CMOSEN
      12'h016: region = a_q[19] ? R_SOUND  : R_SECURITY;   // 0x0160 SECURITY / 0x0168 SOUND
      12'h018: region = a_q[19] ? R_PAL    : R_IO;         // 0x0180 IO / 0x0188 PAL
      12'h01a: region = R_DMA;                             // 0x01A00000 (+mirror 0x01A80000, both 0x01a)
      12'h01b: region = R_CTRL;                            // 0x01B00000
      12'h02?,12'h03?,12'h04?,12'h05?,12'h06?:
               region = R_GFX;                             // 0x02000000-0x06FFFFFF (32MB)
      12'hff8,12'hff9,12'hffa,12'hffb,12'hffc,12'hffd,12'hffe,12'hfff:
               region = R_ROM;                             // 0xFF800000-0xFFFFFFFF
      default: region = R_NONE;
    endcase
  end

  // VRAM is a HW backend region (USE_HW_VRAM BRAM or USE_SDRAM_VRAM): the M_ACK FSM diverts
  // R_VRAM accesses to the selected engine. (Declared AFTER `region` — Questa requires
  // declaration-before-use for the continuous-assign reference.)
`ifdef YM_VRAM_HW
  wire is_hwvram = (region == R_VRAM);
`else
  wire is_hwvram = 1'b0;
`endif
`ifdef USE_SDRAM_RAM
  wire is_sdram_ram = (region == R_RAM);   // main RAM in SDRAM -> divert R_RAM to ram_sdram
`else
  wire is_sdram_ram = 1'b0;
`endif

  // ---- SRT sideband geometry (P0027 Phase 2; see the mem_srt port contract) ----
  // Entry base = 2 * (bit_addr >> 4) = widx << 1 (one CPU word = entries 2W, 2W+1).
  wire [28:0] srt_base = {widx, 1'b0};

  // Read one word from the selected region at global word index gw (backed
  // regions only; others / OOB return 0). Function form (continuous-assign
  // call) — inlining these array reads into an always_comb makes iverilog
  // build a huge structure over the 0x20000-word ROM and hang. This is the
  // functional model; the HW controller replaces it in Phase 6.
  localparam logic [27:0] ROMW  = ROM_WORDS[27:0];
  localparam logic [27:0] RAMW  = RAM_WORDS[27:0];
  localparam logic [27:0] VRAMW = VRAM_WORDS[27:0];
  localparam logic [27:0] PALW  = PAL_WORDS[27:0];
  localparam logic [27:0] CMOSW = CMOS_WORDS[27:0];
  localparam logic [27:0] GFXPIXW = GFX_PIXELS[27:0];

  function automatic logic [15:0] read_word(input logic [3:0] rgn, input logic [27:0] gw);
    logic [27:0] rel;
    begin
      read_word = 16'h0000;
      if (rgn == R_ROM) begin
`ifndef USE_EXT_ROM
        rel = gw - WB_ROM;                           // region-relative word
        if (rel >= ROM_PROG_OFF && (rel - ROM_PROG_OFF) < ROMW)
          read_word = rom[rel - ROM_PROG_OFF];
`endif
        // USE_EXT_ROM: in-range R_ROM reads are served by the M_GFX external fetch;
        // out-of-range reads fall here and return 0 (matches the internal array).
      end else if (rgn == R_RAM) begin
`ifndef USE_HW_RAM
`ifndef USE_SDRAM_RAM
        rel = gw - WB_RAM;   if (rel < RAMW)  read_word = ram[rel];  // (SDRAM RAM: diverted to ram_sdram)
`endif
`endif
      end else if (rgn == R_VRAM) begin
`ifndef YM_VRAM_HW
        // MAME vram_r: each 34010 word offset -> 2 pixels; byte-lane per videobank.
        rel = gw - WB_VRAM;                        // 34010 VRAM word offset
        if (((rel << 1) + 28'd1) < VRAMW) begin
          if (videobank)                           // pixel plane: the two pixel low-bytes
            read_word = {vram[(rel<<1)+1][7:0], vram[rel<<1][7:0]};
          else                                     // palette-base plane: the two high-bytes
            read_word = {vram[(rel<<1)+1][15:8], vram[rel<<1][15:8]};
        end
`endif
      end else if (rgn == R_PAL) begin
`ifndef USE_HW_RAM
        rel = gw - WB_PAL;   if (rel < PALW)  read_word = pal[rel];
`endif
      end else if (rgn == R_CMOS) begin
`ifndef USE_HW_RAM
        // FLAT nvram[rel] (Wolf drops Y-unit paging). midwunit_m.cpp:48 cmos_r.
        rel = gw - WB_CMOS;  if (rel < CMOSW) read_word = nvram[rel];
`endif
      end else if (rgn == R_IO) begin
        // MAME io_r (midwunit_m.cpp:105-116): offset = ioshuffle[off%16]; umk3 default
        // ioshuffle[i]=i%8 -> s = (off%16)%8 = off[2:0]. Ports 0-3 = m_ports[0..3];
        // case 4 = (pic_status<<12) | dcs.control_r(); else = ~0. Boot-poll region.
        //
        // WOLF PORT ORDER (fork bug fix): m_ports = { "IN0", "IN1", "DSW", "IN2" }
        // (midwunit.h:35, required_ioport_array<4> :82) -> case2 = DSW, case3 = IN2.
        // The donor Y/T-unit order (yunit_mem.sv:380-381; midtunit PORT order
        // IN0/IN1/IN2/DSW) had case2=IN2/case3=DSW — inherited-enum-ordering fork
        // bug. Five-way trace proof (mame-gospel/trace/
        // exp2b_iobreak.txt:2-6): idle reads 0187FF80->FFFF(IN0) FF90->FFFF(IN1)
        // FFA0->FD7D(DSW live value, case 2!) FFB0->FFFF(IN2, all IP_ACTIVE_LOW
        // inactive) FFC0->1C00(case4). Serving the in2 tie at case2 made the game's
        // DSW read @0x0187FFA0 see 0xFFFF -> bit9 "Powerup Test"=ON (midwunit.cpp:
        // 197-199, default Off) -> the FFBA2200 JANE gate (trace/ffba20xx.txt:6-9)
        // fell into the DIP-gated power-up self-test leg @FFBA6xxx that MAME never
        // runs = the cab's endless gfx-window-read / zero-blit black-screen loop.
        // The `inputs` bus packing is {DSW, IN2, IN1, IN0} (wolf_top.sv:56).
        rel = gw - WB_IO;
        case (wwf_io_shuffle_active ? ioshuffle[rel[3:0]] : rel[2:0])
          3'd0: read_word = inputs[15:0];    // IN0 (m_ports[0])
          3'd1: read_word = inputs[31:16];   // IN1 (m_ports[1])
          3'd2: read_word = inputs[63:48];   // DSW (m_ports[2], midwunit.h:35)
          3'd3: read_word = inputs[47:32];   // IN2 (m_ports[3], midwunit.h:35)
          3'd4: read_word = {pic_status, 12'd0} | snd_stat; // status word (io_r case 4)
          default: read_word = 16'hFFFF;     // cases 5-7 = ~0
        endcase
      end else if (rgn == R_SECURITY) begin
        // security_r (midwunit_m.cpp:338) = pic.read() (byte). Stub for bring-up.
        read_word = {8'h00, pic_rdata};
      end else if (rgn == R_SOUND) begin
        // sound_r (midwunit_m.cpp:364) = dcs.data_r() & 0xff.
        read_word = {8'h00, snd_rdata};
      end else if (rgn == R_CTRL) begin
        // midwunit_control_r (midtunit_v.cpp:388) = m_midtunit_control.
        read_word = control_word;
      end else if (rgn == R_GFX) begin
        // MAME gfxrom_r (midyunit_v.cpp:116): offset*=2 (word->byte-pair);
        // return gfx[2*rel] | gfx[2*rel+1]<<8. Unpacked 1 byte/pixel.
        rel = gw - WB_GFX;
`ifndef USE_EXT_GFX
        if (((rel << 1) + 28'd1) < GFXPIXW)
          read_word = {gfx[(rel << 1) + 28'd1], gfx[rel << 1]};
`endif
        // USE_EXT_GFX: R_GFX reads are served by the M_GFX external fetch (below),
        // not read_word — this returns 0 and is never used for R_GFX.
      end
    end
  endfunction

  // Field masks (no array dependency -> safe as continuous assigns).
  wire [47:0] rmask = (48'd1 << sz) - 48'd1;         // sz low bits
  wire [47:0] smask = rmask << boff;                 // field in place
  wire [5:0]  lastb = boff + sz - 6'd1;              // top bit (<=46)

  // SRT latch-ack rdata (A0033): the normal CPU-visible word read at mem_addr, formed
  // from the two base entries' videobank byte lane and field-extracted like a read.
  // (MAME returns m_shiftreg[0]; the game discards the PIXT result — either is safe,
  // this choice keeps the ack self-consistent with vram_r. Bits beyond the base word
  // extract as 0 — a >16-bit SRT pixel read never occurs in the game.)
  function automatic logic [31:0] srt_rdata_f(input logic [15:0] e0, input logic [15:0] e1);
    logic [15:0] w;
    begin
      w = videobank ? {e1[7:0], e0[7:0]} : {e1[15:8], e0[15:8]};
      srt_rdata_f = 32'((({32'h0, w} >> boff) & rmask));
    end
  endfunction
`ifdef YM_EXT_RD
  assign gfx_raddr = gfx_base;                     // registered current fetch byte address
  // Select which (if any) read-only region routes through the external fetch, and
  // its SDRAM byte base. R_GFX: gfx region @0. R_ROM: program ROM @SDRAM_ROMB, and
  // ONLY within the populated program range (out-of-range ROM reads fall through
  // to the normal path -> read_word()=0, byte-identical to the internal array).
  logic        ext_fetch;
  logic [25:0] ext_base;
  logic [27:0] rom_rel;
  always_comb begin
    ext_fetch = 1'b0;
    ext_base  = 26'd0;
    rom_rel   = widx - WB_ROM;
  `ifdef USE_EXT_GFX
    if (region == R_GFX && !we_q) begin
      ext_fetch = 1'b1;
  `ifdef USE_DDR3_GFX
      // gfxbank (CONTROL bits 9:8, captured below) offsets the CPU gfx window by
      // 0x800000 * bank — midwunit_gfxrom_r (midtunit_v.cpp:244-248) reads
      // &m_gfxrom[m_gfxbank_offset[0]] and midwunit_control_w (midtunit_v.cpp:381)
      // sets m_gfxbank_offset[0] = 0x800000 * ((control >> 8) & 3). The blitter's
      // own gfxoffset reads are bank-INDEPENDENT (dma_w never touches it) — bank
      // applies to THIS window only. NBA DIAG.ASM's IROMCHIPS1/2_8MEG checksum
      // passes bank 1/2 through SYSCTRL ori 0100h/0200h — the exact consumer.
      // Gated: the legacy SDRAM gfx stub (0x180000, no banks) stays bit-identical.
      ext_base  = {gfxbank, 23'd0} + 26'((widx - WB_GFX) << 1);
  `else
      ext_base  = 26'((widx - WB_GFX) << 1);
  `endif
    end
  `endif
  `ifdef USE_EXT_ROM
    if (region == R_ROM && !we_q &&
        rom_rel >= ROM_PROG_OFF && (rom_rel - ROM_PROG_OFF) < ROMW) begin
      ext_fetch = 1'b1;
      ext_base  = SDRAM_ROMB + 26'((rom_rel - ROM_PROG_OFF) << 1);
    end
  `endif
  end
`endif

`ifdef USE_HW_RAM
  // ---- Phase 6 W1c: clocked BRAM field engine for RAM / PAL / CMOS -----------
  // The functional model reads a combinational 3-word window (3+ async reads per
  // access) — un-inferrable as BRAM (register-explodes: yunit_mem alone >18 GB in
  // quartus_map). Here RAM/PAL/CMOS become true-dual-port synchronous BRAMs, and
  // the CPU field access runs a multi-cycle window RMW over the two ports. The
  // field MATH is unchanged (same win/merge as read_word/merged_s) — only how the
  // window is FILLED changes (combinational -> clocked). Reads: 3 wait cycles;
  // writes: 3-4. The req/ack handshake absorbs the latency. VRAM is separate
  // (USE_HW_VRAM). Access distribution measured in tb_yunit_frame (MEASURE_ACCESS).
  // Decode these physical RAM selects directly from the latched bit address.
  // Routing them through the encoded region adds encode/decode logic before
  // the BRAM bank address. Keep all index/default/bounds equations unchanged.
  logic is_hwram;                     // region uses this engine (RAM/PAL/CMOS)
  logic [1:0]  hsel;                  // 0=ram 1=pal 2=cmos (routes ports/q)
  logic [17:0] hidx [0:2];            // per-window-word array index (region-relative/paged)
  logic        hval [0:2];            // per-word in-range validity
  logic [27:0] hr;                    // per-word region-relative index (comb temp)
  always_comb begin
    is_hwram = 1'b0; hsel = 2'd0; hr = 28'd0;
    for (int j=0;j<3;j++) begin hidx[j]=18'd0; hval[j]=1'b0; end
    if (a_q[31:22] == 10'h004) begin
`ifndef USE_SDRAM_RAM
      is_hwram=1'b1; hsel=2'd0;
      for (int j=0;j<3;j++) begin
        hr = (widx + j[27:0]) - WB_RAM;
        hidx[j]=hr[17:0]; hval[j]=(hr < RAMW);
      end
`endif
      // USE_SDRAM_RAM: R_RAM diverts to ram_sdram (is_sdram_ram) BEFORE the is_hwram engine,
      // so is_hwram stays 0 here (default) and the BRAM path is bypassed for main RAM.
    end else if (a_q[31:19] == 13'h031) begin
      is_hwram=1'b1; hsel=2'd1;
      for (int j=0;j<3;j++) begin
        hr = (widx + j[27:0]) - WB_PAL;
        hidx[j]=hr[17:0]; hval[j]=(hr < PALW);
      end
    end else if (a_q[31:19] == 13'h028) begin
      is_hwram=1'b1; hsel=2'd2;
      for (int j=0;j<3;j++) begin
        hr = (widx + j[27:0]) - WB_CMOS;
        hidx[j]=hr[17:0];                        // FLAT index (Wolf drops Y-unit CMOS paging)
        hval[j]=(hr < CMOSW);
      end
    end
  end

  // captured window words + combinational window/merge (rd* are registered).
  logic [15:0] rd0, rd1, rd2;
  wire  [47:0] hwin    = {hval[2]?rd2:16'h0, hval[1]?rd1:16'h0, hval[0]?rd0:16'h0};
  wire  [47:0] hmerged = (hwin & ~smask) | (({16'h0, wd_q} << boff) & smask);

  // ---- merge/extract PIPELINE (timing closure @96 MHz) ------------------------
  // a_q -> region decode + hidx adder + hval compare + the boff/sz shifts (smask,
  // wd_q<<boff) is ~12 ns combinational. The shifts are a_q/wd_q-derived and settle
  // by M_ACK (3 cyc before use), but STA still sees a_q -> merge -> BRAM/mem_rdata/
  // palv as ONE cycle. Register the settled a_q-derived masks + the read window, then
  // do the merge/extract from registered values in a new M_HFIN2 stage. Same VALUES,
  // one cycle later (the CPU is 24 MHz + latency-tolerant via yunit_mem_cdc).
  logic [47:0] smask_q, rmask_q, wsh_q, hwin_q;   // wsh_q = {16'h0,wd_q} << boff
  logic [3:0]  boff_q;
  // Writeback occurs only in M_HFIN2/M_HW2, after the address has stayed
  // fixed through M_ACK, M_HR1, M_HR2 and M_HFIN. Sample its write decode
  // alongside the existing merge operands, removing address arithmetic
  // from the memory write-enable path without changing any transaction.
  logic [1:0] hwrite_sel_q;
  logic [2:0] hwrite_valid_q;
  always @(posedge clk) begin
    smask_q <= smask; rmask_q <= rmask; boff_q <= boff;
    hwrite_sel_q <= hsel;
    hwrite_valid_q <= {hval[2], hval[1], hval[0]};
    wsh_q   <= ({16'h0, wd_q} << boff);
    hwin_q  <= hwin;                              // valid from M_HFIN (rd* captured by M_HR2)
  end
  wire  [47:0] hmerged2 = (hwin_q & ~smask_q) | (wsh_q & smask_q);

  // shared engine ports (routed to the active array by hsel below).
  logic [17:0] eng_aa, eng_ba;  logic eng_awe, eng_bwe;  logic [15:0] eng_awd, eng_bwd;
  logic [15:0] eng_aq, eng_bq;
  // combinational engine port control by state (1-cycle BRAM read latency).
  always_comb begin
    eng_aa=hidx[0]; eng_ba=hidx[1]; eng_awe=1'b0; eng_bwe=1'b0;
    eng_awd=hmerged2[15:0]; eng_bwd=hmerged2[31:16];   // pipelined merge
    case (state)
      M_HR1: eng_aa=hidx[2];                          // pre-issue w2 read
      M_HFIN2: if (we_q) begin                        // write-back w0,w1 (pipelined stage)
               eng_aa=hidx[0]; eng_awe=hwrite_valid_q[0];
               eng_ba=hidx[1]; eng_bwe=(lastb>=6'd16)&hwrite_valid_q[1];
             end
      M_HW2: begin eng_aa=hidx[2]; eng_awe=(lastb>=6'd32)&hwrite_valid_q[2]; eng_awd=hmerged2[47:32]; end
      default: ;                                      // M_ACK/M_HR2: read w0,w1 (defaults)
    endcase
  end

  // true-dual-port BRAMs (Quartus infers M10K). Plain always @posedge so the sim
  // `initial` preload can also drive the arrays (same reason as the functional path).
  logic [17:0] ram_aa,ram_ba; logic ram_awe,ram_bwe; logic [15:0] ram_awd,ram_bwd,ram_aq,ram_bq;
  logic [14:0] pal_aa,pal_ba; logic pal_awe,pal_bwe; logic [15:0] pal_awd,pal_bwd,pal_aq,pal_bq;
  logic [14:0] nv_aa, nv_ba;  logic nv_awe, nv_bwe;  logic [15:0] nv_awd, nv_bwd, nv_aq, nv_bq;
  logic        nvram_ext_lane_q;
  always_comb begin
    // route shared engine ports to the selected array; deselected arrays idle.
    ram_aa=eng_aa[17:0]; ram_ba=eng_ba[17:0]; ram_awd=eng_awd; ram_bwd=eng_bwd;
    pal_aa=eng_aa[14:0]; pal_ba=eng_ba[14:0]; pal_awd=eng_awd; pal_bwd=eng_bwd;
    // CMOS base is aligned on 0x8000 words. Only the low word address
    // reaches this RAM; avoid routing the unrelated region decode through
    // the physical bank write-enable. Unselected port-A reads are not used.
    nv_aa = widx[14:0] + (((state==M_HR1)||(state==M_HW2)) ? 15'd2 : 15'd0);
    // All three engine region bases are aligned to 0x8000 words. Compute
    // the low second-word address before selecting an enabled region. The
    // zero default also preserves unselected external-port residual reads.
    nv_ba = nvram_ext_active ? nvram_ext_addr[15:1]
                             : (is_hwram ? (widx[14:0] + 15'd1) : 15'd0);
    nv_awd=eng_awd; nv_bwd=eng_bwd;
    ram_awe=(hwrite_sel_q==2'd0)&eng_awe; ram_bwe=(hwrite_sel_q==2'd0)&eng_bwe;
    pal_awe=(hwrite_sel_q==2'd1)&eng_awe; pal_bwe=(hwrite_sel_q==2'd1)&eng_bwe;
    // CMOS writes are one-shot gated by CMOSEN. Reads always remain available.
    nv_awe =(hwrite_sel_q==2'd2)&eng_awe&hw_cmos_write_ok;
    nv_bwe =(hwrite_sel_q==2'd2)&eng_bwe&hw_cmos_write_ok;
    eng_aq = (hsel==2'd0)?ram_aq : (hsel==2'd1)?pal_aq : nv_aq;
    eng_bq = (hsel==2'd0)?ram_bq : (hsel==2'd1)?pal_bq : nv_bq;
  end
  // ONE always block per port (canonical Quartus true-dual-port template — a
  // single block driving both ports does NOT infer M10K in Quartus 17.0).
`ifndef USE_SDRAM_RAM
  always @(posedge clk) begin if (ram_awe) ram[ram_aa]  <= ram_awd;  ram_aq <= ram[ram_aa];  end
  always @(posedge clk) begin if (ram_bwe) ram[ram_ba]  <= ram_bwd;  ram_bq <= ram[ram_ba];  end
`else
  assign ram_aq = 16'h0; assign ram_bq = 16'h0;   // main RAM in SDRAM: BRAM engine's ram port unused (R_RAM diverts to ram_sdram before is_hwram)
`endif
  always @(posedge clk) begin if (pal_awe) pal[pal_aa]  <= pal_awd;  pal_aq <= pal[pal_aa];  end
  always @(posedge clk) begin if (pal_bwe) pal[pal_ba]  <= pal_bwd;  pal_bq <= pal[pal_ba];  end
  always @(posedge clk) begin if (nv_awe)  nvram[nv_aa] <= nv_awd;   nv_aq  <= nvram[nv_aa]; end
  always @(posedge clk) begin
    if (nvram_ext_active) begin
      if (nvram_ext_write) begin
        if (nvram_ext_addr[0]) nvram[nv_ba][15:8] <= nvram_ext_wdata;
        else                   nvram[nv_ba][7:0]  <= nvram_ext_wdata;
      end
      nv_bq <= nvram[nv_ba];
      nvram_ext_lane_q <= nvram_ext_addr[0];
    end else begin
      if (nv_bwe) nvram[nv_ba] <= nv_bwd;
      nv_bq <= nvram[nv_ba];
    end
  end
  assign nvram_ext_rdata = nvram_ext_lane_q ? nv_bq[15:8] : nv_bq[7:0];

  // W3: tap palette writes for the video scanout mirror (pal_awe/pal_bwe already
  // include the hsel==PAL select, so they pulse only on real palette writes).
  // REGISTERED (timing closure): the address-decode -> tap -> yunit_palram FIFO
  // combinational chain missed 96 MHz; a 1-cycle pipeline breaks it. The mirror
  // lags pal[] by one clk — invisible (palette writes are sparse; the video reads
  // the mirror much later).
  always @(posedge clk) begin
    palv_we_a <= pal_awe;  palv_aa <= pal_aa;  palv_awd <= pal_awd;
    palv_we_b <= pal_bwe;  palv_ba <= pal_ba;  palv_bwd <= pal_bwd;
  end
`else
  wire is_hwram = 1'b0;   // engine disabled: all regions use the functional path
  always_comb begin
    if (nvram_ext_addr < (CMOS_WORDS * 2))
      nvram_ext_rdata = nvram_ext_addr[0]
                       ? nvram[nvram_ext_addr[15:1]][15:8]
                       : nvram[nvram_ext_addr[15:1]][7:0];
    else nvram_ext_rdata = 8'h00;
  end
`endif

`ifdef USE_HW_VRAM
  // ---- Phase 6 W1c: clocked 2-port BRAM VRAM engine + accessor arbiter --------
  // VRAM (512x512, 16b/pixel {palette_hi, pixel_lo}) has 4 accessors: CPU field
  // read/write (byte-lane, videobank plane select), blitter fb_we write, and the
  // autoerase row-copy. They map onto ONE true-dual-port BRAM via a priority
  // arbiter: CPU field access > fb_we > autoerase (the accessors are time-disjoint
  // in practice — the CPU polls, not draws, during blits; autoerase is post-
  // scanout; verified by the byte-identical frame gate). Reads never straddle
  // (measured) -> 1 word = 2 entries. Video scanout (W3) will add a read port.
  // (is_hwvram is defined once above, shared by both HW backends.)
  logic [18:0] va_addr, vb_addr;  logic va_we, vb_we;  logic [15:0] va_wd, vb_wd, va_q, vb_q;

  // CPU VRAM entry geometry (WB_VRAM=0). e0/e1 = word widx; e2/e3 = word widx+1.
  wire [17:0] ve0 = (widx << 1);              wire [17:0] ve1 = (widx << 1) + 18'd1;
  wire [17:0] ve2 = ((widx+28'd1) << 1);      wire [17:0] ve3 = ((widx+28'd1) << 1) + 18'd1;
  wire [18:0] vea = (widx << 1) + {18'd0, boff[3]};   // sz<=8 single-pixel entry
  wire v01 = (((widx<<1)+28'd1) < VRAMW);
  wire v23 = ((((widx+28'd1)<<1)+28'd1) < VRAMW);
  wire vea_v = ((widx<<1)+{27'd0,boff[3]}) < VRAMW;
  // captured old entry values (for the non-videobank low-byte-preserve RMW)
  logic [15:0] o0, o1, o2, o3;
  wire [7:0] oea = boff[3] ? o1[7:0] : o0[7:0];
  // merged new entry values (exact copies of the functional vram_w byte-lane math)
  wire [15:0] vnew0  = videobank ? {dma_palette[7:0],  wd_q[7:0]}   : {wd_q[7:0],   o0[7:0]};
  wire [15:0] vnew1  = videobank ? {dma_palette[15:8], wd_q[15:8]}  : {wd_q[15:8],  o1[7:0]};
  wire [15:0] vnew2  = videobank ? {dma_palette[7:0],  wd_q[23:16]} : {wd_q[23:16], o2[7:0]};
  wire [15:0] vnew3  = videobank ? {dma_palette[15:8], wd_q[31:24]} : {wd_q[31:24], o3[7:0]};
  wire [15:0] vnewea = videobank ? {(boff[3]?dma_palette[15:8]:dma_palette[7:0]), wd_q[7:0]}
                                 : {wd_q[7:0], oea};
  // CPU field read: form the 16-bit word from the two entries' selected byte lane.
  wire [15:0] vword = videobank ? {vb_q[7:0], va_q[7:0]} : {vb_q[15:8], va_q[15:8]};

  // CPU port requests (combinational by state); cpu owns the ports when active.
  wire cpu_vram_active = ((state==M_ACK) & is_hwvram) |
                         (state==M_VRD) | (state==M_VWR0) | (state==M_VWR1) |
                         (state==M_VWW0) | (state==M_VWW1);
  logic [17:0] cv_aa, cv_ba;  logic cv_awe, cv_bwe;  logic [15:0] cv_awd, cv_bwd;
  always_comb begin
    cv_aa=ve0; cv_ba=ve1; cv_awe=1'b0; cv_bwe=1'b0; cv_awd=vnew0; cv_bwd=vnew1;
    case (state)
      M_VWR0: if (sz_q > 6'd16) begin cv_aa=ve2; cv_ba=ve3; end    // issue e2/e3 read
      M_VWW0: if (sz_q <= 6'd8) begin cv_aa=vea; cv_awe=vea_v; cv_awd=vnewea; end
              else begin cv_awe=v01; cv_awd=vnew0; cv_bwe=v01; cv_bwd=vnew1; end
      M_VWW1: begin cv_aa=ve2; cv_ba=ve3; cv_awe=v23; cv_awd=vnew2; cv_bwe=v23; cv_bwd=vnew3; end
      default: ;                                                   // M_ACK/M_VRD/M_VWR1: read e0/e1
    endcase
  end

  // autoerase 3-cycle engine (ER0 issue-read -> ER0b capture src -> ER2 write).
  // Advances only on grant (paused while CPU/fb_we own the ports); the ER0b
  // capture is unconditional (va_q one cycle after ER0's read == src, whoever
  // addresses the port that cycle). src row = 510|parity; rows 510/511 not erased.
  logic [1:0]  er_ph;           // 0=ER0(read) 1=ER0b(capture) 2=ER2(write)
  logic [15:0] er_srcval;
  wire ae_grant = er_run & ~cpu_vram_active & ~fb_we;
  wire [17:0] ae_src = {8'hFF, er_row[0], er_x};
  wire [17:0] ae_dst = {er_row, er_x};
  wire ae_dowr = (er_row != 9'd510) && (er_row != 9'd511);

  // ---- SRT sequential engine (M_SRB): 1024 FULL entries over the 2-port BRAM ----
  // Two clocks per entry (ph0 = issue the vram/buffer read, ph1 = capture/commit),
  // referencing the retained AE engine pattern below — autoerase itself stays inert.
  // The counter spans 1024 entries (the full 2-row pair), NOT 512.
  (* ramstyle = "no_rw_check" *) logic [15:0] srt_bbuf [0:1023];  // SRT row-pair buffer
  logic [10:0] sr_i;        // entry counter 0..1023
  logic        sr_ph;       // 0 = address/issue, 1 = capture/commit
  logic [15:0] sr_bq;       // registered buffer read (transfer write data)
  logic [15:0] sr_e0, sr_e1;
  wire  [28:0] sr_idx29 = srt_base + {18'd0, sr_i};
  wire  [18:0] sr_idx   = sr_idx29[18:0];
  wire         sr_v     = (sr_idx29 < {1'b0, VRAMW});
  // buffer ports (one always block per port for M10K inference)
  always @(posedge clk) sr_bq <= srt_bbuf[sr_i[9:0]];
  always @(posedge clk) if ((state == M_SRB) && sr_ph && !we_q)
    srt_bbuf[sr_i[9:0]] <= sr_v ? va_q : 16'h0000;

  // ---- 2-port arbiter: CPU field > SRT engine > fb_we > autoerase -------------
  // (M_SRB is a CPU op — the CPU is blocked on its ack — so it inherits the CPU's
  // slot ahead of fb_we; the game only runs SRT in DIRQ while the blitter is idle.)
  always_comb begin
    va_addr=18'd0; vb_addr=18'd0; va_we=1'b0; vb_we=1'b0; va_wd=16'd0; vb_wd=16'd0;
    if (cpu_vram_active) begin
      va_addr=cv_aa; vb_addr=cv_ba; va_we=cv_awe; vb_we=cv_bwe; va_wd=cv_awd; vb_wd=cv_bwd;
    end else if (state == M_SRB) begin
      va_addr=sr_idx; va_we=we_q & sr_ph & sr_v; va_wd=sr_bq;
    end else if (fb_we) begin
      va_addr=fb_addr; va_we=1'b1; va_wd=fb_wdata;               // blitter single-entry write
    end else if (ae_grant && er_ph==2'd0) begin
      va_addr=ae_src;                                            // autoerase: read src
    end else if (ae_grant && er_ph==2'd2) begin
      va_addr=ae_dst; va_we=ae_dowr; va_wd=er_srcval;            // autoerase: write dst
    end
  end

  // true-dual-port VRAM BRAM (Quartus infers M10K). Plain always for sim preload.
  // one block per port (see RAM note above)
  always @(posedge clk) begin if (va_we) vram[va_addr] <= va_wd;  va_q <= vram[va_addr];  end
  always @(posedge clk) begin if (vb_we) vram[vb_addr] <= vb_wd;  vb_q <= vram[vb_addr];  end
`endif  // USE_HW_VRAM (2-port BRAM engine; is_hwvram defined once above for both backends)

`ifdef USE_SDRAM_VRAM
  // ---- Phase 6 W1f: VRAM in SDRAM (vram_sdram_top) ----------------------------
  // All four VRAM accessors (CPU field RMW + blitter fb writes + autoerase + scanout)
  // multiplexed onto one 16-bit SDRAM channel. The CPU field access is driven from the
  // M_ACK FSM: pulse vsd_req, M_VSD waits for vsd_done. VRAM_BASE = VRAM's word offset in
  // SDRAM (0 here — a dedicated sim model; the unified controller sets the real base).
  logic        vsd_req; logic vsd_done; logic [31:0] vsd_rdata;
`ifdef USE_DDR3_VRAM
  // SRT sideband -> stv_vram_ddr_top D lane (P0027 Phase 2). Pulse req; M_SRTD waits done.
  logic        vsrt_req;
  logic        vsrt_done;
  logic [31:0] vsrt_e0e1;
  // VRAM in HPS DDR3: same accessor interface (req/done/fb/erase/scan), but the memory
  // channel is the DDRAM_* Avalon master (row-burst scanout + single-beat CPU/fb/autoerase,
  // 4:1 packed). Reset = sdram_por (P0022). This LIFTS the scanout+CPU-VRAM traffic OFF the
  // shared SDRAM, so scanout no longer starves the CPU (the cab boot-hang root cause). Proven
  // bit-exact vs the SDRAM path (tb_vram_ddr_xdiff). Ported from STV yunit_mem:653-667.
  stv_vram_ddr_top #(.VRAMW(VRAM_WORDS), .VRAM_DDR_BASE(29'h6400000)) u_vram_sdram (
    .clk(clk), .rst(rst), .sdram_por(sdram_por),
    .req(vsd_req), .we(we_q), .widx(widx), .boff(boff), .sz(sz_q), .wd(wd_q),
    .videobank(videobank), .dma_palette(dma_palette), .rdata(vsd_rdata), .done(vsd_done),
    .srt_req(vsrt_req), .srt_we(we_q), .srt_entry(srt_base[18:0]),
    .srt_done(vsrt_done), .srt_e0e1(vsrt_e0e1),
    .fb_we(fb_we), .fb_addr(fb_addr), .fb_wdata(fb_wdata), .fb_ack(fb_ack), .wr_busy(fb_wr_busy),
    .dbg_cst(dbg_vram_cst),
    .erase_start(erase_start), .erase_row0(erase_row0), .erase_lines(erase_lines),
    .erase_busy(erase_busy),
    .scan_req(scan_req), .scan_addr(scan_addr), .scan_data(scan_data), .scan_ack(scan_ack),
    .ddram_addr(ddram_addr), .ddram_burstcnt(ddram_burstcnt), .ddram_rd(ddram_rd), .ddram_we(ddram_we),
    .ddram_din(ddram_din), .ddram_be(ddram_be),
    .ddram_busy(ddram_busy), .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready));
`else
  vram_sdram_top #(.VRAMW(VRAM_WORDS), .SD_AW(25), .VRAM_BASE(25'd0)) u_vram_sdram (
    .clk(clk), .rst(rst),
    .req(vsd_req), .we(we_q), .widx(widx), .boff(boff), .sz(sz_q), .wd(wd_q),
    .videobank(videobank), .dma_palette(dma_palette), .rdata(vsd_rdata), .done(vsd_done),
    .fb_we(fb_we), .fb_addr(fb_addr), .fb_wdata(fb_wdata), .fb_ack(fb_ack),
    .erase_start(erase_start), .erase_row0(erase_row0), .erase_lines(erase_lines),
    .erase_busy(erase_busy),
    .scan_req(scan_req), .scan_addr(scan_addr), .scan_data(scan_data), .scan_ack(scan_ack),
    .sd_addr(vsd_addr), .sd_din(vsd_din), .sd_be(vsd_be), .sd_rd(vsd_rd), .sd_wr(vsd_wr),
    .sd_dout(vsd_dout), .sd_ack(vsd_ack));
  assign fb_wr_busy = 1'b0;   // vram_sdram_top: no write-behind FIFO -> fb_ack already means committed
  assign dbg_vram_cst = 3'd0; // BRAM path has no C-lane FSM
`endif
`endif

`ifdef USE_SDRAM_RAM
  // Main RAM in SDRAM: CPU field RMW only (no blitter/scanout). widx-WB_RAM = region-relative
  // word; the arbiter adds RAMW_BASE. Driven from M_ACK: pulse rsd_req, M_RSD waits rsd_done.
  logic        rsd_req; logic rsd_done; logic [31:0] rsd_rdata;
  ram_sdram #(.RAMW(RAM_WORDS), .SD_AW(25), .RAM_BASE(25'd0)) u_ram_sdram (
    .clk(clk), .rst(rst),
    .req(rsd_req), .we(we_q), .widx(widx - WB_RAM), .boff(boff), .sz(sz_q), .wd(wd_q),
    .rdata(rsd_rdata), .done(rsd_done), .active(),
    .sd_addr(rsd_addr), .sd_din(rsd_din), .sd_be(rsd_be),
    .sd_rd(rsd_rd), .sd_wr(rsd_wr), .sd_dout(rsd_dout), .sd_ack(rsd_ack));
`endif

  // The 48-bit window and merged write value are computed SEQUENTIALLY inside
  // M_ACK (below), NOT as continuous assigns: a continuous assign that reads a
  // memory via read_word() does not re-evaluate when the array is written, so a
  // read at the same word index as the previous access would return a stale
  // value. Sampling in the clocked block reads the committed memory each cycle.
  logic [47:0] win_s, merged_s;
  logic [47:0] win_s_q;   // registered window for the pipelined non-BRAM read extract
  logic [27:0] wrel;                                  // region-relative write base

`ifdef MEASURE_ACCESS
  // Sim-only Phase-6 instrumentation: per-region access distribution, to decide
  // how simple each region's synthesizable field engine can be. A "straddle"
  // read/write spans >1 (>=word+1) or >2 (>=word+2) 16-bit words. Aligned,
  // single-word accesses need only a registered 2-port BRAM; straddles need the
  // multi-cycle window FSM. Guarded — inert unless +define+MEASURE_ACCESS.
  integer rd_cnt   [0:15]; integer wr_cnt   [0:15];   // total reads / writes
  integer rd_str1  [0:15]; integer wr_str1  [0:15];   // spans word+1
  integer rd_str2  [0:15]; integer wr_str2  [0:15];   // spans word+2
  integer rd_boffnz[0:15]; integer wr_boffnz[0:15];   // boff != 0
  integer rd_szmax [0:15]; integer wr_szmax [0:15];   // max field size
  initial begin
    for (int i=0;i<16;i++) begin
      rd_cnt[i]=0; wr_cnt[i]=0; rd_str1[i]=0; wr_str1[i]=0;
      rd_str2[i]=0; wr_str2[i]=0; rd_boffnz[i]=0; wr_boffnz[i]=0;
      rd_szmax[i]=0; wr_szmax[i]=0;
    end
  end
  function automatic string rname(input logic [3:0] r);
    case (r)
      R_VRAM:rname="VRAM"; R_RAM:rname="RAM";  R_CMOS:rname="CMOS"; R_CMOSEN:rname="CMOSEN";
      R_PAL:rname="PAL";   R_DMA:rname="DMA";  R_IO:rname="IO";     R_SECURITY:rname="SEC";
      R_SOUND:rname="SOUND";R_CTRL:rname="CTRL";R_GFX:rname="GFX";  R_ROM:rname="ROM";
      default:rname="NONE";
    endcase
  endfunction
  final begin report_access(); end
  task automatic report_access;
    $display("=== MEASURE_ACCESS: per-region field distribution ===");
    $display("%-6s %8s %8s %8s %6s | %8s %8s %8s %6s",
             "region","rd","rd>=w+1","rd>=w+2","szmax","wr","wr>=w+1","wr>=w+2","szmax");
    for (int i=0;i<16;i++) if (rd_cnt[i]||wr_cnt[i])
      $display("%-6s %8d %8d %8d %6d | %8d %8d %8d %6d",
        rname(i[3:0]), rd_cnt[i], rd_str1[i], rd_str2[i], rd_szmax[i],
        wr_cnt[i], wr_str1[i], wr_str2[i], wr_szmax[i]);
  endtask
`endif

  // ---- sequential ------------------------------------------------------
  // Plain `always` (not `always_ff`) so `ram` can also be driven by the sim-only
  // `initial` zeroing above without violating SV's "one driving process per
  // variable" rule for always_ff (Questa vopt-7061). Same reason as birdybro's
  // sim_memory_model. This is the functional model; the synthesizable HW memory
  // controller (Phase 6) drops the initial and uses always_ff.
  always @(posedge clk) begin
`ifndef USE_HW_RAM
    // Functional/simulation backend for the same byte-wide persistence port.
    // Restore/clear holds the integrated game in reset, preventing a CPU clash.
    if (nvram_ext_write) begin
      if (nvram_ext_addr[0])
        nvram[nvram_ext_addr[15:1]][15:8] <= nvram_ext_wdata;
      else
        nvram[nvram_ext_addr[15:1]][7:0] <= nvram_ext_wdata;
    end
`endif
    if (rst) begin
      state     <= M_IDLE;
      mem_ack   <= 1'b0;
      mem_rdata <= 32'h0;
      // Sound (DCS) / security (PIC) / watchdog / control taps
      snd_data_wr   <= 1'b0;
      snd_data_o    <= 8'h00;
      snd_data_rd   <= 1'b0;
      // MAME power-on finishes with reset_w(1), which releases the DCS. snd_reset
      // is our active-HIGH held-reset level, hence the reset value is low.
      snd_reset     <= 1'b0;
      pic_wr        <= 1'b0;
      pic_wdata     <= 8'h00;
      pic_reset     <= 1'b0;
      watchdog_kick <= 1'b0;
      cmos_we       <= 1'b0;   // CMOS write disabled until a CMOSEN write arms it
      hw_cmos_write_ok <= 1'b0;
      nvram_cpu_write <= 1'b0;
      videobank     <= 1'b0;
      gfxbank       <= 2'd0;
      control_word  <= 16'd0;
      for (int io_i = 0; io_i < 16; io_i++)
        ioshuffle[io_i] <= io_i[2:0];
      er_run     <= 1'b0;
`ifdef YM_EXT_RD
      gfx_rd     <= 1'b0;
      cgfx_is_rom<= 1'b0;
`endif
`ifdef USE_HW_VRAM
      er_ph      <= 2'd0;
      sr_i       <= 11'd0;
      sr_ph      <= 1'b0;
`endif
`ifdef USE_SDRAM_VRAM
      vsd_req    <= 1'b0;
`ifdef USE_DDR3_VRAM
      vsrt_req   <= 1'b0;
`endif
`endif
      srt_q      <= 1'b0;
`ifdef USE_SDRAM_RAM
      rsd_req    <= 1'b0;
`endif
    end else begin
      // 1-clk register-tap strobes default de-asserted (pulse only in a write cycle).
      snd_data_wr   <= 1'b0;
      snd_data_rd   <= 1'b0;
      pic_wr        <= 1'b0;
      watchdog_kick <= 1'b0;
      nvram_cpu_write <= 1'b0;

      // Blitter VRAM write (independent of the CPU access FSM). The blitter
      // never writes the same pixel the CPU is mid-accessing (the CPU polls
      // the blitter and leaves VRAM alone while a blit runs), so a plain
      // per-index store is safe in this functional model.
`ifndef YM_VRAM_HW
      if (fb_we) vram[fb_addr] <= fb_wdata;
`endif

      // ---- Autoerase engine (MAME midyunit_v.cpp:534-560) ----------------
      // Per frame, every DISPLAYED row is refilled with the erase pattern the
      // game maintains in VRAM rows 510 (even rows) / 511 (odd rows):
      //   autoerase_line (:534): if (m_autoerase_enable && 0 <= line < 510)
      //     memcpy(&vram[512*line], &vram[512*(510 + (line & 1))], 512 words)
      // scanline_update (:554) erases rowaddr-1 after each scanned line and
      // (:558-559) the last visible rowaddr one line later, so the per-frame
      // erased set = rows (first_rowaddr - 1) .. last_rowaddr = lines+1 rows.
      // The full 16-bit {palette_hi, pixel_lo} word is copied (memcpy), NOT a
      // solid fill — rows 510/511 are a game-authored per-column pattern.
      //
      // DIVERGENCE NOTE (documented, deliberate): MAME's <510 guard tests the
      // RAW 34010 rowaddr (tms34010.cpp:1152 rowaddr = dpyadr >> 4, 12 bits)
      // while the pixel fetch masks it to 9 bits (midyunit_v.cpp:545
      // (rowaddr<<9) & 0x3fe00). We guard on the MASKED row (skip 510/511
      // only), so a window that straddles the 512-row wrap (rows 480-511 +
      // 0-31, seen on this game's boot screens) also erases the wrapped rows
      // — which is what correct video needs; MAME's raw-value guard would
      // leave them stale if the raw rowaddr ran past 511. Identical to MAME
      // whenever the raw window stays within 0..511. The row0-1 = -1 first
      // call MAME skips (line<0) maps here to masked row 511, which the
      // 510/511 guard skips — equivalent by construction.
      //
      // One pixel per clock (512 clk/row, ~132k clk/frame at 256 lines): a
      // paced read-copy loop, the same access shape the Phase-6 SDRAM
      // controller will burst. Ordered AFTER the blitter fb_we store so a
      // same-cycle collision resolves to the erase (MAME's erase timer also
      // runs after the blit that raced it).
`ifndef YM_VRAM_HW
      if (er_run) begin
        if (er_row != 9'd510 && er_row != 9'd511)     // never erase the erase-pattern rows
          vram[{er_row, er_x}] <= vram[{8'hFF, er_row[0], er_x}]; // src row = 510 | parity
        if (er_x == 9'd511) begin
          er_x   <= 9'd0;
          er_row <= er_row + 9'd1;                    // mod-512 row advance
          er_left <= er_left - 10'd1;
          if (er_left <= 10'd1) er_run <= 1'b0;       // that was the last row
        end else begin
          er_x <= er_x + 9'd1;
        end
      end else if (erase_start === 1'b1 && autoerase && erase_lines != 10'd0) begin
        // gated on the captured CONTROL /autoerase enable (control_w:235)
        er_run  <= 1'b1;
        er_row  <= erase_row0 - 9'd1;                 // one-behind first row (:554)
        er_x    <= 9'd0;
        er_left <= erase_lines + 10'd1;               // + the final-line timer row (:558)
      end
`endif
`ifdef USE_HW_VRAM
      // autoerase 3-cycle engine (ports driven by the VRAM arbiter above). ER0
      // issues the src read (on grant), ER0b captures src from va_q (unconditional
      // -- va_q one cycle after ER0 == src regardless of who addresses the port),
      // ER2 writes dst (on grant) and advances the sweep. Paused (no advance) while
      // the CPU field engine or fb_we owns the ports -> byte-identical to MAME's
      // per-row copy, just spread across contention.
      if (er_run) begin
        case (er_ph)
          2'd0: if (ae_grant) er_ph <= 2'd1;                   // read issued -> capture next
          2'd1: begin er_srcval <= va_q; er_ph <= 2'd2; end    // va_q == vram[src]
          2'd2: if (ae_grant) begin                            // dst written -> advance
                  er_ph <= 2'd0;
                  if (er_x == 9'd511) begin
                    er_x    <= 9'd0;
                    er_row  <= er_row + 9'd1;                  // mod-512 row advance
                    er_left <= er_left - 10'd1;
                    if (er_left <= 10'd1) er_run <= 1'b0;      // last row done
                  end else er_x <= er_x + 9'd1;
                end
          default: er_ph <= 2'd0;
        endcase
      end else if (erase_start === 1'b1 && autoerase && erase_lines != 10'd0) begin
        er_run  <= 1'b1;
        er_row  <= erase_row0 - 9'd1;
        er_x    <= 9'd0;
        er_left <= erase_lines + 10'd1;
        er_ph   <= 2'd0;
      end
`endif

      unique case (state)
        M_IDLE: begin
          mem_ack <= 1'b0;
          if (mem_req && !mem_ack) begin
            a_q   <= mem_addr;
            we_q  <= mem_we;
            wd_q  <= mem_wdata;
            sz_q  <= mem_size;
`ifdef SYNTHESIS
            srt_q <= mem_srt;
`else
            srt_q <= (mem_srt === 1'b1);   // legacy hosts leave the port unconnected (z)
`endif
            state <= M_ACK;
          end
        end
        M_ACK: begin
`ifndef SYNTHESIS
          // SRT on any non-VRAM region: execute as a NORMAL access + warn (game never does it).
          if (srt_q && region != R_VRAM)
            $display("[wolf_mem] WARNING: SRT-converted %s to non-VRAM region %0d (addr=%08h) — executing as a NORMAL access",
                     we_q ? "write" : "read", region, a_q);
`endif
`ifdef YM_EXT_RD
          // External read-only fetch (R_GFX and/or R_ROM): fetch only the bytes
          // covered by {boff,size}. An aligned 16-bit opcode needs 2 bytes; the
          // worst-case unaligned 32-bit field still needs the full 6-byte window.
          // ext_fetch/ext_base select gfx @0 or program ROM @SDRAM_ROMB.
          if (ext_fetch) begin
            mem_ack  <= 1'b0;                          // hold ack until fetched
            gfx_base <= ext_base;                      // byte addr of word0 low byte
            cgfx_is_rom <= (region == R_ROM);          // demux key: ROM->SDRAM, GFX->DDR3
            gfx_cnt  <= 3'd0;
            gfx_last <= lastb[5:3];                    // floor((boff+size-1)/8), range 0..5
            gfx_win  <= 48'd0;
            gfx_rd   <= 1'b1;
            state    <= M_GFX;
          end else begin
`endif
`ifdef USE_SDRAM_RAM
          if (is_sdram_ram) begin
            mem_ack <= 1'b0;                       // hold ack until ram_sdram completes
            rsd_req <= 1'b1;                       // 1-cycle pulse (latched by ram_sdram); RMW keyed on we_q
            state   <= M_RSD;
          end else
`endif
          if (is_hwram) begin
            // RAM/PAL/CMOS -> clocked BRAM window engine (multi-cycle). The read
            // of w0/w1 is issued combinationally (eng ports) this cycle; captured
            // in M_HR1. Field math unchanged (hwin/hmerged mirror win_s/merged_s).
            if (region == R_CMOS && nvram_ext_active) begin
              // Upload borrows CMOS port B. Retry a coincident CPU CMOS access
              // in M_ACK after the upload ends.
              mem_ack <= 1'b0;
              state <= M_ACK;
            end else begin
              if (region == R_CMOS && we_q) begin
                // Capture and consume CMOSEN before the multi-cycle writeback.
                hw_cmos_write_ok <= cmos_we;
                cmos_we <= 1'b0;
              end
              mem_ack <= 1'b0;
              state   <= M_HR1;
            end
          end else if (is_hwvram) begin
            mem_ack <= 1'b0;
`ifdef USE_SDRAM_VRAM
`ifdef USE_DDR3_VRAM
            // VRAM in DDR3: SRT ops go to the stv_vram_ddr_top D lane (M_SRTD). The
            // D-lane burst engine requires a beat-aligned entry base (entry[1:0]==0,
            // i.e. even widx) — every game/contract SRT address is row-aligned. A
            // misaligned SRT op (never generated) executes as a NORMAL access + warns.
            if (srt_q && !widx[0]) begin
              vsrt_req <= 1'b1;
              state    <= M_SRTD;
            end else begin
`ifndef SYNTHESIS
              if (srt_q)
                $display("[wolf_mem] WARNING: non-beat-aligned SRT op (addr=%08h) — executing as a NORMAL access", a_q);
`endif
              // VRAM -> DDR3 engine (normal field access). Pulse req; M_VSD waits done.
              vsd_req <= 1'b1;
              state   <= M_VSD;
            end
`else
`ifndef SYNTHESIS
            // Legacy SDRAM VRAM path (vram_sdram_top, non-DDR3): NO SRT engine — the
            // shipping Hangtime/UMK3 config is USE_DDR3_VRAM. Execute as normal + warn.
            if (srt_q)
              $display("[wolf_mem] WARNING: SRT op on the legacy SDRAM VRAM path (addr=%08h) — no SRT engine here, executing as a NORMAL access", a_q);
`endif
            // VRAM -> SDRAM engine (vram_sdram_top). Pulse req; M_VSD waits for done.
            vsd_req <= 1'b1;
            state   <= M_VSD;
`endif
`else
            // VRAM -> clocked 2-port BRAM engine. M_ACK issues the e0/e1 read (via
            // the arbiter); reads go to M_VRD, writes to M_VWR0 (read-modify-write).
            // SRT ops divert to the sequential 1024-entry engine (M_SRB).
`ifdef USE_HW_VRAM
            if (srt_q) begin
              sr_i  <= 11'd0;
              sr_ph <= 1'b0;
              state <= M_SRB;
            end else state <= we_q ? M_VWR0 : M_VRD;
`else
            state <= we_q ? M_VWR0 : M_VRD;
`endif
`endif
          end else begin
`ifndef YM_VRAM_HW
          if (srt_q && region == R_VRAM) begin
            // SRT memcpy (functional model; midtunit_v.cpp:330-339): 1024 FULL 16-bit
            // entries — palette-high bytes INCLUDED — at entry base srt_base. Acks in
            // one cycle like every other functional access.
            if (!we_q) begin
              for (int si = 0; si < 1024; si++)
                srt_fbuf[si] <= ((srt_base + si) < {1'b0, VRAMW}) ? vram[srt_base[18:0] + si]
                                                                  : 16'h0000;
              mem_rdata <= srt_rdata_f(
                  ( srt_base          < {1'b0, VRAMW}) ? vram[srt_base[18:0]]       : 16'h0000,
                  ((srt_base + 29'd1) < {1'b0, VRAMW}) ? vram[srt_base[18:0] + 1'b1] : 16'h0000);
            end else begin
              for (int si = 0; si < 1024; si++)
                if ((srt_base + si) < {1'b0, VRAMW})
                  vram[srt_base[18:0] + si] <= srt_fbuf[si];   // wd_q/sz_q DISCARDED
              mem_rdata <= 32'h0;
            end
            mem_ack <= 1'b1;
            state   <= M_IDLE;
          end else begin
`endif
          // Sample the 3-word window FRESH from committed memory this cycle.
          win_s    = {read_word(region, widx + 28'd2),
                      read_word(region, widx + 28'd1),
                      read_word(region, widx)};
          merged_s = (win_s & ~smask) | (({16'h0, wd_q} << boff) & smask);
`ifdef MEASURE_ACCESS
          if (we_q) begin
            wr_cnt[region] <= wr_cnt[region] + 1;
            if (lastb >= 6'd16) wr_str1[region] <= wr_str1[region] + 1;
            if (lastb >= 6'd32) wr_str2[region] <= wr_str2[region] + 1;
            if (boff != 4'd0)   wr_boffnz[region] <= wr_boffnz[region] + 1;
            if (sz > wr_szmax[region][5:0]) wr_szmax[region] <= sz;
          end else begin
            rd_cnt[region] <= rd_cnt[region] + 1;
            if (lastb >= 6'd16) rd_str1[region] <= rd_str1[region] + 1;
            if (lastb >= 6'd32) rd_str2[region] <= rd_str2[region] + 1;
            if (boff != 4'd0)   rd_boffnz[region] <= rd_boffnz[region] + 1;
            if (sz > rd_szmax[region][5:0]) rd_szmax[region] <= sz;
          end
`endif
          if (we_q) begin
            // Writable backed regions: RAM / VRAM / palette / CMOS. ROM read-only;
            // the register regions (DMA/IO/CTRL/SOUND/SECURITY/CMOSEN) are handled by
            // the write taps below. 3-word straddle RMW per backed region.
            unique case (region)
`ifndef USE_HW_RAM
              R_RAM: begin
                wrel = widx - WB_RAM;
`ifndef USE_SDRAM_RAM
                if (wrel < RAMW)                        ram[wrel]     <= merged_s[15:0];
                if (lastb >= 6'd16 && (wrel+1) < RAMW)  ram[wrel + 1] <= merged_s[31:16];
                if (lastb >= 6'd32 && (wrel+2) < RAMW)  ram[wrel + 2] <= merged_s[47:32];
`endif
              end
`endif
`ifndef YM_VRAM_HW
              R_VRAM: begin
                // MAME vram_w byte-lane: each 34010 word offset -> 2 pixels
                // (offset*2, +1); videobank picks pixel vs palette-base plane.
                // CRITICAL: apply only the ACCESSED byte lane(s). A single 8-bit
                // pixel write (the PIXBLT binary color-expand runs psize=8, one
                // pixel per mem op) must NOT touch the neighbouring pixel — the
                // old code always wrote both, so wd_q[15:8]=0 corrupted the odd
                // pixel and garbled non-uniform content (text). Solid fills hid it.
                if (sz <= 6'd8) begin
                  // one pixel, selected by the bit offset (boff 0 -> even, 8 -> odd)
                  wrel = (widx<<1) + {27'b0, boff[3]};
                  if (wrel < VRAMW) begin
                    if (videobank)
                      vram[wrel] <= {(boff[3] ? dma_palette[15:8] : dma_palette[7:0]), wd_q[7:0]};
                    else
                      vram[wrel] <= {wd_q[7:0], vram[wrel][7:0]};
                  end
                end else begin
                // Low 16-bit sub-word (2 pixels) at offset widx:
                if (((widx<<1)+28'd1) < VRAMW) begin
                  if (videobank) begin
                    vram[ widx<<1     ] <= {dma_palette[7:0],  wd_q[7:0]};
                    vram[(widx<<1)+1  ] <= {dma_palette[15:8], wd_q[15:8]};
                  end else begin
                    vram[ widx<<1     ] <= {wd_q[7:0],  vram[ widx<<1   ][7:0]};
                    vram[(widx<<1)+1  ] <= {wd_q[15:8], vram[(widx<<1)+1][7:0]};
                  end
                end
                // High 16-bit sub-word (only on a 32-bit access) at offset widx+1:
                if (sz > 6'd16 && (((widx+1)<<1)+28'd1) < VRAMW) begin
                  if (videobank) begin
                    vram[ (widx+1)<<1   ] <= {dma_palette[7:0],  wd_q[23:16]};
                    vram[((widx+1)<<1)+1] <= {dma_palette[15:8], wd_q[31:24]};
                  end else begin
                    vram[ (widx+1)<<1   ] <= {wd_q[23:16], vram[ (widx+1)<<1   ][7:0]};
                    vram[((widx+1)<<1)+1] <= {wd_q[31:24], vram[((widx+1)<<1)+1][7:0]};
                  end
                end
                end // sz > 8 (2/4-pixel word write)
              end
`endif
`ifndef USE_HW_RAM
              R_PAL: begin
                wrel = widx - WB_PAL;
                if (wrel < PALW)                        pal[wrel]     <= merged_s[15:0];
                if (lastb >= 6'd16 && (wrel+1) < PALW)  pal[wrel + 1] <= merged_s[31:16];
                if (lastb >= 6'd32 && (wrel+2) < PALW)  pal[wrel + 2] <= merged_s[47:32];
              end
`endif
`ifndef USE_HW_RAM
              R_CMOS: begin
                // FLAT + one-shot GATED (midwunit_m.cpp:32 cmos_w): write only when
                // cmos_we is armed (by a prior CMOSEN write), then consume the latch.
                wrel = widx - WB_CMOS;
                if (cmos_we) begin
                  if (wrel < CMOSW)                       nvram[wrel]     <= merged_s[15:0];
                  if (lastb >= 6'd16 && (wrel+1) < CMOSW) nvram[wrel + 1] <= merged_s[31:16];
                  if (lastb >= 6'd32 && (wrel+2) < CMOSW) nvram[wrel + 2] <= merged_s[47:32];
                  cmos_we <= 1'b0;                       // one-shot consumed
                  nvram_cpu_write <= 1'b1;
                end
              end
`endif
              default: ; // ROM / register regions: handled by the taps below (or dropped)
            endcase

            // ---- Register-region write taps (Wolf machine handlers) -------------
            // CMOSEN (0x01480000, cmos_enable_w midwunit_m.cpp:26): ARM the one-shot
            // CMOS write-enable (MAME sets =1 unconditionally, regardless of data).
            if (region == R_CMOSEN) cmos_we <= 1'b1;

            // CONTROL (0x01B00000, midwunit_control_w midtunit_v.cpp:370): store the
            // word; videobank = bit 11, gfxbank = bits 9:8. NO cmos-page, NO autoerase.
            if (region == R_CTRL) begin
              control_word <= wd_q[15:0];
              videobank    <= wd_q[11];
              gfxbank      <= wd_q[9:8];
            end

            // SOUND (0x01680000, sound_w midwunit_m.cpp:379): DCS data_w(D & 0xff).
            if (region == R_SOUND) begin
              snd_data_o  <= wd_q[7:0];
              snd_data_wr <= 1'b1;                       // 1-clk strobe
            end

            // SECURITY (0x01600000, security_w midwunit_m.cpp:347): pic.write(D&0xff)
            // only when offset==0 (reg word) & ACCESSING_BITS_0_7.
            if (region == R_SECURITY && (widx == WB_SEC)) begin
              pic_wdata <= wd_q[7:0];
              pic_wr    <= 1'b1;                         // 1-clk strobe
            end

            // IO (0x01800000, io_w midwunit_m.cpp:61): s = (off & 7). case 1 -> DCS
            // reset (D[4], active-HIGH in this RTL) + PIC reset (raw bit5); case 3 ->
            // watchdog strobe (no-op). MAME passes ~D[4] into its active-LOW DCS
            // reset_w input, so its observable held-reset level is D[4].
            if (region == R_IO) begin
              wrel = widx - WB_IO;
              if (wwf_io_shuffle_active && (wrel[3:0] == 4'd0)) begin
                // install_write_handler(0x01800000..0x0180000f):
                // selector writes replace normal io_w at physical offset 0.
                for (int io_i = 0; io_i < 16; io_i++)
                  ioshuffle[io_i] <= io_i[2:0];
                unique case (wd_q[15:0])
                  16'd1: begin
                    ioshuffle[4] <= 3'd0; ioshuffle[8] <= 3'd1;
                    ioshuffle[1] <= 3'd2; ioshuffle[9] <= 3'd3;
                    ioshuffle[2] <= 3'd4;
                  end
                  16'd2: begin
                    ioshuffle[8] <= 3'd0; ioshuffle[2] <= 3'd1;
                    ioshuffle[4] <= 3'd2; ioshuffle[6] <= 3'd3;
                    ioshuffle[1] <= 3'd4;
                  end
                  16'd3: begin
                    ioshuffle[1] <= 3'd0; ioshuffle[8] <= 3'd1;
                    ioshuffle[2] <= 3'd2; ioshuffle[10] <= 3'd3;
                    ioshuffle[5] <= 3'd4;
                  end
                  16'd4: begin
                    ioshuffle[2] <= 3'd0; ioshuffle[4] <= 3'd1;
                    ioshuffle[1] <= 3'd2; ioshuffle[7] <= 3'd3;
                    ioshuffle[8] <= 3'd4;
                  end
                  default: ; // selector 0 or invalid data = identity map
                endcase
              end else begin
                unique case (wwf_io_shuffle_active ? ioshuffle[wrel[3:0]] : wrel[2:0])
                  3'd1: begin snd_reset <= wd_q[4]; pic_reset <= wd_q[5]; end
                  3'd3: watchdog_kick <= 1'b1;            // 1-clk pulse
                  default: ;
                endcase
              end
            end
            mem_rdata <= 32'h0;
            mem_ack   <= 1'b1;         // writes/register-sets complete this cycle
            state     <= M_IDLE;
          end else begin
            // dcs.data_r() auto-acks the output latch. win_s snapshots the
            // response before this strobe takes effect in pipelined builds.
            if (region == R_SOUND) snd_data_rd <= 1'b1;
`ifdef USE_HW_RAM
            win_s_q <= win_s;          // pipeline the extract (synth timing closure @96 MHz)
            mem_ack <= 1'b0;
            state   <= M_RDLY;
`else
            mem_rdata <= 32'((win_s >> boff) & rmask);   // functional: 1-cycle read
            mem_ack   <= 1'b1;
            state     <= M_IDLE;
`endif
          end
`ifndef YM_VRAM_HW
          end  // else (non-SRT functional access)
`endif
          end  // else (functional single-cycle path for non-BRAM regions)
`ifdef YM_EXT_RD
          end  // else (non-external / write path)
`endif
        end
`ifdef YM_EXT_RD
        M_GFX: begin
          // Fetch 1..6 consecutive bytes and assemble a zero-filled 48-bit
          // little-endian window, then extract the requested field. gfx_raddr is
          // the registered gfx_base cursor; the one-cycle gap supports any read latency.
          if (gfx_rack) begin
            gfx_rd <= 1'b0;                            // consumed -> gap before next req
            gfx_win <= gfx_win_with_byte;
            if (gfx_cnt == gfx_last) begin
              // Extract on the following cycle from the registered window. This
              // breaks the external address/cache/data path before the barrel shift.
              state <= M_GFIN;
            end else begin
              gfx_cnt <= gfx_cnt + 3'd1;
              gfx_base <= gfx_base + 26'd1;
            end
          end else if (!gfx_rd) begin
            gfx_rd <= 1'b1;                            // (re)issue request for gfx_cnt
          end
        end
        M_GFIN: begin
          mem_ack   <= 1'b1;
          mem_rdata <= 32'((gfx_win >> boff) & rmask);
          state     <= M_IDLE;
        end
`endif  // YM_EXT_RD
`ifdef USE_HW_RAM
        // Clocked BRAM window engine (RAM/PAL/CMOS). eng ports are driven
        // combinationally by `state` above; here we capture q and sequence.
        M_HR1: begin
          rd0   <= eng_aq;            // ram[hidx0] (issued in M_ACK) valid now
          rd1   <= eng_bq;            // ram[hidx1]
          state <= M_HR2;             // M_HR1 combinationally pre-issued hidx2 read
        end
        M_HR2: begin
          rd2   <= eng_aq;            // ram[hidx2] valid now (masked by hval2 in hwin)
          state <= M_HFIN;
        end
        M_HFIN: state <= M_HFIN2;   // rd*/hwin captured -> hwin_q latches this edge; merge/extract next cycle
        M_HFIN2: begin
          // hwin_q + the registered a_q-derived masks are valid -> merge/extract from registers.
          if (we_q) begin
            // write-back w0,w1 issued combinationally this cycle (eng_awe/bwe, hmerged2).
            if (lastb >= 6'd32 && hval[2]) begin
              state <= M_HW2;         // need a 3rd write (only 2 ports)
            end else begin
              if (region == R_CMOS) begin
                if (hw_cmos_write_ok) nvram_cpu_write <= 1'b1;
                hw_cmos_write_ok <= 1'b0;
              end
              mem_ack <= 1'b1;
              state   <= M_IDLE;
            end
          end else begin
            mem_rdata <= 32'((hwin_q >> boff_q) & rmask_q);   // extract field (pipelined)
            mem_ack   <= 1'b1;
            state     <= M_IDLE;
          end
        end
        M_HW2: begin                  // 3rd-word write (eng_awe drives hidx2)
          if (region == R_CMOS) begin
            if (hw_cmos_write_ok) nvram_cpu_write <= 1'b1;
            hw_cmos_write_ok <= 1'b0;
          end
          mem_ack <= 1'b1;
          state   <= M_IDLE;
        end
        M_RDLY: begin                 // non-BRAM (INPUT/PROT/CTRL) read: extract from registered window
          mem_rdata <= 32'((win_s_q >> boff_q) & rmask_q);
          mem_ack   <= 1'b1;
          state     <= M_IDLE;
        end
`endif  // USE_HW_RAM
`ifdef USE_HW_VRAM
        // Clocked VRAM engine. Ports are driven combinationally by `state` (via cv
        // + the arbiter). Read: 1 word (never straddles). Write: RMW e0/e1 (+e2/e3).
        M_VRD: begin
          mem_rdata <= 32'((({32'h0, vword} >> boff) & rmask));   // form+extract field
          mem_ack   <= 1'b1;
          state     <= M_IDLE;
        end
        M_VWR0: begin
          o0 <= va_q; o1 <= vb_q;                 // e0/e1 old values (read in M_ACK)
          state <= (sz_q > 6'd16) ? M_VWR1 : M_VWW0;  // sz>16 also needs e2/e3 (issued now)
        end
        M_VWR1: begin
          o2 <= va_q; o3 <= vb_q;                 // e2/e3 old values
          state <= M_VWW0;
        end
        M_VWW0: begin
          // e0/e1 (or ea) writes issued this cycle via cv/arbiter.
          if (sz_q > 6'd16) state <= M_VWW1;
          else begin mem_ack <= 1'b1; state <= M_IDLE; end
        end
        M_VWW1: begin                             // e2/e3 writes issued this cycle
          mem_ack <= 1'b1;
          state   <= M_IDLE;
        end
        M_SRB: begin
          // SRT sequential engine: 2 clocks per entry over 1024 entries. ph0 issues
          // the vram read (latch) / buffer read (transfer) via the arbiter arm; ph1
          // captures va_q into srt_bbuf (latch; separate buffer-port always) or
          // commits sr_bq into vram (transfer; va_we in the arbiter arm).
          if (!sr_ph) sr_ph <= 1'b1;
          else begin
            sr_ph <= 1'b0;
            if (!we_q) begin
              if (sr_i == 11'd0) sr_e0 <= sr_v ? va_q : 16'h0000;
              if (sr_i == 11'd1) sr_e1 <= sr_v ? va_q : 16'h0000;
            end
            if (sr_i == 11'd1023) begin
              mem_rdata <= we_q ? 32'h0 : srt_rdata_f(sr_e0, sr_e1);
              mem_ack   <= 1'b1;
              state     <= M_IDLE;
            end else sr_i <= sr_i + 11'd1;
          end
        end
`endif  // USE_HW_VRAM
`ifdef USE_SDRAM_VRAM
        M_VSD: begin                              // VRAM access via vram_sdram_top
          vsd_req <= 1'b0;                        // req was a 1-cycle pulse (latched)
          if (vsd_done) begin
            mem_rdata <= vsd_rdata;               // read result (ignored for writes)
            mem_ack   <= 1'b1;
            state     <= M_IDLE;
          end
        end
`endif
`ifdef USE_SDRAM_VRAM
`ifdef USE_DDR3_VRAM
        M_SRTD: begin                             // SRT op via the stv_vram_ddr_top D lane
          vsrt_req <= 1'b0;                       // req was a 1-cycle pulse (latched)
          if (vsrt_done) begin
            // Latch: A0033 rdata from the two base entries returned by the D lane.
            // Transfer: rdata is 0 and the D lane only acks after the burst write has
            // fully retired to the agent (a subsequent CPU access is ordered behind it).
            mem_rdata <= we_q ? 32'h0
                              : srt_rdata_f(vsrt_e0e1[15:0], vsrt_e0e1[31:16]);
            mem_ack   <= 1'b1;
            state     <= M_IDLE;
          end
        end
`endif
`endif
`ifdef USE_SDRAM_RAM
        M_RSD: begin                              // main-RAM access via ram_sdram (mirrors M_VSD)
          rsd_req <= 1'b0;                        // req was a 1-cycle pulse (latched)
          if (rsd_done) begin
            mem_rdata <= rsd_rdata;               // read result (ignored for writes)
            mem_ack   <= 1'b1;
            state     <= M_IDLE;
          end
        end
`endif
        default: begin
          state   <= M_IDLE;
          mem_ack <= 1'b0;
        end
      endcase
    end
  end

endmodule

`default_nettype wire

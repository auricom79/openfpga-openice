// ============================================================================
// adsp2105.sv  --  ADSP-2105 core, behavioral instruction-atomic model
// ----------------------------------------------------------------------------
// Path-A recursive-loop DUT, increment #1.  Goal of this increment: reproduce
// MAME 0.280's per-instruction PC stream (umk3_pc.ref) for the DCS firmware
// boot.  Strategy: the program sequencer's default is pc<-pc+1, so implementing
// only the CONTROL-FLOW ops (JUMP imm, DO-UNTIL/CE, CALL/RTS) + the loop counter
// makes the PC stream match through all straight-line code; the first
// divergence marks the next op to implement.  Data-path (ALU/MAC/shifter) and
// cycle-accurate pipelining come in later increments, validated the same way.
//
// Encodings + semantics taken verbatim from MAME 0.280 gospel:
//   2100dasm.cpp (opcode fields), 2100ops.h (CONDITION/CE, reg groups).
//
// Phase-1 refactor: PM/DM/ROM storage moved into the dcs_mem shim (included
// below so the existing 2-file compile line in loop/run*.sh is unchanged).
// ============================================================================
`include "dcs_mem.sv"

module adsp2105 #(
    parameter PMFILE    = "pm.hex",
    parameter RD_LATENCY = 1,            // Phase 2: 1 = clocked-BRAM fetch + wait state.
                                         //          0 = async fetch (Phase 0/1 legacy).
                                         // Data-side reads (DM/PM-data/alias/bank window +
                                         // the autobuffer drain) are ALWAYS clocked now:
                                         // S_MEM/S_DRAIN wait states issue the address one
                                         // clock before EXEC consumes it.
    parameter DDR_LATENCY = 8,           // Phase 5: modeled DDR3 round-trip clocks for the
                                         // u2-u5 sound-ROM port (registered request -> data);
                                         // bank-window reads + the S_BOOT stream stall on it.
    parameter PF_LINES    = 512,         // Phase 5: prefetch-cache lines (8 B each; 512 =
                                         // one full 4 KB bank page). See dcs_mem.
    parameter EXT_ROM     = 0,           // 1 exposes real packed sound-ROM beat traffic
    parameter CORE_CE_EN  = 0,           // 1 advances architectural state on core_ce only
`ifdef POCKET
    parameter EXPLICIT_RAM_CE = 1,      // physical PM/DM input and core enables
    parameter SHARED_REG_READ = 1,      // one generic register read port per instruction
    parameter MLAB_PC_STACK = 1,        // shared return/loop stack in distributed RAM
    parameter SHARED_DAG_WRITE = 1,      // one write path for both I/M/L groups
    parameter SHARED_MAC = 1,            // one signed multiplier and add/sub datapath
    parameter MLAB_STATUS_STACK = 1,     // interrupt status stack in distributed RAM
    parameter SHARED_ALU = 1,            // one 17-bit arithmetic datapath
    parameter SHARED_SHIFT = 1,          // one reversible barrel shifter
    parameter SHARED_EXEC = 1,           // share mutually exclusive register/DAG writes
    parameter SHARED_PM = 1,             // one fetch port + one read/write port
`else
    parameter EXPLICIT_RAM_CE = 0,
    parameter SHARED_REG_READ = 0,
    parameter MLAB_PC_STACK = 0,
    parameter SHARED_DAG_WRITE = 0,
    parameter SHARED_MAC = 0,
    parameter MLAB_STATUS_STACK = 0,
    parameter SHARED_ALU = 0,
    parameter SHARED_SHIFT = 0,
    parameter SHARED_EXEC = 0,
    parameter SHARED_PM = 0,             // preserve the donor's duplicated RAM
`endif
    parameter PCM_STREAM  = 0            // 1 strobes every captured PCM sample for hardware
) (
    // ---- CLOCKING SHAPE (Phase 8a item 3) -----------------------------------
    //  `clk` is a FREE-RUNNING core clock. This is an instruction-atomic
    //  multicycle FSM (S_FETCH/DECODE/[stalls]/EXEC, SYNTH-REFACTOR-PLAN §3), NOT
    //  a cycle-accurate ADSP-2105 pipeline, so clk is decoupled from the real
    //  ADSP's 10 MHz instruction clock. The ONLY rate anchor in the whole design
    //  is `dac_ce_in` (the 31250 Hz DAC sample slot, below) -- the audio drain
    //  retimes to it, and §0's producer/consumer margin makes the core:DAC clock
    //  ratio irrelevant to the decoded PCM. There is therefore NO fixed clk
    //  frequency requirement for CORRECTNESS; only for THROUGHPUT (keeping the
    //  half-buffer filled ahead of the DAC in real time):
    //    - Measured CPI of this FSM = 13,740,924 clks / 4,500,000 retired instrs
    //      = 3.053 clocks per instruction (iverilog, track 046a, maxn=4.5M).
    //    - The real DCS runs the firmware at 10 MHz = ~10 MIPS. To retire the
    //      same instruction budget in real time the core must run at
    //      >= 10 MHz * 3.05 CPI ~= 30.5 MHz  ->  target clk >= 31 MHz.
    //    - 31 MHz is trivially met on Cyclone V (this core's Fmax is far higher;
    //      the 10 MHz "ADSP clock" of the old cycle model is retired). A single
    //      >=31 MHz PLL output feeds clk; a divider off the audio clock generates
    //      dac_ce_in at 31250 Hz. (No PLL is instantiated here -- that is the
    //      wolf-unit wrapper's job, roadmap E; this is the port/ce contract.)
    input  wire        clk,
    input  wire        rst,
    input  wire        core_ce,
    // ---- DCS board reset line (Phase 7, SYNTH-REFACTOR-PLAN §4.2): the host
    //      (main CPU) pulses the DCS reset (dcs.cpp:1456 reset_w -> dcs_reset ->
    //      dcs_boot). The old RTL-internal reset_ats[] instruction-count replay
    //      is GONE -- this pin is the only external-reset source; board glue
    //      (roadmap C) drives it on silicon, the TB drives it at the captured
    //      instruction counts in sim. Level-sampled through one input flop
    //      (async-line synchronizer) at every instruction-boundary check state;
    //      a held line keeps the CPU rebooting (= held in reset), a one-clock
    //      pulse causes exactly one reboot from ROM bank 0 (dcs.cpp:551-553
    //      REV_DCS1 bank reset + dcs_boot).
    input  wire        host_rst,
    // ---- Host latch port (Phase 8a item 2, roadmap C10, dcs.cpp:1450-1520 +
    //      :174-187). A real bidirectional mailbox between the host (main CPU)
    //      and the DCS, with a status word the host polls:
    //        host_cmd_w  : strobe -- host writes ONE command word into the INPUT
    //                      latch (dcs.cpp data_w -> dcs_delayed_data_w:1503-1520:
    //                      SET_INPUT_FULL + ADSP2105_IRQ2 ASSERT + m_input_data).
    //                      The main CPU writes one BYTE per strobe (midtunit_m.cpp
    //                      :597 data_w(data & 0xff); a DCS track command = two
    //                      such writes, DCSDecoder.h:81-88).
    //        host_cmd_data : the command word latched by host_cmd_w.
    //        host_status_r : the latch-control status word the host reads
    //                      (control_r for mk3 returns the full m_latch_control,
    //                      dcs.cpp:1450-1452). Bit polarities EXACT (dcs.cpp:174-
    //                      175): LCTRL_OUTPUT_EMPTY=0x400, LCTRL_INPUT_EMPTY=0x800
    //                      -- a bit SET means that latch is EMPTY. Power-on/reset
    //                      sets BOTH empty (dcs.cpp:585-586) so idle = 0x0C00.
    //        host_response_r : the OUTPUT latch (DCS->host data, m_output_data);
    //                      the ADSP fills it by writing DM 0x3400-0x3403
    //                      (output_latch_w, dcs.cpp:320 + 1590-1596:SET_OUTPUT_FULL).
    //        host_resp_rd  : strobe -- host reads host_response_r; with auto-ack
    //                      that SETs OUTPUT_EMPTY (data_r -> delayed_ack_w,
    //                      dcs.cpp:1626-1639 + 1607-1609).
    input  wire        host_cmd_w,
    input  wire [15:0] host_cmd_data,
    output wire [15:0] host_status_r,
    output wire [15:0] host_response_r,
    input  wire        host_resp_rd,
    // Packed 4 MB U2|U3|U4|U5 ROM backing. Only active when EXT_ROM=1;
    // rom_ddr_addr is a 64-bit beat offset and rom_ddr_req is held until ready.
    output wire        rom_ddr_req,
    output wire [18:0] rom_ddr_addr,
    input  wire        rom_ddr_rdy,
    input  wire [63:0] rom_ddr_q,
    // ---- DAC-rate clock enable (Phase 8a item 1, SYNTH-REFACTOR-PLAN §0/§3):
    //      one pulse per output SAMPLE SLOT at the DAC frame rate (31250 Hz for
    //      DCS1; midway/dcs.cpp:2028 external-clock sample_period = 1/31250 s).
    //      This is the ONLY rate anchor for the autobuffer drain: the drain no
    //      longer counts retired instructions (the old ab_countdown 320*count
    //      proxy is GONE). The core accumulates dac_ce_in pulses and fires one
    //      buffer-half drain every `count` (= ab_size/(2*incs)) slots -- exactly
    //      as MAME batches m_size/(2*m_incs) samples per dcs_irq callback
    //      (dcs.cpp:1968, period = sample_period*count, dcs.cpp:2036-2039).
    //      Because the trigger is DAC-clock-anchored, not CPU-cycle-anchored,
    //      the producer/consumer margin (§0 crux: >=40000 instrs) is preserved
    //      BY CONSTRUCTION at any core:DAC clock ratio -- silicon-safe. On the
    //      board a divider off the audio clock generates it; in sim the TB
    //      derives it from the same cadence the old countdown produced (Gate 1
    //      stays bit-identical) and can perturb it to re-prove the §0 margin.
    input  wire        dac_ce_in,
    output reg  [13:0] o_ppc,     // address of instruction just executed
    output reg         o_valid,   // strobes once per retired instruction
    output reg         o_unimpl,  // set when an opcode class isn't handled yet
    // ---- DAC output (N17): the autobuffer drain emits each drained s16 sample
    //      here (mono, DCS1 m_channels=1). dac_ce strobes for one clock per
    //      emitted sample; dac_sample holds the little-endian s16 value. In sim
    //      the TB writes these to dut.pcm for the F19 gate; in synth they drive
    //      the MiSTer mono DAC.
    output reg  [15:0] dac_sample,
    output reg         dac_ce
);
    // ---- memories (Phase 1: behind the dcs_mem shim) -----------------------
    // PM/DM/ROM now live in the dcs_mem instance below; the CPU reaches them via
    // combinational request/response nets (RD_LATENCY=0 = async drop-in) and
    // registered write ports. See dcs_mem.sv.
    // ---- register file (MAME reg_grp layout) -------------------------------
    // grp0 index 0..15: AX0 AX1 MX0 MX1 AY0 AY1 MY0 MY1 SI SE AR MR0 MR1 MR2 SR0 SR1
    // N14 (SYNTH-REFACTOR Phase 4): BOTH core banks live in ONE 32-entry file
    // indexed {bnk, idx}, bnk = MSTAT bit0 (secondary-register-bank select,
    // 2100ops.hxx:70 MSTAT_BANK). The old 16-way physical swap in set_mstat is
    // gone -- writing MSTAT retargets every subsequent read/write through the
    // `G0 accessor below (one flop toggles instead of 16 copies).
    reg [15:0] gr [0:31];
    // The hardware wrapper uses a 1-in-2 enable at clk_sys (40 MHz effective
    // at the fitted 80 MHz system clock). Standalone regression builds leave
    // CORE_CE_EN=0, preserving their instruction-per-clock behavior exactly.
    wire cpu_ce = (CORE_CE_EN != 0) ? core_ce : 1'b1;
    reg [15:0] iR [0:7];          // I0..I7
    reg [15:0] mR [0:7];          // M0..M7 (signed)
    reg [15:0] lR [0:7];          // L0..L7 (modulo length; 0 => linear)
    // circular-addressing support (2100ops.hxx:333-341): every I write re-bases
    // base=i&lmask; every L write recomputes lmask=mask_table[l] (adsp2100.cpp:
    // 1089-1106) and re-bases. modify (2100ops.hxx:557-566): i=(i+m)&0x3fff;
    // if (i<base) i+=l; else if (i>=base+l) i-=l.
    reg [13:0] baseR [0:7];       // m_base
    reg [13:0] lmask [0:7];       // m_lmask
    reg [15:0] astat, mstat, sstat, imask, icntl, px;
    // N14: the non-g0 banked core registers keep BOTH banks as 2-entry files
    // indexed by the same active-bank pointer (MAME's set_mstat swaps the whole
    // adsp_core incl. AF/MF/SB and the mr union top half).
    reg [15:0] afb  [0:1];        // ALU feedback register (not in g0), banked
    reg [15:0] mfb  [0:1];        // MAC feedback register, banked
    reg [15:0] sbb  [0:1];        // SB, banked
    // hidden top 16 bits of the 64-bit MR accumulator (adsp2100.h:322-332: the
    // adsp_mac union keeps mr as uint64 {mrzero,mr2,mr1,mr0}; accumulate uses the
    // FULL 64-bit value and MR2 reads back res[47:32], not a 40-bit sign-extension)
    reg [15:0] mrzb [0:1];        // banked (adsp_core replicates mr)
    // ---- N14 active-bank pointer + accessors --------------------------------
    // Every read AND write of a banked register indexes by bnk; a MSTAT write
    // (set_mstat) just changes mstat[0]. Same-clock semantics are identical to
    // the physical swap: no instruction both toggles the bank and touches a
    // banked register in the same clock (callers of set_mstat -- 0x0C mode ctl,
    // MSTAT reg-move/imm/DM-load writes, RTI status restore -- write none of
    // g0/AF/MF/SB/MR in that clock), and all reads in the toggling clock use
    // the pre-write mstat[0] exactly as they read the pre-swap bank before.
    wire bnk = mstat[0];
    `define G0(i)  gr[{bnk, 4'b0000} + (i)]
    `define AF     afb[bnk]
    `define MF     mfb[bnk]
    `define SBR    sbb[bnk]
    `define MRZ    mrzb[bnk]
    reg [13:0] cntr;
    // DCS memory system: U2-U5 sound ROMs + banked data window (DM 0x2000-0x2FFF).
    // Linear layout = 1 MB per chip, chip select in address bits 20-21 (DCSExplorer
    // DCSDecoder.cpp MakeROMPointer: "on the original DCS boards, it's in bits 20-23",
    // ROM[n-2] = chip U<n>; MAME banks the "dcs" region linearly in 0x1000-word pages,
    // dcs.cpp:774-775 configure_entries + dcs.cpp:925-929 bank select data&0x7ff).
    reg [10:0] data_bank;         // ROM data bank (set by DM($3000)); window=bank*0x1000

    // ---- PM / DM internal BRAM (Phase 8a item 4: co-located with the writer) --
    // Program + data memory are the core's ON-CHIP M10K BRAM. They live HERE (in
    // the CPU), NOT behind the dcs_mem shim, so every write site is a LOCAL
    // synchronous BRAM write. A parent writing a submodule's array by hierarchical
    // name (the former `u_mem.pm[a] <= v`) is accepted by iverilog but is NOT
    // synthesizable (Quartus error 10207 "can't resolve reference to pm"); this is
    // the SYNTH-REFACTOR-PLAN §1e/Phase-6 "formalize the hierarchical writes"
    // step. Read/write SEMANTICS and clocking are byte-identical to the former
    // shim (Gate 1 full-2.6M PC match + F19 bit-exact PCM re-proven after the
    // move). dcs_mem now owns ONLY the external sound ROM (DDR3-shaped rom port +
    // prefetch cache).
    // Phase 8c: PM is DUPLICATED (pm = fetch-read copy, pm2 = data-read copy) so
    // each array has exactly ONE read port -> each maps to a clean 1-write/1-read
    // M10K. The single array had 2 read ports (fetch + pmb) + 4 write addresses,
    // which Quartus could NOT infer as BRAM -> it materialized ~393k flops + 4
    // write decoders = the measured >20 GB quartus_map blowup (shrinking the depth
    // to [0:255] maps in 0.7 GB, pinning the arrays as the cause). Both copies take
    // the identical single consolidated write port below (pm_we/pm_wa/pm_wd).
    (* ramstyle = "no_rw_check, M10K" *) reg [23:0] pm  [0:16383]; // program mem, fetch-read copy
    (* ramstyle = "no_rw_check, M10K" *) reg [23:0] pm2 [0:16383]; // program mem, pmb data-read copy
    (* ramstyle = "no_rw_check, M10K" *) reg [15:0] dm  [0:16383]; // data memory, 16-bit (1W/1R)
    // Pocket shares PM through two physical ports. The FSM only consumes PM-B
    // reads issued in S_MEM/S_DRAIN; writes occur in S_EXEC/S_BOOT. Its read
    // output during a write is unused. SHARED_PM=0 retains the donor layout for
    // cycle-by-cycle differential tests; the unused pm2 is removed in synthesis.
    // single PM write port; set by the former `PM[x]<=y sites.
    reg        pm_we; reg [13:0] pm_wa; reg [23:0] pm_wd;
    reg [13:0] pm_port_b_addr;
    `define PM  pm
    `define DM  dm
    // Fetch read port (Port A): the address is PC itself, so the clocked read
    // `fetch_r <= pm[pc]` samples the CURRENT pc at the FETCH-bubble edge and
    // presents op on the EXEC edge (1-clock BRAM latency, RD_LATENCY=1); async
    // when RD_LATENCY=0 (Phase 0/1 legacy).
    wire [13:0] fetch_addr = pc;
    reg  [23:0] fetch_r;
    // Phase 8c: the RD_LATENCY==0 async-read branch (`pm[fetch_addr]`) is a
    // Phase-0/1 SIM legacy path. Quartus sees it syntactically and refuses to
    // infer `pm` as BRAM ("uninferred due to asynchronous read logic") -> 393k
    // flops. Guard it out of synthesis (which is always RD_LATENCY>=1) so `pm`
    // has ONLY the clocked fetch read -> clean 1W/1R M10K, like pm2/dm.
`ifdef SYNTHESIS
    wire [23:0] fetch_q = fetch_r;
`else
    wire [23:0] fetch_q = (RD_LATENCY == 0) ? pm[fetch_addr] : fetch_r;
`endif
    // Data-side read ports (Port B on PM + the DM port): registered address ->
    // data next clock (addresses driven by the S_MEM pre-decode / S_DRAIN stream
    // via the muxes further down). At most one read per port per clock (see the
    // ONE-READ-ONE-WRITE-PER-PORT AUDIT below).
    wire [13:0] pmb_addr;   reg [23:0] pmb_q;
    wire [13:0] dm_addr;    reg [15:0] dm_q;
    always @(posedge clk) begin
        if (cpu_ce && !EXPLICIT_RAM_CE) begin
            fetch_r <= pm [fetch_addr];  // PM copy A read port (fetch)
            if (!SHARED_PM) pmb_q <= pm2[pmb_addr];
            dm_q    <= dm [dm_addr];     // DM read port
        end
    end
    // Phase-5 DDR3-shaped sound-ROM port (request/latency model, see dcs_mem):
    // the requester (bank-window S_MEM stall, or the S_BOOT stream) holds
    // rom_req with rom_addr stable and waits for rom_rdy; on silicon this
    // port is the real HPS DDR3 read path (Partition C).
    wire        rom_req;
    wire [21:0] rom_addr;
    wire        rom_rdy;
    wire        boot_rom_rdy;
    wire [7:0]  rom_q;
    dcs_mem #(.DDR_LATENCY(DDR_LATENCY), .PF_LINES(PF_LINES),
              .EXT_ROM(EXT_ROM), .CORE_CE_EN(CORE_CE_EN)) u_mem
        (.clk(clk), .rst(rst), .core_ce(cpu_ce),
         .rom_req(rom_req), .rom_boot(boot_active), .rom_addr(rom_addr),
         .rom_rdy(rom_rdy), .rom_q(rom_q),
         .boot_rom_addr(boot_rom_addr24[21:0]), .boot_rom_rdy(boot_rom_rdy),
         .ext_req(rom_ddr_req), .ext_addr(rom_ddr_addr),
         .ext_rdy(rom_ddr_rdy), .ext_q(rom_ddr_q));

    // snd_byte: the linear U2|U3|U4|U5 byte fetch lives in u_mem.rom_byte.
    // Phase 5: the DATAPATH no longer calls this (bank window + S_BOOT go
    // through the DDR3-shaped rom_req/rom_rdy port); the only remaining caller
    // is the S_DRAIN RG_BANK fallback (unreachable, sim-only value keeper).
    function [7:0] snd_byte(input [21:0] idx);
`ifndef SYNTHESIS
        snd_byte = u_mem.rom_byte(idx);   // hierarchical fn call (sim only; Quartus can't resolve)
`else
        snd_byte = 8'hFF;                 // synth: the sole caller (S_DRAIN RG_BANK fallback) is
                                          // UNREACHABLE (the output buffer is RAM, not the ROM
                                          // window) -- a stub value that is never consumed.
`endif
    endfunction

    // ---- sequencer state ---------------------------------------------------
    reg [13:0] pc;
    // ---- Phase 6 (SYNTH-REFACTOR-PLAN §3): explicit instruction FSM ---------
    // Replaces the Phase-2 implicit fetch_ready/mem_stage priority chain with
    // named states. One instruction = S_FETCH -> S_DECODE -> [S_DRAIN ->]
    // [S_DIV ->] [S_ROM ->] [S_MEM ->] S_EXEC (stall states only when owed,
    // dispatched in the baseline priority order). S_BOOT = the Phase-3/5
    // streaming boot DMA (CPU held). IRQ/reset/reboot entry is an FSM branch
    // out of the check states (S_DECODE + every stall state -- the same clock
    // positions the Phase-2 chain evaluated them) back to S_FETCH/S_BOOT.
    localparam [2:0] S_BOOT   = 3'd0,  // boot DMA streaming (boot_active)
                     S_FETCH  = 3'd1,  // present PC to the PM fetch port
                     S_DECODE = 3'd2,  // fetch_q valid: latch op + EA, dispatch
                     S_DRAIN  = 3'd3,  // N19 autobuffer drain stream
                     S_DIV    = 3'd4,  // N20 TX1-arm restoring divider
                     S_ROM    = 3'd5,  // Phase-5 bank-window DDR3 stall
                     S_MEM    = 3'd6,  // clocked-BRAM data-read issue
                     S_EXEC   = 3'd7;  // verbatim one-clock instruction commit
    reg [2:0] state;
    // loop stack
    reg [13:0] loop_end  [0:3];
    reg [3:0]  loop_cond [0:3];
    integer    loop_sp;
    // pc stack (for DO-UNTIL top + CALL return)
    reg [13:0] pc_stack [0:15]; // reference storage: no MLAB attribute
    (* ramstyle = "MLAB, no_rw_check" *) reg [13:0] pc_mem [0:15];
    integer    pc_sp;
    reg pc_push_we;
    reg [31:0] pc_push_addr, pc_last_addr;
    reg [13:0] pc_push_data, pc_last_data;
    reg pc_last_valid;
    // Architectural pushes publish the forwarding payload immediately. A
    // toggle transfers that payload to the MLAB on the next system clock.
    // pc_write_toggle changes only on cpu_ce; pc_written_toggle is full-rate.
    // Even consecutive enabled edges work: the RAM sees the previous payload
    // while forwarding publishes the next one. Reset cancels an owed write.
    reg pc_write_toggle, pc_written_toggle;
    wire [31:0] pc_read_addr = pc_sp - 1;
    wire [13:0] pc_top = MLAB_PC_STACK
                       ? ((pc_last_valid && pc_read_addr == pc_last_addr)
                          ? pc_last_data : pc_mem[pc_read_addr])
                       : pc_stack[pc_read_addr];
    // All push sites are exclusive instruction/IRQ alternatives. Request
    // once and commit through one physical RAM port; forwarding covers the
    // newest element while the MLAB read-during-write output is unspecified.
    task automatic push_pc(input [13:0] value);
        if (MLAB_PC_STACK) begin
            pc_push_we=1'b1; pc_push_addr=pc_sp; pc_push_data=value;
        end else pc_stack[pc_sp] <= value;
    endtask
    // cntr stack
    reg [13:0] cntr_stack [0:3];
    integer    cntr_sp;
    // ---- Phase 7 (§4.2): board-reset input register ------------------------
    // One flop between the async board line and the FSM's boundary check (the
    // standard input synchronizer; also gives the TB's one-clock pulse the same
    // one-clock pipeline the old replay compare had). Replaces reset_ats[].
    reg        host_rst_r;
    // firmware-driven SYSCONTROL soft-reboot (DM($3FFF)=reg with bit9): reload PM
    // from the CURRENT data_bank + reset CPU (does NOT reset the bank).
    reg        reboot_pending;
    reg [10:0] reboot_bank;
    // ---- S_BOOT streaming boot-DMA (SYNTH-REFACTOR Phase 3, N12) ------------
    // Replaces the boot_load() one-clock unrolled for-fill with a streaming
    // DMA (a real ADSP-2105 streams its boot page from serial ROM over many
    // clocks; the one-shot copy of up to 384x24b from DDR3 is un-synthesizable,
    // N12). Phase 5 re-sourced the stream through the DDR3-shaped ROM port:
    // one BYTE per rom_req/rom_rdy handshake (header length byte, then bytes
    // 0/1/2 of each word), stalling for each round trip.
    // load_boot_data unpack (adsp2100.cpp:320): pagelen=(src[3]+1)*8 words;
    // PM[j]={src[4j],src[4j+1],src[4j+2]}. All three boot paths (power-on bank0,
    // SYSCONTROL bit9 reboot, host/watchdog reset) launch it; the CPU is held
    // (no fetch/decode/exec) for the whole stream = the reset-stall a real chip
    // sees while its boot loader runs. Behaviorally identical PM image to the
    // old boot_load (F19 gate proves it).
    reg        boot_active;      // 1 while the boot page is streaming (CPU stalled)
    reg [11:0] boot_idx;         // PM word index being assembled
    reg [11:0] boot_plen;        // page length in words (set by the header byte)
    reg [10:0] boot_bank;        // ROM bank this boot streams from
    reg [1:0]  boot_phase;       // Phase 5: 0 = header byte, 1/2/3 = word byte 0/1/2
    reg [7:0]  boot_b0, boot_b1; // Phase 5: first two bytes of the word in flight
    // interrupt status stack {MSTAT,IMASK,ASTAT}
    // (Phase 7: the captured-IRQ replay arrays irq_at[]/irq_vec[] are GONE --
    //  the GENERATED-interrupt path below is the only source; the TB re-phrases
    //  the captured host IRQ2s as host-port pin writes at the same counts.)
    reg [15:0] stat_mstat [0:15];
    reg [15:0] stat_imask [0:15];
    reg [15:0] stat_astat [0:15];
    integer    stat_sp;
    // Only interrupt entry writes the status stack. Keep the old arrays as
    // the reference variant; the Pocket variant has one 48-bit write/read
    // port and forwards the newest push across an MLAB write collision.
    (* ramstyle = "MLAB, no_rw_check" *) reg [47:0] status_mem [0:15];
    reg [31:0] status_last_addr;
    reg [47:0] status_last_data;
    reg status_last_valid;
    wire [31:0] status_read_addr = stat_sp - 1;
    wire [47:0] status_top = (status_last_valid && status_read_addr == status_last_addr)
                           ? status_last_data : status_mem[status_read_addr];


    // ---- Phase 7 (§4.1): on-chip TIMER --------------------------------------
    // Control regs are memory-mapped at DM 0x3FE0-0x3FFF (dcs.cpp control-reg
    // enum: TIMER_SCALE_REG=0x3ffb, TIMER_COUNT_REG=0x3ffc, TIMER_PERIOD_REG=
    // 0x3ffd, dcs.cpp:213-215). Real-silicon registers -> live flop shadows
    // (same pattern as ctl_s1_autobuf); the DM array keeps the raw mirror
    // (adsp_control_w first stores m_control_regs[offset]=data, dcs.cpp:1868).
    //   scale  (dcs.cpp:1923-1925): effective scale = (data & 0xff) + 1
    //   count  (dcs.cpp:1933-1935): m_timer_start_count = data, restart
    //   period (dcs.cpp:1938-1944): reload value
    // Enable = MSTAT bit5 (MSTAT_TIMER=0x20, 2100ops.hxx:74). MAME routes every
    // MSTAT-write path through update_mstat (2100ops.hxx:79-94), whose
    // enable-change callback drives dcs timer_enable_callback (dcs.cpp:1787-
    // 1806, wired dcs.cpp:2458) -> "runs while mstat[5]" is equivalent.
    // Cadence: first underflow after scale*(count+1) CPU cycles (reset_timer,
    // dcs.cpp:1783), then every scale*(period+1) (internal_timer_callback,
    // dcs.cpp:1727-1732). This instruction-atomic model proxies cycles with
    // retired instructions (same proxy as the ab_period=320*count drain model);
    // exact for the F19 gates because the timer is INERT for UMK3 (MAME
    // m_timer_ignore via the DRAM-refresh-stub check, dcs.cpp:1752-1768; IMASK
    // bit0 measured 0 throughout the window) -- enforced by the sim-only
    // ISR-entry cross-check counters below.
    // Underflow -> EDGE pulse on the ADSP timer line (dcs.cpp:1734-1736
    // ASSERT+CLEAR "the IRQ line is edge triggered") -> m_irq_latch[TIMER],
    // consulted by check_irqs with NO level/ICNTL mux (adsp2100.cpp:995-997),
    // lowest priority (indx 5); latch cleared ONLY when the vector is taken
    // (generate_irq, adsp2100.cpp:906) -- a masked underflow stays pending.
    reg [8:0]  tim_scale;       // live (data&0xff)+1 shadow of DM($3FFB)
    reg [15:0] tim_count;       // live down-counter (start = DM($3FFC) write)
    reg [15:0] tim_period;      // live reload shadow of DM($3FFD)
    reg [8:0]  tim_scale_cnt;   // prescaler: instrs left in the current scale group
    reg        tim_irq_latch;   // edge latch (m_irq_latch[ADSP2101_TIMER])
`ifndef SYNTHESIS
    // Phase-7 coverage cross-check (task: "assert its ISR entry count == what
    // MAME's trace implies, or 0 if never fired"): MAME's golden window has ZERO
    // vector-0x18 entries (irq_from_ref histogram = {0x04:2} only; m_timer_ignore
    // set for UMK3). The TB reports these at $finish and aborts if isr != 0.
    integer tim_fire_count   = 0;   // underflow pulses (latch sets)
    integer tim_isr_entries  = 0;   // vector-0x18 takes
    reg     tim_enabled_ever = 0;   // any retired instr with MSTAT bit5 set
`endif

    // ---- SPORT1 autobuffer (audio output DMA) ------------------------------
    // Additive: arms on a TX1 write (wr_reg grp3 idx 0xB) when SYSCONTROL bit11 +
    // S1_AUTOBUF bit1 are set (dcs.cpp sound_tx_callback); a periodic drain then
    // advances I<ireg> by count*incs each tick (dcs.cpp dcs_irq), which is what
    // lets the firmware's `I7 < AY0` output-buffer wait-loop fall through.
    // Control regs (0x3FEF S1_AUTOBUF, 0x3FFF SYSCONTROL) already live in dm[].
    reg        ab_active;
    reg [2:0]  ab_ireg;                 // I register the buffer pointer lives in
    reg [15:0] ab_base, ab_size, ab_incs;
    // Phase 8a item 1: DAC-rate drain trigger (replaces the ab_period/ab_countdown
    // retired-instruction countdown). dac_slot_ctr counts DOWN one per dac_ce_in
    // sample slot; on reaching the last slot of a buffer-half it reloads to
    // `count` (ab_drain_cnt) and sets dac_slot_go = "a drain is due". drain_pend
    // then dispatches S_DRAIN and the S_EXEC commit clears dac_slot_go -- the
    // drain EVENT (S_DRAIN stream, IRQ1-on-wrap, commit ordering) is unchanged;
    // only its TRIGGER moved from instruction-count to the DAC clock enable.
    reg [15:0] dac_slot_ctr;            // sample slots remaining until the next drain
    reg        dac_slot_go;             // set when a buffer-half of slots has elapsed
    reg [15:0] ab_cfg;                  // scratch: S1_AUTOBUF snapshot
    integer    ab_ir, ab_mr, ab_lr, ab_cnt, ab_reg; // scratch
    // ---- host input latch + IRQ2 / IRQ1 state ------------------------------
    // dcs.cpp:1503-1520 dcs_delayed_data_w: a host byte write sets the ADSP IRQ2
    // line (level) + latches m_input_data. dcs.cpp:789: DCS1 auto-acks, so the
    // firmware's read of DM($3400) clears the line (input_latch_ack_w 1544-1552).
    // The CPU-side edge latch (adsp2100.cpp:1164-1171, set on CLEAR->ASSERT) is
    // kept too; check_irqs muxes level/latch on ICNTL (adsp2100.cpp:970-991).
    // UMK3 firmware writes ICNTL=0 (level mode) + IMASK=$20 (IRQ2-only) per the
    // dasm; both modes implemented per gospel.
    reg [15:0] input_data;   // m_input_data (dcs.cpp:1519)
    reg        irq2_line;    // ADSP2105_IRQ2 level
    reg        irq2_latch;   // CPU edge latch (cleared only by generate_irq, adsp2100.cpp:897)
    // ---- host mailbox latch-control + output latch (Phase 8a item 2) ----------
    // m_latch_control (dcs.cpp:174-187): bit11 (0x800)=INPUT_EMPTY, bit10 (0x400)=
    // OUTPUT_EMPTY -- a SET bit means the corresponding latch is EMPTY. Both set
    // (0x0C00) at reset (SET_INPUT_EMPTY+SET_OUTPUT_EMPTY, dcs.cpp:585-586). The
    // host polls it verbatim on mk3 (control_r default, dcs.cpp:1452). This is
    // pure host-visible mailbox status -- the ADSP never reads it, so it CANNOT
    // perturb the instruction stream or the audio (Gate 1 / Gate 2 unaffected).
    reg [15:0] latch_control; // m_latch_control
    reg [15:0] output_data;   // m_output_data (DCS->host response latch)
    assign host_status_r   = latch_control;
    assign host_response_r = output_data;
    // dcs.cpp:1984-1991: on autobuffer wrap MAME pulses IRQ1 (pulse_input_line,
    // minimum-quantum width). Modeled as a single-boundary-check pulse: taken at
    // the next instruction boundary if unmasked (IMASK bit2 = 0x20>>3 per
    // adsp2100.cpp:893 with indx=3), lost otherwise (level mode, ICNTL=0 -> the
    // transient line is gone and the unused edge-latch is never consulted).
    reg        irq1_pulse;

    // PCM emission: each drain reads the count samples from DM BEFORE advancing
    // I<ireg> (dcs.cpp dcs_irq 1966-1976: buffer[i]=m_data->read_word(reg); reg+=m_incs)
    // and emits them little-endian s16 to dut.pcm (the DAC stream for dcs_diff.py).
    integer    ab_i;                    // drain read-loop index
    reg [15:0] ab_smp;                  // drained sample
    // N17 DAC-port burst buffer: the one-clock drain fills up to `ab_cnt` samples;
    // the TB reads dac_emit_burst[0..dac_burst_len-1] on the dac_ce strobe and
    // writes them to dut.pcm (the F19 gate) instead of the DUT owning the file.
    // (Later phases stream the burst over N clocks with one dac_ce per sample.)
    reg [15:0] dac_emit_burst [0:511];
    integer    dac_burst_len;

    localparam [13:0] NO_LOOP = 14'h3FFF; // sentinel: no active loop end

    // ======================================================================
    // Phase 2 (SYNTH-REFACTOR-PLAN §6 Phase 2): clocked-BRAM data side.
    // ======================================================================
    // Control-register live shadows: the TX1-arm path (wr_reg grp3 idx 0xB)
    // reads DM($3FEF) S1_AUTOBUF and DM($3FFF) SYSCONTROL in the SAME clock it
    // executes -- two extra DM reads that would violate one-read-per-port with
    // clocked BRAM. These are the SPORT1/SYSCONTROL memory-mapped CONTROL
    // registers (dcs.cpp adsp_control_r/w) -- registers in real silicon -- so
    // they get live flop shadows written by dm_write alongside the DM array
    // (which keeps holding them for ordinary DM reads). Coherent by
    // construction: dm_write is the only DM-proper writer, both init to 0
    // with the DM array, and resets clear neither DM nor the shadows.
    reg [15:0] ctl_s1_autobuf;   // shadow of DM($3FEF)
    reg [15:0] ctl_syscontrol;   // shadow of DM($3FFF)

    // ---- DM-space region decode (dcs_8k data map, dcs.cpp:317-320) ----------
    localparam [1:0] RG_DM = 2'd0, RG_ALIAS = 2'd1, RG_BANK = 2'd2, RG_LATCH = 2'd3;
    function [1:0] dm_region(input [15:0] a);
        begin
            if      (a >= 16'h0800 && a <= 16'h1fff) dm_region = RG_ALIAS; // PM[23:8] alias
            else if (a >= 16'h2000 && a <= 16'h2fff) dm_region = RG_BANK;  // banked ROM window
            else if (a >= 16'h3400 && a <= 16'h3403) dm_region = RG_LATCH; // host input latch
            else                                     dm_region = RG_DM;
        end
    endfunction

    // ---- pre-decode of THIS instruction's data-memory access -----------------
    // Combinational over fetch_q + the DAG registers (all stable from the last
    // EXEC commit until the next). Mirrors, opcode-class by opcode-class, the
    // address/direction each verbatim EXEC-body site computes; a SIM-only
    // cross-check at the EXEC consumption sites aborts loudly on any mismatch
    // (a truncated PC stream fails the Gate-1 diff -- no silent divergence).
    reg         pre_dm_rd, pre_dm_wr, pre_pm_rd;
    reg  [15:0] pre_addr;      // DM-space address (dm_read/dm_write sites)
    reg  [13:0] pre_pm_addr;   // PM-space word address (0x11/0x50-5F data reads)
    always @* begin
        pre_dm_rd = 1'b0; pre_dm_wr = 1'b0; pre_pm_rd = 1'b0;
        pre_addr = 16'h0; pre_pm_addr = 14'h0;
        casez (fetch_q[23:16])
          8'h11:                                       // shift + PM(I,M) DAG2
              if (!fetch_q[15]) begin                  //   read variant only
                  pre_pm_rd   = 1'b1;
                  pre_pm_addr = iR[{1'b1, fetch_q[3:2]}][13:0];
              end
          8'h12, 8'h13: begin                          // shift + DM(I,M) DAG1/2
              pre_addr = dag_addr({fetch_q[16], fetch_q[3:2]});
              if (fetch_q[15]) pre_dm_wr = 1'b1; else pre_dm_rd = 1'b1;
          end
          8'b0101_????:                                // 0x50-5F ALU/MAC + PM(I,M)
              if (!fetch_q[19]) begin                  //   read variant only
                  pre_pm_rd   = 1'b1;
                  pre_pm_addr = iR[{1'b1, fetch_q[3:2]}][13:0];
              end
          8'b011?_????: begin                          // 0x60-7F ALU/MAC + DM(I,M)
              pre_addr = dag_addr({fetch_q[20], fetch_q[3:2]});
              if (fetch_q[19]) pre_dm_wr = 1'b1; else pre_dm_rd = 1'b1;
          end
          8'b100?_????: begin                          // 0x80-9F DM(imm) r/w
              pre_addr = {2'b0, fetch_q[17:4]};
              if (fetch_q[20]) pre_dm_wr = 1'b1; else pre_dm_rd = 1'b1;
          end
          8'b101?_????: begin                          // 0xA0-BF DM(I,M)=imm
              pre_addr  = dag_addr({fetch_q[20], fetch_q[3:2]});
              pre_dm_wr = 1'b1;
          end
          default: ;                                   // no data-memory access
        endcase
    end
    wire [1:0] pre_region = dm_region(pre_addr);
    wire       pre_bank_rd = pre_dm_rd && (pre_region == RG_BANK);
    // MEM wait states this instruction owes before EXEC:
    //   0 = none (reg/control ops, input-latch reads, plain DM/PM writes)
    //   1 = one clocked BRAM read (DM read, alias read, PM-data read, or the
    //       PM-alias write's RMW pre-read -- §2b OPEN RISK 1, 2-clock RMW)
    // Banked-ROM window reads are NOT counted here (Phase 5): they stall on
    // the rom_rdy handshake instead -- a VARIABLE-latency DDR3 round trip
    // through the prefetch cache (see the rom-stall branch in the main FSM).
    wire [1:0] mem_need =
        ((pre_dm_rd && pre_region != RG_LATCH && pre_region != RG_BANK) ||
         (pre_dm_wr && pre_region == RG_ALIAS) || pre_pm_rd)   ? 2'd1 : 2'd0;

    // ---- Phase 6: S_DECODE latches -------------------------------------------
    // The pre-decode above is combinational over fetch_q (stable for the whole
    // instruction: the fetch port keeps re-reading pm[pc] and pc only moves at
    // EXEC). S_DECODE registers the opcode + the memory pre-decode so every
    // post-DECODE state (the address muxes, the stall dispatch, S_EXEC's body
    // and its cross-checks) runs off FLOPS, not off fetch_q fan-out -- the §1e
    // pipeline-shape fix. Latched values == the comb pre-decode by construction
    // (nothing they depend on changes between DECODE and EXEC); the S_EXEC
    // op-latch cross-check aborts loudly on any violation.
    reg [23:0] op_r;        // latched instruction word (== fetch_q)
    reg [5:0] generic_read_select_r; // instruction-only decode, available before EXEC
    reg [15:0] ea_addr_r;   // latched DM-space effective address
    reg [13:0] pm_addr_r;   // latched PM-data word address (0x11/0x50-5F reads)
    reg        pm_rd_r;     // PM-data read (port B) this instruction
    reg        bank_rd_r;   // banked-ROM window read this instruction
    reg        tx1_r;       // TX1 write (divider owed) this instruction
    reg [1:0]  mem_need_r;  // latched S_MEM requirement

    // ---- N20: TX1-arm pre-decode + sequenced restoring divider ---------------
    // The autobuffer arm computes count = size/(2*incs) (dcs.cpp:1968 drain
    // count m_size/(2*m_incs); dcs.cpp:2036-2039 period, m_channels=1) with a
    // runtime variable divisor -- a variable '/' does not synthesize. Chosen
    // plan = SYNTH-REFACTOR-PLAN N20 option (b): a 16-step restoring divider
    // runs in dedicated stall clocks BEFORE the TX1-write instruction's EXEC,
    // detected by the pre-decode below (the same stall pattern as S_MEM).
    // Stall clocks retire no instruction, so the drain cadence (ab_countdown
    // counts RETIRED instructions) and the Gate-1 PC stream are bit-identical.
    // The gospel-cited division stays, verbatim, as a sim-only cross-check at
    // both consumption sites (abort-loudly, Phase-2 style). The DRAIN-site
    // division is eliminated entirely: ab_size/ab_incs are written ONLY by the
    // arm, so the arm-time quotient (ab_drain_cnt) equals ab_size/(2*incs) by
    // construction and S_DRAIN just reuses it.
    // wr_reg(grp3, idx 0xB) is reachable from exactly three opcode classes:
    wire pre_tx1_wr =
        (fetch_q[23:16] == 8'h0D &&
         fetch_q[11:10] == 2'd3  && fetch_q[7:4] == 4'hB) ||  // 0x0D reg-to-reg move
        (fetch_q[23:20] == 4'h3  &&
         fetch_q[19:18] == 2'd3  && fetch_q[3:0] == 4'hB) ||  // 0x30-3F load reg imm
        (fetch_q[23:21] == 3'b100 && !fetch_q[20] &&
         fetch_q[19:18] == 2'd3  && fetch_q[3:0] == 4'hB);    // 0x80-8F reg = DM(imm)
    // divider operands, decoded from the live S1_AUTOBUF shadow exactly as the
    // arm does (ireg = cfg[11:9]; mreg = {cfg[11], cfg[8:7]}; lreg = ireg) --
    // stable across the stall clocks (nothing executes, nothing writes ctl/DAG)
    wire [2:0]  pre_ab_lr   = ctl_s1_autobuf[11:9];
    wire [2:0]  pre_ab_mr   = {ctl_s1_autobuf[11], ctl_s1_autobuf[8:7]};
    wire [15:0] pre_ab_incs = (mR[pre_ab_mr] == 16'h0) ? 16'h1 : mR[pre_ab_mr];
    reg         div_done;      // quotient valid; EXEC may proceed
    reg [4:0]   div_i;         // 0 = load operands; 1..16 = one quotient bit/clock
    reg [15:0]  div_q;         // quotient (unsigned, == the baseline '/' result)
    reg [15:0]  div_nd;        // dividend (lR), MSB-first shift-out
    reg [16:0]  div_rem;       // partial remainder (divisor is 17-bit: 2*0xFFFF)
    reg [16:0]  div_v;         // divisor = 2*incs
    reg [17:0]  div_t;         // step scratch (shifted remainder before subtract)
    reg [15:0]  ab_drain_cnt;  // arm-time quotient, reused by S_DRAIN (see above)

    // ---- S_DRAIN stream state (N19): the autobuffer drain's ~240 DM reads ----
    // spread one-per-clock through the clocked ports. Reads are side-effect-
    // free and memory is quiescent while the CPU is stalled, so values/order
    // are EXACTLY the old one-clock burst's; the architectural COMMIT stays in
    // the retiring instruction's EXEC clock (see the drain block there).
    reg        dr_done;        // stream complete; EXEC may commit
    integer    dr_idx;         // cycle j: capture sample j-1, issue read j
    integer    dr_acc;         // address accumulator (baseline ab_reg semantics)
    integer    dr_cnt;         // sample count latched at stream start
    reg [1:0]  dr_region;      // region of the in-flight read
    reg [21:0] dr_rom_a;       // (unreachable) bank-window fallback address
    reg [15:0] dr_smp;         // captured sample
    wire        drain_pend  = ab_active && dac_slot_go;
    // (N20: the old drain_cnt_w runtime division is gone -- S_DRAIN reuses the
    //  arm-time quotient ab_drain_cnt; sim cross-check at the latch site.)
    wire [31:0] dr_cur      = (dr_idx == 0) ? {16'h0, iR[ab_ireg]} : dr_acc;

    // ---- data-port address muxes ---------------------------------------------
    // Phase 6: S_DRAIN owns the ports while streaming; otherwise the S_DECODE
    // LATCHES drive them (the only consumed value is the one present during
    // the S_MEM issue clock -- latched at DECODE, stable through MEM). Garbage
    // addresses on non-issue clocks are harmless (the registered q is only
    // consumed on the clock after a real issue).
    assign pmb_addr = (state == S_DRAIN) ? dr_cur[13:0]
                    : pm_rd_r            ? pm_addr_r
                    :                      ea_addr_r[13:0]; // alias read / alias-write RMW
    assign dm_addr  = (state == S_DRAIN) ? dr_cur[13:0] : ea_addr_r[13:0];
    // ---- Phase 5: DDR3-shaped ROM port request muxes -------------------------
    // S_BOOT owns the port while a boot page streams (header byte, then the 3
    // bytes of each PM word); otherwise a pending bank-window read holds it
    // through its stall until rom_rdy. rom_req is level-held with a stable
    // address; dcs_mem re-serves automatically whenever the address advances
    // (next boot byte) or a preempted request is re-issued after an IRQ.
    wire [23:0] boot_rom_base   = ({13'h0, boot_bank} << 12);
    wire [23:0] boot_rom_addr24 = (boot_phase == 2'd0)
                                ? (boot_rom_base + 24'd3)                    // page-length header
                                : (boot_rom_base + ({12'h0, boot_idx} << 2)  // word base (4 bytes/word)
                                   + {22'h0, boot_phase - 2'd1});            // byte 0/1/2
    // Phase 6: a bank-window request asserts from S_DECODE (comb pre-decode --
    // the latch lands that same edge) and is held via the latch through every
    // later state incl. S_EXEC (the consume clock), exactly the clocks the
    // Phase-2 chain held it via fetch_ready. It drops in S_FETCH -> dcs_mem
    // returns to R_IDLE between instructions, as before. The address is stable
    // across the handoff (latched value == the comb pre-decode).
    assign rom_addr = boot_active ? boot_rom_addr24[21:0]                    // truncates like the old
                    : (state == S_DECODE)
                      ? ({data_bank, 12'h0} + {10'h0, pre_addr[11:0]})       //   reg[21:0] ri
                      : ({data_bank, 12'h0} + {10'h0, ea_addr_r[11:0]});
    assign rom_req  = boot_active
                    | (state == S_DECODE && pre_bank_rd)
                    | ((state == S_DRAIN || state == S_DIV || state == S_ROM ||
                        state == S_MEM   || state == S_EXEC) && bank_rd_r);

    // ---- ASTAT flag bits (adsp2100.h:459-466): SS=0x80 MV=0x40 Q=0x20 AS=0x10
    //      AC=0x08 AV=0x04 AN=0x02 AZ=0x01 ------------------------------------
    function automatic integer cond_true(input [3:0] c);
        reg az, an, av, ac, as, mv;
        begin
            az = astat[0]; an = astat[1]; av = astat[2];
            ac = astat[3]; as = astat[4]; mv = astat[6];
            case (c)
                4'h0: cond_true = az;              // EQ
                4'h1: cond_true = !az;             // NE
                4'h2: cond_true = !((an^av)|az);   // GT
                4'h3: cond_true = (an^av)|az;      // LE
                4'h4: cond_true = an^av;           // LT
                4'h5: cond_true = !(an^av);        // GE
                4'h6: cond_true = av;              // AV
                4'h7: cond_true = !av;             // NOT AV
                4'h8: cond_true = ac;              // AC
                4'h9: cond_true = !ac;             // NOT AC
                4'hA: cond_true = as;              // NEG
                4'hB: cond_true = !as;             // POS
                4'hC: cond_true = mv;              // MV
                4'hD: cond_true = !mv;             // NOT MV
                4'hE: cond_true = 1'bx;            // CE - handled inline (mutates cntr)
                4'hF: cond_true = 1'b1;            // TRUE (always)
            endcase
        end
    endfunction

    // full condition evaluation incl. the CE side effect (2100ops.hxx:304
    // condition(): c==14 -> slow_condition() 316-325: pre-decrement CNTR, >0 =>
    // true, else pop the CNTR stack => false)
    task automatic cond_eval(input [3:0] c, output ct);
        begin
            if (c == 4'hF) ct = 1'b1;
            else if (c == 4'hE) begin
                if ($signed({1'b0,cntr}) - 1 > 0) begin
                    cntr <= cntr - 1'b1;                          ct = 1'b1;
                end else begin
                    cntr <= cntr_stack[cntr_sp-1]; cntr_sp <= cntr_sp - 1; ct = 1'b0;
                end
            end else ct = cond_true(c) ? 1'b1 : 1'b0;
        end
    endtask

    // ---- DAG helpers: mask_table (adsp2100.cpp:1089-1106) + I/L write hooks --
    // Each bit is an independent constant threshold. This is equivalent to
    // the priority chain, without serial selection through fourteen cases.
    function [13:0] mask_fn(input [13:0] l);
        integer mb;
        begin
            for (mb=0;mb<14;mb=mb+1)
                mask_fn[mb] = (l <= (14'h1 << mb));
        end
    endfunction
    task automatic wr_ireg(input [2:0] w, input [15:0] val); // update_i (2100ops.hxx:333-336)
        begin
            iR[w]    <= val;
            baseR[w] <= val[13:0] & lmask[w];
        end
    endtask
    task automatic wr_lreg(input [2:0] w, input [15:0] val); // update_l (2100ops.hxx:338-341)
        begin
            lR[w]    <= val;
            lmask[w] <= mask_fn(val[13:0]);
            baseR[w] <= iR[w][13:0] & mask_fn(val[13:0]);
        end
    endtask
    // bit-reversed addressing (DAG1 only): m_reverse_table = full 14-bit bit
    // reversal (adsp2100.cpp:1064-1086); applied to the ACCESS address when
    // MSTAT_REVERSE (0x02) is set (2100ops.hxx:70, 583-586/608-611); the
    // post-modify always runs on the raw (un-reversed) I value.
    function [13:0] rev14(input [13:0] a);
        integer j;
        for (j = 0; j < 14; j = j + 1) rev14[j] = a[13-j];
    endfunction
    // effective DM address for an indirect access through I<w>
    function [15:0] dag_addr(input [2:0] w);
        if (!w[2] && mstat[1]) dag_addr = {2'b0, rev14(iR[w][13:0])}; // DAG1 + BIT_REV
        else                   dag_addr = iR[w];
    endfunction

    // post-modify with wraparound (2100ops.hxx:557-566 modify_address / the
    // equivalent inline update in every dag read/write accessor)
    task automatic dag_modify(input [2:0] w, input [2:0] m);
        reg [13:0] i2;
        begin
            i2 = (iR[w][13:0] + mR[m][13:0]) & 14'h3fff;
            if (i2 < baseR[w])                        i2 = i2 + lR[w][13:0];
            else if (i2 >= (baseR[w] + lR[w][13:0]))  i2 = i2 - lR[w][13:0];
            iR[w] <= {2'b0, i2};
        end
    endtask

    // Blocking request selectors only; the selected operation is committed
    // once at the end of S_EXEC. Each opcode requests at most one generic
    // register write and one DAG update. This preserves the existing NBA
    // priorities, while avoiding a separate copy of the write decoder and
    // modulo-address arithmetic at every opcode call site.
    reg exec_reg_we, exec_dag_we, exec_dm_we;
    reg [15:0] exec_dm_addr, exec_dm_data;
    reg [1:0] exec_reg_group;
    reg [3:0] exec_reg_index;
    reg [15:0] exec_reg_data;
    reg [2:0] exec_dag_index, exec_dag_modifier;
    task automatic request_dag_modify(input [2:0] w, input [2:0] m);
        if (SHARED_EXEC) begin
            exec_dag_we=1'b1; exec_dag_index=w; exec_dag_modifier=m;
        end else dag_modify(w,m);
    endtask
    task automatic request_reg_write(input [1:0] grp, input [3:0] idx, input [15:0] val);
        if (SHARED_EXEC) begin
            exec_reg_we=1'b1; exec_reg_group=grp; exec_reg_index=idx; exec_reg_data=val;
        end else wr_reg(grp,idx,val);
    endtask

    // DM stores are exclusive opcode alternatives. Capture their operands
    // at the original call site, before any parallel ALU/shift writeback,
    // and share the address decoder, aliases, mailbox and timer write logic.
    task automatic request_dm_write(input [15:0] addr, input [15:0] val);
        if (SHARED_EXEC) begin
            exec_dm_we=1'b1; exec_dm_addr=addr; exec_dm_data=val;
        end else dm_write(addr,val);
    endtask

    // ---- register write via (group,index), per MAME reg_grp ----------------
    task automatic wr_reg(input [1:0] grp, input [3:0] idx, input [15:0] val);
        reg [2:0] dag_index;
        begin
            if (SHARED_DAG_WRITE && (grp == 2'd1 || grp == 2'd2)) begin
                // Groups 1/2 differ only by the high register-bank bit. One
                // I/M/L decoder and one base/mask calculation serves both.
                dag_index = {grp[1],idx[1:0]};
                case (idx[3:2])
                    2'd0: wr_ireg(dag_index,{2'b0,val[13:0]});
                    2'd1: mR[dag_index] <= {{2{val[13]}},val[13:0]};
                    2'd2: wr_lreg(dag_index,{2'b0,val[13:0]});
                    default: ; // overlays/reserved: same no-op as the donor
                endcase
            end else case (grp)
              // grp0 special cases per write_reg0 (2100ops.hxx:349-370):
              //   SE  (idx 9): (int8_t)val  -> sign-extended low byte
              //   MR1 (idx C): also MR2 = (int16_t)val >> 15 (sign fill)
              //   MR2 (idx D): (int8_t)val  -> sign-extended low byte
              2'd0: case (idx)
                      4'h9: `G0(9)  <= {{8{val[7]}}, val[7:0]};
                      4'hC: begin `G0(12) <= val; `G0(13) <= {16{val[15]}}; end
                      4'hD: `G0(13) <= {{8{val[7]}}, val[7:0]};
                      default: `G0(idx) <= val;
                    endcase
              // write_reg1/write_reg2 (2100ops.hxx:372-395): I = val&0x3fff (+update_i),
              // M = sext(val,14), L = val&0x3fff (+update_l)
              2'd1: case (idx) // I0-3,M0-3,L0-3,-,-,PMOVLAY,DMOVLAY
                      4'd0,4'd1,4'd2,4'd3: wr_ireg(idx[2:0], {2'b0, val[13:0]});
                      4'd4,4'd5,4'd6,4'd7: mR[idx-4]      <= {{2{val[13]}}, val[13:0]};
                      4'd8,4'd9,4'd10,4'd11: wr_lreg(idx[2:0], {2'b0, val[13:0]}); // L0..L3
                      default: ; // PMOVLAY/DMOVLAY: overlay regs (later increment)
                    endcase
              2'd2: case (idx) // I4-7,M4-7,L4-7
                      4'd0,4'd1,4'd2,4'd3: wr_ireg(idx[2:0]+3'd4, {2'b0, val[13:0]});
                      4'd4,4'd5,4'd6,4'd7: mR[idx]        <= {{2{val[13]}}, val[13:0]}; // M4..M7
                      4'd8,4'd9,4'd10,4'd11: wr_lreg(idx[2:0]+3'd4, {2'b0, val[13:0]}); // L4..L7
                      default: ;
                    endcase
              2'd3: case (idx) // ASTAT MSTAT SSTAT IMASK ICNTL CNTR SB PX ...
                      4'd0: astat <= val;
                      4'd1: set_mstat(val);   // may swap register bank
                      4'd2: sstat <= val;
                      4'd3: imask <= val;
                      4'd4: icntl <= val;
                      4'd5: begin // CNTR write: push cntr stack, then load (wr_cntr)
                              cntr_stack[cntr_sp] <= cntr; cntr_sp <= cntr_sp + 1;
                              cntr <= val[13:0];
                            end
                      4'd6: `SBR <= val;
                      4'd7: px <= val;
                      4'hD: cntr <= val[13:0];  // OWRCNTR: overwrite CNTR, NO stack push
                                                // (write_reg3 case 0x0d, 2100ops.hxx:491;
                                                // the decoder's run-length path uses it:
                                                // 099C-099E AY0=CNTR / AR=AY0-1 / OWRCNTR=AR)
                      4'hF: begin               // TOPPCSTACK write (write_reg3 case 0x0f)
                              push_pc(val[13:0]); pc_sp <= pc_sp + 1;
                            end
                      4'hB: begin // TX1 (SPORT1 transmit): arm autobuffer (dcs.cpp sound_tx_callback)
                              // Phase 2: read the live control-reg SHADOWS (same values as
                              // the DM array; see ctl_* decl) -- avoids two same-clock DM
                              // BRAM reads inside one instruction.
                              ab_cfg = ctl_s1_autobuf;                // S1_AUTOBUF reg
                              if ((ctl_syscontrol & 16'h0800) &&      // SYSCONTROL bit11: SPORT1 enable
                                  (ab_cfg       & 16'h0002)) begin   // S1_AUTOBUF bit1: autobuffer enable
                                  ab_ir = (ab_cfg >> 9) & 7;                              // ireg
                                  ab_mr = ((ab_cfg >> 7) & 3) | (((ab_cfg >> 9) & 7) & 4);// mreg (msb from ireg)
                                  ab_lr = (ab_cfg >> 9) & 7;                              // lreg = ireg
                                  iR[ab_ir]    <= iR[ab_ir] & 16'hFFF0;  // source &= ~0xf (first-sample guard)
                                  // set_state_int(I) re-bases the DAG (adsp2100.cpp:744-753 -> update_i)
                                  baseR[ab_ir] <= (iR[ab_ir][13:0] & 14'h3FF0) & lmask[ab_ir];
                                  ab_base      <= iR[ab_ir] & 16'hFFF0;
                                  ab_size      <= lR[ab_lr];
                                  ab_incs      <= mR[ab_mr];
                                  ab_ireg      <= ab_ir[2:0];
                                  // N20: count = size/(2*incs) (dcs.cpp:1968/2036-2039).
                                  // Quotient comes from the sequenced restoring divider
                                  // that ran in the pre-EXEC stall clocks (div_q); the
                                  // gospel division below is the sim-only cross-check.
                                  ab_cnt        = div_q;
                                  ab_drain_cnt <= div_q;   // S_DRAIN reuses this (ab_size/ab_incs only change here)
`ifndef SYNTHESIS
                                  if (!div_done ||
                                      div_q != (lR[ab_lr] / (2 * ((mR[ab_mr]==16'h0)?1:mR[ab_mr])))) begin
                                      $display("FATAL: N20 arm divider mismatch pc=%04x done=%b q=%04x expect=%0d",
                                               pc, div_done, div_q,
                                               lR[ab_lr] / (2 * ((mR[ab_mr]==16'h0)?1:mR[ab_mr])));
                                      $finish;
                                  end
`endif
                                  // Phase 8a item 1: prime the DAC-slot counter to
                                  // a full buffer-half (`count` slots). The first
                                  // drain fires after `count` dac_ce_in pulses; the
                                  // TB phases dac_ce_in so that lands on the exact
                                  // retired instruction the old 320*count countdown
                                  // fired at (Gate 1 = MAME boot PC stream). H9: on
                                  // a re-arm coinciding with a due drain, this arm
                                  // is LEXICALLY LATER than the S_EXEC drain-commit
                                  // block, so the re-primed counter/flag WIN.
                                  dac_slot_ctr <= ab_cnt[15:0];
                                  dac_slot_go  <= 1'b0;
                                  ab_active    <= 1'b1;
                              end
                            end
                      default: ;
                    endcase
            endcase
        end
    endtask

    function automatic [15:0] rd_reg(input [1:0] grp, input [3:0] idx);
        begin
            case (grp)
              2'd0: rd_reg = `G0(idx);
              2'd1: case (idx)
                      4'd0,4'd1,4'd2,4'd3: rd_reg = iR[idx];
                      4'd4,4'd5,4'd6,4'd7: rd_reg = mR[idx-4];
                      4'd8,4'd9,4'd10,4'd11: rd_reg = lR[idx-8];
                      default: rd_reg = 16'h0;
                    endcase
              2'd2: case (idx)
                      4'd0,4'd1,4'd2,4'd3: rd_reg = iR[idx+4];
                      4'd4,4'd5,4'd6,4'd7: rd_reg = mR[idx];
                      4'd8,4'd9,4'd10,4'd11: rd_reg = lR[idx-4];
                      default: rd_reg = 16'h0;
                    endcase
              2'd3: case (idx)
                      4'd0: rd_reg = astat; 4'd1: rd_reg = mstat;
                      4'd2: rd_reg = sstat; 4'd3: rd_reg = imask;
                      4'd4: rd_reg = icntl; 4'd5: rd_reg = {2'b0,cntr};
                      4'd6: rd_reg = `SBR;    4'd7: rd_reg = px;
                      default: rd_reg = 16'h0;
                    endcase
            endcase
        end
    endfunction

    // A generic move or store reads at most one register. ALU/MAC/shifter
    // operands are independent ports; this selector only merges the eight
    // mutually exclusive generic rd_reg call sites below, before writeback.
    function automatic [5:0] shared_reg_read_select(input [23:0] instruction);
        reg [7:0] opcode_hi;
        reg [1:0] read_group;
        reg [3:0] read_index;
        begin
            opcode_hi = instruction[23:16];
            if (opcode_hi == 8'h0D) read_group = instruction[9:8];
            else if (opcode_hi[7:5] == 3'b100) read_group = instruction[19:18];
            else read_group = 2'd0;
            if (opcode_hi == 8'h0D || opcode_hi == 8'h10 ||
                opcode_hi[7:3] == 5'b00101 || opcode_hi[7:5] == 3'b100)
                read_index = instruction[3:0];
            else read_index = instruction[7:4];
            shared_reg_read_select = {read_group,read_index};
        end
    endfunction

    // ---- ALU (per MAME 2100ops.hxx). ASTAT: AZ=b0 AN=b1 AV=b2 AC=b3 AS=b4 ----
    function [15:0] alu_xread(input [2:0] xi); // {AX0 AX1 AR MR0 MR1 MR2 SR0 SR1}
        case (xi)
          3'd0: alu_xread=`G0(0);  3'd1: alu_xread=`G0(1);
          3'd2: alu_xread=`G0(10); 3'd3: alu_xread=`G0(11);
          3'd4: alu_xread=`G0(12); 3'd5: alu_xread=`G0(13);
          3'd6: alu_xread=`G0(14); 3'd7: alu_xread=`G0(15);
        endcase
    endfunction
    function [15:0] alu_yread(input [1:0] yi); // {AY0 AY1 AF 0}
        case (yi)
          2'd0: alu_yread=`G0(4); 2'd1: alu_yread=`G0(5);
          2'd2: alu_yread=`AF;    2'd3: alu_yread=16'h0;
        endcase
    endfunction
    function [15:0] c_nz(input [15:0] a, input [31:0] r); // N (bit15) + Z
        begin
            c_nz = a;
            if ((r & 32'h0000ffff)==0) c_nz = c_nz | 16'h0001;
            c_nz = c_nz | ((r >> 14) & 16'h0002);
        end
    endfunction
    function [15:0] c_v(input [15:0] a, input [31:0] s, input [31:0] d, input [31:0] r);
        c_v = a | (((s ^ d ^ r ^ (r>>1)) >> 13) & 16'h0004);   // V per MAME CALC_V
    endfunction

    // Phase 8c: PURE combinational ALU result generator (was `task alu_exec`,
    // inlined at 4 sites). Returns {astat_next[31:16], result[15:0]}; the AR/AF
    // writeback split moves to the call sites. Math byte-identical to the task.
    function automatic [31:0] alu_eval(input [3:0] sub, input [15:0] xv, input [15:0] yv);
        reg [16:0] r; reg [15:0] astn; reg cin; reg [31:0] s32,d32,r32;
        reg [16:0] add_a, add_b, add_result; reg add_cin;
        begin
            cin  = astat[3];                  // C flag as 0/1
            astn = astat & ~16'h000F;         // CLR_FLAGS (m_astat_clear = ~0x0F)
            if (SHARED_ALU) begin
                // Keep the 17th bit: subtraction exposes the borrow through
                // r[16], which the flag logic below inverts for AC.
                add_a = {1'b0, xv}; add_b = {1'b0, yv}; add_cin = 1'b0;
                case (sub)
                  4'h1: begin add_a={1'b0,yv}; add_b=17'd0; add_cin=1'b1; end
                  4'h2: add_cin=cin;
                  4'h5: begin add_a=17'd0; add_b=~{1'b0,yv}; add_cin=1'b1; end
                  4'h6,4'h7: begin add_b=~{1'b0,yv}; add_cin=(sub==4'h7) | cin; end
                  4'h8: begin add_a={1'b0,yv}; add_b=17'h1ffff; end
                  4'h9,4'ha: begin add_a={1'b0,yv}; add_b=~{1'b0,xv}; add_cin=(sub==4'h9) | cin; end
                  4'hf: begin add_a=17'd0; add_b=~{1'b0,xv}; add_cin=1'b1; end
                  default: ;
                endcase
                add_result = add_a + add_b + {16'd0,add_cin};
                case (sub)
                  4'h0: r={1'b0,yv};
                  4'h4: r={1'b0,~yv};
                  4'hb: r={1'b0,~xv};
                  4'hc: r={1'b0,xv & yv};
                  4'hd: r={1'b0,xv | yv};
                  4'he: r={1'b0,xv ^ yv};
                  4'hf: r=xv[15] ? add_result : {1'b0,xv};
                  default: r=add_result;
                endcase
            end else begin
            case (sub)
              4'h0: r = {1'b0, yv};                                 // PASS Y
              4'h1: r = {1'b0, yv} + 17'd1;                         // Y+1
              4'h2: r = {1'b0, xv} + {1'b0, yv} + {16'h0,cin};      // X+Y+C
              4'h3: r = {1'b0, xv} + {1'b0, yv};                    // X+Y
              4'h4: r = {1'b0, (~yv)};                              // NOT Y
              4'h5: r = 17'h0 - {1'b0, yv};                         // -Y
              4'h6: r = {1'b0, xv} - {1'b0, yv} + {16'h0,cin} - 17'd1; // X-Y+C-1
              4'h7: r = {1'b0, xv} - {1'b0, yv};                    // X-Y
              4'h8: r = {1'b0, yv} - 17'd1;                         // Y-1
              4'h9: r = {1'b0, yv} - {1'b0, xv};                    // Y-X
              4'ha: r = {1'b0, yv} - {1'b0, xv} + {16'h0,cin} - 17'd1; // Y-X+C-1
              4'hb: r = {1'b0, (~xv)};                              // NOT X
              4'hc: r = {1'b0, (xv & yv)};                          // X AND Y
              4'hd: r = {1'b0, (xv | yv)};                          // X OR Y
              4'he: r = {1'b0, (xv ^ yv)};                          // X XOR Y
              4'hf: r = xv[15] ? (17'h0 - {1'b0,xv}) : {1'b0,xv};   // ABS X
            endcase
            end
            astn = c_nz(astn, {15'h0, r});
            s32 = {16'h0, xv}; d32 = {16'h0, yv}; r32 = {15'h0, r};
            case (sub)
              4'h2,4'h3: begin astn=c_v(astn,s32,d32,r32); astn=astn | ((r32>>13)&16'h0008); end
              4'h6,4'h7: begin astn=c_v(astn,s32,d32,r32); astn=astn | (((~r32)>>13)&16'h0008); end
              4'h9,4'ha: begin astn=c_v(astn,d32,s32,r32); astn=astn | (((~r32)>>13)&16'h0008); end
              4'h1: if(yv==16'h7fff) astn=astn|16'h0004; else if(yv==16'hffff) astn=astn|16'h0008;
              4'h5: begin if(yv==16'h8000) astn=astn|16'h0004; if(yv==16'h0000) astn=astn|16'h0008; end
              4'h8: if(yv==16'h8000) astn=astn|16'h0004; else if(yv==16'h0000) astn=astn|16'h0008;
              4'hf: begin astn = astat & ~16'h001F; if(xv==16'h0) astn=astn|16'h0001;
                          if(xv==16'h8000) astn=astn|16'h0006; if(xv[15]) astn=astn|16'h0010; end
              default: ; // logical ops: N,Z only
            endcase
            alu_eval = {astn, r[15:0]}; // {astat_next, 16-bit result}; writeback at call sites
        end
    endfunction

    // ---- MAC unit (per MAME 2100ops.h mac_op_mr). MR 40-bit = {MR2[7:0],MR1,MR0} --
    function [15:0] mac_xread(input [2:0] xi); // {MX0 MX1 AR MR0 MR1 MR2 SR0 SR1}
        case (xi)
          3'd0: mac_xread=`G0(2);  3'd1: mac_xread=`G0(3);
          3'd2: mac_xread=`G0(10); 3'd3: mac_xread=`G0(11);
          3'd4: mac_xread=`G0(12); 3'd5: mac_xread=`G0(13);
          3'd6: mac_xread=`G0(14); 3'd7: mac_xread=`G0(15);
        endcase
    endfunction
    function [15:0] mac_yread(input [1:0] yi); // {MY0 MY1 MF 0}
        case (yi)
          2'd0: mac_yread=`G0(6); 2'd1: mac_yread=`G0(7);
          2'd2: mac_yread=`MF;    2'd3: mac_yread=16'h0;
        endcase
    endfunction
    // dst_mf=0: mac_op_mr (2100ops.hxx:1380-1683); dst_mf=1: mac_op_mf (1690-1843).
    // Product is a 32-bit int truncation `int32_t temp = (xop*yop) << shift`
    // (2100ops.hxx:1385/1397 etc.) sign-extended into the 64-bit accumulate;
    // accumulate uses the FULL 64-bit m_core.mr.mr (incl. hidden mrzero).
    // Phase 8c: PURE combinational MAC result generator (was `task mac_exec`,
    // inlined at 4 call sites -> 4 replicated 16x16->64b MACs = the 20 GB blowup).
    // Evaluated ONCE per instruction into `mac_r`; the MV flag + MR/MF writeback
    // split now lives at the call sites. Math byte-identical to the former task.
    function automatic [63:0] mac_r64_f(input [3:0] sub);
        reg [15:0] xv, yv; reg xs, ys; reg [1:0] acc; reg rnd, sh;
        reg signed [31:0] xe, ye, p32; reg signed [63:0] prod, r, mrold;
        reg signed [16:0] narrow_x, narrow_y;
        reg [63:0] add_a, add_b;
        reg subtract;
        begin
            r = 64'sh0;
            if (sub != 4'h0) begin
                xv = mac_xread(op[10:8]); yv = mac_yread(op[12:11]);
                case (sub)  // X,Y signedness
                  4'h1,4'h2,4'h3,4'h4,4'h8,4'hC: begin xs=1'b1; ys=1'b1; end // SS
                  4'h5,4'h9,4'hD:                begin xs=1'b1; ys=1'b0; end // SU
                  4'h6,4'hA,4'hE:                begin xs=1'b0; ys=1'b1; end // US
                  default:                       begin xs=1'b0; ys=1'b0; end // UU
                endcase
                case (sub)  // accumulate
                  4'h2,4'h8,4'h9,4'hA,4'hB: acc=2'd1; // MR + X*Y
                  4'h3,4'hC,4'hD,4'hE,4'hF: acc=2'd2; // MR - X*Y
                  default:                  acc=2'd0; // X*Y
                endcase
                rnd = (sub==4'h1)||(sub==4'h2)||(sub==4'h3);
                sh  = ~mstat[4];   // shift = MSTAT_INTEGER ? 0 : 1 (2100ops.hxx:1382)
                xe  = xs ? $signed({{16{xv[15]}}, xv}) : $signed({16'b0, xv});
                ye  = ys ? $signed({{16{yv[15]}}, yv}) : $signed({16'b0, yv});
                if (SHARED_MAC) begin
                    // A signed 17-bit representation covers both signed and
                    // unsigned 16-bit inputs. Only the low 32 product bits are
                    // architectural, matching the original int32 truncation.
                    narrow_x = $signed({xs & xv[15],xv});
                    narrow_y = $signed({ys & yv[15],yv});
                    p32 = narrow_x * narrow_y;
                end else p32 = xe * ye;        // int32 truncation per gospel
                if (sh) p32 = p32 <<< 1;
                prod = {{32{p32[31]}}, p32};
                mrold = $signed({`MRZ, `G0(13), `G0(12), `G0(11)}); // full 64-bit MR
                if (SHARED_MAC) begin
                    subtract = acc == 2'd2;
                    add_a = acc == 2'd0 ? 64'd0 : mrold;
                    add_b = prod ^ {64{subtract}};
                    r = add_a + add_b + {{63{1'b0}},subtract};
                end else begin
                    case (acc)
                      2'd1:    r = mrold + prod;
                      2'd2:    r = mrold - prod;
                      default: r = prod;
                    endcase
                end
                if (rnd) begin
                    // 2100ops.hxx:1713-1716: res += 0x8000; if pre-round product
                    // low 16 == 0x8000, clear bit16 (round half to even)
                    r = r + 64'sh8000;
                    if (prod[15:0] == 16'h8000) r[16] = 1'b0;
                end
            end
            mac_r64_f = r;   // full 64-bit accumulate/product; writeback at call sites
        end
    endfunction

    // Phase 8c: shifter writeback — cheap muxing only. Consumes the shared
    // shift_eval outputs; the mode-gated SR / SE / SS / SBR commit that used to
    // live inside shift_do. Called exactly where shift_do was, so the "move wins
    // on clash" ordering vs the parallel reg/PM/DM moves is preserved verbatim.
    task automatic shift_wb(input [3:0] mode);
        begin
            if (mode < 4'hC) begin
                `G0(14) <= shift_res_v[15:0]; `G0(15) <= shift_res_v[31:16]; // SR0, SR1
            end
            if (shift_ss_we)  astat[7] <= shift_ss_v; // SS flag (EXP modes)
            if (shift_se_we)  `G0(9)   <= shift_se_v; // SE   (EXP modes)
            if (shift_sbr_we) `SBR     <= shift_sbr_v; // SB  (EXPADJ)
        end
    endtask

    // Phase 8c: ALU writeback — cheap muxing only. Consumes shared `alu_res`.
    task automatic alu_wb(input dst_af);
        begin
            astat <= alu_res[31:16];
            if (dst_af) `AF <= alu_res[15:0]; else `G0(10) <= alu_res[15:0]; // AR = G0(10)
        end
    endtask

    // Phase 8c: MAC writeback — cheap register muxing only (no datapath), so
    // inlining at the 4 call sites costs nothing. Consumes the shared `mac_r`;
    // `sub!=0` guard preserves the former task's "MAC-NOP does nothing" semantics.
    task automatic mac_wb(input [3:0] sub, input dst_mf);
        begin
            if (sub != 4'h0) begin
                if (dst_mf) begin
                    `MF <= mac_r[31:16];        // mac_op_mf tail (2100ops.hxx:1840-1842); no MV
                end else begin                  // ov = BIT(res,31,9) (2100ops.hxx:1678-1680)
                    if (mac_r[39:31] != 9'h000 && mac_r[39:31] != 9'h1ff) astat <= astat | 16'h0040; // SET_MV
                    else                                                   astat <= astat & ~16'h0040; // CLR_MV
                    `G0(11) <= mac_r[15:0]; `G0(12) <= mac_r[31:16];
                    `G0(13) <= mac_r[47:32]; `MRZ <= mac_r[63:48]; // full 64-bit store (union mr)
                end
            end
        end
    endtask

    // ---- hardware boot: reload internal PM from a ROM bank (load_boot_data) --
    // pagelen=(ROM[bank*0x1000+3]+1)*8 opcodes; PM[j] = 3 bytes ROM[base+4j..+2].
    // Streamed one word/clock by the S_BOOT FSM (below) rather than an unrolled
    // one-clock for-fill (N12: un-synthesizable). See boot_active/boot_idx state.
    // launch_boot: arm the streaming DMA for `bank`; the CPU is held until done.
    task automatic launch_boot(input [10:0] bank);
        begin
            boot_active <= 1'b1;
            state       <= S_BOOT;   // Phase 6: FSM enters the boot-DMA state
            boot_bank   <= bank;
            boot_idx    <= 12'h0;
            boot_plen   <= 12'h0;
            boot_phase  <= 2'd0;    // Phase 5: start with the page-length header byte
        end
    endtask

    // ---- DM read with input-latch auto-ack side effect ----------------------
    // Instruction-path DM loads go through here so a read of the input latch
    // (DM $3400-$3403, dcs_8k_data_map dcs.cpp:320) performs input_latch_r's
    // auto-ack (dcs.cpp:1555-1563 + 1544-1552 with m_auto_ack=true, dcs.cpp:789):
    // clear the IRQ2 line. (The CPU edge latch is NOT cleared by the ack in MAME;
    // only generate_irq clears it, adsp2100.cpp:897.)
    task automatic dm_load(input [15:0] addr, output [15:0] val);
        begin
            val = dm_read(addr);
`ifndef SYNTHESIS
            // Phase-2/6 cross-check: for port-backed regions the S_MEM stage
            // must have pre-issued THIS address (else the captured data is
            // stale). Compared against the S_DECODE latch (what was issued).
            // Abort loudly: the truncated PC stream fails the Gate-1 diff.
            if (dm_region(addr) != RG_LATCH && addr != ea_addr_r) begin
                $display("FATAL: Phase-6 pre-read addr mismatch (load) pc=%04x op=%06x pre=%04x used=%04x",
                         pc, op, ea_addr_r, addr);
                $finish;
            end
`endif
`ifndef SYNTHESIS
            if (wrlog_en && wrlog_on && wrlog_cnt < 40000 &&
                addr >= 16'h2000 && addr <= 16'h2fff) begin
                // ROM-window read log w/ reader state (mirror of rdlog.lua)
                $fdisplay(wrlog_fd, "R %04x %04x pc=%04x cntr=%04x se=%04x ar=%04x i4=%04x sr0=%04x sr1=%04x mr0=%04x",
                          addr, val, pc, cntr, `G0(9), `G0(10), iR[4], `G0(14), `G0(15), `G0(11));
                wrlog_cnt = wrlog_cnt + 1;
            end
`endif
            if (addr >= 16'h3400 && addr <= 16'h3403) begin
                irq2_line <= 1'b0;
                // input_latch_r auto-ack (dcs.cpp:1544-1552, m_auto_ack dcs.cpp:789):
                // SET_INPUT_EMPTY (dcs.cpp:186) -- the host now sees the input latch
                // drained. Host-visible only; never read by the ADSP.
                latch_control <= latch_control | 16'h0800;
            end
        end
    endtask

    // ---- DM write with the full 8k data-map semantics ------------------------
    // 0x0800-0x1FFF: shared external program RAM -- dcs_dataram_w (dcs.cpp:916-923)
    //   stores the 16-bit value into the PM word's high 16 bits, low byte kept.
    // 0x3000: ROM bank select (dcs.cpp:319 + dcs_data_bank_select_w 925-939).
    // 0x3FFF write with bit9: SYSCONTROL soft reboot (adsp_control_w 1872-1880).
    // debug write-log (mirrors ../../mame-gospel/trace/wrlog.lua): ordered log of
    // parse-region DM writes from the queue push of 0x046A on (plusarg +wrlog=1)
    integer wrlog_en = 0, wrlog_fd = 0, wrlog_cnt = 0;
    reg     wrlog_on = 1'b0;
`ifndef SYNTHESIS
    initial if ($value$plusargs("wrlog=%d", wrlog_en) && wrlog_en) begin
        wrlog_fd = $fopen("dut_wr.txt", "w");
    end
`endif

    task automatic dm_write(input [15:0] addr, input [15:0] val);
        begin
`ifndef SYNTHESIS
            if (wrlog_en) begin
                if (!wrlog_on && val == 16'h046a)   // queue push of the track word (@~0x3910)
                    wrlog_on = 1'b1;
                if (wrlog_on && wrlog_cnt < 40000 &&
                    ((addr >= 16'h0300 && addr <= 16'h05ff) ||
                     (addr >= 16'h3900 && addr <= 16'h39ff))) begin
                    $fdisplay(wrlog_fd, "%04x %04x", addr, val);
                    wrlog_cnt = wrlog_cnt + 1;
                end
            end
`endif
            if (addr >= 16'h0800 && addr <= 16'h1fff) begin
                // PM-alias RMW (§2b, OPEN RISK 1) -- the 2-CLOCK RMW variant:
                // the merge {val, old[7:0]} needs the OLD low byte; the S_MEM
                // stage pre-read PM[addr] one clock ago (pmb_q holds it), the
                // merged word commits here. Chosen over the shadow-low-byte
                // BRAM because it reuses the exact pre-read machinery every
                // load already has: zero extra storage and no second write-
                // coherence path to keep in sync across the three PM writers
                // (boot DMA, PM-data ops, alias writes). Hazard-free: the CPU
                // is stalled between the pre-read and this commit, and no
                // other agent writes PM.
                pm_we = 1'b1; pm_wa = addr[13:0]; pm_wd = {val, pmb_q[7:0]};
`ifndef SYNTHESIS
                if (addr != ea_addr_r) begin
                    $display("FATAL: Phase-6 pre-read addr mismatch (RMW) pc=%04x op=%06x pre=%04x used=%04x",
                             pc, op, ea_addr_r, addr);
                    $finish;
                end
`endif
            end else if (addr == 16'h3000)
                data_bank <= val[10:0];
            else if (addr >= 16'h3400 && addr <= 16'h3403) begin
                // ---- output latch (DCS->host): the ADSP writing DM 0x3400-0x3403
                //      is output_latch_w (dcs.cpp:320 map + 1590-1596): latch the
                //      response word and SET_OUTPUT_FULL (dcs.cpp:181). MAME maps
                //      this to the latch, NOT to RAM, so we do NOT touch the DM
                //      array here (a DM read of 0x3400 returns input_data via
                //      RG_LATCH, never this word). Host-visible only -> gate-inert.
                output_data   <= val;
                latch_control <= latch_control & ~16'h0400;  // SET_OUTPUT_FULL
            end
            else begin
                if (!EXPLICIT_RAM_CE) `DM[addr[13:0]] <= val;
`ifndef SYNTHESIS
                legacy_dm_we = 1'b1;
                legacy_dm_wa = addr[13:0]; legacy_dm_wd = val;
`endif
                if (addr == 16'h3FEF) ctl_s1_autobuf <= val;  // live control-reg shadow
                // ---- Phase-7 timer control writes (adsp_control_w; the DM
                //      array above keeps the raw m_control_regs mirror per
                //      dcs.cpp:1868 `m_control_regs[offset] = data`). A write
                //      restarts the fire schedule (reset_timer: next underflow
                //      = scale*(count+1) cycles from now, dcs.cpp:1783)
                //      -> reload the prescaler alongside the shadow.
                if (addr == 16'h3FFB) begin   // TIMER_SCALE_REG (dcs.cpp:1923-1931)
                    tim_scale     <= {1'b0, val[7:0]} + 9'd1;  // (data & 0xff) + 1
                    tim_scale_cnt <= {1'b0, val[7:0]} + 9'd1;
                end
                if (addr == 16'h3FFC) begin   // TIMER_COUNT_REG (dcs.cpp:1933-1935)
                    tim_count     <= val;      // m_timer_start_count = data
                    tim_scale_cnt <= tim_scale;
                end
                if (addr == 16'h3FFD)         // TIMER_PERIOD_REG (dcs.cpp:1938-1944)
                    tim_period    <= val;
                if (addr == 16'h3FFF) begin
                    ctl_syscontrol <= val;                    // live control-reg shadow
                    if (val[9]) begin
                        reboot_pending <= 1'b1; reboot_bank <= data_bank;
                    end
                end
            end
        end
    endtask

    // ---- MSTAT write (N14): bank select is a POINTER, not a physical swap ---
    // MSTAT bit0 = secondary-register-bank select (2100ops.hxx:70 MSTAT_BANK;
    // MAME swaps the adsp_core storage, we retarget the index -- semantically
    // identical, see the `G0 accessor comment). One flop (mstat[0]) toggles
    // instead of an un-synthesizable 16-way multi-port copy.
    task automatic set_mstat(input [15:0] nm);
        begin
            mstat <= nm;
        end
    endtask

    // ---- data-memory read with banked ROM window (DM 0x2000-0x2FFF) --------
    // Phase 2: the instruction path now CONSUMES the S_MEM pre-read -- the
    // clocked ports' registered outputs (pmb_q/dm_q/rom_q), issued one (or, for
    // the bank window, two) clocks earlier at this same address. Region routing
    // is identical to the old async version (dcs_8k data map); the input latch
    // stays a live register read (its value is architecturally a flop, and a
    // host write may land between S_MEM and EXEC -- baseline reads it at EXEC).
    // Only caller is dm_load (the drain has its own S_DRAIN capture path).
    function [15:0] dm_read(input [15:0] addr);
        begin
            case (dm_region(addr))
              RG_ALIAS:
                // DM 0x0800-0x1FFF is SHARED with external program RAM (dcs_8k
                // program map dcs.cpp:307-312 + data map 317): dcs_dataram_r
                // (dcs.cpp:909-913) returns the PM word's high 16 bits (>>8)
                dm_read = pmb_q[23:8];
              RG_BANK:
                // banked ROM window: rom_q = byte at (data_bank<<12)+addr[11:0]
                // via the Phase-5 DDR3-shaped port (prefetch cache + modeled
                // round trip; the rom-stall branch guaranteed rom_rdy before
                // this EXEC clock); dcs word = FF|lowbyte
                dm_read = {8'hFF, rom_q};
              RG_LATCH:
                // input latch read (dcs_8k_data_map dcs.cpp:320 -> input_latch_r
                // dcs.cpp:1555-1563): returns m_input_data. The auto-ack side
                // effect (clear the IRQ2 line, dcs.cpp:789 m_auto_ack=true ->
                // 1544-1552) is applied by the dm_load task wrapper.
                dm_read = input_data;
              default:
                // Phase-7 timer: a TIMER_COUNT read returns the LIVE count
                // (adsp_control_r case TIMER_COUNT_REG updates from elapsed
                // cycles before returning, dcs.cpp:1850-1854); every other
                // control reg reads back its raw m_control_regs mirror = the
                // DM array (adsp_control_r default, dcs.cpp:1856-1858).
                dm_read = (addr == 16'h3FFC) ? tim_count : dm_q;
            endcase
        end
    endfunction

    // ---- shifter: FULL 16-mode shift_op per 2100ops.hxx:1994-2149 ----------
    // SR = {`G0(15)=SR1, `G0(14)=SR0}; SE = `G0(9) (int8, read as signed [7:0]);
    // SB = `SBR (int16); SS flag = astat bit7 (SSFLAG=0x80, adsp2100.h:459);
    // carry CFLAG = astat bit3. xreg table per adsp2100.cpp:251-258 (idx 1 = SI).
    function [15:0] shift_xreg(input [2:0] xi);
        case (xi)
          3'd0: shift_xreg = `G0(8);   3'd1: shift_xreg = `G0(8);   // SI, SI
          3'd2: shift_xreg = `G0(10);  3'd3: shift_xreg = `G0(11);  // AR, MR0
          3'd4: shift_xreg = `G0(12);  3'd5: shift_xreg = `G0(13);  // MR1, MR2
          3'd6: shift_xreg = `G0(14);  3'd7: shift_xreg = `G0(15);  // SR0, SR1
        endcase
    endfunction
    function automatic integer clz32(input [31:0] v); // count_leading_zeros_32
        integer j;
        begin
            clz32 = 32;
            for (j = 31; j >= 0; j = j - 1)
                if (v[j] && clz32 == 32) clz32 = 31 - j;
        end
    endfunction
    // Phase 8c: PURE shifter result generator (was `task shift_do`, inlined at 7
    // sites -> 7 replicated 16-mode barrel shifters). Evaluated ONCE per instr;
    // writes ONLY its output args (no arch-reg side effects). The SR/SE/SS/SBR
    // writeback (mode-dependent) moves to shift_wb at the call sites. Math is
    // byte-identical to the former task (nonblocking `<=` -> blocking out-arg).
    task automatic shift_eval(input [3:0] mode, input [2:0] xi, input signed [7:0] sc,
                              output reg [31:0] o_res, output reg [15:0] o_se, output reg o_ss,
                              output reg [15:0] o_sbr,
                              output reg o_se_we, output reg o_ss_we, output reg o_sbr_we);
        reg [15:0] xr; reg signed [31:0] xs; reg [31:0] xu, res;
        integer e; reg signed [15:0] sev;
        reg [31:0] shift_value, shift_input, shifted;
        reg signed [32:0] barrel_value, barrel_result;
        reg [7:0] amount;
        reg shift_left, sign_fill;
        reg [15:0] exp_bits;
        integer exp_count;
        begin
            o_res=32'h0; o_se=16'h0; o_ss=1'b0; o_sbr=16'h0;
            o_se_we=1'b0; o_ss_we=1'b0; o_sbr_we=1'b0;
            xr = shift_xreg(xi);
            res = 32'h0;
            // Logical/arithmetic HI/LO and NORM share a right barrel.
            // A bit reversal on each side implements left shifts as wiring.
            // NORM HI consumes carry at bit 31 and uses sc-1 for right shifts.
            exp_bits = xr ^ {16{(mode == 4'hE) ? astat[7] : xr[15]}};
            exp_count = clz32({16'b0, exp_bits});
            if (SHARED_SHIFT && mode < 4'hC) begin
                shift_left = mode[3] ? (sc <= 0) : (sc > 0);
                amount = sc[7] ? -sc : sc;
                shift_value = mode[1] ? {16'b0, xr} : {xr, 16'b0};
                if (mode[3:2] == 2'b01 && mode[1]) shift_value = {{16{xr[15]}},xr};
                sign_fill = (mode[3:2] == 2'b01) && !shift_left && xr[15];
                if (mode[3:1] == 3'b100 && sc > 0) begin
                    shift_value = {astat[3], xr, 15'b0};
                    amount = $unsigned(sc) - 8'd1;
                end
                for (integer bit_index=0; bit_index<32; bit_index=bit_index+1)
                    shift_input[bit_index] = shift_left ? shift_value[31-bit_index] : shift_value[bit_index];
                barrel_value = $signed({sign_fill, shift_input});
                barrel_result = barrel_value >>> amount[4:0];
                shifted = (amount >= 32) ? {32{sign_fill}} : barrel_result[31:0];
                for (integer bit_index=0; bit_index<32; bit_index=bit_index+1)
                    res[bit_index] = shift_left ? shifted[31-bit_index] : shifted[bit_index];
            end else begin
            case (mode)
              4'h0, 4'h1: begin // LSHIFT (HI[,OR])   2100ops.hxx:2002-2015
                  xu = {xr, 16'h0};
                  if (sc > 0) res = (sc < 32)   ? (xu << sc)    : 32'h0;
                  else        res = (sc > -32)  ? (xu >> (-sc)) : 32'h0;
              end
              4'h2, 4'h3: begin // LSHIFT (LO[,OR])   2100ops.hxx:2016-2029
                  xu = {16'h0, xr};
                  if (sc > 0) res = (sc < 32)   ? (xu << sc)    : 32'h0;
                  else        res = (sc > -32)  ? (xu >> (-sc)) : 32'h0;
              end
              4'h4, 4'h5: begin // ASHIFT (HI[,OR])   2100ops.hxx:2030-2043
                  xs = $signed({xr, 16'h0});
                  if (sc > 0) res = (sc < 32)   ? (xs <<  sc)   : 32'h0;
                  else        res = (sc > -32)  ? (xs >>> (-sc)) : (xs >>> 31);
              end
              4'h6, 4'h7: begin // ASHIFT (LO[,OR])   2100ops.hxx:2044-2057
                  xs = $signed({{16{xr[15]}}, xr});
                  if (sc > 0) res = (sc < 32)   ? (xs <<  sc)   : 32'h0;
                  else        res = (sc > -32)  ? (xs >>> (-sc)) : (xs >>> 31);
              end
              4'h8, 4'h9: begin // NORM (HI[,OR])     2100ops.hxx:2058-2079
                  xs = $signed({xr, 16'h0});
                  if (sc > 0) begin
                      xu  = {astat[3], xs[31:1]};     // (uint32)xop>>1 | (CFLAG<<28): carry->bit31
                      res = xu >> (sc - 1);
                  end else
                      res = (sc > -32) ? (xs << (-sc)) : 32'h0;
              end
              4'hA, 4'hB: begin // NORM (LO[,OR])     2100ops.hxx:2080-2094
                  xu = {16'h0, xr};
                  if (sc > 0) res = (sc < 32)  ? (xu >> sc)    : 32'h0;
                  else        res = (sc > -32) ? (xu << (-sc)) : 32'h0;
              end
              4'hC: begin       // EXP (HI)           2100ops.hxx:2095-2108
                  xs = $signed({{16{xr[15]}}, xr});
                  if (xs < 0) begin
                      o_ss = 1'b1; o_ss_we = 1'b1;     // SET_SS
                      e = (SHARED_SHIFT ? exp_count : clz32(~xs)) - 16 - 1;
                  end else begin
                      o_ss = 1'b0; o_ss_we = 1'b1;     // CLR_SS
                      e = (SHARED_SHIFT ? exp_count : clz32(xs)) - 16 - 1;
                  end
                  sev = -e; o_se = sev; o_se_we = 1'b1; // SE = -res (int8 range)
              end
              4'hD: begin       // EXP (HIX)          2100ops.hxx:2109-2133
                  xs = $signed({{16{xr[15]}}, xr});
                  if (astat[2]) begin                 // GET_V
                      sev = 16'sd1; o_se = sev; o_se_we = 1'b1;
                      if (xs < 0) begin o_ss = 1'b0; o_ss_we = 1'b1; end else begin o_ss = 1'b1; o_ss_we = 1'b1; end
                  end else begin
                      if (xs < 0) begin
                          o_ss = 1'b1; o_ss_we = 1'b1; e = (SHARED_SHIFT ? exp_count : clz32(~xs)) - 16 - 1;
                      end else begin
                          o_ss = 1'b0; o_ss_we = 1'b1; e = (SHARED_SHIFT ? exp_count : clz32(xs)) - 16 - 1;
                      end
                      sev = -e; o_se = sev; o_se_we = 1'b1;
                  end
              end
              4'hE: begin       // EXP (LO)           2100ops.hxx:2134-2142
                  if ($signed(`G0(9)[7:0]) == -8'sd15) begin
                      xs = $signed({{16{xr[15]}}, xr});
                      e  = (SHARED_SHIFT ? exp_count : clz32((astat[7] ? ~xs : xs) & 32'h0000ffff)) - 1;
                      sev = -e; o_se = sev; o_se_we = 1'b1;
                  end
              end
              4'hF: begin       // EXPADJ             2100ops.hxx:2143-2149
                  xs = $signed({{16{xr[15]}}, xr});
                  e  = (SHARED_SHIFT ? exp_count : clz32((xs < 0) ? ~xs : xs)) - 16 - 1;
                  if (e < -$signed(`SBR)) begin sev = -e; o_sbr = sev; o_sbr_we = 1'b1; end
              end
            endcase
            end
            if (mode < 4'hC) begin                    // SR-result modes
                if (mode[0]) res = {`G0(15), `G0(14)} | res; // OR variant
                o_res = res;                           // SR0/SR1 committed at shift_wb
            end
        end
    endtask


    // Explicit physical RAM ports. The original sequential write calculations
    // below remain as a simulation oracle. The primitive consumes combinational
    // intent before the edge; feeding posedge blocking temporaries to another
    // module would introduce a scheduling race and an unintended cycle.
    reg ram_pm_we, ram_dm_we;
    reg [13:0] ram_pm_wa, ram_dm_wa;
    reg [23:0] ram_pm_wd;
    reg [15:0] ram_dm_wd;
    reg mem_dm_request;
    reg [15:0] mem_dm_address, mem_dm_value, mem_register_value;
    reg [2:0] mem_dag_index;
    wire [13:0] ram_pm_addr = ram_pm_we ? ram_pm_wa : pmb_addr;
    always_comb begin
        ram_pm_we=0; ram_pm_wa=0; ram_pm_wd=0;
        ram_dm_we=0; ram_dm_wa=0; ram_dm_wd=0;
        mem_dm_request=0; mem_dm_address=0; mem_dm_value=0;
        mem_dag_index={op_r[20],op_r[3:2]};
        mem_register_value = SHARED_REG_READ
            ? rd_reg(generic_read_select_r[5:4],generic_read_select_r[3:0])
            : rd_reg((op_r[23:21]==3'b100) ? op_r[19:18] : 2'd0,
                     (op_r[23:21]==3'b100) ? op_r[3:0] : op_r[7:4]);
        // CE is applied at the primitive input/core registers. Do not include
        // it in write intent: an inactive CE must HOLD the RAM input registers.
        if (!rst) begin
            if (state == S_BOOT && boot_rom_rdy && boot_phase==2'd3) begin
                ram_pm_we=1; ram_pm_wa={2'b0,boot_idx};
                ram_pm_wd={boot_b0,boot_b1,rom_q};
            end
            if (state == S_EXEC) begin
                if ((op_r[23:16]==8'h11 && op_r[15]) ||
                    (op_r[23:20]==4'h5 && op_r[19])) begin
                    ram_pm_we=1; ram_pm_wa=iR[{1'b1,op_r[3:2]}][13:0];
                    ram_pm_wd={mem_register_value,px[7:0]};
                end
                if ((op_r[23:16]==8'h12 || op_r[23:16]==8'h13) && op_r[15]) begin
                    mem_dag_index={op_r[16],op_r[3:2]};
                    mem_dm_request=1;
                    mem_dm_address=dag_addr(mem_dag_index);
                    mem_dm_value=mem_register_value;
                end else if (op_r[23:21]==3'b011 && op_r[19]) begin
                    mem_dm_request=1;
                    mem_dm_address=dag_addr(mem_dag_index);
                    mem_dm_value=mem_register_value;
                end else if (op_r[23:20]==4'h9) begin
                    mem_dm_request=1;
                    mem_dm_address={2'b0,op_r[17:4]};
                    mem_dm_value=mem_register_value;
                end else if (op_r[23:21]==3'b101) begin
                    mem_dm_request=1;
                    mem_dm_address=dag_addr(mem_dag_index);
                    mem_dm_value=op_r[19:4];
                end
                if (mem_dm_request) begin
                    if (mem_dm_address>=16'h0800 && mem_dm_address<=16'h1fff) begin
                        ram_pm_we=1; ram_pm_wa=mem_dm_address[13:0];
                        ram_pm_wd={mem_dm_value,pmb_q[7:0]};
                    end else if (mem_dm_address!=16'h3000 &&
                                 !(mem_dm_address>=16'h3400 && mem_dm_address<=16'h3403)) begin
                        ram_dm_we=1; ram_dm_wa=mem_dm_address[13:0];
                        ram_dm_wd=mem_dm_value;
                    end
                end
            end
        end
    end
    generate if (EXPLICIT_RAM_CE) begin : g_ce_ram
        dcs_ce_ram #(.WIDTH(24),.READ_WRITE_A(1),.SIM_INIT(PMFILE)) pm_store(
            .clk(clk),.ce(cpu_ce),.write_enable(ram_pm_we),
            .address_a(ram_pm_addr),.write_data(ram_pm_wd),.q_a(pmb_q),
            .address_b(fetch_addr),.q_b(fetch_r));
        dcs_ce_ram #(.WIDTH(16),.READ_WRITE_A(0)) dm_store(
            .clk(clk),.ce(cpu_ce),.write_enable(ram_dm_we),
            .address_a(ram_dm_wa),.write_data(ram_dm_wd),.q_a(),
            .address_b(dm_addr),.q_b(dm_q));
`ifndef SYNTHESIS
        initial if (!SHARED_PM || RD_LATENCY!=1)
            $fatal(1,"EXPLICIT_RAM_CE needs SHARED_PM=1 and RD_LATENCY=1");
`endif
    end endgenerate
`ifndef SYNTHESIS
    reg legacy_dm_we;
    reg [13:0] legacy_dm_wa;
    reg [15:0] legacy_dm_wd;
`endif

    // ---- init --------------------------------------------------------------
    // PM/DM now live HERE (Phase 8a item 4 move); the U2-U5 ROM $fread stays in
    // u_mem (dcs_mem). Sim-only preload of the PM image (the boot DMA overwrites
    // PM[0..plen] from ROM on the power-on reset anyway; the $readmemh keeps the
    // overlay tail the disassembly-sourced image provides for the F19 window).
    integer k;
`ifndef SYNTHESIS
    initial begin
        for (k=0;k<16384;k=k+1) begin
            pm[k]=24'h0; dm[k]=16'h0;
            if (!SHARED_PM) pm2[k]=24'h0;
        end
        $readmemh(PMFILE, pm);
        if (!SHARED_PM) $readmemh(PMFILE, pm2);
    end
`endif
    initial begin
        // Phase 7: the reset/IRQ replay tables + their $readmemh loads are GONE
        // (N8/N9/N16). All external stimulus arrives on pins (host_rst/host_wr).
        data_bank = 11'h0;
        input_data = 16'h0;
        latch_control = 16'h0C00;   // SET_INPUT_EMPTY|SET_OUTPUT_EMPTY (dcs.cpp:585-586); host idle read
        output_data = 16'h0;
        host_rst_r = 1'b0;
        // Phase-7 timer power-up = dcs_reset state: scale=1 (dcs.cpp:598),
        // control-reg mirrors zeroed (dcs.cpp:578 memset), no pending latch
        // (device_reset clears irq state, adsp2100.cpp:661-663).
        tim_scale = 9'd1; tim_count = 16'h0; tim_period = 16'h0;
        tim_scale_cnt = 9'd1; tim_irq_latch = 1'b0;
        // N17: PCM file is now owned by the TB (external $fwrite on dac_ce).
        dac_sample = 16'h0; dac_ce = 1'b0; dac_burst_len = 0;
        boot_active = 1'b0; boot_idx = 12'h0; boot_plen = 12'h0; boot_bank = 11'h0;
        boot_phase = 2'd0; boot_b0 = 8'h0; boot_b1 = 8'h0;   // Phase 5
        // Phase 2/6: FSM state + drain-stream progress + ctl shadows
        state = S_FETCH; dr_done = 1'b0; dr_idx = 0; dr_acc = 0; dr_cnt = 0;
        div_done = 1'b0; div_i = 5'd0; div_q = 16'h0; ab_drain_cnt = 16'h0;  // N20
        dr_region = RG_DM; dr_rom_a = 22'h0; dr_smp = 16'h0;
        ctl_s1_autobuf = 16'h0; ctl_syscontrol = 16'h0;  // == cleared DM array
    end

    // ---- main instruction-atomic step -------------------------------------
    reg [23:0] op;
    reg [7:0]  hi;
    reg [13:0] tgt;
    reg [1:0]  grp;  reg [3:0] ridx;  reg [13:0] daddr;
    reg [2:0]  iidx, midx;
    reg        do_loop_back, do_loop_exit;
    reg [15:0] mstat_tmp, dmv, mvtmp;
    reg [5:0] generic_read_select;
    reg [15:0] generic_read_data;
    reg        cflag;
    // Phase 8c: shared-datapath results — each unit is evaluated ONCE per
    // instruction (single HW instance) and committed at the call sites below.
    reg signed [63:0] mac_r;
    reg        [31:0] alu_res;   // {astat_next[31:16], result[15:0]}
    reg        [31:0] shift_res_v;   // SR1:SR0 result (OR-merged) for modes < 0xC
    reg        [15:0] shift_se_v, shift_sbr_v;
    reg               shift_ss_v, shift_se_we, shift_ss_we, shift_sbr_we;
    integer    li;

    // ======================================================================
    // Phase 6 (SYNTH-REFACTOR-PLAN §3 + §6 Phase 6): the multicycle-FSM cut.
    // ----------------------------------------------------------------------
    // Explicit instruction state machine replacing the Phase-2 implicit
    // fetch_ready/mem_stage priority chain. One instruction:
    //   S_FETCH  -> S_DECODE -> [S_DRAIN] -> [S_DIV] -> [S_ROM] -> [S_MEM]
    //            -> S_EXEC
    // S_EXEC still commits the WHOLE verbatim instruction body in one clock
    // (datapath functions verbatim, all writebacks, next-PC, drain commit),
    // so every nonblocking read-old-value / last-write-wins ordering the
    // behavioral model relies on is preserved by construction -- see the
    // HAZARD TABLE at the S_EXEC arm. Instruction ORDER (the Gate-1 PC
    // stream) is untouched: only clock counts change, which no gate observes
    // (drain cadence counts retired instructions; the drain itself is
    // DAC-retimed on silicon per §0). Reg-file operand reads stay
    // combinational inside S_EXEC: they read FLOPS/LUTRAM (N3/N4), not BRAM,
    // so the one-read-one-write-per-port rule (which is about the dcs_mem
    // BRAM ports) is not implicated; the plan's OPEN RISK 2 (operand-latch
    // states for Fmax) stays open for Quartus timing, not correctness.
    // ----------------------------------------------------------------------
    // ONE-READ-ONE-WRITE-PER-PORT AUDIT (dcs_mem ports, per state x clock):
    //  state    | PM-A (fetch)   | PM-B (pmb/PM-writes)      | DM read | DM write | ROM port
    //  S_BOOT   | idle re-read   | <=1 WRITE (word commit)   | -       | -        | req (stream)
    //  S_FETCH  | READ pm[pc]    | -                         | -       | -        | idle
    //  S_DECODE | re-read (same) | -                         | -       | -        | req starts (bank rd)
    //  S_DRAIN  | re-read        | READ dr_cur (alias rgn)   | READ dr_cur | -    | req held
    //  S_DIV    | re-read        | -                         | -       | -        | req held
    //  S_ROM    | re-read        | -                         | -       | -        | req held (stall)
    //  S_MEM    | re-read        | READ ea (alias/PM/RMW)    | READ ea | -        | req held
    //  S_EXEC   | re-read        | <=1 WRITE (PM-data write  | -       | <=1 WRITE| req held
    //           |                |  OR alias-RMW merge)      |         | (dm_write)| (consume)
    //  * PM-A: the registered fetch port re-reads pm[pc] every clock (pc moves
    //    only at EXEC) -- exactly one read per clock on a read-only port.
    //  * PM-B: reads are consumed only from S_MEM/S_DRAIN issues; writes land
    //    only in S_EXEC (one per instruction: the PM-data write variants and
    //    the alias RMW are mutually exclusive opcode classes) or S_BOOT (one
    //    word commit per completed byte-triplet). Reads and writes never share
    //    a clock on this port.
    //  * DM: reads issued in S_MEM/S_DRAIN only; writes in S_EXEC only (one
    //    dm_write per instruction). The sim's always-reading registered port
    //    is 1 read/clock; the unconsumed reloads are don't-cares.
    //  * S_DRAIN reads BOTH PM-B and DM at dr_cur each clock -- one read on
    //    EACH port (legal); only the region-selected value is consumed.
    //  * ROM port: one level-held request in flight at a time (S_BOOT stream
    //    xor one bank-window read; muxed by boot_active).
    // ======================================================================
    always @(posedge clk) begin
        dac_ce <= 1'b0;   // N17: default; the autobuffer drain pulses it for one clock
        exec_reg_we=1'b0; exec_dag_we=1'b0; exec_dm_we=1'b0; pc_push_we=1'b0;
        `ifndef SYNTHESIS
        legacy_dm_we=1'b0;
`endif
        pm_we  = 1'b0;    // Phase 8c: default no PM write; the write sites set it (blocking)
        if (rst) begin
            dr_done <= 1'b0; dr_idx <= 0; div_done <= 1'b0; div_i <= 5'd0;   // Phase-2 progress clear
            pc <= 14'h0000; o_valid <= 1'b0; o_unimpl <= 1'b0; o_ppc <= 14'h0;
            dac_sample <= 16'h0;
            loop_sp <= 0; pc_sp <= 0; cntr_sp <= 0; cntr <= 14'h0;
            astat<=0; mstat<=0; sstat<=0; imask<=0; icntl<=0; px<=0;
            afb[0]<=0; afb[1]<=0; mfb[0]<=0; mfb[1]<=0; sbb[0]<=0; sbb[1]<=0; mrzb[0]<=0; mrzb[1]<=0;
            for (k=0;k<8;k=k+1) begin iR[k]<=0; mR[k]<=0; lR[k]<=0; baseR[k]<=0; lmask[k]<=14'h3fff; end
            for (k=0;k<32;k=k+1) gr[k]<=0;   // both banks (N14)
            for (k=0;k<4;k=k+1)  loop_end[k]<=NO_LOOP;
            stat_sp <= 0; status_last_valid <= 1'b0; pc_last_valid <= 1'b0;
            data_bank <= 11'h0; reboot_pending <= 1'b0; launch_boot(11'h0); // power-on boot, bank 0
            latch_control <= 16'h0C00; output_data <= 16'h0; // dcs_reset: both latches EMPTY (dcs.cpp:585-586)
            ab_active <= 1'b0; dac_slot_ctr <= 16'h0; dac_slot_go <= 1'b0; // SPORT1 autobuffer idle
            irq2_line <= 1'b0; irq2_latch <= 1'b0; irq1_pulse <= 1'b0;     // dcs.cpp:582 IRQ2 clear;
                                                    // adsp2100.cpp:661-663 device_reset clears irq state
            host_rst_r <= 1'b0;
            // Phase-7 timer: power-on = dcs_reset (scale=1 dcs.cpp:598; count/
            // period mirrors zeroed dcs.cpp:578; latch cleared adsp2100.cpp:661-663)
            tim_scale <= 9'd1; tim_count <= 16'h0; tim_period <= 16'h0;
            tim_scale_cnt <= 9'd1; tim_irq_latch <= 1'b0;
        end else if (cpu_ce) begin case (state)

          S_BOOT: begin
            // ---- S_BOOT: streaming boot-DMA (N12), Phase-5 re-sourced through
            //      the DDR3-shaped ROM port. The page streams BYTE-BY-BYTE via
            //      the rom_req/rom_rdy handshake (page-length header ROM[base+3]
            //      first: pagelen=(src[3]+1)*8, adsp2100.cpp:320; then bytes
            //      0/1/2 of each word), stalling for each round trip (prefetch-
            //      cache hits ~3 clks/byte, misses take the DDR_LATENCY trip).
            //      Each completed word writes PM[idx]={src[4idx],src[4idx+1],
            //      src[4idx+2]} -- byte-identical PM image to the old per-clock
            //      snd_byte stream (and the original boot_load one-shot). CPU
            //      held (no fetch/retire) for the whole page; only the CLOCK
            //      count changes, which no gate observes (nothing retires;
            //      the drain cadence counts retired instructions). PM
            //      beyond the page keeps overlay content (no bulk clear, N13).
            o_valid <= 1'b0;
            if (boot_rom_rdy) begin
                case (boot_phase)
                  2'd0: begin   // page-length header byte ROM[base+3]
                      boot_plen  <= ({4'h0, rom_q} + 12'd1) << 3;
                      boot_phase <= 2'd1;
                  end
                  2'd1: begin boot_b0 <= rom_q; boot_phase <= 2'd2; end
                  2'd2: begin boot_b1 <= rom_q; boot_phase <= 2'd3; end
                  2'd3: begin   // third byte: commit the PM word
                      pm_we = 1'b1; pm_wa = {2'b0, boot_idx}; pm_wd = {boot_b0, boot_b1, rom_q};
                      boot_phase <= 2'd1;
                      if (boot_idx + 12'd1 >= boot_plen) begin
                          boot_active <= 1'b0;   // page fully streamed -> release the CPU
                          state       <= S_FETCH; // next clock = fresh fetch of PC (=0)
                      end else
                          boot_idx <= boot_idx + 12'd1;
                  end
                endcase
            end
          end

          S_FETCH: begin
            // ---- S_FETCH: PC (=fetch_addr) is presented to the clocked PM
            //      fetch port this edge; op (fetch_q) valid next clk. No
            //      retire, no architectural change. (With RD_LATENCY=0 the
            //      fetch is async and this is a plain bubble -- same flow.)
            o_valid <= 1'b0;
            state   <= S_DECODE;
          end

          // ---- the CHECK states: S_DECODE + every stall state ----------------
          // reboot / board-reset (host_rst_r) / generated-IRQ are evaluated at
          // the TOP of every clock of these states, in the baseline priority
          // order (Phase 7: same slots the reset/IRQ replay compares occupied)
          // -- the exact clock positions the Phase-2 chain evaluated them
          // (every fetch-valid clock before EXEC; never during the fetch
          // bubble, never during boot). S_EXEC commits unconditionally; a
          // pending event is taken at the next boundary's S_DECODE, which is
          // the same instruction boundary the baseline took it at.
          S_DECODE, S_DRAIN, S_DIV, S_ROM, S_MEM: begin
            o_valid <= 1'b0;
            if (reboot_pending) begin
            dr_done <= 1'b0; dr_idx <= 0; div_done <= 1'b0; div_i <= 5'd0;   // discard in-flight Phase-2 progress
            // ---- SYSCONTROL soft-reboot: reset CPU, reload PM from CURRENT bank ----
            pc <= 14'h0000; o_valid <= 1'b0; o_unimpl <= 1'b0;
            loop_sp <= 0; pc_sp <= 0; cntr_sp <= 0; cntr <= 14'h0; stat_sp <= 0; status_last_valid <= 1'b0; pc_last_valid <= 1'b0;
            astat<=0; mstat<=0; sstat<=0; imask<=0; icntl<=0; px<=0;
            afb[0]<=0; afb[1]<=0; mfb[0]<=0; mfb[1]<=0; sbb[0]<=0; sbb[1]<=0; mrzb[0]<=0; mrzb[1]<=0;
            for (k=0;k<8;k=k+1) begin iR[k]<=0; mR[k]<=0; lR[k]<=0; baseR[k]<=0; lmask[k]<=14'h3fff; end
            for (k=0;k<32;k=k+1) gr[k]<=0;   // both banks (N14)
            for (k=0;k<4;k=k+1)  loop_end[k]<=NO_LOOP;
            launch_boot(reboot_bank);      // reload from the bank selected before the write
            reboot_pending <= 1'b0;
            irq2_line <= 1'b0; irq2_latch <= 1'b0; irq1_pulse <= 1'b0; // CPU reset clears irq
                // state (adsp2100.cpp:661-663); input_data (board latch) persists
            tim_irq_latch <= 1'b0;         // Phase-7 timer: CPU reset clears the
                // latch too (adsp2100.cpp:661-663); the SYSCONTROL soft reboot
                // does NOT run dcs_reset (adsp_control_w case SYSCONTROL_REG,
                // dcs.cpp:1872-1879 = pulse CPU reset + dcs_boot only), so
                // tim_scale/count/period persist; enable dies with MSTAT<=0.
            end else if (host_rst_r) begin
            dr_done <= 1'b0; dr_idx <= 0; div_done <= 1'b0; div_i <= 5'd0;   // discard in-flight Phase-2 progress
            // ---- BOARD async reset (Phase 7 §4.2, dcs.cpp:1456 reset_w ->
            //      dcs_reset): reset bank to 0 + reload bank 0 (dcs.cpp:551-553
            //      + dcs_boot 593). Replaces the reset_ats[] replay; the pin is
            //      driven by board glue on silicon / the TB in sim. Body is the
            //      old captured-reset body verbatim minus the replay pointer.
            //      (Like the old branch, ab_* persists: MAME dcs_reset kills the
            //      dmadac via the SYSCONTROL/S1_AUTOBUF mirrors, unobservable
            //      here until the firmware re-arms TX1 -- baseline-identical.)
            pc <= 14'h0000; o_valid <= 1'b0; o_unimpl <= 1'b0;
            loop_sp <= 0; pc_sp <= 0; cntr_sp <= 0; cntr <= 14'h0; stat_sp <= 0; status_last_valid <= 1'b0; pc_last_valid <= 1'b0;
            astat<=0; mstat<=0; sstat<=0; imask<=0; icntl<=0; px<=0;
            afb[0]<=0; afb[1]<=0; mfb[0]<=0; mfb[1]<=0; sbb[0]<=0; sbb[1]<=0; mrzb[0]<=0; mrzb[1]<=0;
            for (k=0;k<8;k=k+1) begin iR[k]<=0; mR[k]<=0; lR[k]<=0; baseR[k]<=0; lmask[k]<=14'h3fff; end
            for (k=0;k<32;k=k+1) gr[k]<=0;   // both banks (N14)
            for (k=0;k<4;k=k+1)  loop_end[k]<=NO_LOOP;
            data_bank <= 11'h0; launch_boot(11'h0);
            latch_control <= 16'h0C00; // board reset_w -> dcs_reset SETs both latches EMPTY
                // (dcs.cpp:585-586); output_data persists (dcs_reset does not clear it)
            irq2_line <= 1'b0; irq2_latch <= 1'b0; irq1_pulse <= 1'b0; // dcs_reset clears IRQ2
                // (dcs.cpp:582) + CPU reset clears irq state; input_data persists
            // Phase-7 timer at dcs_reset: scale back to 1 (dcs.cpp:598); pending
            // latch cleared (CPU reset clears irq state, adsp2100.cpp:661-663);
            // enable dies with MSTAT<=0 above. count/period members persist in
            // MAME (dcs_reset touches neither m_timer_start_count nor
            // m_timer_period) -- keep the live shadows too.
            tim_scale <= 9'd1; tim_scale_cnt <= 9'd1; tim_irq_latch <= 1'b0;
            end else if (((icntl[2] ? irq2_latch : irq2_line) && imask[5]) ||
                     (irq1_pulse && imask[2]) ||
                     (tim_irq_latch && imask[0])) begin
            state <= S_FETCH;                // vector fetch next (entry = bubble)
            // Discard in-flight Phase-2 progress: an IRQ preempting mid-S_DRAIN/
            // S_MEM is safe because those states are side-effect-free reads --
            // after the vector the boundary restarts and re-reads identical
            // values (memory is untouched; the drain commit never happened).
            dr_done <= 1'b0; dr_idx <= 0; div_done <= 1'b0; div_i <= 5'd0;
            // ---- GENERATED interrupt (Phase 7: the ONLY interrupt source) ----
            // adsp2101_device::check_irqs (adsp2100.cpp:966-999): IRQ2 checked
            // first (level or latch per ICNTL bit2), then IRQ1 (autobuffer-wrap
            // pulse), then the TIMER (latch only, no ICNTL mux, lowest priority
            // indx 5, adsp2100.cpp:995-997). generate_irq (adsp2100.cpp:890-911):
            // mask check m_imask & (0x20 >> indx) -> IRQ2 indx=0 = bit5, IRQ1
            // indx=3 = bit2, TIMER indx=5 = bit0; push PC + status; vector =
            // 0x04 + indx*4; IMASK &= nesting? ~(0x3f>>indx) : ~0x3f (ICNTL bit4).
            push_pc(pc);      pc_sp   <= pc_sp + 1;
            if (MLAB_STATUS_STACK) begin
                status_mem[stat_sp] <= {mstat,imask,astat};
                status_last_addr <= stat_sp;
                status_last_data <= {mstat,imask,astat};
                status_last_valid <= 1'b1;
            end else begin
                stat_mstat[stat_sp] <= mstat;
                stat_imask[stat_sp] <= imask;
                stat_astat[stat_sp] <= astat;
            end
            stat_sp <= stat_sp + 1;
            if ((icntl[2] ? irq2_latch : irq2_line) && imask[5]) begin
                imask <= icntl[4] ? (imask & ~(16'h003F >> 0)) : (imask & ~16'h003F);
                pc <= 14'h0004;                 // 0x04 + 0*4
                irq2_latch <= 1'b0;             // generate_irq clears the latch (adsp2100.cpp:897)
            end else if (irq1_pulse && imask[2]) begin
                imask <= icntl[4] ? (imask & ~(16'h003F >> 3)) : (imask & ~16'h003F);
                pc <= 14'h0010;                 // 0x04 + 3*4
                irq1_pulse <= 1'b0;
            end else begin
                // TIMER (Phase 7 §4.1): vector 0x18 = 0x04 + 5*4; nesting mask
                // ~(0x3f>>5) = ~0x01; latch cleared only here (generate_irq,
                // adsp2100.cpp:897). Audio-inert for UMK3 (never unmasked in the
                // F19 window) -- the TB cross-check asserts zero entries.
                imask <= icntl[4] ? (imask & ~(16'h003F >> 5)) : (imask & ~16'h003F);
                pc <= 14'h0018;                 // 0x04 + 5*4
                tim_irq_latch <= 1'b0;
`ifndef SYNTHESIS
                tim_isr_entries = tim_isr_entries + 1;
`endif
            end
            o_valid <= 1'b0;                    // entry is a bubble (no retired instr)
            end else begin
              case (state)

                S_DECODE: begin
                    // ---- S_DECODE: fetch_q valid. Latch the opcode + the
                    //      pre-decoded memory access (combinational over
                    //      fetch_q + DAG state, both stable until EXEC) and
                    //      dispatch to the owed stall states in the baseline
                    //      priority order: drain > divider > ROM > MEM > EXEC.
                    op_r       <= fetch_q;
                    generic_read_select_r <= shared_reg_read_select(fetch_q);
                    ea_addr_r  <= pre_addr;
                    pm_addr_r  <= pre_pm_addr;
                    pm_rd_r    <= pre_pm_rd;
                    bank_rd_r  <= pre_bank_rd;
                    tx1_r      <= pre_tx1_wr;
                    mem_need_r <= mem_need;
                    if      (drain_pend && !dr_done)  state <= S_DRAIN;
                    else if (pre_tx1_wr && !div_done) state <= S_DIV;
                    else if (pre_bank_rd && !rom_rdy) state <= S_ROM;
                    else if (mem_need != 2'd0)        state <= S_MEM;
                    else                              state <= S_EXEC;
                end

                S_DRAIN: begin
            // ---- S_DRAIN (N19): stream the autobuffer drain's DM reads one word
            //      per clock through the clocked ports (issue read j this clock,
            //      capture it next clock), replacing the old ~240-reads-in-one-
            //      clock burst. The reads are side-effect-free and memory is
            //      quiescent (CPU stalled, nothing else writes), so the sample
            //      values and their order are EXACTLY the baseline burst's. The
            //      pointer/wrap SEMANTICS are untouched: the same accumulator
            //      arithmetic runs here (reg += m_incs per sample, dcs.cpp:1975),
            //      and the architectural COMMIT (I<ireg> advance, wrap check vs
            //      the live DAG base, IRQ1 pulse, countdown reload, dac_ce) still
            //      happens in the upcoming EXEC clock in the baseline's
            //      nonblocking order -- so the retiring instruction reads
            //      pre-drain state and wins any same-clock write collision,
            //      keeping the Gate-1 PC stream identical (crux §0 covers PCM,
            //      but Gate 1 requires the exact instruction-boundary phase).
            o_valid <= 1'b0;
            if (dr_idx == 0) begin
                // N20: the arm-time quotient IS ab_size/(2*incs) (dcs.cpp:1968)
                // -- ab_size/ab_incs are latched only by the arm, which also
                // latched ab_drain_cnt from the same divide. No runtime '/'.
                dr_cnt = ab_drain_cnt;
`ifndef SYNTHESIS
                if (dr_cnt != (ab_size / (2 * ((ab_incs==16'h0) ? 16'd1 : ab_incs)))) begin
                    $display("FATAL: N20 drain-count mismatch cnt=%0d expect=%0d",
                             dr_cnt, ab_size / (2 * ((ab_incs==16'h0) ? 16'd1 : ab_incs)));
                    $finish;
                end
`endif
            end
            if (dr_idx > 0 && dr_idx <= dr_cnt) begin
                // capture sample (dr_idx-1), issued last clock
                case (dr_region)
                  RG_ALIAS: dr_smp = pmb_q[23:8];              // output buffer lives here
                  RG_BANK : dr_smp = {8'hFF, snd_byte(dr_rom_a)}; // unreachable (buffer is RAM,
                                    // ROM window is unwritable); SIM fallback keeps values exact
                  RG_LATCH: dr_smp = input_data;               // unreachable likewise
                  default : dr_smp = dm_q;
                endcase
                dac_emit_burst[dr_idx-1] <= dr_smp;
                dac_sample <= dr_smp;
                // Hardware needs every sample, not merely the final sample of
                // a DCS half-buffer. Keep the legacy end-of-burst strobe for
                // the bit-exact F19 harness, and stream one sample per drain
                // cycle only when the board wrapper explicitly selects it.
                if (PCM_STREAM)
                    dac_ce <= 1'b1;
            end
            if (dr_idx < dr_cnt) begin
                // issue read dr_idx this clock (port address = dr_cur via the muxes)
                dr_region <= dm_region(dr_cur[15:0]);
                dr_rom_a  <= ({data_bank, 12'h0} + {10'h0, dr_cur[11:0]});
                dr_acc    <= dr_cur + {16'h0, ab_incs};        // dcs.cpp:1975 reg += m_incs
                dr_idx    <= dr_idx + 1;
            end else begin
                dr_done   <= 1'b1;       // all captured; EXEC commits next
                // dispatch on: the baseline chain's next-priority stall
                state     <= (tx1_r && !div_done)    ? S_DIV
                           : (bank_rd_r && !rom_rdy) ? S_ROM
                           : (mem_need_r != 2'd0)    ? S_MEM
                           :                           S_EXEC;
            end
                end

                S_DIV: begin
            // ---- N20 divider stall: one restoring-division step per clock,
            //      computing div_q = lR[lreg] / (2*incs) for the TX1 arm about
            //      to execute. No architectural state changes and no retire
            //      (Gate-1 stream + drain cadence untouched; the added clocks
            //      are covered by the §0 crux). Preempted cleanly by the IRQ
            //      branches above (div state is discarded and re-runs after
            //      the vector, exactly like an in-flight S_MEM pre-read).
            o_valid <= 1'b0;
            if (div_i == 5'd0) begin
                div_v   <= {pre_ab_incs, 1'b0};   // divisor = 2*incs (17-bit)
                div_nd  <= lR[pre_ab_lr];         // dividend
                div_rem <= 17'h0;
                div_q   <= 16'h0;
                div_i   <= 5'd1;
            end else begin
                div_t = {div_rem, div_nd[15]};    // shift in next dividend bit
                if (div_t >= {1'b0, div_v}) begin
                    div_rem <= div_t - {1'b0, div_v};   // fits 17 bits: rem < divisor
                    div_q   <= {div_q[14:0], 1'b1};
                end else begin
                    div_rem <= div_t[16:0];             // < divisor <= 0x1FFFE
                    div_q   <= {div_q[14:0], 1'b0};
                end
                div_nd <= {div_nd[14:0], 1'b0};
                if (div_i == 5'd16) begin
                    div_done <= 1'b1;
                    state    <= (bank_rd_r && !rom_rdy) ? S_ROM
                              : (mem_need_r != 2'd0)    ? S_MEM
                              :                           S_EXEC;
                end else
                    div_i    <= div_i + 5'd1;
            end
                end

                S_ROM: begin
            // ---- Phase 5: banked-ROM window (DM 0x2000-0x2FFF) DDR3 round trip
            //      in flight -- stall until the prefetch cache / modeled DDR3
            //      port presents the byte (rom_rdy). No architectural state
            //      changes and no retire: the Gate-1 PC stream is untouched,
            //      and per the §0 crux the variable stall clocks cannot move
            //      the PCM. An IRQ preempting this stall (branches above)
            //      simply abandons the request; dcs_mem completes the fill
            //      into the cache (ROM is constant) and re-serves the address
            //      re-issued after the vector.
                    if (rom_rdy)
                        state <= (mem_need_r != 2'd0) ? S_MEM : S_EXEC;
                end

                S_MEM: begin
            // ---- S_MEM: issue this instruction's data read to the clocked
            //      port(s) (address = the S_DECODE latches via the muxes; data
            //      valid next clock, consumed by S_EXEC). One clock; no
            //      architectural state changes; no retire (Gate-1 untouched;
            //      per the §0 crux the added clocks cannot move the PCM).
                    state <= S_EXEC;
                end

                default: ;   // unreachable (outer case covers these five)
              endcase
            end
          end

          // ================================================================
          // §5.3 WRITEBACK-HAZARD TABLE -- every nonblocking read-old-value /
          // last-write-wins ordering the verbatim S_EXEC body relies on.
          // S_EXEC commits the whole instruction in ONE clock, so Verilog NBA
          // semantics reproduce the behavioral model EXACTLY: every read sees
          // the PRE-instruction state, and on a same-register clash the
          // LEXICALLY-LAST write in this block wins. Verified by the +hprobe
          // register-stream capture (TB tb_adsp2105.sv: post-writeback state
          // of every retired instruction over windows [1.04M,1.09M) Gate-1 +
          // [2.80M,2.90M) track-decode, byte-identical pre-cut vs post-cut)
          // plus the +cprobe spot hooks and both PCM gates.
          //  #  | site (op class)          | ordering relied on
          //  H1 | 0x10 shift + reg move    | move reads PRE-shift src; move
          //     |                          | (last NBA) WINS over shift dest
          //  H2 | 0x11 PM read variant     | shift first; reg<=PM[23:8] (mem,
          //     |                          | last) WINS over shift dest; px
          //  H3 | 0x11 PM write variant    | PM write stores PRE-shift reg
          //     |                          | (write emitted before shift_do)
          //  H4 | 0x12/13 DM read variant  | shift first; reg<=DM (last) WINS
          //     | 0x12/13 DM write variant | DM write stores PRE-shift reg
          //  H5 | 0x28-2F ALU/MAC + move   | mvtmp = PRE-op src (NBA read);
          //     |                          | move (last) WINS over compute dest
          //  H6 | 0x50-5F PM read variant  | compute first; reg<=PM[23:8]
          //     |                          | (last) WINS over compute dest; px
          //     | 0x50-5F PM write variant | PM write stores PRE-compute reg
          //  H7 | 0x60-7F DM read variant  | compute first; reg<=DM (last)
          //     |                          | WINS over compute dest
          //     | 0x60-7F DM write variant | DM write stores PRE-compute reg
          //  H8 | drain commit vs instr    | drain's iR/baseR writes are
          //     |                          | EARLIER in the block: the retiring
          //     |                          | instruction reads PRE-drain
          //     |                          | I<ireg>; its own DAG writes WIN
          //  H9 | TX1 arm vs drain commit  | wr_reg(TX1) arm is LATER: the
          //     |                          | arm's ab_countdown reload WINS
          //     |                          | over the same-clock drain reload
          //  H10| CNTR writes vs loop-end  | loop-end CE cntr decrement is
          //     |                          | EARLIER; a same-clock wr_reg
          //     |                          | CNTR-push/OWRCNTR write WINS
          //     |                          | (gospel overwrite semantics)
          // ================================================================
          S_EXEC: begin
            state <= S_FETCH;                 // consume; next clock re-fetches new PC
            dr_done <= 1'b0; dr_idx <= 0; div_done <= 1'b0; div_i <= 5'd0;  // fresh progress for the next boundary
            // -------- fetch --------
            o_ppc   <= pc;
            o_valid <= 1'b1;
            o_unimpl<= 1'b0;
            // ---- Phase-7 TIMER engine (§4.1): one prescale step per RETIRED
            //      instruction while MSTAT bit5 is set (MSTAT_TIMER=0x20,
            //      2100ops.hxx:74; enable-change routes through update_mstat ->
            //      dcs timer_enable_callback, dcs.cpp:1787-1806). Retired
            //      instructions proxy CPU cycles (dcs.cpp:1700 counts
            //      total_cycles) exactly as the drain's 320*count model does.
            //      Every tim_scale instrs = one timer clock (TIMER_SCALE,
            //      dcs.cpp:1923-1925); TCOUNT underflow -> reload TPERIOD +
            //      edge-latch the IRQ (dcs.cpp:1727-1736): first fire after
            //      scale*(count+1), then every scale*(period+1) (dcs.cpp:1783,
            //      1727). Placed BEFORE the instruction body so a same-clock
            //      DM($3FFB-D) control write WINS the NBA clash (gospel
            //      overwrite semantics, same ordering rule as H10).
            if (mstat[5]) begin
`ifndef SYNTHESIS
                tim_enabled_ever <= 1'b1;
`endif
                if (tim_scale_cnt <= 9'd1) begin
                    tim_scale_cnt <= tim_scale;
                    if (tim_count == 16'h0) begin
                        tim_count     <= tim_period;   // reload (dcs.cpp:1727 period+1 cadence)
                        tim_irq_latch <= 1'b1;         // edge pulse -> latch (dcs.cpp:1734-1736)
`ifndef SYNTHESIS
                        tim_fire_count = tim_fire_count + 1;
`endif
                    end else
                        tim_count <= tim_count - 16'h1;
                end else
                    tim_scale_cnt <= tim_scale_cnt - 9'd1;
            end
            // IRQ1 pulse decay: MAME's wrap pulse (pulse_input_line) is transient;
            // in level mode (ICNTL bit1=0) a masked pulse is lost, not held. One
            // boundary check then gone (a same-cycle wrap re-set below wins).
            if (irq1_pulse) irq1_pulse <= 1'b0;
            // ---- SPORT1 autobuffer drain (dcs.cpp dcs_irq): advance I<ireg> so the
            //      firmware output-buffer wait-loop (I7 < AY0) falls through.
            //      IRQ1-on-wrap is GENERATED (irq1_pulse, dcs.cpp:1990-1991).
            // Phase 8a item 1: commit only once S_DRAIN has actually streamed the
            // samples (dr_done). dac_slot_go is set asynchronously by the DAC-rate
            // accumulator, so it can rise mid-instruction (after this instruction's
            // S_DECODE already ran) -- without the dr_done guard that instruction
            // would reach S_EXEC and "commit" a 0-sample drain. Deferring to the
            // next instruction (whose S_DECODE dispatches S_DRAIN via drain_pend)
            // keeps the stream->commit sequence intact. In the OLD countdown model
            // drain_pend rose cleanly at an S_EXEC->S_DECODE boundary so dr_done
            // was always already set here; the guard is a no-op there and the exact
            // fix for the async DAC trigger.
            if (ab_active && dac_slot_go && dr_done) begin
                begin
                    // ---- drain COMMIT (Phase 2 / N19): the count samples were
                    // already streamed one-per-clock by S_DRAIN (dcs.cpp:1972-1976
                    // buffer[i]=m_data->read_word(reg); reg+=m_incs -- values and
                    // order identical to the old one-clock burst; memory was
                    // quiescent). Here the architectural effects land in the SAME
                    // clock as the retiring instruction, in the baseline's
                    // nonblocking order: the instruction reads pre-drain I<ireg>
                    // and its own writes win a same-clock collision. Emission =
                    // dcs.cpp:1979 dmadac_transfer, m_channels=1 mono (dcs.cpp:766).
                    ab_cnt = dr_cnt;    // latched at stream start (= ab_size/(2*incs))
                    ab_reg = dr_cur;    // final pointer after cnt increments (cnt==0 -> iR unchanged)
                    dac_burst_len = ab_cnt;                      // #samples in this burst
                    if (!PCM_STREAM)
                        dac_ce <= 1'b1;                          // legacy F19 burst strobe
                    // wrap check vs the LIVE DAG base (dcs.cpp:1983 m_ireg_base =
                    // m_cpu->get_ibase(m_ireg), i.e. m_base[ireg], not an armed-time
                    // snapshot)
                    if (ab_reg >= ({16'h0, baseR[ab_ireg]} + ab_size)) begin
                        ab_reg = {16'h0, baseR[ab_ireg]};  // reset to base (dcs.cpp:1984-1987)
                        irq1_pulse <= 1'b1;         // pulse IRQ1 on wrap (dcs.cpp:1990-1991)
                    end
                    iR[ab_ireg]  <= ab_reg & 16'h3FFF;
                    // write-back re-bases too (dcs.cpp:1995 set_state_int -> update_i)
                    baseR[ab_ireg] <= ab_reg[13:0] & lmask[ab_ireg];
                    // Phase 8a item 1: consume the drain-due flag. The DAC-slot
                    // counter already reloaded to `count` when it expired (in the
                    // dac_ce_in accumulator below), so the next buffer-half of
                    // sample slots is already being counted -- no reload here.
                    dac_slot_go <= 1'b0;
                end
            end
            op = op_r;      // Phase 6: opcode latched at S_DECODE (== fetch_q)
`ifndef SYNTHESIS
            // fetch_q re-reads pm[pc] every clock and pc/PM only move at EXEC,
            // so the S_DECODE latch must still equal the live fetch port here.
            if (op_r !== fetch_q) begin
                $display("FATAL: Phase-6 op-latch mismatch pc=%04x op_r=%06x fetch_q=%06x",
                         pc, op_r, fetch_q);
                $finish;
            end
`endif
            hi = op[23:16];
            generic_read_select = generic_read_select_r;
            generic_read_data = rd_reg(generic_read_select[5:4],generic_read_select[3:0]);

            // -------- Phase 8c: shared datapath, evaluated ONCE per instruction
            //          (single HW instance; consumed by the case writebacks) -----
            mac_r   = mac_r64_f(op[16:13]);
            alu_res = alu_eval(op[16:13], alu_xread(op[10:8]), alu_yread(op[12:11]));
            shift_eval(op[14:11], op[10:8], (hi==8'h0F) ? op[7:0] : `G0(9)[7:0],
                       shift_res_v, shift_se_v, shift_ss_v, shift_sbr_v,
                       shift_se_we, shift_ss_we, shift_sbr_we);

            // -------- sequencer default advance (with loop handling) --------
            do_loop_back = 1'b0; do_loop_exit = 1'b0;
            if (loop_sp != 0 && pc == loop_end[loop_sp-1]) begin
                if (loop_cond[loop_sp-1] == 4'hE) begin
                    // CE: predecrement cntr; >0 keep looping else exit+pop cntr
                    if ($signed({1'b0,cntr}) - 1 > 0) begin
                        cntr <= cntr - 1'b1; do_loop_back = 1'b1;
                    end else begin
                        cntr <= cntr - 1'b1;
                        cntr <= cntr_stack[cntr_sp-1]; cntr_sp <= cntr_sp - 1; // pop restores
                        do_loop_exit = 1'b1;
                    end
                end else if (cond_true(loop_cond[loop_sp-1])) begin
                    do_loop_back = 1'b1;          // condition not yet met -> loop
                end else begin
                    do_loop_exit = 1'b1;          // met -> fall through
                end
            end

            if (do_loop_back)      pc <= pc_top;
            else if (do_loop_exit) begin
                loop_sp <= loop_sp - 1; pc_sp <= pc_sp - 1; pc <= pc + 1'b1;
            end else               pc <= pc + 1'b1;

            // -------- execute (control-flow + counter effects) --------------
            case (hi)
              8'h00: ; // NOP

              8'h05: // SAT MR (adsp2100.cpp case 0x05): if MV, saturate by MR2 bit7
                  if (astat[6]) begin
                      if (`G0(13)[7]) begin `G0(13)<=16'hffff; `G0(12)<=16'h8000; `G0(11)<=16'h0000; end
                      else           begin `G0(13)<=16'h0000; `G0(12)<=16'h7fff; `G0(11)<=16'hffff; end
                  end

              8'h06: begin // DIVS (adsp2100.cpp case 0x06)
                  dmv   = alu_yread(op[12:11]);                       // yop
                  mvtmp = alu_xread(op[10:8]) ^ dmv;                  // temp = xop^yop
                  astat <= (astat & ~16'h0020) | (mvtmp[15] ? 16'h0020 : 16'h0000); // Q flag
                  `AF    <= {dmv[14:0], `G0(4)[15]};                    // AF = (y<<1)|(AY0>>15)
                  `G0(4) <= {`G0(4)[14:0], mvtmp[15]};                  // AY0 = (AY0<<1)|(temp>>15)
              end

              8'h07: begin // DIVQ (adsp2100.cpp case 0x07)
                  if (astat[5]) dmv = `AF + alu_xread(op[10:8]);       // GET_Q ? AF+x
                  else          dmv = `AF - alu_xread(op[10:8]);       //       : AF-x
                  mvtmp = dmv ^ alu_xread(op[10:8]);                  // temp = res^xop
                  astat <= (astat & ~16'h0020) | (mvtmp[15] ? 16'h0020 : 16'h0000);
                  `AF    <= {dmv[14:0], `G0(4)[15]};                    // AF = (res<<1)|(AY0>>15)
                  `G0(4) <= {`G0(4)[14:0], ~mvtmp[15]};                 // AY0 = (AY0<<1)|(~temp>>15)
              end

              8'h09: // MODIFY (Iy,Mn) -- adsp2100.cpp:1335-1338: ireg=BIT(op,2,3),
                     // mreg=(ireg&4)|(op&3); pure address-register modify
                  request_dag_modify(op[4:2], {op[4], op[1:0]});

              8'h0B: begin  // conditional JUMP/CALL indirect (adsp2100.cpp case 0x0b):
                            // target = I[4 + op(7:6)] & 0x3fff; op[4]=1 -> push return
                  cond_eval(op[3:0], cflag);
                  if (cflag) begin
                      if (op[4]) begin
                          push_pc(pc + 1'b1); pc_sp <= pc_sp + 1;
                      end
                      pc <= iR[{1'b1, op[7:6]}][13:0];
                  end
              end

              8'h0A: begin  // conditional RTS / RTI
                  cond_eval(op[3:0], cflag);
                  if (cflag) begin
                      pc <= pc_top; pc_sp <= pc_sp - 1;   // pop return PC
                      if (op[4]) begin                               // RTI: restore status
                          set_mstat(MLAB_STATUS_STACK ? status_top[47:32] : stat_mstat[stat_sp-1]);          // may swap bank back
                          imask <= MLAB_STATUS_STACK ? status_top[31:16] : stat_imask[stat_sp-1];
                          astat <= MLAB_STATUS_STACK ? status_top[15:0] : stat_astat[stat_sp-1];
                          stat_sp <= stat_sp - 1;
                      end
                  end
              end

              8'h0C: begin  // mode control: set/clear MSTAT bits (swap bank if BANK toggles)
                  // full gospel pair set, adsp2100.cpp:1360-1372 (chip>=2101
                  // pairs included -- this IS a 2105): each pair = (enable bit,
                  // value bit) -> GOMODE op[3]/op[2], INTEGER op[13]/op[12],
                  // TIMER op[15]/op[14] (the Phase-7 timer enable, MSTAT bit5),
                  // BANK op[5]/op[4], REVERSE op[7]/op[6], STICKYV op[9]/op[8],
                  // SATURATE op[11]/op[10].
                  mstat_tmp = mstat;
                  if (op[3])  mstat_tmp = (mstat_tmp & ~16'h0040) | (op[2]  ? 16'h0040 : 16'h0); // GOMODE
                  if (op[13]) mstat_tmp = (mstat_tmp & ~16'h0010) | (op[12] ? 16'h0010 : 16'h0); // INTEGER
                  if (op[15]) mstat_tmp = (mstat_tmp & ~16'h0020) | (op[14] ? 16'h0020 : 16'h0); // TIMER
                  if (op[5])  mstat_tmp = (mstat_tmp & ~16'h0001) | ((op>>4) & 16'h0001); // BANK
                  if (op[7])  mstat_tmp = (mstat_tmp & ~16'h0002) | ((op>>5) & 16'h0002); // REVERSE
                  if (op[9])  mstat_tmp = (mstat_tmp & ~16'h0004) | ((op>>6) & 16'h0004); // STICKYV
                  if (op[11]) mstat_tmp = (mstat_tmp & ~16'h0008) | ((op>>7) & 16'h0008); // SATURATE
                  set_mstat(mstat_tmp);
              end

              8'h0D: // internal data register move: reg_grp[a][b] = reg_grp[c][d]
                  request_reg_write(op[11:10], op[7:4], (SHARED_REG_READ ? generic_read_data : rd_reg(op[9:8], op[3:0])));

              8'h0E: begin // conditional shift (sc = SE)
                  cond_eval(op[3:0], cflag);
                  if (cflag) shift_wb(op[14:11]);
              end

              8'h0F: // shift immediate (sc = signed op[7:0])
                  shift_wb(op[14:11]);

              8'h10: begin // shift + internal reg move (adsp2100.cpp case 0x10)
                  shift_wb(op[14:11]);
                  request_reg_write(2'd0, op[7:4], (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[3:0]))); // move AFTER shift (wins on clash)
              end

              8'h11: begin // shift + PM(I,M) r/w DAG2 (adsp2100.cpp case 0x11)
                  iidx = {1'b1, op[3:2]}; midx = {1'b1, op[1:0]};
                  if (op[15]) begin // pgm write BEFORE shift (reads pre-shift reg)
                      pm_we = 1'b1; pm_wa = iR[iidx][13:0]; pm_wd = {(SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])), px[7:0]};
                      shift_wb(op[14:11]);
                  end else begin    // shift FIRST, then reg <= PM (mem value wins on clash)
                      shift_wb(op[14:11]);
                      // Phase 2: PM word pre-read by S_MEM at iR[iidx][13:0] (pmb_q)
                      request_reg_write(2'd0, op[7:4], pmb_q[23:8]);
                      px <= {8'h0, pmb_q[7:0]};
`ifndef SYNTHESIS
                      if (iR[iidx] != {2'b0, pm_addr_r}) begin
                          $display("FATAL: Phase-6 pre-read addr mismatch (0x11 PM) pc=%04x op=%06x pre=%04x used=%04x",
                                   pc, op, pm_addr_r, iR[iidx]);
                          $finish;
                      end
`endif
                  end
                  request_dag_modify(iidx, midx);
              end

              8'h12,8'h13: begin // shift (sc=SE) + DM(I,M) r/w -- 0x12=DAG1, 0x13=DAG2
                                 // (adsp2100.cpp cases 0x12/0x13)
                  iidx = {op[16], op[3:2]}; midx = {op[16], op[1:0]};
                  if (op[15]) begin // mem write BEFORE shift (gospel order)
                      request_dm_write(dag_addr(iidx), (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])));
                      shift_wb(op[14:11]);
                  end else begin    // shift FIRST, then reg <= DM
                      shift_wb(op[14:11]);
                      dm_load(dag_addr(iidx), dmv); request_reg_write(2'd0, op[7:4], dmv);
                  end
                  request_dag_modify(iidx, midx);
              end

              8'h14,8'h15,8'h16,8'h17: begin           // DO <addr> UNTIL <cond>
                  loop_end [loop_sp] <= op[17:4];
                  loop_cond[loop_sp] <= op[3:0];
                  loop_sp            <= loop_sp + 1;
                  push_pc(pc + 1'b1);      // loop top = next instr
                  pc_sp              <= pc_sp + 1;
              end

              8'h18,8'h19,8'h1A,8'h1B,                  // conditional JUMP/CALL imm (op[18]=CALL)
              8'h1C,8'h1D,8'h1E,8'h1F: begin
                  tgt = op[17:4];
                  cond_eval(op[3:0], cflag);
                  if (cflag) begin
                      if (op[18]) begin                 // CALL: push return address (pc+1)
                          push_pc(pc + 1'b1); pc_sp <= pc_sp + 1;
                      end
                      pc <= tgt;                        // overrides default advance
                  end
              end

              8'h20,8'h21,8'h22,8'h23,8'h24,8'h25,8'h26,8'h27: begin // conditional ALU/MAC
                  // adsp2100.cpp:1472-1511: 0x20/21 MAC->MR, 0x22/23 ALU->AR,
                  // 0x24/25 MAC->MF, 0x26/27 ALU->AF. op[17]=ALU, op[18]=alt dest.
                  cond_eval(op[3:0], cflag);
                  if (cflag) begin
                      if (op[17])       // ALU op (dest AR / AF per op[18])
                          alu_wb(op[18]);
                      else              // MAC op (dest MR / MF per op[18])
                          mac_wb(op[16:13], op[18]);
                  end
              end

              8'h28,8'h29,8'h2A,8'h2B,8'h2C,8'h2D,8'h2E,8'h2F: begin
                  // ALU/MAC with internal data register move (adsp2100.cpp:1512-1541):
                  // UNCONDITIONAL; temp = reg0[op(3:0)] read BEFORE the op, written
                  // to reg0[op(7:4)] AFTER (move wins over the compute on a clash).
                  mvtmp = (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[3:0]));
                  if (op[17])
                      alu_wb(op[18]);
                  else
                      mac_wb(op[16:13], op[18]);
                  request_reg_write(2'd0, op[7:4], mvtmp);
              end

              8'h30,8'h31,8'h32,8'h33,8'h34,8'h35,8'h36,8'h37, // load non-data reg imm (14b)
              8'h38,8'h39,8'h3A,8'h3B,8'h3C,8'h3D,8'h3E,8'h3F: begin
                  grp  = op[19:18]; ridx = op[3:0];
                  request_reg_write(grp, ridx, {2'b0, op[17:4]});
              end

              8'h40,8'h41,8'h42,8'h43,8'h44,8'h45,8'h46,8'h47, // load data reg imm (16b)
              8'h48,8'h49,8'h4A,8'h4B,8'h4C,8'h4D,8'h4E,8'h4F: begin
                  request_reg_write(2'd0, op[3:0], op[19:4]);
              end

              8'h50,8'h51,8'h52,8'h53,8'h54,8'h55,8'h56,8'h57, // ALU/MAC + PM(I,M) r/w
              8'h58,8'h59,8'h5A,8'h5B,8'h5C,8'h5D,8'h5E,8'h5F: begin
                  if (op[17:13] != 5'h0) begin   // parallel ALU/MAC
                      if (op[17])       alu_wb(op[18]);
                      else              mac_wb(op[16:13], op[18]); // MR/MF per op[18]
                  end
                  iidx = {1'b1, op[3:2]};   // I4 + BIT(op,2,2)  -> index 4..7
                  midx = {1'b1, op[1:0]};   // M4 + BIT(op,0,2)
                  // PM data access is 24-bit via PX: reg=PM[23:8], px=PM[7:0]; PM=(reg<<8)|px
                  if (op[19]) begin
                      pm_we = 1'b1; pm_wa = iR[iidx][13:0]; pm_wd = {(SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])), px[7:0]}; // PM(I,M)=reg
                  end else begin
                      // Phase 2: PM word pre-read by S_MEM at iR[iidx] (pmb_q)
                      request_reg_write(2'd0, op[7:4], pmb_q[23:8]);                       // reg=PM[23:8]
                      px <= {8'h0, pmb_q[7:0]};                                 // px=PM[7:0]
`ifndef SYNTHESIS
                      if (iR[iidx] != {2'b0, pm_addr_r}) begin
                          $display("FATAL: Phase-6 pre-read addr mismatch (0x50 PM) pc=%04x op=%06x pre=%04x used=%04x",
                                   pc, op, pm_addr_r, iR[iidx]);
                          $finish;
                      end
`endif
                  end
                  request_dag_modify(iidx, midx);       // circular post-modify (2100ops.hxx:645-693 pm dag2)
              end

              8'h60,8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67, // ALU/MAC + DM(I,M) r/w
              8'h68,8'h69,8'h6A,8'h6B,8'h6C,8'h6D,8'h6E,8'h6F,
              8'h70,8'h71,8'h72,8'h73,8'h74,8'h75,8'h76,8'h77,
              8'h78,8'h79,8'h7A,8'h7B,8'h7C,8'h7D,8'h7E,8'h7F: begin
                  if (op[17:13] != 5'h0) begin      // parallel ALU/MAC op
                      if (op[17])       alu_wb(op[18]);
                      else              mac_wb(op[16:13], op[18]); // MR/MF per op[18]
                  end
                  iidx = {op[20], op[3:2]};  // (BIT20?4:0)+I(0..3)
                  midx = {op[20], op[1:0]};
                  if (op[19]) request_dm_write(dag_addr(iidx), (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4]))); // DM(I,M)=reg
                  else begin  dm_load(dag_addr(iidx), dmv); request_reg_write(2'd0, op[7:4], dmv); end
                  request_dag_modify(iidx, midx);       // circular post-modify (2100ops.hxx:575-641)
              end

              8'h80,8'h81,8'h82,8'h83,8'h84,8'h85,8'h86,8'h87, // DM(imm) r/w
              8'h88,8'h89,8'h8A,8'h8B,8'h8C,8'h8D,8'h8E,8'h8F,
              8'h90,8'h91,8'h92,8'h93,8'h94,8'h95,8'h96,8'h97,
              8'h98,8'h99,8'h9A,8'h9B,8'h9C,8'h9D,8'h9E,8'h9F: begin
                  daddr = op[17:4]; grp = op[19:18]; ridx = op[3:0];
                  if (op[20])
                      request_dm_write({2'b0,daddr}, (SHARED_REG_READ ? generic_read_data : rd_reg(grp, ridx)));    // DM(addr)=reg (all map cases)
                  else begin
                      dm_load({2'b0,daddr}, dmv); request_reg_write(grp, ridx, dmv); // reg=DM(addr)
                  end
              end

              8'hA0,8'hA1,8'hA2,8'hA3,8'hA4,8'hA5,8'hA6,8'hA7, // DM(I,M)=imm DAG1
              8'hA8,8'hA9,8'hAA,8'hAB,8'hAC,8'hAD,8'hAE,8'hAF, //   (adsp2100.cpp:1714-1718)
              8'hB0,8'hB1,8'hB2,8'hB3,8'hB4,8'hB5,8'hB6,8'hB7, // DM(I,M)=imm DAG2
              8'hB8,8'hB9,8'hBA,8'hBB,8'hBC,8'hBD,8'hBE,8'hBF: begin //   (adsp2100.cpp:1719-1723)
                  iidx = {op[20], op[3:2]}; midx = {op[20], op[1:0]}; // op[20]=0 -> I0-3/M0-3
                  request_dm_write(dag_addr(iidx), op[19:4]);
                  request_dag_modify(iidx, midx);       // circular post-modify (2100ops.hxx:575-597/624-641)
              end

              default: o_unimpl <= 1'b1;  // not yet implemented: sequencer already did pc++
            endcase
            if (SHARED_EXEC) begin
                if (exec_dm_we) dm_write(exec_dm_addr,exec_dm_data);
                if (exec_reg_we) wr_reg(exec_reg_group,exec_reg_index,exec_reg_data);
                if (exec_dag_we) dag_modify(exec_dag_index,exec_dag_modifier);
            end
          end
        endcase

        // ---- board reset line input register (Phase 7 §4.2): sampled every
        //      clock; the boundary-check states consume host_rst_r.
        if (!rst) host_rst_r <= host_rst;
        // ---- DAC-rate slot accumulator (Phase 8a item 1): one dac_ce_in pulse =
        //      one output sample slot consumed by the SPORT1 DAC frame. While the
        //      autobuffer is armed, count down a full buffer-half of slots
        //      (ab_drain_cnt = count = ab_size/(2*incs)); on the last slot, reload
        //      and raise dac_slot_go so the next instruction boundary dispatches
        //      the S_DRAIN stream + EXEC commit (drain_pend). Free-running off the
        //      DAC clock enable, decoupled from the CPU instruction rate -- this
        //      is the retiming: the drain EVENT is unchanged, its TRIGGER is now
        //      the DAC clock. Sampled here (after the FSM case, before host_wr) so
        //      the arm's re-prime in S_EXEC (lexically earlier) is overridden by a
        //      truly-coincident pulse only in the impossible same-clock re-arm
        //      case; in practice arm and dac_ce_in never coincide (arm is one
        //      instruction, pulses are ~320 instrs apart). Placed after the drain
        //      COMMIT's `dac_slot_go<=0` (S_EXEC, earlier) so a pulse landing on
        //      the very commit clock re-raises correctly (cannot happen: the
        //      commit is `count` slots after the previous raise).
        if (!rst && dac_ce_in && ab_active) begin
            if (dac_slot_ctr <= 16'd1) begin
                dac_slot_ctr <= ab_drain_cnt;   // reload one buffer-half of slots
                dac_slot_go  <= 1'b1;            // a drain is due at the next boundary
            end else
                dac_slot_ctr <= dac_slot_ctr - 16'd1;
        end
        // ---- host command write (dcs.cpp:1503-1520 dcs_delayed_data_w): latch the
        //      data + assert the IRQ2 line + SET_INPUT_FULL; the CLEAR->ASSERT edge
        //      also sets the CPU-side latch (adsp2100.cpp:1164-1171). Placed last so
        //      it wins over a same-cycle auto-ack (an ADSP read of DM 0x3400 in the
        //      FSM case above SET_INPUT_EMPTY; a coincident host write re-fills).
        if (host_cmd_w && !rst) begin
            input_data <= host_cmd_data;
            if (!irq2_line) irq2_latch <= 1'b1;
            irq2_line  <= 1'b1;
            latch_control <= latch_control & ~16'h0800; // SET_INPUT_FULL (dcs.cpp:187)
        end
        // ---- host response read (dcs.cpp:1626-1639 data_r + auto-ack): the host
        //      reading host_response_r SETs OUTPUT_EMPTY (delayed_ack_w, dcs.cpp:
        //      1607-1609). Level-strobe from the board; harmless when idle. Placed
        //      after the ADSP output_latch_w in the FSM case, so a same-cycle ADSP
        //      write (SET_OUTPUT_FULL) that races a host read is resolved OUTPUT_
        //      EMPTY here -- but the two never coincide in practice (different
        //      clock domains on silicon; the mailbox is half-duplex per direction).
        if (host_resp_rd && !rst)
            latch_control <= latch_control | 16'h0400;  // SET_OUTPUT_EMPTY (dcs.cpp:182)
        // ---- Phase 8c: consolidated single PM write port (drives both duplicated
        //      copies). The 4 former `PM[x]<=y sites set pm_we/pm_wa/pm_wd (blocking)
        //      earlier in this same evaluation; they are mutually exclusive so at
        //      most one fires per clock -> one write/clock, one write port per copy.
        //      Commit is nonblocking at this clock edge = identical timing to the
        //      former in-place `PM[x]<=y writes.
        if (!EXPLICIT_RAM_CE && !SHARED_PM && pm_we) pm2[pm_wa] <= pm_wd;
        end
        // Keep this port in the writer's process: pm_we/pm_wa/pm_wd are
        // blocking temporaries calculated above, so a separate always block
        // would race in simulation. A common read/write address infers one
        // bidirectional RAM port, plus the independent fetch port above.
        pm_port_b_addr = (SHARED_PM && !pm_we) ? pmb_addr : pm_wa;
        if (rst) begin
            pc_write_toggle <= 1'b0;
            pc_written_toggle <= 1'b0;
        end else begin
            pc_written_toggle <= pc_write_toggle;
            if (MLAB_PC_STACK && pc_write_toggle != pc_written_toggle)
                pc_mem[pc_last_addr] <= pc_last_data;
        end
        if (cpu_ce) begin
            if (MLAB_PC_STACK && pc_push_we) begin
                pc_write_toggle <= ~pc_write_toggle;
                pc_last_addr <= pc_push_addr;
                pc_last_data <= pc_push_data;
                pc_last_valid <= 1'b1;
            end
            if (!EXPLICIT_RAM_CE) begin
                if (pm_we) pm[pm_port_b_addr] <= pm_wd;
                if (SHARED_PM) pmb_q <= pm[pm_port_b_addr];
            end
        end
`ifndef SYNTHESIS
        if (EXPLICIT_RAM_CE && cpu_ce) begin
            if (pm_we !== ram_pm_we || (pm_we && {pm_wa,pm_wd} !== {ram_pm_wa,ram_pm_wd}))
                $fatal(1,"Explicit PM write decode disagrees with sequential oracle pc=%h op=%h",pc,op_r);
            if (legacy_dm_we !== ram_dm_we ||
                (legacy_dm_we && {legacy_dm_wa,legacy_dm_wd} !== {ram_dm_wa,ram_dm_wd}))
                $fatal(1,"Explicit DM write decode disagrees with sequential oracle pc=%h op=%h",pc,op_r);
        end
`endif
    end
endmodule

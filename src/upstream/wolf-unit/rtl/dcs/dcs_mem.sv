// ============================================================================
// dcs_mem.sv  --  DCS/ADSP-2105 memory-abstraction shim (SYNTH-REFACTOR Phase 1)
// ----------------------------------------------------------------------------
// Owns PM (24b x 16384), DM (16b x 16384) and the U2-U5 sound ROM bytes. Phase 1
// is a PURE refactor: it moves the storage out of adsp2105.sv into this module
// behind a single choke-point, WITHOUT changing behavior. The read window is
// still async (RD_LATENCY=0): the parent indexes the arrays combinationally
// through the exported read functions / hierarchical net refs, byte-for-byte
// identical to when the arrays lived inline. Writes stay procedural, driven by
// the parent (nonblocking, same clock edge as before).
//
// Phase 2: PM/DM are BRAM-SHAPED. Every READ goes through a
// registered read port (RD_LATENCY=1: address sampled at clock N -> data valid
// at N+1); at most ONE read and ONE write land on each port per clock:
//   PM port A = instruction fetch (read-only, every clock)
//   PM port B = data side: DM-alias reads (dm[0x0800-0x1fff] -> pm[23:8]),
//               PM-data reads (ops 0x11/0x50-0x5F), the alias-write RMW
//               pre-read; the parent's PM writes commit on this port's clock
//               edge on a DIFFERENT cycle than any read (reads happen in the
//               CPU's S_MEM/S_DRAIN wait states, writes in its EXEC state).
//   DM port    = data reads (S_MEM/S_DRAIN) + writes (EXEC), same discipline.
//
// Phase 5 (THIS state): the u2-u5 sound ROM sits behind a DDR3-SHAPED
// request/latency port (SYNTH-REFACTOR-PLAN §2c + §6 Phase 5) fronted by a
// bank-page PREFETCH CACHE:
//   rom_req/rom_addr -> [prefetch-cache lookup, 1-clk BRAM-shaped read] ->
//   hit: rom_rdy after ~2 clks | miss: registered DDR3 request ->
//   DDR_LATENCY-clock round trip -> 8-byte beat fills one cache line ->
//   rom_rdy. The requester (CPU S_MEM bank-window stall / S_BOOT stream)
//   holds rom_req with rom_addr stable and waits for rom_rdy; rom_rdy is
//   only presented while rom_addr matches the served address, so a
//   preempted/abandoned request (IRQ mid-stall) self-recovers: the fill
//   completes into the cache (data is ROM -- constant) and the FSM re-serves
//   whatever address the requester holds next.
//   THE PORT IS WHAT SHIPS: on silicon the `ddr beat` below is the real HPS
//   DDR3 read (sys/ddr_svc f2sdram, Partition C); in sim it is backed by the
//   same u2-u5 byte arrays as always ($fread init, `ifndef SYNTHESIS).
//
// The parent's WRITES stay hierarchical nonblocking assigns (u_mem.pm[a] <= w):
// a single nonblocking element write at posedge IS a synchronous BRAM write
// port -- Phase 6 (FSM cut) formalizes them as explicit ports. Hierarchical
// READS from the parent's datapath are gone (Phase-2 point); the TB's debug
// taps still peek the arrays (sim-only observation, not the datapath).
// Init: $readmemh(PMFILE) + $fread of ../rom/u{2..5}.bin (sim only).
// ============================================================================
// Phase 8a item 4: dcs_mem now owns ONLY the EXTERNAL sound ROM (the DDR3-shaped
// rom_req/rom_rdy port + prefetch cache). PM/DM internal BRAM moved into the CPU
// (adsp2105) so their writes are local synchronous BRAM writes (a parent writing
// a submodule array by hierarchical name is un-synthesizable, Quartus 10207).
module dcs_mem #(
    parameter DDR_LATENCY = 8,          // Phase 5: modeled DDR3 round-trip clocks
                                        // (registered request -> beat valid). >=8 per plan.
    parameter PF_LINES    = 512,        // Phase 5: prefetch-cache lines (8 bytes each).
                                        // 512 lines x 8 B = 4 KB = one full bank page (§2c:
                                        // "a small BRAM prefetch/cache window over the
                                        // current bank page"). Must be a power of two.
    parameter EXT_ROM     = 0,          // 0: sim/elab backing; 1: external 64-bit beat port
    parameter CORE_CE_EN  = 0           // 1: advance the cache FSM on core_ce only
) (
    input  wire        clk,
    input  wire        rst,         // invalidate cache on board/core reset
    input  wire        core_ce,
    // ---- Phase 5: DDR3-shaped sound-ROM byte port ----------------------------
    // Level protocol: requester holds rom_req=1 with rom_addr stable; rom_rdy
    // goes (and stays) 1 with rom_q valid once the byte is available, for as
    // long as rom_req is held at that same address. Changing rom_addr (or
    // dropping rom_req) restarts/releases the port.
    input  wire        rom_req,
    input  wire        rom_boot,    // attribution only (sim hit-rate counters):
                                    // 1 = S_BOOT stream, 0 = bank-window read
    input  wire [21:0] rom_addr,
    output wire        rom_rdy,
    input  wire [21:0] boot_rom_addr,
    output wire        boot_rom_rdy,
    output wire [7:0]  rom_q,
    // Packed U2|U3|U4|U5 backing for integration. Address is a 64-bit beat
    // offset within the 4 MB image. Hold ext_req until ext_rdy; ext_q is
    // consumed on that cycle. EXT_ROM=0 retains the golden simulation model.
    output wire        ext_req,
    output wire [18:0] ext_addr,
    input  wire        ext_rdy,
    input  wire [63:0] ext_q
);
`ifndef SYNTHESIS
    // Sim backing store for the DDR3 ROM (on silicon this is HPS DDR3 content,
    // ioctl-loaded via the MRA; the arrays NEVER ship -- only the rom_req/rom_rdy
    // port above, SYNTH-REFACTOR-PLAN §2c). Guarded out of synthesis so the
    // elaboration gate does not instantiate 4 MB of registers (32 Mbit >> the
    // device); under SYNTHESIS rom_byte is a stub and the real DDR3 read replaces
    // ddr_beat on silicon (roadmap E, f2sdram).
    reg [7:0]  u2 [0:1048575];    // U2 sound ROM bytes (= low byte of dcs region word)
    reg [7:0]  u3 [0:1048575];    // U3
    reg [7:0]  u4 [0:1048575];    // U4
    reg [7:0]  u5 [0:1048575];    // U5
`endif

    // ---- ROM byte fetch (linear U2|U3|U4|U5, chip-select in idx[21:20]) --------
    // Sim backing (DCSExplorer MakeROMPointer chip-select); on silicon the DDR3
    // address decode is the same linear layout, offset into the 8 MB region.
`ifndef SYNTHESIS
    function [7:0] rom_byte(input [21:0] idx);
        case (idx[21:20])
          2'd0: rom_byte = u2[idx[19:0]];
          2'd1: rom_byte = u3[idx[19:0]];
          2'd2: rom_byte = u4[idx[19:0]];
          2'd3: rom_byte = u5[idx[19:0]];
        endcase
    endfunction
`else
    // synth-time placeholder: the DDR3 beat comes from the real HPS DDR3 on
    // silicon (roadmap E); for the elaboration gate a deterministic placeholder
    // keeps the prefetch-cache + DDR round-trip FSM synthesizable without the
    // 4 MB arrays. (Worded to avoid a "// synthesis <attr>" pragma misparse.)
    function [7:0] rom_byte(input [21:0] idx); rom_byte = idx[7:0]; endfunction
`endif

    // ======================================================================
    // Phase 5: prefetch cache + DDR3 round-trip model
    // ----------------------------------------------------------------------
    // Direct-mapped, 8-byte lines (= one modeled DDR3 beat). Index =
    // addr[3 +: IDXW] (the offset within a 4 KB bank page when PF_LINES=512),
    // tag = the remaining high bits, so bank switches are handled by tag
    // mismatch -- no flush needed, and boot pages / data pages share the
    // cache correctly. Storage is BRAM-shaped: one clocked read (the lookup
    // cycle) and one write (the fill) per clock.
    // ======================================================================
    localparam IDXW = $clog2(PF_LINES);
    localparam TAGW = 19 - IDXW;              // 22-bit byte addr - 3 offset - IDXW index

    // Phase 8c area fix: force the wide cache stores into M10K. Without the hint
    // Quartus left pf_data (512x64=32 Kbit) + pf_tag as a register array + a 512:1
    // combinational read mux = ~11.8k ALMs (60% of the whole DCS core!). The reads
    // are already registered (line_q<=pf_data[idx]); this just maps them to BRAM.
    (* ramstyle = "no_rw_check, M10K" *) reg [63:0]     pf_data [0:PF_LINES-1]; // line data (byte i at [8*i +: 8])
    (* ramstyle = "no_rw_check, M10K" *) reg [TAGW-1:0] pf_tag  [0:PF_LINES-1];
    reg                                  pf_valid[0:PF_LINES-1]; // 512x1: keep as regs (M10K wasteful)

    localparam [2:0] R_IDLE=3'd0, R_ADDR=3'd1, R_LOOK=3'd2, R_FILL=3'd3, R_SERVE=3'd4;
    reg [2:0]  rstate = R_IDLE;
    reg [21:0] srv_addr;         // address being served (latched at lookup)
    reg        srv_boot;         // attribution of the in-flight request
    reg [7:0]  srv_byte;         // the served byte (rom_q)
    reg [15:0] ddr_cnt;          // DDR3 round-trip countdown
    reg [63:0] ddr_beat;         // modeled DDR3 read data (8-byte aligned beat)
    // Phase 8c area fix: UNCONDITIONAL registered cache read (a clean M10K read
    // port) addressed by srv_idx (the latched request). The former conditional
    // `line_q<=pf_data[req_idx]` inside the state case was "uninferred due to
    // asynchronous read" -> an 11.8k-ALM register array + 512:1 read mux (60% of
    // the whole DCS core). The added R_ADDR clock for the registered-read latency
    // is F19-invariant (crux: ROM-read stalls are DAC-retimed; retired-PC order
    // and PCM are unchanged).
    reg [63:0]     pfd_q;        // registered pf_data [srv_idx]
    reg [TAGW-1:0] pft_q;        // registered pf_tag  [srv_idx]
    reg            pfv_q;        // registered pf_valid[srv_idx]
    // External DDR responses are one clk pulse. When the ADSP itself advances
    // on a slower clock-enable, retain that pulse until the cache FSM consumes
    // it; otherwise an accepted Avalon response could be lost between CE slots.
    reg            ext_rsp_valid;
    reg [63:0]     ext_rsp_q;
    wire           mem_ce = (CORE_CE_EN != 0) ? core_ce : 1'b1;

    wire [IDXW-1:0] req_idx = rom_addr[3 +: IDXW];
    wire [TAGW-1:0] req_tag = rom_addr[21 -: TAGW];
    wire [IDXW-1:0] srv_idx = srv_addr[3 +: IDXW];
    wire [TAGW-1:0] srv_tag = srv_addr[21 -: TAGW];

    assign rom_rdy = (rstate == R_SERVE) && rom_req && (rom_addr == srv_addr);
    // During boot rom_req=1 and rom_addr=boot_rom_addr. A separate
    // comparator keeps instruction predecode out of the PM boot-write path.
    assign boot_rom_rdy = (rstate == R_SERVE) && rom_boot && (boot_rom_addr == srv_addr);
    assign rom_q   = srv_byte;
    // Drop the request as soon as a response is captured, not only when the
    // slowed FSM reaches its next CE edge. This prevents the one-outstanding
    // Avalon adapter from issuing a duplicate beat request.
    assign ext_req  = (EXT_ROM != 0) && (rstate == R_FILL) && !ext_rsp_valid;
    assign ext_addr = srv_addr[21:3];

    // Unconditional registered read of the cache stores (M10K read port). Reads
    // srv_idx every clock; the value is valid one clock later (consumed in R_LOOK,
    // which R_ADDR delays to). Write side is the R_FILL fill in the FSM below ->
    // simple dual-port (1 write / 1 read) per store -> maps to M10K, not a mux.
    always @(posedge clk) begin
        if (mem_ce) begin
            pfd_q <= pf_data [srv_idx];
            pft_q <= pf_tag  [srv_idx];
            pfv_q <= pf_valid[srv_idx];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            ext_rsp_valid <= 1'b0;
            ext_rsp_q     <= 64'd0;
        end else begin
            if ((EXT_ROM != 0) && ext_rdy && (rstate == R_FILL) && !ext_rsp_valid) begin
                ext_rsp_valid <= 1'b1;
                ext_rsp_q     <= ext_q;
            end else if (mem_ce && (rstate == R_FILL) && ext_rsp_valid) begin
                ext_rsp_valid <= 1'b0;
            end
        end
    end

    // sim instrumentation: hit/miss counters, split by requester
    integer pf_hits_w = 0, pf_miss_w = 0;   // bank-window (DM 0x2000-0x2FFF) reads
    integer pf_hits_b = 0, pf_miss_b = 0;   // S_BOOT stream reads

    // sim backing for the DDR3 beat: 8 bytes at the line-aligned address.
    // On silicon this becomes the f2sdram read data (64-bit beat).
    function [63:0] ddr_beat_fn(input [21:0] a);
        integer bi;
        for (bi = 0; bi < 8; bi = bi + 1)
            ddr_beat_fn[8*bi +: 8] = rom_byte({a[21:3], 3'b000} + bi[21:0]);
    endfunction

    integer ri;
    always @(posedge clk) begin
        if (rst) begin
            rstate   <= R_IDLE;
            srv_addr <= '0;
            srv_boot <= 1'b0;
            srv_byte <= 8'h00;
            ddr_cnt  <= '0;
            ddr_beat <= '0;
            for (ri = 0; ri < PF_LINES; ri = ri + 1)
                pf_valid[ri] <= 1'b0;
        end else if (mem_ce) case (rstate)
          R_IDLE: if (rom_req) begin
              // latch the request; R_ADDR waits one clock for the registered
              // (M10K) read of srv_idx to land in pfd_q/pft_q/pfv_q.
              srv_addr <= rom_addr;
              srv_boot <= rom_boot;
              rstate   <= R_ADDR;
          end
          R_ADDR: rstate <= R_LOOK;   // pfd_q/pft_q/pfv_q now = *[srv_idx]
          R_LOOK: begin
              if (pfv_q && (pft_q == srv_tag)) begin
                  srv_byte <= pfd_q[8*srv_addr[2:0] +: 8];
`ifndef SYNTHESIS
                  if (pfd_q[8*srv_addr[2:0] +: 8] !== rom_byte(srv_addr)) begin
                      $display("FATAL: Phase-5 PF-cache hit data mismatch addr=%06x got=%02x expect=%02x",
                               srv_addr, pfd_q[8*srv_addr[2:0] +: 8], rom_byte(srv_addr));
                      $finish;
                  end
                  if (srv_boot) pf_hits_b = pf_hits_b + 1; else pf_hits_w = pf_hits_w + 1;
`endif
                  rstate <= R_SERVE;
              end else begin
                  // Integrated builds raise ext_req in R_FILL and wait for
                  // ext_rdy. The standalone model counts DDR_LATENCY clocks.
`ifndef SYNTHESIS
                  if (srv_boot) pf_miss_b = pf_miss_b + 1; else pf_miss_w = pf_miss_w + 1;
`endif
                  if (EXT_ROM == 0)
                      ddr_cnt <= DDR_LATENCY[15:0];
                  rstate  <= R_FILL;
              end
          end
          R_FILL: begin
              if (((EXT_ROM != 0) && ext_rsp_valid) ||
                  ((EXT_ROM == 0) && (ddr_cnt <= 16'd1))) begin
                  // DDR3 beat valid: fill the cache line + serve the byte.
                  // The fill completes even if the requester was preempted --
                  // ROM is constant and a later request can reuse the line.
                  if (EXT_ROM != 0)
                      ddr_beat = ext_rsp_q;
                  else
                      ddr_beat = ddr_beat_fn(srv_addr);
                  pf_data[srv_idx]  <= ddr_beat;
                  pf_tag[srv_idx]   <= srv_tag;
                  pf_valid[srv_idx] <= 1'b1;
                  srv_byte          <= ddr_beat[8*srv_addr[2:0] +: 8];
                  rstate            <= R_SERVE;
              end else if (EXT_ROM == 0)
                  ddr_cnt <= ddr_cnt - 16'd1;
          end
          R_SERVE: begin
              if (!rom_req)
                  rstate <= R_IDLE;
              else if (rom_addr != srv_addr) begin
                  // requester moved on (next boot byte / re-issued after an
                  // IRQ preemption): restart the lookup via R_ADDR (registered read)
                  srv_addr <= rom_addr;
                  srv_boot <= rom_boot;
                  rstate   <= R_ADDR;
              end
          end
        endcase
    end

`ifndef SYNTHESIS
    // Phase-5 report: measured prefetch hit rate (window = the interesting
    // number: the decode inner loop's DM(0x2000-0x2FFF) reads; boot = the
    // S_BOOT page streams). Printed on any $finish, incl. FATAL aborts.
    final begin
        $display("PF-CACHE window: %0d reads, %0d hits, %0d misses (hit rate %0d.%02d%%)",
                 pf_hits_w + pf_miss_w, pf_hits_w, pf_miss_w,
                 (pf_hits_w + pf_miss_w) ? (100 * pf_hits_w) / (pf_hits_w + pf_miss_w) : 0,
                 (pf_hits_w + pf_miss_w) ? (10000 * pf_hits_w / (pf_hits_w + pf_miss_w)) % 100 : 0);
        $display("PF-CACHE boot  : %0d reads, %0d hits, %0d misses (DDR_LATENCY=%0d PF_LINES=%0d)",
                 pf_hits_b + pf_miss_b, pf_hits_b, pf_miss_b, DDR_LATENCY, PF_LINES);
    end
`endif

    // ---- init (sim only) -------------------------------------------------------
    // PM/DM preload moved to the parent (adsp2105) with the arrays; here we only
    // load the sim ROM backing + clear the prefetch valid bits.
    integer k, romfd;
`ifndef SYNTHESIS
    initial begin
        for (k=0;k<PF_LINES;k=k+1) pf_valid[k]=1'b0;
        romfd = $fopen("../rom/u2.bin", "rb");
        if (romfd) begin k = $fread(u2, romfd); $fclose(romfd); end
        romfd = $fopen("../rom/u3.bin", "rb");
        if (romfd) begin k = $fread(u3, romfd); $fclose(romfd); end
        romfd = $fopen("../rom/u4.bin", "rb");
        if (romfd) begin k = $fread(u4, romfd); $fclose(romfd); end
        romfd = $fopen("../rom/u5.bin", "rb");
        if (romfd) begin k = $fread(u5, romfd); $fclose(romfd); end
    end
`endif
endmodule

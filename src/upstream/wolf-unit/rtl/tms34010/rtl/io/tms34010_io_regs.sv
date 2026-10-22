// -----------------------------------------------------------------------------
// tms34010_io_regs.sv
//
// On-chip memory-mapped I/O register file for the TMS34010.
//
// Per the 1988 User's Guide Figure 6-1 (page 6-3), the GSP has 32 internal
// 16-bit registers occupying the bit-address range 0xC0000000-0xC00001FF.
// Each register sits at a 0x10-bit-aligned address (16 bits apart). The CPU
// (and, on real silicon, the host) reaches them through the ordinary
// bit-addressed memory interface; an address decodes to I/O space when its
// two MSBs are 11 and bits[29:9] are 0. The register index is addr[8:4].
//
// "All I/O registers ... are cleared to 0 at reset" (UG §6, Reset). The one
// documented exception concerns the HLT bit's dependence on the HCS pin of
// the host interface, which this FPGA reimplementation does not yet model;
// resetting every register to 0 is therefore correct here.
//
// Scope (Task 0081 — foundation; P00xx — live video counters):
//   - Plain read/write storage for the control/graphics registers that the
//     instruction set reads (PSIZE, PMASK, CONVSP, CONVDP, CONTROL, DPYCTL, ...).
//   - HCOUNT/VCOUNT are now the LIVE horizontal/vertical counters from u_video
//     (read-only on silicon; see the rdata mux). REFCNT/DPYADR remain plain
//     storage; INTPEND bits are software-clear with device set-on-event (DI/WV).
//
// Port shape:
//   - Synchronous active-high reset (assumption A0003), all registers -> 0.
//   - One synchronous write port (req & we & is_io).
//   - One combinational (async) read port. The 32x16 array is tiny (512
//     bits) and async read keeps this composable with the core's existing
//     register-style reads; FPGA maps it to flops + a 32:1 mux.
//   - `is_io` tells the caller whether `addr` decoded as I/O space, so the
//     surrounding memory fabric can route reads/writes here vs. external RAM.
//
// Spec source:
//   third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf
//   Figure 6-1 (I/O Register Memory Map), §6 "I/O Registers".
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_io_regs
  import tms34010_pkg::*;
#(
  // Optional comparison variant; measured larger on Pocket, so keep it off.
  parameter bit LOCAL_WRITE = 1'b0,
  // CPU-originated actions sample only on the core enable; raster events remain full-rate.
  parameter bit CPU_CE_WRITE = 1'b0,
`ifdef POCKET
  parameter bit BANKED_WRITE = 1'b1
`else
  parameter bit BANKED_WRITE = 1'b0
`endif
)(
  input  wire logic                  clk,
  input  wire logic                  rst,
  input  wire logic                  ce_cpu,

  input  wire logic                  req,      // access strobe
  input  wire logic                  we,       // 1 = write, 0 = read
  input  wire logic [ADDR_WIDTH-1:0] addr,     // full 32-bit bit-address
  input  wire logic [FIELD_SIZE_WIDTH-1:0] size,// field width in bits
  input  wire logic [DATA_WIDTH-1:0] wdata,    // full field (low 16 for contained
                                               // writes; hi bits span into idx+1)

  // Pixel-clock ENABLE for the video-timing counters (u_video). Threaded from
  // the emu (Arcade-SmashTV.sv ce_pix = 96 MHz / 12 = 8 MHz) through the core.
  // Left UNCONNECTED by legacy unit TBs -> u_video defaults to full rate (its
  // own `ce === 1'b0` guard), so those TBs are unaffected.
  input  wire logic                  ce_pix,

  output logic [15:0]           rdata,    // selected register (0 if not I/O)
  output logic                  is_io,    // addr decodes to I/O space

  // Dedicated taps for the graphics datapath (combinational views of the
  // stored registers). More can be added (PMASK/CONTROL) as the graphics ops
  // that need them land.
  output logic [15:0]           psize_o,  // PSIZE: pixel size in bits (1..16)
  output logic [15:0]           convdp_o, // CONVDP: XY->linear dest pitch shift
  output logic [15:0]           convsp_o, // CONVSP: XY->linear source pitch shift
  output logic [15:0]           control_o,// CONTROL: PPOP[14:10], PBV/PBH, W, T(bit5)
  output logic [15:0]           pmask_o,  // PMASK: plane mask (1 bit = plane masked)
  output logic [15:0]           dpyctl_o, // DPYCTL: display control (SRT = bit 11,
                                          // 1988 UG p114 / MAME tms34010.cpp:937-967)
  output logic [15:0]           intenb_o, // INTENB: maskable-interrupt enables
  output logic [15:0]           intpend_o,// INTPEND: maskable-interrupt pending bits
  output logic [15:0]           dpystrt_o,// P0024: DPYSTRT (display start) — double-buffer page tap
  output logic [15:0]           dpyadr_o, // live DPYADR page; software may override it in vblank
  output logic                  vblank_start_o, // edge where hardware loads DPYADR from DPYSTRT
  output logic [15:0]           hstctlh_o,// HSTCTLH: host control (NMI/NMIM in bits 8/9)
  input  wire logic                  nmi_clear,// 1-cycle: clear HSTCTLH.NMI (device took NMI)
  input  wire logic                  wvp_set,  // 1-cycle: set INTPEND.WV (window violation)
  // P0016: external interrupt pin LINT1 (level). Per the 1988 UG §8.3 the
  // INTPEND.X1P bit REFLECTS the pin level (it is not a latch and cannot be
  // cleared by writing INTPEND) -- so it is OR-mirrored into the INTPEND view
  // (both the dedicated intpend_o tap and CPU reads of the register).
  input  wire logic                  lint1_in,

  // Dynamic display geometry (Phase 2B): expose display timing registers for runtime
  // video geometry adaptation (Rampage reprograms these at runtime). Video module
  // reads actual geometry instead of hardcoded parameters.
  output logic [15:0]           heblnk_o, // Horizontal end of blanking
  output logic [15:0]           hsblnk_o, // Horizontal start of blanking
  output logic [15:0]           veblnk_o, // Vertical end of blanking
  output logic [15:0]           vsblnk_o  // Vertical start of blanking
);

  // I/O-space decode: two MSBs = 11 and bits[29:9] = 0 (range C0000000-
  // C00001FF). The register index is addr[8:4].
  logic [IO_REG_IDX_W-1:0] idx;
  assign is_io = (addr[ADDR_WIDTH-1:ADDR_WIDTH-2] == 2'b11)
              && (addr[ADDR_WIDTH-3:IO_REG_IDX_W+4] == '0);
  assign idx   = addr[IO_REG_IDX_W+3 : 4];

  // Register storage.
  logic [15:0] io_reg [0:IO_REG_COUNT-1];

  // ---------------------------------------------------------------------------
  // Display-interrupt source + live video counters (P0012 + P00xx).
  // The vendored `tms34010_video` block generates DPYINT_PULSE (a 1-clock strobe
  // at the start of the scan line == DPYINT) from the video-timing registers.
  // Wire it here where all the timing registers already live. It is clocked by
  // the io_regs clk and gated by ce_pix (the dot-clock enable) so DPYINT fires
  // ONCE PER FRAME at the DPYINT scan line -- matching real HW / MAME -- instead
  // of at the core clock (the fork-inherited bug: ~12x too fast, which derailed
  // NBA/UMK3 init before the RAM interrupt-dispatch table is built).
  // hcount/vcount are the LIVE counters and are returned on CPU reads of
  // HCOUNT/VCOUNT (see the rdata mux): NBA display_blank spins on VCOUNT
  // (BB.ASM #nxt: `move *VCOUNT,a0; jrz` waits for VCOUNT to leave 0) and hangs
  // forever if the read returns a dead/stored 0.
  // ---------------------------------------------------------------------------
  logic        dpyint_pulse;
  logic [15:0] vid_hcount, vid_vcount;
  logic        vid_hs_unused, vid_vs_unused, vid_hb_unused, vid_vb_unused, vid_bl_unused;

  tms34010_video u_video (
    .clk         (clk),
    .rst         (rst),
    .ce          (ce_pix),   // dot-clock enable: HCOUNT/dot, VCOUNT/line, DPYINT/frame
    .hesync      (io_reg[IO_IDX_HESYNC]),
    .heblnk      (io_reg[IO_IDX_HEBLNK]),
    .hsblnk      (io_reg[IO_IDX_HSBLNK]),
    .htotal      (io_reg[IO_IDX_HTOTAL]),
    .vesync      (io_reg[IO_IDX_VESYNC]),
    .veblnk      (io_reg[IO_IDX_VEBLNK]),
    .vsblnk      (io_reg[IO_IDX_VSBLNK]),
    .vtotal      (io_reg[IO_IDX_VTOTAL]),
    .dpyint      (io_reg[IO_IDX_DPYINT]),
    .hcount      (vid_hcount),
    .vcount      (vid_vcount),
    .hsync       (vid_hs_unused),
    .vsync       (vid_vs_unused),
    .hblank      (vid_hb_unused),
    .vblank      (vid_vb_unused),
    .blank       (vid_bl_unused),
    .dpyint_pulse(dpyint_pulse),
    .vblank_start(vblank_start_o)
  );

  // Async read: the selected register, or 0 when the address is not in
  // I/O space (so a non-I/O read contributes nothing to a merged read bus).
  // P0016: CPU reads of INTPEND see the live LINT1 pin mirrored into X1P.
  // The `=== 1'b1` makes an UNCONNECTED pin (legacy TBs: 'z) read as not
  // asserted in sim; synthesis treats it as plain equality.
  logic lint1_lvl;
  assign lint1_lvl = (lint1_in === 1'b1);
  // HCOUNT/VCOUNT are READ-ONLY-ish counters on real silicon (1988 UG Fig 6-1;
  // memory_map.md marks them "read-only on silicon"): a CPU read returns the
  // LIVE horizontal/vertical counter, not the stored io_reg. NBA display_blank
  // spins on VCOUNT (BB.ASM #nxt) and MAME returns a live, sweeping VCOUNT; a
  // dead/stored 0 hangs the spin. Writes still fall through to io_reg[idx] (dead
  // storage for these two indices) -- harmless, and matches MAME, where the
  // stored write does not feed the computed read.
  logic field_contained;
  logic [15:0] selected_rdata;
  assign field_contained = size >= FIELD_SIZE_WIDTH'(1)
                        && size <= FIELD_SIZE_WIDTH'(16)
                        && ({2'b00, addr[3:0]} + size <= FIELD_SIZE_WIDTH'(16));
  always_comb begin
    selected_rdata = io_reg[idx];
    if (idx == IO_IDX_VCOUNT)
      selected_rdata = vid_vcount;
    else if (idx == IO_IDX_HCOUNT)
      selected_rdata = vid_hcount;
    else if (idx == IO_IDX_INTPEND)
      selected_rdata = io_reg[idx] | (16'(lint1_lvl) << INT_X1_BIT);
  end
  assign rdata = !is_io ? 16'h0
               : field_contained ? (selected_rdata >> addr[3:0])
               : selected_rdata;

  // I/O locations use bit-addressed field semantics. A field wholly within one
  // 16-bit register uses the contained path (Wolf-unit code relies on a one-bit
  // store to INTENB+1 to set X1E without disturbing the other enables). A field
  // whose bits CROSS the 16-bit boundary (FS>16, or an unaligned field with
  // addr[3:0]+size>16) writes io_reg[idx] (its low bits) AND io_reg[idx+1] (its
  // high bits). This single-boundary span is exactly what the Wolf CRTC init
  // needs: HESYNC..VTOTAL are programmed by an FS=32, register-aligned block
  // copy (SETF 20h; MOVE *B0+,*B2+ to C0000000+), so each 32-bit store must land
  // two adjacent 16-bit IO registers (1988 UG §6 bit-addressed I/O field
  // semantics; MOVE field size 1..32). A >2-register field (offset+size>32) is
  // still not implemented (unused by the Wolf title set).
  logic        io_span;                 // field crosses idx -> idx+1
  logic [5:0]  io_lo_bits;              // field bits landing in io_reg[idx] (1..16)
  logic [15:0] io_write_mask, io_write_data;   // -> io_reg[idx]
  logic [15:0] io_hi_mask,    io_hi_data;      // -> io_reg[idx+1] (span only)
  always_comb begin
    io_lo_bits = 6'd16 - {2'b00, addr[3:0]};
    // Restrict spanning to FS>16 fields (the CRTC block copy). Fields of size<=16
    // — contained OR unaligned boundary-crossing — keep their exact prior behavior,
    // so no UMK3/Wolf IO write changes (UMK3 issues only <=16-bit IO writes).
    io_span = is_io
            && (size > FIELD_SIZE_WIDTH'(16))
            && (({2'b00, addr[3:0]} + size) <= FIELD_SIZE_WIDTH'(32));
    // low register (io_reg[idx])
    io_write_mask = field_contained ? ((17'h1FFFF >> (17 - size)) << addr[3:0])
                  : io_span         ? (16'hFFFF << addr[3:0])
                  :                    16'hFFFF;
    io_write_data = (field_contained || io_span) ? 16'(wdata[15:0] << addr[3:0])
                                                 :  wdata[15:0];
    // high register (io_reg[idx+1]): the (size-io_lo_bits) field bits above the
    // boundary, right-justified at bit 0.
    io_hi_mask = io_span ? (16'hFFFF >> (6'd16 - (size - io_lo_bits))) : 16'h0;
    io_hi_data = io_span ? 16'(wdata >> io_lo_bits)                    : 16'h0;
  end

  // Adjacent spanning writes always target opposite parity banks. Select
  // low/high data and mask once per bank, then update each register from its
  // own local feedback. This avoids the two asynchronous array read muxes
  // needed by dynamic read-modify-write expressions.
  wire [15:0] even_write_data = idx[0] ? io_hi_data : io_write_data;
  wire [15:0] odd_write_data = idx[0] ? io_write_data : io_hi_data;
  wire [15:0] even_write_mask = idx[0] ? io_hi_mask : io_write_mask;
  wire [15:0] odd_write_mask = idx[0] ? io_write_mask : io_hi_mask;

  // Dedicated graphics taps.
  assign psize_o   = io_reg[IO_IDX_PSIZE];
  assign convdp_o  = io_reg[IO_IDX_CONVDP];
  assign convsp_o  = io_reg[IO_IDX_CONVSP];
  assign control_o = io_reg[IO_IDX_CONTROL];
  assign dpyctl_o  = io_reg[IO_IDX_DPYCTL];   // SRT gating tap (DPYCTL_SRT_BIT)
  assign dpystrt_o = io_reg[IO_IDX_DPYSTRT];  // P0024
  assign dpyadr_o  = io_reg[IO_IDX_DPYADR];
  assign pmask_o   = io_reg[IO_IDX_PMASK];
  assign intenb_o  = io_reg[IO_IDX_INTENB];
  // P0016: X1P mirrors the LINT1 pin level into the pending view.
  assign intpend_o = io_reg[IO_IDX_INTPEND] | (16'(lint1_lvl) << INT_X1_BIT);
  assign hstctlh_o = io_reg[IO_IDX_HSTCTLH];

  // The core's request/data change only after ce_cpu edges. Committing CPU
  // writes on that same enable gives the combinational datapath its full CPU
  // period. Device raster events below must remain active on every system edge.
  // Legacy stand-alone users leave CPU_CE_WRITE=0 (and may omit ce_cpu).
  wire cpu_action = !CPU_CE_WRITE || (ce_cpu !== 1'b0);
  wire cpu_write = cpu_action && req && we && is_io;

  // Synchronous write + reset. The reset loop is bounded (32 iterations) and
  // fully unrollable, so synthesis treats it as parallel resets.
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < IO_REG_COUNT; i++) begin
        io_reg[i] <= 16'h0;
      end
    end else begin
      if (cpu_write) begin
        if (BANKED_WRITE) begin
          for (int i = 0; i < IO_REG_COUNT; i++) begin
            if (idx == IO_REG_IDX_W'(i)
                || (io_span && idx != IO_REG_IDX_W'(IO_REG_COUNT-1)
                    && idx + IO_REG_IDX_W'(1) == IO_REG_IDX_W'(i))) begin
              if (i == IO_IDX_INTPEND) begin
                io_reg[i] <= io_reg[i]
                  & ((i % 2 == 0 ? even_write_data : odd_write_data)
                    | ~(INTPEND_W0C_MASK & (i % 2 == 0 ? even_write_mask : odd_write_mask)));
              end else begin
                io_reg[i] <= (io_reg[i] & ~(i % 2 == 0 ? even_write_mask : odd_write_mask))
                          | ((i % 2 == 0 ? even_write_data : odd_write_data)
                             & (i % 2 == 0 ? even_write_mask : odd_write_mask));
              end
            end
          end
        end else if (LOCAL_WRITE) begin
          // Constant-index, per-bit enables keep each register's feedback
          // local. This avoids two dynamic read muxes feeding the masked
          // write ports. Preserve the low-then-high write priority and W0C
          // semantics; device updates below retain their original priority.
          for (int i = 0; i < IO_REG_COUNT; i++) begin
            for (int b = 0; b < 16; b++) begin
              if (idx == IO_REG_IDX_W'(i) && io_write_mask[b]) begin
                if (i == IO_IDX_INTPEND) begin
                  if (INTPEND_W0C_MASK[b] && !io_write_data[b]) io_reg[i][b] <= 1'b0;
                end else io_reg[i][b] <= io_write_data[b];
              end
              if (io_span && idx != IO_REG_IDX_W'(IO_REG_COUNT-1)
                  && (idx + IO_REG_IDX_W'(1)) == IO_REG_IDX_W'(i) && io_hi_mask[b]) begin
                if (i == IO_IDX_INTPEND) begin
                  if (INTPEND_W0C_MASK[b] && !io_hi_data[b]) io_reg[i][b] <= 1'b0;
                end else io_reg[i][b] <= io_hi_data[b];
              end
            end
          end
        end else begin
        // SHARED-P0016 (ported from the Y-unit donor, which never lost it; this
        // tree and NARC's both regressed it). INTPEND is NOT a plain store:
        //   MAME tms34010.cpp:1348-1356
        //     /* X1P, X2P and HIP are read-only */
        //     /* WVP and DIP can only have 0's written to them */
        //     IOREG(REG_INTPEND) = oldreg;
        //     if (!(data & TMS34010_WV)) IOREG(REG_INTPEND) &= ~TMS34010_WV;
        //     if (!(data & TMS34010_DI)) IOREG(REG_INTPEND) &= ~TMS34010_DI;
        // Stronger evidence than the gospel cite: Williams' SHIPPING source
        // acknowledges by writing a ZERO into the bit --
        //   smashtv-src/MAIN.ASM:220  MOVE @INTPEND,A1,W ; CLEAR STUPID INTERRUPT PENDING
        //                             ANDNI DIE,A1
        //                             MOVE A1,@INTPEND,W
        // The game only works if the silicon is write-zero-to-clear.
        //
        // Without this, the ordinary read-modify-write idiom stores the X1P the
        // READ mirrored in from the live LINT1 pin (:225), so X1P latches stuck-1
        // and `intpend_o = stored | pin` asserts INT1 forever regardless of the
        // pin. MEASURED on Open Ice: 2007 of 2012 INTPEND writes set X1P, 1728 of
        // them from the display ISR at FF803AE0 -- ~10 words from the page flip
        // at FF803A40.
        //
        // DELIBERATE DIVERGENCE -- from GOSPEL as well as from the donor.
        // Reviewed by the NARC (Z-unit) session; recorded here so the next
        // person to diff the three forks against tms34010.cpp does not flag this
        // line as an error. It is intentional and it is SAFER than MAME:
        //   MAME's io_register_w (tms34010.cpp:1247-1256) passes mem_mask to a
        //   pre-write callback and then IGNORES it -- `IOREG(offset) = data` is a
        //   full-word store, and the INTPEND case tests raw `data`. So on a
        //   genuine sub-word write whose field EXCLUDES WV/DI, MAME itself would
        //   read 0 in those positions and SPURIOUSLY CLEAR them. The donor cannot
        //   express the case at all (word-granular writes).
        // Wolf's write path is FIELD-based, so intersecting the w0c mask with
        // io_write_mask makes bits OUTSIDE the written field untouchable.
        // For FS=16 the intersection is a no-op and this reduces EXACTLY to the
        // donor form -- and MEASURED on Open Ice attract, all 21 observed INTPEND
        // writes carry mask=FFFF, so the divergence is unreachable on real game
        // code and all three forks behave identically in practice.
        if (idx == IO_IDX_INTPEND) begin
          io_reg[IO_IDX_INTPEND] <=
              io_reg[IO_IDX_INTPEND]
              & (io_write_data | ~(INTPEND_W0C_MASK & io_write_mask));
        end else
        io_reg[idx] <= (io_reg[idx] & ~io_write_mask)
                     | (io_write_data & io_write_mask);
        // Cross-boundary span: also land the high bits in the next register.
        // Guard idx+1 in range (idx==31 has no successor; never a CRTC target).
        if (io_span && (idx != IO_REG_IDX_W'(IO_REG_COUNT-1))) begin
          // SHARED-P0016 SPAN HOLE (found by the Y-unit session while diffing
          // their independent FS>16 transcription against this one). The direct
          // write above honours INTPEND's read-only / write-zero-to-clear mask,
          // but this cross-register span wrote idx+1 UNMASKED -- so a 32-bit
          // field write at INTENB (idx 0x11) lands its high half on INTPEND
          // (idx 0x12) and could SET the read-only X1P/X2P/HIP bits, i.e. the
          // exact defect the mask exists to prevent, reachable by the other door.
          // Apply the same mask whenever the span TARGET is INTPEND.
          if ((idx + IO_REG_IDX_W'(1)) == IO_IDX_INTPEND) begin
            io_reg[IO_IDX_INTPEND] <=
                io_reg[IO_IDX_INTPEND]
                & (io_hi_data | ~(INTPEND_W0C_MASK & io_hi_mask));
          end else
          io_reg[idx + IO_REG_IDX_W'(1)] <=
              (io_reg[idx + IO_REG_IDX_W'(1)] & ~io_hi_mask)
            | (io_hi_data & io_hi_mask);
        end
        end
      end else if (cpu_action && nmi_clear) begin
        // The device automatically clears HSTCTLH.NMI when it takes the NMI
        // (1988 UG §8). A normal I/O write takes precedence (the else-if order):
        // simultaneous host write + take is a don't-care corner.
        io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] <= 1'b0;
      end else if (cpu_action && wvp_set) begin
        // The graphics engine sets INTPEND.WV on a window violation (1988 UG
        // §7.10). Like nmi_clear, this is a device-internal set, lower priority
        // than a host/program I/O write.
        io_reg[IO_IDX_INTPEND][INT_WV_BIT] <= 1'b1;
      end
      // Display interrupt (P0012): set INTPEND.DI at the DPYINT scan line.
      // Independent of the else-if chain above so a coincident I/O write to a
      // DIFFERENT register cannot drop the frame's DI. A same-cycle write to
      // INTPEND itself: this bit-select assign wins for bit DI (set-dominant),
      // matching the device-sets / software-clears model (the handler clears DI
      // by writing INTPEND). dpyint_pulse is a ce-gated one-clock strobe (once
      // per frame), so it never fights RETI.
      // Gate on a programmed raster (VTOTAL != 0) so the reset state (all timing
      // regs 0 -> pulse whenever ce fires) doesn't spam INTPEND.DI before the
      // game sets up video. Harmless while IE=0, but keep it clean.
      if (dpyint_pulse && io_reg[IO_IDX_VTOTAL] != 16'h0) begin
        io_reg[IO_IDX_INTPEND][INT_DI_BIT] <= 1'b1;
      end
      // Entering VSBLNK loads DPYADR from DPYSTRT. A same-cycle explicit
      // DPYADR write wins so software can override the automatic load.
      if (vblank_start_o && !(cpu_write && (idx == IO_IDX_DPYADR))) begin
        io_reg[IO_IDX_DPYADR] <= io_reg[IO_IDX_DPYSTRT];
      end
    end
  end

  // Output assignments: display geometry registers (Phase 2B)
  assign heblnk_o = io_reg[IO_IDX_HEBLNK];
  assign hsblnk_o = io_reg[IO_IDX_HSBLNK];
  assign veblnk_o = io_reg[IO_IDX_VEBLNK];
  assign vsblnk_o = io_reg[IO_IDX_VSBLNK];

endmodule : tms34010_io_regs

`default_nettype wire

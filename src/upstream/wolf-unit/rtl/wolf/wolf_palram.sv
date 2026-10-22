// wolf_palram.sv — palette mirror for Wolf-unit (UMK3) video scanout.
// FORK of yunit/yunit_palram.sv, widened to the 32768-entry Wolf palette.
//
// Gospel: midwunit.cpp:643 PALETTE(..., 32768) xRGB_555; :625/map palette_device
// ::write16 over 0x01880000-0x018fffff. wolf_pkg::PAL_ENTRIES = 32768 => a
// 15-bit palette address (vs Y-unit's 12/13-bit). The scanout indexes the palette
// DIRECTLY with the 15-bit VRAM word (no pen fold), so this mirror is 32768 deep.
//
// Same structure as yunit_palram: the palette BRAM in wolf_mem is true-dual-port
// with both ports consumed by the CPU field engine, so the video scanout keeps
// its own MIRROR with a dedicated always-available read port. Up to two CPU
// palette writes per cycle (port A word0, port B word1) are serialized into the
// mirror's single write port through a tiny FIFO (peaks at depth 1 for the
// worst-case field). Writes are sparse (MOVE-driven), so the mirror always tracks
// the CPU palette far faster than the pixel rate.
//
// Inference: two always blocks (one write from the serializer, one video read)
// => simple-dual-port M10K.
`default_nettype none
module wolf_palram #(
  parameter int AW = 15,           // Wolf palette address width (32768 = PAL_ENTRIES)
  parameter int DEPTH = 1 << AW
)(
  input  logic          clk,
  input  logic          rst,
  // CPU palette write taps from wolf_mem (port A = word0, port B = word1; both
  // may fire the same cycle for a field spanning two palette words).
  input  logic          we_a,
  input  logic [AW-1:0] aa,
  input  logic [15:0]   awd,
  input  logic          we_b,
  input  logic [AW-1:0] ba,
  input  logic [15:0]   bwd,
  // video read (registered, 1-clk; dedicated port — never preempted)
  input  logic [AW-1:0] raddr,
  output logic [15:0]   rdata
);
  // ramstyle no_rw_check RETAINED + an EXPLICIT read-during-write bypass below.
  //
  // THE DEFECT IS REAL: `no_rw_check` promises the fitter that no address is read
  // and written in the same cycle, and that promise is FALSE. The CPU write path
  // (w_we/w_aa) and the DEDICATED VIDEO READ PORT (raddr/rdata) index this same
  // array; video reads an entry EVERY PIXEL and the CPU writes palette entries
  // during ACTIVE DISPLAY (fades, colour cycling). On collision Quartus picks
  // READ_DURING_WRITE_MODE_MIXED_PORTS = DONT_CARE, documented UNDEFINED, while
  // Verilog models deterministic old-data -- so no bench here can ever exhibit
  // it. Silicon-only class, alongside P0019 and P0022. Found by Gladiator.
  //
  // *** DO NOT "FIX" THIS BY DELETING THE ATTRIBUTE. *** That was tried and it
  // BLEW THE DEVICE (Gladiator, 2026-07-27, measured): dropping the hint forces
  // OLD_DATA, Cyclone V cannot do mixed-port OLD_DATA natively in simple-dual-
  // port M10K, so the fitter pulls the array OUT of block RAM into logic --
  // registers 21,006 -> 71,459 and "Error (170012): Fitter requires 4347 LABs,
  // device contains only 4191". THIS array is the 32768-entry palette mirror:
  // 32768 x 16 = 512 kbit, i.e. ~524k registers if it falls out of M10K. It
  // would fail far harder than the case that was measured.
  //
  // CORRECT SHAPE (Gladiator's, after their failed fit): keep the attribute and
  // keep M10K, and remove the COLLISION instead -- a comparator and a mux, not a
  // whole block RAM. The bypass below makes the undefined case unreachable: when
  // the write and read addresses coincide, the output comes from the forwarding
  // register rather than from the RAM, so whatever the M10K emits on a collision
  // is never observed.
  (* ramstyle = "no_rw_check" *) logic [15:0] mem [0:DEPTH-1];

  // ---- write serializer: up to 2 in/cycle, 1 out/cycle, depth-4 FIFO ---------
  localparam int QAW = 2;                 // depth 4 (>= worst-case peak of 1)
  logic [AW+16-1:0] q [0:(1<<QAW)-1];     // {addr, data}
  logic [QAW:0] wptr, rptr;               // extra bit for full/empty distinction
  wire  qempty = (wptr == rptr);

  logic          w_we;                    // this-cycle mirror write
  logic [AW-1:0] w_aa;
  logic [15:0]   w_awd;

  // Hoist the FIFO-head read + its constant part-selects to wires (Icarus does
  // not support constant selects inside always_* processes — wolf_dma lesson).
  wire [AW+16-1:0] q_head    = q[rptr[QAW-1:0]];
  wire [AW-1:0]    q_head_a  = q_head[AW+16-1:16];
  wire [15:0]      q_head_d  = q_head[15:0];
  always_comb begin
    // dequeue one if available
    w_we  = !qempty;
    w_aa  = q_head_a;
    w_awd = q_head_d;
  end

  // port A: FIFO -> mirror write (read side of FIFO uses q, not mem)
  always_ff @(posedge clk) begin
    if (rst) begin
      wptr <= '0; rptr <= '0;
    end else begin
      if (!qempty) rptr <= rptr + 1'b1;                 // dequeue -> applied below
      // enqueue A then B (distinct slots; wptr advances by count)
      if (we_a && we_b) begin
        q[wptr[QAW-1:0]]         <= {aa, awd};
        q[wptr[QAW-1:0] + 1'b1]  <= {ba, bwd};          // next slot (wraps in QAW bits)
        wptr <= wptr + 2'd2;
      end else if (we_a) begin
        q[wptr[QAW-1:0]] <= {aa, awd};  wptr <= wptr + 1'b1;
      end else if (we_b) begin
        q[wptr[QAW-1:0]] <= {ba, bwd};  wptr <= wptr + 1'b1;
      end
    end
  end
  // the actual mirror write (port A)
  always_ff @(posedge clk) if (w_we) mem[w_aa] <= w_awd;

  // port B: dedicated video read (1-clk registered) + RDW bypass.
  //
  // The bypass is what makes `no_rw_check` HONEST rather than merely asserted.
  // Both the RAM read and the comparison are registered on the same edge, so the
  // forwarded value lands in the same cycle the RAM output would have, and the
  // 1-clk read latency contract is unchanged.
  //
  // Forwarding NEW data (the value being written), not old. Cost is one 15-bit
  // comparator and a 16-bit mux against a 512 kbit array.
  //
  // *** NEW-vs-OLD IS NOT A FIDELITY DECISION AND THERE IS NO GOSPEL CITATION
  // *** FOR IT. Do not go looking for one. MAME has no cycle-level collision
  // semantics at all here -- it marks the tilemap dirty and re-renders, so there
  // is no "correct" answer to inherit from midtunit_v.cpp. What is being chosen
  // is DETERMINISM, not accuracy: either polarity is defined, and the entire
  // point is that the UNDEFINED M10K collision output is never OBSERVED.
  // New-data is picked because the CPU has just written this palette entry and
  // it is the cheaper of the two. Flipping it to old-data would cost an extra
  // stage for NO behavioural gain -- so if you are here because the absent
  // citation bothered you, the answer is that the citation cannot exist.
  // (Point made by the Gladiator session, 2026-07-27, after their own failed
  // attribute-drop fit.)
  logic        rdw_hit_q;
  logic [15:0] rdw_data_q;
  logic [15:0] mem_q;
  always_ff @(posedge clk) begin
    mem_q      <= mem[raddr];
    rdw_hit_q  <= w_we && (w_aa == raddr);
    rdw_data_q <= w_awd;
  end
  assign rdata = rdw_hit_q ? rdw_data_q : mem_q;
endmodule
`default_nettype wire

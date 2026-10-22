// -----------------------------------------------------------------------------
// tms34010_regfile.sv
//
// General-purpose register file for the TMS34010 core.
//
// Architectural contract (per bibliography/hdl-reimplementation/03-registers.md):
//   - File A: A0..A14 (15 entries, 32 bits each).
//   - File B: B0..B14 (15 entries, 32 bits each).
//   - SP    : 1 entry, 32 bits, accessible from BOTH files at index 4'hF
//             (i.e., A15 and B15 are aliases for the same SP).
//
// Port shape:
//   - Two combinational read ports. Async read is FPGA-friendly for this
//     size (~1 Kb total) — fits in distributed/LUT RAM on Cyclone V or
//     plain flip-flops without inflating the LUT count.
//   - One synchronous write port. Write-after-read on the SAME port within
//     a cycle: a read on `rs1`/`rs2` issued in the same cycle as a write
//     to the matching index returns the OLD value (the new value lands at
//     the next clock edge). This matches the multi-cycle execute model.
//
// Reset:
//   Synchronous active-high `rst`. All entries clear to '0. The loop in
//   the reset arm is bounded and fully unrollable (15 iterations × 2 files
//   + 1 SP = 31 sequential element updates), so synthesis treats it as
//   plain parallel resets.
//
// Notes:
//   - SP aliasing is implemented in one place (the read/write decode
//     functions). Code that touches the regfile never has to know about
//     the alias.
//   - No `/`, no `%`, no `initial` (rst handles all init), no unbounded
//     loops, no latches (all combinational outputs assigned on every
//     path through `always_comb`).
//
// Spec source:
//   third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_regfile
  import tms34010_pkg::*;
#(parameter bit USE_MLAB = 1'b0)(
  input  wire logic                  clk,
  input  wire logic                  ce_cpu,   // P0019: CPU clock-enable (see tms34010_core)
  input  wire logic                  rst,

  // Read port 1.
  input  wire reg_file_t             rs1_file,
  input  wire reg_idx_t              rs1_idx,
  output logic [DATA_WIDTH-1:0] rs1_data,

  // Read port 2.
  input  wire reg_file_t             rs2_file,
  input  wire reg_idx_t              rs2_idx,
  output logic [DATA_WIDTH-1:0] rs2_data,

  // Read port 3. Added for instructions that need a third simultaneous
  // source — currently CPW (reads the point plus WSTART and WEND). Async
  // read like the others; a third read mux on this flop-based file is
  // cheap (no extra memory blocks).
  input  wire reg_file_t             rs3_file,
  input  wire reg_idx_t              rs3_idx,
  output logic [DATA_WIDTH-1:0] rs3_data,

  // Write port.
  input  wire logic                  wr_en,
  input  wire reg_file_t             wr_file,
  input  wire reg_idx_t              wr_idx,
  input  wire logic [DATA_WIDTH-1:0] wr_data,

  // Observability: SP value, used by testbenches and (eventually) host
  // interface debug paths.
  output logic [DATA_WIDTH-1:0] sp_o
);

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] a_regs [0:14];
  logic [DATA_WIDTH-1:0] b_regs [0:14];
  logic [DATA_WIDTH-1:0] sp_q;

  generate if (USE_MLAB) begin : mlab
    // Three copies supply the three asynchronous read ports. A validity bit
    // per register preserves reset-to-zero without resetting the RAM cells,
    // which would force Quartus to implement the storage as flip-flops.
    // Forward the last accepted write to hide the MLAB mixed-port collision
    // interval; other addresses read the array. Before an edge the forwarding
    // latch still holds the previous value, preserving old-data read semantics.
    // Keep SP as a flop: it has a fourth, dedicated asynchronous read tap.
    (* ramstyle = "MLAB, no_rw_check" *) logic [DATA_WIDTH-1:0] port1_mem [0:31];
    (* ramstyle = "MLAB, no_rw_check" *) logic [DATA_WIDTH-1:0] port2_mem [0:31];
    (* ramstyle = "MLAB, no_rw_check" *) logic [DATA_WIDTH-1:0] port3_mem [0:31];
    logic [31:0] valid;
    // Keep the decoded acceptance on the CPU-enable edge. The full-rate
    // phase flag alone controls the one-system-clock-later RAM commit.
    (* preserve *) logic last_write_valid;
    logic write_phase;
    wire write_pending = write_phase && last_write_valid;
    logic [4:0] last_write_addr;
    logic [DATA_WIDTH-1:0] last_write_data;
    wire [4:0] a1 = {(rs1_file == REG_FILE_B),rs1_idx};
    wire [4:0] a2 = {(rs2_file == REG_FILE_B),rs2_idx};
    wire [4:0] a3 = {(rs3_file == REG_FILE_B),rs3_idx};
    wire [4:0] wa = {(wr_file == REG_FILE_B),wr_idx};
    wire write_ram = !rst && (ce_cpu !== 1'b0) && wr_en && (wr_idx != REG_SP_IDX);
    always @(posedge clk) if (write_ram) begin
      last_write_addr <= wa;
      last_write_data <= wr_data;
    end
    // Commit the previously accepted write from the existing forwarding FFs.
    // Reads of the newest address already return last_write_data, so the RAM
    // can trail that architectural write by one system clock with no CPU stall.
    // Consecutive writes work too: the old forwarding word enters RAM at the
    // same edge that the next word replaces it in the forwarding FFs.
    always @(posedge clk) begin
      if (rst) begin
        write_phase <= 1'b0;
        last_write_valid <= 1'b0;
      end else begin
        write_phase <= (ce_cpu !== 1'b0);
        if (ce_cpu !== 1'b0)
          last_write_valid <= wr_en && (wr_idx != REG_SP_IDX);
      end
      if (!rst && write_pending) begin
        port1_mem[last_write_addr] <= last_write_data;
        port2_mem[last_write_addr] <= last_write_data;
        port3_mem[last_write_addr] <= last_write_data;
      end
    end
    always_ff @(posedge clk) begin
      if (rst) begin valid <= '0; sp_q <= '0; end
      else if ((ce_cpu !== 1'b0) && wr_en) begin
        if (wr_idx == REG_SP_IDX) sp_q <= wr_data;
        else valid[wa] <= 1'b1;
      end
    end
    assign rs1_data = (rs1_idx == REG_SP_IDX) ? sp_q : valid[a1] ? ((a1 == last_write_addr) ? last_write_data : port1_mem[a1]) : '0;
    assign rs2_data = (rs2_idx == REG_SP_IDX) ? sp_q : valid[a2] ? ((a2 == last_write_addr) ? last_write_data : port2_mem[a2]) : '0;
    assign rs3_data = (rs3_idx == REG_SP_IDX) ? sp_q : valid[a3] ? ((a3 == last_write_addr) ? last_write_data : port3_mem[a3]) : '0;
`ifndef SYNTHESIS
`define TMS_REGFILE_TAPS
`elsif VERILATOR
`define TMS_REGFILE_TAPS
`endif
`ifdef TMS_REGFILE_TAPS
    // Preserve upstream testbench register taps without extra hardware ports.
    for (genvar i=0;i<15;i++) begin : taps
      assign a_regs[i] = valid[i] ? ((last_write_addr == 5'(i)) ? last_write_data : port1_mem[i]) : '0;
      assign b_regs[i] = valid[i+16] ? ((last_write_addr == 5'(i+16)) ? last_write_data : port1_mem[i+16]) : '0;
    end
`undef TMS_REGFILE_TAPS
`endif
  end else begin : flops
  // ---------------------------------------------------------------------------
  // Read multiplex (combinational / async read)
  //
  // Index 4'hF on either file returns SP. Other indices return the matching
  // file entry. Implemented inline rather than via a function to keep the
  // synthesizable form trivial for Quartus.
  // ---------------------------------------------------------------------------
  always_comb begin
    if (rs1_idx == REG_SP_IDX) begin
      rs1_data = sp_q;
    end else if (rs1_file == REG_FILE_B) begin
      rs1_data = b_regs[rs1_idx];
    end else begin
      rs1_data = a_regs[rs1_idx];
    end
  end

  always_comb begin
    if (rs2_idx == REG_SP_IDX) begin
      rs2_data = sp_q;
    end else if (rs2_file == REG_FILE_B) begin
      rs2_data = b_regs[rs2_idx];
    end else begin
      rs2_data = a_regs[rs2_idx];
    end
  end

  always_comb begin
    if (rs3_idx == REG_SP_IDX) begin
      rs3_data = sp_q;
    end else if (rs3_file == REG_FILE_B) begin
      rs3_data = b_regs[rs3_idx];
    end else begin
      rs3_data = a_regs[rs3_idx];
    end
  end

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) if (rst || (ce_cpu !== 1'b0)) begin
    if (rst) begin
      // Bounded, fully unrollable resets.
      for (int unsigned i = 0; i < 15; i++) begin
        a_regs[i] <= '0;
      end
      for (int unsigned i = 0; i < 15; i++) begin
        b_regs[i] <= '0;
      end
      sp_q <= '0;
    end else if (wr_en) begin
      if (wr_idx == REG_SP_IDX) begin
        sp_q <= wr_data;
      end else if (wr_file == REG_FILE_B) begin
        b_regs[wr_idx] <= wr_data;
      end else begin
        a_regs[wr_idx] <= wr_data;
      end
    end
  end

  end endgenerate

  assign sp_o = sp_q;

endmodule : tms34010_regfile
`default_nettype wire

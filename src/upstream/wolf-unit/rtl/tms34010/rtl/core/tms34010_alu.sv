// -----------------------------------------------------------------------------
// tms34010_alu.sv
//
// 32-bit purely combinational ALU. Produces a result and four flags
// (N, C, Z, V). No internal state — the surrounding control logic latches
// the result and flags into the register file and status register.
//
// Operations (alu_op_t in tms34010_pkg):
//   ADD     r = a + b
//   ADDC    r = a + b + cin              (cin from ST's C flag)
//   SUB     r = a - b                    (and CMP, which is SUB without writeback)
//   SUBB    r = a - b - cin              (cin = borrow-in)
//   CMP     same as SUB, but the surrounding control does not write back r
//   AND     r = a & b
//   ANDN    r = a & ~b
//   OR      r = a | b
//   XOR     r = a ^ b
//   NOT     r = ~a
//   NEG     r = 0 - a                    (implemented via the subtractor)
//   PASS_A  r = a                        (MOVE / passthrough)
//   PASS_B  r = b
//
// Flag convention:
//   - Arithmetic ops (ADD/ADDC/SUB/SUBB/CMP/NEG):
//       N = r[31]
//       Z = (r == 0)
//       C = unsigned-overflow indicator. For ADD/ADDC: carry-out of bit 31.
//           For SUB/SUBB/CMP/NEG: borrow-out, equal to !(carry-out of a + ~b + cin').
//       V = signed-overflow indicator.
//           ADD: V = (a[31] == b[31]) && (r[31] != a[31])
//           SUB: V = (a[31] != b[31]) && (r[31] != a[31])
//           NEG is just SUB with a=0, so it falls out naturally.
//   - Logical ops (AND/ANDN/OR/XOR/NOT/PASS_A/PASS_B):
//       N = r[31], Z = (r == 0), C = 0, V = 0.
//
// Per-instruction nuances (e.g., whether MOVE clears or preserves flags;
// the V-on-MIN-NEG behavior of ABS that we don't implement here) live in
// docs/assumptions.md A0009 until SPVU001A Appendix A is read in detail.
//
// Synthesis notes:
//   - One `always_comb` block, with a safe default at the top.
//   - The 33-bit add gives carry and result in one synthesizable adder.
//   - No `/`, no `%`, no loops, no `initial`.
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_alu
  import tms34010_pkg::*;
#(
`ifdef POCKET
  parameter bit SHARED_ADDER = 1'b1
`else
  parameter bit SHARED_ADDER = 1'b0
`endif
)(
  input  wire alu_op_t                 op,
  input  wire logic [DATA_WIDTH-1:0]   a,
  input  wire logic [DATA_WIDTH-1:0]   b,
  input  wire logic                    cin,   // ST.C for ADDC; borrow-in for SUBB

  output logic [DATA_WIDTH-1:0]   result,
  output var alu_flags_t              flags
);

  // ---------------------------------------------------------------------------
  // 33-bit adder/subtractor result extraction
  //
  // ADD path:  {cout, sum} = a + b + (op == ADDC ? cin : 0)
  // SUB path:  {cout, sum} = a + ~b + 1 - (op == SUBB ? cin : 0)
  //                       = a + ~b + (op == SUBB ? !cin : 1)
  // ---------------------------------------------------------------------------
  logic [DATA_WIDTH:0]   add_ext;   // 33-bit
  logic [DATA_WIDTH:0]   sub_ext;   // 33-bit
  logic [DATA_WIDTH-1:0] not_b;
  logic                  add_cin;
  logic                  sub_cin;   // value added to a + ~b (1 for SUB, !cin for SUBB)

  assign not_b   = ~b;
  assign add_cin = (op == ALU_OP_ADDC) ? cin : 1'b0;
  assign sub_cin = (op == ALU_OP_SUBB) ? !cin : 1'b1;
  // Only one arithmetic operation is consumed per cycle. Select its operands
  // before the adder rather than instantiate add, subtract and negate paths.
  // SUBB's C flag remains the original operand comparison below: its borrow
  // input affects the result but must not affect C when a == b.
  wire shared_negate = (op == ALU_OP_NEG) || (op == ALU_OP_ABS);
  wire shared_subtract = shared_negate || (op == ALU_OP_SUB)
                       || (op == ALU_OP_SUBB) || (op == ALU_OP_CMP);
  wire [DATA_WIDTH-1:0] shared_a = shared_negate ? '0 : a;
  wire [DATA_WIDTH-1:0] shared_b = shared_subtract ? ~(shared_negate ? a : b) : b;
  wire shared_cin = shared_subtract ? sub_cin : add_cin;
  wire [DATA_WIDTH:0] shared_sum = {1'b0, shared_a} + {1'b0, shared_b}
                                + {{DATA_WIDTH{1'b0}}, shared_cin};
  assign add_ext = SHARED_ADDER ? shared_sum
                 : {1'b0, a} + {1'b0, b} + {{DATA_WIDTH{1'b0}}, add_cin};
  assign sub_ext = SHARED_ADDER ? shared_sum
                 : {1'b0, a} + {1'b0, not_b} + {{DATA_WIDTH{1'b0}}, sub_cin};

  // ---------------------------------------------------------------------------
  // Result mux
  // ---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] add_result;
  logic [DATA_WIDTH-1:0] sub_result;
  logic [DATA_WIDTH-1:0] neg_result;
  logic [DATA_WIDTH:0]   neg_ext;
  logic [DATA_WIDTH-1:0] not_a;

  assign add_result = add_ext[DATA_WIDTH-1:0];
  assign sub_result = sub_ext[DATA_WIDTH-1:0];
  assign not_a      = ~a;
  // NEG = 0 - a. Implemented as a + ~b + 1 with a = 0, b = a-of-input.
  assign neg_ext    = SHARED_ADDER ? shared_sum
                     : {1'b0, {DATA_WIDTH{1'b0}}} + {1'b0, not_a} + 33'd1;
  assign neg_result = neg_ext[DATA_WIDTH-1:0];

  always_comb begin
    // Safe defaults. Result = 0, flags = 0. Every case arm assigns a real
    // value, so this default exists only to prevent latch inference on a
    // future arm that forgets a flag.
    result    = '0;
    flags.n   = 1'b0;
    flags.c   = 1'b0;
    flags.z   = 1'b0;
    flags.v   = 1'b0;

    unique case (op)
      ALU_OP_ADD, ALU_OP_ADDC: begin
        result   = add_result;
        flags.n  = add_result[DATA_WIDTH-1];
        flags.z  = (add_result == '0);
        flags.c  = add_ext[DATA_WIDTH];
        flags.v  = (a[DATA_WIDTH-1] == b[DATA_WIDTH-1])
                && (add_result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
      end

      ALU_OP_SUB, ALU_OP_SUBB, ALU_OP_CMP: begin
        result   = sub_result;
        flags.n  = sub_result[DATA_WIDTH-1];
        flags.z  = (sub_result == '0);
        // SHARED-P0030. C is a PURE UNSIGNED OPERAND COMPARE, independent of the
        // borrow-in: MAME 34010ops.hxx:66  SET_C_LOG((uint32_t)b > (uint32_t)a).
        // SUBB (34010ops.hxx:985-994) folds the borrow into the RESULT
        //   r = *rd - t - (C_FLAG() ? 1 : 0)
        // and then flags with SET_NZCV_SUB(*rd, t, r) -- i.e. from the ORIGINAL
        // operands, NOT from the borrowed subtraction.
        //
        // The previous form was `!sub_ext[DATA_WIDTH]`, the carry-out of
        // (a + ~b + sub_cin). That READS as correct borrow semantics, and for
        // SUB/CMP it IS identical to (b > a). But for SUBB, sub_cin carries the
        // borrow-in (:74), so the borrow contaminated the same adder whose
        // carry-out became C. Divergence is exactly at a == b with borrow set:
        // MAME C=0, adder form C=1.
        // NOTE the fix deliberately does NOT touch sub_cin -- SUBB's RESULT must
        // still include the borrow. Only the FLAG is operand-derived.
        //
        // Found by the NARC (Z-unit) session, gated by Y-unit, measured across
        // all five forks by T-unit: Wolf, rampage-wt-tree and UMK3 all had it.
        // A code reading of the old line agreed with its own comment and with
        // gospel, and was still wrong -- the defect was two lines upstream.
        flags.c  = (b > a);
        flags.v  = (a[DATA_WIDTH-1] != b[DATA_WIDTH-1])
                && (sub_result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
      end

      ALU_OP_NEG: begin
        result   = neg_result;
        flags.n  = neg_result[DATA_WIDTH-1];
        flags.z  = (neg_result == '0);
        // Borrow-out from (0 - a) = (a != 0). Equivalently, !carry-out of
        // (0 + ~a + 1) — both come out the same here.
        flags.c  = !neg_ext[DATA_WIDTH];
        // Signed overflow on NEG occurs only for a == 32'h8000_0000.
        // Falls out from SUB-style V with a-side==0.
        flags.v  = (a[DATA_WIDTH-1])
                && (neg_result[DATA_WIDTH-1]);
      end

      ALU_OP_AND: begin
        result  = a & b;
        flags.n = result[DATA_WIDTH-1];
        flags.z = (result == '0);
      end

      ALU_OP_ANDN: begin
        result  = a & ~b;
        flags.n = result[DATA_WIDTH-1];
        flags.z = (result == '0);
      end

      ALU_OP_OR: begin
        result  = a | b;
        flags.n = result[DATA_WIDTH-1];
        flags.z = (result == '0);
      end

      ALU_OP_XOR: begin
        result  = a ^ b;
        flags.n = result[DATA_WIDTH-1];
        flags.z = (result == '0);
      end

      ALU_OP_NOT: begin
        result  = ~a;
        flags.n = result[DATA_WIDTH-1];
        flags.z = (result == '0);
      end

      ALU_OP_PASS_A: begin
        result  = a;
        flags.n = a[DATA_WIDTH-1];
        flags.z = (a == '0);
      end

      ALU_OP_PASS_B: begin
        result  = b;
        flags.n = b[DATA_WIDTH-1];
        flags.z = (b == '0);
      end

      ALU_OP_ABS: begin
        // |a|. Uses the existing neg_result (= 0 - a).
        // - If neg_result is non-negative (sign bit 0), then a was
        //   negative (and small enough to flip): |a| = neg_result.
        // - If neg_result is negative (sign bit 1), then either a was
        //   already non-negative (|a| = a) OR a == MIN_INT and the
        //   negate overflowed (|a| can't be represented; spec returns
        //   a unchanged with V=1). Both → result = a.
        // Status bits per SPVU001A page 12-34:
        //   N = sign of (0 - a)            (NOT sign of |a|)
        //   C = "Unaffected" per spec — we set 0 here (A0024).
        //   Z = (original a == 0)
        //   V = (a == 0x8000_0000)         (MIN_INT overflow)
        result   = neg_result[DATA_WIDTH-1] ? a : neg_result;
        flags.n  = neg_result[DATA_WIDTH-1];
        flags.z  = (a == '0);
        flags.c  = 1'b0;
        flags.v  = (a == 32'h8000_0000);
      end

      default: begin
        // Unreachable in synthesis (unique case covers every enum value).
        // Defaults already applied above.
      end
    endcase
  end

endmodule : tms34010_alu
`default_nettype wire

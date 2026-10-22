// -----------------------------------------------------------------------------
// tms34010_shifter.sv
//
// 32-bit purely combinational barrel shifter.
//
// Operations:
//   SLL : shift left, fill LSB with 0       (logical)
//   SLA : shift left, arithmetic            (same output as SLL in Phase 2;
//                                            V-flag-on-sign-change quirk
//                                            tracked in A0009)
//   SRL : shift right, fill MSB with 0      (logical)
//   SRA : shift right, sign-extend MSB      (arithmetic)
//   RL  : rotate left
//   RR  : rotate right
//
// Output flags (alu_flags_t):
//   N : result[31]
//   Z : result == 0
//   C : last bit shifted/rotated out:
//       SLL/SLA/RL: a[32 - amount]   (the MSB-side bit that just departed)
//       SRL/SRA/RR: a[amount - 1]    (the LSB-side bit that just departed)
//       amount == 0: C = 0 (nothing shifted).
//   V : SLA only — arithmetic-left-shift overflow (a significant bit is
//       shifted past/into the sign). 0 for SLL/SRL/SRA/RL/RR. The decode
//       flag mask makes V "Unaffected" for every op except SLA.
//
// Synthesis notes:
//   - One `always_comb` block with safe defaults at the top.
//   - Five shift expressions are pre-computed in `always_comb`-free assigns
//     so Quartus shares the barrel-shifter network.
//   - amount == 0 is special-cased to avoid `>> 32` undefined-by-design
//     behavior in rotates.
//   - No `/`, no `%`, no `initial`, no runtime loops.
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_shifter
  import tms34010_pkg::*;
#(
`ifdef POCKET
  parameter bit SHARED_BARREL = 1'b1
`else
  parameter bit SHARED_BARREL = 1'b0
`endif
)(
  input  wire shift_op_t                       op,
  input  wire logic [DATA_WIDTH-1:0]           a,
  input  wire logic [SHIFT_AMOUNT_WIDTH-1:0]   amount,

  output logic [DATA_WIDTH-1:0]           result,
  output var alu_flags_t                      flags
);

  // Widened amount and its complement (32 - amount). Using 6 bits avoids
  // the wrap that happens when subtracting 32 in a 5-bit field.
  logic [SHIFT_AMOUNT_WIDTH:0] amount_w6;
  logic [SHIFT_AMOUNT_WIDTH:0] complement_w6;
  assign amount_w6     = {1'b0, amount};
  assign complement_w6 = 6'd32 - amount_w6;
  // 5-bit slices for indexing into `a`. For amount in [1..31] both are
  // valid bit indices; the amount==0 case is handled separately so the
  // bit index does not need to be 32.
  logic [SHIFT_AMOUNT_WIDTH-1:0] left_carry_idx;
  logic [SHIFT_AMOUNT_WIDTH-1:0] right_carry_idx;
  assign left_carry_idx  = complement_w6[SHIFT_AMOUNT_WIDTH-1:0];
  assign right_carry_idx = amount - 5'd1;

  // Pre-computed shift networks. SystemVerilog `<<`/`>>` accept any
  // unsigned amount; for amount == 0 these are all identity (no-op).
  logic [DATA_WIDTH-1:0]        left;        // a << amount
  logic [DATA_WIDTH-1:0]        right_l;     // a >> amount        (logical)
  logic signed [DATA_WIDTH-1:0] right_a;     // a >>> amount       (arithmetic)
  logic [DATA_WIDTH-1:0]        right_comp;  // a >> (32 - amount) — for RL
  logic [DATA_WIDTH-1:0]        left_comp;   // a << (32 - amount) — for RR

  assign left       = a << amount;
  assign right_l    = a >> amount;
  assign right_a    = $signed(a) >>> amount;
  assign right_comp = a >> complement_w6;
  assign left_comp  = a << complement_w6;

  // Left operations reverse the bit order around one right barrel. Each
  // stage selects either the low wrapped bits (rotate), zero, or the sign
  // bit. This replaces the independent left/right/complement networks.
  wire shared_left = (op == SHIFT_OP_SLL) || (op == SHIFT_OP_SLA)
                   || (op == SHIFT_OP_RL);
  wire shared_rotate = (op == SHIFT_OP_RL) || (op == SHIFT_OP_RR);
  wire shared_fill = (op == SHIFT_OP_SRA) && a[DATA_WIDTH-1];
  wire [DATA_WIDTH-1:0] shared_stage [0:SHIFT_AMOUNT_WIDTH];
  wire [DATA_WIDTH-1:0] shared_result;
  for (genvar bit_idx = 0; bit_idx < DATA_WIDTH; bit_idx++) begin : reverse_barrel_bits
    assign shared_stage[0][bit_idx] = shared_left ? a[DATA_WIDTH-1-bit_idx] : a[bit_idx];
    assign shared_result[bit_idx] = shared_left
      ? shared_stage[SHIFT_AMOUNT_WIDTH][DATA_WIDTH-1-bit_idx]
      : shared_stage[SHIFT_AMOUNT_WIDTH][bit_idx];
  end
  for (genvar stage_idx = 0; stage_idx < SHIFT_AMOUNT_WIDTH; stage_idx++) begin : barrel_stage
    localparam integer STEP = 1 << stage_idx;
    wire [STEP-1:0] upper = shared_rotate ? shared_stage[stage_idx][STEP-1:0]
                                         : {STEP{shared_fill}};
    assign shared_stage[stage_idx+1] = amount[stage_idx]
      ? {upper, shared_stage[stage_idx][DATA_WIDTH-1:STEP]} : shared_stage[stage_idx];
  end

  // SLA (shift-left-arithmetic) overflow V. MAME (34010ops.hxx SLA):
  //   mask = (0xffffffff << (31-k)) & 0x7fffffff;
  //   res2 = SIGN(a) ? a^mask : a;   V = (res2 & mask) != 0
  // i.e. V=1 iff any of the `amount` bits just below the sign bit differ
  // from the sign bit (a significant bit is shifted out / the sign flips).
  // Only consumed for SLA (all other shift ops mask V off).
  logic [DATA_WIDTH-1:0] sla_v_mask;
  logic [DATA_WIDTH-1:0] sla_v_res2;
  assign sla_v_mask = (32'hFFFF_FFFF << (6'd31 - amount_w6)) & 32'h7FFF_FFFF;
  assign sla_v_res2 = a[DATA_WIDTH-1] ? (a ^ sla_v_mask) : a;

  // Separate generate branches prevent synthesis retaining the legacy
  // networks behind a logically redundant op-dependent result override.
  generate if (SHARED_BARREL) begin : shared_output
    always_comb begin
      result = a;
      flags.c = 1'b0;
      flags.v = 1'b0;
      if (amount != '0 && op <= SHIFT_OP_RR) begin
        result = shared_result;
        // In the reversed domain, both directions discard bit amount-1.
        flags.c = shared_stage[0][right_carry_idx];
        if (op == SHIFT_OP_SLA) flags.v = |(sla_v_res2 & sla_v_mask);
      end
      flags.n = result[DATA_WIDTH-1];
      flags.z = (result == '0);
    end
  end else begin : legacy_output
  always_comb begin
    // Defaults: identity passthrough.
    result  = a;
    flags.n = a[DATA_WIDTH-1];
    flags.c = 1'b0;
    flags.z = (a == '0);
    flags.v = 1'b0;

    if (amount != '0) begin
      unique case (op)
        SHIFT_OP_SLL: begin
          result  = left;
          flags.c = a[left_carry_idx];
        end
        SHIFT_OP_SLA: begin
          result  = left;
          flags.c = a[left_carry_idx];
          flags.v = |(sla_v_res2 & sla_v_mask);   // arithmetic-shift overflow
        end
        SHIFT_OP_SRL: begin
          result  = right_l;
          flags.c = a[right_carry_idx];
        end
        SHIFT_OP_SRA: begin
          result  = right_a;
          flags.c = a[right_carry_idx];
        end
        SHIFT_OP_RL: begin
          result  = left | right_comp;
          flags.c = a[left_carry_idx];
        end
        SHIFT_OP_RR: begin
          result  = right_l | left_comp;
          flags.c = a[right_carry_idx];
        end
        default: ;  // unique case covers every enum
      endcase

      flags.n = result[DATA_WIDTH-1];
      flags.z = (result == '0);
    end
  end

  end endgenerate

endmodule : tms34010_shifter
`default_nettype wire

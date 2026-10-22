// wolf_gfx_interleave.sv — combinational transform: linear MRA-part-stream byte address
// (as the 20 gfx chips arrive back-to-back, ordered u133,u132,u131,u130, u129,...,u110 --
// matching sim/make_wolf_gfx_hex.py's GROUPS list) -> the correct byte-interleaved
// destination address in the 32MB gfx region (matching ROM_LOAD32_BYTE's lane layout,
// mame-gospel/midway/midwunit.cpp ROM_START(umk3):884-909). Same transform as
// make_wolf_gfx_hex.py, done at download time instead of pre-processing the ROM file --
// mirrors this project's OWN precedent for the prog-ROM u54/u63 byte-lane interleave
// (done on-chip in Arcade-SmashTV.sv, per the MRA's own header comment).
//
// CHIP_SIZE = 0x100000 (1MB) is a power of 2, so chip_index/chip_off fall out of the
// linear address as pure bit-slices (no divide): chip_index = addr[24:20] (0..19),
// chip_off = addr[19:0]. group = chip_index[4:2] (0..4), lane = chip_index[1:0] (0..3).
// GROUP_BASE skips 0x1000000-0x13FFFFF (sockets U114-U117 empty on this board revision).
// dest = GROUP_BASE[group] + {chip_off, lane} (chip_off<<2 | lane, disjoint bit ranges).
`default_nettype none
module wolf_gfx_interleave #(
    // MK3 uses four 512 KiB U117..U114 parts immediately at 0x1000000.
    // UMK3 instead uses four 1 MiB U113..U110 parts at 0x1400000 after an
    // unpopulated 4 MiB socket group. All earlier groups are identical.
    parameter bit MK3_LAYOUT = 1'b0
) (
    input  logic        mk3_layout_i, // runtime master-core profile; may be left open by legacy TBs
    input  logic [24:0] lin_addr,     // 0..0x13FFFFF (20 chips x 1MB, MRA part order)
    output logic [24:0] dest_addr     // byte address in the 32MB gfx region
);
    wire [4:0] chip_index = lin_addr[24:20];
    wire [19:0] chip_off  = lin_addr[19:0];
    wire [2:0] group      = chip_index[4:2];
    wire [1:0] lane       = chip_index[1:0];

    logic [24:0] group_base;
    always_comb begin
        case (group)
            3'd0: group_base = 25'h0000000;
            3'd1: group_base = 25'h0400000;
            3'd2: group_base = 25'h0800000;
            3'd3: group_base = 25'h0C00000;
            3'd4: group_base = 25'h1400000;   // skips the 0x1000000 U114-U117 gap
            default: group_base = 25'h0000000;
        endcase
    end
    wire [20:0] mk3_tail_addr = lin_addr[20:0]; // lin_addr - 0x1000000
    wire  [1:0] mk3_tail_lane = mk3_tail_addr[20:19];
    wire [18:0] mk3_tail_off  = mk3_tail_addr[18:0];
    wire [24:0] normal_dest   = group_base + {chip_off, lane};
    wire [24:0] mk3_tail_dest = 25'h1000000 + {mk3_tail_off, mk3_tail_lane};
    logic use_mk3_layout;

    // The elaboration parameter remains for focused legacy tests. A connected
    // runtime input promotes the same transform in the one-RBF master core.
    always_comb begin
        use_mk3_layout = MK3_LAYOUT;
        case (mk3_layout_i)
            1'b1:    use_mk3_layout = 1'b1;
            default: use_mk3_layout = MK3_LAYOUT;
        endcase
    end

    assign dest_addr = (use_mk3_layout && (lin_addr >= 25'h1000000))
                     ? mk3_tail_dest : normal_dest;
endmodule
`default_nettype wire

// wolf_game_inputs.sv -- runtime-selectable Wolf-unit control and DIP profiles.
//
// The MRA supplies one profile byte at ioctl index 3. Button labels/counts stay
// in each MRA, while this block translates the resulting MiSTer joystick bits
// to the exact active-low Wolf harness read by the selected game.

`default_nettype none

module wolf_game_inputs #(
    parameter integer PROFILE = 3,
    parameter bit RUNTIME_SELECT = 1'b0
) (
    input  logic [2:0]  game_profile,
    input  logic [15:0] joystick_0,
    input  logic [15:0] joystick_1,
    input  logic [15:0] joystick_2,
    input  logic [15:0] joystick_3,
    input  logic [31:0] status,
    output logic [15:0] in0,
    output logic [15:0] in1,
    output logic [15:0] in2,
    output logic [15:0] dsw
);
    localparam logic [2:0] PROFILE_OPEN_ICE = 3'd0;
    localparam logic [2:0] PROFILE_WWF      = 3'd1;
    localparam logic [2:0] PROFILE_MK3      = 3'd2;
    localparam logic [2:0] PROFILE_UMK3     = 3'd3;
    localparam logic [2:0] PROFILE_NBA      = 3'd4;
    localparam logic [2:0] PROFILE_NBAMAX   = 3'd5;
    localparam logic [2:0] PROFILE_RAMPAGE  = 3'd6;

    logic [2:0]  active_profile;
    logic [15:0] in2_active;
    logic        test_switch;
    logic        service_credit;
    logic        vol_down;
    logic        vol_up;

    always_comb begin
        active_profile = PROFILE;
        if (RUNTIME_SELECT) begin
            case (game_profile)
                PROFILE_OPEN_ICE,
                PROFILE_WWF,
                PROFILE_MK3,
                PROFILE_UMK3,
                PROFILE_NBA,
                PROFILE_NBAMAX,
                PROFILE_RAMPAGE: active_profile = game_profile;
                default:         active_profile = PROFILE;
            endcase
        end
    end

    always_comb begin
        in0            = 16'hFFFF;
        in1            = 16'hFFFF;
        in2_active     = 16'h0000;
        dsw            = 16'hFFFF;
        test_switch    = status[8];
        service_credit = status[9];
        vol_down       = status[10];
        vol_up         = status[11];

        case (active_profile)
            PROFILE_OPEN_ICE: begin
                // Player byte: U,D,L,R,Shoot,Pass,Turbo,unused.
                // MRA order: Turbo,Shoot/Block,Pass/Steal,Start,Coin.
                in0 = ~{
                    1'b0, joystick_1[4], joystick_1[6], joystick_1[5],
                    joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3],
                    1'b0, joystick_0[4], joystick_0[6], joystick_0[5],
                    joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]
                };
                in1 = ~{
                    1'b0, joystick_3[4], joystick_3[6], joystick_3[5],
                    joystick_3[0], joystick_3[1], joystick_3[2], joystick_3[3],
                    1'b0, joystick_2[4], joystick_2[6], joystick_2[5],
                    joystick_2[0], joystick_2[1], joystick_2[2], joystick_2[3]
                };

                service_credit = status[9]  | (test_switch & joystick_0[7]);
                vol_down       = status[10] | (test_switch & joystick_0[2]);
                vol_up         = status[11] | (test_switch & joystick_0[3]);
                in2_active =
                    (joystick_0[8] ? 16'h0001 : 16'h0000) |
                    (joystick_1[8] ? 16'h0002 : 16'h0000) |
                    (joystick_0[7] ? 16'h0004 : 16'h0000) |
                    (joystick_1[7] ? 16'h0020 : 16'h0000) |
                    (service_credit ? 16'h0040 : 16'h0000) |
                    (joystick_2[8] ? 16'h0080 : 16'h0000) |
                    (joystick_3[8] ? 16'h0100 : 16'h0000) |
                    (joystick_2[7] ? 16'h0200 : 16'h0000) |
                    (joystick_3[7] ? 16'h0400 : 16'h0000) |
                    (vol_down ? 16'h0800 : 16'h0000) |
                    (vol_up   ? 16'h1000 : 16'h0000);

                // Open Ice: Test=DSW15, cabinet=DSW12. Defaults are MAME live
                // values including inactive active-low unused inputs.
                dsw = status[12] ? 16'hFBBE : 16'hEBBE; // 4P : 2P
                if (test_switch) dsw = dsw & ~16'h8000;
            end

            PROFILE_WWF: begin
                // MRA order: Punch,Defense,Power Punch,Kick,Power Kick.
                in0 = ~{
                    1'b0, joystick_1[6], joystick_1[5], joystick_1[4],
                    joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3],
                    1'b0, joystick_0[6], joystick_0[5], joystick_0[4],
                    joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]
                };
                in1 = ~{
                    8'h00, 2'b00, joystick_1[8], joystick_1[7],
                    2'b00, joystick_0[8], joystick_0[7]
                };

                service_credit = status[9]  | (test_switch & joystick_0[9]);
                vol_down       = status[10] | (test_switch & joystick_0[2]);
                vol_up         = status[11] | (test_switch & joystick_0[3]);
                in2_active =
                    (joystick_0[10] ? 16'h0001 : 16'h0000) |
                    (joystick_1[10] ? 16'h0002 : 16'h0000) |
                    (joystick_0[9]  ? 16'h0004 : 16'h0000) |
                    (joystick_1[9]  ? 16'h0020 : 16'h0000) |
                    (service_credit ? 16'h0040 : 16'h0000) |
                    (vol_down ? 16'h0800 : 16'h0000) |
                    (vol_up   ? 16'h1000 : 16'h0000);

                // WWF uses the shuffled Wolf I/O map and Test on DSW bit 0.
                dsw = test_switch ? 16'h7FFC : 16'h7FFD;
            end

            PROFILE_MK3,
            PROFILE_UMK3: begin
                // MK3 and UMK3 share the six-button harness and DIP layout.
                // MRA order: HP,LP,Block,HK,LK,Run,Start,Coin.
                in0 = ~{
                    1'b0, joystick_1[7], joystick_1[6], joystick_1[4],
                    joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3],
                    1'b0, joystick_0[7], joystick_0[6], joystick_0[4],
                    joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]
                };
                in1 = ~{
                    8'h00, 1'b0, joystick_1[9], joystick_1[8], joystick_1[5],
                    1'b0, joystick_0[9], joystick_0[8], joystick_0[5]
                };

                service_credit = status[9]  | (test_switch & joystick_0[10]);
                vol_down       = status[10] | (test_switch & joystick_0[2]);
                vol_up         = status[11] | (test_switch & joystick_0[3]);
                in2_active =
                    (joystick_0[11] ? 16'h0001 : 16'h0000) |
                    (joystick_1[11] ? 16'h0002 : 16'h0000) |
                    (joystick_0[10] ? 16'h0004 : 16'h0000) |
                    (joystick_1[10] ? 16'h0020 : 16'h0000) |
                    (service_credit ? 16'h0040 : 16'h0000) |
                    (vol_down ? 16'h0800 : 16'h0000) |
                    (vol_up   ? 16'h1000 : 16'h0000);

                dsw = test_switch ? 16'hFD7C : 16'hFD7D;
            end

            PROFILE_NBA,
            PROFILE_NBAMAX: begin
                // Hangtime-family player bytes match Open Ice, but the DIP
                // layout uses Test=bit0 and cabinet select=bit7.
                in0 = ~{
                    1'b0, joystick_1[4], joystick_1[6], joystick_1[5],
                    joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3],
                    1'b0, joystick_0[4], joystick_0[6], joystick_0[5],
                    joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]
                };
                in1 = ~{
                    1'b0, joystick_3[4], joystick_3[6], joystick_3[5],
                    joystick_3[0], joystick_3[1], joystick_3[2], joystick_3[3],
                    1'b0, joystick_2[4], joystick_2[6], joystick_2[5],
                    joystick_2[0], joystick_2[1], joystick_2[2], joystick_2[3]
                };

                service_credit = status[9]  | (test_switch & joystick_0[7]);
                vol_down       = status[10] | (test_switch & joystick_0[2]);
                vol_up         = status[11] | (test_switch & joystick_0[3]);
                in2_active =
                    (joystick_0[8] ? 16'h0001 : 16'h0000) |
                    (joystick_1[8] ? 16'h0002 : 16'h0000) |
                    (joystick_0[7] ? 16'h0004 : 16'h0000) |
                    (joystick_1[7] ? 16'h0020 : 16'h0000) |
                    (service_credit ? 16'h0040 : 16'h0000) |
                    (joystick_2[8] ? 16'h0080 : 16'h0000) |
                    (joystick_3[8] ? 16'h0100 : 16'h0000) |
                    (joystick_2[7] ? 16'h0200 : 16'h0000) |
                    (joystick_3[7] ? 16'h0400 : 16'h0000) |
                    (vol_down ? 16'h0800 : 16'h0000) |
                    (vol_up   ? 16'h1000 : 16'h0000);

                dsw = status[12] ? 16'h7FFD : 16'h7F7D; // 4P : 2P
                if (test_switch) dsw = dsw & ~16'h0001;
            end

            default: begin // PROFILE_RAMPAGE
                // MRA order: Jump,Punch,Kick,Start,Coin. The physical Wolf
                // button bits are Punch=4, Kick=5, Jump=6.
                in0 = ~{
                    1'b0, joystick_1[4], joystick_1[6], joystick_1[5],
                    joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3],
                    1'b0, joystick_0[4], joystick_0[6], joystick_0[5],
                    joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]
                };
                in1 = ~{
                    9'd0, joystick_2[4], joystick_2[6], joystick_2[5],
                    joystick_2[0], joystick_2[1], joystick_2[2], joystick_2[3]
                };

                service_credit = status[9]  | (test_switch & joystick_0[7]);
                vol_down       = status[10] | (test_switch & joystick_0[2]);
                vol_up         = status[11] | (test_switch & joystick_0[3]);
                in2_active =
                    (joystick_0[8] ? 16'h0001 : 16'h0000) |
                    (joystick_1[8] ? 16'h0002 : 16'h0000) |
                    (joystick_0[7] ? 16'h0004 : 16'h0000) |
                    (joystick_1[7] ? 16'h0020 : 16'h0000) |
                    (service_credit ? 16'h0040 : 16'h0000) |
                    (joystick_2[8] ? 16'h0080 : 16'h0000) |
                    (joystick_2[7] ? 16'h0200 : 16'h0000) |
                    (vol_down ? 16'h0800 : 16'h0000) |
                    (vol_up   ? 16'h1000 : 16'h0000);

                dsw = test_switch ? 16'h7BBE : 16'hFBBE;
            end
        endcase

        in2 = ~in2_active;
    end
endmodule

`default_nettype wire

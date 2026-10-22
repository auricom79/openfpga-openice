// SPDX-License-Identifier: MIT
// APF button layout -> existing Wolf harness. A=Turbo, B=Shoot, X=Pass.
// Two-stage synchronization matches APF's stable controller snapshots; transitions
// are not atomic across buttons. Menu status is supplied in the core clock domain.
`default_nettype none
module wolf_pocket_inputs (
    input wire clk, reset,
    input wire [31:0] cont1_key, cont2_key, cont3_key, cont4_key,
    input wire [31:0] status,
    output wire [63:0] inputs
);
    reg [127:0] keys_meta, keys;
    always @(posedge clk) begin
        if (reset) begin keys_meta <= 0; keys <= 0; end
        else begin
            keys_meta <= {cont4_key,cont3_key,cont2_key,cont1_key};
            keys <= keys_meta;
        end
    end
    function automatic [15:0] joystick(input [31:0] key);
        joystick = {7'd0,key[14],key[15],key[6],key[5],key[4],
                    key[0],key[1],key[2],key[3]};
    endfunction
    wolf_game_inputs #(.PROFILE(0),.RUNTIME_SELECT(1'b0)) harness (
        .game_profile(3'd0), .status(status),
        .joystick_0(joystick(keys[31:0])),
        .joystick_1(joystick(keys[63:32])),
        .joystick_2(joystick(keys[95:64])),
        .joystick_3(joystick(keys[127:96])),
        .in0(inputs[15:0]), .in1(inputs[31:16]),
        .in2(inputs[47:32]), .dsw(inputs[63:48])
    );
endmodule
`default_nettype wire

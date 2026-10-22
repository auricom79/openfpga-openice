// SPDX-License-Identifier: MIT
// APF 48 kHz stereo I2S: 12.288 MHz MCLK, 64 serial bits per stereo frame.
// Coherent bundled-data mailbox transfers the latest signed sample pair from
// the arcade clock. This is sample-and-hold resampling, without an audio filter.
`default_nettype none
module wolf_pocket_audio(
    input wire clk_bridge, reset_bridge, clk_mem, reset_mem,
    input wire signed [15:0] left,right,
    output reg mclk=0,lrck=0,dac=0
);
    reg [31:0] held=0,sample_pair=0;
    reg request=0,ack=0;
    (* async_reg="true" *) reg ack_meta=0,ack_sync=0,req_meta=0,req_sync=0;
    always @(posedge clk_mem) begin
        ack_meta<=ack; ack_sync<=ack_meta;
        if(reset_mem) begin held<=0;request<=0;ack_meta<=0;ack_sync<=0;end
        else if(ack_sync==request) begin held<={left,right};request<=~request;end
    end
    reg [20:0] accum=0;
    wire [21:0] next_accum={1'b0,accum}+22'd245760;
    reg [1:0] divider=0;
    reg [5:0] serial_count=0;
    reg [31:0] frame_samples=0;
    always @(posedge clk_bridge) begin
        req_meta<=request; req_sync<=req_meta;
        if(req_sync!=ack) begin sample_pair<=held;ack<=req_sync;end
        if(next_accum>=22'd742500) begin
            accum<=21'(next_accum-22'd742500);
            mclk<=~mclk;
            if(!mclk) begin
                divider<=divider+1'b1;
                // Falling edge of the MCLK/4 serial clock.
                if(divider==3) begin
                    serial_count<=serial_count+1'b1;
                    dac<=0;
                    // I2S MSB is one serial bit after the LRCK transition.
                    if(serial_count==0) begin
                        lrck<=0; frame_samples<=sample_pair;
                    end else if(serial_count<=16) dac<=frame_samples[32-serial_count];
                    else if(serial_count==32) lrck<=1;
                    else if(serial_count<=48 && serial_count>32) dac<=frame_samples[48-serial_count];
                end
            end
        end else accum<=next_accum[20:0];
        if(reset_bridge) begin
            req_meta<=0;req_sync<=0;ack<=0;sample_pair<=0;
            accum<=0;mclk<=0;divider<=0;serial_count<=0;
            frame_samples<=0;lrck<=0;dac<=0;
        end
    end
endmodule
`default_nettype wire

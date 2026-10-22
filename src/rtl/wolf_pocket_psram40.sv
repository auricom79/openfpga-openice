// SPDX-License-Identifier: MIT
// Original sequencer for AS1C8M16PL-70BIN with dedicated I/O capture/enable FFs.
// Datasheet: Alliance rev 1.0 August 2018, figures 9/18/28/33.
// System clock 80 MHz; fixed-phase external clock 40 MHz. No copied PSX RTL.
// Both clocks run continuously after initialization; BCR writes require CLK=0.
// Requests must stay inside an aligned 32-word block and exclude the last
// address of every die (the caller retains those four words in registers).
// BCR: synchronous, fixed latency code 3, 32-word wrapped bursts, half drive.
// Limiting requests to the current 32-word block avoids every row crossing.
`timescale 1ns/1ps
module wolf_pocket_psram40 #(
    parameter integer POWER_CYCLES=12000
)(
    input wire clk, reset,
    input wire req, chip, writing,
    input wire [22:0] address,
    input wire [5:0] length,
    input wire [15:0] wdata,
    input wire [1:0] wbe,
    output wire ready,
    output reg done=0, rvalid=0,
    output reg [15:0] rdata=0,
    output reg [4:0] windex=0,
    output reg [3:0] configured=0,
    output wire [21:16] cram0_a,cram1_a,
    inout wire [15:0] cram0_dq,cram1_dq,
    input wire cram0_wait,cram1_wait,
    output wire cram0_clk,cram0_adv_n,cram0_cre,cram0_ce0_n,cram0_ce1_n,
    output wire cram0_oe_n,cram0_we_n,cram0_ub_n,cram0_lb_n,
    output wire cram1_clk,cram1_adv_n,cram1_cre,cram1_ce0_n,cram1_ce1_n,
    output wire cram1_oe_n,cram1_we_n,cram1_ub_n,cram1_lb_n
);
    localparam [15:0] BCR=16'h5d14;
    localparam POWER=0, CRE=1, CFG=2, CFG_HOLD=3, START=4, RUN=5, GAP=6, IDLE=7, READ_END=8;
    reg [3:0] state=POWER;
    reg [13:0] count=POWER_CYCLES;
    reg [7:0] step=0;
    reg [1:0] die=0;
    reg init_mode=1, config_gap=0, restart=0;
    reg wr=0;
    reg [21:0] addr=0;
    reg [5:0] words=1;
    reg [5:0] word_no=0;
    reg write_end=0; // next falling edge terminates the just-committed word
    reg [21:16] a=0;
    reg [15:0] dq_out=0;
    reg dq_drive=0;
    reg adv=1, cre=0, ce=1, oe=1, we=1;
    reg phase40=0, clock_enable=0;
    (* preserve *) reg pin_clk0=0,pin_clk1=0;
    // A single free-running divider fixes the phase. Both output clocks are
    // registers; there is no combinational clock gate on either physical pin.
    always @(posedge clk)begin
        phase40<=~phase40;
        pin_clk0<=phase40 && clock_enable;
        pin_clk1<=phase40 && clock_enable;
    end
    reg [1:0] be=2'b11;
    // Decode selection before the pad registers, so CE and DQ-enable can
    // occupy dedicated IOFFs. Die changes only while both outputs are idle.
    reg [3:0] ce_n=4'b1111;
    reg [1:0] dq_enable=2'b00;
    // Capture the two packages independently at the original rising phase.
    // The package mux occurs one SYS cycle later, away from external timing.
    (* preserve *) reg [15:0] dq0_capture=0,dq1_capture=0;
    reg capture_pending=0,capture_chip=0;
    always @(posedge clk) if(phase40) begin
        dq0_capture<=cram0_dq;
        dq1_capture<=cram1_dq;
    end
    assign ready=(state==IDLE) && !reset && !restart;
    assign cram0_a=a; assign cram1_a=a;
    assign cram0_dq=dq_enable[0]?dq_out:16'hzzzz;
    assign cram1_dq=dq_enable[1]?dq_out:16'hzzzz;
    assign cram0_clk=pin_clk0;
    assign cram1_clk=pin_clk1;
    assign cram0_ce0_n=ce_n[0];
    assign cram0_ce1_n=ce_n[1];
    assign cram1_ce0_n=ce_n[2];
    assign cram1_ce1_n=ce_n[3];
    assign cram0_adv_n=adv; assign cram1_adv_n=adv;
    assign cram0_cre=cre; assign cram1_cre=cre;
    assign cram0_oe_n=oe; assign cram1_oe_n=oe;
    assign cram0_we_n=we; assign cram1_we_n=we;
    assign cram0_lb_n=be[0]; assign cram1_lb_n=be[0];
    assign cram0_ub_n=be[1]; assign cram1_ub_n=be[1];

    always @(posedge clk) begin
        done<=0; rvalid<=capture_pending; capture_pending<=0;
        if(capture_pending) rdata<=capture_chip?dq1_capture:dq0_capture;
        // A warm power-reset request drains the physical operation first.
        // Game reset must never reset this controller or the ROM loader.
        if(reset) restart<=1;
        case(state)
            POWER: begin
                ce<=1; ce_n<=4'b1111; clock_enable<=0; adv<=1; cre<=0; oe<=1; we<=1; dq_drive<=0; dq_enable<=2'b00; be<=3;
                configured<=0; init_mode<=1; die<=0;
                if(reset) count<=POWER_CYCLES;
                else if(count!=0) count<=count-1'b1;
                else begin restart<=0; count<=2; cre<=1; state<=CRE; end
            end
            CRE: if(count!=0) count<=count-1'b1; else begin
                // Place config address/ADV before WE falls (tAS), including
                // independent pad delays. CE remains deselected this cycle.
                a<=6'b001000; dq_out<=BCR; dq_drive<=1;
                dq_enable<=die[1]?2'b10:2'b01; adv<=0;
                state<=CFG;
            end
            CFG: begin
                a<=6'b001000; dq_out<=BCR; dq_drive<=1; dq_enable<=die[1]?2'b10:2'b01;
                ce<=0; ce_n<=~(4'b0001<<die); adv<=0; we<=0; cre<=1; oe<=1; be<=3;
                count<=0; state<=CFG_HOLD;
            end
            CFG_HOLD: begin
                count<=count+1'b1;
                if(count==1) adv<=1;
                if(count==6) begin
                    // BCR latches at the first rising CE/WE edge. Keep its
                    // address on DQ for another SYS cycle to cover pad skew.
                    ce<=1; ce_n<=4'b1111; we<=1;
                    configured[die]<=1;
                    config_gap<=1; count<=2; state<=GAP;
                end
            end
            IDLE: begin
                if(reset||restart) begin count<=POWER_CYCLES; state<=POWER; end
                else if(req) begin
                    die<={chip,address[22]}; addr<=address[21:0]; wr<=writing;
                    words<=length; init_mode<=0; state<=START;
`ifndef SYNTHESIS
                    if(length==0||length>32||({1'b0,address[4:0]}+length)>32)
                        $fatal(1,"invalid physical burst length/address");
                    if(({1'b0,address[21:0]}+length)>23'h3fffff)
                        $fatal(1,"physical access to shadow configuration word");
`endif
                end
            end
            START: if(!phase40) begin
                clock_enable<=1;
                a<=addr[21:16]; dq_out<=addr[15:0]; dq_drive<=1; dq_enable<=die[1]?2'b10:2'b01;
                ce<=0; ce_n<=~(4'b0001<<die); adv<=0; cre<=0; oe<=1; we<=!wr;
                be<=wr?2'b11:2'b00;
                step<=1; word_no<=0; windex<=0; write_end<=0; state<=RUN;
            end
            RUN: begin
                step<=step+1'b1;
                if(step==2) begin adv<=1; we<=1; end
                if(!wr) begin
                    // Retain address for a full SYS after ADV rises at step2
                    // (tAVH), then release before external OE falls at step4.
                    // READ has no device input-data sample on step3.
                    if(step==3) begin dq_drive<=0; dq_enable<=2'b00; end
                    if(step==4) oe<=0;
                    // D0 is produced after memory edge #3 after address;
                    // capture it immediately before edge #4 reaches the chip.
                    if(step>=9 && step[0]) begin
                        if(!init_mode) begin capture_pending<=1; capture_chip<=die[1]; end
                        word_no<=word_no+1'b1;
                        if(word_no==words-1'b1) begin
                            // Capture before this rising clock reaches the chip.
                            // End CE at the following falling edge, after hold.
                            state<=READ_END;
                        end
                    end
                end else begin
                    // All write data and masks change on memory falling edges.
                    if(step>=8 && !step[0]) begin
                        if(write_end) begin
                            ce<=1; ce_n<=4'b1111; dq_drive<=0; dq_enable<=2'b00; be<=3;
                            config_gap<=0; count<=2; state<=GAP;
                        end else begin dq_out<=wdata; be<=~wbe; end
                    end
                    if(step>=9 && step[0]) begin
                        word_no<=word_no+1'b1; windex<=windex+1'b1;
                        write_end<=(word_no==words-1'b1);
                    end
                end
            end
            READ_END: begin
                ce<=1; ce_n<=4'b1111;oe<=1;be<=3;
                if(init_mode)clock_enable<=0;
                config_gap<=0;count<=2;state<=GAP;
            end
            GAP: if(count!=0) begin
                count<=count-1'b1;
                if(config_gap && count==2) begin dq_drive<=0; dq_enable<=2'b00; end
            end else begin
                cre<=0;
                if(reset||restart) begin count<=POWER_CYCLES; state<=POWER; end
                else if(init_mode) begin
                    if(config_gap) begin addr<=0; wr<=0; words<=1; state<=START; end
                    else if(die!=3) begin die<=die+1'b1; count<=2; cre<=1; state<=CRE; end
                    else begin clock_enable<=1;state<=IDLE;end
                end else begin done<=1; state<=IDLE; end
            end
            default: begin ce<=1; ce_n<=4'b1111; state<=POWER; count<=POWER_CYCLES; end
        endcase
    end
endmodule

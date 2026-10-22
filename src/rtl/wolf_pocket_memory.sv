// SPDX-License-Identifier: MIT
// Private burst adaptation of wolf_pocket_memory's MIT address map/protocol.
// Read/write bursts become <=32-word physical runs, using a small write buffer.
`timescale 1ns/1ps
module wolf_pocket_memory(
    input wire clk,reset,
    input wire [28:0] ddram_addr,
    input wire [7:0] ddram_burstcnt,
    input wire ddram_rd,ddram_we,
    input wire [63:0] ddram_din,
    input wire [7:0] ddram_be,
    output wire ddram_busy,
    output reg [63:0] ddram_dout=0,
    output reg ddram_dout_ready=0,fault=0,
    output wire mem_req,
    output reg mem_chip,
    output wire mem_writing,
    output reg [22:0] mem_address,
    output reg [5:0] mem_length,
    output wire [15:0] mem_wdata,
    output wire [1:0] mem_be,
    input wire mem_ready,mem_done,mem_rvalid,
    input wire [15:0] mem_rdata,
    input wire [4:0] mem_windex
);
    localparam IDLE=0,PREP=1,WAIT_DONE=2,WRITE_NEXT=3,FAILED=4,COLLECT=5;
    reg [2:0] state=IDLE;
    reg writing=0;
    reg [30:0] ptr=0;
    reg [9:0] read_left=0;
    reg [7:0] beat_left=0;
    reg [5:0] write_left=0;
    reg [3:0] batch_beats=0,collected=0;
    reg [5:0] write_cursor=0;
    reg [63:0] write_buffer[0:7];
    reg [7:0] mask_buffer[0:7];
    wire [3:0] until_boundary=4'd8-{1'b0,ptr[4:2]};
    wire [3:0] next_batch=beat_left<{4'd0,until_boundary}?beat_left[3:0]:until_boundary;
    reg [63:0] assembly=0;
    
    reg [5:0] active_len=0;
    reg mapped,zero_fill;
    reg [15:0] shadows[0:3];
    wire shadow_access=&mem_address[21:0];
    wire [1:0] shadow_index={mem_chip,mem_address[22]};
    wire [28:0] beat_addr=ptr[30:2];
    // A buffered batch ends within its current32-word block. Its sole
    // physical write run begins at cursor0; only a final reserved shadow
    // word can remain afterwards. The next batch resets cursor to0. Thus
    // physical sampling uses mem_windex directly (unused data is don't-care).
    wire [4:0] write_lane=mem_windex;
    wire [63:0] selected_data=write_buffer[write_lane[4:2]];
    wire [7:0] selected_mask=mask_buffer[write_lane[4:2]];
    wire [63:0] shadow_data=write_buffer[write_cursor[4:2]];
    wire [7:0] shadow_mask=mask_buffer[write_cursor[4:2]];
    assign mem_wdata=selected_data[write_lane[1:0]*16+:16];
    assign mem_be=selected_mask[write_lane[1:0]*2+:2];
    assign mem_writing=writing;
    assign mem_req=!reset && state==PREP && mapped && !zero_fill && !shadow_access &&
                   (writing ? write_left!=0 : read_left!=0);
    assign ddram_busy=reset || (state!=IDLE && state!=WRITE_NEXT && state!=COLLECT) ||
                      (state==IDLE && !mem_ready);
    wire [5:0] normal_row_words = 6'd32 - {1'b0, mem_address[4:0]};
    (* keep *) wire request_shorter_than_row = writing
        ? (write_left < normal_row_words)
        : (read_left < {4'd0, normal_row_words});
    always @* begin
        mapped=1;zero_fill=0;mem_chip=0;mem_address=0;
        if(beat_addr>=29'h6800000 && beat_addr<29'h6a00000)
            mem_address={beat_addr[20:0],ptr[1:0]};
        else if(beat_addr>=29'h6a00000 && beat_addr<29'h6c00000) begin
            zero_fill=!writing; mapped=!writing;
        end else if(beat_addr>=29'h6400000 && beat_addr<29'h6420000) begin
            mem_chip=1;mem_address={4'd0,beat_addr[16:0],ptr[1:0]};
        end else if(beat_addr>=29'h6c00000 && beat_addr<29'h6c80000) begin
            mem_chip=1;mem_address=23'h200000+{2'd0,beat_addr[18:0],ptr[1:0]};
        end else mapped=0;
        // A request shorter than the ordinary row remainder is already at
        // least one word short of its end, so it cannot touch the reserved
        // configuration word. Compute this decision without the high-address
        // decode; the final mux alone selects the reserved-row cap.
        if (request_shorter_than_row)
            mem_length = writing ? write_left : read_left[5:0];
        else if (mem_address[21:5] == 17'h1ffff)
            mem_length = {1'b0, ~mem_address[4:0]};
        else
            mem_length = normal_row_words;
    end
    task receive(input [15:0] value);
        begin
            assembly[ptr[1:0]*16+:16]<=value;
            if(ptr[1:0]==3) begin
                ddram_dout<={value,assembly[47:0]}; ddram_dout_ready<=1;
            end
            ptr<=ptr+1'b1;read_left<=read_left-1'b1;
        end
    endtask
    always @(posedge clk) begin
        ddram_dout_ready<=0;
        if(reset) begin
            state<=IDLE;writing<=0;ptr<=0;read_left<=0;beat_left<=0;
            write_left<=0;write_cursor<=0;batch_beats<=0;collected<=0;fault<=0;ddram_dout<=0;assembly<=0;
        end else case(state)
            IDLE: if(!ddram_busy && (ddram_rd||ddram_we)) begin
                if(ddram_rd&&ddram_we) begin fault<=1;state<=FAILED;end
                else begin
                    ptr<={ddram_addr,2'b00};writing<=ddram_we;
                    beat_left<=ddram_burstcnt==0?8'd1:ddram_burstcnt;
                    read_left<=ddram_burstcnt==0?10'd4:{ddram_burstcnt,2'b00};
                    write_buffer[0]<=ddram_din;mask_buffer[0]<=ddram_be;
                    collected<=1;write_cursor<=0;
                    // Plan uses the incoming address, before ptr is latched.
                    if(ddram_burstcnt==0) begin batch_beats<=1;write_left<=4;state<=PREP;end
                    else if(ddram_burstcnt < (8-{5'd0,ddram_addr[2:0]})) begin
                        batch_beats<=ddram_burstcnt[3:0];write_left<={ddram_burstcnt[3:0],2'b00};
                        state<=ddram_we&&ddram_burstcnt>1?COLLECT:PREP;
                    end else begin
                        batch_beats<=4'd8-{1'b0,ddram_addr[2:0]};
                        write_left<={(4'd8-{1'b0,ddram_addr[2:0]}),2'b00};
                        state<=ddram_we&&ddram_addr[2:0]!=7?COLLECT:PREP;
                    end
                end
            end
            PREP: begin
                if(writing && write_left==0) begin
                    if(beat_left=={4'd0,batch_beats})state<=IDLE;
                    else begin beat_left<=beat_left-{4'd0,batch_beats};state<=WRITE_NEXT;end
                end else if(!writing && read_left==0)state<=IDLE;
                else if(!mapped)begin fault<=1;state<=FAILED;end
                else if(zero_fill||shadow_access) begin
                    if(writing) begin
                        if(shadow_mask[write_cursor[1:0]*2]) shadows[shadow_index][7:0]<=shadow_data[write_cursor[1:0]*16+:8];
                        if(shadow_mask[write_cursor[1:0]*2+1]) shadows[shadow_index][15:8]<=shadow_data[write_cursor[1:0]*16+8+:8];
                        ptr<=ptr+1'b1;write_left<=write_left-1'b1;write_cursor<=write_cursor+1'b1;
                    end else receive(zero_fill?16'd0:shadows[shadow_index]);
                end else if(mem_ready) begin
                    active_len<=mem_length;state<=WAIT_DONE;
                end
            end
            WAIT_DONE: begin
                if(mem_rvalid&&!writing)receive(mem_rdata);
                if(mem_done) begin
                    if(writing) begin ptr<=ptr+active_len;write_left<=write_left-active_len;write_cursor<=write_cursor+active_len;end
                    state<=PREP;
                end
            end
            WRITE_NEXT: if(ddram_we)begin
                write_buffer[0]<=ddram_din;mask_buffer[0]<=ddram_be;
                collected<=1;write_cursor<=0;batch_beats<=next_batch;write_left<={next_batch,2'b00};
                state<=next_batch>1?COLLECT:PREP;
            end
            COLLECT: if(ddram_we)begin
                write_buffer[collected[2:0]]<=ddram_din;mask_buffer[collected[2:0]]<=ddram_be;
                collected<=collected+1'b1;
                if(collected+1'b1==batch_beats)state<=PREP;
            end
            default:state<=FAILED;
        endcase
    end
endmodule

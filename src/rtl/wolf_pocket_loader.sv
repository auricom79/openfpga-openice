// SPDX-License-Identifier: MIT
// Pull deferred APF slots in bounded chunks. The bridge has no wait signal.
// A chunk is fully received before the memory clock reads it; the next request
// waits for all physical writes to drain. The RAM and metadata remain stable
// throughout the toggle handshake, including arbitrarily long memory stalls.
`default_nettype none
module wolf_pocket_loader #(
    parameter integer CHUNK_BYTES=4096,
    parameter integer PROGRAM_BYTES=1048576,
    parameter integer GRAPHICS_BYTES=16777216,
    parameter integer SOUND_BYTES=4194304
)(
    input wire clk_bridge, reset_bridge, clk_mem, reset_mem,
    input wire start,
    input wire bridge_wr,
    input wire [31:0] bridge_addr, bridge_wr_data,
    output reg target_read=0,
    output wire [15:0] target_id,
    output wire [31:0] target_offset, target_address, target_length,
    input wire target_ack, target_done,
    input wire [2:0] target_error,
    output reg done=0, fault=0,
    output reg [6:0] progress=0, progress_gray=0,
    output wire load_active, load_valid,
    output reg [1:0] load_index=0,
    output reg [24:0] load_addr=0,
    output wire [7:0] load_data,
    input wire load_ready, writes_idle
);
    localparam integer WORDS=CHUNK_BYTES/4;
    localparam integer AW=$clog2(WORDS);
    localparam integer TOTAL_BYTES=PROGRAM_BYTES+GRAPHICS_BYTES+SOUND_BYTES;
    localparam [3:0] WAIT_START=0, ISSUE=1, ARM=2, RECEIVE=3,
                     DRAIN=4, ADVANCE=5, FINISHED=6, FAILED=7, PROGRESS=8;
    reg [3:0] state=WAIT_START;
    reg [1:0] slot=0;
    reg [31:0] offset=0, received=0;
    reg [31:0] progress_remainder=0;
    reg final_chunk=0;
    wire [6:0] next_progress=progress+7'd1;
    wire [31:0] slot_size=slot==0 ? PROGRAM_BYTES :
                                 slot==1 ? GRAPHICS_BYTES : SOUND_BYTES;
    (* ramstyle="M10K, no_rw_check" *) reg [31:0] buffer [0:WORDS-1];
    reg prev_wr=0, request_toggle=0;
    reg ack_toggle=0;
    (* async_reg="true" *) reg ack_meta=0, ack_sync=0;
    wire payload_write=bridge_wr && !prev_wr && bridge_addr[31:28]==4'h1;
    assign target_id={14'd0,slot};
    assign target_offset=offset;
    assign target_address=32'h10000000;
    assign target_length=CHUNK_BYTES;

    always @(posedge clk_bridge) begin
        ack_meta<=ack_toggle;
        ack_sync<=ack_meta;
        prev_wr<=bridge_wr;
        target_read<=0;
        if(reset_bridge) begin
            state<=WAIT_START; slot<=0; offset<=0; received<=0;
            done<=0; fault<=0; request_toggle<=0; prev_wr<=0;
            ack_meta<=0; ack_sync<=0;
            progress<=0; progress_gray<=0; progress_remainder<=0; final_chunk<=0;
        end else begin
            case(state)
                WAIT_START: if(start) state<=ISSUE;
                ISSUE: begin
                    received<=0; target_read<=1; state<=ARM;
                end
                // done remains high after a previous command. Wait for the
                // command handler to clear it before accepting this result.
                ARM: if(!target_done || target_ack) state<=RECEIVE;
                RECEIVE: if(target_done) begin
                    if(target_error!=0 || received!=CHUNK_BYTES) begin
                        fault<=1; state<=FAILED;
                    end else begin
                        request_toggle<=~request_toggle; state<=DRAIN;
                    end
                end
                DRAIN: if(ack_sync==request_toggle) state<=ADVANCE;
                ADVANCE: begin
                    // Count only chunks acknowledged after physical memory
                    // writes have drained. Carry the fractional percentage
                    // instead of inferring a hardware divider/multiplier.
                    progress_remainder<=progress_remainder+CHUNK_BYTES*100;
                    state<=PROGRESS;
                    if(offset+CHUNK_BYTES==slot_size) begin
                        offset<=0;
                        if(slot==2) final_chunk<=1;
                        else slot<=slot+1'b1;
                    end else offset<=offset+CHUNK_BYTES;
                end
                PROGRESS: begin
                    if(progress_remainder>=TOTAL_BYTES) begin
                        progress_remainder<=progress_remainder-TOTAL_BYTES;
                        progress<=next_progress;
                        // Registered adjacent Gray states permit coherent
                        // observation from the slower display clock domain.
                        progress_gray<=next_progress^(next_progress>>1);
                    end else if(final_chunk) begin
                        done<=1; state<=FINISHED;
                    end else state<=ISSUE;
                end
                default: ;
            endcase
            if(payload_write) begin
                if((state!=ARM && state!=RECEIVE) ||
                   bridge_addr!=32'h10000000+received || received>=CHUNK_BYTES) begin
                    fault<=1; done<=0; state<=FAILED;
                end else begin
                    // Big-endian APF: first byte is bits 31:24.
                    buffer[received[AW+1:2]]<=bridge_wr_data;
                    received<=received+4;
                end
            end
        end
    end

    (* async_reg="true" *) reg req_meta=0, req_sync=0, done_meta=0, done_sync=0;
    localparam [2:0] M_IDLE=0, M_FETCH=1, M_BYTE=2, M_DRAIN=3;
    reg [2:0] mem_state=M_IDLE;
    reg [AW-1:0] word_index=0;
    reg [1:0] lane=0;
    reg [31:0] read_word=0;
    // Separate clocked read port permits inference of true dual-port block RAM.
    always @(posedge clk_mem) read_word<=buffer[word_index];
    assign load_active=!done_sync;
    assign load_valid=mem_state==M_BYTE && !reset_mem;
    assign load_data=read_word[31-8*lane -:8];
    always @(posedge clk_mem) begin
        req_meta<=request_toggle; req_sync<=req_meta;
        done_meta<=done; done_sync<=done_meta;
        if(reset_mem) begin
            req_meta<=0; req_sync<=0; done_meta<=0; done_sync<=0;
            ack_toggle<=0; mem_state<=M_IDLE; word_index<=0; lane<=0;
            load_index<=0; load_addr<=0;
        end else case(mem_state)
            M_IDLE: if(req_sync!=ack_toggle) begin
                // Bundled data is stable before the two-flop request arrives
                // and remains stable until the returned acknowledgement.
                load_index<=slot; load_addr<=offset[24:0];
                word_index<=0; lane<=0; mem_state<=M_FETCH;
            end
            M_FETCH: mem_state<=M_BYTE;
            M_BYTE: if(load_ready) begin
                load_addr<=load_addr+1'b1;
                if(lane==3) begin
                    lane<=0;
                    if(word_index==AW'(WORDS-1)) mem_state<=M_DRAIN;
                    else begin word_index<=word_index+1'b1; mem_state<=M_FETCH; end
                end else lane<=lane+1'b1;
            end
            M_DRAIN: if(writes_idle) begin ack_toggle<=req_sync; mem_state<=M_IDLE; end
            default: mem_state<=M_IDLE;
        endcase
    end
    initial begin
        if(CHUNK_BYTES<8 || (CHUNK_BYTES & (CHUNK_BYTES-1))!=0 ||
           PROGRAM_BYTES%CHUNK_BYTES!=0 || GRAPHICS_BYTES%CHUNK_BYTES!=0 || SOUND_BYTES%CHUNK_BYTES!=0)
            $error("Chunk must be a power of two >=8 dividing all three ROM sizes");
    end
endmodule
`default_nettype wire

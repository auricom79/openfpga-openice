`timescale 1ns/1ps
// Exercise production-sized chunks and, optionally, all 21 MiB with synthetic data.
module tb_loader_4k;
    localparam integer CHUNK=4096;
`ifdef FULL_ASSETS
    localparam integer PROGRAM=1048576, GRAPHICS=16777216, SOUND=4194304;
`else
    localparam integer PROGRAM=CHUNK*2, GRAPHICS=CHUNK*3, SOUND=CHUNK*2;
`endif
    localparam integer TOTAL=PROGRAM+GRAPHICS+SOUND;
    reg cb=0,cm=0,rb=1,rm=1,start=0,wr=0,ack=0,tdone=0;
    always #6.734 cb=~cb;
    always #6.25 cm=~cm;
    reg [31:0] addr=0,data=0;
    reg [2:0] err=0;
    wire request,done,fault,active,valid;
    wire [15:0] id;
    wire [31:0] offset,address,length;
    wire [1:0] index;
    wire [24:0] la;
    wire [7:0] ld;
    wire [6:0] progress,progress_gray;
    reg ready=0,idle=0;
    integer accepted=0,requests=0,drain_delay=0,cycles=0,drained_bytes=0;
    integer previous_progress=0;
    integer expected_slot=0,expected_addr=0;
    reg [31:0] random_state=32'h64259137;
    reg [1:0] held_index;
    reg [24:0] held_addr;
    reg [7:0] held_data;
    reg was_stalled=0;
    wolf_pocket_loader #(.CHUNK_BYTES(CHUNK),.PROGRAM_BYTES(PROGRAM),
        .GRAPHICS_BYTES(GRAPHICS),.SOUND_BYTES(SOUND)) dut (
        .clk_bridge(cb),.reset_bridge(rb),.clk_mem(cm),.reset_mem(rm),.start(start),
        .bridge_wr(wr),.bridge_addr(addr),.bridge_wr_data(data),.target_read(request),
        .target_id(id),.target_offset(offset),.target_address(address),.target_length(length),
        .target_ack(ack),.target_done(tdone),.target_error(err),.done(done),.fault(fault),
        .load_active(active),.load_valid(valid),.load_index(index),.load_addr(la),
        .load_data(ld),.load_ready(ready),.writes_idle(idle),
        .progress(progress),.progress_gray(progress_gray));
    function automatic [7:0] pattern(input integer s,a);
        pattern=8'((s*83)^(a*17)^(a>>3)^(a>>13));
    endfunction
    always @(negedge cm) begin
        cycles++;
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        ready=!rm && random_state[2:0]!=0 && cycles%4096>=137;
        if(drain_delay>0) drain_delay--;
        idle=drain_delay==0;
        if(!rm && idle && accepted%CHUNK==0) drained_bytes=accepted;
    end
    always @(posedge cb) begin
        if(rb) previous_progress=0;
        else begin
            if(progress>drained_bytes*100/TOTAL || progress<previous_progress || progress>100)
                $fatal(1,"Progress lied: percent=%0d drained=%0d previous=%0d",progress,drained_bytes,previous_progress);
            if(progress_gray!=(progress^(progress>>1))) $fatal(1,"Wrong Gray code");
            previous_progress=progress;
        end
    end
    always @(posedge cm) begin
        if(rm) was_stalled=0;
        else begin
            if(was_stalled && (!valid || index!=held_index || la!=held_addr || ld!=held_data))
                $fatal(1,"Payload changed while stalled");
            was_stalled=valid && !ready;
            held_index=index;held_addr=la;held_data=ld;
        end
        if(valid && ready) begin
            if(!active || fault) $fatal(1,"Invalid engine load state");
            if(index!=expected_slot || la!=expected_addr || ld!=pattern(expected_slot,expected_addr))
                $fatal(1,"Byte mismatch got %d:%h=%h expected %d:%h=%h",index,la,ld,
                       expected_slot,expected_addr,pattern(expected_slot,expected_addr));
            accepted++; expected_addr++;
            if(expected_addr==(expected_slot==0 ? PROGRAM : expected_slot==1 ? GRAPHICS : SOUND)) begin
                expected_slot++;expected_addr=0;
            end
            drain_delay=91;
        end
        if(!rm && !active && (accepted!=TOTAL || !idle || !done))
            $fatal(1,"Engine released before complete final drain");
    end
    task automatic send_word(input integer pos,slot,off);
        @(negedge cb);wr=1;addr=32'h10000000+pos;
        data={pattern(slot,off+pos),pattern(slot,off+pos+1),
              pattern(slot,off+pos+2),pattern(slot,off+pos+3)};
        // Held strobes must not duplicate; both 1-cycle and longer writes occur.
        repeat(pos%64==0 ? 3 : 1) @(negedge cb);
        wr=0;
        repeat(pos%256==0 ? 7 : 1) @(negedge cb);
    endtask
    task automatic restart;
        @(negedge cb);rb=1;rm=1;start=0;wr=0;tdone=0;ack=0;err=0;
        repeat(9) @(negedge cb);
        accepted=0;requests=0;expected_slot=0;expected_addr=0;drain_delay=0;drained_bytes=0;
        rb=0;rm=0;
        repeat(8) @(negedge cb);
        if(request || done || fault || valid || !active) $fatal(1,"Loading before start");
        start=1;
        @(negedge cb);start=0;
    endtask
    initial begin
        restart();
        repeat(TOTAL/CHUNK) begin
            wait(request);
            if(accepted!=requests*CHUNK || !idle) $fatal(1,"Request before prior drain");
            if(progress!=accepted*100/TOTAL) $fatal(1,"Progress inaccurate at next request");
            if(address!=32'h10000000 || length!=CHUNK || id!=expected_slot || offset!=expected_addr)
                $fatal(1,"Wrong 4KiB request metadata");
            requests++;
            // The previous completion remains high until host accepts the new one.
            repeat(7) @(negedge cb);
            tdone=0;ack=1;
            for(integer p=0;p<CHUNK;p+=4) send_word(p,id,offset);
            @(negedge cb);tdone=1;ack=0;
            repeat(3) @(negedge cb);
        end
        wait(done);wait(!active);
        if(fault || accepted!=TOTAL || requests!=TOTAL/CHUNK || !idle || progress!=100) $fatal(1,"Final load mismatch");
        $display("PASS full transfer bytes=%0d chunks=%0d",accepted,requests);
        // A short transaction, including almost a full 4KiB, never leaks partial data.
        restart();wait(request);repeat(5) @(negedge cb);ack=1;
        for(integer p=0;p<CHUNK-4;p+=4) send_word(p,0,0);
        @(negedge cb);tdone=1;ack=0;
        wait(fault);repeat(10) @(negedge cb);
        if(done || !active || accepted!=0) $fatal(1,"Truncated transfer escaped");
        restart();wait(request);repeat(5) @(negedge cb);ack=1;
        @(negedge cb);tdone=1;err=2;ack=0;
        wait(fault);if(done || !active || accepted!=0) $fatal(1,"Host error escaped");
        restart();wait(request);repeat(5) @(negedge cb);ack=1;
        send_word(4,0,0);wait(fault);
        if(done || !active || accepted!=0) $fatal(1,"Out-of-order transfer escaped");
        // A reset during reception discards buffered partial bytes.
        restart();wait(request);repeat(5) @(negedge cb);ack=1;
        for(integer p=0;p<CHUNK/2;p+=4) send_word(p,0,0);
        restart();wait(request);
        if(offset!=0 || id!=0 || accepted!=0 || done || fault) $fatal(1,"Partial reset failed");
        $display("PASS loader4KiB: byte integrity, async clocks, mixed/held strobes, random/long stalls, physical drain, stale done, truncated/error/ordering/reset");
        $finish;
    end
    initial begin #10000000000;$fatal(1,"Loader4KiB timeout");end
endmodule

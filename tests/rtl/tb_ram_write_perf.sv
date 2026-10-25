// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
module ram_word_model #(parameter integer WORDS=128)(input logic clk,rst,
    input logic [24:0] addr,input logic [15:0] din,input logic [1:0] be,
    input logic rd,wr,output logic [15:0] dout,output logic ack,
    output integer reads=0,writes=0);
    logic [15:0] mem[0:WORDS-1];
    integer state=0,delay_left=0;
    logic [24:0] qa;
    logic [15:0] qd;
    logic [1:0] qb;
    logic qw;
    initial for(integer i=0;i<WORDS;i++) mem[i]=16'(i*131+16'h55aa);
    always @(posedge clk) begin
        if(rst) begin state<=0;ack<=0;dout<=0;end
        else begin
            ack<=0;
            case(state)
            0: if(rd||wr) begin
                if(rd&&wr) $fatal(1,"Read and write overlap");
                if(addr>=WORDS) $fatal(1,"Out-of-bounds physical access");
                qa<=addr;qd<=din;qb<=be;qw<=wr;
                delay_left<=1+((addr+reads+writes)%17);state<=1;
            end
            1: if(delay_left>0) delay_left<=delay_left-1;
               else begin
                   if(qw) begin
                       if(qb[0]) mem[qa][7:0]<=qd[7:0];
                       if(qb[1]) mem[qa][15:8]<=qd[15:8];
                       writes<=writes+1;
                   end else begin dout<=mem[qa];reads<=reads+1;end
                   ack<=1;state<=2;
               end
            2: if(!rd&&!wr) state<=0;
            default:$fatal(1,"Bad model state");
            endcase
        end
    end
endmodule

module tb_ram_write_perf;
    logic clk=0,rst=1,req=0,we=0;
    always #5 clk=~clk;
    logic [27:0] widx=0;
    logic [3:0] boff=0;
    logic [5:0] sz=16;
    logic [31:0] wd=0,rdata[2];
    wire done[2],active[2],rd[2],wr[2],ack[2];
    wire [24:0] addr[2];
    wire [15:0] din[2],dout[2];
    wire [1:0] be[2];
    wire integer reads[2],writes[2];
    integer elapsed[2],total[2],aligned_total[2],aligned_n=0,cases_run=0;
    logic [15:0] gold[0:127];
    integer memory_checks=0,reset_cases=0,normal_reads[2],normal_writes[2];
    for(genvar g=0;g<2;g++)begin:impl
        ram_sdram #(.RAMW(128),.FAST_FULL_WRITES(g==1)) dut(
            .clk,.rst,.req,.we,.widx,.boff,.sz,.wd,.rdata(rdata[g]),.done(done[g]),.active(active[g]),
            .sd_addr(addr[g]),.sd_din(din[g]),.sd_be(be[g]),.sd_rd(rd[g]),.sd_wr(wr[g]),
            .sd_dout(dout[g]),.sd_ack(ack[g]));
        ram_word_model model(.clk,.rst,.addr(addr[g]),.din(din[g]),.be(be[g]),
            .rd(rd[g]),.wr(wr[g]),.dout(dout[g]),.ack(ack[g]),.reads(reads[g]),.writes(writes[g]));
    end
    task automatic transaction(input bit write_op,input integer wi,bo,width,input logic [31:0] data);
        logic seen[2];
        logic [31:0] expected;
        integer tick,absolute,word_index,bit_index;
        integer reads_before[2],writes_before[2],touched_valid,last_bit,touched;
        for(integer i=0;i<2;i++)begin reads_before[i]=reads[i];writes_before[i]=writes[i];end
        last_bit=(bo+width-1)&63;
        touched=last_bit<16?1:last_bit<32?2:3;
        touched_valid=0;
        for(integer j=0;j<touched;j++)if(wi+j<128)touched_valid++;
        expected=0;
        for(integer bitno=0;bitno<width;bitno++)begin
            absolute=wi*16+bo+bitno;word_index=absolute/16;bit_index=absolute%16;
            if(word_index<128)expected[bitno]=gold[word_index][bit_index];
        end
        if(write_op)for(integer bitno=0;bitno<width;bitno++)begin
            absolute=wi*16+bo+bitno;word_index=absolute/16;bit_index=absolute%16;
            if(word_index<128)gold[word_index][bit_index]=data[bitno];
        end
        @(negedge clk);we=write_op;widx=28'(wi);boff=4'(bo);sz=6'(width);wd=data;req=1;
        @(negedge clk);req=0;seen[0]=0;seen[1]=0;tick=0;
        while(!seen[0]||!seen[1])begin
            @(negedge clk);tick++;
            if(tick>500)$fatal(1,"Transaction timeout");
            for(integer i=0;i<2;i++)if(done[i])begin
                if(seen[i])$fatal(1,"Duplicated completion");
                if(!write_op && rdata[i]!==expected)$fatal(1,"Read mismatch case%0d impl%0d: %h vs%h",cases_run,i,rdata[i],expected);
                if(writes[i]-writes_before[i] != (write_op?touched_valid:0))
                    $fatal(1,"Completion before all writes or extra writes impl%0d",i);
                if(reads[i]-reads_before[i] != ((i==1&&write_op&&bo==0&&(width==16||width==32))?0:touched_valid))
                    $fatal(1,"Unexpected physical read count impl%0d",i);
                // Check each implementation at its own done, not only after
                // the slower reference has also finished.
                for(integer wi2=0;wi2<128;wi2++)begin
                    if((i==0 ? impl[0].model.mem[wi2] : impl[1].model.mem[wi2])!==gold[wi2])
                        $fatal(1,"Early done or bad word impl%0d case%0d word%0d",i,cases_run,wi2);
                end
                seen[i]=1;elapsed[i]=tick;total[i]+=tick;
                if(write_op&&bo==0&&(width==16||width==32))aligned_total[i]+=tick;
            end
        end
        if(write_op&&bo==0&&(width==16||width==32))aligned_n++;
        for(integer wi2=0;wi2<128;wi2++)begin
            if(impl[0].model.mem[wi2]!==gold[wi2]||impl[1].model.mem[wi2]!==gold[wi2])
                $fatal(1,"Memory mismatch case%0d word%0d",cases_run,wi2);
            memory_checks++;
        end
        cases_run++;
    endtask
    task automatic interrupt_with_reset(input integer age,input bit write_op,input integer bo,width);
        logic [15:0] before0[128],before1[128];
        @(negedge clk);we=write_op;widx=16;boff=4'(bo);sz=6'(width);wd=32'hbad01234;req=1;
        @(negedge clk);req=0;
        repeat(age)@(negedge clk);
        for(integer i=0;i<128;i++)begin before0[i]=impl[0].model.mem[i];before1[i]=impl[1].model.mem[i];end
        rst=1;
        repeat(3)@(negedge clk);
        for(integer i=0;i<2;i++)if(done[i]||active[i]||rd[i]||wr[i])$fatal(1,"Reset did not clear control");
        rst=0;
        repeat(60)begin
            @(negedge clk);
            for(integer i=0;i<2;i++)if(done[i]||active[i]||rd[i]||wr[i])$fatal(1,"Stale activity after reset");
        end
        for(integer i=0;i<128;i++)begin
            if(impl[0].model.mem[i]!==before0[i]||impl[1].model.mem[i]!==before1[i])$fatal(1,"Memory changed after cancellation");
            // Reinitialize only the external test fixture after checking its
            // retained contents. No DUT register is forced or edited.
            gold[i]=16'(i*131+16'h55aa);
            impl[0].model.mem[i]=gold[i];impl[1].model.mem[i]=gold[i];
        end
        transaction(1,16,0,32,32'h5a17cafe);
        transaction(0,16,0,32,0);
        reset_cases++;
    endtask
    initial begin
        for(integer i=0;i<128;i++)gold[i]=16'(i*131+16'h55aa);
        total[0]=0;total[1]=0;aligned_total[0]=0;aligned_total[1]=0;
        repeat(4)@(negedge clk);rst=0;
        // Exhaust all field offsets/widths, include final valid words and OOB.
        for(integer width=0;width<=32;width++)for(integer bo=0;bo<16;bo++)begin
            transaction(1,(width*5+bo*13)%130,bo,width,32'hd3ad1234^(width*17+bo));
            transaction(0,(width*5+bo*13)%130,bo,width,0);
        end
        // Repeated aligned stores expose throughput on the intended fast path.
        for(integer i=0;i<1024;i++)begin
            transaction(1,i%130,0,(i%2)?16:32,32'hca1dbeef^i);
            transaction(0,i%130,0,(i%2)?16:32,0);
        end
        for(integer i=0;i<2;i++)begin normal_reads[i]=reads[i];normal_writes[i]=writes[i];end
        // All four accesses include reset before issue, during variable
        // memory latency, around completion, and after completion.
        for(integer age=0;age<45;age++)begin
            interrupt_with_reset(age,1,0,16);
            interrupt_with_reset(age,1,0,32);
            interrupt_with_reset(age,1,7,23);
            interrupt_with_reset(age,0,0,32);
        end
        if(normal_reads[1]>=normal_reads[0]||normal_writes[1]!=normal_writes[0]||aligned_total[1]>=aligned_total[0])
            $fatal(1,"No safe read/latency saving");
        $display("PASS RAM full-word bypass: %0d cases, %0d memory checks, %0d aligned writes, %0d reset windows",cases_run,memory_checks,aligned_n,reset_cases);
        $display("cycles total baseline=%0d candidate=%0d; aligned baseline=%0d candidate=%0d; ordinary reads=%0d/%0d writes=%0d/%0d",total[0],total[1],aligned_total[0],aligned_total[1],normal_reads[0],normal_reads[1],normal_writes[0],normal_writes[1]);
        $finish;
    end
endmodule

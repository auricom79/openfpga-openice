// SPDX-License-Identifier: MIT
// Synthetic graphics bytes only. Verifies stream bursts, every returned byte,
// resets/reloads, donor fallback parameters and both ends of the GFX aperture.
// The physical PSRAM integration comparison is a separate private experiment.
`timescale 1ns/1ps
module tb_gfx_stream_burst;
 parameter integer BURST=4, STREAM_HINT=1;
 localparam integer PHYSICAL=0;
 reg clk=0;always #6.25 clk=~clk;
 reg rst=1,sdram_por=1;
 reg force_adjacent=0;
 reg src_req=0,src_active=0,src_stream=0,cg_req=0,dl_wr=0;
 reg [31:0] src_addr=0;
 reg [25:0] cg_addr=0;
 reg [24:0] dl_addr=0;
 reg [7:0] dl_data=0;
 wire [7:0] src_data,cg_data;
 wire src_ack,cg_ack,dl_ack,dl_idle,dcs_safe;
 wire [25:0] dbg_wbeats;wire [15:0] dbg_srd,dbg_cgrd;
 wire [28:0] b_addr;
 wire [7:0] b_burstcnt,b_be;
 wire b_rd,b_we,b_busy,b_dout_ready;
 wire [63:0] b_din,b_dout;
 wolf_gfx_ddr_top #(.USE_STREAM_HINT(STREAM_HINT),.DIRECT_PREFETCH(1)
 , .STREAM_BURST_BEATS(BURST)
 ) dut(.*,.ddram_addr(b_addr),.ddram_burstcnt(b_burstcnt),.ddram_be(b_be),
   .ddram_rd(b_rd),.ddram_we(b_we),.ddram_busy(b_busy),.ddram_dout_ready(b_dout_ready),.ddram_din(b_din),.ddram_dout(b_dout));
 wire [28:0] a_addr;
 wire [7:0] a_burstcnt,a_be;
 wire a_rd,a_we,a_busy,a_dout_ready;
 wire [63:0] a_din,a_dout;
 reg a_request=0;reg [25:0] a_offset=0;reg [7:0] a_length=1;
 wire [63:0] a_result;wire a_valid,a_working;
 stv_vram_ddr_agent #(.VRAM_DDR_BASE(29'h6800000)) priority_agent(
   .clk(clk),.sdram_por(sdram_por),.tst_wr_req(1'b0),.tst_rd_req(a_request),
   .tst_addr(a_offset),.tst_wdata(64'd0),.tst_be(8'hff),.tst_burstcnt(a_length),
   .tst_rdata(a_result),.tst_rd_valid(a_valid),.tst_busy(a_working),
   .ddram_addr(a_addr),.ddram_burstcnt(a_burstcnt),.ddram_be(a_be),
   .ddram_rd(a_rd),.ddram_we(a_we),.ddram_busy(a_busy),.ddram_dout_ready(a_dout_ready),.ddram_din(a_din),.ddram_dout(a_dout));
 wire [28:0] ddram_addr;
 wire [7:0] ddram_burstcnt,ddram_be;
 wire ddram_rd,ddram_we,ddram_busy,ddram_dout_ready,fault;
 wire [63:0] ddram_din,ddram_dout;
 wolf_ddr3_arb arb(.*,.b_allow(1'b1));
 gfx_burst_memory_model mem(.*,.reset(sdram_por));
 byte unsigned updated[int unsigned];
 byte unsigned intended[int unsigned];
 function automatic logic[7:0] expected_byte(input int unsigned address);
   int unsigned a,h;
   a=address&32'h1ffffff;
   if(a>=32'h1000000)return 0;
   if(intended.exists(a))return intended[a];
   h=(a>>1)^32'h9e3779b9;
   h=(h^(h>>16))*32'h7feb352d;
   h=(h^(h>>15))*32'h846ca68b;
   h=h^(h>>16);
   return a[0]?h[15:8]:h[7:0];
 endfunction
 function automatic logic[7:0] bus_expected_byte(input int unsigned address);
   int unsigned a,h;
   a=address&32'h1ffffff;
   if(a>=32'h1000000)return 0;
   if(updated.exists(a))return updated[a];
   h=(a>>1)^32'h9e3779b9;
   h=(h^(h>>16))*32'h7feb352d;
   h=(h^(h>>15))*32'h846ca68b;
   h=h^(h>>16);
   return a[0]?h[15:8]:h[7:0];
 endfunction
 longint cycles=0,src_checked=0,cg_checked=0,priority_checked=0,bus_checked=0;
 longint read_commands=0,read_beats=0,write_commands=0;
 reg[63:0] trace_hash=64'hcbf29ce484222325;
 longint burst_hist[0:255];
 integer pending_beats=0;
 logic[28:0] expected_address=0;
 logic was_blocked=0;
 logic[28:0] blocked_addr=0;
 logic[7:0] blocked_len=0,blocked_be=0;
 logic blocked_rd=0,blocked_we=0;
 logic[63:0] blocked_din=0;
 bit expecting_fault=0;
 integer core_reset_drains=0, multi_reset_drains=0;
 integer interrupted_address=0;
 integer caught_tail=0,caught_early=0,consecutive_responses=0,hint_fell_in_burst=0;
 reg previous_response=0,previous_hint=0;
 reg[3:0] alignments=0;
 integer target_last_byte=0;
 always @(posedge clk) begin
   cycles<=cycles+1;
   if(sdram_por)begin pending_beats=0;was_blocked=0;end
   else begin
     if(dut.tst_rd_valid&&previous_response)consecutive_responses++;
     previous_response=dut.tst_rd_valid;
     if(dut.ost==9&&!src_stream&&previous_hint)hint_fell_in_burst++;
     previous_hint=src_stream;
     if(dut.ost==9&&dut.tst_rd_valid&&dut.src_pend&&dut.src_qaddr[24:3]==dut.pf_target&&dut.pf_burst_len>1)begin
       if(dut.pf_burst_left==1)caught_tail++;else caught_early++;
     end
     trace_hash={trace_hash[62:0],trace_hash[63]} ^
       {32'd0,src_ack,cg_ack,dl_ack,dl_idle,dcs_safe,ddram_rd,ddram_we,ddram_busy,24'd0};
     if(src_ack)trace_hash=trace_hash^{32'd0,src_addr}^{56'd0,src_data};
     if(cg_ack)trace_hash=trace_hash^{38'd0,cg_addr}^{56'd0,cg_data};
     if(ddram_rd||ddram_we)trace_hash=trace_hash^{27'd0,ddram_addr,ddram_burstcnt};
     if(was_blocked)begin
       if({ddram_addr,ddram_burstcnt,ddram_be,ddram_rd,ddram_we}!={blocked_addr,blocked_len,blocked_be,blocked_rd,blocked_we})
         $fatal(1,"Avalon command changed while waitrequest high");
       if(blocked_we && ddram_din!==blocked_din)$fatal(1,"Avalon write data changed while stalled");
     end
     was_blocked=(ddram_rd||ddram_we)&&ddram_busy;
     blocked_addr=ddram_addr;blocked_len=ddram_burstcnt;blocked_be=ddram_be;
     blocked_rd=ddram_rd;blocked_we=ddram_we;blocked_din=ddram_din;
     if(ddram_rd&&!ddram_busy)begin
       if(pending_beats!=0)$fatal(1,"new read accepted before prior burst drained");
       pending_beats=ddram_burstcnt;expected_address=ddram_addr;
       read_commands++;read_beats+=ddram_burstcnt;
       if(arb.gnt==2) begin
         alignments[b_addr[1:0]]=1;
         burst_hist[ddram_burstcnt]++;
         if(ddram_burstcnt>4)$fatal(1,"GFX burst larger than cache");
         if((BURST==1||STREAM_HINT==0)&&ddram_burstcnt!=1)$fatal(1,"fallback changed shape");
       end
       if(ddram_addr+ddram_burstcnt>29'h6c00000)$fatal(1,"GFX burst crossed into sound aperture");
     end
     if(ddram_we&&!ddram_busy)begin
       write_commands++;
       if(ddram_addr<29'h6a00000)
         for(int i=0;i<8;i++)if(ddram_be[i])updated[((ddram_addr-29'h6800000)<<3)+i]=ddram_din[i*8+:8];
     end
     if(ddram_dout_ready)begin
       if(pending_beats<=0)$fatal(1,"unexpected read response");
       for(int i=0;i<8;i++)
         if(ddram_dout[i*8+:8]!==bus_expected_byte(((expected_address-29'h6800000)<<3)+i))
           $fatal(1,"bus read mismatch addr=%h lane=%0d got=%h want=%h",expected_address,i,ddram_dout[i*8+:8],bus_expected_byte(((expected_address-29'h6800000)<<3)+i));
       expected_address++;pending_beats--;bus_checked++;
     end
     if(fault&&!expecting_fault)$fatal(1,"unexpected bridge fault");
   end
 end
 task automatic source_read(input int unsigned address,input integer gap=0);
   integer waited;
   @(negedge clk);src_addr=address;src_req=1;waited=0;
   while(!src_ack)begin @(negedge clk);waited++;if(waited>20000)$fatal(1,"source timeout %h ost=%0d",address,dut.ost);end
   if(src_data!==expected_byte(address))$fatal(1,"source mismatch %h got=%h want=%h ost=%0d",address,src_data,expected_byte(address),dut.ost);
   src_checked++;src_req=0;
   repeat(gap)@(negedge clk);
 endtask
 task automatic cpu_read(input int unsigned address);
   integer waited;
   @(negedge clk);cg_addr=26'(address);cg_req=1;waited=0;
   while(!cg_ack)begin @(negedge clk);waited++;if(waited>40000)$fatal(1,"CPU GFX timeout %h",address);end
   if(cg_data!==expected_byte(address))$fatal(1,"CPU mismatch %h got=%h want=%h",address,cg_data,expected_byte(address));
   cg_checked++;cg_req=0;
 endtask
 task automatic priority_read(input int unsigned address,input integer count);
   integer received,waited;
   @(negedge clk);a_offset=26'(address>>3);a_length=8'(count);a_request=1;
   @(negedge clk);a_request=0;received=0;waited=0;
   while(received<count)begin
     @(negedge clk);waited++;
     if(waited>20000)$fatal(1,"priority timeout");
     if(a_valid)begin
       for(int i=0;i<8;i++)if(a_result[i*8+:8]!==expected_byte(address+received*8+i))$fatal(1,"priority data mismatch");
       received++;priority_checked++;
     end
   end
 endtask
 task automatic byte_write(input int unsigned address,input byte unsigned data);
   integer waited;
   @(negedge clk);dl_addr=25'(address);dl_data=data;dl_wr=1;waited=0;
   while(!dl_ack)begin @(negedge clk);waited++;if(waited>20000)$fatal(1,"download timeout");end
   if(address<'h1000000)intended[address]=data;
   dl_wr=0;
 endtask
 task automatic drain;
   integer waited;
   waited=0;
   repeat(4)@(negedge clk);
   while(!dl_idle||ddram_busy||pending_beats!=0)begin @(negedge clk);waited++;if(waited>40000)$fatal(1,"drain timeout");end
 endtask
 task automatic run_linear(input string name,input integer base,input integer count,input integer gap,input bit active,input bit stream);
   longint start_cycles,start_cmd,start_beats;
   @(negedge clk);src_active=active;src_stream=stream;
   drain();start_cycles=cycles;start_cmd=read_commands;start_beats=read_beats;
   for(int i=0;i<count;i++)source_read((base+i)&'h1ffffff,gap);
   $display("METRIC,%s,physical=%0d,burst=%0d,bytes=%0d,cycles=%0d,commands=%0d,beats=%0d",name,PHYSICAL,BURST,count,cycles-start_cycles,read_commands-start_cmd,read_beats-start_beats);
   src_active=0;src_stream=0;drain();
 endtask
 initial begin
   for(int i=0;i<256;i++)burst_hist[i]=0;
   repeat(8)@(negedge clk);sdram_por=0;
   while(ddram_busy)@(negedge clk);
   repeat(5)@(negedge clk);rst=0;
   run_linear("dense_fast",'h10000,8192,0,1,1);
   run_linear("dense_paced",'h20000,8192,4,1,1);
   run_linear("active_nonstream",'h30000,4096,0,1,0);
   run_linear("inactive",'h40000,2048,0,0,0);
   run_linear("die_boundary",'h7fffc0,256,0,1,1);
   run_linear("zero_boundary",'hffffc0,256,0,1,1);
   run_linear("wrap_boundary",'h1ffffc0,256,0,1,1);
   // Concurrent independent CPU and priority requester, random sprite jumps.
   src_active=1;src_stream=1;
   fork
     begin
       for(int run=0;run<64;run++)begin
         for(int i=0;i<64;i++)source_read(((run*7919)%'hff0000)+i,run%3);
         repeat(run%11)@(negedge clk);
       end
       src_active=0;
     end
     begin for(int i=0;i<192;i++)cpu_read((i*104729+7919)%'h1000000);end
     begin for(int i=0;i<80;i++)begin priority_read('h100000+i*64,1+(i%8));repeat(i%17)@(negedge clk);end end
   join
   drain();
   // Hint changes and jumps while speculative reads finish independently.
   for(int i=0;i<2048;i++)begin
     src_active=(i%11)!=0;src_stream=(i%7)<4;
     source_read(i%5==0 ? ((i*65521)&'hffffff) : ((src_addr+1)&'h1ffffff),i%3);
     if(i%19==0)cpu_read((i*13007)&'hffffff);
   end
   src_active=0;src_stream=0;drain();
   // All download lanes, strided original chip interleave, cache invalidation.
   run_linear("prewrite_cache",'h50000,128,7,1,1);
   @(negedge clk);rst=1;
   for(int lane=0;lane<4;lane++)for(int i=0;i<32;i++)byte_write('h50000+i*4+lane,8'(i*19+lane*23));
   drain();
   // Timeout-split writes to the same beat exercise forwarding after RMW.
   byte_write('h60001,8'h35);drain();repeat(150)@(negedge clk);
   byte_write('h60005,8'hc2);drain();
   @(negedge clk);rst=0;
   run_linear("postwrite_cache",'h50000,128,0,1,1);
   for(int i=0;i<8;i++)begin source_read('h60000+i);cpu_read('h60000+i);end
   // Pause source indefinitely with active asserted: CPU must still progress.
   src_active=1;src_stream=1;
   source_read('h90123);
   repeat(100)@(negedge clk);
   cpu_read('h175891);src_active=0;drain();
   // Reset the consumer while a speculative transaction is still in flight.
   // Ownership must survive to the final beat, then future requests work.
   for(int reset_index=0;reset_index<8;reset_index++)begin
     src_active=1;src_stream=1;
     fork : warm_and_reset
       begin
         for(int i=0;i<2048;i++)source_read('ha0000+reset_index*4096+i,4);
       end
       begin
         integer opportunities;
         opportunities=0;
         while(opportunities<4)begin
           @(negedge clk);
           if(dut.ost==9 && dut.tst_busy)begin
             opportunities++;
             while(dut.ost==9)@(negedge clk);
           end
         end
         while(dut.ost!=9 || !dut.tst_busy)@(negedge clk);
         repeat(reset_index%4)@(negedge clk);
         rst=1;src_req=0;src_active=0;
         interrupted_address=int'(dut.pf_target)<<3;
         if(b_burstcnt>1)multi_reset_drains++;
         core_reset_drains++;
       end
     join_any
     disable fork;
     rst=1;src_req=0;src_active=0;
     byte_write(interrupted_address,8'(reset_index*13));
     byte_write(interrupted_address+7,8'(reset_index*29));
     repeat(200)@(negedge clk);drain();
     rst=0;source_read(interrupted_address);cpu_read(interrupted_address+7);
     source_read('hc0000+reset_index*31);cpu_read('hd0000+reset_index*17);
   end
   src_active=0;drain();
   // Brief consumer resets followed by immediate unrelated requests while
   // the old transaction can still be returning. No stale completion may
   // acknowledge the new address. Offset sweeps straddle early response ACK.
   for(int i=0;i<8;i++)begin
     src_active=1;src_stream=1;
     fork
       begin for(int j=0;j<2048;j++)source_read('he0000+i*4096+j,4);end
       begin
         while(dut.ost!=9||!dut.tst_busy)@(negedge clk);
         repeat(i*5)@(negedge clk);
         rst=1;src_req=0;
       end
     join_any
     disable fork;
     rst=1;src_req=0;src_active=0;
     repeat(2+i%3)@(negedge clk);rst=0;
     source_read('h120000+i*123);cpu_read('h130000+i*177);drain();
   end
   if(BURST==4&&STREAM_HINT==1)begin
     // Explicitly catch the final beat, including adjacent-cycle responses.
     // Reset only the consumer to cancel the setup run; the bus keeps draining.
     force_adjacent=1;
     for(int i=0;i<4;i++)begin
       src_active=1;src_stream=1;
       fork
         begin for(int j=0;j<2048;j++)source_read('h180000+i*4096+j,4);end
         begin
           while(dut.ost!=9||!dut.tst_busy||dut.pf_burst_len!=4||dut.pf_burst_left!=4)@(negedge clk);
           target_last_byte=(int'(dut.pf_burst_base)+3)*8+i;
           rst=1;src_req=0;
         end
       join_any
       disable fork;
       rst=1;src_req=0;repeat(2)@(negedge clk);rst=0;
       src_stream=0; // issued burst must still drain every beat
       source_read(target_last_byte);src_active=0;drain();
     end
     force_adjacent=0;
   end
   // Deliberately unmapped download: sticky physical/model fault, no false
   // success or new read acceptance, then explicit power reset recovery.
   expecting_fault=1;rst=1;
   byte_write('h1000000,8'h42);
   begin: fault_wait
     integer waited;waited=0;
     while(!fault)begin @(negedge clk);waited++;if(waited>30000)$fatal(1,"fault not raised");end
   end
   repeat(50)@(negedge clk);
   sdram_por=1;repeat(8)@(negedge clk);sdram_por=0;
   while(ddram_busy)@(negedge clk);
   expecting_fault=0;rst=0;source_read('h1e0000);cpu_read('h1f0000);drain();
   if(core_reset_drains!=8)$fatal(1,"reset coverage incomplete");
   if(BURST==4&&STREAM_HINT==1&&multi_reset_drains<4)$fatal(1,"multibeat reset coverage incomplete");
   if(BURST==4&&STREAM_HINT==1&&(caught_tail<4||caught_early==0||hint_fell_in_burst==0||alignments!=15))$fatal(1,"burst directed coverage incomplete");
   if(BURST==4&&STREAM_HINT==1&&PHYSICAL==0&&consecutive_responses==0)$fatal(1,"adjacent response coverage missing");
   $display("PASS physical=%0d burst=%0d stream_hint=%0d src=%0d cg=%0d priority=%0d busbeats=%0d reads=%0d writes=%0d resets=%0d multiresets=%0d hist1=%0d hist2=%0d hist3=%0d hist4=%0d",PHYSICAL,BURST,STREAM_HINT,src_checked,cg_checked,priority_checked,bus_checked,read_commands,write_commands,core_reset_drains,multi_reset_drains,burst_hist[1],burst_hist[2],burst_hist[3],burst_hist[4]);
   $display("TRACE_HASH %016h",trace_hash);
   $display("COVER tail=%0d early=%0d adjacent=%0d hint_fall=%0d alignments=%b",caught_tail,caught_early,consecutive_responses,hint_fell_in_burst,alignments);
   $finish;
 end
 initial begin #100000000;$fatal(1,"global timeout");end
endmodule

`timescale 1ns/1ps
module gfx_burst_memory_model(
 input logic clk,reset,force_adjacent,
 input logic [28:0] ddram_addr,
 input logic [7:0] ddram_burstcnt,ddram_be,
 input logic ddram_rd,ddram_we,
 input logic [63:0] ddram_din,
 output logic ddram_busy,
 output logic [63:0] ddram_dout=0,
 output logic ddram_dout_ready=0,fault=0
);
 logic active=0;
 int delay_left=0, beats_left=0, cycle=0;
 logic [28:0] next_address=0;
 byte unsigned changed[int unsigned];
 function automatic logic[7:0] initial_byte(input int unsigned a);
   int unsigned h;
   h=(a>>1)^32'h9e3779b9;
   h=(h^(h>>16))*32'h7feb352d;
   h=(h^(h>>15))*32'h846ca68b;
   h=h^(h>>16);
   return a[0]?h[15:8]:h[7:0];
 endfunction
 function automatic logic[7:0] value(input int unsigned a);
   if(a>=32'h1000000) return 0;
   if(changed.exists(a)) return changed[a];
   return initial_byte(a);
 endfunction
 assign ddram_busy=reset||fault||active||(cycle%17==0)||(cycle%17==1);
 always @(posedge clk) begin
   cycle<=cycle+1;ddram_dout_ready<=0;
   if(reset) begin active<=0;fault<=0;delay_left<=0;beats_left<=0;end
   else if(active) begin
     if(delay_left!=0)delay_left<=delay_left-1;
     else begin
       for(int lane=0;lane<8;lane++)ddram_dout[lane*8+:8]<=value(((next_address-29'h6800000)<<3)+lane);
       ddram_dout_ready<=1;next_address<=next_address+1;
       beats_left<=beats_left-1;
       if(beats_left==1)active<=0;
       else delay_left<=force_adjacent?0:cycle%5; // variable gaps, including adjacent beats
     end
   end else if(!ddram_busy&&(ddram_rd||ddram_we)) begin
     if(ddram_rd&&ddram_we) $fatal(1,"rd+we");
     if(ddram_addr<29'h6800000 || ddram_addr>=29'h6c00000 || (ddram_we&&ddram_addr>=29'h6a00000))fault<=1;
     else if(ddram_we)begin
       if(ddram_burstcnt!=1)$fatal(1,"unexpected burst write");
       for(int lane=0;lane<8;lane++)if(ddram_be[lane])changed[((ddram_addr-29'h6800000)<<3)+lane]=ddram_din[lane*8+:8];
     end else begin
       active<=1;next_address<=ddram_addr;beats_left<=ddram_burstcnt;
       delay_left<=22+(cycle%7);
     end
   end
 end
endmodule

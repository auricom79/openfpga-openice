`timescale 1ns/1ps
module tb_apf_ready_4k;
localparam integer CHUNK=4096, PROGRAM=8192, GRAPHICS=12288, SOUND=8192, TOTAL=28672;
reg clk_74a=0,clk_mem=0,reset=1;
always #6.734 clk_74a=~clk_74a;
always #6.25 clk_mem=~clk_mem;
reg bridge_wr=0,bridge_rd=0;
reg [31:0] bridge_addr=0,bridge_wr_data=0;
wire [31:0] cmd_data;
wire bridge_endian_little=0;
wire reset_n,allcomplete,loader_done,loader_fault;
wire ef_sync=0;
wire [2:0] por_bridge={3{reset}};
wire target_read,target_ack,target_done;
wire [2:0] target_error;
wire [15:0] target_id;
wire [31:0] target_offset,target_address,target_length;
core_bridge_cmd commands(
    .clk(clk_74a),.reset_n(reset_n),.bridge_endian_little(bridge_endian_little),
    .bridge_addr(bridge_addr),.bridge_rd(bridge_rd),.bridge_rd_data(cmd_data),
    .bridge_wr(bridge_wr),.bridge_wr_data(bridge_wr_data),
    .status_boot_done(!por_bridge[2]),.status_setup_done(!por_bridge[2]),
    .status_running(reset_n && loader_done && !loader_fault && !ef_sync),
    .dataslot_requestread(),.dataslot_requestread_id(),
    .dataslot_requestread_ack(1'b1),.dataslot_requestread_ok(1'b0),
    .dataslot_requestwrite(),.dataslot_requestwrite_id(),.dataslot_requestwrite_size(),
    .dataslot_requestwrite_ack(1'b1),.dataslot_requestwrite_ok(1'b1),
    .dataslot_update(),.dataslot_update_id(),.dataslot_update_size(),
    .dataslot_allcomplete(allcomplete),
    .rtc_epoch_seconds(),.rtc_date_bcd(),.rtc_time_bcd(),.rtc_valid(),
    .savestate_supported(1'b0),.savestate_addr(32'd0),.savestate_size(32'd0),
    .savestate_maxloadsize(32'd0),.savestate_start(),.savestate_start_ack(1'b0),
    .savestate_start_busy(1'b0),.savestate_start_ok(1'b0),.savestate_start_err(1'b0),
    .savestate_load(),.savestate_load_ack(1'b0),.savestate_load_busy(1'b0),
    .savestate_load_ok(1'b0),.savestate_load_err(1'b0),.osnotify_inmenu(),
    .target_dataslot_read(target_read),.target_dataslot_write(1'b0),
    .target_dataslot_getfile(1'b0),.target_dataslot_openfile(1'b0),
    .target_dataslot_ack(target_ack),.target_dataslot_done(target_done),
    .target_dataslot_err(target_error),.target_dataslot_id(target_id),
    .target_dataslot_slotoffset(target_offset),.target_dataslot_bridgeaddr(target_address),
    .target_dataslot_length(target_length),.target_buffer_param_struct(32'd0),
    .target_buffer_resp_struct(32'd0),.datatable_addr(10'd0),.datatable_wren(1'b0),
    .datatable_data(32'd0),.datatable_q()
);

wire active,valid;
wire [1:0] index;
wire [24:0] addr;
wire [7:0] data;
reg ready=0,idle=0;
integer accepted=0,wait_drain=0,cycles=0;
wolf_pocket_loader #(.CHUNK_BYTES(CHUNK),.PROGRAM_BYTES(PROGRAM),.GRAPHICS_BYTES(GRAPHICS),.SOUND_BYTES(SOUND)) loader(
 .clk_bridge(clk_74a),.reset_bridge(reset),.clk_mem(clk_mem),.reset_mem(reset),.start(allcomplete),
 .bridge_wr(bridge_wr),.bridge_addr(bridge_addr),.bridge_wr_data(bridge_wr_data),
 .target_read(target_read),.target_id(target_id),.target_offset(target_offset),
 .target_address(target_address),.target_length(target_length),.target_ack(target_ack),
 .target_done(target_done),.target_error(target_error),.done(loader_done),.fault(loader_fault),
 .load_active(active),.load_valid(valid),.load_index(index),.load_addr(addr),.load_data(data),
 .load_ready(ready),.writes_idle(idle));
always @(negedge clk_mem) begin
 cycles++; ready=!reset && cycles>10000 && cycles%17==0;
 if(wait_drain>0) wait_drain--;
 idle=wait_drain==0;
end
always @(posedge clk_mem) if(valid && ready) begin
 if(!allcomplete) $fatal(1,"APF accepted data before cold-boot008F");
 if(index!=(accepted<PROGRAM?0:accepted<PROGRAM+GRAPHICS?1:2) || addr!=(accepted<PROGRAM?accepted:accepted<PROGRAM+GRAPHICS?accepted-PROGRAM:accepted-PROGRAM-GRAPHICS) || data!=8'((accepted<PROGRAM?0:accepted<PROGRAM+GRAPHICS?64:128)+addr))
  $fatal(1,"APF delivered wrong byte %d",accepted);
 accepted++;wait_drain=750;
end
wire modeled_engine_reset=!reset_n || reset || active || loader_fault;
always @(posedge clk_mem) if(!reset && accepted<TOTAL && !modeled_engine_reset)
 $fatal(1,"Game reset released before deferred ROM completion");
always @(posedge clk_mem) if(!reset && !active && (accepted!=TOTAL || !idle || !loader_done))
 $fatal(1,"Loader released game before all writes drained");
task automatic wrreg(input [31:0] a,d);
 @(negedge clk_74a);bridge_addr=a;bridge_wr_data=d;bridge_wr=1;
 @(negedge clk_74a);bridge_wr=0;
 repeat(4) @(negedge clk_74a);
endtask
task automatic rdreg(input [31:0] a,output [31:0] d);
 @(negedge clk_74a);bridge_addr=a;bridge_rd=1;
 repeat(4) @(negedge clk_74a);
 d=cmd_data;bridge_rd=0;
endtask
task automatic host_command(input [15:0] command,input [31:0] expected);
 reg [31:0] response;
 wrreg(32'hf8000000,{16'h434d,command});
 rdreg(32'hf8000000,response);
 if(response!==expected) $fatal(1,"APF host command %h returned %h, expected %h",command,response,expected);
endtask
task automatic wait_command(input [31:0] c);
 reg [31:0] d;
 do rdreg(32'hf8001000,d); while(d!=c);
endtask
reg [31:0] q;
initial begin
 repeat(12) @(negedge clk_74a);reset=0;
 // Pocket OS2.7 cold-boot sequence from the APF_Deferred hardware log:
 // accept0082 to open each deferred slot, update ID/size BRAM, then008F.
 // Cold boot does not send008A; no payload is pushed while opening slots.
 host_command(16'h0000,32'h4f4b0003);
 wrreg(32'hf8000020,32'h00008000);
 host_command(16'h00b1,32'h4f4bffff);
 for(integer slot=0;slot<3;slot++) begin
  wrreg(32'hf8000020,32'(slot));wrreg(32'hf8000024,slot==1?GRAPHICS:PROGRAM);
  host_command(16'h0082,32'h4f4b0000);
  wrreg(32'hf8002000+slot*8,32'(slot));
  wrreg(32'hf8002004+slot*8,slot==1?GRAPHICS:PROGRAM);
  rdreg(32'hf8002000+slot*8,q);if(q!==32'(slot)) $fatal(1,"Wrong cold slot table ID");
  rdreg(32'hf8002004+slot*8,q);if(q!==(slot==1?GRAPHICS:PROGRAM)) $fatal(1,"Wrong cold slot table size");
  if(accepted!=0 || valid || target_read || allcomplete || loader_done || loader_fault || reset_n)
   $fatal(1,"Deferred slot opening started loading before008F");
 end
 host_command(16'h008f,32'h4f4b0000);
 // Strict host policy follows the historical APF_Deferred OS2.7 sequence:
 // do not service target file reads until READY TO RUN and Reset Exit.
 // No newly observed test3 log is claimed by this regression.
 // The actual test3 logs contain RTC and Docked notifications before readiness.
 wrreg(32'hf8000020,32'h61d0b24e);wrreg(32'hf8000024,32'h20211231);wrreg(32'hf8000028,32'h05195806);
 host_command(16'h0090,32'h4f4b0000);
 wrreg(32'hf8000020,32'h00000000);host_command(16'h00b2,32'h4f4bffff);
 repeat(40) @(negedge clk_74a);
 rdreg(32'hf8001000,q);
 if(q!==32'h636d0140) $fatal(1,"STRICT_HOST Core not ready to run: target=%h loader_done=%b reset_n=%b accepted=%0d",q,loader_done,reset_n,accepted);
 if(loader_done || !active || accepted!=0 || reset_n) $fatal(1,"Unexpected early game/payload state");
 wrreg(32'hf8001000,32'h6f6b0000);
 // The target may publish0180 once0140 is ACKed. Hold it without any service
 // while the host is still in prerun; queueing must survive a long delay.
 repeat(4000) @(negedge clk_74a);
 rdreg(32'hf8001000,q);if(q!==32'h636d0180) $fatal(1,"Deferred request lost before0011");
 if(loader_done || accepted!=0 || loader_fault || !active || reset_n) $fatal(1,"Early deferred progress before0011");
 host_command(16'h0011,32'h4f4b0000);
 if(!reset_n || !active || loader_done) $fatal(1,"Framework reset exit must precede deferred payload completion");
 // Even with host reset released, the exact system rst expression includes
 // load_active. The CPU may not run until bytes and writes have drained.

 for(integer slot=0;slot<3;slot++) begin
  for(integer off=0;off<(slot==1?GRAPHICS:PROGRAM);off+=CHUNK) begin
   wait_command(32'h636d0180);
   rdreg(32'hf8001020,q);if(q!=slot) $fatal(1,"Wrong APF slot id");
   rdreg(32'hf8001024,q);if(q!=off) $fatal(1,"Wrong APF slot offset");
   rdreg(32'hf8001028,q);if(q!=32'h10000000) $fatal(1,"Wrong APF buffer address");
   rdreg(32'hf800102c,q);if(q!=CHUNK) $fatal(1,"Wrong APF length");
   wrreg(32'hf8001000,32'h62750000);
   // Firmware/file latency is unconstrained relative to the game; no progress
   // may be inferred from ACK alone.
   repeat(500+slot*200) @(negedge clk_74a);
   for(integer n=0;n<CHUNK;n+=4) begin
    if(n==CHUNK/2) repeat(1000) @(negedge clk_74a);
    wrreg(32'h10000000+n,{8'(slot*64+off+n),8'(slot*64+off+n+1),8'(slot*64+off+n+2),8'(slot*64+off+n+3)});
   end
   wrreg(32'hf8001000,32'h6f6b0000);
  end
 end
 wait(loader_done);repeat(10)@(negedge clk_mem);
 if(accepted!=TOTAL || !idle || loader_fault || !reset_n || active) $fatal(1,"Deferred completion before drain");
 host_command(16'h0010,32'h4f4b0000);
 if(reset_n || accepted!=TOTAL || !loader_done || loader_fault)
  $fatal(1,"Game reset changed deferred loader contents/state");
 $display("PASS strict host:0082x3/008F,0140 before0180,0011 before deferred reads,28672 bytes/7chunks4KiB/drain then game released,0010 preserves ROMs");
 $finish;
end
initial begin #20000000;$fatal(1,"APF command timeout");end
endmodule

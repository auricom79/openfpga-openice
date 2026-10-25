`timescale 1ns/1ps
// Real Pocket-configured TMS CPU executing a synthetic program. Exercises
// opcode/immediate fetches with c_req continuously asserted across ACKs,
// then data store/load dependencies. No game ROM or forced internal state.
module tms_adapter_case #(parameter bit FAST=0)(output reg done=0,output integer elapsed=0);
    import tms34010_pkg::*;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg[1:0]div=0;
    wire ce=rst || (!done && div==0);
    always @(posedge clk)if(rst)div<=0;else div<=div+1;
    wire c_req,c_we,c_srt,c_ack,m_req,m_we,m_ack,illegal;
    wire[31:0]c_addr,c_wdata,c_rdata,m_addr,m_wdata,m_rdata,pc;
    wire[5:0]c_size,m_size;
    wire[15:0]instr;
    core_state_t state;
    tms34010_core cpu(.clk(clk),.rst(rst),.ce_cpu(ce),.ce_pix(1'b0),
        .mem_req(c_req),.mem_we(c_we),.mem_srt(c_srt),.mem_addr(c_addr),
        .mem_wdata(c_wdata),.mem_size(c_size),.mem_rdata(c_rdata),.mem_ack(c_ack),
        .pc_o(pc),.instr_word_o(instr),.state_o(state),.illegal_opcode_o(illegal),.lint1_in(1'b0));
    yunit_mem_sameclock #(.FAST_BACK_TO_BACK(FAST)) adapter(
        .clk_cpu(clk),.clk_sys(clk),.ce_cpu(ce),.rst_cpu(rst),.rst_sys(rst),
        .c_req(c_req),.c_we(c_we),.c_addr(c_addr),.c_size(c_size),.c_wdata(c_wdata),
        .c_ack(c_ack),.c_rdata(c_rdata),.m_req(m_req),.m_we(m_we),.m_addr(m_addr),
        .m_size(m_size),.m_wdata(m_wdata),.m_rdata(m_rdata),.m_ack(m_ack));
    sim_memory_model #(.DEPTH_WORDS(16384)) mem(.clk(clk),.rst(rst),.mem_req(m_req),
        .mem_we(m_we),.mem_addr(m_addr),.mem_size(m_size),.mem_wdata(m_wdata),
        .mem_rdata(m_rdata),.mem_ack(m_ack),.mem_srt(1'b0));
    function automatic[31:0]value(input integer n);value=32'h1ce01234^(32'h9e3779b9*n);endfunction
    integer p=0,stores=0,transactions=0,clock_count=0;
    integer consumed_last=-99,req_changed_last=-99;
    reg[70:0]previous_cpu_payload=0;
    task automatic word(input[15:0]w);mem.mem[p]=w;p=p+1;endtask
    task automatic op32(input[15:0]op,input[31:0]v);word(op);word(v[15:0]);word(v[31:16]);endtask
    initial begin
        #1;
        for(integer i=0;i<16384;i++)mem.mem[i]=16'h0300;
        word(16'h0540); // SETF field0=32
        for(integer i=0;i<128;i++)begin
            op32(16'h09e1,value(i)); // MOVI IL immediate,A1
            op32(16'h0581,32'h10000+i*32); // MOVE A1,@scratch[i]
            op32(16'h05a2,32'h10000+i*32); // MOVE @scratch[i],A2
            op32(16'h0582,32'h20000+i*32); // MOVE A2,@result[i]
        end
        word(16'hc0ff); // JRUC self
        mem.mem[16382]=0;mem.mem[16383]=0;
        repeat(4)@(negedge clk);rst=0;
        wait(stores==256);@(negedge clk);
        for(integer i=0;i<128;i++)begin
            if({mem.mem[4097+i*2],mem.mem[4096+i*2]}!==value(i) ||
               {mem.mem[8193+i*2],mem.mem[8192+i*2]}!==value(i))
                $fatal(1,"Stored result mismatch fast%0d index%0d",FAST,i);
        end
        if(cpu.u_regfile.a_regs[2]!==value(127))$fatal(1,"Final A2 mismatch");
        done=1;elapsed=clock_count;
        $display("TMS PASS fast=%0d cycles=%0d transactions=%0d stores=%0d final_A2=%08h",FAST,elapsed,transactions,stores,cpu.u_regfile.a_regs[2]);
    end
    always @(posedge clk)begin
        if(!rst)begin
            clock_count<=clock_count+1;
            if(illegal)$fatal(1,"Illegal instruction fast=%0d PC=%08h",FAST,pc);
            if(c_srt)$fatal(1,"Unexpected SRT transaction");
            if(m_ack)begin
                transactions<=transactions+1;
                if(m_we)begin
                    if(m_size!=32 || m_wdata!==value(stores/2) ||
                       m_addr!==((stores[0]?32'h20000:32'h10000)+(stores/2)*32))
                        $fatal(1,"Stale/reordered real-CPU store fast%0d count%0d addr%h data%h",FAST,stores,m_addr,m_wdata);
                    stores<=stores+1;
                end
            end
        end
    end
    initial begin #10000000;$fatal(1,"TMS timeout fast=%0d",FAST);end
endmodule
module tb_tms_adapter_perf;
    wire slow_done,fast_done;
    wire[31:0]slow_cycles,fast_cycles;
    tms_adapter_case #(.FAST(0)) baseline(slow_done,slow_cycles);
    tms_adapter_case #(.FAST(1)) candidate(fast_done,fast_cycles);
    initial begin wait(slow_done&&fast_done);#20;
        if(fast_cycles>=slow_cycles)$fatal(1,"No real-CPU improvement");
        if(baseline.transactions!==candidate.transactions)$fatal(1,"Duplicated/missing CPU transaction");
        $display("TMS ALL PASS cycles %0d -> %0d, identical transaction count and memory results",slow_cycles,fast_cycles);$finish;
    end
endmodule

// SPDX-License-Identifier: MIT
`timescale 1ns/1ps
// Real TMS with FS=0 (encoded32), actual same-clock adapter and RAM field engine.
// Program/reset vector are synthetic. ROM fixture is separate from RAM.
module tms_ram_case #(parameter bit FAST=0)(output reg done=0,output integer elapsed=0);
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
    yunit_mem_sameclock #(.FAST_BACK_TO_BACK(1'b1)) adapter(
        .clk_cpu(clk),.clk_sys(clk),.ce_cpu(ce),.rst_cpu(rst),.rst_sys(rst),
        .c_req(c_req),.c_we(c_we),.c_addr(c_addr),.c_size(c_size),.c_wdata(c_wdata),
        .c_ack(c_ack),.c_rdata(c_rdata),.m_req(m_req),.m_we(m_we),.m_addr(m_addr),
        .m_size(m_size),.m_wdata(m_wdata),.m_rdata(m_rdata),.m_ack(m_ack));
    wire ram_selected=m_addr>=32'h10000 && m_addr<32'h30000;
    wire [31:0]rom_data,ram_data;
    wire rom_done,ram_done;
    assign m_ack=ram_selected?ram_done:rom_done;
    // For a completed store, FAST intentionally returns a conspicuous ignored
    // value. This checks that architectural state depends only on read returns.
    assign m_rdata=ram_selected ? ((FAST&&m_we)?32'hbad0cafe:ram_data) : rom_data;
    sim_memory_model #(.DEPTH_WORDS(16384)) rom(.clk(clk),.rst(rst),
        .mem_req(m_req&&!ram_selected),.mem_we(1'b0),.mem_addr(m_addr),.mem_size(m_size),
        .mem_wdata(32'd0),.mem_rdata(rom_data),.mem_ack(rom_done),.mem_srt(1'b0));
    reg ram_seen=0;
    always @(posedge clk)if(rst||!m_req)ram_seen<=0;else if(ram_selected)ram_seen<=1;
    wire [24:0] sd_addr;
    wire [15:0] sd_din,sd_dout;
    wire [1:0] sd_be;
    wire sd_rd,sd_wr,sd_ack;
    wire integer reads,writes;
    ram_sdram #(.RAMW(8192),.FAST_FULL_WRITES(FAST)) ram(
        .clk,.rst,.req(m_req&&ram_selected&&!ram_seen),.we(m_we),.widx(m_addr[31:4]-28'h1000),
        .boff(m_addr[3:0]),.sz(m_size),.wd(m_wdata),.rdata(ram_data),.done(ram_done),.active(),
        .sd_addr,.sd_din,.sd_be,.sd_rd,.sd_wr,.sd_dout,.sd_ack);
    ram_word_model #(.WORDS(8192)) memory(.clk,.rst,.addr(sd_addr),.din(sd_din),.be(sd_be),
        .rd(sd_rd),.wr(sd_wr),.dout(sd_dout),.ack(sd_ack),.reads,.writes);
    function automatic[31:0]value(input integer n);value=32'h1ce01234^(32'h9e3779b9*n);endfunction
    integer p=0,stores=0,transactions=0,clock_count=0;
    task automatic word(input[15:0]w);rom.mem[p]=w;p=p+1;endtask
    task automatic op32(input[15:0]op,input[31:0]v);word(op);word(v[15:0]);word(v[31:16]);endtask
    initial begin
        #1;
        for(integer i=0;i<16384;i++)rom.mem[i]=16'h0300;
        word(16'h0540); // SETF field0=0 encoding32
        for(integer i=0;i<128;i++)begin
            op32(16'h09e1,value(i));
            op32(16'h0581,32'h10000+i*32);
            op32(16'h05a2,32'h10000+i*32);
            op32(16'h0582,32'h20000+i*32);
        end
        word(16'hc0ff);
        rom.mem[16382]=0;rom.mem[16383]=0;
        repeat(4)@(negedge clk);rst=0;
        wait(stores==256);@(negedge clk);
        for(integer i=0;i<128;i++)begin
            if({memory.mem[1+i*2],memory.mem[i*2]}!==value(i) ||
               {memory.mem[4097+i*2],memory.mem[4096+i*2]}!==value(i))
                $fatal(1,"Real CPU RAM mismatch fast%0d index%0d",FAST,i);
        end
        if(cpu.u_regfile.a_regs[2]!==value(127))$fatal(1,"Final A2 mismatch");
        done=1;elapsed=clock_count;
        $display("REAL TMS RAM PASS fast=%0d cycles=%0d transactions=%0d stores=%0d reads=%0d writes=%0d final_A2=%08h",FAST,elapsed,transactions,stores,reads,writes,cpu.u_regfile.a_regs[2]);
    end
    always @(posedge clk)if(!rst)begin
        clock_count<=clock_count+1;
        if(illegal)$fatal(1,"Illegal instruction fast%0d PC=%08h",FAST,pc);
        if(c_srt)$fatal(1,"Unexpected SRT");
        if(m_ack)begin
            transactions<=transactions+1;
            if(m_we)begin
                if(m_size!=32 || m_wdata!==value(stores/2) ||
                   m_addr!==((stores[0]?32'h20000:32'h10000)+(stores/2)*32))
                    $fatal(1,"Real CPU store mismatch/size encoding fast%0d",FAST);
                stores<=stores+1;
            end
        end
    end
    initial begin #10000000;$fatal(1,"Real TMS RAM timeout");end
endmodule
module tb_tms_ram_perf;
    wire d0,d1;wire[31:0]t0,t1;
    tms_ram_case #(.FAST(0)) baseline(d0,t0);
    tms_ram_case #(.FAST(1)) candidate(d1,t1);
    initial begin wait(d0&&d1);#20;
        if(t1>=t0||baseline.transactions!==candidate.transactions)$fatal(1,"No safe real CPU RAM saving");
        for(integer i=0;i<15;i++)begin
            if(baseline.cpu.u_regfile.a_regs[i]!==candidate.cpu.u_regfile.a_regs[i] ||
               baseline.cpu.u_regfile.b_regs[i]!==candidate.cpu.u_regfile.b_regs[i])
                $fatal(1,"CPU register mismatch%0d",i);
        end
        if(baseline.cpu.st_value!==candidate.cpu.st_value)$fatal(1,"CPU status mismatch");
        $display("ALL PASS real TMS RAM store-return poison and encoded-zero32bit field");$finish;
    end
endmodule

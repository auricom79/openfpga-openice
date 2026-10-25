`timescale 1ns/1ps
// Independent synthetic CPU and memory peers. No game ROMs.
module adapter_case #(
    parameter bit FAST=0,
    parameter integer ID=0,
    parameter integer THINK=0,
    parameter integer TOTAL=2048
)(output reg done=0, output integer cycles_done=0);
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg [1:0] div=0;
    wire ce=rst || div==0;
    always @(posedge clk) if(rst) div<=0; else div<=div+1;
    reg c_req=0,c_we=0;
    reg [31:0] c_addr=0,c_wdata=0;
    reg [5:0] c_size=0;
    wire c_ack,m_req,m_we;
    wire [31:0] c_rdata,m_addr,m_wdata;
    wire [5:0] m_size;
    reg m_ack=0;
    reg [31:0] m_rdata=0;
    yunit_mem_sameclock #(.FAST_BACK_TO_BACK(FAST)) dut(
        .clk_cpu(clk),.clk_sys(clk),.ce_cpu(ce),.rst_cpu(rst),.rst_sys(rst),
        .c_req(c_req),.c_we(c_we),.c_addr(c_addr),.c_size(c_size),.c_wdata(c_wdata),
        .c_ack(c_ack),.c_rdata(c_rdata),.m_req(m_req),.m_we(m_we),.m_addr(m_addr),
        .m_size(m_size),.m_wdata(m_wdata),.m_rdata(m_rdata),.m_ack(m_ack));
    function automatic [31:0] mix(input [31:0] x);
        reg [31:0] q;
        begin q=x^(x<<13);q=q^(q>>17);mix=q^(q<<5);end
    endfunction
    function automatic [70:0] payload(input integer seq);
        reg[31:0] q;
        begin q=mix(32'h1ce12345+seq);payload={q[6],q,seq[5:0],~q};end
    endfunction
    function automatic [31:0] response(input [70:0] p);
        response=mix(p[69:38]^p[31:0]^{25'd0,p[70],p[37:32]});
    endfunction
    task automatic send(input integer seq);
        {c_we,c_addr,c_size,c_wdata}<=payload(seq);
        c_req<=1;
    endtask
    integer clock_count=0,consumed=0,issued=0,think_left=0;
    integer epoch=0,last_cpu_change=-999,last_mem_accept=-999;
    integer pending_delay=0,mem_state=0,mem_index=0;
    integer resets=0,non_ce_responses=0,payload_checks=0;
    reg [70:0] held_payload=0;
    reg [31:0] digest=0;
    // Check the actual adapter capture edge, not the memory peer's later
    // observation of m_req. This is the CE/4 timing obligation itself.
    always @(posedge clk) if(!rst && dut.scst==0 && ce && c_req) begin
        if(clock_count-last_cpu_change<4)
            $fatal(1,"Adapter capture violated 4 SYS clocks case%0d",ID);
    end
    always @(posedge clk) begin
        clock_count<=clock_count+1;
        if(rst)begin
            consumed<=0;issued<=0;think_left<=0;c_req<=0;
            c_we<=0;c_addr<=0;c_size<=0;c_wdata<=0;last_cpu_change<=-999;
        end else if(!done && ce)begin
            if(c_ack)begin
                if(!c_req) $fatal(1,"Unexpected CPU ACK case%0d",ID);
                if(c_rdata!==response(payload(consumed)))
                    $fatal(1,"Response mismatch case%0d seq%0d",ID,consumed);
                consumed<=consumed+1;digest<=mix(digest^c_rdata);
                if(consumed+1==TOTAL)begin
                    done<=1;c_req<=0;cycles_done<=clock_count;
                    $display("CASE PASS id=%0d fast=%0d think=%0d transactions=%0d cycles=%0d digest=%h offCE_ACK=%0d reset_windows=%0d",ID,FAST,THINK,TOTAL,clock_count,mix(digest^c_rdata),non_ce_responses,resets);
                end else if(THINK==0)begin send(consumed+1);last_cpu_change<=clock_count;issued<=issued+1;end
                else begin c_req<=0;think_left<=THINK;end
            end else if(!c_req)begin
                if(think_left==0)begin send(consumed);last_cpu_change<=clock_count;issued<=issued+1;end
                else think_left<=think_left-1;
            end
        end
    end
    // A registered responder with deterministic variable delay 0..31 SYS
    // edges, independent from the adapter FSM and CPU CE phase.
    always @(posedge clk)begin
        if(rst)begin
            m_ack<=0;m_rdata<=0;mem_state<=0;mem_index<=0;pending_delay<=0;
        end else case(mem_state)
            0:if(m_req)begin
                if({m_we,m_addr,m_size,m_wdata}!==payload(mem_index))
                    $fatal(1,"Duplicate, stale or reordered request case%0d seq%0d",ID,mem_index);
                if(clock_count-last_cpu_change<4)
                    $fatal(1,"CPU payload captured before 4-cycle allowance case%0d",ID);
                held_payload<={m_we,m_addr,m_size,m_wdata};
                pending_delay<=(mix(mem_index+32'habcdefff)&31);
                mem_state<=1;last_mem_accept<=clock_count;
            end
            1:begin
                if(!m_req || {m_we,m_addr,m_size,m_wdata}!==held_payload)
                    $fatal(1,"Payload/request changed while memory outstanding case%0d",ID);
                payload_checks<=payload_checks+1;
                if(pending_delay==0)begin
                    m_rdata<=response(held_payload);m_ack<=1;mem_state<=2;
                    if(!ce)non_ce_responses<=non_ce_responses+1;
                end else pending_delay<=pending_delay-1;
            end
            2:if(!m_req)begin m_ack<=0;mem_state<=0;mem_index<=mem_index+1;end
        endcase
    end
    // Exercise reset in-flight and with an outstanding response, for each
    // CE phase. The final uninterrupted epoch is scored for throughput.
    initial begin
        repeat(4)@(negedge clk);
        for(integer phase=0;phase<4;phase=phase+1)begin
            rst=0;
            wait(m_req);repeat(phase+1)@(negedge clk);rst=1;resets=resets+1;
            repeat(3)@(negedge clk);rst=0;
            wait(c_ack);repeat(phase+1)@(negedge clk);rst=1;resets=resets+1;
            repeat(3)@(negedge clk);
        end
        clock_count=0;digest=0;rst=0;
    end
    initial begin #5000000;$fatal(1,"Timeout case%0d",ID);end
endmodule

module tb_sameclock_perf;
    wire[5:0]done;
    wire[31:0]cycles[0:5];
    adapter_case #(.FAST(0),.ID(0),.THINK(0)) a(done[0],cycles[0]);
    adapter_case #(.FAST(1),.ID(1),.THINK(0)) b(done[1],cycles[1]);
    adapter_case #(.FAST(0),.ID(2),.THINK(1)) c(done[2],cycles[2]);
    adapter_case #(.FAST(1),.ID(3),.THINK(1)) d(done[3],cycles[3]);
    adapter_case #(.FAST(0),.ID(4),.THINK(3)) e(done[4],cycles[4]);
    adapter_case #(.FAST(1),.ID(5),.THINK(3)) f(done[5],cycles[5]);
    initial begin
        wait(&done);#20;
        if(cycles[1]>=cycles[0])$fatal(1,"No back-to-back benefit");
        if(cycles[3]>cycles[2] || cycles[5]>cycles[4])$fatal(1,"Throughput regression");
        $display("ALL PASS: continuous %0d -> %0d; 1CE gap %0d -> %0d; 3CE gap %0d -> %0d",cycles[0],cycles[1],cycles[2],cycles[3],cycles[4],cycles[5]);$finish;
    end
endmodule

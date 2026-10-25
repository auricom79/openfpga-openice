// Existing conditional-request independence test, with FAST_BACK_TO_BACK enabled.
`timescale 1ns/1ps
module tb_request_qualifier;
 logic clk=0,ce=0,rst=1,c_req=0,noisy_req=0,c_we=0,m_ack=0;
 logic [31:0] c_addr=0,c_wdata=0,m_rdata=0;
 logic [5:0] c_size=0;
 wire ca,cb,ma,mb,wa,wb;wire [31:0]ra,rb,aa,ab,da,db;wire [5:0]sa,sb;
 yunit_mem_sameclock #(.FAST_BACK_TO_BACK(1)) a(.clk_cpu(clk),.clk_sys(clk),.ce_cpu(ce),.rst_cpu(rst),.rst_sys(rst),.c_req(c_req),.c_we(c_we),.c_addr(c_addr),.c_size(c_size),.c_wdata(c_wdata),.c_ack(ca),.c_rdata(ra),.m_req(ma),.m_we(wa),.m_addr(aa),.m_size(sa),.m_wdata(da),.m_rdata(m_rdata),.m_ack(m_ack));
 yunit_mem_sameclock #(.FAST_BACK_TO_BACK(1)) b(.clk_cpu(clk),.clk_sys(clk),.ce_cpu(ce),.rst_cpu(rst),.rst_sys(rst),.c_req(noisy_req),.c_we(c_we),.c_addr(c_addr),.c_size(c_size),.c_wdata(c_wdata),.c_ack(cb),.c_rdata(rb),.m_req(mb),.m_we(wb),.m_addr(ab),.m_size(sb),.m_wdata(db),.m_rdata(m_rdata),.m_ack(m_ack));
 integer checks=0,flips=0,acks_offce=0,accepted=0;logic oldreq;
 logic [31:0] rng=32'h47caee16;
 function automatic [31:0] random_word(input [31:0] x);reg[31:0]r;begin r=x^(x<<13);r=r^(r>>17);r=r^(r<<5);return r;end endfunction
 initial begin
 for(integer i=0;i<100000;i++)begin
  clk=0;ce=((i%4)==0);rst=(i<2)||((i%997)==0);
  rng=random_word(rng);c_req=rng[0];noisy_req=ce?c_req:!c_req;
  c_we=rng[1];c_size=rng[7:2];c_addr=rng; c_wdata=~rng;
  m_ack=rng[8]&&rng[9];m_rdata=rng^32'h19482;
  #2;oldreq=ma;if(!ce&&!rst)flips++;if(!rst&&ma&&m_ack&&!ce)acks_offce++;
  clk=1;#2;
  if({ca,ra,ma,wa,aa,sa,da,a.scst}!=={cb,rb,mb,wb,ab,sb,db,b.scst})$fatal(1,"non-CE request affected adapter cycle=%0d",i);
  if(!oldreq&&ma)accepted++;
  checks++;
 end
 if(flips<70000||acks_offce<1000||accepted<1000)$fatal(1,"insufficient coverage");
 $display("TEST_RESULT PASS: cycles=%0d nonCE_request_inversions=%0d nonCE_ACKs=%0d accepted=%0d",checks,flips,acks_offce,accepted);$finish;
 end
endmodule

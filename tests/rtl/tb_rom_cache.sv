`timescale 1ns/1ps
module cache_case #(parameter integer BITS=0)(output logic finished=0);
  localparam AW=25, N=65536;
  // Exercise the production address/tag width, including physical bit24.
  // The memory oracle stores disjoint test regions by their low16 bits.
  localparam [AW-1:0] ROM_BASE=25'h1001000,VRAM_BASE=25'h1404000,RAM_BASE=25'h1808000;
  logic clk=0; always #5 clk=~clk;
  logic rst=1;
  logic[AW-1:0] vsd_addr=0,rsd_addr=0,iol_addr=0;
  logic[15:0] vsd_din=0,rsd_din=0,iol_din=0;
  logic[1:0] vsd_be=0,rsd_be=0,iol_be=0;
  logic vsd_rd=0,vsd_wr=0,rsd_rd=0,rsd_wr=0,iol_rd=0,iol_wr=0;
  logic cgfx_rd=0,src_rd=0; logic[23:0] cgfx_addr=0,src_addr=0;
  wire[15:0] vsd_dout,rsd_dout,iol_dout; wire[7:0] cgfx_data,src_data;
  wire vsd_ack,rsd_ack,iol_ack,cgfx_ack,src_ack;
  wire[AW-1:0] sd_addr;wire[15:0]sd_din;wire[1:0]sd_be;wire sd_rd,sd_wr;
  logic[15:0]sd_dout=0;logic sd_ack=0;
  yunit_sdram_arb #(.SD_AW(AW),.GFXW_BASE(25'h0000000),.ROMW_BASE(ROM_BASE),
    .VRAMW_BASE(VRAM_BASE),.RAMW_BASE(RAM_BASE),.GFX_BYTES(24'h002000),.CGFX_CACHE_BITS(BITS)) dut(.*);
  if(BITS==0)begin:check_original
    wire[AW-1:0] o_sd_addr;wire[15:0]o_sd_din,o_vsd_dout,o_rsd_dout,o_iol_dout;
    wire[1:0]o_sd_be;wire o_sd_rd,o_sd_wr,o_vsd_ack,o_rsd_ack,o_iol_ack,o_cgfx_ack,o_src_ack;
    wire[7:0]o_cgfx_data,o_src_data;
    yunit_sdram_arb_baseline #(.SD_AW(AW),.GFXW_BASE(25'h0000000),.ROMW_BASE(ROM_BASE),
      .VRAMW_BASE(VRAM_BASE),.RAMW_BASE(RAM_BASE),.GFX_BYTES(24'h002000)) original(
      .sd_addr(o_sd_addr),.sd_din(o_sd_din),.sd_be(o_sd_be),.sd_rd(o_sd_rd),.sd_wr(o_sd_wr),
      .vsd_dout(o_vsd_dout),.rsd_dout(o_rsd_dout),.iol_dout(o_iol_dout),
      .vsd_ack(o_vsd_ack),.rsd_ack(o_rsd_ack),.iol_ack(o_iol_ack),.cgfx_ack(o_cgfx_ack),.src_ack(o_src_ack),
      .cgfx_data(o_cgfx_data),.src_data(o_src_data),.*);
    always @(negedge clk)if(!rst)begin
      assert({sd_addr,sd_din,sd_be,sd_rd,sd_wr,vsd_dout,rsd_dout,iol_dout,vsd_ack,rsd_ack,iol_ack,cgfx_ack,src_ack,cgfx_ack?cgfx_data:8'd0,src_ack?src_data:8'd0}===
        {o_sd_addr,o_sd_din,o_sd_be,o_sd_rd,o_sd_wr,o_vsd_dout,o_rsd_dout,o_iol_dout,o_vsd_ack,o_rsd_ack,o_iol_ack,o_cgfx_ack,o_src_ack,o_cgfx_ack?o_cgfx_data:8'd0,o_src_ack?o_src_data:8'd0})
        else $fatal(1,"Parameter0 changed original behavior");
    end
  end

  logic[15:0] memory[0:N-1],reference[0:N-1];
  logic backend_busy=0,need_low=0;
  logic[AW-1:0] physical_addr;
  logic[15:0] physical_data;
  logic[1:0] physical_be;
  logic physical_wr;
  integer delay_left=0,forced_latency=-1;
  integer cycles=0,accepted=0,reads_cpu=0,completed=0,aborted=0;
  integer ack_cpu=0,ack_vsd=0,ack_rsd=0,ack_iol=0,ack_src=0,overlap_hits=0;
  logic cpu_acked=0,past_cpu_req=0;
  logic[31:0] latency_seen=0;
  integer seed=32'h7294526d;
  function automatic integer physical_word(input logic[23:0]a);
    return a<24'h2000 ? integer'(a>>1) : integer'(ROM_BASE)+integer'((a-24'h2000)>>1);
  endfunction
  function automatic logic[7:0] wanted_byte(input logic[23:0]a);
    logic[15:0]w;w=reference[physical_word(a)&16'hffff];return a[0]?w[15:8]:w[7:0];
  endfunction
  always @(posedge clk)begin
    cycles<=cycles+1;
    sd_ack<=0;
    if(rst)begin
      if(backend_busy)aborted<=aborted+1;
      backend_busy<=0;need_low<=0;cpu_acked<=0;past_cpu_req<=0;
    end else begin
      past_cpu_req<=cgfx_rd;
      if(!dut.gnt_held&&!dut.bubble)
        assert(dut.gnt==((iol_rd||iol_wr)?1:(vsd_rd||vsd_wr)?2:dut.cgfx_miss_req?3:(rsd_rd||rsd_wr)?5:src_rd?4:0))
          else $fatal(1,"Arbitration priority changed");
      if(!cgfx_rd)cpu_acked<=0;
      if(cgfx_ack)begin
        assert(cgfx_rd&&!cpu_acked&&past_cpu_req)else $fatal(1,"Unexpected/duplicate/early CPU ack BITS%0d",BITS);
        cpu_acked<=1;ack_cpu<=ack_cpu+1;
        if(dut.gnt_held&&dut.gnt!=3)overlap_hits<=overlap_hits+1;
      end
      if(vsd_ack)begin assert(vsd_rd||vsd_wr);ack_vsd<=ack_vsd+1;end
      if(rsd_ack)begin assert(rsd_rd||rsd_wr);ack_rsd<=ack_rsd+1;end
      if(iol_ack)begin assert(iol_rd||iol_wr);ack_iol<=ack_iol+1;end
      if(src_ack)begin assert(src_rd);ack_src<=ack_src+1;end
      if(backend_busy)begin
        assert(sd_rd||sd_wr)else $fatal(1,"Physical request withdrawn before ack");
        assert({sd_addr,sd_din,sd_be,sd_wr}==={physical_addr,physical_data,physical_be,physical_wr})else $fatal(1,"Held physical payload changed");
        if(delay_left==0)begin
          sd_dout<=memory[physical_addr[15:0]];
          if(physical_wr)begin
            if(physical_be[0])memory[physical_addr[15:0]][7:0]<=physical_data[7:0];
            if(physical_be[1])memory[physical_addr[15:0]][15:8]<=physical_data[15:8];
          end
          sd_ack<=1;backend_busy<=0;need_low<=1;completed<=completed+1;
        end else delay_left<=delay_left-1;
      end else if(need_low)begin
        if(!(sd_rd||sd_wr))need_low<=0;
      end else if(sd_rd||sd_wr)begin
        accepted<=accepted+1;
        physical_addr<=sd_addr;physical_data<=sd_din;physical_be<=sd_be;physical_wr<=sd_wr;
        backend_busy<=1;
        seed<=(seed<<1)^((seed<0)?32'h04c11db7:0);
        delay_left<=forced_latency>=0?forced_latency:integer'((unsigned'(seed)>>8)%32);
        if(forced_latency<32)latency_seen[forced_latency>=0?forced_latency:integer'((unsigned'(seed)>>8)%32)]<=1;
        case(dut.gnt)
          1:assert(sd_addr==iol_addr&&sd_din==iol_din&&sd_be==iol_be&&sd_wr==iol_wr);
          2:assert(sd_addr==VRAM_BASE+vsd_addr&&sd_din==vsd_din&&sd_be==vsd_be&&sd_wr==vsd_wr);
          3:begin
            assert(sd_addr==physical_word(cgfx_addr)&&sd_rd&&!sd_wr&&cgfx_rd);
            assert(!dut.cgfx_cache_hit&&!dut.cgfx_hit_pending&&dut.cgfx_lookup_ready)else $fatal(1,"Physical CPU request without confirmed miss");
            reads_cpu<=reads_cpu+1;
          end
          4:assert(sd_addr==src_addr>>1&&sd_rd&&!sd_wr);
          5:assert(sd_addr==RAM_BASE+rsd_addr&&sd_din==rsd_din&&sd_be==rsd_be&&sd_wr==rsd_wr);
          default:$fatal(1,"Physical request without grant");
        endcase
      end
    end
  end

  task automatic cpu(input logic[23:0]a,input integer gap=0);
    integer waiting;logic[7:0]expected;
    @(negedge clk);cgfx_addr=a;cgfx_rd=1;
    waiting=0;
    do begin @(posedge clk);waiting++;if(waiting>10000)$fatal(1,"CPU timeout BITS%0d addr%h",BITS,a);end while(!cgfx_ack);
    expected=wanted_byte(a);
    assert(cgfx_data===expected)else $fatal(1,"CPU byte mismatch BITS%0d addr%h got%h expected%h cycle%0d",BITS,a,cgfx_data,expected,cycles);
    @(negedge clk);cgfx_rd=0;
    repeat(gap+1)@(posedge clk);
  endtask
  task automatic iol(input logic wr,input integer a,input logic[15:0]data,input logic[1:0]be=3);
    integer waiting;
    @(negedge clk);iol_addr=ROM_BASE+AW'(a-16'h1000);iol_din=data;iol_be=be;iol_wr=wr;iol_rd=!wr;
    waiting=0;do begin @(posedge clk);waiting++;if(waiting>10000)$fatal(1,"IOL timeout");end while(!iol_ack);
    if(wr)begin
      if(be[0])reference[a][7:0]=data[7:0];if(be[1])reference[a][15:8]=data[15:8];
    end else assert(iol_dout===reference[a]);
    @(negedge clk);iol_wr=0;iol_rd=0;@(posedge clk);
  endtask
  task automatic vsd(input logic wr,input integer a,input logic[15:0]data,input logic[1:0]be=3);
    integer waiting;
    @(negedge clk);vsd_addr=AW'(a);vsd_din=data;vsd_be=be;vsd_wr=wr;vsd_rd=!wr;
    waiting=0;do begin @(posedge clk);waiting++;if(waiting>10000)$fatal(1,"VSD timeout");end while(!vsd_ack);
    if(wr)begin if(be[0])reference[16'h4000+a][7:0]=data[7:0];if(be[1])reference[16'h4000+a][15:8]=data[15:8];end
    else assert(vsd_dout===reference[16'h4000+a]);
    @(negedge clk);vsd_wr=0;vsd_rd=0;@(posedge clk);
  endtask
  task automatic rsd(input logic wr,input integer a,input logic[15:0]data,input logic[1:0]be=3);
    integer waiting;
    @(negedge clk);rsd_addr=AW'(a);rsd_din=data;rsd_be=be;rsd_wr=wr;rsd_rd=!wr;
    waiting=0;do begin @(posedge clk);waiting++;if(waiting>10000)$fatal(1,"RSD timeout");end while(!rsd_ack);
    if(wr)begin if(be[0])reference[16'h8000+a][7:0]=data[7:0];if(be[1])reference[16'h8000+a][15:8]=data[15:8];end
    else assert(rsd_dout===reference[16'h8000+a]);
    @(negedge clk);rsd_wr=0;rsd_rd=0;@(posedge clk);
  endtask
  task automatic src(input integer a);
    integer waiting;
    @(negedge clk);src_addr=24'(a);src_rd=1;
    waiting=0;do begin @(posedge clk);waiting++;if(waiting>10000)$fatal(1,"SRC timeout");end while(!src_ack);
    assert(src_data===(a[0]?reference[a>>1][15:8]:reference[a>>1][7:0]));
    @(negedge clk);src_rd=0;@(posedge clk);
  endtask
  task automatic reset_core;
    @(negedge clk);rst=1;cgfx_rd=0;src_rd=0;vsd_rd=0;vsd_wr=0;rsd_rd=0;rsd_wr=0;iol_rd=0;iol_wr=0;
    repeat(3)@(posedge clk);@(negedge clk);rst=0;repeat(2)@(posedge clk);
  endtask

  integer c0,r0,hit_start,loop_cycles,loop_reads,random_cycles,random_reads;
  integer random_address=32'h1d953769;
  logic[255:0]seen=0;
  initial begin
    for(integer n=0;n<N;n++)begin memory[n]=16'((n*229)^16'ha78b);reference[n]=memory[n];end
    reset_core();
    // Every possible byte, including alternating byte selects and replacement.
    for(integer n=0;n<128;n++)iol(1,16'h1000+n,{8'(2*n+1),8'(2*n)},3);
    for(integer n=0;n<256;n++)begin cpu(24'h2000+24'(n),n%3);seen[wanted_byte(24'h2000+24'(n))]=1;end
    assert(&seen)else $fatal(1,"Byte coverage incomplete");
    // Same table index, different tags. Then immediate same-tag reload.
    for(integer n=0;n<80;n++)begin
      cpu(24'h2000+24'((n%4)*128));cpu(24'h2001+24'((n%4)*128));
    end
    for(integer n=0;n<16;n++)begin
      cpu(24'h2060);iol(1,16'h1030,16'(n*131+16'h4200),1);cpu(24'h2060);cpu(24'h2061);
      iol(1,16'h1030,16'(n*271+16'h9a00),2);cpu(24'h2060);cpu(24'h2061);iol(0,16'h1030,0);
      iol(1,16'h1030,16'hdead,0);cpu(24'h2060);cpu(24'h2061);
    end
    // GFX and ROM physical tags are separate, including identical index bits.
    for(integer n=0;n<64;n++)begin cpu(24'(n*2));cpu(24'h2000+24'(n*2));end
    // A writer becomes pending during a CPU fill. Never retain a stale same-tag
    // lookup after the write completes (both low and high byte independently).
    reset_core();forced_latency=11;
    fork
      cpu(24'h2080);
      begin wait(backend_busy&&dut.gnt==3);iol(1,16'h1040,16'h43a5,1);end
    join
    cpu(24'h2080);cpu(24'h2081);
    fork
      cpu(24'h2181);
      begin wait(backend_busy&&dut.gnt==3);iol(1,16'h10c0,16'hb600,2);end
    join
    cpu(24'h2180);cpu(24'h2181);
    // Abort a pending miss, including the edge where physical ACK was produced
    // but not yet sampled by the arbiter. RAM contents persist across reset.
    for(integer phase=0;phase<3;phase++)begin
      reset_core();
      @(negedge clk);cgfx_addr=24'h2200+24'(phase*128);cgfx_rd=1;
      wait(backend_busy);if(phase==0)repeat(2)@(negedge clk);
      else if(phase==1)wait(delay_left==0);
      else wait(sd_ack);
      reset_core();iol(1,16'h1100+phase*64,16'(16'hda40+phase),3);
      cpu(24'h2200+24'(phase*128));cpu(24'h2201+24'(phase*128));
    end
    forced_latency=-1;
    // Every physical response latency0..31, including immediate adjacent-byte
    // lookup after fill and a reset before each cold request.
    for(integer latency=0;latency<32;latency++)begin
      reset_core();forced_latency=latency;
      cpu(24'h2600+24'(latency*128));cpu(24'h2601+24'(latency*128));
    end
    assert(&latency_seen);
    // Hits can complete independently while VRAM owns the physical port.
    cpu(24'h2020);forced_latency=45;r0=reads_cpu;
    fork
      vsd(0,7,0);
      begin wait(backend_busy&&dut.gnt==2);hit_start=cycles;cpu(24'h2021);assert(cycles-hit_start<12);end
    join
    assert(reads_cpu==r0)else $fatal(1,"Cached hit issued physical read under other grant");
    fork
      vsd(1,16,16'hdead);
      begin wait(backend_busy&&dut.gnt==2);cpu(24'h2020);end
    join
    fork
      rsd(1,16,16'hbeef);
      begin wait(backend_busy&&dut.gnt==5);cpu(24'h2021);end
    join
    assert(reads_cpu==r0)else $fatal(1,"Disjoint RAM/VRAM writes invalidated ROM cache");
    forced_latency=-1;
    // Concurrent channels with disjoint physical maps and varying latency.
    fork
      begin for(integer n=0;n<200;n++)cpu(24'h2000+24'((n*37)%512),n%4);end
      begin for(integer n=0;n<40;n++)begin vsd(1,n,16'(n*499),2'(n%3+1));vsd(0,n,0);end end
      begin for(integer n=0;n<35;n++)begin rsd(1,n,16'(n*653),2'(n%3+1));rsd(0,n,0);end end
      begin for(integer n=0;n<70;n++)src((n*97)%1024);end
      begin for(integer n=0;n<8;n++)begin repeat(41)@(posedge clk);iol(1,16'h1800+n,16'(n*757),3);end end
    join
    assert(ack_vsd>=81&&ack_rsd>=70&&ack_src>=70&&overlap_hits>=1);
    // Controlled measurements: fixed latency, identical logical request trace.
    //32 four-byte instructions=64words, repeated16times. Includes cold fills.
    reset_core();forced_latency=12;c0=cycles;r0=reads_cpu;
    for(integer n=0;n<16;n++)for(integer b=0;b<128;b++)cpu(24'h2400+24'(b));
    loop_cycles=cycles-c0;loop_reads=reads_cpu-r0;
    reset_core();c0=cycles;r0=reads_cpu;
    for(integer n=0;n<2048;n++)begin
      random_address=(random_address<<1)^((random_address<0)?32'h04c11db7:0);
      cpu(24'h2000+24'((unsigned'(random_address)>>8)%2048));
    end
    random_cycles=cycles-c0;random_reads=reads_cpu-r0;
    $display("RESULT bits=%0d loop_cycles=%0d loop_reads=%0d random_cycles=%0d random_reads=%0d cpu_ack=%0d other_ack=%0d/%0d/%0d/%0d overlap=%0d resets_aborted=%0d",BITS,loop_cycles,loop_reads,random_cycles,random_reads,ack_cpu,ack_vsd,ack_rsd,ack_src,ack_iol,overlap_hits,aborted);
    $display("PASS ROM cache bits=%0d: all byte values, tag/index collisions, partial IOL writes, fill/write collision, reset phases, held payload, all clients, registered hits",BITS);
    finished=1;
  end
endmodule
module tb_rom_cache;
  wire d0,d6;
  cache_case #(.BITS(0)) old_path(d0);
  cache_case #(.BITS(6)) new_path(d6);
  initial begin wait(d0&&d6);$display("ALL PASS ROM cache prototype");$finish;end
  initial begin #100000000;$fatal(1,"Global timeout");end
endmodule

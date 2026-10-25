`timescale 1ns/1ps
module tb_loading;
    reg clk=0,reset=1;
    always #62.5 clk=~clk;
    reg [6:0] percent=0;
    reg fault=0;
    wire [23:0] rgb;
    wire hs,vs,de;
    wolf_pocket_loading #(.ART_FILE("src/rtl/openice_loading.hex")) dut(
        .clk_pixel(clk),.reset(reset),.percent(percent),.fault(fault),
        .rgb(rgb),.hs(hs),.vs(vs),.de(de));
    integer tick=0,last_hs=-1,last_vs=-1,hs_high=0,vs_high=0,active_run=0;
    reg old_hs=0,old_vs=0,old_de=0;
    always @(posedge clk) begin
        #1;
        tick=tick+1;
        if(reset) begin
            if({rgb,hs,vs,de}!==27'd0)$fatal(1,"Outputs not zero in reset");
            last_hs=-1;last_vs=-1;hs_high=0;vs_high=0;active_run=0;
            old_hs=0;old_vs=0;old_de=0;
        end else begin
            if($isunknown({rgb,hs,vs,de}))$fatal(1,"Unknown video output");
            if(!de && rgb!=0)$fatal(1,"Nonblack blanking");
            if(hs && !old_hs) begin
                if(last_hs>=0 && tick-last_hs!=506)$fatal(1,"Line period %0d",tick-last_hs);
                last_hs=tick;
            end
            if(vs && !old_vs) begin
                if(last_vs>=0 && tick-last_vs!=146234)$fatal(1,"Frame period %0d",tick-last_vs);
                last_vs=tick;
            end
            if(hs)hs_high=hs_high+1;
            if(!hs && old_hs)begin
                if(hs_high!=43)$fatal(1,"HS width %0d",hs_high);
                hs_high=0;
            end
            if(vs)vs_high=vs_high+1;
            if(!vs && old_vs)begin
                if(vs_high!=1518)$fatal(1,"VS width %0d",vs_high);
                vs_high=0;
            end
            if(de)active_run=active_run+1;
            if(!de && old_de)begin
                if(active_run!=400)$fatal(1,"Active width %0d",active_run);
                active_run=0;
            end
            old_hs=hs;old_vs=vs;old_de=de;
        end
    end
    task automatic capture(input integer p,input bit f,input string name);
        integer fd,count,fill_count,red_count,lines;
        reg previous_de;
        begin
            @(negedge clk);percent=7'(p);fault=f;
            @(posedge vs);@(negedge vs);@(posedge vs);@(negedge vs);
            fd=$fopen({"build/loading-tests/",name,".ppm"},"wb");
            if(!fd)$fatal(1,"Cannot open screenshot");
            $fwrite(fd,"P6\n400 254\n255\n");
            count=0;fill_count=0;red_count=0;lines=0;previous_de=0;
            while(count<101600)begin
                @(negedge clk);
                if(de)begin
                    $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                    count=count+1;
                    if(rgb==24'h40c8e8)fill_count=fill_count+1;
                    if(rgb==24'hc83838)red_count=red_count+1;
                    if(!previous_de)lines=lines+1;
                end
                previous_de=de;
            end
            $fclose(fd);
            if(lines!=254)$fatal(1,"Active height %0d",lines);
            if(!f && fill_count!=12*(p>100 ? 100:p))$fatal(1,"Bar area %0d for %0d",fill_count,p);
            if(f && red_count!=12*(p>100 ? 100:p))$fatal(1,"Fault bar area %0d for %0d",red_count,p);
            $display("PASS frame %s percent=%0d fault=%0d active=%0d lines=%0d fill=%0d red=%0d",name,p,f,count,lines,fill_count,red_count);
        end
    endtask
    task automatic coherent_change;
        integer count,changed_pixels;
        begin
            @(negedge clk);percent=0;fault=0;
            @(posedge vs);@(negedge vs);@(posedge vs);@(negedge vs);
            count=0;changed_pixels=0;
            while(count<101600)begin
                @(negedge clk);
                if(de)begin
                    count=count+1;
                    // Change both inputs after half the active image. The
                    // current frame must still render its 0%, nonfault label.
                    if(count==50000)begin percent=42;fault=1;end
                    if(rgb==24'h40c8e8 || rgb==24'hc83838 || rgb==24'hff7777)
                        changed_pixels=changed_pixels+1;
                end
            end
            if(changed_pixels!=0)$fatal(1,"Status changed partway through frame");
            $display("PASS frame-coherent percent/fault input changes");
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);reset=0;
        capture(0,0,"loading-000");capture(1,0,"loading-001");
        capture(9,0,"loading-009");capture(10,0,"loading-010");
        capture(42,0,"loading-042");capture(99,0,"loading-099");
        capture(100,0,"loading-100");capture(127,0,"loading-clamp");
        coherent_change();
        capture(42,1,"loading-fault");
        @(negedge clk);reset=1;
        repeat(4)@(negedge clk);reset=0;
        capture(0,0,"loading-reset");
        $display("PASS loading renderer timing, artwork stream, progress bounds, fault and reset");
        $finish;
    end
    initial begin #1000000000; $fatal(1,"Timeout"); end
endmodule

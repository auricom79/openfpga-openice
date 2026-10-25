`timescale 1ns/1ps
module tb_display_integration;
    reg cb=0;
    always #6.734 cb=~cb;
    reg [31:0] addr=0,wd=0;
    reg wr=0,rd=0;
    wire [31:0] q;
    wire [23:0] rgb;
    wire pclk,pclk90,hs,vs,de;
    core_top dut(.clk_74a(cb),.clk_74b(cb),.bridge_addr(addr),.bridge_wr_data(wd),
        .bridge_wr(wr),.bridge_rd(rd),.bridge_rd_data(q),
        .video_rgb(rgb),.video_rgb_clock(pclk),.video_rgb_clock_90(pclk90),
        .video_hs(hs),.video_vs(vs),.video_de(de),
        .cont1_key(32'd0),.cont2_key(32'd0),.cont3_key(32'd0),.cont4_key(32'd0));
    defparam dut.loader.PROGRAM_BYTES=4096;
    defparam dut.loader.GRAPHICS_BYTES=4096;
    defparam dut.loader.SOUND_BYTES=4096;
    defparam dut.loading_screen.ART_FILE="src/rtl/openice_loading.hex";
    integer pixels=0,loading_pixels=0,loading_nonblack=0,loading_frames=0;
    integer switched=0,full_percent_loading_pixels=0,game_pixels=0;
    realtime last_pixel=0;
    reg last_show=1,selected_de,selected_hs,selected_vs,previous_hs=0,previous_vs=0;
    reg [23:0] selected_rgb;
    reg at_game_vsync,selected_ready;
    always @(posedge pclk) begin
        pixels++;
        if(last_pixel>0 && $realtime-last_pixel!=125.0) $fatal(1,"Pixel clock interrupted");
        last_pixel=$realtime;
        selected_rgb=dut.show_loading ? dut.loading_rgb : {dut.r,dut.g,dut.b};
        selected_de=dut.show_loading ? dut.loading_de : dut.de;
        selected_hs=dut.show_loading ? dut.loading_hs : dut.hs;
        selected_vs=dut.show_loading ? dut.loading_vs : dut.vs;
        at_game_vsync=dut.vs && !dut.prev_game_vs;
        selected_ready=dut.ready_pixel_sync;
        if(!dut.por_pixel[2]) begin
            if(dut.show_loading && selected_de) begin
                loading_pixels++;
                if(selected_rgb!=0) loading_nonblack++;
                if(dut.progress_pixel==100) full_percent_loading_pixels++;
            end
            if(!dut.show_loading && selected_de) game_pixels++;
            if(dut.show_loading && selected_vs && !previous_vs) loading_frames++;
        end
        #1;
        if(!dut.por_pixel[2]) begin
            if(!selected_ready && !dut.show_loading) $fatal(1,"Game remains selected after sampled readiness drops");
            if(rgb!==(selected_de ? selected_rgb : 24'd0) || de!==selected_de ||
               hs!==(selected_hs && !previous_hs) || vs!==(selected_vs && !previous_vs))
                $fatal(1,"Mux/APF pixel pipeline mismatch");
            if(last_show && !dut.show_loading) begin
                switched++;
                if(!at_game_vsync || dut.progress_pixel!=100 || !dut.ready_pixel_sync)
                    $fatal(1,"Handoff was not at ready game VS after 100 percent");
            end
            previous_hs=selected_hs;previous_vs=selected_vs;
        end else begin previous_hs=0;previous_vs=0;end
        last_show=dut.show_loading;
    end
    task automatic w(input [31:0] a,d);
        @(negedge cb);addr=a;wd=d;wr=1;
        @(negedge cb);wr=0;
        repeat(4) @(negedge cb);
    endtask
    task automatic r(input [31:0] a,output [31:0] d);
        @(negedge cb);addr=a;rd=1;
        repeat(4) @(negedge cb);
        d=q;rd=0;
    endtask
    task automatic command(input [15:0] c,input [31:0] expected);
        reg [31:0] d;
        w(32'hf8000000,{16'h434d,c});r(32'hf8000000,d);
        if(d!==expected) $fatal(1,"Host command %h returned %h expected %h",c,d,expected);
    endtask
    task automatic wait_target(input [31:0] c);
        reg [31:0] d;
        do r(32'hf8001000,d);while(d!=c);
    endtask
    reg [31:0] value;
    initial begin
        wait(!dut.por_bridge[2]);repeat(12) @(negedge cb);
        command(16'h0000,32'h4f4b0003);
        // Leave ROM loading idle for more than two complete visible frames.
        repeat(320000) @(negedge pclk);
        if(loading_frames<2 || loading_nonblack<10000 || !dut.load_active || !dut.show_loading || dut.game_ready)
            $fatal(1,"Loading title absent while CPU held in reset");
        for(integer slot=0;slot<3;slot++) begin
            w(32'hf8000020,slot);w(32'hf8000024,4096);
            command(16'h0082,32'h4f4b0000);
            w(32'hf8002000+slot*8,slot);w(32'hf8002004+slot*8,4096);
        end
        command(16'h008f,32'h4f4b0000);
        wait_target(32'h636d0140);w(32'hf8001000,32'h6f6b0000);
        command(16'h0011,32'h4f4b0000);
        for(integer slot=0;slot<3;slot++) begin
            wait_target(32'h636d0180);
            r(32'hf8001020,value);if(value!=slot) $fatal(1,"Wrong slot");
            r(32'hf800102c,value);if(value!=4096) $fatal(1,"Wrong chunk size");
            w(32'hf8001000,32'h62750000);
            for(integer n=0;n<4096;n+=4) w(32'h10000000+n,32'(n));
            w(32'hf8001000,32'h6f6b0000);
        end
        wait(dut.loader_done);
        repeat(8) @(negedge pclk);
        if(dut.progress_pixel!=100 || !dut.show_loading || !dut.game_ready)
            $fatal(1,"Expected visible loading at 100 before first game VS");
        wait(!dut.show_loading);
        repeat(1000) @(negedge pclk);
        if(switched!=1 || full_percent_loading_pixels<10000 || game_pixels<10)
            $fatal(1,"Handoff coverage missing switched=%0d progress100=%0d game=%0d",switched,full_percent_loading_pixels,game_pixels);
        command(16'h0010,32'h4f4b0000);
        repeat(12) @(negedge pclk);
        if(!dut.show_loading || !dut.loader_done || dut.progress_pixel!=100)
            $fatal(1,"Framework reset failed to restore loading without losing ROM state");
        $display("PASS real core_top integration: title during reset, continuous pixel clock, strict APF load,100percent wait, game VS handoff, exact pixel/sync pipeline, reset preserves assets");
        $finish;
    end
    initial begin #150000000;$fatal(1,"Display integration timeout");end
endmodule

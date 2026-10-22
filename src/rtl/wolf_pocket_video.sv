// SPDX-License-Identifier: MIT
// Related PLL clocks: Wolf advances at 8 MHz CE within its 80 MHz domain.
// Sample the settled pixel at the next 8 MHz edge, then convert level sync to
// single-cycle APF pulses. Keep the video clock running throughout reset.
`default_nettype none
// Both PLL outputs have the same nominal rising phase and an exact 10:1 ratio.
// Sample on the opposite system edge so neither pixel transition coincides
// with the capture edge. The registered level detector then gives Wolf one
// full system-cycle CE, consumed 12.5 ns after each pixel rising edge. RGB is
// captured at the following pixel edge. These are related clocks in STA.
module wolf_pocket_pixel_enable(
    input wire clk_sys, clk_pixel,
    output wire ce_pix
);
    reg pixel_sample=0, ce_pix_r=0;
    always @(negedge clk_sys) begin
        pixel_sample<=clk_pixel;
        ce_pix_r<=clk_pixel && !pixel_sample;
    end
    assign ce_pix=ce_pix_r;
endmodule

module wolf_pocket_video(
    input wire clk_pixel, reset,
    input wire [7:0] r,g,b,
    input wire hs,vs,de,
    output reg [23:0] rgb=0,
    output reg apf_hs=0,apf_vs=0,apf_de=0
);
    reg prev_hs=0,prev_vs=0;
    always @(posedge clk_pixel) begin
        prev_hs<=hs; prev_vs<=vs;
        rgb<=de ? {r,g,b} : 24'd0;
        apf_hs<=hs && !prev_hs;
        apf_vs<=vs && !prev_vs;
        apf_de<=de;
        if(reset) begin
            rgb<=0; apf_hs<=0; apf_vs<=0; apf_de<=0;
            prev_hs<=0;prev_vs<=0;
        end
    end
endmodule
`default_nettype wire

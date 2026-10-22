// SPDX-License-Identifier: MIT
// Requested PLL configuration, pending Quartus fitting and hardware validation.
`default_nettype none
module wolf_pocket_pll(
    input wire refclk,
    output wire clk_sys,clk_sdram,clk_pixel,clk_pixel_90,locked
);
    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("normal"),.number_of_clocks(4),
        .output_clock_frequency0("80 MHz"),.phase_shift0("0 ps"),.duty_cycle0(50),
        // Quartus 18.1 reports nonnegative, quantized legal counter phases.
        // 8984 ps is the supported step nearest -3500 ps modulo 12500 ps.
        .output_clock_frequency1("80 MHz"),.phase_shift1("8984 ps"),.duty_cycle1(50),
        .output_clock_frequency2("8 MHz"),.phase_shift2("0 ps"),.duty_cycle2(50),
        .output_clock_frequency3("8 MHz"),.phase_shift3("31250 ps"),.duty_cycle3(50),
        .pll_type("General"),.pll_subtype("General")
    ) pll (.refclk(refclk),.rst(1'b0),.outclk({clk_pixel_90,clk_pixel,clk_sdram,clk_sys}),
           .locked(locked),.fbclk(1'b0),.fboutclk());
endmodule
`default_nettype wire

// SPDX-License-Identifier: MIT
// DCS PM/DM with explicit same-cycle input AND core clock enables.
// One write/read port A plus one independent synchronous read port B.
module dcs_ce_ram #(
    parameter integer WIDTH=24,
    parameter integer READ_WRITE_A=1,
    parameter SIM_INIT=""
)(
    input wire clk, ce, write_enable,
    input wire [13:0] address_a, address_b,
    input wire [WIDTH-1:0] write_data,
    output wire [WIDTH-1:0] q_a, q_b
);
`ifdef SYNTHESIS
`ifndef DCS_BEHAVIORAL_SIM
`define DCS_RAM_USE_ALTSYNCRAM
`endif
`endif
`ifdef DCS_VENDOR_SIM
`define DCS_RAM_USE_ALTSYNCRAM
`endif
`ifdef DCS_RAM_USE_ALTSYNCRAM
    altsyncram #(
        .intended_device_family("Cyclone V"), .lpm_type("altsyncram"),
        .ram_block_type("M10K"),
        .operation_mode(READ_WRITE_A ? "BIDIR_DUAL_PORT" : "DUAL_PORT"),
        .width_a(WIDTH),.widthad_a(14),.numwords_a(16384),
        .width_b(WIDTH),.widthad_b(14),.numwords_b(16384),
        .width_byteena_a(1),.width_byteena_b(1),
        .outdata_reg_a("UNREGISTERED"),.outdata_reg_b("UNREGISTERED"),
        .address_reg_b("CLOCK1"),.indata_reg_b("CLOCK1"),.wrcontrol_wraddress_reg_b("CLOCK1"),
        .clock_enable_input_a("NORMAL"),.clock_enable_core_a("NORMAL"),
        .clock_enable_input_b("NORMAL"),.clock_enable_core_b("NORMAL"),
        .clock_enable_output_a("BYPASS"),.clock_enable_output_b("BYPASS"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("FALSE"),.init_file("UNUSED")
    ) ram (
        .clock0(clk),.clock1(clk),.clocken0(ce),.clocken1(ce),.clocken2(1'b1),.clocken3(1'b1),
        .aclr0(1'b0),.aclr1(1'b0),
        .address_a(address_a),.data_a(write_data),.wren_a(write_enable),.rden_a(1'b1),.byteena_a(1'b1),
        .address_b(address_b),.data_b({WIDTH{1'b0}}),.wren_b(1'b0),.rden_b(1'b1),.byteena_b(1'b1),
        .addressstall_a(1'b0),.addressstall_b(1'b0),.q_a(q_a),.q_b(q_b),.eccstatus()
    );
`else
    reg [WIDTH-1:0] mem[0:16383];
    reg [WIDTH-1:0] read_a=0,read_b=0;
    integer init_i;
    initial begin
        for(init_i=0;init_i<16384;init_i=init_i+1) mem[init_i]=0;
        if(SIM_INIT!="")$readmemh(SIM_INIT,mem);
    end
    always @(posedge clk) if(ce) begin
        if(write_enable)mem[address_a]<=write_data;
        // Write-cycle A output and simultaneous B read/write collisions are
        // unconsumed by the ADSP. Keep reference old-data behavior in simulation.
        if(READ_WRITE_A)read_a<=mem[address_a];
        read_b<=mem[address_b];
    end
    assign q_a=read_a;
    assign q_b=read_b;
`endif
`ifdef DCS_RAM_USE_ALTSYNCRAM
`undef DCS_RAM_USE_ALTSYNCRAM
`endif
endmodule

module mf_datatable(input wire [7:0] address_a,address_b,
    input wire clock_a,clock_b,input wire [31:0] data_a,data_b,
    input wire wren_a,wren_b,output reg [31:0] q_a,q_b);
    reg [31:0] ram[0:255];
    always @(posedge clock_a) begin if(wren_a) ram[address_a]<=data_a;q_a<=ram[address_a];end
    always @(posedge clock_b) begin if(wren_b) ram[address_b]<=data_b;q_b<=ram[address_b];end
endmodule

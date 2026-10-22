`default_nettype none
`default_nettype wire
`default_nettype none
`default_nettype wire
`default_nettype none
`default_nettype wire
`default_nettype none
module tms34010_alu (
	op,
	a,
	b,
	cin,
	result,
	flags
);
	reg _sv2v_0;
	parameter [0:0] SHARED_ADDER = 1'b1;
	input wire [3:0] op;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	input wire [31:0] a;
	input wire [31:0] b;
	input wire cin;
	output reg [31:0] result;
	output reg [3:0] flags;
	wire [tms34010_pkg_DATA_WIDTH:0] add_ext;
	wire [tms34010_pkg_DATA_WIDTH:0] sub_ext;
	wire [31:0] not_b;
	wire add_cin;
	wire sub_cin;
	assign not_b = ~b;
	assign add_cin = (op == 4'd1 ? cin : 1'b0);
	assign sub_cin = (op == 4'd3 ? !cin : 1'b1);
	wire shared_negate = (op == 4'd10) || (op == 4'd13);
	wire shared_subtract = ((shared_negate || (op == 4'd2)) || (op == 4'd3)) || (op == 4'd4);
	wire [31:0] shared_a = (shared_negate ? {32 {1'sb0}} : a);
	wire [31:0] shared_b = (shared_subtract ? ~(shared_negate ? a : b) : b);
	wire shared_cin = (shared_subtract ? sub_cin : add_cin);
	wire [tms34010_pkg_DATA_WIDTH:0] shared_sum = ({1'b0, shared_a} + {1'b0, shared_b}) + {{tms34010_pkg_DATA_WIDTH {1'b0}}, shared_cin};
	assign add_ext = (SHARED_ADDER ? shared_sum : ({1'b0, a} + {1'b0, b}) + {{tms34010_pkg_DATA_WIDTH {1'b0}}, add_cin});
	assign sub_ext = (SHARED_ADDER ? shared_sum : ({1'b0, a} + {1'b0, not_b}) + {{tms34010_pkg_DATA_WIDTH {1'b0}}, sub_cin});
	wire [31:0] add_result;
	wire [31:0] sub_result;
	wire [31:0] neg_result;
	wire [tms34010_pkg_DATA_WIDTH:0] neg_ext;
	wire [31:0] not_a;
	assign add_result = add_ext[31:0];
	assign sub_result = sub_ext[31:0];
	assign not_a = ~a;
	assign neg_ext = (SHARED_ADDER ? shared_sum : ({1'b0, {tms34010_pkg_DATA_WIDTH {1'b0}}} + {1'b0, not_a}) + 33'd1);
	assign neg_result = neg_ext[31:0];
	always @(*) begin
		if (_sv2v_0)
			;
		result = 1'sb0;
		flags[3] = 1'b0;
		flags[2] = 1'b0;
		flags[1] = 1'b0;
		flags[0] = 1'b0;
		(* full_case, parallel_case *)
		case (op)
			4'd0, 4'd1: begin
				result = add_result;
				flags[3] = add_result[31];
				flags[1] = add_result == {32 {1'sb0}};
				flags[2] = add_ext[tms34010_pkg_DATA_WIDTH];
				flags[0] = (a[31] == b[31]) && (add_result[31] != a[31]);
			end
			4'd2, 4'd3, 4'd4: begin
				result = sub_result;
				flags[3] = sub_result[31];
				flags[1] = sub_result == {32 {1'sb0}};
				flags[2] = b > a;
				flags[0] = (a[31] != b[31]) && (sub_result[31] != a[31]);
			end
			4'd10: begin
				result = neg_result;
				flags[3] = neg_result[31];
				flags[1] = neg_result == {32 {1'sb0}};
				flags[2] = !neg_ext[tms34010_pkg_DATA_WIDTH];
				flags[0] = a[31] && neg_result[31];
			end
			4'd5: begin
				result = a & b;
				flags[3] = result[31];
				flags[1] = result == {32 {1'sb0}};
			end
			4'd6: begin
				result = a & ~b;
				flags[3] = result[31];
				flags[1] = result == {32 {1'sb0}};
			end
			4'd7: begin
				result = a | b;
				flags[3] = result[31];
				flags[1] = result == {32 {1'sb0}};
			end
			4'd8: begin
				result = a ^ b;
				flags[3] = result[31];
				flags[1] = result == {32 {1'sb0}};
			end
			4'd9: begin
				result = ~a;
				flags[3] = result[31];
				flags[1] = result == {32 {1'sb0}};
			end
			4'd11: begin
				result = a;
				flags[3] = a[31];
				flags[1] = a == {32 {1'sb0}};
			end
			4'd12: begin
				result = b;
				flags[3] = b[31];
				flags[1] = b == {32 {1'sb0}};
			end
			4'd13: begin
				result = (neg_result[31] ? a : neg_result);
				flags[3] = neg_result[31];
				flags[1] = a == {32 {1'sb0}};
				flags[2] = 1'b0;
				flags[0] = a == 32'h80000000;
			end
			default:
				;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_core (
	clk,
	ce_cpu,
	ce_pix,
	rst,
	mem_req,
	mem_we,
	mem_addr,
	mem_size,
	mem_wdata,
	mem_srt,
	mem_rdata,
	mem_ack,
	state_o,
	pc_o,
	instr_word_o,
	illegal_opcode_o,
	dpystrt_o,
	dpyadr_o,
	vblank_start_o,
	heblnk_o,
	hsblnk_o,
	veblnk_o,
	vsblnk_o,
	lint1_in
);
	reg _sv2v_0;
	parameter [0:0] SHARED_XY_ARITH = 1'b1;
	parameter [0:0] SHARED_WINDOW = 1'b1;
	parameter [0:0] SHARED_ADDRESS = 1'b1;
	parameter [0:0] SHARED_PIXEL = 1'b1;
	parameter [0:0] SHARED_XY = 1'b1;
	parameter [0:0] SHARED_GRAPHICS_REGS = 1'b1;
	parameter [0:0] MLAB_REGFILE = 1'b1;
	parameter [0:0] IO_CPU_CE = 1'b1;
	parameter [0:0] LOCAL_IO_WRITE = 1'b0;
	input wire clk;
	input wire ce_cpu;
	input wire ce_pix;
	input wire rst;
	output wire mem_req;
	output wire mem_we;
	localparam [31:0] tms34010_pkg_ADDR_WIDTH = 32;
	output reg [31:0] mem_addr;
	localparam [31:0] tms34010_pkg_FIELD_SIZE_WIDTH = 6;
	output reg [5:0] mem_size;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	output reg [31:0] mem_wdata;
	output reg mem_srt;
	input wire [31:0] mem_rdata;
	input wire mem_ack;
	output wire [5:0] state_o;
	output wire [31:0] pc_o;
	localparam [31:0] tms34010_pkg_INSTR_WORD_WIDTH = 16;
	output wire [15:0] instr_word_o;
	output wire illegal_opcode_o;
	output wire [15:0] dpystrt_o;
	output wire [15:0] dpyadr_o;
	output wire vblank_start_o;
	output wire [15:0] heblnk_o;
	output wire [15:0] hsblnk_o;
	output wire [15:0] veblnk_o;
	output wire [15:0] vsblnk_o;
	input wire lint1_in;
	reg pblt_w2_q;
	reg pblt_w1_q;
	wire pblt_array_hit;
	reg [1:0] drav_w_q;
	reg drav_inside_q;
	reg line_last_inside_q;
	reg line_aborted_q;
	wire line_win_en;
	wire [31:0] rf_rs1_data;
	wire [31:0] rf_rs2_data;
	wire [31:0] rf_rs3_data;
	wire is_fill;
	wire fill_is_xy;
	wire is_pblt;
	wire is_drav;
	wire is_line;
	wire pixt_rmw;
	reg [31:0] pix_dest_q;
	wire pixt_xy_win;
	reg pixt_inside_q;
	reg [4:0] pix_xy_xsh;
	wire [31:0] pix_xy_dst_linear;
	wire is_mpy;
	wire mpy_signed;
	wire mpy_rd_even;
	wire is_div;
	wire is_divu;
	wire is_modu;
	wire is_divs;
	wire is_mods;
	wire div_signed_ovf;
	wire div_v;
	wire is_pair_wb;
	wire pair_second_pass;
	reg pair_wb_step;
	wire [15:0] io_psize;
	wire [15:0] io_convdp;
	wire [15:0] io_convsp;
	wire [15:0] io_control;
	wire [15:0] io_pmask;
	wire wvp_set;
	wire [31:0] mem_rdata_eff;
	reg mem_read_active;
	reg int_push_q;
	function automatic [31:0] ppop_apply;
		input reg [31:0] src;
		input reg [31:0] dest;
		input reg [4:0] ppop;
		input reg [31:0] fmask;
		reg [31:0] sp;
		reg [31:0] dp;
		reg [31:0] addsum;
		begin
			sp = src & fmask;
			dp = dest & fmask;
			addsum = dp + sp;
			(* full_case, parallel_case *)
			case (ppop)
				5'h00: ppop_apply = src;
				5'h01: ppop_apply = src & dest;
				5'h02: ppop_apply = src & ~dest;
				5'h03: ppop_apply = 1'sb0;
				5'h04: ppop_apply = src | ~dest;
				5'h05: ppop_apply = ~(src ^ dest);
				5'h06: ppop_apply = ~dest;
				5'h07: ppop_apply = ~(src | dest);
				5'h08: ppop_apply = src | dest;
				5'h09: ppop_apply = dest;
				5'h0a: ppop_apply = src ^ dest;
				5'h0b: ppop_apply = ~src & dest;
				5'h0c: ppop_apply = 1'sb1;
				5'h0d: ppop_apply = ~src | dest;
				5'h0e: ppop_apply = ~(src & dest);
				5'h0f: ppop_apply = ~src;
				5'h10: ppop_apply = addsum;
				5'h11: ppop_apply = (addsum > fmask ? fmask : addsum);
				5'h12: ppop_apply = dp - sp;
				5'h13: ppop_apply = (dp >= sp ? dp - sp : {32 {1'sb0}});
				5'h14: ppop_apply = (dp >= sp ? dp : sp);
				5'h15: ppop_apply = (dp <= sp ? dp : sp);
				default: ppop_apply = src;
			endcase
		end
	endfunction
	reg pc_advance_en;
	reg pc_load_en;
	reg [31:0] pc_load_value;
	wire [31:0] pc_value;
	localparam [5:0] tms34010_pkg_INSTR_WORD_BITS = 6'd16;
	localparam [31:0] tms34010_pkg_PC_ADVANCE_WIDTH = 8;
	function automatic [7:0] sv2v_cast_4E301;
		input reg [7:0] inp;
		sv2v_cast_4E301 = inp;
	endfunction
	tms34010_pc u_pc(
		.clk(clk),
		.ce_cpu(ce_cpu),
		.rst(rst),
		.load_en(pc_load_en),
		.load_value(pc_load_value),
		.advance_en(pc_advance_en),
		.advance_amount(sv2v_cast_4E301(tms34010_pkg_INSTR_WORD_BITS)),
		.pc_o(pc_value)
	);
	reg [5:0] state_q;
	reg [5:0] state_d;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				state_q <= 6'd0;
			else
				state_q <= state_d;
		end
	reg [15:0] instr_word_q;
	wire [52:0] decoded;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				instr_word_q <= 1'sb0;
			else if ((state_q == 6'd1) && mem_ack)
				instr_word_q <= mem_rdata_eff[15:0];
		end
	tms34010_decode u_decode(
		.instr(instr_word_q),
		.decoded(decoded)
	);
	reg illegal_q;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				illegal_q <= 1'b0;
			else if ((state_q == 6'd2) && decoded[52])
				illegal_q <= 1'b1;
		end
	wire [31:0] shared_address_sum;
	wire [31:0] branch_target_short;
	wire signed [15:0] disp_signed_12;
	assign disp_signed_12 = $signed({instr_word_q[7:0], 4'h0});
	function automatic signed [31:0] sv2v_cast_DEBC9_signed;
		input reg signed [31:0] inp;
		sv2v_cast_DEBC9_signed = inp;
	endfunction
	assign branch_target_short = (SHARED_ADDRESS ? shared_address_sum : pc_value + sv2v_cast_DEBC9_signed(disp_signed_12));
	reg [15:0] imm_lo_q;
	reg [15:0] imm_hi_q;
	reg [15:0] imm2_lo_q;
	reg [15:0] imm2_hi_q;
	wire [31:0] imm2_32 = {imm2_hi_q, imm2_lo_q};
	wire is_mv_abs_m2m = decoded[51-:7] == 7'd99;
	wire is_mv_off_m2m = decoded[51-:7] == 7'd100;
	wire [31:0] imm2_off_sext = {{tms34010_pkg_DATA_WIDTH - tms34010_pkg_INSTR_WORD_WIDTH {imm2_lo_q[15]}}, imm2_lo_q};
	wire [31:0] branch_target_long;
	wire signed [19:0] disp_signed_20;
	assign disp_signed_20 = $signed({imm_lo_q, 4'h0});
	assign branch_target_long = (SHARED_ADDRESS ? shared_address_sum : pc_value + sv2v_cast_DEBC9_signed(disp_signed_20));
	wire [31:0] branch_target_jacc;
	assign branch_target_jacc = {imm_hi_q, imm_lo_q[15:4], 4'h0};
	wire [31:0] branch_target_dsjs;
	wire signed [9:0] dsjs_disp_bits;
	function automatic signed [9:0] sv2v_cast_10_signed;
		input reg signed [9:0] inp;
		sv2v_cast_10_signed = inp;
	endfunction
	assign dsjs_disp_bits = (instr_word_q[10] ? -sv2v_cast_10_signed($signed({1'b0, instr_word_q[9:5], 4'h0})) : sv2v_cast_10_signed($signed({1'b0, instr_word_q[9:5], 4'h0})));
	assign branch_target_dsjs = (SHARED_ADDRESS ? shared_address_sum : pc_value + sv2v_cast_DEBC9_signed(dsjs_disp_bits));
	reg [1:0] mem_op_step;
	reg [31:0] popped_st_q;
	reg [31:0] popped_pc_q;
	reg [31:0] move_data_q;
	reg [31:0] mv_load_data_q;
	wire trap_skip_push;
	assign trap_skip_push = (decoded[51-:7] == 7'd71) && (decoded[23-:5] == 5'd0);
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				mem_op_step <= 2'd0;
				popped_st_q <= 1'sb0;
				popped_pc_q <= 1'sb0;
				move_data_q <= 1'sb0;
				pix_dest_q <= 1'sb0;
			end
			else if ((state_q == 6'd6) && mem_ack) begin
				if ((decoded[51-:7] == 7'd76) && (mem_op_step == 2'd0))
					move_data_q <= mem_rdata_eff;
				if (((((decoded[51-:7] == 7'd99) || (decoded[51-:7] == 7'd100)) || (decoded[51-:7] == 7'd101)) || (decoded[51-:7] == 7'd102)) && (mem_op_step == 2'd0))
					move_data_q <= mem_rdata_eff;
				if (((decoded[51-:7] == 7'd74) && pixt_rmw) && (mem_op_step == 2'd0))
					pix_dest_q <= mem_rdata_eff;
				if (decoded[51-:7] == 7'd70) begin
					if (mem_op_step == 2'd0)
						popped_st_q <= mem_rdata_eff;
					if (mem_op_step == 2'd1)
						popped_pc_q <= mem_rdata_eff;
				end
				if (decoded[51-:7] == 7'd65)
					popped_st_q <= mem_rdata_eff;
				if (decoded[51-:7] == 7'd67)
					popped_pc_q <= mem_rdata_eff;
				if (decoded[51-:7] == 7'd71) begin
					if (trap_skip_push) begin
						if (mem_op_step == 2'd0)
							popped_pc_q <= mem_rdata_eff;
					end
					else if (mem_op_step == 2'd2)
						popped_pc_q <= mem_rdata_eff;
				end
				(* full_case, parallel_case *)
				case (decoded[51-:7])
					7'd70: mem_op_step <= (mem_op_step == 2'd1 ? 2'd0 : mem_op_step + 2'd1);
					7'd71: mem_op_step <= (trap_skip_push || (mem_op_step == 2'd2) ? 2'd0 : mem_op_step + 2'd1);
					7'd76, 7'd99, 7'd100, 7'd101, 7'd102: mem_op_step <= (mem_op_step == 2'd1 ? 2'd0 : mem_op_step + 2'd1);
					7'd74: mem_op_step <= (pixt_rmw && (mem_op_step == 2'd0) ? 2'd1 : 2'd0);
					default: mem_op_step <= 2'd0;
				endcase
			end
			else if ((state_q == 6'd19) && mem_ack) begin
				popped_pc_q <= mem_rdata_eff;
				mem_op_step <= 2'd0;
			end
			else if (state_q != 6'd6)
				mem_op_step <= 2'd0;
		end
	reg [31:0] fill_dptch_q;
	reg [31:0] fill_color_q;
	reg [31:0] fill_daddr_raw_q;
	reg [15:0] fill_dx_q;
	reg [15:0] fill_dy_q;
	reg [31:0] fill_addr_q;
	reg [31:0] fill_row_base_q;
	reg [15:0] fill_x_q;
	reg [15:0] fill_y_q;
	wire [31:0] fill_psize_ext;
	wire fill_row_end;
	wire fill_done;
	function automatic [31:0] sv2v_cast_DEBC9;
		input reg [31:0] inp;
		sv2v_cast_DEBC9 = inp;
	endfunction
	assign fill_psize_ext = sv2v_cast_DEBC9(io_psize[5:0]);
	assign fill_row_end = fill_x_q == (fill_dx_q - 16'd1);
	assign fill_done = fill_row_end && (fill_y_q == (fill_dy_q - 16'd1));
	wire [4:0] fill_xy_yshift;
	wire [31:0] fill_xy_linear;
	wire [31:0] fill_start;
	assign fill_xy_yshift = 5'd31 - io_convdp[4:0];
	wire [31:0] shared_xy0_result;
	assign fill_xy_linear = (SHARED_XY ? shared_xy0_result : (({{16 {fill_daddr_raw_q[31]}}, fill_daddr_raw_q[31:16]} << fill_xy_yshift) | ({16'b0000000000000000, fill_daddr_raw_q[15:0]} << pix_xy_xsh)) + rf_rs3_data);
	assign fill_start = (fill_is_xy ? fill_xy_linear : fill_daddr_raw_q);
	wire shared_window_inside;
	reg fill_substep_q;
	reg [31:0] fill_dest_q;
	wire [31:0] fill_pixel_mask;
	wire [31:0] fill_pmask_field;
	wire [31:0] fill_processed;
	wire [31:0] fill_merged;
	wire fill_transp;
	reg [31:0] fill_wstart_q;
	reg [31:0] fill_wend_q;
	reg fill_win_en_q;
	reg fill_w2_q;
	wire [15:0] fill_px;
	wire [15:0] fill_py;
	wire fill_in_window;
	wire fill_clip_out;
	assign fill_px = fill_daddr_raw_q[15:0] + fill_x_q;
	assign fill_py = fill_daddr_raw_q[31:16] + fill_y_q;
	assign fill_in_window = (SHARED_WINDOW ? shared_window_inside : (((fill_px >= fill_wstart_q[15:0]) && (fill_px <= fill_wend_q[15:0])) && (fill_py >= fill_wstart_q[31:16])) && (fill_py <= fill_wend_q[31:16]));
	assign fill_clip_out = fill_win_en_q && !fill_in_window;
	wire fill_array_inside;
	wire [15:0] fill_arr_x0;
	wire [15:0] fill_arr_y0;
	wire [15:0] fill_arr_x1;
	wire [15:0] fill_arr_y1;
	assign fill_arr_x0 = fill_daddr_raw_q[15:0];
	assign fill_arr_y0 = fill_daddr_raw_q[31:16];
	assign fill_arr_x1 = (fill_arr_x0 + fill_dx_q) - 16'd1;
	assign fill_arr_y1 = (fill_arr_y0 + fill_dy_q) - 16'd1;
	assign fill_array_inside = (SHARED_WINDOW ? shared_window_inside : (((fill_arr_x0 >= rf_rs1_data[15:0]) && (fill_arr_x1 <= rf_rs2_data[15:0])) && (fill_arr_y0 >= rf_rs1_data[31:16])) && (fill_arr_y1 <= rf_rs2_data[31:16]));
	reg fill_w1_q;
	wire fill_array_hit;
	assign fill_array_hit = (SHARED_WINDOW ? shared_window_inside : !((((fill_arr_x1 < fill_wstart_q[15:0]) || (fill_arr_x0 > fill_wend_q[15:0])) || (fill_arr_y1 < fill_wstart_q[31:16])) || (fill_arr_y0 > fill_wend_q[31:16])));
	wire fill_win_flag_wb;
	wire fill_win_violation;
	wire drav_win_wb;
	assign drav_win_wb = ((state_q == 6'd7) && is_drav) && (drav_w_q != 2'd0);
	wire line_win_wb;
	assign line_win_wb = (state_q == 6'd33) && line_win_en;
	wire pixt_win_wb;
	assign pixt_win_wb = (state_q == 6'd7) && pixt_xy_win;
	assign fill_win_violation = ((((((state_q == 6'd23) || (state_q == 6'd24)) || ((state_q == 6'd25) && !fill_array_hit)) || ((state_q == 6'd26) && !pblt_array_hit)) || (drav_win_wb && !drav_inside_q)) || (line_win_wb && !line_last_inside_q)) || (pixt_win_wb && !pixt_inside_q);
	assign fill_win_flag_wb = ((((((((state_q == 6'd23) || ((state_q == 6'd11) && fill_w2_q)) || (state_q == 6'd24)) || ((state_q == 6'd15) && pblt_w2_q)) || (state_q == 6'd25)) || (state_q == 6'd26)) || drav_win_wb) || line_win_wb) || pixt_win_wb;
	localparam [31:0] tms34010_pkg_CTRL_W_HI = 7;
	localparam [31:0] tms34010_pkg_CTRL_W_LO = 6;
	assign wvp_set = ((((((state_q == 6'd23) || (state_q == 6'd24)) || ((state_q == 6'd25) && fill_array_hit)) || ((state_q == 6'd26) && pblt_array_hit)) || (drav_win_wb && (((drav_w_q == 2'd1) && drav_inside_q) || ((drav_w_q == 2'd2) && !drav_inside_q)))) || (line_win_wb && line_aborted_q)) || (pixt_win_wb && (((io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd1) && pixt_inside_q) || ((io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd2) && !pixt_inside_q)));
	assign fill_pixel_mask = (32'd1 << io_psize[5:0]) - 32'd1;
	assign fill_pmask_field = {{16 {1'b0}}, io_pmask} & fill_pixel_mask;
	localparam [31:0] tms34010_pkg_CTRL_PPOP_HI = 14;
	localparam [31:0] tms34010_pkg_CTRL_PPOP_LO = 10;
	assign fill_processed = ppop_apply(fill_color_q, fill_dest_q, io_control[tms34010_pkg_CTRL_PPOP_HI:tms34010_pkg_CTRL_PPOP_LO], fill_pixel_mask);
	localparam [31:0] tms34010_pkg_CTRL_T_BIT = 5;
	assign fill_transp = io_control[tms34010_pkg_CTRL_T_BIT] && ((fill_processed & fill_pixel_mask) == {32 {1'sb0}});
	wire [31:0] shared_pixel_result;
	assign fill_merged = (SHARED_PIXEL ? shared_pixel_result : (fill_transp || fill_clip_out ? fill_dest_q : (fill_processed & ~fill_pmask_field) | (fill_dest_q & fill_pmask_field)));
	generate
		if (!SHARED_GRAPHICS_REGS) begin : legacy_fill_registers
			always @(posedge clk)
				if (rst || (ce_cpu !== 1'b0)) begin
					if (rst) begin
						fill_dptch_q <= 1'sb0;
						fill_color_q <= 1'sb0;
						fill_daddr_raw_q <= 1'sb0;
						fill_dx_q <= 1'sb0;
						fill_dy_q <= 1'sb0;
						fill_addr_q <= 1'sb0;
						fill_row_base_q <= 1'sb0;
						fill_x_q <= 1'sb0;
						fill_y_q <= 1'sb0;
						fill_substep_q <= 1'b0;
						fill_dest_q <= 1'sb0;
						fill_wstart_q <= 1'sb0;
						fill_wend_q <= 1'sb0;
						fill_win_en_q <= 1'b0;
						fill_w2_q <= 1'b0;
						fill_w1_q <= 1'b0;
					end
					else begin
						if ((state_q == 6'd5) && is_fill) begin
							fill_daddr_raw_q <= rf_rs1_data;
							fill_dptch_q <= rf_rs2_data;
							fill_dx_q <= rf_rs3_data[15:0];
							fill_dy_q <= rf_rs3_data[31:16];
							fill_x_q <= 16'd0;
							fill_y_q <= 16'd0;
							fill_win_en_q <= fill_is_xy && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd3);
							fill_w2_q <= fill_is_xy && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd2);
							fill_w1_q <= fill_is_xy && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd1);
						end
						if (state_q == 6'd21) begin
							fill_wstart_q <= rf_rs1_data;
							fill_wend_q <= rf_rs2_data;
						end
						if (state_q == 6'd9) begin
							fill_color_q <= rf_rs1_data;
							fill_addr_q <= fill_start;
							fill_row_base_q <= fill_start;
							fill_substep_q <= 1'b0;
						end
						if ((state_q == 6'd10) && mem_ack) begin
							fill_substep_q <= ~fill_substep_q;
							if (!fill_substep_q)
								fill_dest_q <= mem_rdata_eff;
							else begin
								fill_addr_q <= fill_addr_q + fill_psize_ext;
								if (fill_row_end && !fill_done) begin
									fill_y_q <= fill_y_q + 16'd1;
									fill_row_base_q <= fill_row_base_q + fill_dptch_q;
									fill_addr_q <= fill_row_base_q + fill_dptch_q;
									fill_x_q <= 16'd0;
								end
								else if (!fill_done)
									fill_x_q <= fill_x_q + 16'd1;
							end
						end
					end
				end
		end
	endgenerate
	reg [31:0] pblt_sptch_q;
	reg [31:0] pblt_dptch_q;
	reg [15:0] pblt_dx_q;
	reg [15:0] pblt_dy_q;
	reg [31:0] pblt_src_addr_q;
	reg [31:0] pblt_dst_addr_q;
	reg [31:0] pblt_src_row_q;
	reg [31:0] pblt_dst_row_q;
	reg [15:0] pblt_x_q;
	reg [15:0] pblt_y_q;
	reg [1:0] pblt_substep_q;
	reg [31:0] pblt_src_pix_q;
	reg [31:0] pblt_dst_pix_q;
	wire [31:0] pblt_psize_ext;
	wire [31:0] pblt_pixel_mask;
	wire [31:0] pblt_pmask_field;
	wire [31:0] pblt_processed;
	wire [31:0] pblt_merged;
	wire pblt_row_end;
	wire pblt_done;
	wire pblt_transp;
	reg [31:0] pblt_color0_q;
	reg [31:0] pblt_color1_q;
	wire [31:0] pblt_src_eff;
	wire [31:0] pblt_src_step;
	assign pblt_psize_ext = sv2v_cast_DEBC9(io_psize[5:0]);
	assign pblt_pixel_mask = (32'd1 << io_psize[5:0]) - 32'd1;
	assign pblt_pmask_field = {{16 {1'b0}}, io_pmask} & pblt_pixel_mask;
	assign pblt_row_end = pblt_x_q == (pblt_dx_q - 16'd1);
	assign pblt_done = pblt_row_end && (pblt_y_q == (pblt_dy_q - 16'd1));
	assign pblt_src_eff = (decoded[0] ? (pblt_src_pix_q[0] ? pblt_color1_q : pblt_color0_q) : pblt_src_pix_q);
	assign pblt_src_step = (decoded[0] ? 32'd1 : pblt_psize_ext);
	assign pblt_processed = ppop_apply(pblt_src_eff, pblt_dst_pix_q, io_control[tms34010_pkg_CTRL_PPOP_HI:tms34010_pkg_CTRL_PPOP_LO], pblt_pixel_mask);
	assign pblt_transp = io_control[tms34010_pkg_CTRL_T_BIT] && ((pblt_processed & pblt_pixel_mask) == {32 {1'sb0}});
	reg [31:0] pblt_dst_xy_raw_q;
	reg [31:0] pblt_wstart_q;
	reg [31:0] pblt_wend_q;
	reg pblt_win_en_q;
	wire [15:0] pblt_px;
	wire [15:0] pblt_py;
	wire pblt_in_window;
	wire pblt_clip_out;
	assign pblt_px = pblt_dst_xy_raw_q[15:0] + pblt_x_q;
	assign pblt_py = pblt_dst_xy_raw_q[31:16] + pblt_y_q;
	assign pblt_in_window = (SHARED_WINDOW ? shared_window_inside : (((pblt_px >= pblt_wstart_q[15:0]) && (pblt_px <= pblt_wend_q[15:0])) && (pblt_py >= pblt_wstart_q[31:16])) && (pblt_py <= pblt_wend_q[31:16]));
	assign pblt_clip_out = pblt_win_en_q && !pblt_in_window;
	wire pblt_array_inside;
	wire [15:0] pblt_arr_x0;
	wire [15:0] pblt_arr_y0;
	wire [15:0] pblt_arr_x1;
	wire [15:0] pblt_arr_y1;
	assign pblt_arr_x0 = pblt_dst_xy_raw_q[15:0];
	assign pblt_arr_y0 = pblt_dst_xy_raw_q[31:16];
	assign pblt_arr_x1 = (pblt_arr_x0 + pblt_dx_q) - 16'd1;
	assign pblt_arr_y1 = (pblt_arr_y0 + pblt_dy_q) - 16'd1;
	assign pblt_array_inside = (SHARED_WINDOW ? shared_window_inside : (((pblt_arr_x0 >= rf_rs1_data[15:0]) && (pblt_arr_x1 <= rf_rs2_data[15:0])) && (pblt_arr_y0 >= rf_rs1_data[31:16])) && (pblt_arr_y1 <= rf_rs2_data[31:16]));
	assign pblt_array_hit = (SHARED_WINDOW ? shared_window_inside : !((((pblt_arr_x1 < pblt_wstart_q[15:0]) || (pblt_arr_x0 > pblt_wend_q[15:0])) || (pblt_arr_y1 < pblt_wstart_q[31:16])) || (pblt_arr_y0 > pblt_wend_q[31:16])));
	assign pblt_merged = (SHARED_PIXEL ? shared_pixel_result : (pblt_transp || pblt_clip_out ? pblt_dst_pix_q : (pblt_processed & ~pblt_pmask_field) | (pblt_dst_pix_q & pblt_pmask_field)));
	wire [31:0] pblt_src_conv;
	wire [31:0] pblt_dst_conv;
	assign pblt_src_conv = (SHARED_XY ? shared_xy0_result : (({{16 {pblt_src_addr_q[31]}}, pblt_src_addr_q[31:16]} << (5'd31 - io_convsp[4:0])) | ({16'b0000000000000000, pblt_src_addr_q[15:0]} << pix_xy_xsh)) + rf_rs3_data);
	wire [31:0] shared_xy1_result;
	assign pblt_dst_conv = (SHARED_XY ? shared_xy1_result : (({{16 {pblt_dst_addr_q[31]}}, pblt_dst_addr_q[31:16]} << (5'd31 - io_convdp[4:0])) | ({16'b0000000000000000, pblt_dst_addr_q[15:0]} << pix_xy_xsh)) + rf_rs3_data);
	generate
		if (!SHARED_GRAPHICS_REGS) begin : legacy_pblt_registers
			always @(posedge clk)
				if (rst || (ce_cpu !== 1'b0)) begin
					if (rst) begin
						pblt_sptch_q <= 1'sb0;
						pblt_dptch_q <= 1'sb0;
						pblt_dx_q <= 1'sb0;
						pblt_dy_q <= 1'sb0;
						pblt_src_addr_q <= 1'sb0;
						pblt_dst_addr_q <= 1'sb0;
						pblt_src_row_q <= 1'sb0;
						pblt_dst_row_q <= 1'sb0;
						pblt_x_q <= 1'sb0;
						pblt_y_q <= 1'sb0;
						pblt_substep_q <= 2'd0;
						pblt_src_pix_q <= 1'sb0;
						pblt_dst_pix_q <= 1'sb0;
						pblt_color0_q <= 1'sb0;
						pblt_color1_q <= 1'sb0;
						pblt_dst_xy_raw_q <= 1'sb0;
						pblt_wstart_q <= 1'sb0;
						pblt_wend_q <= 1'sb0;
						pblt_win_en_q <= 1'b0;
						pblt_w2_q <= 1'b0;
						pblt_w1_q <= 1'b0;
					end
					else begin
						if ((state_q == 6'd5) && is_pblt) begin
							pblt_src_addr_q <= rf_rs1_data;
							pblt_src_row_q <= rf_rs1_data;
							pblt_dst_addr_q <= rf_rs2_data;
							pblt_dst_row_q <= rf_rs2_data;
							pblt_dst_xy_raw_q <= rf_rs2_data;
							pblt_dx_q <= rf_rs3_data[15:0];
							pblt_dy_q <= rf_rs3_data[31:16];
							pblt_x_q <= 16'd0;
							pblt_y_q <= 16'd0;
							pblt_substep_q <= 2'd0;
							pblt_win_en_q <= decoded[1] && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd3);
							pblt_w2_q <= decoded[1] && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd2);
							pblt_w1_q <= decoded[1] && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd1);
						end
						if (state_q == 6'd22) begin
							pblt_wstart_q <= rf_rs1_data;
							pblt_wend_q <= rf_rs2_data;
						end
						if (state_q == 6'd12) begin
							pblt_sptch_q <= rf_rs1_data;
							pblt_dptch_q <= rf_rs2_data;
							if (decoded[2]) begin
								pblt_src_addr_q <= pblt_src_conv;
								pblt_src_row_q <= pblt_src_conv;
							end
							if (decoded[1]) begin
								pblt_dst_addr_q <= pblt_dst_conv;
								pblt_dst_row_q <= pblt_dst_conv;
							end
						end
						if (state_q == 6'd16) begin
							pblt_color0_q <= rf_rs1_data;
							pblt_color1_q <= rf_rs2_data;
						end
						if ((state_q == 6'd13) && mem_ack) begin
							if (pblt_substep_q == 2'd0) begin
								pblt_src_pix_q <= mem_rdata_eff;
								pblt_substep_q <= 2'd1;
							end
							else if (pblt_substep_q == 2'd1) begin
								pblt_dst_pix_q <= mem_rdata_eff;
								pblt_substep_q <= 2'd2;
							end
							else begin
								pblt_substep_q <= 2'd0;
								pblt_src_addr_q <= pblt_src_addr_q + pblt_src_step;
								pblt_dst_addr_q <= pblt_dst_addr_q + pblt_psize_ext;
								if (pblt_done) begin
									pblt_src_addr_q <= pblt_src_row_q + pblt_sptch_q;
									pblt_dst_addr_q <= pblt_dst_row_q + pblt_dptch_q;
								end
								else if (pblt_row_end) begin
									pblt_y_q <= pblt_y_q + 16'd1;
									pblt_src_row_q <= pblt_src_row_q + pblt_sptch_q;
									pblt_dst_row_q <= pblt_dst_row_q + pblt_dptch_q;
									pblt_src_addr_q <= pblt_src_row_q + pblt_sptch_q;
									pblt_dst_addr_q <= pblt_dst_row_q + pblt_dptch_q;
									pblt_x_q <= 16'd0;
								end
								else
									pblt_x_q <= pblt_x_q + 16'd1;
							end
						end
					end
				end
		end
	endgenerate
	reg [31:0] drav_rd_q;
	reg [31:0] drav_rs_q;
	reg [31:0] drav_linear_q;
	reg [31:0] drav_dest_q;
	reg drav_substep_q;
	wire drav_in_window;
	wire drav_draw;
	assign drav_in_window = (SHARED_WINDOW ? shared_window_inside : (((drav_rd_q[15:0] >= rf_rs1_data[15:0]) && (drav_rd_q[15:0] <= rf_rs2_data[15:0])) && (drav_rd_q[31:16] >= rf_rs1_data[31:16])) && (drav_rd_q[31:16] <= rf_rs2_data[31:16]));
	assign drav_draw = (drav_w_q == 2'd0) || (((drav_w_q == 2'd2) || (drav_w_q == 2'd3)) && drav_inside_q);
	wire [31:0] drav_pixel_mask;
	wire [31:0] drav_pmask_field;
	wire [31:0] drav_processed;
	wire [31:0] drav_merged;
	wire drav_transp;
	wire [31:0] drav_advance;
	wire [31:0] shared_xy_arith_result;
	assign drav_pixel_mask = (32'd1 << io_psize[5:0]) - 32'd1;
	assign drav_pmask_field = {{16 {1'b0}}, io_pmask} & drav_pixel_mask;
	assign drav_processed = ppop_apply(rf_rs1_data, drav_dest_q, io_control[tms34010_pkg_CTRL_PPOP_HI:tms34010_pkg_CTRL_PPOP_LO], drav_pixel_mask);
	assign drav_transp = io_control[tms34010_pkg_CTRL_T_BIT] && ((drav_processed & drav_pixel_mask) == {32 {1'sb0}});
	assign drav_merged = (SHARED_PIXEL ? shared_pixel_result : (drav_transp ? drav_dest_q : (drav_processed & ~drav_pmask_field) | (drav_dest_q & drav_pmask_field)));
	assign drav_advance = (SHARED_XY_ARITH ? shared_xy_arith_result : {drav_rd_q[31:16] + drav_rs_q[31:16], drav_rd_q[15:0] + drav_rs_q[15:0]});
	generate
		if (!SHARED_GRAPHICS_REGS) begin : legacy_drav_registers
			always @(posedge clk)
				if (rst || (ce_cpu !== 1'b0)) begin
					if (rst) begin
						drav_rd_q <= 1'sb0;
						drav_rs_q <= 1'sb0;
						drav_linear_q <= 1'sb0;
						drav_dest_q <= 1'sb0;
						drav_substep_q <= 1'b0;
						drav_w_q <= 2'd0;
						drav_inside_q <= 1'b0;
					end
					else begin
						if ((state_q == 6'd5) && is_drav) begin
							drav_rd_q <= rf_rs2_data;
							drav_rs_q <= rf_rs1_data;
							drav_linear_q <= pix_xy_dst_linear;
							drav_substep_q <= 1'b0;
							drav_w_q <= io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO];
						end
						if (state_q == 6'd28)
							drav_inside_q <= drav_in_window;
						if ((state_q == 6'd27) && mem_ack) begin
							drav_substep_q <= ~drav_substep_q;
							if (!drav_substep_q)
								drav_dest_q <= mem_rdata_eff;
						end
					end
				end
		end
	endgenerate
	reg [31:0] line_d_q;
	reg [31:0] line_count_q;
	reg [31:0] line_inc1_q;
	reg [31:0] line_inc2_q;
	reg [31:0] line_offset_q;
	reg [31:0] line_daddr_q;
	reg [31:0] line_color_q;
	reg [31:0] line_dest_q;
	reg [15:0] line_b_q;
	reg [15:0] line_a_q;
	reg line_substep_q;
	wire [31:0] line_linear;
	assign line_linear = (SHARED_XY ? shared_xy0_result : (({{16 {line_daddr_q[31]}}, line_daddr_q[31:16]} << (5'd31 - io_convdp[4:0])) | ({16'b0000000000000000, line_daddr_q[15:0]} << pix_xy_xsh)) + line_offset_q);
	wire [31:0] line_pixel_mask;
	wire [31:0] line_pmask_field;
	wire [31:0] line_processed;
	wire [31:0] line_merged;
	wire line_transp;
	assign line_pixel_mask = (32'd1 << io_psize[5:0]) - 32'd1;
	assign line_pmask_field = {{16 {1'b0}}, io_pmask} & line_pixel_mask;
	assign line_processed = ppop_apply(line_color_q, line_dest_q, io_control[tms34010_pkg_CTRL_PPOP_HI:tms34010_pkg_CTRL_PPOP_LO], line_pixel_mask);
	assign line_transp = io_control[tms34010_pkg_CTRL_T_BIT] && ((line_processed & line_pixel_mask) == {32 {1'sb0}});
	reg [31:0] line_wstart_q;
	reg [31:0] line_wend_q;
	wire [1:0] line_w_mode;
	wire line_in_window;
	wire line_draw_pixel;
	wire line_clip_out;
	wire line_abort;
	assign line_w_mode = io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO];
	assign line_win_en = line_w_mode != 2'd0;
	assign line_in_window = (SHARED_WINDOW ? shared_window_inside : (((line_daddr_q[15:0] >= line_wstart_q[15:0]) && (line_daddr_q[15:0] <= line_wend_q[15:0])) && (line_daddr_q[31:16] >= line_wstart_q[31:16])) && (line_daddr_q[31:16] <= line_wend_q[31:16]));
	assign line_draw_pixel = (line_w_mode == 2'd1 ? !line_in_window : line_in_window);
	assign line_clip_out = line_win_en && !line_draw_pixel;
	assign line_abort = ((line_w_mode == 2'd1) && line_in_window) || ((line_w_mode == 2'd2) && !line_in_window);
	assign line_merged = (SHARED_PIXEL ? shared_pixel_result : (line_transp || line_clip_out ? line_dest_q : (line_processed & ~line_pmask_field) | (line_dest_q & line_pmask_field)));
	wire line_branch;
	wire [31:0] line_2b;
	wire [31:0] line_2a;
	wire [31:0] line_d_next;
	wire [31:0] line_daddr_next;
	wire [31:0] line_count_next;
	assign line_branch = (instr_word_q[7] ? !line_d_q[31] : !line_d_q[31] && (line_d_q != {32 {1'sb0}}));
	assign line_2b = {16'b0000000000000000, line_b_q} << 1;
	assign line_2a = {16'b0000000000000000, line_a_q} << 1;
	assign line_d_next = (line_branch ? (line_d_q + line_2b) - line_2a : line_d_q + line_2b);
	assign line_daddr_next = (SHARED_XY_ARITH ? shared_xy_arith_result : (line_branch ? {line_daddr_q[31:16] + line_inc1_q[31:16], line_daddr_q[15:0] + line_inc1_q[15:0]} : {line_daddr_q[31:16] + line_inc2_q[31:16], line_daddr_q[15:0] + line_inc2_q[15:0]}));
	assign line_count_next = line_count_q - 32'd1;
	generate
		if (!SHARED_GRAPHICS_REGS) begin : legacy_line_registers
			always @(posedge clk)
				if (rst || (ce_cpu !== 1'b0)) begin
					if (rst) begin
						line_d_q <= 1'sb0;
						line_count_q <= 1'sb0;
						line_inc1_q <= 1'sb0;
						line_inc2_q <= 1'sb0;
						line_offset_q <= 1'sb0;
						line_daddr_q <= 1'sb0;
						line_color_q <= 1'sb0;
						line_dest_q <= 1'sb0;
						line_b_q <= 1'sb0;
						line_a_q <= 1'sb0;
						line_substep_q <= 1'b0;
						line_wstart_q <= 1'sb0;
						line_wend_q <= 1'sb0;
						line_last_inside_q <= 1'b0;
						line_aborted_q <= 1'b0;
					end
					else begin
						if ((state_q == 6'd5) && is_line)
							line_aborted_q <= 1'b0;
						if (state_q == 6'd36) begin
							line_wstart_q <= rf_rs1_data;
							line_wend_q <= rf_rs2_data;
						end
						if (state_q == 6'd29) begin
							line_d_q <= rf_rs1_data;
							line_b_q <= rf_rs2_data[31:16];
							line_a_q <= rf_rs2_data[15:0];
							line_count_q <= rf_rs3_data;
						end
						if (state_q == 6'd30) begin
							line_inc1_q <= rf_rs1_data;
							line_inc2_q <= rf_rs2_data;
							line_offset_q <= rf_rs3_data;
						end
						if (state_q == 6'd31) begin
							line_daddr_q <= rf_rs1_data;
							line_color_q <= rf_rs2_data;
							line_substep_q <= 1'b0;
						end
						if ((state_q == 6'd32) && mem_ack) begin
							line_substep_q <= ~line_substep_q;
							if (!line_substep_q)
								line_dest_q <= mem_rdata_eff;
							else begin
								line_last_inside_q <= line_in_window;
								if (line_abort)
									line_aborted_q <= 1'b1;
								line_d_q <= line_d_next;
								line_daddr_q <= line_daddr_next;
								line_count_q <= line_count_next;
							end
						end
					end
				end
		end
		if (SHARED_GRAPHICS_REGS) begin : shared_graphics_registers
			reg [31:0] graphics_word_q [0:12];
			reg [15:0] graphics_half_q [0:3];
			wire [32:1] sv2v_tmp_17B62;
			assign sv2v_tmp_17B62 = graphics_word_q[0];
			always @(*) pblt_sptch_q = sv2v_tmp_17B62;
			wire [32:1] sv2v_tmp_0496E;
			assign sv2v_tmp_0496E = graphics_word_q[0];
			always @(*) line_inc1_q = sv2v_tmp_0496E;
			wire [32:1] sv2v_tmp_48BDB;
			assign sv2v_tmp_48BDB = graphics_word_q[0];
			always @(*) drav_rs_q = sv2v_tmp_48BDB;
			wire [32:1] sv2v_tmp_A9634;
			assign sv2v_tmp_A9634 = graphics_word_q[1];
			always @(*) pblt_dptch_q = sv2v_tmp_A9634;
			wire [32:1] sv2v_tmp_11741;
			assign sv2v_tmp_11741 = graphics_word_q[1];
			always @(*) fill_dptch_q = sv2v_tmp_11741;
			wire [32:1] sv2v_tmp_EF68C;
			assign sv2v_tmp_EF68C = graphics_word_q[1];
			always @(*) line_inc2_q = sv2v_tmp_EF68C;
			wire [32:1] sv2v_tmp_1BFD7;
			assign sv2v_tmp_1BFD7 = graphics_word_q[2];
			always @(*) pblt_src_addr_q = sv2v_tmp_1BFD7;
			wire [32:1] sv2v_tmp_C2321;
			assign sv2v_tmp_C2321 = graphics_word_q[2];
			always @(*) fill_daddr_raw_q = sv2v_tmp_C2321;
			wire [32:1] sv2v_tmp_BEEBF;
			assign sv2v_tmp_BEEBF = graphics_word_q[2];
			always @(*) line_daddr_q = sv2v_tmp_BEEBF;
			wire [32:1] sv2v_tmp_0117E;
			assign sv2v_tmp_0117E = graphics_word_q[2];
			always @(*) drav_rd_q = sv2v_tmp_0117E;
			wire [32:1] sv2v_tmp_380F7;
			assign sv2v_tmp_380F7 = graphics_word_q[3];
			always @(*) pblt_dst_addr_q = sv2v_tmp_380F7;
			wire [32:1] sv2v_tmp_A344A;
			assign sv2v_tmp_A344A = graphics_word_q[3];
			always @(*) fill_addr_q = sv2v_tmp_A344A;
			wire [32:1] sv2v_tmp_C9D21;
			assign sv2v_tmp_C9D21 = graphics_word_q[3];
			always @(*) line_d_q = sv2v_tmp_C9D21;
			wire [32:1] sv2v_tmp_82898;
			assign sv2v_tmp_82898 = graphics_word_q[3];
			always @(*) drav_linear_q = sv2v_tmp_82898;
			wire [32:1] sv2v_tmp_B988F;
			assign sv2v_tmp_B988F = graphics_word_q[4];
			always @(*) pblt_src_row_q = sv2v_tmp_B988F;
			wire [32:1] sv2v_tmp_8056A;
			assign sv2v_tmp_8056A = graphics_word_q[4];
			always @(*) fill_row_base_q = sv2v_tmp_8056A;
			wire [32:1] sv2v_tmp_B416D;
			assign sv2v_tmp_B416D = graphics_word_q[4];
			always @(*) line_count_q = sv2v_tmp_B416D;
			wire [32:1] sv2v_tmp_C0A1F;
			assign sv2v_tmp_C0A1F = graphics_word_q[5];
			always @(*) pblt_dst_row_q = sv2v_tmp_C0A1F;
			wire [32:1] sv2v_tmp_D08E1;
			assign sv2v_tmp_D08E1 = graphics_word_q[5];
			always @(*) line_offset_q = sv2v_tmp_D08E1;
			wire [32:1] sv2v_tmp_83D56;
			assign sv2v_tmp_83D56 = graphics_word_q[6];
			always @(*) pblt_src_pix_q = sv2v_tmp_83D56;
			wire [32:1] sv2v_tmp_AA290;
			assign sv2v_tmp_AA290 = graphics_word_q[6];
			always @(*) fill_color_q = sv2v_tmp_AA290;
			wire [32:1] sv2v_tmp_A8281;
			assign sv2v_tmp_A8281 = graphics_word_q[6];
			always @(*) line_color_q = sv2v_tmp_A8281;
			wire [32:1] sv2v_tmp_12DA6;
			assign sv2v_tmp_12DA6 = graphics_word_q[7];
			always @(*) pblt_dst_pix_q = sv2v_tmp_12DA6;
			wire [32:1] sv2v_tmp_2FD8B;
			assign sv2v_tmp_2FD8B = graphics_word_q[7];
			always @(*) fill_dest_q = sv2v_tmp_2FD8B;
			wire [32:1] sv2v_tmp_A806A;
			assign sv2v_tmp_A806A = graphics_word_q[7];
			always @(*) line_dest_q = sv2v_tmp_A806A;
			wire [32:1] sv2v_tmp_7DAD5;
			assign sv2v_tmp_7DAD5 = graphics_word_q[7];
			always @(*) drav_dest_q = sv2v_tmp_7DAD5;
			wire [32:1] sv2v_tmp_72F28;
			assign sv2v_tmp_72F28 = graphics_word_q[8];
			always @(*) pblt_color0_q = sv2v_tmp_72F28;
			wire [32:1] sv2v_tmp_87268;
			assign sv2v_tmp_87268 = graphics_word_q[9];
			always @(*) pblt_color1_q = sv2v_tmp_87268;
			wire [32:1] sv2v_tmp_F560F;
			assign sv2v_tmp_F560F = graphics_word_q[10];
			always @(*) pblt_dst_xy_raw_q = sv2v_tmp_F560F;
			wire [32:1] sv2v_tmp_A1D9B;
			assign sv2v_tmp_A1D9B = graphics_word_q[11];
			always @(*) pblt_wstart_q = sv2v_tmp_A1D9B;
			wire [32:1] sv2v_tmp_FD96E;
			assign sv2v_tmp_FD96E = graphics_word_q[11];
			always @(*) fill_wstart_q = sv2v_tmp_FD96E;
			wire [32:1] sv2v_tmp_F04FF;
			assign sv2v_tmp_F04FF = graphics_word_q[11];
			always @(*) line_wstart_q = sv2v_tmp_F04FF;
			wire [32:1] sv2v_tmp_225E5;
			assign sv2v_tmp_225E5 = graphics_word_q[12];
			always @(*) pblt_wend_q = sv2v_tmp_225E5;
			wire [32:1] sv2v_tmp_90A70;
			assign sv2v_tmp_90A70 = graphics_word_q[12];
			always @(*) fill_wend_q = sv2v_tmp_90A70;
			wire [32:1] sv2v_tmp_67DC1;
			assign sv2v_tmp_67DC1 = graphics_word_q[12];
			always @(*) line_wend_q = sv2v_tmp_67DC1;
			wire [16:1] sv2v_tmp_98960;
			assign sv2v_tmp_98960 = graphics_half_q[0];
			always @(*) pblt_dx_q = sv2v_tmp_98960;
			wire [16:1] sv2v_tmp_4D445;
			assign sv2v_tmp_4D445 = graphics_half_q[0];
			always @(*) fill_dx_q = sv2v_tmp_4D445;
			wire [16:1] sv2v_tmp_D61D9;
			assign sv2v_tmp_D61D9 = graphics_half_q[0];
			always @(*) line_b_q = sv2v_tmp_D61D9;
			wire [16:1] sv2v_tmp_5B0C0;
			assign sv2v_tmp_5B0C0 = graphics_half_q[1];
			always @(*) pblt_dy_q = sv2v_tmp_5B0C0;
			wire [16:1] sv2v_tmp_0CDA5;
			assign sv2v_tmp_0CDA5 = graphics_half_q[1];
			always @(*) fill_dy_q = sv2v_tmp_0CDA5;
			wire [16:1] sv2v_tmp_7435B;
			assign sv2v_tmp_7435B = graphics_half_q[1];
			always @(*) line_a_q = sv2v_tmp_7435B;
			wire [16:1] sv2v_tmp_7C0E5;
			assign sv2v_tmp_7C0E5 = graphics_half_q[2];
			always @(*) pblt_x_q = sv2v_tmp_7C0E5;
			wire [16:1] sv2v_tmp_CD150;
			assign sv2v_tmp_CD150 = graphics_half_q[2];
			always @(*) fill_x_q = sv2v_tmp_CD150;
			wire [16:1] sv2v_tmp_93BC5;
			assign sv2v_tmp_93BC5 = graphics_half_q[3];
			always @(*) pblt_y_q = sv2v_tmp_93BC5;
			wire [16:1] sv2v_tmp_33A70;
			assign sv2v_tmp_33A70 = graphics_half_q[3];
			always @(*) fill_y_q = sv2v_tmp_33A70;
			always @(posedge clk)
				if (rst || (ce_cpu !== 1'b0)) begin
					if (rst) begin
						begin : sv2v_autoblock_1
							reg signed [31:0] i;
							for (i = 0; i < 13; i = i + 1)
								graphics_word_q[i] <= 1'sb0;
						end
						begin : sv2v_autoblock_2
							reg signed [31:0] i;
							for (i = 0; i < 4; i = i + 1)
								graphics_half_q[i] <= 1'sb0;
						end
						fill_substep_q <= 1'b0;
						fill_win_en_q <= 1'b0;
						fill_w2_q <= 1'b0;
						fill_w1_q <= 1'b0;
						pblt_substep_q <= 2'd0;
						pblt_win_en_q <= 1'b0;
						pblt_w2_q <= 1'b0;
						pblt_w1_q <= 1'b0;
						drav_substep_q <= 1'b0;
						drav_w_q <= 2'd0;
						drav_inside_q <= 1'b0;
						line_substep_q <= 1'b0;
						line_last_inside_q <= 1'b0;
						line_aborted_q <= 1'b0;
					end
					else begin
						if ((state_q == 6'd5) && is_fill) begin
							graphics_word_q[2] <= rf_rs1_data;
							graphics_word_q[1] <= rf_rs2_data;
							graphics_half_q[0] <= rf_rs3_data[15:0];
							graphics_half_q[1] <= rf_rs3_data[31:16];
							graphics_half_q[2] <= 16'd0;
							graphics_half_q[3] <= 16'd0;
							fill_win_en_q <= fill_is_xy && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd3);
							fill_w2_q <= fill_is_xy && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd2);
							fill_w1_q <= fill_is_xy && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd1);
						end
						if (state_q == 6'd21) begin
							graphics_word_q[11] <= rf_rs1_data;
							graphics_word_q[12] <= rf_rs2_data;
						end
						if (state_q == 6'd9) begin
							graphics_word_q[6] <= rf_rs1_data;
							graphics_word_q[3] <= fill_start;
							graphics_word_q[4] <= fill_start;
							fill_substep_q <= 1'b0;
						end
						if ((state_q == 6'd10) && mem_ack) begin
							fill_substep_q <= ~fill_substep_q;
							if (!fill_substep_q)
								graphics_word_q[7] <= mem_rdata_eff;
							else begin
								graphics_word_q[3] <= fill_addr_q + fill_psize_ext;
								if (fill_row_end && !fill_done) begin
									graphics_half_q[3] <= fill_y_q + 16'd1;
									graphics_word_q[4] <= fill_row_base_q + fill_dptch_q;
									graphics_word_q[3] <= fill_row_base_q + fill_dptch_q;
									graphics_half_q[2] <= 16'd0;
								end
								else if (!fill_done)
									graphics_half_q[2] <= fill_x_q + 16'd1;
							end
						end
						if ((state_q == 6'd5) && is_pblt) begin
							graphics_word_q[2] <= rf_rs1_data;
							graphics_word_q[4] <= rf_rs1_data;
							graphics_word_q[3] <= rf_rs2_data;
							graphics_word_q[5] <= rf_rs2_data;
							graphics_word_q[10] <= rf_rs2_data;
							graphics_half_q[0] <= rf_rs3_data[15:0];
							graphics_half_q[1] <= rf_rs3_data[31:16];
							graphics_half_q[2] <= 16'd0;
							graphics_half_q[3] <= 16'd0;
							pblt_substep_q <= 2'd0;
							pblt_win_en_q <= decoded[1] && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd3);
							pblt_w2_q <= decoded[1] && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd2);
							pblt_w1_q <= decoded[1] && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd1);
						end
						if (state_q == 6'd22) begin
							graphics_word_q[11] <= rf_rs1_data;
							graphics_word_q[12] <= rf_rs2_data;
						end
						if (state_q == 6'd12) begin
							graphics_word_q[0] <= rf_rs1_data;
							graphics_word_q[1] <= rf_rs2_data;
							if (decoded[2]) begin
								graphics_word_q[2] <= pblt_src_conv;
								graphics_word_q[4] <= pblt_src_conv;
							end
							if (decoded[1]) begin
								graphics_word_q[3] <= pblt_dst_conv;
								graphics_word_q[5] <= pblt_dst_conv;
							end
						end
						if (state_q == 6'd16) begin
							graphics_word_q[8] <= rf_rs1_data;
							graphics_word_q[9] <= rf_rs2_data;
						end
						if ((state_q == 6'd13) && mem_ack) begin
							if (pblt_substep_q == 2'd0) begin
								graphics_word_q[6] <= mem_rdata_eff;
								pblt_substep_q <= 2'd1;
							end
							else if (pblt_substep_q == 2'd1) begin
								graphics_word_q[7] <= mem_rdata_eff;
								pblt_substep_q <= 2'd2;
							end
							else begin
								pblt_substep_q <= 2'd0;
								graphics_word_q[2] <= pblt_src_addr_q + pblt_src_step;
								graphics_word_q[3] <= pblt_dst_addr_q + pblt_psize_ext;
								if (pblt_done) begin
									graphics_word_q[2] <= pblt_src_row_q + pblt_sptch_q;
									graphics_word_q[3] <= pblt_dst_row_q + pblt_dptch_q;
								end
								else if (pblt_row_end) begin
									graphics_half_q[3] <= pblt_y_q + 16'd1;
									graphics_word_q[4] <= pblt_src_row_q + pblt_sptch_q;
									graphics_word_q[5] <= pblt_dst_row_q + pblt_dptch_q;
									graphics_word_q[2] <= pblt_src_row_q + pblt_sptch_q;
									graphics_word_q[3] <= pblt_dst_row_q + pblt_dptch_q;
									graphics_half_q[2] <= 16'd0;
								end
								else
									graphics_half_q[2] <= pblt_x_q + 16'd1;
							end
						end
						if ((state_q == 6'd5) && is_drav) begin
							graphics_word_q[2] <= rf_rs2_data;
							graphics_word_q[0] <= rf_rs1_data;
							graphics_word_q[3] <= pix_xy_dst_linear;
							drav_substep_q <= 1'b0;
							drav_w_q <= io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO];
						end
						if (state_q == 6'd28)
							drav_inside_q <= drav_in_window;
						if ((state_q == 6'd27) && mem_ack) begin
							drav_substep_q <= ~drav_substep_q;
							if (!drav_substep_q)
								graphics_word_q[7] <= mem_rdata_eff;
						end
						if ((state_q == 6'd5) && is_line)
							line_aborted_q <= 1'b0;
						if (state_q == 6'd36) begin
							graphics_word_q[11] <= rf_rs1_data;
							graphics_word_q[12] <= rf_rs2_data;
						end
						if (state_q == 6'd29) begin
							graphics_word_q[3] <= rf_rs1_data;
							graphics_half_q[0] <= rf_rs2_data[31:16];
							graphics_half_q[1] <= rf_rs2_data[15:0];
							graphics_word_q[4] <= rf_rs3_data;
						end
						if (state_q == 6'd30) begin
							graphics_word_q[0] <= rf_rs1_data;
							graphics_word_q[1] <= rf_rs2_data;
							graphics_word_q[5] <= rf_rs3_data;
						end
						if (state_q == 6'd31) begin
							graphics_word_q[2] <= rf_rs1_data;
							graphics_word_q[6] <= rf_rs2_data;
							line_substep_q <= 1'b0;
						end
						if ((state_q == 6'd32) && mem_ack) begin
							line_substep_q <= ~line_substep_q;
							if (!line_substep_q)
								graphics_word_q[7] <= mem_rdata_eff;
							else begin
								line_last_inside_q <= line_in_window;
								if (line_abort)
									line_aborted_q <= 1'b1;
								graphics_word_q[3] <= line_d_next;
								graphics_word_q[2] <= line_daddr_next;
								graphics_word_q[4] <= line_count_next;
							end
						end
					end
				end
		end
	endgenerate
	reg [31:0] mm_rp_q;
	reg [15:0] mm_mask_q;
	reg [3:0] mm_iter_idx;
	wire [3:0] mm_reg_idx;
	wire mm_mask_will_be_empty;
	wire is_mmtm;
	wire is_mmfm;
	wire is_mm;
	assign is_mmtm = decoded[51-:7] == 7'd72;
	assign is_mmfm = decoded[51-:7] == 7'd73;
	assign is_mm = is_mmtm || is_mmfm;
	function automatic signed [3:0] sv2v_cast_4_signed;
		input reg signed [3:0] inp;
		sv2v_cast_4_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		mm_iter_idx = 4'd0;
		begin : sv2v_autoblock_3
			reg signed [31:0] i;
			for (i = 0; i < 16; i = i + 1)
				if (mm_mask_q[i])
					mm_iter_idx = sv2v_cast_4_signed(i);
		end
	end
	assign mm_reg_idx = (is_mmtm ? 4'd15 - mm_iter_idx : mm_iter_idx);
	assign mm_mask_will_be_empty = (mm_mask_q & ~(16'd1 << mm_iter_idx)) == 16'd0;
	localparam [31:0] tms34010_pkg_WORD_BIT_SIZE = sv2v_cast_DEBC9(tms34010_pkg_DATA_WIDTH);
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				mm_rp_q <= 1'sb0;
				mm_mask_q <= 1'sb0;
			end
			else if (((state_q == 6'd5) && (state_d == 6'd6)) && is_mm) begin
				mm_rp_q <= (is_mmtm ? rf_rs2_data - tms34010_pkg_WORD_BIT_SIZE : rf_rs2_data);
				mm_mask_q <= imm_lo_q;
			end
			else if (((state_q == 6'd6) && is_mm) && mem_ack) begin
				mm_mask_q[mm_iter_idx] <= 1'b0;
				if (is_mmfm)
					mm_rp_q <= mm_rp_q + tms34010_pkg_WORD_BIT_SIZE;
				else if (!mm_mask_will_be_empty)
					mm_rp_q <= mm_rp_q - tms34010_pkg_WORD_BIT_SIZE;
			end
		end
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				imm_lo_q <= 1'sb0;
				imm_hi_q <= 1'sb0;
			end
			else begin
				if ((state_q == 6'd3) && mem_ack)
					imm_lo_q <= mem_rdata_eff[15:0];
				if ((state_q == 6'd4) && mem_ack)
					imm_hi_q <= mem_rdata_eff[15:0];
				if ((state_q == 6'd39) && mem_ack)
					imm2_lo_q <= mem_rdata_eff[15:0];
				if ((state_q == 6'd40) && mem_ack)
					imm2_hi_q <= mem_rdata_eff[15:0];
			end
		end
	wire rf_rs1_file;
	wire [3:0] rf_rs1_idx;
	wire rf_rs2_file;
	wire [3:0] rf_rs2_idx;
	wire rf_rs3_file;
	wire [3:0] rf_rs3_idx;
	wire rf_wr_en;
	wire rf_wr_file;
	wire [3:0] rf_wr_idx;
	reg [31:0] rf_wr_data;
	wire [31:0] rf_sp;
	wire [3:0] alu_op;
	reg [31:0] alu_a;
	reg [31:0] alu_b;
	wire alu_cin;
	wire [31:0] alu_result;
	wire [3:0] alu_flags;
	wire st_flag_update_en;
	wire st_write_en;
	reg [31:0] st_write_data;
	wire [31:0] st_value;
	wire st_n;
	wire st_c;
	wire st_z;
	wire st_v;
	wire [31:0] shifter_result;
	wire [3:0] shifter_flags;
	reg [31:0] imm32;
	always @(*) begin
		if (_sv2v_0)
			;
		if (decoded[33])
			imm32 = {imm_hi_q, imm_lo_q};
		else if (decoded[32])
			imm32 = {{tms34010_pkg_DATA_WIDTH - tms34010_pkg_INSTR_WORD_WIDTH {imm_lo_q[15]}}, imm_lo_q};
		else
			imm32 = {{tms34010_pkg_DATA_WIDTH - tms34010_pkg_INSTR_WORD_WIDTH {1'b0}}, imm_lo_q};
	end
	assign is_fill = (decoded[51-:7] == 7'd94) || (decoded[51-:7] == 7'd95);
	assign fill_is_xy = decoded[51-:7] == 7'd95;
	assign is_pblt = decoded[51-:7] == 7'd96;
	assign is_drav = decoded[51-:7] == 7'd97;
	assign is_line = decoded[51-:7] == 7'd98;
	wire line_rd_b;
	assign line_rd_b = is_line && ((((state_q == 6'd29) || (state_q == 6'd30)) || (state_q == 6'd31)) || (state_q == 6'd36));
	assign rf_rs1_file = (line_rd_b ? 1'b1 : (state_q == 6'd37 ? 1'b1 : (is_drav && ((state_q == 6'd27) || (state_q == 6'd28)) ? 1'b1 : (is_fill || is_pblt ? 1'b1 : (decoded[51-:7] == 7'd30 ? decoded[35] : decoded[44])))));
	localparam [3:0] tms34010_pkg_B_COLOR0_IDX = 4'd8;
	localparam [3:0] tms34010_pkg_B_COLOR1_IDX = 4'd9;
	localparam [3:0] tms34010_pkg_B_DADDR_IDX = 4'd2;
	localparam [3:0] tms34010_pkg_B_INC1_IDX = 4'd11;
	localparam [3:0] tms34010_pkg_B_SADDR_IDX = 4'd0;
	localparam [3:0] tms34010_pkg_B_SPTCH_IDX = 4'd1;
	localparam [3:0] tms34010_pkg_CPW_WSTART_IDX = 4'd5;
	assign rf_rs1_idx = (is_fill ? (state_q == 6'd21 ? tms34010_pkg_CPW_WSTART_IDX : (state_q == 6'd9 ? tms34010_pkg_B_COLOR1_IDX : tms34010_pkg_B_DADDR_IDX)) : (is_pblt ? (state_q == 6'd22 ? tms34010_pkg_CPW_WSTART_IDX : (state_q == 6'd16 ? tms34010_pkg_B_COLOR0_IDX : (state_q == 6'd12 ? tms34010_pkg_B_SPTCH_IDX : tms34010_pkg_B_SADDR_IDX))) : ((state_q == 6'd6) && is_mmtm ? mm_reg_idx : (is_drav && (state_q == 6'd28) ? tms34010_pkg_CPW_WSTART_IDX : (is_drav && (state_q == 6'd27) ? tms34010_pkg_B_COLOR1_IDX : (is_line && (state_q == 6'd29) ? tms34010_pkg_B_SADDR_IDX : (is_line && (state_q == 6'd30) ? tms34010_pkg_B_INC1_IDX : (is_line && (state_q == 6'd31) ? tms34010_pkg_B_DADDR_IDX : (is_line && (state_q == 6'd36) ? tms34010_pkg_CPW_WSTART_IDX : (state_q == 6'd37 ? tms34010_pkg_CPW_WSTART_IDX : decoded[39-:4]))))))))));
	assign rf_rs2_file = (((((line_rd_b || is_fill) || is_pblt) || (decoded[51-:7] == 7'd86)) || (state_q == 6'd37)) || (is_drav && (state_q == 6'd28)) ? 1'b1 : decoded[44]);
	localparam [3:0] tms34010_pkg_B_DPTCH_IDX = 4'd3;
	localparam [3:0] tms34010_pkg_B_DYDX_IDX = 4'd7;
	localparam [3:0] tms34010_pkg_B_INC2_IDX = 4'd12;
	localparam [3:0] tms34010_pkg_CPW_WEND_IDX = 4'd6;
	assign rf_rs2_idx = (is_fill ? (state_q == 6'd21 ? tms34010_pkg_CPW_WEND_IDX : tms34010_pkg_B_DPTCH_IDX) : (is_pblt ? (state_q == 6'd22 ? tms34010_pkg_CPW_WEND_IDX : (state_q == 6'd16 ? tms34010_pkg_B_COLOR1_IDX : (state_q == 6'd12 ? tms34010_pkg_B_DPTCH_IDX : tms34010_pkg_B_DADDR_IDX))) : (is_drav && (state_q == 6'd28) ? tms34010_pkg_CPW_WEND_IDX : (is_line && (state_q == 6'd29) ? tms34010_pkg_B_DYDX_IDX : (is_line && (state_q == 6'd30) ? tms34010_pkg_B_INC2_IDX : (is_line && (state_q == 6'd31) ? tms34010_pkg_B_COLOR1_IDX : (is_line && (state_q == 6'd36) ? tms34010_pkg_CPW_WEND_IDX : (state_q == 6'd37 ? tms34010_pkg_CPW_WEND_IDX : (decoded[51-:7] == 7'd86 ? tms34010_pkg_CPW_WSTART_IDX : decoded[43-:4])))))))));
	assign rf_rs3_file = ((decoded[51-:7] == 7'd89) || (decoded[51-:7] == 7'd91) ? decoded[44] : 1'b1);
	localparam [3:0] tms34010_pkg_B_COUNT_IDX = 4'd10;
	localparam [3:0] tms34010_pkg_B_OFFSET_IDX = 4'd4;
	assign rf_rs3_idx = ((decoded[51-:7] == 7'd89) || (decoded[51-:7] == 7'd91) ? decoded[43-:4] + 4'd1 : (is_fill ? (state_q == 6'd9 ? tms34010_pkg_B_OFFSET_IDX : tms34010_pkg_B_DYDX_IDX) : (is_pblt ? (state_q == 6'd12 ? tms34010_pkg_B_OFFSET_IDX : tms34010_pkg_B_DYDX_IDX) : (is_line && (state_q == 6'd29) ? tms34010_pkg_B_COUNT_IDX : (is_line && (state_q == 6'd30) ? tms34010_pkg_B_OFFSET_IDX : (((decoded[51-:7] == 7'd93) || decoded[3]) || is_drav ? tms34010_pkg_B_OFFSET_IDX : tms34010_pkg_CPW_WEND_IDX))))));
	reg dsj_precondition;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (decoded[51-:7])
			7'd36, 7'd40: dsj_precondition = 1'b1;
			7'd37: dsj_precondition = st_z;
			7'd38: dsj_precondition = !st_z;
			default: dsj_precondition = 1'b1;
		endcase
	end
	wire dsj_rd_nonzero;
	assign dsj_rd_nonzero = alu_result != {32 {1'sb0}};
	wire mmfm_pop_wr;
	assign mmfm_pop_wr = ((state_q == 6'd6) && is_mmfm) && mem_ack;
	wire is_mv_store;
	wire is_mv_load;
	wire mv_postinc;
	wire mv_predec;
	wire mv_incdec;
	wire [31:0] mv_ptr;
	wire [31:0] mv_addr;
	wire [31:0] mv_ptr_new;
	wire mv_load_ptr_wr;
	assign is_mv_store = decoded[51-:7] == 7'd74;
	assign is_mv_load = decoded[51-:7] == 7'd75;
	assign mv_postinc = decoded[7-:2] == 2'b01;
	assign mv_predec = decoded[7-:2] == 2'b10;
	assign mv_incdec = mv_postinc || mv_predec;
	assign mv_ptr = (is_mv_store ? rf_rs2_data : rf_rs1_data);
	assign mv_load_ptr_wr = (((state_q == 6'd6) && is_mv_load) && mv_incdec) && mem_ack;
	wire [4:0] mv_fs_raw;
	wire [5:0] mv_fs;
	wire mv_fe;
	wire [31:0] mv_fs_ext;
	wire [31:0] mv_fmask;
	reg [31:0] mv_load_data;
	localparam [31:0] tms34010_pkg_ST_FS0_HI = 4;
	localparam [31:0] tms34010_pkg_ST_FS0_LO = 0;
	localparam [31:0] tms34010_pkg_ST_FS1_HI = 10;
	localparam [31:0] tms34010_pkg_ST_FS1_LO = 6;
	assign mv_fs_raw = (instr_word_q[9] ? st_value[tms34010_pkg_ST_FS1_HI:tms34010_pkg_ST_FS1_LO] : st_value[tms34010_pkg_ST_FS0_HI:tms34010_pkg_ST_FS0_LO]);
	function automatic signed [5:0] sv2v_cast_13C0F_signed;
		input reg signed [5:0] inp;
		sv2v_cast_13C0F_signed = inp;
	endfunction
	function automatic [5:0] sv2v_cast_13C0F;
		input reg [5:0] inp;
		sv2v_cast_13C0F = inp;
	endfunction
	assign mv_fs = (decoded[5] ? sv2v_cast_13C0F_signed(8) : (decoded[4] ? io_psize[5:0] : (mv_fs_raw == 5'd0 ? sv2v_cast_13C0F(tms34010_pkg_DATA_WIDTH) : {1'b0, mv_fs_raw})));
	localparam [31:0] tms34010_pkg_ST_FE0_BIT = 5;
	localparam [31:0] tms34010_pkg_ST_FE1_BIT = 11;
	assign mv_fe = (decoded[5] ? 1'b1 : (decoded[4] ? 1'b0 : (instr_word_q[9] ? st_value[tms34010_pkg_ST_FE1_BIT] : st_value[tms34010_pkg_ST_FE0_BIT])));
	assign mv_fs_ext = sv2v_cast_DEBC9(mv_fs);
	assign mv_fmask = (mv_fs >= sv2v_cast_13C0F(tms34010_pkg_DATA_WIDTH) ? {32 {1'sb1}} : (32'd1 << mv_fs) - 32'd1);
	always @(*) begin
		if (_sv2v_0)
			;
		if (mv_fs >= sv2v_cast_13C0F(tms34010_pkg_DATA_WIDTH))
			mv_load_data = mv_load_data_q;
		else if (mv_fe && mv_load_data_q[mv_fs - 6'd1])
			mv_load_data = mv_load_data_q | ~mv_fmask;
		else
			mv_load_data = mv_load_data_q & mv_fmask;
	end
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				mv_load_data_q <= 1'sb0;
			else if (((state_q == 6'd6) && mem_ack) && (((decoded[51-:7] == 7'd75) || (decoded[51-:7] == 7'd78)) || (decoded[51-:7] == 7'd80)))
				mv_load_data_q <= mem_rdata_eff;
		end
	wire [31:0] pixt_pmask_field;
	wire [31:0] pixt_processed;
	wire pixt_transp;
	wire [31:0] pixt_merged;
	assign pixt_rmw = decoded[4] && is_mv_store;
	assign pixt_pmask_field = {{16 {1'b0}}, io_pmask} & mv_fmask;
	assign pixt_processed = ppop_apply(rf_rs1_data, pix_dest_q, io_control[tms34010_pkg_CTRL_PPOP_HI:tms34010_pkg_CTRL_PPOP_LO], mv_fmask);
	assign pixt_transp = io_control[tms34010_pkg_CTRL_T_BIT] && ((pixt_processed & mv_fmask) == {32 {1'sb0}});
	reg [31:0] pixt_wstart_q;
	reg [31:0] pixt_wend_q;
	wire pixt_in_window;
	wire pixt_clip_out;
	assign pixt_xy_win = (pixt_rmw && decoded[3]) && (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] != 2'd0);
	assign pixt_in_window = (SHARED_WINDOW ? shared_window_inside : (((mv_ptr[15:0] >= pixt_wstart_q[15:0]) && (mv_ptr[15:0] <= pixt_wend_q[15:0])) && (mv_ptr[31:16] >= pixt_wstart_q[31:16])) && (mv_ptr[31:16] <= pixt_wend_q[31:16]));
	assign pixt_clip_out = pixt_xy_win && ((io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] == 2'd1) || !pixt_in_window);
	assign pixt_merged = (SHARED_PIXEL ? shared_pixel_result : (pixt_transp || pixt_clip_out ? pix_dest_q : (pixt_processed & ~pixt_pmask_field) | (pix_dest_q & pixt_pmask_field)));
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				pixt_wstart_q <= 1'sb0;
				pixt_wend_q <= 1'sb0;
				pixt_inside_q <= 1'b0;
			end
			else begin
				if (state_q == 6'd37) begin
					pixt_wstart_q <= rf_rs1_data;
					pixt_wend_q <= rf_rs2_data;
				end
				if ((((state_q == 6'd6) && pixt_rmw) && (mem_op_step == 2'd1)) && mem_ack)
					pixt_inside_q <= pixt_in_window;
			end
		end
	reg [31:0] window_start;
	reg [31:0] window_end;
	reg [31:0] window_point;
	reg [31:0] window_array_origin;
	reg [15:0] window_dx;
	reg [15:0] window_dy;
	reg [15:0] window_col;
	reg [15:0] window_row;
	reg [15:0] window_x0;
	reg [15:0] window_y0;
	reg [15:0] window_x1;
	reg [15:0] window_y1;
	reg [15:0] window_calc_x;
	reg [15:0] window_calc_y;
	reg window_is_array;
	reg window_corner_test;
	reg window_hit_test;
	always @(*) begin
		if (_sv2v_0)
			;
		window_start = pixt_wstart_q;
		window_end = pixt_wend_q;
		window_point = mv_ptr;
		window_array_origin = pblt_dst_xy_raw_q;
		window_dx = pblt_dx_q;
		window_dy = pblt_dy_q;
		window_col = pblt_x_q;
		window_row = pblt_y_q;
		window_is_array = is_fill || is_pblt;
		window_corner_test = (((state_q == 6'd21) || (state_q == 6'd25)) || (state_q == 6'd22)) || (state_q == 6'd26);
		window_hit_test = (state_q == 6'd25) || (state_q == 6'd26);
		if (is_fill) begin
			window_start = fill_wstart_q;
			window_end = fill_wend_q;
			window_array_origin = fill_daddr_raw_q;
			window_dx = fill_dx_q;
			window_dy = fill_dy_q;
			window_col = fill_x_q;
			window_row = fill_y_q;
		end
		else if (is_pblt) begin
			window_start = pblt_wstart_q;
			window_end = pblt_wend_q;
		end
		else if (is_line) begin
			window_start = line_wstart_q;
			window_end = line_wend_q;
			window_point = line_daddr_q;
		end
		else if (is_drav) begin
			window_start = rf_rs1_data;
			window_end = rf_rs2_data;
			window_point = drav_rd_q;
		end
		if ((state_q == 6'd21) || (state_q == 6'd22)) begin
			window_start = rf_rs1_data;
			window_end = rf_rs2_data;
		end
		window_calc_x = window_array_origin[15:0] + (window_corner_test ? window_dx - 16'd1 : window_col);
		window_calc_y = window_array_origin[31:16] + (window_corner_test ? window_dy - 16'd1 : window_row);
		window_x0 = window_point[15:0];
		window_x1 = window_point[15:0];
		window_y0 = window_point[31:16];
		window_y1 = window_point[31:16];
		if (window_is_array) begin
			window_x0 = (window_corner_test ? window_array_origin[15:0] : window_calc_x);
			window_y0 = (window_corner_test ? window_array_origin[31:16] : window_calc_y);
			window_x1 = window_calc_x;
			window_y1 = window_calc_y;
		end
	end
	assign shared_window_inside = ((((window_hit_test ? window_x1 : window_x0) >= window_start[15:0]) && ((window_hit_test ? window_x0 : window_x1) <= window_end[15:0])) && ((window_hit_test ? window_y1 : window_y0) >= window_start[31:16])) && ((window_hit_test ? window_y0 : window_y1) <= window_end[31:16]);
	wire [15:0] pix_xy_conv;
	wire [4:0] pix_xy_yshift;
	wire [31:0] pix_xy_linear;
	assign pix_xy_conv = (is_mv_store ? io_convdp : io_convsp);
	assign pix_xy_yshift = 5'd31 - pix_xy_conv[4:0];
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (io_psize[4:0])
			5'd1: pix_xy_xsh = 5'd0;
			5'd2: pix_xy_xsh = 5'd1;
			5'd4: pix_xy_xsh = 5'd2;
			5'd8: pix_xy_xsh = 5'd3;
			5'd16: pix_xy_xsh = 5'd4;
			default: pix_xy_xsh = 5'd0;
		endcase
	end
	assign pix_xy_linear = (SHARED_XY ? shared_xy0_result : (({{16 {mv_ptr[31]}}, mv_ptr[31:16]} << pix_xy_yshift) | ({16'b0000000000000000, mv_ptr[15:0]} << pix_xy_xsh)) + rf_rs3_data);
	assign mv_addr = (decoded[3] ? pix_xy_linear : (mv_predec ? (SHARED_ADDRESS ? shared_address_sum : mv_ptr - mv_fs_ext) : mv_ptr));
	assign mv_ptr_new = (SHARED_ADDRESS ? shared_address_sum : (mv_predec ? mv_ptr - mv_fs_ext : mv_ptr + mv_fs_ext));
	wire [4:0] pix_xy_dst_yshift;
	assign pix_xy_dst_yshift = 5'd31 - io_convdp[4:0];
	assign pix_xy_dst_linear = (SHARED_XY ? shared_xy1_result : (({{16 {rf_rs2_data[31]}}, rf_rs2_data[31:16]} << pix_xy_dst_yshift) | ({16'b0000000000000000, rf_rs2_data[15:0]} << pix_xy_xsh)) + rf_rs3_data);
	wire is_mv_m2m;
	wire m2m_same_reg;
	wire m2m_src_wr;
	wire [31:0] m2m_src_addr;
	wire [31:0] m2m_dst_addr;
	wire [31:0] m2m_src_new;
	wire [31:0] m2m_dst_new;
	assign is_mv_m2m = decoded[51-:7] == 7'd76;
	assign m2m_same_reg = decoded[39-:4] == decoded[43-:4];
	assign m2m_src_addr = (decoded[3] ? pix_xy_linear : (mv_predec ? (SHARED_ADDRESS ? shared_address_sum : rf_rs1_data - mv_fs_ext) : rf_rs1_data));
	assign m2m_dst_addr = (decoded[3] ? pix_xy_dst_linear : (mv_predec ? (SHARED_ADDRESS ? shared_address_sum : rf_rs2_data - mv_fs_ext) : rf_rs2_data));
	assign m2m_src_new = (SHARED_ADDRESS ? shared_address_sum : (mv_predec ? rf_rs1_data - mv_fs_ext : rf_rs1_data + mv_fs_ext));
	assign m2m_dst_new = (SHARED_ADDRESS ? shared_address_sum : (mv_predec ? rf_rs2_data - mv_fs_ext : rf_rs2_data + mv_fs_ext));
	assign m2m_src_wr = ((((state_q == 6'd6) && is_mv_m2m) && mv_incdec) && (mem_op_step == 2'd0)) && mem_ack;
	reg [31:0] address_a;
	reg [31:0] address_b;
	reg address_subtract;
	always @(*) begin
		if (_sv2v_0)
			;
		address_a = rf_rs1_data;
		address_b = mv_fs_ext;
		address_subtract = mv_predec;
		case (decoded[51-:7])
			7'd74: address_a = rf_rs2_data;
			7'd76: address_a = ((state_q == 6'd6) && (mem_op_step == 2'd0) ? rf_rs1_data : rf_rs2_data);
			7'd79: begin
				address_a = rf_rs2_data;
				address_b = imm32;
				address_subtract = 1'b0;
			end
			7'd80: begin
				address_b = imm32;
				address_subtract = 1'b0;
			end
			7'd100: begin
				address_a = (mem_op_step == 2'd0 ? rf_rs1_data : rf_rs2_data);
				address_b = (mem_op_step == 2'd0 ? imm32 : imm2_off_sext);
				address_subtract = 1'b0;
			end
			7'd101: begin
				address_a = (state_q == 6'd7 ? rf_rs2_data : rf_rs1_data);
				address_b = (state_q == 6'd7 ? mv_fs_ext : imm32);
				address_subtract = 1'b0;
			end
			7'd102: begin
				address_a = rf_rs2_data;
				address_subtract = 1'b0;
			end
			7'd11: begin
				address_a = pc_value;
				address_b = sv2v_cast_DEBC9_signed(disp_signed_12);
				address_subtract = 1'b0;
			end
			7'd34, 7'd36, 7'd37, 7'd38, 7'd69: begin
				address_a = pc_value;
				address_b = sv2v_cast_DEBC9_signed(disp_signed_20);
				address_subtract = 1'b0;
			end
			7'd40: begin
				address_a = pc_value;
				address_b = sv2v_cast_DEBC9_signed(dsjs_disp_bits);
				address_subtract = 1'b0;
			end
			default:
				;
		endcase
	end
	assign shared_address_sum = (address_a + (address_b ^ {tms34010_pkg_DATA_WIDTH {address_subtract}})) + sv2v_cast_DEBC9(address_subtract);
	wire fill_wb;
	wire pblt_wb_saddr;
	wire pblt_wb_daddr;
	wire graphics_wb;
	assign fill_wb = state_q == 6'd11;
	assign pblt_wb_saddr = state_q == 6'd14;
	assign pblt_wb_daddr = state_q == 6'd15;
	wire line_wb_d;
	wire line_wb_daddr;
	wire line_wb_count;
	wire line_wb;
	assign line_wb_d = state_q == 6'd33;
	assign line_wb_daddr = state_q == 6'd34;
	assign line_wb_count = state_q == 6'd35;
	assign line_wb = (line_wb_d || line_wb_daddr) || line_wb_count;
	assign graphics_wb = ((fill_wb || pblt_wb_saddr) || pblt_wb_daddr) || line_wb;
	wire int_sp_wb;
	assign int_sp_wb = (state_q == 6'd20) && int_push_q;
	assign rf_wr_en = (((((((((state_q == 6'd7) && decoded[14]) && dsj_precondition) && !(is_mv_m2m && m2m_same_reg)) && !(is_div && div_v)) || mmfm_pop_wr) || mv_load_ptr_wr) || m2m_src_wr) || graphics_wb) || int_sp_wb;
	assign rf_wr_file = (int_sp_wb ? 1'b0 : (graphics_wb ? 1'b1 : decoded[44]));
	localparam [3:0] tms34010_pkg_REG_SP_IDX = 4'hf;
	assign rf_wr_idx = (int_sp_wb ? tms34010_pkg_REG_SP_IDX : (line_wb_count ? tms34010_pkg_B_COUNT_IDX : ((fill_wb || pblt_wb_daddr) || line_wb_daddr ? tms34010_pkg_B_DADDR_IDX : (pblt_wb_saddr || line_wb_d ? tms34010_pkg_B_SADDR_IDX : (mmfm_pop_wr ? mm_iter_idx : (mv_load_ptr_wr || m2m_src_wr ? decoded[39-:4] : ((is_mpy || is_div) && pair_wb_step ? decoded[43-:4] + 4'd1 : decoded[43-:4])))))));
	wire [4:0] exgf_cur_fs;
	wire exgf_cur_fe;
	wire [31:0] exgf_new_rd;
	reg [31:0] exgf_new_st;
	assign exgf_cur_fs = (instr_word_q[9] ? st_value[tms34010_pkg_ST_FS1_HI:tms34010_pkg_ST_FS1_LO] : st_value[tms34010_pkg_ST_FS0_HI:tms34010_pkg_ST_FS0_LO]);
	assign exgf_cur_fe = (instr_word_q[9] ? st_value[tms34010_pkg_ST_FE1_BIT] : st_value[tms34010_pkg_ST_FE0_BIT]);
	assign exgf_new_rd = {{26 {1'b0}}, exgf_cur_fe, exgf_cur_fs};
	always @(*) begin
		if (_sv2v_0)
			;
		exgf_new_st = st_value;
		if (instr_word_q[9]) begin
			exgf_new_st[tms34010_pkg_ST_FS1_HI:tms34010_pkg_ST_FS1_LO] = rf_rs2_data[4:0];
			exgf_new_st[tms34010_pkg_ST_FE1_BIT] = rf_rs2_data[5];
		end
		else begin
			exgf_new_st[tms34010_pkg_ST_FS0_HI:tms34010_pkg_ST_FS0_LO] = rf_rs2_data[4:0];
			exgf_new_st[tms34010_pkg_ST_FE0_BIT] = rf_rs2_data[5];
		end
	end
	wire [15:0] xy_rs_x;
	wire [15:0] xy_rs_y;
	wire [15:0] xy_rd_x;
	wire [15:0] xy_rd_y;
	wire [15:0] xy_x_add;
	wire [15:0] xy_y_add;
	wire [15:0] xy_x_sub;
	wire [15:0] xy_y_sub;
	wire [31:0] addxy_result;
	wire [31:0] subxy_result;
	wire [3:0] addxy_flags;
	wire [3:0] subxy_flags;
	assign xy_rs_x = rf_rs1_data[15:0];
	assign xy_rs_y = rf_rs1_data[31:16];
	assign xy_rd_x = rf_rs2_data[15:0];
	assign xy_rd_y = rf_rs2_data[31:16];
	assign xy_x_add = (SHARED_XY_ARITH ? shared_xy_arith_result[15:0] : xy_rd_x + xy_rs_x);
	assign xy_y_add = (SHARED_XY_ARITH ? shared_xy_arith_result[31:16] : xy_rd_y + xy_rs_y);
	assign xy_x_sub = (SHARED_XY_ARITH ? shared_xy_arith_result[15:0] : xy_rd_x - xy_rs_x);
	assign xy_y_sub = (SHARED_XY_ARITH ? shared_xy_arith_result[31:16] : xy_rd_y - xy_rs_y);
	assign addxy_result = {xy_y_add, xy_x_add};
	assign subxy_result = {xy_y_sub, xy_x_sub};
	assign addxy_flags = {xy_x_add == 16'd0, xy_y_add[15], xy_y_add == 16'd0, xy_x_add[15]};
	assign subxy_flags = {xy_x_sub == 16'd0, $signed(xy_rd_y) < $signed(xy_rs_y), xy_y_sub == 16'd0, $signed(xy_rd_x) < $signed(xy_rs_x)};
	wire [3:0] cmpxy_flags;
	assign cmpxy_flags = {xy_x_sub == 16'd0, xy_y_sub[15], xy_y_sub == 16'd0, xy_x_sub[15]};
	reg [31:0] xy_arith_a;
	reg [31:0] xy_arith_b;
	reg xy_arith_subtract;
	always @(*) begin
		if (_sv2v_0)
			;
		xy_arith_a = rf_rs2_data;
		xy_arith_b = rf_rs1_data;
		xy_arith_subtract = (decoded[51-:7] == 7'd84) || (decoded[51-:7] == 7'd85);
		if (is_drav) begin
			xy_arith_a = drav_rd_q;
			xy_arith_b = drav_rs_q;
		end
		else if (is_line) begin
			xy_arith_a = line_daddr_q;
			xy_arith_b = (line_branch ? line_inc1_q : line_inc2_q);
		end
	end
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	assign shared_xy_arith_result[15:0] = (xy_arith_a[15:0] + (xy_arith_b[15:0] ^ {16 {xy_arith_subtract}})) + sv2v_cast_16(xy_arith_subtract);
	assign shared_xy_arith_result[31:16] = (xy_arith_a[31:16] + (xy_arith_b[31:16] ^ {16 {xy_arith_subtract}})) + sv2v_cast_16(xy_arith_subtract);
	wire [15:0] cpw_pt_x;
	wire [15:0] cpw_pt_y;
	wire [15:0] cpw_ws_x;
	wire [15:0] cpw_ws_y;
	wire [15:0] cpw_we_x;
	wire [15:0] cpw_we_y;
	wire cpw_b5;
	wire cpw_b6;
	wire cpw_b7;
	wire cpw_b8;
	wire [31:0] cpw_result;
	wire [3:0] cpw_flags;
	assign cpw_pt_x = rf_rs1_data[15:0];
	assign cpw_pt_y = rf_rs1_data[31:16];
	assign cpw_ws_x = rf_rs2_data[15:0];
	assign cpw_ws_y = rf_rs2_data[31:16];
	assign cpw_we_x = rf_rs3_data[15:0];
	assign cpw_we_y = rf_rs3_data[31:16];
	assign cpw_b5 = $signed(cpw_ws_x) > $signed(cpw_pt_x);
	assign cpw_b6 = $signed(cpw_pt_x) > $signed(cpw_we_x);
	assign cpw_b7 = $signed(cpw_ws_y) > $signed(cpw_pt_y);
	assign cpw_b8 = $signed(cpw_pt_y) > $signed(cpw_we_y);
	assign cpw_result = {{23 {1'b0}}, cpw_b8, cpw_b7, cpw_b6, cpw_b5, 5'b00000};
	assign cpw_flags = {3'b000, ((cpw_b5 | cpw_b6) | cpw_b7) | cpw_b8};
	wire [4:0] cvxyl_ydp_shift;
	reg [4:0] cvxyl_xsh;
	wire [31:0] cvxyl_ypart;
	wire [31:0] cvxyl_xpart;
	wire [31:0] cvxyl_result;
	assign cvxyl_ydp_shift = 5'd31 - io_convdp[4:0];
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (io_psize[4:0])
			5'd1: cvxyl_xsh = 5'd0;
			5'd2: cvxyl_xsh = 5'd1;
			5'd4: cvxyl_xsh = 5'd2;
			5'd8: cvxyl_xsh = 5'd3;
			5'd16: cvxyl_xsh = 5'd4;
			default: cvxyl_xsh = 5'd0;
		endcase
	end
	assign cvxyl_ypart = {{16 {rf_rs1_data[31]}}, rf_rs1_data[31:16]} << cvxyl_ydp_shift;
	assign cvxyl_xpart = {16'b0000000000000000, rf_rs1_data[15:0]} << cvxyl_xsh;
	assign cvxyl_result = (SHARED_XY ? shared_xy0_result : (cvxyl_ypart | cvxyl_xpart) + rf_rs3_data);
	reg [31:0] shared_pixel_src;
	reg [31:0] shared_pixel_dst;
	reg [31:0] shared_pixel_mask;
	wire [31:0] shared_pixel_processed;
	wire [31:0] shared_pixel_pmask;
	reg shared_pixel_clip;
	wire shared_pixel_transp;
	always @(*) begin
		if (_sv2v_0)
			;
		shared_pixel_src = rf_rs1_data;
		shared_pixel_dst = pix_dest_q;
		shared_pixel_mask = mv_fmask;
		shared_pixel_clip = pixt_clip_out;
		case (state_q)
			6'd10: begin
				shared_pixel_src = fill_color_q;
				shared_pixel_dst = fill_dest_q;
				shared_pixel_mask = fill_pixel_mask;
				shared_pixel_clip = fill_clip_out;
			end
			6'd13: begin
				shared_pixel_src = pblt_src_eff;
				shared_pixel_dst = pblt_dst_pix_q;
				shared_pixel_mask = pblt_pixel_mask;
				shared_pixel_clip = pblt_clip_out;
			end
			6'd27: begin
				shared_pixel_dst = drav_dest_q;
				shared_pixel_mask = drav_pixel_mask;
				shared_pixel_clip = 1'b0;
			end
			6'd32: begin
				shared_pixel_src = line_color_q;
				shared_pixel_dst = line_dest_q;
				shared_pixel_mask = line_pixel_mask;
				shared_pixel_clip = line_clip_out;
			end
			default:
				;
		endcase
	end
	assign shared_pixel_processed = ppop_apply(shared_pixel_src, shared_pixel_dst, io_control[tms34010_pkg_CTRL_PPOP_HI:tms34010_pkg_CTRL_PPOP_LO], shared_pixel_mask);
	assign shared_pixel_pmask = {{16 {1'b0}}, io_pmask} & shared_pixel_mask;
	assign shared_pixel_transp = io_control[tms34010_pkg_CTRL_T_BIT] && ((shared_pixel_processed & shared_pixel_mask) == {32 {1'sb0}});
	assign shared_pixel_result = (shared_pixel_transp || shared_pixel_clip ? shared_pixel_dst : (shared_pixel_processed & ~shared_pixel_pmask) | (shared_pixel_dst & shared_pixel_pmask));
	reg [31:0] shared_xy0_raw;
	reg [31:0] shared_xy1_raw;
	reg [31:0] shared_xy0_offset;
	reg [4:0] shared_xy0_yshift;
	always @(*) begin
		if (_sv2v_0)
			;
		shared_xy0_raw = mv_ptr;
		shared_xy1_raw = rf_rs2_data;
		shared_xy0_offset = rf_rs3_data;
		shared_xy0_yshift = pix_xy_yshift;
		if (decoded[51-:7] == 7'd93) begin
			shared_xy0_raw = rf_rs1_data;
			shared_xy0_yshift = 5'd31 - io_convdp[4:0];
		end
		case (state_q)
			6'd9: begin
				shared_xy0_raw = fill_daddr_raw_q;
				shared_xy0_yshift = 5'd31 - io_convdp[4:0];
			end
			6'd12: begin
				shared_xy0_raw = pblt_src_addr_q;
				shared_xy1_raw = pblt_dst_addr_q;
				shared_xy0_yshift = 5'd31 - io_convsp[4:0];
			end
			6'd32: begin
				shared_xy0_raw = line_daddr_q;
				shared_xy0_offset = line_offset_q;
				shared_xy0_yshift = 5'd31 - io_convdp[4:0];
			end
			default:
				;
		endcase
	end
	assign shared_xy0_result = (({{16 {shared_xy0_raw[31]}}, shared_xy0_raw[31:16]} << shared_xy0_yshift) | ({16'b0000000000000000, shared_xy0_raw[15:0]} << pix_xy_xsh)) + shared_xy0_offset;
	assign shared_xy1_result = (({{16 {shared_xy1_raw[31]}}, shared_xy1_raw[31:16]} << (5'd31 - io_convdp[4:0])) | ({16'b0000000000000000, shared_xy1_raw[15:0]} << pix_xy_xsh)) + rf_rs3_data;
	wire signed [63:0] mpy_sprod;
	wire [63:0] mpy_uprod;
	wire [63:0] mpy_product;
	reg [63:0] mpy_product_q;
	assign is_mpy = (decoded[51-:7] == 7'd87) || (decoded[51-:7] == 7'd88);
	assign mpy_signed = decoded[51-:7] == 7'd87;
	assign mpy_rd_even = decoded[40] == 1'b0;
	wire [4:0] mpy_fs1;
	wire [31:0] mpy_fmask;
	reg [31:0] mpy_rs_field;
	assign mpy_fs1 = st_value[tms34010_pkg_ST_FS1_HI:tms34010_pkg_ST_FS1_LO];
	assign mpy_fmask = (32'd1 << mpy_fs1) - 32'd1;
	always @(*) begin
		if (_sv2v_0)
			;
		if (mpy_fs1 == 5'd0)
			mpy_rs_field = rf_rs1_data;
		else if (mpy_signed && rf_rs1_data[mpy_fs1 - 5'd1])
			mpy_rs_field = (rf_rs1_data & mpy_fmask) | ~mpy_fmask;
		else
			mpy_rs_field = rf_rs1_data & mpy_fmask;
	end
	assign mpy_sprod = $signed(rf_rs2_data) * $signed(mpy_rs_field);
	assign mpy_uprod = rf_rs2_data * mpy_rs_field;
	assign mpy_product = (mpy_signed ? $unsigned(mpy_sprod) : mpy_uprod);
	wire is_signed_div;
	wire is_div_mod;
	wire div_rd_even;
	wire div_use_pair;
	reg [63:0] div_dividend;
	wire [31:0] div_divisor;
	wire [31:0] div_quotient;
	wire [31:0] div_remainder;
	wire div_start;
	wire div_busy;
	wire div_done;
	wire div_overflow;
	assign is_divu = decoded[51-:7] == 7'd89;
	assign is_modu = decoded[51-:7] == 7'd90;
	assign is_divs = decoded[51-:7] == 7'd91;
	assign is_mods = decoded[51-:7] == 7'd92;
	assign is_div = ((is_divu || is_modu) || is_divs) || is_mods;
	assign is_signed_div = is_divs || is_mods;
	assign is_div_mod = is_modu || is_mods;
	assign div_rd_even = decoded[40] == 1'b0;
	assign div_use_pair = (is_divu || is_divs) && div_rd_even;
	wire div_dvd_sign;
	wire div_dvs_sign;
	wire div_result_neg;
	reg div_dvd_sign_q;
	reg div_dvs_sign_q;
	assign div_dvd_sign = is_signed_div && rf_rs2_data[31];
	assign div_dvs_sign = is_signed_div && rf_rs1_data[31];
	assign div_result_neg = div_dvd_sign_q ^ div_dvs_sign_q;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				div_dvd_sign_q <= 1'b0;
				div_dvs_sign_q <= 1'b0;
			end
			else if ((state_q == 6'd5) && is_div) begin
				div_dvd_sign_q <= div_dvd_sign;
				div_dvs_sign_q <= div_dvs_sign;
			end
		end
	wire [31:0] rd_abs;
	wire [63:0] raw64;
	wire [63:0] abs64;
	assign rd_abs = (rf_rs2_data[31] ? ~rf_rs2_data + 1'b1 : rf_rs2_data);
	assign raw64 = {rf_rs2_data, rf_rs3_data};
	assign abs64 = (rf_rs2_data[31] ? ~raw64 + 1'b1 : raw64);
	always @(*) begin
		if (_sv2v_0)
			;
		if (!is_signed_div)
			div_dividend = (div_use_pair ? raw64 : {{tms34010_pkg_DATA_WIDTH {1'b0}}, rf_rs2_data});
		else if (div_use_pair)
			div_dividend = abs64;
		else
			div_dividend = {{tms34010_pkg_DATA_WIDTH {1'b0}}, rd_abs};
	end
	assign div_divisor = (div_dvs_sign ? ~rf_rs1_data + 1'b1 : rf_rs1_data);
	assign div_start = (state_q == 6'd5) && is_div;
	tms34010_divider u_divider(
		.clk(clk),
		.ce_cpu(ce_cpu),
		.rst(rst),
		.start(div_start),
		.dividend(div_dividend),
		.divisor(div_divisor),
		.busy(div_busy),
		.done(div_done),
		.quotient(div_quotient),
		.remainder(div_remainder),
		.overflow(div_overflow)
	);
	wire [31:0] div_quot_out;
	wire [31:0] div_rem_out;
	wire [31:0] div_result_main;
	assign div_quot_out = (div_result_neg ? ~div_quotient + 1'b1 : div_quotient);
	assign div_rem_out = (div_dvd_sign_q ? ~div_remainder + 1'b1 : div_remainder);
	assign div_result_main = (is_div_mod ? div_rem_out : div_quot_out);
	assign div_signed_ovf = div_overflow || (is_signed_div && (div_result_neg ? div_quotient[31] && (div_quotient[30:0] != {31 {1'sb0}}) : div_quotient[31]));
	assign div_v = (is_signed_div ? div_signed_ovf : div_overflow);
	assign is_pair_wb = (is_mpy && mpy_rd_even) || (div_use_pair && !div_v);
	assign pair_second_pass = is_pair_wb && (pair_wb_step == 1'b0);
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				mpy_product_q <= 1'sb0;
				pair_wb_step <= 1'b0;
			end
			else begin
				if ((state_q == 6'd5) && is_mpy)
					mpy_product_q <= mpy_product;
				if (state_q == 6'd7)
					pair_wb_step <= (pair_second_pass ? 1'b1 : 1'b0);
				else
					pair_wb_step <= 1'b0;
			end
		end
	wire [4:0] fs_selected;
	reg [31:0] field_mask;
	reg field_msb;
	reg [31:0] sext_result;
	reg [31:0] zext_result;
	assign fs_selected = (instr_word_q[9] ? st_value[tms34010_pkg_ST_FS1_HI:tms34010_pkg_ST_FS1_LO] : st_value[tms34010_pkg_ST_FS0_HI:tms34010_pkg_ST_FS0_LO]);
	always @(*) begin
		if (_sv2v_0)
			;
		if (fs_selected == 5'd0) begin
			field_mask = 1'sb1;
			field_msb = rf_rs2_data[31];
			sext_result = rf_rs2_data;
			zext_result = rf_rs2_data;
		end
		else begin
			field_mask = (32'd1 << fs_selected) - 32'd1;
			field_msb = rf_rs2_data[fs_selected - 5'd1];
			sext_result = (field_msb ? (rf_rs2_data & field_mask) | ~field_mask : rf_rs2_data & field_mask);
			zext_result = rf_rs2_data & field_mask;
		end
	end
	reg [4:0] lmo_bit_pos;
	reg [31:0] lmo_result;
	function automatic signed [4:0] sv2v_cast_5_signed;
		input reg signed [4:0] inp;
		sv2v_cast_5_signed = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		lmo_bit_pos = 5'd0;
		begin : sv2v_autoblock_4
			reg signed [31:0] i;
			for (i = 0; i < tms34010_pkg_DATA_WIDTH; i = i + 1)
				if (rf_rs1_data[i])
					lmo_bit_pos = sv2v_cast_5_signed(i);
		end
		if (rf_rs1_data == {32 {1'sb0}})
			lmo_result = 1'sb0;
		else
			lmo_result = {{27 {1'b0}}, ~lmo_bit_pos};
	end
	localparam [31:0] tms34010_pkg_REV_VALUE = 32'h00000008;
	localparam [31:0] tms34010_pkg_WORD_BIT_SIZE_2 = sv2v_cast_DEBC9(64);
	always @(*) begin
		if (_sv2v_0)
			;
		if (int_sp_wb)
			rf_wr_data = rf_sp - tms34010_pkg_WORD_BIT_SIZE_2;
		else
			(* full_case, parallel_case *)
			case (decoded[51-:7])
				7'd81: rf_wr_data = {rf_rs2_data[31:16], rf_rs1_data[15:0]};
				7'd82: rf_wr_data = {rf_rs1_data[31:16], rf_rs2_data[15:0]};
				7'd83: rf_wr_data = addxy_result;
				7'd84: rf_wr_data = subxy_result;
				7'd97: rf_wr_data = drav_advance;
				7'd86: rf_wr_data = cpw_result;
				7'd87, 7'd88: rf_wr_data = (mpy_rd_even ? (pair_wb_step ? mpy_product_q[31:0] : mpy_product_q[63:32]) : mpy_product_q[31:0]);
				7'd89, 7'd91: rf_wr_data = (div_rd_even && pair_wb_step ? div_rem_out : div_quot_out);
				7'd90, 7'd92: rf_wr_data = div_rem_out;
				7'd47: rf_wr_data = st_value;
				7'd72: rf_wr_data = mm_rp_q;
				7'd73: rf_wr_data = (mmfm_pop_wr ? mem_rdata_eff : mm_rp_q);
				7'd74: rf_wr_data = mv_ptr_new;
				7'd75: rf_wr_data = (mv_load_ptr_wr ? mv_ptr_new : mv_load_data);
				7'd76: rf_wr_data = (m2m_src_wr ? m2m_src_new : m2m_dst_new);
				7'd78, 7'd80: rf_wr_data = mv_load_data;
				7'd101, 7'd102: rf_wr_data = (SHARED_ADDRESS ? shared_address_sum : rf_rs2_data + mv_fs_ext);
				7'd93: rf_wr_data = cvxyl_result;
				7'd94, 7'd95: rf_wr_data = fill_addr_q;
				7'd96: rf_wr_data = (pblt_wb_saddr ? pblt_src_addr_q : (decoded[1] ? {pblt_dst_xy_raw_q[31:16] + pblt_dy_q, pblt_dst_xy_raw_q[15:0]} : pblt_dst_addr_q));
				7'd98: rf_wr_data = (line_wb_d ? line_d_q : (line_wb_daddr ? line_daddr_q : line_count_q));
				7'd54, 7'd55: rf_wr_data = pc_value;
				7'd56: rf_wr_data = tms34010_pkg_REV_VALUE;
				7'd57: rf_wr_data = lmo_result;
				7'd59: rf_wr_data = sext_result;
				7'd60: rf_wr_data = zext_result;
				7'd61: rf_wr_data = exgf_new_rd;
				default: rf_wr_data = (decoded[24] ? shifter_result : alu_result);
			endcase
	end
	assign alu_op = decoded[31-:4];
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (decoded[51-:7])
			7'd5, 7'd33, 7'd7, 7'd10, 7'd12, 7'd13, 7'd14, 7'd15, 7'd41, 7'd16, 7'd17, 7'd18, 7'd24, 7'd25, 7'd26, 7'd27, 7'd28, 7'd29, 7'd36, 7'd37, 7'd38, 7'd40, 7'd43, 7'd44: alu_a = rf_rs2_data;
			7'd42: alu_a = 1'sb0;
			7'd64, 7'd65, 7'd66, 7'd68, 7'd69, 7'd67, 7'd70, 7'd71: alu_a = rf_rs2_data;
			default: alu_a = rf_rs1_data;
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (decoded[51-:7])
			7'd17, 7'd18, 7'd25, 7'd26: alu_b = ~imm32;
			7'd1, 7'd2, 7'd16, 7'd24, 7'd27, 7'd28, 7'd29: alu_b = imm32;
			7'd3, 7'd12, 7'd13: alu_b = (decoded[23-:5] == 5'd0 ? 32'd32 : {{27 {1'b0}}, decoded[23-:5]});
			7'd36, 7'd37, 7'd38, 7'd40: alu_b = {{27 {1'b0}}, decoded[23-:5]};
			7'd43: alu_b = 32'd1 << decoded[23-:5];
			7'd44: alu_b = 32'd1 << rf_rs1_data[4:0];
			7'd64, 7'd65, 7'd66, 7'd68, 7'd69: alu_b = tms34010_pkg_WORD_BIT_SIZE;
			7'd67: alu_b = tms34010_pkg_WORD_BIT_SIZE + ({{27 {1'b0}}, decoded[23-:5]} << 4);
			7'd70: alu_b = tms34010_pkg_WORD_BIT_SIZE_2;
			7'd71: alu_b = (trap_skip_push ? 32'd0 : tms34010_pkg_WORD_BIT_SIZE_2);
			7'd5, 7'd33, 7'd7, 7'd10: alu_b = rf_rs1_data;
			default: alu_b = rf_rs2_data;
		endcase
	end
	assign alu_cin = st_c;
	assign st_flag_update_en = ((state_q == 6'd7) && decoded[13]) || fill_win_flag_wb;
	reg [31:0] setf_new_st;
	always @(*) begin
		if (_sv2v_0)
			;
		setf_new_st = st_value;
		if (instr_word_q[9]) begin
			setf_new_st[tms34010_pkg_ST_FS1_HI:tms34010_pkg_ST_FS1_LO] = instr_word_q[4:0];
			setf_new_st[tms34010_pkg_ST_FE1_BIT] = instr_word_q[5];
		end
		else begin
			setf_new_st[tms34010_pkg_ST_FS0_HI:tms34010_pkg_ST_FS0_LO] = instr_word_q[4:0];
			setf_new_st[tms34010_pkg_ST_FE0_BIT] = instr_word_q[5];
		end
	end
	assign st_write_en = ((state_q == 6'd7) && ((((((((decoded[51-:7] == 7'd48) || (decoded[51-:7] == 7'd58)) || (decoded[51-:7] == 7'd61)) || (decoded[51-:7] == 7'd62)) || (decoded[51-:7] == 7'd63)) || (decoded[51-:7] == 7'd65)) || (decoded[51-:7] == 7'd70)) || (decoded[51-:7] == 7'd71))) || ((state_q == 6'd20) && int_push_q);
	localparam [31:0] tms34010_pkg_ST_IE_BIT = 21;
	localparam [31:0] tms34010_pkg_ST_RESET_VALUE = 32'h00000010;
	always @(*) begin
		if (_sv2v_0)
			;
		if (state_q == 6'd20)
			st_write_data = tms34010_pkg_ST_RESET_VALUE;
		else
			(* full_case, parallel_case *)
			case (decoded[51-:7])
				7'd48: st_write_data = rf_rs1_data;
				7'd58: st_write_data = setf_new_st;
				7'd61: st_write_data = exgf_new_st;
				7'd62: st_write_data = st_value & ~(32'd1 << tms34010_pkg_ST_IE_BIT);
				7'd63: st_write_data = st_value | (32'd1 << tms34010_pkg_ST_IE_BIT);
				7'd65: st_write_data = popped_st_q;
				7'd70: st_write_data = popped_st_q;
				7'd71: st_write_data = tms34010_pkg_ST_RESET_VALUE;
				default: st_write_data = 1'sb0;
			endcase
	end
	reg branch_taken;
	localparam [3:0] tms34010_pkg_CC_C = 4'b1000;
	localparam [3:0] tms34010_pkg_CC_EQ = 4'b1010;
	localparam [3:0] tms34010_pkg_CC_GE = 4'b0101;
	localparam [3:0] tms34010_pkg_CC_GT = 4'b0111;
	localparam [3:0] tms34010_pkg_CC_HI = 4'b0011;
	localparam [3:0] tms34010_pkg_CC_HS = 4'b1001;
	localparam [3:0] tms34010_pkg_CC_LE = 4'b0110;
	localparam [3:0] tms34010_pkg_CC_LS = 4'b0010;
	localparam [3:0] tms34010_pkg_CC_LT = 4'b0100;
	localparam [3:0] tms34010_pkg_CC_N = 4'b1110;
	localparam [3:0] tms34010_pkg_CC_NE = 4'b1011;
	localparam [3:0] tms34010_pkg_CC_NN = 4'b1111;
	localparam [3:0] tms34010_pkg_CC_NV = 4'b1101;
	localparam [3:0] tms34010_pkg_CC_P = 4'b0001;
	localparam [3:0] tms34010_pkg_CC_UC = 4'b0000;
	localparam [3:0] tms34010_pkg_CC_V = 4'b1100;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (decoded[18-:4])
			tms34010_pkg_CC_UC: branch_taken = 1'b1;
			tms34010_pkg_CC_P: branch_taken = !st_n & !st_z;
			tms34010_pkg_CC_LS: branch_taken = st_c | st_z;
			tms34010_pkg_CC_HI: branch_taken = !st_c & !st_z;
			tms34010_pkg_CC_LT: branch_taken = st_n ^ st_v;
			tms34010_pkg_CC_LE: branch_taken = (st_n ^ st_v) | st_z;
			tms34010_pkg_CC_GT: branch_taken = !(st_n ^ st_v) & !st_z;
			tms34010_pkg_CC_GE: branch_taken = !(st_n ^ st_v);
			tms34010_pkg_CC_EQ: branch_taken = st_z;
			tms34010_pkg_CC_NE: branch_taken = !st_z;
			tms34010_pkg_CC_HS: branch_taken = !st_c;
			tms34010_pkg_CC_C: branch_taken = st_c;
			tms34010_pkg_CC_V: branch_taken = st_v;
			tms34010_pkg_CC_NV: branch_taken = !st_v;
			tms34010_pkg_CC_N: branch_taken = st_n;
			tms34010_pkg_CC_NN: branch_taken = !st_n;
			default: branch_taken = 1'b0;
		endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		pc_load_en = 1'b0;
		pc_load_value = 1'sb0;
		if (state_q == 6'd7)
			(* full_case, parallel_case *)
			case (decoded[51-:7])
				7'd11:
					if (branch_taken) begin
						pc_load_en = 1'b1;
						pc_load_value = branch_target_short;
					end
				7'd34:
					if (branch_taken) begin
						pc_load_en = 1'b1;
						pc_load_value = branch_target_long;
					end
				7'd35: begin
					pc_load_en = 1'b1;
					pc_load_value = {rf_rs1_data[31:4], 4'h0};
				end
				7'd55: begin
					pc_load_en = 1'b1;
					pc_load_value = {rf_rs2_data[31:4], 4'h0};
				end
				7'd36, 7'd37, 7'd38:
					if (dsj_precondition && dsj_rd_nonzero) begin
						pc_load_en = 1'b1;
						pc_load_value = branch_target_long;
					end
				7'd39:
					if (branch_taken) begin
						pc_load_en = 1'b1;
						pc_load_value = branch_target_jacc;
					end
				7'd40:
					if (dsj_rd_nonzero) begin
						pc_load_en = 1'b1;
						pc_load_value = branch_target_dsjs;
					end
				7'd66: begin
					pc_load_en = 1'b1;
					pc_load_value = {rf_rs1_data[31:4], 4'h0};
				end
				7'd68: begin
					pc_load_en = 1'b1;
					pc_load_value = branch_target_jacc;
				end
				7'd69: begin
					pc_load_en = 1'b1;
					pc_load_value = branch_target_long;
				end
				7'd67: begin
					pc_load_en = 1'b1;
					pc_load_value = popped_pc_q;
				end
				7'd70: begin
					pc_load_en = 1'b1;
					pc_load_value = popped_pc_q;
				end
				7'd71: begin
					pc_load_en = 1'b1;
					pc_load_value = popped_pc_q;
				end
				default:
					;
			endcase
		else if (state_q == 6'd20) begin
			pc_load_en = 1'b1;
			pc_load_value = popped_pc_q;
		end
		else if ((state_q == 6'd38) && mem_ack) begin
			pc_load_en = 1'b1;
			pc_load_value = mem_rdata_eff;
		end
	end
	tms34010_regfile #(.USE_MLAB(MLAB_REGFILE)) u_regfile(
		.clk(clk),
		.ce_cpu(ce_cpu),
		.rst(rst),
		.rs1_file(rf_rs1_file),
		.rs1_idx(rf_rs1_idx),
		.rs1_data(rf_rs1_data),
		.rs2_file(rf_rs2_file),
		.rs2_idx(rf_rs2_idx),
		.rs2_data(rf_rs2_data),
		.rs3_file(rf_rs3_file),
		.rs3_idx(rf_rs3_idx),
		.rs3_data(rf_rs3_data),
		.wr_en(rf_wr_en),
		.wr_file(rf_wr_file),
		.wr_idx(rf_wr_idx),
		.wr_data(rf_wr_data),
		.sp_o(rf_sp)
	);
	wire io_is_io;
	wire [15:0] io_rdata16;
	wire [15:0] io_intenb;
	wire [15:0] io_intpend;
	wire [15:0] io_dpyctl;
	wire [15:0] io_hstctlh;
	wire nmi_clear;
	reg mem_we_int;
	tms34010_io_regs #(
		.LOCAL_WRITE(LOCAL_IO_WRITE),
		.CPU_CE_WRITE(IO_CPU_CE)
	) u_io_regs(
		.ce_cpu(ce_cpu),
		.clk(clk),
		.rst(rst),
		.ce_pix(ce_pix),
		.req(mem_req),
		.we(mem_we_int),
		.addr(mem_addr),
		.size(mem_size),
		.wdata(mem_wdata),
		.rdata(io_rdata16),
		.is_io(io_is_io),
		.psize_o(io_psize),
		.convdp_o(io_convdp),
		.convsp_o(io_convsp),
		.control_o(io_control),
		.pmask_o(io_pmask),
		.dpyctl_o(io_dpyctl),
		.intenb_o(io_intenb),
		.intpend_o(io_intpend),
		.dpystrt_o(dpystrt_o),
		.dpyadr_o(dpyadr_o),
		.vblank_start_o(vblank_start_o),
		.hstctlh_o(io_hstctlh),
		.nmi_clear(nmi_clear),
		.wvp_set(wvp_set),
		.lint1_in(lint1_in),
		.heblnk_o(heblnk_o),
		.hsblnk_o(hsblnk_o),
		.veblnk_o(veblnk_o),
		.vsblnk_o(vsblnk_o)
	);
	wire int_req;
	wire [31:0] int_vector;
	tms34010_int_ctrl u_int_ctrl(
		.intpend(io_intpend),
		.intenb(io_intenb),
		.ie(st_value[tms34010_pkg_ST_IE_BIT]),
		.int_req(int_req),
		.int_vector(int_vector)
	);
	wire nmi_req;
	wire nmi_nmim;
	localparam [31:0] tms34010_pkg_HSTCTL_NMI_BIT = 8;
	assign nmi_req = io_hstctlh[tms34010_pkg_HSTCTL_NMI_BIT];
	localparam [31:0] tms34010_pkg_HSTCTL_NMIM_BIT = 9;
	assign nmi_nmim = io_hstctlh[tms34010_pkg_HSTCTL_NMIM_BIT];
	wire int_take;
	assign int_take = nmi_req || int_req;
	reg fetch_inflight_q;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				fetch_inflight_q <= 1'b0;
			else if (((state_q == 6'd1) && mem_req) && !mem_ack)
				fetch_inflight_q <= 1'b1;
			else if (mem_ack || (state_q != 6'd1))
				fetch_inflight_q <= 1'b0;
		end
	reg [31:0] int_vec_q;
	reg int_is_nmi_q;
	localparam [31:0] tms34010_pkg_INT_VEC_NMI = 32'hfffffee0;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				int_vec_q <= 1'sb0;
				int_is_nmi_q <= 1'b0;
				int_push_q <= 1'b0;
			end
			else if ((state_q == 6'd1) && int_take) begin
				int_vec_q <= (nmi_req ? tms34010_pkg_INT_VEC_NMI : int_vector);
				int_is_nmi_q <= nmi_req;
				int_push_q <= (nmi_req ? !nmi_nmim : 1'b1);
			end
		end
	assign nmi_clear = (state_q == 6'd20) && int_is_nmi_q;
	assign mem_we = mem_we_int && !io_is_io;
	assign mem_req = mem_read_active && !(((state_q == 6'd1) && int_take) && !fetch_inflight_q);
	wire srt_on;
	localparam [31:0] tms34010_pkg_DPYCTL_SRT_BIT = 11;
	assign srt_on = io_dpyctl[tms34010_pkg_DPYCTL_SRT_BIT];
	reg [15:0] io_rdata_q;
	reg io_is_io_q;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				io_rdata_q <= 1'sb0;
				io_is_io_q <= 1'b0;
			end
			else if (mem_req && mem_ack) begin
				io_rdata_q <= io_rdata16;
				io_is_io_q <= io_is_io;
			end
		end
	assign mem_rdata_eff = (mem_read_active ? (io_is_io ? {{16 {1'b0}}, io_rdata16} : mem_rdata) : (io_is_io_q ? {{16 {1'b0}}, io_rdata_q} : mem_rdata));
	tms34010_alu u_alu(
		.op(alu_op),
		.a(alu_a),
		.b(alu_b),
		.cin(alu_cin),
		.result(alu_result),
		.flags(alu_flags)
	);
	localparam [31:0] tms34010_pkg_SHIFT_AMOUNT_WIDTH = 5;
	reg [4:0] shifter_amount;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (decoded[51-:7])
			7'd49, 7'd50, 7'd53: shifter_amount = rf_rs1_data[4:0];
			7'd51, 7'd52: shifter_amount = ~rf_rs1_data[4:0] + {{4 {1'b0}}, 1'b1};
			7'd21, 7'd22: shifter_amount = ~decoded[23-:5] + {{4 {1'b0}}, 1'b1};
			default: shifter_amount = decoded[23-:5];
		endcase
	end
	tms34010_shifter u_shifter(
		.op(decoded[27-:3]),
		.a(rf_rs2_data),
		.amount(shifter_amount),
		.result(shifter_result),
		.flags(shifter_flags)
	);
	reg [3:0] flag_input;
	always @(*) begin
		if (_sv2v_0)
			;
		if (fill_win_flag_wb)
			flag_input = {3'b000, fill_win_violation};
		else
			(* full_case, parallel_case *)
			case (decoded[51-:7])
				7'd46: flag_input = 4'b0100;
				7'd45: flag_input = 4'b0000;
				7'd57: flag_input = {2'b00, rf_rs1_data == 1'b0, 1'b0};
				7'd59: flag_input = {sext_result[31], 1'b0, sext_result == 1'b0, 1'b0};
				7'd60: flag_input = {2'b00, zext_result == 1'b0, 1'b0};
				7'd72: flag_input = {~rf_rs2_data[31], 3'b000};
				7'd75, 7'd78, 7'd80: flag_input = {mv_load_data[31], 1'b0, mv_load_data == 1'b0, decoded[4] && (mv_load_data != 1'b0)};
				7'd83: flag_input = addxy_flags;
				7'd84: flag_input = subxy_flags;
				7'd85: flag_input = cmpxy_flags;
				7'd86: flag_input = cpw_flags;
				7'd87, 7'd88: flag_input = {mpy_product_q[63], 1'b0, mpy_product_q == 64'd0, 1'b0};
				7'd89, 7'd91, 7'd90, 7'd92: flag_input = {(is_signed_div && !div_v) && div_result_main[31], 1'b0, !div_v && (div_result_main == 1'b0), div_v};
				default: flag_input = (decoded[24] ? shifter_flags : alu_flags);
			endcase
	end
	reg [3:0] effective_flag_mask;
	always @(*) begin
		if (_sv2v_0)
			;
		effective_flag_mask = decoded[12-:4];
		if (is_div_mod && div_v)
			effective_flag_mask[1] = 1'b0;
		if (fill_win_flag_wb)
			effective_flag_mask = 4'b0001;
	end
	tms34010_status_reg u_status_reg(
		.clk(clk),
		.ce_cpu(ce_cpu),
		.rst(rst),
		.flag_update_en(st_flag_update_en),
		.flags_in(flag_input),
		.flag_update_mask(effective_flag_mask),
		.st_write_en(st_write_en),
		.st_write_data(st_write_data),
		.st_o(st_value),
		.n_o(st_n),
		.c_o(st_c),
		.z_o(st_z),
		.v_o(st_v)
	);
	wire [31:0] unused_rf_sp;
	wire [31:0] unused_st_value;
	wire unused_st_nv;
	assign unused_rf_sp = rf_sp;
	assign unused_st_value = st_value;
	assign unused_st_nv = (st_n ^ st_v) ^ st_z;
	localparam [5:0] tms34010_pkg_MEM_SIZE_32 = sv2v_cast_13C0F(tms34010_pkg_DATA_WIDTH);
	localparam [31:0] tms34010_pkg_TRAP_VECTOR_BASE = 32'hffffffe0;
	always @(*) begin
		if (_sv2v_0)
			;
		state_d = state_q;
		mem_read_active = 1'b0;
		mem_we_int = 1'b0;
		mem_addr = 1'sb0;
		mem_size = 1'sb0;
		mem_wdata = 1'sb0;
		mem_srt = 1'b0;
		pc_advance_en = 1'b0;
		(* full_case, parallel_case *)
		case (state_q)
			6'd0: state_d = 6'd38;
			6'd38: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b0;
				mem_addr = tms34010_pkg_TRAP_VECTOR_BASE;
				mem_size = tms34010_pkg_MEM_SIZE_32;
				if (mem_ack)
					state_d = 6'd1;
			end
			6'd1: begin
				mem_read_active = 1'b1;
				mem_addr = pc_value;
				mem_size = tms34010_pkg_INSTR_WORD_BITS;
				if (int_take && !fetch_inflight_q)
					state_d = (nmi_req && nmi_nmim ? 6'd19 : 6'd18);
				else if (mem_ack) begin
					state_d = 6'd2;
					pc_advance_en = 1'b1;
				end
			end
			6'd18: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b1;
				mem_addr = rf_sp - tms34010_pkg_WORD_BIT_SIZE;
				mem_size = tms34010_pkg_MEM_SIZE_32;
				mem_wdata = pc_value;
				if (mem_ack)
					state_d = 6'd17;
			end
			6'd17: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b1;
				mem_addr = rf_sp - tms34010_pkg_WORD_BIT_SIZE_2;
				mem_size = tms34010_pkg_MEM_SIZE_32;
				mem_wdata = st_value;
				if (mem_ack)
					state_d = 6'd19;
			end
			6'd19: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b0;
				mem_addr = int_vec_q;
				mem_size = tms34010_pkg_MEM_SIZE_32;
				if (mem_ack)
					state_d = 6'd20;
			end
			6'd20: state_d = 6'd1;
			6'd2:
				if (decoded[33])
					state_d = 6'd3;
				else if (decoded[34])
					state_d = 6'd3;
				else
					state_d = 6'd5;
			6'd3: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b0;
				mem_addr = pc_value;
				mem_size = tms34010_pkg_INSTR_WORD_BITS;
				if (mem_ack) begin
					pc_advance_en = 1'b1;
					state_d = (decoded[33] ? 6'd4 : (is_mv_off_m2m ? 6'd39 : 6'd5));
				end
			end
			6'd4: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b0;
				mem_addr = pc_value;
				mem_size = tms34010_pkg_INSTR_WORD_BITS;
				if (mem_ack) begin
					pc_advance_en = 1'b1;
					state_d = (is_mv_abs_m2m ? 6'd39 : 6'd5);
				end
			end
			6'd39: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b0;
				mem_addr = pc_value;
				mem_size = tms34010_pkg_INSTR_WORD_BITS;
				if (mem_ack) begin
					pc_advance_en = 1'b1;
					state_d = (is_mv_off_m2m ? 6'd5 : 6'd40);
				end
			end
			6'd40: begin
				mem_read_active = 1'b1;
				mem_we_int = 1'b0;
				mem_addr = pc_value;
				mem_size = tms34010_pkg_INSTR_WORD_BITS;
				if (mem_ack) begin
					pc_advance_en = 1'b1;
					state_d = 6'd5;
				end
			end
			6'd5:
				if (is_div)
					state_d = 6'd8;
				else if (is_fill)
					state_d = 6'd9;
				else if (is_pblt)
					state_d = 6'd12;
				else if (is_drav)
					state_d = (io_control[tms34010_pkg_CTRL_W_HI:tms34010_pkg_CTRL_W_LO] != 2'd0 ? 6'd28 : 6'd27);
				else if (is_line)
					state_d = 6'd29;
				else if (pixt_xy_win)
					state_d = 6'd37;
				else
					state_d = (decoded[8] ? 6'd6 : 6'd7);
			6'd8: state_d = (div_done ? 6'd7 : 6'd8);
			6'd9: state_d = ((fill_win_en_q || fill_w2_q) || fill_w1_q ? 6'd21 : 6'd10);
			6'd21: state_d = (fill_w1_q ? 6'd25 : (fill_w2_q && !fill_array_inside ? 6'd23 : 6'd10));
			6'd23: state_d = 6'd1;
			6'd25: state_d = 6'd1;
			6'd28: state_d = (((drav_w_q == 2'd2) || (drav_w_q == 2'd3)) && drav_in_window ? 6'd27 : 6'd7);
			6'd37: state_d = 6'd6;
			6'd27: begin
				mem_read_active = 1'b1;
				mem_addr = drav_linear_q;
				mem_size = io_psize[5:0];
				if (!drav_substep_q)
					mem_we_int = 1'b0;
				else begin
					mem_we_int = 1'b1;
					mem_wdata = drav_merged;
					mem_srt = srt_on;
				end
				if (mem_ack && drav_substep_q)
					state_d = 6'd7;
				else
					state_d = 6'd27;
			end
			6'd29: state_d = 6'd30;
			6'd30: state_d = 6'd31;
			6'd31: state_d = (line_count_q == {32 {1'sb0}} ? 6'd33 : (line_win_en ? 6'd36 : 6'd32));
			6'd36: state_d = 6'd32;
			6'd32: begin
				mem_read_active = 1'b1;
				mem_addr = line_linear;
				mem_size = io_psize[5:0];
				if (!line_substep_q)
					mem_we_int = 1'b0;
				else begin
					mem_we_int = 1'b1;
					mem_wdata = line_merged;
				end
				if ((mem_ack && line_substep_q) && ((line_count_q == 32'd1) || line_abort))
					state_d = 6'd33;
				else
					state_d = 6'd32;
			end
			6'd33: state_d = 6'd34;
			6'd34: state_d = 6'd35;
			6'd35: state_d = 6'd1;
			6'd10: begin
				mem_read_active = 1'b1;
				mem_addr = fill_addr_q;
				mem_size = io_psize[5:0];
				if (!fill_substep_q)
					mem_we_int = 1'b0;
				else begin
					mem_we_int = 1'b1;
					mem_wdata = fill_merged;
					mem_srt = srt_on;
				end
				if ((mem_ack && fill_substep_q) && fill_done)
					state_d = 6'd11;
				else
					state_d = 6'd10;
			end
			6'd11: state_d = 6'd1;
			6'd12: state_d = ((pblt_dx_q == 16'd0) || (pblt_dy_q == 16'd0) ? 6'd1 : (decoded[0] ? 6'd16 : ((pblt_win_en_q || pblt_w2_q) || pblt_w1_q ? 6'd22 : 6'd13)));
			6'd16: state_d = ((pblt_win_en_q || pblt_w2_q) || pblt_w1_q ? 6'd22 : 6'd13);
			6'd22: state_d = (pblt_w1_q ? 6'd26 : (pblt_w2_q && !pblt_array_inside ? 6'd24 : 6'd13));
			6'd24: state_d = 6'd1;
			6'd26: state_d = 6'd1;
			6'd13: begin
				mem_read_active = 1'b1;
				mem_size = io_psize[5:0];
				(* full_case, parallel_case *)
				case (pblt_substep_q)
					2'd0: begin
						mem_we_int = 1'b0;
						mem_addr = pblt_src_addr_q;
						if (decoded[0])
							mem_size = sv2v_cast_13C0F_signed(1);
					end
					2'd1: begin
						mem_we_int = 1'b0;
						mem_addr = pblt_dst_addr_q;
					end
					default: begin
						mem_we_int = 1'b1;
						mem_addr = pblt_dst_addr_q;
						mem_wdata = pblt_merged;
					end
				endcase
				if ((mem_ack && (pblt_substep_q == 2'd2)) && pblt_done)
					state_d = 6'd14;
				else
					state_d = 6'd13;
			end
			6'd14: state_d = 6'd15;
			6'd15: state_d = 6'd1;
			6'd6: begin
				(* full_case, parallel_case *)
				case (decoded[51-:7])
					7'd64: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b1;
						mem_addr = alu_result;
						mem_size = tms34010_pkg_MEM_SIZE_32;
						mem_wdata = st_value;
					end
					7'd65: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_addr = rf_rs2_data;
						mem_size = tms34010_pkg_MEM_SIZE_32;
					end
					7'd66, 7'd68, 7'd69: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b1;
						mem_addr = alu_result;
						mem_size = tms34010_pkg_MEM_SIZE_32;
						mem_wdata = pc_value;
					end
					7'd67: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_addr = rf_rs2_data;
						mem_size = tms34010_pkg_MEM_SIZE_32;
					end
					7'd70: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_size = tms34010_pkg_MEM_SIZE_32;
						mem_addr = (mem_op_step == 2'd0 ? rf_rs2_data : rf_rs2_data + tms34010_pkg_WORD_BIT_SIZE);
					end
					7'd71: begin
						mem_read_active = 1'b1;
						mem_size = tms34010_pkg_MEM_SIZE_32;
						if (trap_skip_push) begin
							mem_we_int = 1'b0;
							mem_addr = tms34010_pkg_TRAP_VECTOR_BASE;
						end
						else
							(* full_case, parallel_case *)
							case (mem_op_step)
								2'd0: begin
									mem_we_int = 1'b1;
									mem_addr = rf_rs2_data - tms34010_pkg_WORD_BIT_SIZE;
									mem_wdata = pc_value;
								end
								2'd1: begin
									mem_we_int = 1'b1;
									mem_addr = rf_rs2_data - tms34010_pkg_WORD_BIT_SIZE_2;
									mem_wdata = st_value;
								end
								default: begin
									mem_we_int = 1'b0;
									mem_addr = tms34010_pkg_TRAP_VECTOR_BASE - ({{27 {1'b0}}, decoded[23-:5]} << 5);
								end
							endcase
					end
					7'd72: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b1;
						mem_addr = mm_rp_q;
						mem_size = tms34010_pkg_MEM_SIZE_32;
						mem_wdata = rf_rs1_data;
					end
					7'd73: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_addr = mm_rp_q;
						mem_size = tms34010_pkg_MEM_SIZE_32;
					end
					7'd74: begin
						mem_read_active = 1'b1;
						mem_addr = mv_addr;
						mem_size = mv_fs;
						if (pixt_rmw && (mem_op_step == 2'd0))
							mem_we_int = 1'b0;
						else begin
							mem_we_int = 1'b1;
							mem_wdata = (pixt_rmw ? pixt_merged : rf_rs1_data);
							if (decoded[4])
								mem_srt = srt_on;
						end
					end
					7'd75: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_addr = mv_addr;
						mem_size = mv_fs;
						if (decoded[4])
							mem_srt = srt_on;
					end
					7'd79: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b1;
						mem_addr = (SHARED_ADDRESS ? shared_address_sum : rf_rs2_data + imm32);
						mem_size = mv_fs;
						mem_wdata = rf_rs1_data;
					end
					7'd80: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_addr = (SHARED_ADDRESS ? shared_address_sum : rf_rs1_data + imm32);
						mem_size = mv_fs;
					end
					7'd77: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b1;
						mem_addr = imm32;
						mem_size = mv_fs;
						mem_wdata = rf_rs1_data;
					end
					7'd78: begin
						mem_read_active = 1'b1;
						mem_we_int = 1'b0;
						mem_addr = imm32;
						mem_size = mv_fs;
					end
					7'd76: begin
						mem_read_active = 1'b1;
						mem_size = mv_fs;
						if (decoded[4])
							mem_srt = srt_on;
						if (mem_op_step == 2'd0) begin
							mem_we_int = 1'b0;
							mem_addr = m2m_src_addr;
						end
						else begin
							mem_we_int = 1'b1;
							mem_addr = m2m_dst_addr;
							mem_wdata = move_data_q;
						end
					end
					7'd99: begin
						mem_read_active = 1'b1;
						mem_size = mv_fs;
						if (mem_op_step == 2'd0) begin
							mem_we_int = 1'b0;
							mem_addr = imm32;
						end
						else begin
							mem_we_int = 1'b1;
							mem_addr = imm2_32;
							mem_wdata = move_data_q;
						end
					end
					7'd100: begin
						mem_read_active = 1'b1;
						mem_size = mv_fs;
						if (mem_op_step == 2'd0) begin
							mem_we_int = 1'b0;
							mem_addr = (SHARED_ADDRESS ? shared_address_sum : rf_rs1_data + imm32);
						end
						else begin
							mem_we_int = 1'b1;
							mem_addr = (SHARED_ADDRESS ? shared_address_sum : rf_rs2_data + imm2_off_sext);
							mem_wdata = move_data_q;
						end
					end
					7'd101: begin
						mem_read_active = 1'b1;
						mem_size = mv_fs;
						if (mem_op_step == 2'd0) begin
							mem_we_int = 1'b0;
							mem_addr = (SHARED_ADDRESS ? shared_address_sum : rf_rs1_data + imm32);
						end
						else begin
							mem_we_int = 1'b1;
							mem_addr = rf_rs2_data;
							mem_wdata = move_data_q;
						end
					end
					7'd102: begin
						mem_read_active = 1'b1;
						mem_size = mv_fs;
						if (mem_op_step == 2'd0) begin
							mem_we_int = 1'b0;
							mem_addr = imm32;
						end
						else begin
							mem_we_int = 1'b1;
							mem_addr = rf_rs2_data;
							mem_wdata = move_data_q;
						end
					end
					default:
						;
				endcase
				if (mem_ack)
					(* full_case, parallel_case *)
					case (decoded[51-:7])
						7'd70:
							if (mem_op_step == 2'd1)
								state_d = 6'd7;
						7'd71:
							if (trap_skip_push || (mem_op_step == 2'd2))
								state_d = 6'd7;
						7'd72, 7'd73:
							if (mm_mask_will_be_empty)
								state_d = 6'd7;
						7'd76, 7'd99, 7'd100, 7'd101, 7'd102:
							if (mem_op_step == 2'd1)
								state_d = 6'd7;
						7'd74:
							if (!pixt_rmw || (mem_op_step == 2'd1))
								state_d = 6'd7;
						default: state_d = 6'd7;
					endcase
			end
			6'd7: state_d = (pair_second_pass ? 6'd7 : 6'd1);
			default: state_d = 6'd0;
		endcase
	end
	assign state_o = state_q;
	assign pc_o = pc_value;
	assign instr_word_o = instr_word_q;
	assign illegal_opcode_o = illegal_q;
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_decode (
	instr,
	decoded
);
	reg _sv2v_0;
	localparam [31:0] tms34010_pkg_INSTR_WORD_WIDTH = 16;
	input wire [15:0] instr;
	output reg [52:0] decoded;
	wire [9:0] top10;
	wire [6:0] top7;
	wire [5:0] top6;
	assign top10 = instr[15:6];
	assign top7 = instr[15:9];
	assign top6 = instr[15:10];
	localparam [9:0] MOVI_TOP10 = 10'b0000100111;
	localparam [5:0] MOVK_TOP6 = 6'b000110;
	localparam [5:0] ADDK_TOP6 = 6'b000100;
	localparam [5:0] SUBK_TOP6 = 6'b000101;
	localparam [8:0] UNARY_TOP9 = 9'b000000111;
	localparam [10:0] ADDI_IW_TOP11 = 11'b00001011000;
	localparam [10:0] SUBI_IW_TOP11 = 11'b00001011111;
	localparam [10:0] CMPI_IW_TOP11 = 11'b00001011010;
	localparam [5:0] SLA_K_TOP6 = 6'b001000;
	localparam [5:0] SLL_K_TOP6 = 6'b001001;
	localparam [5:0] SRA_K_TOP6 = 6'b001010;
	localparam [5:0] SRL_K_TOP6 = 6'b001011;
	localparam [5:0] RL_K_TOP6 = 6'b001100;
	localparam [10:0] ADDI_IL_TOP11 = 11'b00001011001;
	localparam [10:0] CMPI_IL_TOP11 = 11'b00001011011;
	localparam [10:0] ANDI_IL_TOP11 = 11'b00001011100;
	localparam [10:0] ORI_IL_TOP11 = 11'b00001011101;
	localparam [10:0] XORI_IL_TOP11 = 11'b00001011110;
	localparam [10:0] SUBI_IL_TOP11 = 11'b00001101000;
	localparam [5:0] MOVE_RR_TOP6 = 6'b010011;
	localparam [5:0] MOVE_STORE_TOP6 = 6'b100000;
	localparam [5:0] MOVE_LOAD_TOP6 = 6'b100001;
	localparam [5:0] MOVE_M2M_TOP6 = 6'b100010;
	localparam [5:0] MOVE_M2M_POSTINC_TOP6 = 6'b100110;
	localparam [5:0] MOVE_M2M_PREDEC_TOP6 = 6'b101010;
	localparam [5:0] MOVE_OFF_STORE_TOP6 = 6'b101100;
	localparam [5:0] MOVE_OFF_LOAD_TOP6 = 6'b101101;
	localparam [5:0] MOVE_OFF_M2M_TOP6 = 6'b101110;
	localparam [5:0] MOVE_OFF_M2M_POST_TOP6 = 6'b110100;
	localparam [5:0] MOVE_ABS_M2M_POST_TOP6 = 6'b110101;
	localparam [5:0] MOVE_STORE_POSTINC_TOP6 = 6'b100100;
	localparam [5:0] MOVE_LOAD_POSTINC_TOP6 = 6'b100101;
	localparam [5:0] MOVE_STORE_PREDEC_TOP6 = 6'b101000;
	localparam [5:0] MOVE_LOAD_PREDEC_TOP6 = 6'b101001;
	localparam [6:0] MOVB_STORE_TOP7 = 7'b1000110;
	localparam [6:0] MOVB_LOAD_TOP7 = 7'b1000111;
	localparam [6:0] MOVB_M2M_TOP7 = 7'b1001110;
	localparam [6:0] MOVB_OFF_STORE_TOP7 = 7'b1010110;
	localparam [6:0] MOVB_OFF_LOAD_TOP7 = 7'b1010111;
	localparam [6:0] MOVB_OFF_M2M_TOP7 = 7'b1011110;
	localparam [6:0] PIXT_STORE_TOP7 = 7'b1111100;
	localparam [6:0] PIXT_LOAD_TOP7 = 7'b1111101;
	localparam [6:0] PIXT_M2M_TOP7 = 7'b1111110;
	localparam [6:0] PIXT_XY_STORE_TOP7 = 7'b1111000;
	localparam [6:0] PIXT_XY_LOAD_TOP7 = 7'b1111001;
	localparam [6:0] PIXT_XY_M2M_TOP7 = 7'b1111010;
	localparam [6:0] MOVX_TOP7 = 7'b1110110;
	localparam [6:0] MOVY_TOP7 = 7'b1110111;
	localparam [6:0] CVXYL_TOP7 = 7'b1110100;
	localparam [6:0] ADDXY_TOP7 = 7'b1110000;
	localparam [6:0] SUBXY_TOP7 = 7'b1110001;
	localparam [6:0] DRAV_TOP7 = 7'b1111011;
	localparam [6:0] CMPXY_TOP7 = 7'b1110010;
	localparam [6:0] CPW_TOP7 = 7'b1110011;
	localparam [6:0] MPYS_TOP7 = 7'b0101110;
	localparam [6:0] MPYU_TOP7 = 7'b0101111;
	localparam [6:0] DIVU_TOP7 = 7'b0101101;
	localparam [6:0] MODU_TOP7 = 7'b0110111;
	localparam [6:0] DIVS_TOP7 = 7'b0101100;
	localparam [6:0] MODS_TOP7 = 7'b0110110;
	localparam [6:0] ADD_RR_TOP7 = 7'b0100000;
	localparam [6:0] ADDC_RR_TOP7 = 7'b0100001;
	localparam [6:0] SUB_RR_TOP7 = 7'b0100010;
	localparam [6:0] SUBB_RR_TOP7 = 7'b0100011;
	localparam [6:0] AND_RR_TOP7 = 7'b0101000;
	localparam [6:0] ANDN_RR_TOP7 = 7'b0101001;
	localparam [6:0] OR_RR_TOP7 = 7'b0101010;
	localparam [6:0] XOR_RR_TOP7 = 7'b0101011;
	localparam [6:0] CMP_RR_TOP7 = 7'b0100100;
	localparam [15:0] PUSHST_OPCODE = 16'h01e0;
	localparam [15:0] POPST_OPCODE = 16'h01c0;
	localparam [10:0] CALL_RS_TOP11 = 11'b00001001001;
	localparam [15:0] RETI_OPCODE = 16'h0940;
	localparam [10:0] TRAP_TOP11 = 11'b00001001000;
	localparam [10:0] MMTM_TOP11 = 11'b00001001100;
	localparam [10:0] MMFM_TOP11 = 11'b00001001101;
	localparam [15:0] CALLA_OPCODE = 16'h0d5f;
	localparam [15:0] CALLR_OPCODE = 16'h0d3f;
	localparam [10:0] RETS_TOP11 = 11'b00001001011;
	localparam [15:0] DINT_OPCODE = 16'h0360;
	localparam [15:0] EINT_OPCODE = 16'h0d60;
	localparam [5:0] EXGF_TOP6 = 6'b110101;
	localparam [5:0] SETF_TOP6 = 6'b000001;
	localparam [6:0] LMO_RR_TOP7 = 7'b0110101;
	localparam [6:0] SLA_RR_TOP7 = 7'b0110000;
	localparam [6:0] SLL_RR_TOP7 = 7'b0110001;
	localparam [6:0] SRA_RR_TOP7 = 7'b0110010;
	localparam [6:0] SRL_RR_TOP7 = 7'b0110011;
	localparam [6:0] RL_RR_TOP7 = 7'b0110100;
	localparam [3:0] JRCC_TOP4 = 4'b1100;
	localparam [15:0] NOP_OPCODE = 16'h0300;
	localparam [10:0] JUMP_RS_TOP11 = 11'b00000001011;
	localparam [10:0] DSJ_TOP11 = 11'b00001101100;
	localparam [10:0] DSJEQ_TOP11 = 11'b00001101101;
	localparam [10:0] DSJNE_TOP11 = 11'b00001101110;
	localparam [15:0] CLRC_OPCODE = 16'h0320;
	localparam [15:0] SETC_OPCODE = 16'h0de0;
	localparam [10:0] GETST_TOP11 = 11'b00000001100;
	localparam [10:0] PUTST_TOP11 = 11'b00000001101;
	localparam [10:0] GETPC_TOP11 = 11'b00000001010;
	localparam [10:0] EXGPC_TOP11 = 11'b00000001001;
	localparam [10:0] REV_TOP11 = 11'b00000000001;
	localparam [5:0] BTST_K_TOP6 = 6'b000111;
	localparam [6:0] BTST_RR_TOP7 = 7'b0100101;
	localparam [4:0] DSJS_TOP5 = 5'b00111;
	wire [3:0] rs_idx_from_instr;
	assign rs_idx_from_instr = instr[8:5];
	wire [10:0] top11;
	assign top11 = instr[15:5];
	wire reg_file_from_instr;
	wire [3:0] reg_idx_from_instr;
	assign reg_file_from_instr = instr[4];
	assign reg_idx_from_instr = instr[3:0];
	localparam [3:0] tms34010_pkg_CC_C = 4'b1000;
	localparam [3:0] tms34010_pkg_CC_EQ = 4'b1010;
	localparam [3:0] tms34010_pkg_CC_GE = 4'b0101;
	localparam [3:0] tms34010_pkg_CC_GT = 4'b0111;
	localparam [3:0] tms34010_pkg_CC_HI = 4'b0011;
	localparam [3:0] tms34010_pkg_CC_HS = 4'b1001;
	localparam [3:0] tms34010_pkg_CC_LE = 4'b0110;
	localparam [3:0] tms34010_pkg_CC_LS = 4'b0010;
	localparam [3:0] tms34010_pkg_CC_LT = 4'b0100;
	localparam [3:0] tms34010_pkg_CC_N = 4'b1110;
	localparam [3:0] tms34010_pkg_CC_NE = 4'b1011;
	localparam [3:0] tms34010_pkg_CC_NN = 4'b1111;
	localparam [3:0] tms34010_pkg_CC_NV = 4'b1101;
	localparam [3:0] tms34010_pkg_CC_P = 4'b0001;
	localparam [3:0] tms34010_pkg_CC_UC = 4'b0000;
	localparam [3:0] tms34010_pkg_CC_V = 4'b1100;
	localparam [3:0] tms34010_pkg_REG_SP_IDX = 4'hf;
	always @(*) begin
		if (_sv2v_0)
			;
		decoded[52] = 1'b1;
		decoded[51-:7] = 7'd0;
		decoded[44] = 1'b0;
		decoded[43-:4] = 1'sb0;
		decoded[39-:4] = 1'sb0;
		decoded[34] = 1'b0;
		decoded[33] = 1'b0;
		decoded[32] = 1'b0;
		decoded[31-:4] = 4'd11;
		decoded[35] = reg_file_from_instr;
		decoded[7-:2] = 2'b00;
		decoded[5] = 1'b0;
		decoded[4] = 1'b0;
		decoded[3] = 1'b0;
		decoded[2] = 1'b0;
		decoded[1] = 1'b0;
		decoded[0] = 1'b0;
		decoded[27-:3] = 3'd0;
		decoded[24] = 1'b0;
		decoded[23-:5] = 1'sb0;
		decoded[18-:4] = 1'sb0;
		decoded[14] = 1'b0;
		decoded[13] = 1'b0;
		decoded[12-:4] = 4'b1111;
		decoded[8] = 1'b0;
		if ((top10 == MOVI_TOP10) && (instr[5] == 1'b0)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[33] = 1'b0;
			decoded[32] = 1'b1;
			decoded[31-:4] = 4'd12;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if ((top10 == MOVI_TOP10) && (instr[5] == 1'b1)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd2;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[34] = 1'b0;
			decoded[33] = 1'b1;
			decoded[32] = 1'b0;
			decoded[31-:4] = 4'd12;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top6 == MOVK_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd3;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[34] = 1'b0;
			decoded[33] = 1'b0;
			decoded[32] = 1'b0;
			decoded[31-:4] = 4'd12;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top6 == ADDK_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd12;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top6 == SUBK_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd13;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top11 == ADDI_IW_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd16;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top11 == SUBI_IW_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd17;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top11 == CMPI_IW_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd18;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[31-:4] = 4'd4;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
		end
		if (top11 == ADDI_IL_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd24;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top11 == SUBI_IL_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd25;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top11 == CMPI_IL_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd26;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[31-:4] = 4'd4;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
		end
		if (top11 == ANDI_IL_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd27;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[31-:4] = 4'd6;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top11 == ORI_IL_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd28;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[31-:4] = 4'd7;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top11 == XORI_IL_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd29;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[31-:4] = 4'd8;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top6 == MOVE_RR_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd30;
			decoded[35] = reg_file_from_instr;
			decoded[44] = (instr[9] ? ~instr[4] : reg_file_from_instr);
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd11;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top7 == MOVX_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd81;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top7 == MOVY_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd82;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top7 == CVXYL_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd93;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top7 == ADDXY_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd83;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == SUBXY_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd84;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == DRAV_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd97;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[8] = 1'b1;
		end
		if ((instr[15:8] == 8'hdf) && (instr[6:0] == 7'h1a)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd98;
			decoded[14] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top7 == CMPXY_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd85;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
		end
		if (top7 == MPYS_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd87;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1010;
		end
		if (top7 == MPYU_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd88;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top7 == DIVU_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd89;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0011;
		end
		if (top7 == MODU_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd90;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0011;
		end
		if (top7 == DIVS_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd91;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top7 == MODS_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd92;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top7 == CPW_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd86;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0001;
		end
		if (top6 == MOVE_STORE_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd74;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top6 == MOVE_LOAD_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd75;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
			decoded[8] = 1'b1;
		end
		if (top6 == MOVE_OFF_STORE_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd79;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (top6 == MOVE_OFF_LOAD_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd80;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top6 == MOVE_OFF_M2M_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd100;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (top6 == MOVE_OFF_M2M_POST_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd101;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if ((top6 == MOVE_ABS_M2M_POST_TOP6) && (instr[8:5] == 4'b0000)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd102;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top6 == MOVE_M2M_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd76;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if ((top6 == MOVE_M2M_POSTINC_TOP6) || (top6 == MOVE_M2M_PREDEC_TOP6)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd76;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[7-:2] = (top6 == MOVE_M2M_PREDEC_TOP6 ? 2'b10 : 2'b01);
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if ((top6 == MOVE_STORE_POSTINC_TOP6) || (top6 == MOVE_STORE_PREDEC_TOP6)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd74;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[7-:2] = (top6 == MOVE_STORE_PREDEC_TOP6 ? 2'b10 : 2'b01);
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if ((top6 == MOVE_LOAD_POSTINC_TOP6) || (top6 == MOVE_LOAD_PREDEC_TOP6)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd75;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[7-:2] = (top6 == MOVE_LOAD_PREDEC_TOP6 ? 2'b10 : 2'b01);
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
			decoded[8] = 1'b1;
		end
		if (top6 == SLA_K_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd19;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[27-:3] = 3'd1;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top6 == SLL_K_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd20;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[27-:3] = 3'd0;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0110;
		end
		if (top6 == SRA_K_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd21;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[27-:3] = 3'd3;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1110;
		end
		if (top6 == SRL_K_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd22;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[27-:3] = 3'd2;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0110;
		end
		if (top6 == RL_K_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd23;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = instr[9:5];
			decoded[27-:3] = 3'd4;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0110;
		end
		if (instr[15:7] == UNARY_TOP9)
			case (instr[6:5])
				2'b00: begin
					decoded[52] = 1'b0;
					decoded[51-:7] = 7'd41;
					decoded[44] = reg_file_from_instr;
					decoded[43-:4] = reg_idx_from_instr;
					decoded[31-:4] = 4'd13;
					decoded[14] = 1'b1;
					decoded[13] = 1'b1;
					decoded[12-:4] = 4'b1011;
				end
				2'b01: begin
					decoded[52] = 1'b0;
					decoded[51-:7] = 7'd14;
					decoded[44] = reg_file_from_instr;
					decoded[43-:4] = reg_idx_from_instr;
					decoded[31-:4] = 4'd10;
					decoded[14] = 1'b1;
					decoded[13] = 1'b1;
				end
				2'b10: begin
					decoded[52] = 1'b0;
					decoded[51-:7] = 7'd42;
					decoded[44] = reg_file_from_instr;
					decoded[43-:4] = reg_idx_from_instr;
					decoded[31-:4] = 4'd3;
					decoded[14] = 1'b1;
					decoded[13] = 1'b1;
				end
				2'b11: begin
					decoded[52] = 1'b0;
					decoded[51-:7] = 7'd15;
					decoded[44] = reg_file_from_instr;
					decoded[43-:4] = reg_idx_from_instr;
					decoded[31-:4] = 4'd9;
					decoded[14] = 1'b1;
					decoded[13] = 1'b1;
					decoded[12-:4] = 4'b0010;
				end
				default:
					;
			endcase
		if (top7 == SLA_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd49;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[27-:3] = 3'd1;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == SLL_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd50;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[27-:3] = 3'd0;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0110;
		end
		if (top7 == SRA_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd51;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[27-:3] = 3'd3;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1110;
		end
		if (top7 == SRL_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd52;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[27-:3] = 3'd2;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0110;
		end
		if (top7 == RL_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd53;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[27-:3] = 3'd4;
			decoded[24] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0110;
		end
		if (top7 == LMO_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd57;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (((instr[15:10] == SETF_TOP6) && instr[8]) && (instr[7:6] == 2'b01)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd58;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (((instr[15:10] == SETF_TOP6) && instr[8]) && (instr[7:5] == 3'b000)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd59;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1010;
		end
		if (((instr[15:10] == SETF_TOP6) && instr[8]) && (instr[7:5] == 3'b001)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd60;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (((instr[15:10] == SETF_TOP6) && instr[8]) && (instr[7:5] == 3'b100)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd77;
			decoded[44] = reg_file_from_instr;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (((instr[15:10] == SETF_TOP6) && instr[8]) && (instr[7:5] == 3'b101)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd78;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (((instr[15:10] == SETF_TOP6) && instr[8]) && (instr[7:5] == 3'b110)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd99;
			decoded[33] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (top7 == MOVB_STORE_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd74;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top7 == MOVB_LOAD_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd75;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
			decoded[8] = 1'b1;
		end
		if (top7 == MOVB_M2M_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd76;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top7 == MOVB_OFF_STORE_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd79;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (top7 == MOVB_OFF_LOAD_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd80;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top7 == MOVB_OFF_M2M_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd100;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[34] = 1'b1;
			decoded[32] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if ((((instr[15:10] == SETF_TOP6) && !instr[9]) && instr[8]) && (instr[7:5] == 3'b111)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd77;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if ((((instr[15:10] == SETF_TOP6) && instr[9]) && instr[8]) && (instr[7:5] == 3'b111)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd78;
			decoded[5] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[33] = 1'b1;
			decoded[8] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b1011;
		end
		if (top7 == PIXT_STORE_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd74;
			decoded[4] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top7 == PIXT_LOAD_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd75;
			decoded[4] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0001;
			decoded[8] = 1'b1;
		end
		if (top7 == PIXT_M2M_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd76;
			decoded[4] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top7 == PIXT_XY_STORE_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd74;
			decoded[4] = 1'b1;
			decoded[3] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top7 == PIXT_XY_LOAD_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd75;
			decoded[4] = 1'b1;
			decoded[3] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0001;
			decoded[8] = 1'b1;
		end
		if (top7 == PIXT_XY_M2M_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd76;
			decoded[4] = 1'b1;
			decoded[3] = 1'b1;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (((instr[15:10] == EXGF_TOP6) && instr[8]) && (instr[7:5] == 3'b000)) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd61;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (instr == DINT_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd62;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (instr == EINT_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd63;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (instr == PUSHST_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd64;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[39-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (instr == POPST_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd65;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[39-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top11 == CALL_RS_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd66;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top11 == RETS_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd67;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[39-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[23-:5] = instr[4:0];
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (instr == CALLA_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd68;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[31-:4] = 4'd2;
			decoded[33] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (instr == CALLR_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd69;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[31-:4] = 4'd2;
			decoded[34] = 1'b1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (instr == RETI_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd70;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[39-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top11 == TRAP_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd71;
			decoded[44] = 1'b0;
			decoded[43-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[39-:4] = tms34010_pkg_REG_SP_IDX;
			decoded[23-:5] = instr[4:0];
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[8] = 1'b1;
		end
		if (top11 == MMTM_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd72;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[34] = 1'b1;
			decoded[8] = 1'b1;
		end
		if (top11 == MMFM_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd73;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			decoded[34] = 1'b1;
			decoded[8] = 1'b1;
		end
		if (top7 == ADD_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd4;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == ADDC_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd32;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd1;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == SUB_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd5;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == SUBB_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd33;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd3;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
		end
		if (top7 == AND_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd6;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd5;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top7 == ANDN_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd7;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd6;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top7 == OR_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd8;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd7;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top7 == XOR_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd9;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd8;
			decoded[14] = 1'b1;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (top7 == CMP_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd10;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd4;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
		end
		if ((((instr[15:12] == JRCC_TOP4) && (instr[7:0] != 8'h00)) && (instr[7:0] != 8'h80)) && ((((((((((((((((instr[11:8] == tms34010_pkg_CC_UC) || (instr[11:8] == tms34010_pkg_CC_P)) || (instr[11:8] == tms34010_pkg_CC_LS)) || (instr[11:8] == tms34010_pkg_CC_HI)) || (instr[11:8] == tms34010_pkg_CC_LT)) || (instr[11:8] == tms34010_pkg_CC_LE)) || (instr[11:8] == tms34010_pkg_CC_GT)) || (instr[11:8] == tms34010_pkg_CC_GE)) || (instr[11:8] == tms34010_pkg_CC_EQ)) || (instr[11:8] == tms34010_pkg_CC_NE)) || (instr[11:8] == tms34010_pkg_CC_HS)) || (instr[11:8] == tms34010_pkg_CC_C)) || (instr[11:8] == tms34010_pkg_CC_V)) || (instr[11:8] == tms34010_pkg_CC_NV)) || (instr[11:8] == tms34010_pkg_CC_N)) || (instr[11:8] == tms34010_pkg_CC_NN))) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd11;
			decoded[18-:4] = instr[11:8];
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (((instr[15:12] == JRCC_TOP4) && (instr[7:0] == 8'h00)) && ((((((((((((((((instr[11:8] == tms34010_pkg_CC_UC) || (instr[11:8] == tms34010_pkg_CC_P)) || (instr[11:8] == tms34010_pkg_CC_LS)) || (instr[11:8] == tms34010_pkg_CC_HI)) || (instr[11:8] == tms34010_pkg_CC_LT)) || (instr[11:8] == tms34010_pkg_CC_LE)) || (instr[11:8] == tms34010_pkg_CC_GT)) || (instr[11:8] == tms34010_pkg_CC_GE)) || (instr[11:8] == tms34010_pkg_CC_EQ)) || (instr[11:8] == tms34010_pkg_CC_NE)) || (instr[11:8] == tms34010_pkg_CC_HS)) || (instr[11:8] == tms34010_pkg_CC_C)) || (instr[11:8] == tms34010_pkg_CC_V)) || (instr[11:8] == tms34010_pkg_CC_NV)) || (instr[11:8] == tms34010_pkg_CC_N)) || (instr[11:8] == tms34010_pkg_CC_NN))) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd34;
			decoded[18-:4] = instr[11:8];
			decoded[34] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (instr == NOP_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd31;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (instr == 16'h0fc0) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd94;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0fe0) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd95;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0f00) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd96;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0f20) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd96;
			decoded[1] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0f40) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd96;
			decoded[2] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0f60) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd96;
			decoded[2] = 1'b1;
			decoded[1] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0f80) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd96;
			decoded[0] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (instr == 16'h0fa0) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd96;
			decoded[0] = 1'b1;
			decoded[1] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
			decoded[8] = 1'b0;
		end
		if (top11 == JUMP_RS_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd35;
			decoded[44] = reg_file_from_instr;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (((top11 == DSJ_TOP11) || (top11 == DSJEQ_TOP11)) || (top11 == DSJNE_TOP11)) begin
			decoded[52] = 1'b0;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = 5'd1;
			decoded[31-:4] = 4'd2;
			decoded[34] = 1'b1;
			decoded[32] = 1'b0;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
			(* full_case, parallel_case *)
			case (top11)
				DSJ_TOP11: decoded[51-:7] = 7'd36;
				DSJEQ_TOP11: decoded[51-:7] = 7'd37;
				DSJNE_TOP11: decoded[51-:7] = 7'd38;
				default: decoded[51-:7] = 7'd0;
			endcase
		end
		if (((instr[15:12] == JRCC_TOP4) && (instr[7:0] == 8'h80)) && ((((((((((((((((instr[11:8] == tms34010_pkg_CC_UC) || (instr[11:8] == tms34010_pkg_CC_P)) || (instr[11:8] == tms34010_pkg_CC_LS)) || (instr[11:8] == tms34010_pkg_CC_HI)) || (instr[11:8] == tms34010_pkg_CC_LT)) || (instr[11:8] == tms34010_pkg_CC_LE)) || (instr[11:8] == tms34010_pkg_CC_GT)) || (instr[11:8] == tms34010_pkg_CC_GE)) || (instr[11:8] == tms34010_pkg_CC_EQ)) || (instr[11:8] == tms34010_pkg_CC_NE)) || (instr[11:8] == tms34010_pkg_CC_HS)) || (instr[11:8] == tms34010_pkg_CC_C)) || (instr[11:8] == tms34010_pkg_CC_V)) || (instr[11:8] == tms34010_pkg_CC_NV)) || (instr[11:8] == tms34010_pkg_CC_N)) || (instr[11:8] == tms34010_pkg_CC_NN))) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd39;
			decoded[18-:4] = instr[11:8];
			decoded[33] = 1'b1;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (instr[15:11] == DSJS_TOP5) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd40;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = 5'd1;
			decoded[31-:4] = 4'd2;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top6 == BTST_K_TOP6) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd43;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[23-:5] = ~instr[9:5];
			decoded[31-:4] = 4'd5;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
		if (instr == CLRC_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd45;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0100;
		end
		if (instr == SETC_OPCODE) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd46;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0100;
		end
		if (top11 == GETST_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd47;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top11 == PUTST_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd48;
			decoded[44] = reg_file_from_instr;
			decoded[39-:4] = reg_idx_from_instr;
			decoded[14] = 1'b0;
			decoded[13] = 1'b0;
		end
		if (top11 == GETPC_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd54;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top11 == EXGPC_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd55;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top11 == REV_TOP11) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd56;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[14] = 1'b1;
			decoded[13] = 1'b0;
		end
		if (top7 == BTST_RR_TOP7) begin
			decoded[52] = 1'b0;
			decoded[51-:7] = 7'd44;
			decoded[44] = reg_file_from_instr;
			decoded[43-:4] = reg_idx_from_instr;
			decoded[39-:4] = rs_idx_from_instr;
			decoded[31-:4] = 4'd5;
			decoded[14] = 1'b0;
			decoded[13] = 1'b1;
			decoded[12-:4] = 4'b0010;
		end
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_divider (
	clk,
	ce_cpu,
	rst,
	start,
	dividend,
	divisor,
	busy,
	done,
	quotient,
	remainder,
	overflow
);
	input wire clk;
	input wire ce_cpu;
	input wire rst;
	input wire start;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	input wire [63:0] dividend;
	input wire [31:0] divisor;
	output wire busy;
	output wire done;
	output wire [31:0] quotient;
	output wire [31:0] remainder;
	output wire overflow;
	reg [1:0] st_q;
	reg [tms34010_pkg_DATA_WIDTH:0] rem_q;
	reg [31:0] quot_q;
	reg [31:0] dvd_lo_q;
	reg [31:0] divisor_q;
	reg ovf_q;
	localparam [31:0] tms34010_pkg_SHIFT_AMOUNT_WIDTH = 5;
	reg [tms34010_pkg_SHIFT_AMOUNT_WIDTH:0] iter_q;
	wire [tms34010_pkg_DATA_WIDTH:0] shifted;
	wire [tms34010_pkg_DATA_WIDTH:0] divisor_ext;
	assign divisor_ext = {1'b0, divisor_q};
	assign shifted = {rem_q[31:0], dvd_lo_q[31]};
	wire start_overflow;
	assign start_overflow = (divisor == {32 {1'sb0}}) || (dividend[63:tms34010_pkg_DATA_WIDTH] >= divisor);
	function automatic [5:0] sv2v_cast_287E4;
		input reg [5:0] inp;
		sv2v_cast_287E4 = inp;
	endfunction
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst) begin
				st_q <= 2'd0;
				rem_q <= 1'sb0;
				quot_q <= 1'sb0;
				dvd_lo_q <= 1'sb0;
				divisor_q <= 1'sb0;
				ovf_q <= 1'b0;
				iter_q <= 1'sb0;
			end
			else
				(* full_case, parallel_case *)
				case (st_q)
					2'd0:
						if (start) begin
							divisor_q <= divisor;
							ovf_q <= start_overflow;
							rem_q <= {1'b0, dividend[63:tms34010_pkg_DATA_WIDTH]};
							dvd_lo_q <= dividend[31:0];
							quot_q <= 1'sb0;
							iter_q <= 1'sb0;
							st_q <= (start_overflow ? 2'd2 : 2'd1);
						end
					2'd1: begin
						if (shifted >= divisor_ext) begin
							rem_q <= shifted - divisor_ext;
							quot_q <= {quot_q[30:0], 1'b1};
						end
						else begin
							rem_q <= shifted;
							quot_q <= {quot_q[30:0], 1'b0};
						end
						dvd_lo_q <= {dvd_lo_q[30:0], 1'b0};
						iter_q <= iter_q + 1'b1;
						if (iter_q == sv2v_cast_287E4(31))
							st_q <= 2'd2;
					end
					2'd2: st_q <= 2'd0;
					default: st_q <= 2'd0;
				endcase
		end
	assign busy = st_q != 2'd0;
	assign done = st_q == 2'd2;
	assign quotient = quot_q;
	assign remainder = rem_q[31:0];
	assign overflow = ovf_q;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_int_ctrl (
	intpend,
	intenb,
	ie,
	int_req,
	int_vector
);
	reg _sv2v_0;
	input wire [15:0] intpend;
	input wire [15:0] intenb;
	input wire ie;
	output wire int_req;
	localparam [31:0] tms34010_pkg_ADDR_WIDTH = 32;
	output reg [31:0] int_vector;
	wire [15:0] active;
	assign active = intpend & intenb;
	localparam [31:0] tms34010_pkg_INT_DI_BIT = 10;
	localparam [31:0] tms34010_pkg_INT_HI_BIT = 9;
	localparam [31:0] tms34010_pkg_INT_WV_BIT = 11;
	localparam [31:0] tms34010_pkg_INT_X1_BIT = 1;
	localparam [31:0] tms34010_pkg_INT_X2_BIT = 2;
	assign int_req = ie && ((((active[tms34010_pkg_INT_HI_BIT] || active[tms34010_pkg_INT_DI_BIT]) || active[tms34010_pkg_INT_WV_BIT]) || active[tms34010_pkg_INT_X1_BIT]) || active[tms34010_pkg_INT_X2_BIT]);
	localparam [31:0] tms34010_pkg_INT_VEC_DI = 32'hfffffea0;
	localparam [31:0] tms34010_pkg_INT_VEC_HI = 32'hfffffec0;
	localparam [31:0] tms34010_pkg_INT_VEC_WV = 32'hfffffe80;
	localparam [31:0] tms34010_pkg_INT_VEC_X1 = 32'hffffffc0;
	localparam [31:0] tms34010_pkg_INT_VEC_X2 = 32'hffffffa0;
	always @(*) begin
		if (_sv2v_0)
			;
		if (active[tms34010_pkg_INT_HI_BIT])
			int_vector = tms34010_pkg_INT_VEC_HI;
		else if (active[tms34010_pkg_INT_DI_BIT])
			int_vector = tms34010_pkg_INT_VEC_DI;
		else if (active[tms34010_pkg_INT_WV_BIT])
			int_vector = tms34010_pkg_INT_VEC_WV;
		else if (active[tms34010_pkg_INT_X1_BIT])
			int_vector = tms34010_pkg_INT_VEC_X1;
		else if (active[tms34010_pkg_INT_X2_BIT])
			int_vector = tms34010_pkg_INT_VEC_X2;
		else
			int_vector = tms34010_pkg_INT_VEC_HI;
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_pc (
	clk,
	ce_cpu,
	rst,
	load_en,
	load_value,
	advance_en,
	advance_amount,
	pc_o
);
	reg _sv2v_0;
	localparam [31:0] tms34010_pkg_ADDR_WIDTH = 32;
	localparam [31:0] tms34010_pkg_RESET_PC = 1'sb0;
	parameter [31:0] RESET_VALUE = tms34010_pkg_RESET_PC;
	input wire clk;
	input wire ce_cpu;
	input wire rst;
	input wire load_en;
	input wire [31:0] load_value;
	input wire advance_en;
	localparam [31:0] tms34010_pkg_PC_ADVANCE_WIDTH = 8;
	input wire [7:0] advance_amount;
	output wire [31:0] pc_o;
	reg [31:0] pc_q;
	reg [31:0] pc_d;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				pc_q <= RESET_VALUE;
			else
				pc_q <= pc_d;
		end
	wire [31:0] advance_ext;
	assign advance_ext = {{tms34010_pkg_ADDR_WIDTH - tms34010_pkg_PC_ADVANCE_WIDTH {1'b0}}, advance_amount};
	always @(*) begin
		if (_sv2v_0)
			;
		pc_d = pc_q;
		if (load_en)
			pc_d = load_value;
		else if (advance_en)
			pc_d = pc_q + advance_ext;
	end
	assign pc_o = pc_q;
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_regfile (
	clk,
	ce_cpu,
	rst,
	rs1_file,
	rs1_idx,
	rs1_data,
	rs2_file,
	rs2_idx,
	rs2_data,
	rs3_file,
	rs3_idx,
	rs3_data,
	wr_en,
	wr_file,
	wr_idx,
	wr_data,
	sp_o
);
	reg _sv2v_0;
	parameter [0:0] USE_MLAB = 1'b0;
	input wire clk;
	input wire ce_cpu;
	input wire rst;
	input wire rs1_file;
	input wire [3:0] rs1_idx;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	output reg [31:0] rs1_data;
	input wire rs2_file;
	input wire [3:0] rs2_idx;
	output reg [31:0] rs2_data;
	input wire rs3_file;
	input wire [3:0] rs3_idx;
	output reg [31:0] rs3_data;
	input wire wr_en;
	input wire wr_file;
	input wire [3:0] wr_idx;
	input wire [31:0] wr_data;
	output wire [31:0] sp_o;
	reg [31:0] a_regs [0:14];
	reg [31:0] b_regs [0:14];
	reg [31:0] sp_q;
	localparam [3:0] tms34010_pkg_REG_SP_IDX = 4'hf;
	generate
		if (USE_MLAB) begin : mlab
			(* ramstyle = "MLAB, no_rw_check" *) reg [31:0] port1_mem [0:31];
			(* ramstyle = "MLAB, no_rw_check" *) reg [31:0] port2_mem [0:31];
			(* ramstyle = "MLAB, no_rw_check" *) reg [31:0] port3_mem [0:31];
			reg [31:0] valid;
			(* preserve *) reg last_write_valid;
			reg write_phase;
			wire write_pending = write_phase && last_write_valid;
			reg [4:0] last_write_addr;
			reg [31:0] last_write_data;
			wire [4:0] a1 = {rs1_file == 1'b1, rs1_idx};
			wire [4:0] a2 = {rs2_file == 1'b1, rs2_idx};
			wire [4:0] a3 = {rs3_file == 1'b1, rs3_idx};
			wire [4:0] wa = {wr_file == 1'b1, wr_idx};
			wire write_ram = ((!rst && (ce_cpu !== 1'b0)) && wr_en) && (wr_idx != tms34010_pkg_REG_SP_IDX);
			always @(posedge clk)
				if (write_ram) begin
					last_write_addr <= wa;
					last_write_data <= wr_data;
				end
			always @(posedge clk) begin
				if (rst) begin
					write_phase <= 1'b0;
					last_write_valid <= 1'b0;
				end
				else begin
					write_phase <= ce_cpu !== 1'b0;
					if (ce_cpu !== 1'b0)
						last_write_valid <= wr_en && (wr_idx != tms34010_pkg_REG_SP_IDX);
				end
				if (!rst && write_pending) begin
					port1_mem[last_write_addr] <= last_write_data;
					port2_mem[last_write_addr] <= last_write_data;
					port3_mem[last_write_addr] <= last_write_data;
				end
			end
			always @(posedge clk)
				if (rst) begin
					valid <= 1'sb0;
					sp_q <= 1'sb0;
				end
				else if ((ce_cpu !== 1'b0) && wr_en) begin
					if (wr_idx == tms34010_pkg_REG_SP_IDX)
						sp_q <= wr_data;
					else
						valid[wa] <= 1'b1;
				end
			wire [32:1] sv2v_tmp_FCBB8;
			assign sv2v_tmp_FCBB8 = (rs1_idx == tms34010_pkg_REG_SP_IDX ? sp_q : (valid[a1] ? (a1 == last_write_addr ? last_write_data : port1_mem[a1]) : {32 {1'sb0}}));
			always @(*) rs1_data = sv2v_tmp_FCBB8;
			wire [32:1] sv2v_tmp_AD14B;
			assign sv2v_tmp_AD14B = (rs2_idx == tms34010_pkg_REG_SP_IDX ? sp_q : (valid[a2] ? (a2 == last_write_addr ? last_write_data : port2_mem[a2]) : {32 {1'sb0}}));
			always @(*) rs2_data = sv2v_tmp_AD14B;
			wire [32:1] sv2v_tmp_675DA;
			assign sv2v_tmp_675DA = (rs3_idx == tms34010_pkg_REG_SP_IDX ? sp_q : (valid[a3] ? (a3 == last_write_addr ? last_write_data : port3_mem[a3]) : {32 {1'sb0}}));
			always @(*) rs3_data = sv2v_tmp_675DA;
		end
		else begin : flops
			always @(*) begin
				if (_sv2v_0)
					;
				if (rs1_idx == tms34010_pkg_REG_SP_IDX)
					rs1_data = sp_q;
				else if (rs1_file == 1'b1)
					rs1_data = b_regs[rs1_idx];
				else
					rs1_data = a_regs[rs1_idx];
			end
			always @(*) begin
				if (_sv2v_0)
					;
				if (rs2_idx == tms34010_pkg_REG_SP_IDX)
					rs2_data = sp_q;
				else if (rs2_file == 1'b1)
					rs2_data = b_regs[rs2_idx];
				else
					rs2_data = a_regs[rs2_idx];
			end
			always @(*) begin
				if (_sv2v_0)
					;
				if (rs3_idx == tms34010_pkg_REG_SP_IDX)
					rs3_data = sp_q;
				else if (rs3_file == 1'b1)
					rs3_data = b_regs[rs3_idx];
				else
					rs3_data = a_regs[rs3_idx];
			end
			always @(posedge clk)
				if (rst || (ce_cpu !== 1'b0)) begin
					if (rst) begin
						begin : sv2v_autoblock_1
							reg [31:0] i;
							for (i = 0; i < 15; i = i + 1)
								a_regs[i] <= 1'sb0;
						end
						begin : sv2v_autoblock_2
							reg [31:0] i;
							for (i = 0; i < 15; i = i + 1)
								b_regs[i] <= 1'sb0;
						end
						sp_q <= 1'sb0;
					end
					else if (wr_en) begin
						if (wr_idx == tms34010_pkg_REG_SP_IDX)
							sp_q <= wr_data;
						else if (wr_file == 1'b1)
							b_regs[wr_idx] <= wr_data;
						else
							a_regs[wr_idx] <= wr_data;
					end
				end
		end
	endgenerate
	assign sp_o = sp_q;
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_shifter (
	op,
	a,
	amount,
	result,
	flags
);
	reg _sv2v_0;
	parameter [0:0] SHARED_BARREL = 1'b1;
	input wire [2:0] op;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	input wire [31:0] a;
	localparam [31:0] tms34010_pkg_SHIFT_AMOUNT_WIDTH = 5;
	input wire [4:0] amount;
	output reg [31:0] result;
	output reg [3:0] flags;
	wire [tms34010_pkg_SHIFT_AMOUNT_WIDTH:0] amount_w6;
	wire [tms34010_pkg_SHIFT_AMOUNT_WIDTH:0] complement_w6;
	assign amount_w6 = {1'b0, amount};
	assign complement_w6 = 6'd32 - amount_w6;
	wire [4:0] left_carry_idx;
	wire [4:0] right_carry_idx;
	assign left_carry_idx = complement_w6[4:0];
	assign right_carry_idx = amount - 5'd1;
	wire [31:0] left;
	wire [31:0] right_l;
	wire signed [31:0] right_a;
	wire [31:0] right_comp;
	wire [31:0] left_comp;
	assign left = a << amount;
	assign right_l = a >> amount;
	assign right_a = $signed(a) >>> amount;
	assign right_comp = a >> complement_w6;
	assign left_comp = a << complement_w6;
	wire shared_left = ((op == 3'd0) || (op == 3'd1)) || (op == 3'd4);
	wire shared_rotate = (op == 3'd4) || (op == 3'd5);
	wire shared_fill = (op == 3'd3) && a[31];
	wire [31:0] shared_stage [0:tms34010_pkg_SHIFT_AMOUNT_WIDTH];
	wire [31:0] shared_result;
	genvar _gv_bit_idx_1;
	generate
		for (_gv_bit_idx_1 = 0; _gv_bit_idx_1 < tms34010_pkg_DATA_WIDTH; _gv_bit_idx_1 = _gv_bit_idx_1 + 1) begin : reverse_barrel_bits
			localparam bit_idx = _gv_bit_idx_1;
			assign shared_stage[0][bit_idx] = (shared_left ? a[31 - bit_idx] : a[bit_idx]);
			assign shared_result[bit_idx] = (shared_left ? shared_stage[tms34010_pkg_SHIFT_AMOUNT_WIDTH][31 - bit_idx] : shared_stage[tms34010_pkg_SHIFT_AMOUNT_WIDTH][bit_idx]);
		end
	endgenerate
	genvar _gv_stage_idx_1;
	generate
		for (_gv_stage_idx_1 = 0; _gv_stage_idx_1 < tms34010_pkg_SHIFT_AMOUNT_WIDTH; _gv_stage_idx_1 = _gv_stage_idx_1 + 1) begin : barrel_stage
			localparam stage_idx = _gv_stage_idx_1;
			localparam integer STEP = 1 << stage_idx;
			wire [STEP - 1:0] upper = (shared_rotate ? shared_stage[stage_idx][STEP - 1:0] : {STEP {shared_fill}});
			assign shared_stage[stage_idx + 1] = (amount[stage_idx] ? {upper, shared_stage[stage_idx][31:STEP]} : shared_stage[stage_idx]);
		end
	endgenerate
	wire [31:0] sla_v_mask;
	wire [31:0] sla_v_res2;
	assign sla_v_mask = (32'hffffffff << (6'd31 - amount_w6)) & 32'h7fffffff;
	assign sla_v_res2 = (a[31] ? a ^ sla_v_mask : a);
	generate
		if (SHARED_BARREL) begin : shared_output
			always @(*) begin
				if (_sv2v_0)
					;
				result = a;
				flags[2] = 1'b0;
				flags[0] = 1'b0;
				if ((amount != {5 {1'sb0}}) && (op <= 3'd5)) begin
					result = shared_result;
					flags[2] = shared_stage[0][right_carry_idx];
					if (op == 3'd1)
						flags[0] = |(sla_v_res2 & sla_v_mask);
				end
				flags[3] = result[31];
				flags[1] = result == {32 {1'sb0}};
			end
		end
		else begin : legacy_output
			always @(*) begin
				if (_sv2v_0)
					;
				result = a;
				flags[3] = a[31];
				flags[2] = 1'b0;
				flags[1] = a == {32 {1'sb0}};
				flags[0] = 1'b0;
				if (amount != {5 {1'sb0}}) begin
					(* full_case, parallel_case *)
					case (op)
						3'd0: begin
							result = left;
							flags[2] = a[left_carry_idx];
						end
						3'd1: begin
							result = left;
							flags[2] = a[left_carry_idx];
							flags[0] = |(sla_v_res2 & sla_v_mask);
						end
						3'd2: begin
							result = right_l;
							flags[2] = a[right_carry_idx];
						end
						3'd3: begin
							result = right_a;
							flags[2] = a[right_carry_idx];
						end
						3'd4: begin
							result = left | right_comp;
							flags[2] = a[left_carry_idx];
						end
						3'd5: begin
							result = right_l | left_comp;
							flags[2] = a[right_carry_idx];
						end
						default:
							;
					endcase
					flags[3] = result[31];
					flags[1] = result == {32 {1'sb0}};
				end
			end
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_status_reg (
	clk,
	ce_cpu,
	rst,
	flag_update_en,
	flags_in,
	flag_update_mask,
	st_write_en,
	st_write_data,
	st_o,
	n_o,
	c_o,
	z_o,
	v_o
);
	input wire clk;
	input wire ce_cpu;
	input wire rst;
	input wire flag_update_en;
	input wire [3:0] flags_in;
	input wire [3:0] flag_update_mask;
	input wire st_write_en;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	input wire [31:0] st_write_data;
	output wire [31:0] st_o;
	output wire n_o;
	output wire c_o;
	output wire z_o;
	output wire v_o;
	reg [31:0] st_q;
	localparam [31:0] tms34010_pkg_ST_C_BIT = 30;
	localparam [31:0] tms34010_pkg_ST_N_BIT = 31;
	localparam [31:0] tms34010_pkg_ST_RESET_VALUE = 32'h00000010;
	localparam [31:0] tms34010_pkg_ST_V_BIT = 28;
	localparam [31:0] tms34010_pkg_ST_Z_BIT = 29;
	always @(posedge clk)
		if (rst || (ce_cpu !== 1'b0)) begin
			if (rst)
				st_q <= tms34010_pkg_ST_RESET_VALUE;
			else if (st_write_en)
				st_q <= st_write_data;
			else if (flag_update_en) begin
				if (flag_update_mask[3])
					st_q[tms34010_pkg_ST_N_BIT] <= flags_in[3];
				if (flag_update_mask[2])
					st_q[tms34010_pkg_ST_C_BIT] <= flags_in[2];
				if (flag_update_mask[1])
					st_q[tms34010_pkg_ST_Z_BIT] <= flags_in[1];
				if (flag_update_mask[0])
					st_q[tms34010_pkg_ST_V_BIT] <= flags_in[0];
			end
		end
	assign st_o = st_q;
	assign n_o = st_q[tms34010_pkg_ST_N_BIT];
	assign c_o = st_q[tms34010_pkg_ST_C_BIT];
	assign z_o = st_q[tms34010_pkg_ST_Z_BIT];
	assign v_o = st_q[tms34010_pkg_ST_V_BIT];
endmodule
`default_nettype wire
`default_nettype none
module tms34010_io_regs (
	clk,
	rst,
	ce_cpu,
	req,
	we,
	addr,
	size,
	wdata,
	ce_pix,
	rdata,
	is_io,
	psize_o,
	convdp_o,
	convsp_o,
	control_o,
	pmask_o,
	dpyctl_o,
	intenb_o,
	intpend_o,
	dpystrt_o,
	dpyadr_o,
	vblank_start_o,
	hstctlh_o,
	nmi_clear,
	wvp_set,
	lint1_in,
	heblnk_o,
	hsblnk_o,
	veblnk_o,
	vsblnk_o
);
	reg _sv2v_0;
	parameter [0:0] LOCAL_WRITE = 1'b0;
	parameter [0:0] CPU_CE_WRITE = 1'b0;
	parameter [0:0] BANKED_WRITE = 1'b1;
	input wire clk;
	input wire rst;
	input wire ce_cpu;
	input wire req;
	input wire we;
	localparam [31:0] tms34010_pkg_ADDR_WIDTH = 32;
	input wire [31:0] addr;
	localparam [31:0] tms34010_pkg_FIELD_SIZE_WIDTH = 6;
	input wire [5:0] size;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	input wire [31:0] wdata;
	input wire ce_pix;
	output wire [15:0] rdata;
	output wire is_io;
	output wire [15:0] psize_o;
	output wire [15:0] convdp_o;
	output wire [15:0] convsp_o;
	output wire [15:0] control_o;
	output wire [15:0] pmask_o;
	output wire [15:0] dpyctl_o;
	output wire [15:0] intenb_o;
	output wire [15:0] intpend_o;
	output wire [15:0] dpystrt_o;
	output wire [15:0] dpyadr_o;
	output wire vblank_start_o;
	output wire [15:0] hstctlh_o;
	input wire nmi_clear;
	input wire wvp_set;
	input wire lint1_in;
	output wire [15:0] heblnk_o;
	output wire [15:0] hsblnk_o;
	output wire [15:0] veblnk_o;
	output wire [15:0] vsblnk_o;
	localparam [31:0] tms34010_pkg_IO_REG_IDX_W = 5;
	wire [4:0] idx;
	assign is_io = (addr[31:30] == 2'b11) && (addr[29:9] == {21 {1'sb0}});
	assign idx = addr[8:4];
	localparam [31:0] tms34010_pkg_IO_REG_COUNT = 32;
	reg [15:0] io_reg [0:31];
	wire dpyint_pulse;
	wire [15:0] vid_hcount;
	wire [15:0] vid_vcount;
	wire vid_hs_unused;
	wire vid_vs_unused;
	wire vid_hb_unused;
	wire vid_vb_unused;
	wire vid_bl_unused;
	localparam [4:0] tms34010_pkg_IO_IDX_DPYINT = 5'h0a;
	localparam [4:0] tms34010_pkg_IO_IDX_HEBLNK = 5'h01;
	localparam [4:0] tms34010_pkg_IO_IDX_HESYNC = 5'h00;
	localparam [4:0] tms34010_pkg_IO_IDX_HSBLNK = 5'h02;
	localparam [4:0] tms34010_pkg_IO_IDX_HTOTAL = 5'h03;
	localparam [4:0] tms34010_pkg_IO_IDX_VEBLNK = 5'h05;
	localparam [4:0] tms34010_pkg_IO_IDX_VESYNC = 5'h04;
	localparam [4:0] tms34010_pkg_IO_IDX_VSBLNK = 5'h06;
	localparam [4:0] tms34010_pkg_IO_IDX_VTOTAL = 5'h07;
	tms34010_video u_video(
		.clk(clk),
		.rst(rst),
		.ce(ce_pix),
		.hesync(io_reg[tms34010_pkg_IO_IDX_HESYNC]),
		.heblnk(io_reg[tms34010_pkg_IO_IDX_HEBLNK]),
		.hsblnk(io_reg[tms34010_pkg_IO_IDX_HSBLNK]),
		.htotal(io_reg[tms34010_pkg_IO_IDX_HTOTAL]),
		.vesync(io_reg[tms34010_pkg_IO_IDX_VESYNC]),
		.veblnk(io_reg[tms34010_pkg_IO_IDX_VEBLNK]),
		.vsblnk(io_reg[tms34010_pkg_IO_IDX_VSBLNK]),
		.vtotal(io_reg[tms34010_pkg_IO_IDX_VTOTAL]),
		.dpyint(io_reg[tms34010_pkg_IO_IDX_DPYINT]),
		.hcount(vid_hcount),
		.vcount(vid_vcount),
		.hsync(vid_hs_unused),
		.vsync(vid_vs_unused),
		.hblank(vid_hb_unused),
		.vblank(vid_vb_unused),
		.blank(vid_bl_unused),
		.dpyint_pulse(dpyint_pulse),
		.vblank_start(vblank_start_o)
	);
	wire lint1_lvl;
	assign lint1_lvl = lint1_in === 1'b1;
	wire field_contained;
	reg [15:0] selected_rdata;
	function automatic signed [5:0] sv2v_cast_13C0F_signed;
		input reg signed [5:0] inp;
		sv2v_cast_13C0F_signed = inp;
	endfunction
	assign field_contained = ((size >= sv2v_cast_13C0F_signed(1)) && (size <= sv2v_cast_13C0F_signed(16))) && (({2'b00, addr[3:0]} + size) <= sv2v_cast_13C0F_signed(16));
	localparam [31:0] tms34010_pkg_INT_X1_BIT = 1;
	localparam [4:0] tms34010_pkg_IO_IDX_HCOUNT = 5'h1c;
	localparam [4:0] tms34010_pkg_IO_IDX_INTPEND = 5'h12;
	localparam [4:0] tms34010_pkg_IO_IDX_VCOUNT = 5'h1d;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		selected_rdata = io_reg[idx];
		if (idx == tms34010_pkg_IO_IDX_VCOUNT)
			selected_rdata = vid_vcount;
		else if (idx == tms34010_pkg_IO_IDX_HCOUNT)
			selected_rdata = vid_hcount;
		else if (idx == tms34010_pkg_IO_IDX_INTPEND)
			selected_rdata = io_reg[idx] | (sv2v_cast_16(lint1_lvl) << tms34010_pkg_INT_X1_BIT);
	end
	assign rdata = (!is_io ? 16'h0000 : (field_contained ? selected_rdata >> addr[3:0] : selected_rdata));
	reg io_span;
	reg [5:0] io_lo_bits;
	reg [15:0] io_write_mask;
	reg [15:0] io_write_data;
	reg [15:0] io_hi_mask;
	reg [15:0] io_hi_data;
	always @(*) begin
		if (_sv2v_0)
			;
		io_lo_bits = 6'd16 - {2'b00, addr[3:0]};
		io_span = (is_io && (size > sv2v_cast_13C0F_signed(16))) && (({2'b00, addr[3:0]} + size) <= sv2v_cast_13C0F_signed(32));
		io_write_mask = (field_contained ? (17'h1ffff >> (17 - size)) << addr[3:0] : (io_span ? 16'hffff << addr[3:0] : 16'hffff));
		io_write_data = (field_contained || io_span ? wdata[15:0] << addr[3:0] : wdata[15:0]);
		io_hi_mask = (io_span ? 16'hffff >> (6'd16 - (size - io_lo_bits)) : 16'h0000);
		io_hi_data = (io_span ? sv2v_cast_16(wdata >> io_lo_bits) : 16'h0000);
	end
	wire [15:0] even_write_data = (idx[0] ? io_hi_data : io_write_data);
	wire [15:0] odd_write_data = (idx[0] ? io_write_data : io_hi_data);
	wire [15:0] even_write_mask = (idx[0] ? io_hi_mask : io_write_mask);
	wire [15:0] odd_write_mask = (idx[0] ? io_write_mask : io_hi_mask);
	localparam [4:0] tms34010_pkg_IO_IDX_PSIZE = 5'h15;
	assign psize_o = io_reg[tms34010_pkg_IO_IDX_PSIZE];
	localparam [4:0] tms34010_pkg_IO_IDX_CONVDP = 5'h14;
	assign convdp_o = io_reg[tms34010_pkg_IO_IDX_CONVDP];
	localparam [4:0] tms34010_pkg_IO_IDX_CONVSP = 5'h13;
	assign convsp_o = io_reg[tms34010_pkg_IO_IDX_CONVSP];
	localparam [4:0] tms34010_pkg_IO_IDX_CONTROL = 5'h0b;
	assign control_o = io_reg[tms34010_pkg_IO_IDX_CONTROL];
	localparam [4:0] tms34010_pkg_IO_IDX_DPYCTL = 5'h08;
	assign dpyctl_o = io_reg[tms34010_pkg_IO_IDX_DPYCTL];
	localparam [4:0] tms34010_pkg_IO_IDX_DPYSTRT = 5'h09;
	assign dpystrt_o = io_reg[tms34010_pkg_IO_IDX_DPYSTRT];
	localparam [4:0] tms34010_pkg_IO_IDX_DPYADR = 5'h1e;
	assign dpyadr_o = io_reg[tms34010_pkg_IO_IDX_DPYADR];
	localparam [4:0] tms34010_pkg_IO_IDX_PMASK = 5'h16;
	assign pmask_o = io_reg[tms34010_pkg_IO_IDX_PMASK];
	localparam [4:0] tms34010_pkg_IO_IDX_INTENB = 5'h11;
	assign intenb_o = io_reg[tms34010_pkg_IO_IDX_INTENB];
	assign intpend_o = io_reg[tms34010_pkg_IO_IDX_INTPEND] | (sv2v_cast_16(lint1_lvl) << tms34010_pkg_INT_X1_BIT);
	localparam [4:0] tms34010_pkg_IO_IDX_HSTCTLH = 5'h10;
	assign hstctlh_o = io_reg[tms34010_pkg_IO_IDX_HSTCTLH];
	wire cpu_action = !CPU_CE_WRITE || (ce_cpu !== 1'b0);
	wire cpu_write = ((cpu_action && req) && we) && is_io;
	localparam [31:0] tms34010_pkg_HSTCTL_NMI_BIT = 8;
	localparam [31:0] tms34010_pkg_INT_DI_BIT = 10;
	localparam [31:0] tms34010_pkg_INT_WV_BIT = 11;
	localparam [15:0] tms34010_pkg_INTPEND_W0C_MASK = (16'h0001 << tms34010_pkg_INT_DI_BIT) | (16'h0001 << tms34010_pkg_INT_WV_BIT);
	function automatic signed [4:0] sv2v_cast_7548C_signed;
		input reg signed [4:0] inp;
		sv2v_cast_7548C_signed = inp;
	endfunction
	function automatic [4:0] sv2v_cast_7548C;
		input reg [4:0] inp;
		sv2v_cast_7548C = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < tms34010_pkg_IO_REG_COUNT; i = i + 1)
				io_reg[i] <= 16'h0000;
		end
		else begin
			if (cpu_write) begin
				if (BANKED_WRITE) begin : sv2v_autoblock_2
					reg signed [31:0] i;
					for (i = 0; i < tms34010_pkg_IO_REG_COUNT; i = i + 1)
						if ((idx == sv2v_cast_7548C_signed(i)) || ((io_span && (idx != sv2v_cast_7548C(31))) && ((idx + sv2v_cast_7548C_signed(1)) == sv2v_cast_7548C_signed(i)))) begin
							if (i == tms34010_pkg_IO_IDX_INTPEND)
								io_reg[i] <= io_reg[i] & (((i % 2) == 0 ? even_write_data : odd_write_data) | ~(tms34010_pkg_INTPEND_W0C_MASK & ((i % 2) == 0 ? even_write_mask : odd_write_mask)));
							else
								io_reg[i] <= (io_reg[i] & ~((i % 2) == 0 ? even_write_mask : odd_write_mask)) | (((i % 2) == 0 ? even_write_data : odd_write_data) & ((i % 2) == 0 ? even_write_mask : odd_write_mask));
						end
				end
				else if (LOCAL_WRITE) begin : sv2v_autoblock_3
					reg signed [31:0] i;
					for (i = 0; i < tms34010_pkg_IO_REG_COUNT; i = i + 1)
						begin : sv2v_autoblock_4
							reg signed [31:0] b;
							for (b = 0; b < 16; b = b + 1)
								begin
									if ((idx == sv2v_cast_7548C_signed(i)) && io_write_mask[b]) begin
										if (i == tms34010_pkg_IO_IDX_INTPEND) begin
											if (tms34010_pkg_INTPEND_W0C_MASK[b] && !io_write_data[b])
												io_reg[i][b] <= 1'b0;
										end
										else
											io_reg[i][b] <= io_write_data[b];
									end
									if (((io_span && (idx != sv2v_cast_7548C(31))) && ((idx + sv2v_cast_7548C_signed(1)) == sv2v_cast_7548C_signed(i))) && io_hi_mask[b]) begin
										if (i == tms34010_pkg_IO_IDX_INTPEND) begin
											if (tms34010_pkg_INTPEND_W0C_MASK[b] && !io_hi_data[b])
												io_reg[i][b] <= 1'b0;
										end
										else
											io_reg[i][b] <= io_hi_data[b];
									end
								end
						end
				end
				else begin
					if (idx == tms34010_pkg_IO_IDX_INTPEND)
						io_reg[tms34010_pkg_IO_IDX_INTPEND] <= io_reg[tms34010_pkg_IO_IDX_INTPEND] & (io_write_data | ~(tms34010_pkg_INTPEND_W0C_MASK & io_write_mask));
					else
						io_reg[idx] <= (io_reg[idx] & ~io_write_mask) | (io_write_data & io_write_mask);
					if (io_span && (idx != sv2v_cast_7548C(31))) begin
						if ((idx + sv2v_cast_7548C_signed(1)) == tms34010_pkg_IO_IDX_INTPEND)
							io_reg[tms34010_pkg_IO_IDX_INTPEND] <= io_reg[tms34010_pkg_IO_IDX_INTPEND] & (io_hi_data | ~(tms34010_pkg_INTPEND_W0C_MASK & io_hi_mask));
						else
							io_reg[idx + sv2v_cast_7548C_signed(1)] <= (io_reg[idx + sv2v_cast_7548C_signed(1)] & ~io_hi_mask) | (io_hi_data & io_hi_mask);
					end
				end
			end
			else if (cpu_action && nmi_clear)
				io_reg[tms34010_pkg_IO_IDX_HSTCTLH][tms34010_pkg_HSTCTL_NMI_BIT] <= 1'b0;
			else if (cpu_action && wvp_set)
				io_reg[tms34010_pkg_IO_IDX_INTPEND][tms34010_pkg_INT_WV_BIT] <= 1'b1;
			if (dpyint_pulse && (io_reg[tms34010_pkg_IO_IDX_VTOTAL] != 16'h0000))
				io_reg[tms34010_pkg_IO_IDX_INTPEND][tms34010_pkg_INT_DI_BIT] <= 1'b1;
			if (vblank_start_o && !(cpu_write && (idx == tms34010_pkg_IO_IDX_DPYADR)))
				io_reg[tms34010_pkg_IO_IDX_DPYADR] <= io_reg[tms34010_pkg_IO_IDX_DPYSTRT];
		end
	assign heblnk_o = io_reg[tms34010_pkg_IO_IDX_HEBLNK];
	assign hsblnk_o = io_reg[tms34010_pkg_IO_IDX_HSBLNK];
	assign veblnk_o = io_reg[tms34010_pkg_IO_IDX_VEBLNK];
	assign vsblnk_o = io_reg[tms34010_pkg_IO_IDX_VSBLNK];
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module tms34010_refresh (
	clk,
	rst,
	rr,
	refresh_row,
	refresh_req
);
	input wire clk;
	input wire rst;
	input wire [1:0] rr;
	output wire [7:0] refresh_row;
	output wire refresh_req;
	wire enabled;
	wire [6:0] interval;
	assign enabled = (rr == 2'b00) || (rr == 2'b01);
	assign interval = (rr == 2'b01 ? 7'd63 : 7'd31);
	reg [6:0] presc_q;
	reg [7:0] refresh_row_q;
	assign refresh_req = enabled && (presc_q == interval);
	assign refresh_row = refresh_row_q;
	always @(posedge clk)
		if (rst) begin
			presc_q <= 7'd0;
			refresh_row_q <= 8'd0;
		end
		else if (enabled) begin
			if (presc_q == interval) begin
				presc_q <= 7'd0;
				refresh_row_q <= refresh_row_q + 8'd1;
			end
			else
				presc_q <= presc_q + 7'd1;
		end
endmodule
`default_nettype wire
`default_nettype none
module tms34010_video (
	clk,
	rst,
	ce,
	hesync,
	heblnk,
	hsblnk,
	htotal,
	vesync,
	veblnk,
	vsblnk,
	vtotal,
	dpyint,
	hcount,
	vcount,
	hsync,
	vsync,
	hblank,
	vblank,
	blank,
	dpyint_pulse,
	vblank_start
);
	input wire clk;
	input wire rst;
	input wire ce;
	input wire [15:0] hesync;
	input wire [15:0] heblnk;
	input wire [15:0] hsblnk;
	input wire [15:0] htotal;
	input wire [15:0] vesync;
	input wire [15:0] veblnk;
	input wire [15:0] vsblnk;
	input wire [15:0] vtotal;
	input wire [15:0] dpyint;
	output reg [15:0] hcount;
	output reg [15:0] vcount;
	output wire hsync;
	output wire vsync;
	output wire hblank;
	output wire vblank;
	output wire blank;
	output wire dpyint_pulse;
	output wire vblank_start;
	(* keep *) wire [5:0] hwrap_group_match;
	genvar _gv_h_1;
	generate
		for (_gv_h_1 = 0; _gv_h_1 < 5; _gv_h_1 = _gv_h_1 + 1) begin : hwrap_compare_group
			localparam h = _gv_h_1;
			assign hwrap_group_match[h] = hcount[3 * h+:3] == htotal[3 * h+:3];
		end
	endgenerate
	assign hwrap_group_match[5] = hcount[15] == htotal[15];
	(* keep *) wire hwrap = &hwrap_group_match;
	wire vwrap;
	wire next_line_matches;
	assign vwrap = vcount == vtotal;
	wire [3:0] increment_carry = {&vcount[11:0], &vcount[7:0], &vcount[3:0], 1'b1};
	(* keep *) wire [3:0] increment_nibble_match;
	genvar _gv_n_1;
	generate
		for (_gv_n_1 = 0; _gv_n_1 < 4; _gv_n_1 = _gv_n_1 + 1) begin : increment_compare_nibble
			localparam n = _gv_n_1;
			wire equal_same = vcount[4 * n+:4] == vsblnk[4 * n+:4];
			wire equal_next = (vcount[4 * n+:4] + 4'd1) == vsblnk[4 * n+:4];
			assign increment_nibble_match[n] = (increment_carry[n] ? equal_next : equal_same);
		end
	endgenerate
	(* keep *) wire increment_matches = &increment_nibble_match;
	assign next_line_matches = (vwrap ? vsblnk == 16'd0 : increment_matches);
	wire ce_eff;
	assign ce_eff = (ce === 1'b0 ? 1'b0 : 1'b1);
	always @(posedge clk)
		if (rst) begin
			hcount <= 16'd0;
			vcount <= 16'd0;
		end
		else if (ce_eff) begin
			if (hwrap) begin
				hcount <= 16'd0;
				if (vcount == vtotal)
					vcount <= 16'd0;
				else
					vcount <= vcount + 16'd1;
			end
			else
				hcount <= hcount + 16'd1;
		end
	assign hsync = hcount < hesync;
	assign vsync = vcount < vesync;
	assign hblank = (hcount < heblnk) || (hcount >= hsblnk);
	assign vblank = (vcount < veblnk) || (vcount >= vsblnk);
	assign blank = hblank || vblank;
	assign dpyint_pulse = (ce_eff && (hcount == 16'd0)) && (vcount == dpyint);
	(* keep *) wire vblank_edge_ready = ((hwrap && (htotal != 16'd0)) && (vtotal != 16'd0)) && next_line_matches;
	assign vblank_start = ce_eff && vblank_edge_ready;
endmodule
`default_nettype wire
`default_nettype none
module wolf_mem (
	clk,
	rst,
	mem_req,
	mem_we,
	mem_addr,
	mem_size,
	mem_wdata,
	mem_rdata,
	mem_ack,
	mem_srt,
	fb_we,
	fb_addr,
	fb_wdata,
	dma_palette,
	inputs,
	wwf_io_shuffle_i,
	snd_data_wr,
	snd_data_o,
	snd_data_rd,
	snd_reset,
	snd_rdata,
	snd_stat,
	pic_wr,
	pic_wdata,
	pic_reset,
	pic_rdata,
	pic_status,
	watchdog_kick,
	gfxbank_o,
	erase_start,
	erase_row0,
	erase_lines,
	erase_busy,
	nvram_ext_en,
	nvram_ext_wr,
	nvram_ext_addr,
	nvram_ext_wdata,
	nvram_ext_rdata,
	nvram_cpu_write,
	gfx_rd,
	gfx_raddr,
	gfx_rdata,
	gfx_rack,
	cgfx_is_rom,
	fb_ack,
	fb_wr_busy,
	dbg_vram_cst,
	scan_req,
	scan_addr,
	scan_data,
	scan_ack,
	sdram_por,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready,
	rsd_addr,
	rsd_din,
	rsd_be,
	rsd_rd,
	rsd_wr,
	rsd_dout,
	rsd_ack,
	palv_we_a,
	palv_aa,
	palv_awd,
	palv_we_b,
	palv_ba,
	palv_bwd
);
	reg _sv2v_0;
	parameter signed [31:0] ROM_WORDS = 32'h00020000;
	parameter [27:0] ROM_PROG_OFF = 28'h0060000;
	parameter signed [31:0] RAM_WORDS = 32'h00040000;
	parameter signed [31:0] VRAM_WORDS = 32'h00080000;
	parameter signed [31:0] PAL_WORDS = 32'h00008000;
	parameter signed [31:0] CMOS_WORDS = 32'h00006000;
	parameter signed [31:0] GFX_PIXELS = 32'h00180000;
	parameter ROM_HEX = "umk3_maindata.hex";
	parameter GFX_HEX = "build/umk3_gfx.hex";
	parameter CMOS_HEX = "build/umk3_cmos.hex";
	parameter NB_VRAM_HEX = "../../mame-gospel/trace/nearblit/vram.hex";
	parameter NB_RAM_HEX = "../../mame-gospel/trace/nearblit/ram.hex";
	parameter NB_PAL_HEX = "../../mame-gospel/trace/nearblit/pal.hex";
	parameter NB_CMOS_HEX = "../../mame-gospel/trace/nearblit/cmos.hex";
	parameter [0:0] WWF_IO_SHUFFLE = 1'b0;
	input wire clk;
	input wire rst;
	input wire mem_req;
	input wire mem_we;
	input wire [31:0] mem_addr;
	input wire [5:0] mem_size;
	input wire [31:0] mem_wdata;
	output reg [31:0] mem_rdata;
	output reg mem_ack;
	input wire mem_srt;
	input wire fb_we;
	localparam signed [31:0] wolf_pkg_FB_ADDR_W = 19;
	input wire [18:0] fb_addr;
	input wire [15:0] fb_wdata;
	input wire [15:0] dma_palette;
	input wire [63:0] inputs;
	input wire wwf_io_shuffle_i;
	output reg snd_data_wr;
	output reg [7:0] snd_data_o;
	output reg snd_data_rd;
	output reg snd_reset;
	input wire [7:0] snd_rdata;
	input wire [15:0] snd_stat;
	output reg pic_wr;
	output reg [7:0] pic_wdata;
	output reg pic_reset;
	input wire [7:0] pic_rdata;
	input wire [3:0] pic_status;
	output reg watchdog_kick;
	output wire [1:0] gfxbank_o;
	input wire erase_start;
	input wire [8:0] erase_row0;
	input wire [9:0] erase_lines;
	output wire erase_busy;
	input wire nvram_ext_en;
	input wire nvram_ext_wr;
	input wire [15:0] nvram_ext_addr;
	input wire [7:0] nvram_ext_wdata;
	output wire [7:0] nvram_ext_rdata;
	output reg nvram_cpu_write;
	output reg gfx_rd;
	output wire [25:0] gfx_raddr;
	input wire [7:0] gfx_rdata;
	input wire gfx_rack;
	output reg cgfx_is_rom;
	output wire fb_ack;
	output wire fb_wr_busy;
	output wire [2:0] dbg_vram_cst;
	input wire scan_req;
	input wire [18:0] scan_addr;
	output wire [15:0] scan_data;
	output wire scan_ack;
	input wire sdram_por;
	output wire [28:0] ddram_addr;
	output wire [7:0] ddram_burstcnt;
	output wire ddram_rd;
	output wire ddram_we;
	output wire [63:0] ddram_din;
	output wire [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	output wire [24:0] rsd_addr;
	output wire [15:0] rsd_din;
	output wire [1:0] rsd_be;
	output wire rsd_rd;
	output wire rsd_wr;
	input wire [15:0] rsd_dout;
	input wire rsd_ack;
	output reg palv_we_a;
	output reg [14:0] palv_aa;
	output reg [15:0] palv_awd;
	output reg palv_we_b;
	output reg [14:0] palv_ba;
	output reg [15:0] palv_bwd;
	localparam [3:0] R_NONE = 4'd0;
	localparam [3:0] R_VRAM = 4'd1;
	localparam [3:0] R_RAM = 4'd2;
	localparam [3:0] R_CMOS = 4'd3;
	localparam [3:0] R_CMOSEN = 4'd4;
	localparam [3:0] R_PAL = 4'd5;
	localparam [3:0] R_DMA = 4'd6;
	localparam [3:0] R_IO = 4'd7;
	localparam [3:0] R_SECURITY = 4'd8;
	localparam [3:0] R_SOUND = 4'd9;
	localparam [3:0] R_CTRL = 4'd10;
	localparam [3:0] R_GFX = 4'd11;
	localparam [3:0] R_ROM = 4'd12;
	localparam [31:0] wolf_pkg_WMAP_RAM_BASE = 32'h01000000;
	function automatic [27:0] sv2v_cast_28;
		input reg [27:0] inp;
		sv2v_cast_28 = inp;
	endfunction
	localparam [27:0] WB_RAM = sv2v_cast_28(wolf_pkg_WMAP_RAM_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_MAINDATA_BASE = 32'hff800000;
	localparam [27:0] WB_ROM = sv2v_cast_28(wolf_pkg_WMAP_MAINDATA_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_VRAM_BASE = 32'h00000000;
	localparam [27:0] WB_VRAM = sv2v_cast_28(wolf_pkg_WMAP_VRAM_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_PAL_BASE = 32'h01880000;
	localparam [27:0] WB_PAL = sv2v_cast_28(wolf_pkg_WMAP_PAL_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_CMOS_BASE = 32'h01400000;
	localparam [27:0] WB_CMOS = sv2v_cast_28(wolf_pkg_WMAP_CMOS_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_IO_BASE = 32'h01800000;
	localparam [27:0] WB_IO = sv2v_cast_28(wolf_pkg_WMAP_IO_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_SECURITY_BASE = 32'h01600000;
	localparam [27:0] WB_SEC = sv2v_cast_28(wolf_pkg_WMAP_SECURITY_BASE >> 4);
	localparam [31:0] wolf_pkg_WMAP_GFX_BASE = 32'h02000000;
	localparam [27:0] WB_GFX = sv2v_cast_28(wolf_pkg_WMAP_GFX_BASE >> 4);
	(* ramstyle = "no_rw_check" *) reg [15:0] pal [0:PAL_WORDS - 1];
	reg videobank = 1'b0;
	reg [1:0] gfxbank = 2'd0;
	reg [15:0] control_word = 16'd0;
	reg [2:0] ioshuffle [0:15];
	reg wwf_io_shuffle_active;
	always @(*) begin
		if (_sv2v_0)
			;
		wwf_io_shuffle_active = WWF_IO_SHUFFLE;
		case (wwf_io_shuffle_i)
			1'b1: wwf_io_shuffle_active = 1'b1;
			default: wwf_io_shuffle_active = WWF_IO_SHUFFLE;
		endcase
	end
	reg cmos_we = 1'b0;
	reg hw_cmos_write_ok = 1'b0;
	wire nvram_ext_active = nvram_ext_en === 1'b1;
	wire nvram_ext_write = (nvram_ext_active && (nvram_ext_wr === 1'b1)) && (nvram_ext_addr < (CMOS_WORDS * 2));
	assign gfxbank_o = gfxbank;
	reg autoerase = 1'b0;
	reg er_run = 1'b0;
	wire [8:0] er_row;
	wire [8:0] er_x;
	wire [9:0] er_left;
	(* ramstyle = "no_rw_check" *) reg [15:0] nvram [0:CMOS_WORDS - 1];
	localparam [4:0] M_IDLE = 5'd0;
	localparam [4:0] M_ACK = 5'd1;
	localparam [4:0] M_GFX = 5'd2;
	localparam [4:0] M_HR1 = 5'd3;
	localparam [4:0] M_HR2 = 5'd4;
	localparam [4:0] M_HFIN = 5'd5;
	localparam [4:0] M_HW2 = 5'd6;
	localparam [4:0] M_VRD = 5'd7;
	localparam [4:0] M_VWR0 = 5'd8;
	localparam [4:0] M_VWR1 = 5'd9;
	localparam [4:0] M_VWW0 = 5'd10;
	localparam [4:0] M_VWW1 = 5'd11;
	localparam [4:0] M_VSD = 5'd12;
	localparam [4:0] M_RSD = 5'd15;
	localparam [4:0] M_HFIN2 = 5'd13;
	localparam [4:0] M_RDLY = 5'd14;
	localparam [4:0] M_GFIN = 5'd16;
	localparam [4:0] M_SRB = 5'd17;
	localparam [4:0] M_SRTD = 5'd18;
	reg [4:0] state;
	reg [25:0] gfx_base;
	reg [2:0] gfx_cnt;
	reg [2:0] gfx_last;
	reg [47:0] gfx_win;
	reg [47:0] gfx_win_with_byte;
	function automatic signed [25:0] sv2v_cast_26_signed;
		input reg signed [25:0] inp;
		sv2v_cast_26_signed = inp;
	endfunction
	localparam [25:0] SDRAM_ROMB = sv2v_cast_26_signed(GFX_PIXELS);
	always @(*) begin
		if (_sv2v_0)
			;
		gfx_win_with_byte = gfx_win;
		case (gfx_cnt)
			3'd0: gfx_win_with_byte[7:0] = gfx_rdata;
			3'd1: gfx_win_with_byte[15:8] = gfx_rdata;
			3'd2: gfx_win_with_byte[23:16] = gfx_rdata;
			3'd3: gfx_win_with_byte[31:24] = gfx_rdata;
			3'd4: gfx_win_with_byte[39:32] = gfx_rdata;
			3'd5: gfx_win_with_byte[47:40] = gfx_rdata;
			default:
				;
		endcase
	end
	reg [31:0] a_q;
	reg we_q;
	reg [31:0] wd_q;
	reg [5:0] sz_q;
	reg srt_q;
	wire [27:0] widx = a_q[31:4];
	wire [3:0] boff = a_q[3:0];
	wire [5:0] sz = sz_q;
	reg [3:0] region;
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		casez (a_q[31:20])
			12'h000, 12'h001, 12'h002, 12'h003: region = R_VRAM;
			12'h010, 12'h011, 12'h012, 12'h013: region = R_RAM;
			12'h014: region = (a_q[19] ? R_CMOSEN : R_CMOS);
			12'h016: region = (a_q[19] ? R_SOUND : R_SECURITY);
			12'h018: region = (a_q[19] ? R_PAL : R_IO);
			12'h01a: region = R_DMA;
			12'h01b: region = R_CTRL;
			12'h02z, 12'h03z, 12'h04z, 12'h05z, 12'h06z: region = R_GFX;
			12'hff8, 12'hff9, 12'hffa, 12'hffb, 12'hffc, 12'hffd, 12'hffe, 12'hfff: region = R_ROM;
			default: region = R_NONE;
		endcase
	end
	wire is_hwvram = region == R_VRAM;
	wire is_sdram_ram = region == R_RAM;
	wire [28:0] srt_base = {widx, 1'b0};
	localparam [27:0] ROMW = ROM_WORDS[27:0];
	localparam [27:0] RAMW = RAM_WORDS[27:0];
	localparam [27:0] VRAMW = VRAM_WORDS[27:0];
	localparam [27:0] PALW = PAL_WORDS[27:0];
	localparam [27:0] CMOSW = CMOS_WORDS[27:0];
	localparam [27:0] GFXPIXW = GFX_PIXELS[27:0];
	function automatic [15:0] read_word;
		input reg [3:0] rgn;
		input reg [27:0] gw;
		reg [27:0] rel;
		begin
			read_word = 16'h0000;
			if (rgn == R_ROM)
				;
			else if (rgn == R_RAM)
				;
			else if (rgn == R_VRAM)
				;
			else if (rgn == R_PAL)
				;
			else if (rgn == R_CMOS)
				;
			else if (rgn == R_IO) begin
				rel = gw - WB_IO;
				case ((wwf_io_shuffle_active ? ioshuffle[rel[3:0]] : rel[2:0]))
					3'd0: read_word = inputs[15:0];
					3'd1: read_word = inputs[31:16];
					3'd2: read_word = inputs[63:48];
					3'd3: read_word = inputs[47:32];
					3'd4: read_word = {pic_status, 12'd0} | snd_stat;
					default: read_word = 16'hffff;
				endcase
			end
			else if (rgn == R_SECURITY)
				read_word = {8'h00, pic_rdata};
			else if (rgn == R_SOUND)
				read_word = {8'h00, snd_rdata};
			else if (rgn == R_CTRL)
				read_word = control_word;
			else if (rgn == R_GFX)
				rel = gw - WB_GFX;
		end
	endfunction
	wire [47:0] rmask = (48'd1 << sz) - 48'd1;
	wire [47:0] smask = rmask << boff;
	wire [5:0] lastb = (boff + sz) - 6'd1;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [31:0] srt_rdata_f;
		input reg [15:0] e0;
		input reg [15:0] e1;
		reg [15:0] w;
		begin
			w = (videobank ? {e1[7:0], e0[7:0]} : {e1[15:8], e0[15:8]});
			srt_rdata_f = sv2v_cast_32(({32'h00000000, w} >> boff) & rmask);
		end
	endfunction
	assign gfx_raddr = gfx_base;
	reg ext_fetch;
	reg [25:0] ext_base;
	reg [27:0] rom_rel;
	function automatic [25:0] sv2v_cast_26;
		input reg [25:0] inp;
		sv2v_cast_26 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		ext_fetch = 1'b0;
		ext_base = 26'd0;
		rom_rel = widx - WB_ROM;
		if ((region == R_GFX) && !we_q) begin
			ext_fetch = 1'b1;
			ext_base = {gfxbank, 23'd0} + sv2v_cast_26((widx - WB_GFX) << 1);
		end
		if ((((region == R_ROM) && !we_q) && (rom_rel >= ROM_PROG_OFF)) && ((rom_rel - ROM_PROG_OFF) < ROMW)) begin
			ext_fetch = 1'b1;
			ext_base = SDRAM_ROMB + sv2v_cast_26((rom_rel - ROM_PROG_OFF) << 1);
		end
	end
	reg is_hwram;
	reg [1:0] hsel;
	reg [17:0] hidx [0:2];
	reg hval [0:2];
	reg [27:0] hr;
	always @(*) begin
		if (_sv2v_0)
			;
		is_hwram = 1'b0;
		hsel = 2'd0;
		hr = 28'd0;
		begin : sv2v_autoblock_1
			reg signed [31:0] j;
			for (j = 0; j < 3; j = j + 1)
				begin
					hidx[j] = 18'd0;
					hval[j] = 1'b0;
				end
		end
		if (region == R_RAM)
			;
		else if (region == R_PAL) begin
			is_hwram = 1'b1;
			hsel = 2'd1;
			begin : sv2v_autoblock_2
				reg signed [31:0] j;
				for (j = 0; j < 3; j = j + 1)
					begin
						hr = (widx + j[27:0]) - WB_PAL;
						hidx[j] = hr[17:0];
						hval[j] = hr < PALW;
					end
			end
		end
		else if (region == R_CMOS) begin
			is_hwram = 1'b1;
			hsel = 2'd2;
			begin : sv2v_autoblock_3
				reg signed [31:0] j;
				for (j = 0; j < 3; j = j + 1)
					begin
						hr = (widx + j[27:0]) - WB_CMOS;
						hidx[j] = hr[17:0];
						hval[j] = hr < CMOSW;
					end
			end
		end
	end
	reg [15:0] rd0;
	reg [15:0] rd1;
	reg [15:0] rd2;
	wire [47:0] hwin = {(hval[2] ? rd2 : 16'h0000), (hval[1] ? rd1 : 16'h0000), (hval[0] ? rd0 : 16'h0000)};
	wire [47:0] hmerged = (hwin & ~smask) | (({16'h0000, wd_q} << boff) & smask);
	reg [47:0] smask_q;
	reg [47:0] rmask_q;
	reg [47:0] wsh_q;
	reg [47:0] hwin_q;
	reg [3:0] boff_q;
	reg [1:0] hwrite_sel_q;
	reg [2:0] hwrite_valid_q;
	always @(posedge clk) begin
		smask_q <= smask;
		rmask_q <= rmask;
		boff_q <= boff;
		hwrite_sel_q <= hsel;
		hwrite_valid_q <= {hval[2], hval[1], hval[0]};
		wsh_q <= {16'h0000, wd_q} << boff;
		hwin_q <= hwin;
	end
	wire [47:0] hmerged2 = (hwin_q & ~smask_q) | (wsh_q & smask_q);
	reg [17:0] eng_aa;
	reg [17:0] eng_ba;
	reg eng_awe;
	reg eng_bwe;
	reg [15:0] eng_awd;
	reg [15:0] eng_bwd;
	reg [15:0] eng_aq;
	reg [15:0] eng_bq;
	always @(*) begin
		if (_sv2v_0)
			;
		eng_aa = hidx[0];
		eng_ba = hidx[1];
		eng_awe = 1'b0;
		eng_bwe = 1'b0;
		eng_awd = hmerged2[15:0];
		eng_bwd = hmerged2[31:16];
		case (state)
			M_HR1: eng_aa = hidx[2];
			M_HFIN2:
				if (we_q) begin
					eng_aa = hidx[0];
					eng_awe = hwrite_valid_q[0];
					eng_ba = hidx[1];
					eng_bwe = (lastb >= 6'd16) & hwrite_valid_q[1];
				end
			M_HW2: begin
				eng_aa = hidx[2];
				eng_awe = (lastb >= 6'd32) & hwrite_valid_q[2];
				eng_awd = hmerged2[47:32];
			end
			default:
				;
		endcase
	end
	reg [17:0] ram_aa;
	reg [17:0] ram_ba;
	reg ram_awe;
	reg ram_bwe;
	reg [15:0] ram_awd;
	reg [15:0] ram_bwd;
	wire [15:0] ram_aq;
	wire [15:0] ram_bq;
	reg [14:0] pal_aa;
	reg [14:0] pal_ba;
	reg pal_awe;
	reg pal_bwe;
	reg [15:0] pal_awd;
	reg [15:0] pal_bwd;
	reg [15:0] pal_aq;
	reg [15:0] pal_bq;
	reg [14:0] nv_aa;
	reg [14:0] nv_ba;
	reg nv_awe;
	reg nv_bwe;
	reg [15:0] nv_awd;
	reg [15:0] nv_bwd;
	reg [15:0] nv_aq;
	reg [15:0] nv_bq;
	reg nvram_ext_lane_q;
	always @(*) begin
		if (_sv2v_0)
			;
		ram_aa = eng_aa[17:0];
		ram_ba = eng_ba[17:0];
		ram_awd = eng_awd;
		ram_bwd = eng_bwd;
		pal_aa = eng_aa[14:0];
		pal_ba = eng_ba[14:0];
		pal_awd = eng_awd;
		pal_bwd = eng_bwd;
		nv_aa = widx[14:0] + ((state == M_HR1) || (state == M_HW2) ? 15'd2 : 15'd0);
		nv_ba = (nvram_ext_active ? nvram_ext_addr[15:1] : (is_hwram ? widx[14:0] + 15'd1 : 15'd0));
		nv_awd = eng_awd;
		nv_bwd = eng_bwd;
		ram_awe = (hwrite_sel_q == 2'd0) & eng_awe;
		ram_bwe = (hwrite_sel_q == 2'd0) & eng_bwe;
		pal_awe = (hwrite_sel_q == 2'd1) & eng_awe;
		pal_bwe = (hwrite_sel_q == 2'd1) & eng_bwe;
		nv_awe = ((hwrite_sel_q == 2'd2) & eng_awe) & hw_cmos_write_ok;
		nv_bwe = ((hwrite_sel_q == 2'd2) & eng_bwe) & hw_cmos_write_ok;
		eng_aq = (hsel == 2'd0 ? ram_aq : (hsel == 2'd1 ? pal_aq : nv_aq));
		eng_bq = (hsel == 2'd0 ? ram_bq : (hsel == 2'd1 ? pal_bq : nv_bq));
	end
	assign ram_aq = 16'h0000;
	assign ram_bq = 16'h0000;
	always @(posedge clk) begin
		if (pal_awe)
			pal[pal_aa] <= pal_awd;
		pal_aq <= pal[pal_aa];
	end
	always @(posedge clk) begin
		if (pal_bwe)
			pal[pal_ba] <= pal_bwd;
		pal_bq <= pal[pal_ba];
	end
	always @(posedge clk) begin
		if (nv_awe)
			nvram[nv_aa] <= nv_awd;
		nv_aq <= nvram[nv_aa];
	end
	always @(posedge clk)
		if (nvram_ext_active) begin
			if (nvram_ext_write) begin
				if (nvram_ext_addr[0])
					nvram[nv_ba][15:8] <= nvram_ext_wdata;
				else
					nvram[nv_ba][7:0] <= nvram_ext_wdata;
			end
			nv_bq <= nvram[nv_ba];
			nvram_ext_lane_q <= nvram_ext_addr[0];
		end
		else begin
			if (nv_bwe)
				nvram[nv_ba] <= nv_bwd;
			nv_bq <= nvram[nv_ba];
		end
	assign nvram_ext_rdata = (nvram_ext_lane_q ? nv_bq[15:8] : nv_bq[7:0]);
	always @(posedge clk) begin
		palv_we_a <= pal_awe;
		palv_aa <= pal_aa;
		palv_awd <= pal_awd;
		palv_we_b <= pal_bwe;
		palv_ba <= pal_ba;
		palv_bwd <= pal_bwd;
	end
	reg vsd_req;
	wire vsd_done;
	wire [31:0] vsd_rdata;
	reg vsrt_req;
	wire vsrt_done;
	wire [31:0] vsrt_e0e1;
	stv_vram_ddr_top #(
		.VRAMW(VRAM_WORDS),
		.VRAM_DDR_BASE(29'h06400000)
	) u_vram_sdram(
		.clk(clk),
		.rst(rst),
		.sdram_por(sdram_por),
		.req(vsd_req),
		.we(we_q),
		.widx(widx),
		.boff(boff),
		.sz(sz_q),
		.wd(wd_q),
		.videobank(videobank),
		.dma_palette(dma_palette),
		.rdata(vsd_rdata),
		.done(vsd_done),
		.srt_req(vsrt_req),
		.srt_we(we_q),
		.srt_entry(srt_base[18:0]),
		.srt_done(vsrt_done),
		.srt_e0e1(vsrt_e0e1),
		.fb_we(fb_we),
		.fb_addr(fb_addr),
		.fb_wdata(fb_wdata),
		.fb_ack(fb_ack),
		.wr_busy(fb_wr_busy),
		.dbg_cst(dbg_vram_cst),
		.erase_start(erase_start),
		.erase_row0(erase_row0),
		.erase_lines(erase_lines),
		.erase_busy(erase_busy),
		.scan_req(scan_req),
		.scan_addr(scan_addr),
		.scan_data(scan_data),
		.scan_ack(scan_ack),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_be(ddram_be),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready)
	);
	reg rsd_req;
	wire rsd_done;
	wire [31:0] rsd_rdata;
	ram_sdram #(
		.RAMW(RAM_WORDS),
		.SD_AW(25),
		.RAM_BASE(25'd0)
	) u_ram_sdram(
		.clk(clk),
		.rst(rst),
		.req(rsd_req),
		.we(we_q),
		.widx(widx - WB_RAM),
		.boff(boff),
		.sz(sz_q),
		.wd(wd_q),
		.rdata(rsd_rdata),
		.done(rsd_done),
		.active(),
		.sd_addr(rsd_addr),
		.sd_din(rsd_din),
		.sd_be(rsd_be),
		.sd_rd(rsd_rd),
		.sd_wr(rsd_wr),
		.sd_dout(rsd_dout),
		.sd_ack(rsd_ack)
	);
	reg [47:0] win_s;
	reg [47:0] merged_s;
	reg [47:0] win_s_q;
	reg [27:0] wrel;
	always @(posedge clk)
		if (rst) begin
			state <= M_IDLE;
			mem_ack <= 1'b0;
			mem_rdata <= 32'h00000000;
			snd_data_wr <= 1'b0;
			snd_data_o <= 8'h00;
			snd_data_rd <= 1'b0;
			snd_reset <= 1'b0;
			pic_wr <= 1'b0;
			pic_wdata <= 8'h00;
			pic_reset <= 1'b0;
			watchdog_kick <= 1'b0;
			cmos_we <= 1'b0;
			hw_cmos_write_ok <= 1'b0;
			nvram_cpu_write <= 1'b0;
			videobank <= 1'b0;
			gfxbank <= 2'd0;
			control_word <= 16'd0;
			begin : sv2v_autoblock_4
				reg signed [31:0] io_i;
				for (io_i = 0; io_i < 16; io_i = io_i + 1)
					ioshuffle[io_i] <= io_i[2:0];
			end
			er_run <= 1'b0;
			gfx_rd <= 1'b0;
			cgfx_is_rom <= 1'b0;
			vsd_req <= 1'b0;
			vsrt_req <= 1'b0;
			srt_q <= 1'b0;
			rsd_req <= 1'b0;
		end
		else begin
			snd_data_wr <= 1'b0;
			snd_data_rd <= 1'b0;
			pic_wr <= 1'b0;
			watchdog_kick <= 1'b0;
			nvram_cpu_write <= 1'b0;
			(* full_case, parallel_case *)
			case (state)
				M_IDLE: begin
					mem_ack <= 1'b0;
					if (mem_req && !mem_ack) begin
						a_q <= mem_addr;
						we_q <= mem_we;
						wd_q <= mem_wdata;
						sz_q <= mem_size;
						srt_q <= mem_srt;
						state <= M_ACK;
					end
				end
				M_ACK:
					if (ext_fetch) begin
						mem_ack <= 1'b0;
						gfx_base <= ext_base;
						cgfx_is_rom <= region == R_ROM;
						gfx_cnt <= 3'd0;
						gfx_last <= lastb[5:3];
						gfx_win <= 48'd0;
						gfx_rd <= 1'b1;
						state <= M_GFX;
					end
					else if (is_sdram_ram) begin
						mem_ack <= 1'b0;
						rsd_req <= 1'b1;
						state <= M_RSD;
					end
					else if (is_hwram) begin
						if ((region == R_CMOS) && nvram_ext_active) begin
							mem_ack <= 1'b0;
							state <= M_ACK;
						end
						else begin
							if ((region == R_CMOS) && we_q) begin
								hw_cmos_write_ok <= cmos_we;
								cmos_we <= 1'b0;
							end
							mem_ack <= 1'b0;
							state <= M_HR1;
						end
					end
					else if (is_hwvram) begin
						mem_ack <= 1'b0;
						if (srt_q && !widx[0]) begin
							vsrt_req <= 1'b1;
							state <= M_SRTD;
						end
						else begin
							vsd_req <= 1'b1;
							state <= M_VSD;
						end
					end
					else begin
						win_s = {read_word(region, widx + 28'd2), read_word(region, widx + 28'd1), read_word(region, widx)};
						merged_s = (win_s & ~smask) | (({16'h0000, wd_q} << boff) & smask);
						if (we_q) begin
							(* full_case, parallel_case *)
							case (region)
								default:
									;
							endcase
							if (region == R_CMOSEN)
								cmos_we <= 1'b1;
							if (region == R_CTRL) begin
								control_word <= wd_q[15:0];
								videobank <= wd_q[11];
								gfxbank <= wd_q[9:8];
							end
							if (region == R_SOUND) begin
								snd_data_o <= wd_q[7:0];
								snd_data_wr <= 1'b1;
							end
							if ((region == R_SECURITY) && (widx == WB_SEC)) begin
								pic_wdata <= wd_q[7:0];
								pic_wr <= 1'b1;
							end
							if (region == R_IO) begin
								wrel = widx - WB_IO;
								if (wwf_io_shuffle_active && (wrel[3:0] == 4'd0)) begin
									begin : sv2v_autoblock_5
										reg signed [31:0] io_i;
										for (io_i = 0; io_i < 16; io_i = io_i + 1)
											ioshuffle[io_i] <= io_i[2:0];
									end
									(* full_case, parallel_case *)
									case (wd_q[15:0])
										16'd1: begin
											ioshuffle[4] <= 3'd0;
											ioshuffle[8] <= 3'd1;
											ioshuffle[1] <= 3'd2;
											ioshuffle[9] <= 3'd3;
											ioshuffle[2] <= 3'd4;
										end
										16'd2: begin
											ioshuffle[8] <= 3'd0;
											ioshuffle[2] <= 3'd1;
											ioshuffle[4] <= 3'd2;
											ioshuffle[6] <= 3'd3;
											ioshuffle[1] <= 3'd4;
										end
										16'd3: begin
											ioshuffle[1] <= 3'd0;
											ioshuffle[8] <= 3'd1;
											ioshuffle[2] <= 3'd2;
											ioshuffle[10] <= 3'd3;
											ioshuffle[5] <= 3'd4;
										end
										16'd4: begin
											ioshuffle[2] <= 3'd0;
											ioshuffle[4] <= 3'd1;
											ioshuffle[1] <= 3'd2;
											ioshuffle[7] <= 3'd3;
											ioshuffle[8] <= 3'd4;
										end
										default:
											;
									endcase
								end
								else
									(* full_case, parallel_case *)
									case ((wwf_io_shuffle_active ? ioshuffle[wrel[3:0]] : wrel[2:0]))
										3'd1: begin
											snd_reset <= wd_q[4];
											pic_reset <= wd_q[5];
										end
										3'd3: watchdog_kick <= 1'b1;
										default:
											;
									endcase
							end
							mem_rdata <= 32'h00000000;
							mem_ack <= 1'b1;
							state <= M_IDLE;
						end
						else begin
							if (region == R_SOUND)
								snd_data_rd <= 1'b1;
							win_s_q <= win_s;
							mem_ack <= 1'b0;
							state <= M_RDLY;
						end
					end
				M_GFX:
					if (gfx_rack) begin
						gfx_rd <= 1'b0;
						gfx_win <= gfx_win_with_byte;
						if (gfx_cnt == gfx_last)
							state <= M_GFIN;
						else begin
							gfx_cnt <= gfx_cnt + 3'd1;
							gfx_base <= gfx_base + 26'd1;
						end
					end
					else if (!gfx_rd)
						gfx_rd <= 1'b1;
				M_GFIN: begin
					mem_ack <= 1'b1;
					mem_rdata <= sv2v_cast_32((gfx_win >> boff) & rmask);
					state <= M_IDLE;
				end
				M_HR1: begin
					rd0 <= eng_aq;
					rd1 <= eng_bq;
					state <= M_HR2;
				end
				M_HR2: begin
					rd2 <= eng_aq;
					state <= M_HFIN;
				end
				M_HFIN: state <= M_HFIN2;
				M_HFIN2:
					if (we_q) begin
						if ((lastb >= 6'd32) && hval[2])
							state <= M_HW2;
						else begin
							if (region == R_CMOS) begin
								if (hw_cmos_write_ok)
									nvram_cpu_write <= 1'b1;
								hw_cmos_write_ok <= 1'b0;
							end
							mem_ack <= 1'b1;
							state <= M_IDLE;
						end
					end
					else begin
						mem_rdata <= sv2v_cast_32((hwin_q >> boff_q) & rmask_q);
						mem_ack <= 1'b1;
						state <= M_IDLE;
					end
				M_HW2: begin
					if (region == R_CMOS) begin
						if (hw_cmos_write_ok)
							nvram_cpu_write <= 1'b1;
						hw_cmos_write_ok <= 1'b0;
					end
					mem_ack <= 1'b1;
					state <= M_IDLE;
				end
				M_RDLY: begin
					mem_rdata <= sv2v_cast_32((win_s_q >> boff_q) & rmask_q);
					mem_ack <= 1'b1;
					state <= M_IDLE;
				end
				M_VSD: begin
					vsd_req <= 1'b0;
					if (vsd_done) begin
						mem_rdata <= vsd_rdata;
						mem_ack <= 1'b1;
						state <= M_IDLE;
					end
				end
				M_SRTD: begin
					vsrt_req <= 1'b0;
					if (vsrt_done) begin
						mem_rdata <= (we_q ? 32'h00000000 : srt_rdata_f(vsrt_e0e1[15:0], vsrt_e0e1[31:16]));
						mem_ack <= 1'b1;
						state <= M_IDLE;
					end
				end
				M_RSD: begin
					rsd_req <= 1'b0;
					if (rsd_done) begin
						mem_rdata <= rsd_rdata;
						mem_ack <= 1'b1;
						state <= M_IDLE;
					end
				end
				default: begin
					state <= M_IDLE;
					mem_ack <= 1'b0;
				end
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_dma (
	clk,
	rst,
	reg_we,
	reg_addr,
	reg_wdata,
	reg_rdata,
	reg_ready,
	go_hold,
	src_req,
	src_addr,
	src_active,
	src_stream,
	src_data,
	src_ack,
	fb_we,
	fb_addr,
	fb_wdata,
	fb_ack,
	wr_busy,
	busy,
	blit_irq,
	dma_palette,
	dbg_q_overflow,
	dbg_q_highwater
);
	reg _sv2v_0;
	parameter [0:0] GFX_ROM_LARGE = 1'b1;
	parameter [0:0] TIMED_IRQ_PUMP = 1'b0;
	parameter [0:0] RETIRE_IRQ_FENCE = 1'b1;
	parameter [0:0] DRAIN_QUEUED_ON_STOP = 1'b0;
	parameter integer NORMAL_Q_DEPTH = 256;
	parameter [0:0] WAIT_GO_RETIRED = 1'b0;
	parameter [0:0] REG_WRITE_BACKPRESSURE = 1'b0;
	parameter [0:0] SHARED_SOURCE_LOOKUP = 1'b1;
	parameter [0:0] COMPACT_DIVIDER = 1'b1;
	parameter [0:0] SHARED_WALKER_ARITH = 1'b1;
	parameter [0:0] COMPACT_WALKER = 1'b1;
	parameter [0:0] SHARED_COMMAND_IMAGE = 1'b1;
	input wire clk;
	input wire rst;
	input wire reg_we;
	input wire [3:0] reg_addr;
	input wire [15:0] reg_wdata;
	output wire [15:0] reg_rdata;
	output wire reg_ready;
	input wire go_hold;
	output wire src_req;
	output wire [31:0] src_addr;
	output wire src_active;
	output wire src_stream;
	input wire [7:0] src_data;
	input wire src_ack;
	output reg fb_we;
	localparam signed [31:0] wolf_pkg_FB_ADDR_W = 19;
	output reg [18:0] fb_addr;
	output reg [15:0] fb_wdata;
	input wire fb_ack;
	input wire wr_busy;
	output wire busy;
	output reg blit_irq;
	output wire [15:0] dma_palette;
	output wire dbg_q_overflow;
	output wire [8:0] dbg_q_highwater;
	localparam [1:0] OP_SKIP = 2'd0;
	localparam [1:0] OP_COLOR = 2'd1;
	localparam [1:0] OP_COPY = 2'd2;
	localparam signed [31:0] wolf_pkg_DMA_NREGS = 18;
	reg [15:0] regf [0:17];
	reg busy_r;
	reg cadence_valid_r;
	reg [17:0] cadence_x_reload_r;
	reg [17:0] cadence_x_rem_r;
	reg [17:0] cadence_y_rem_r;
	reg [15:0] cadence_xstep_r;
	reg [15:0] cadence_ystep_r;
	reg [6:0] cadence_phase_r;
	reg halt_pending_r;
	reg walker_halted_r;
	reg paused_r;
	reg kill_pending_r;
	reg [15:0] restart_regf [0:17];
	reg restart_pending_r;
	reg setup_from_restart_r;
	localparam integer NORMAL_Q_PTR_W = $clog2(NORMAL_Q_DEPTH);
	localparam integer NORMAL_Q_CNT_W = $clog2(NORMAL_Q_DEPTH + 1);
	localparam integer NORMAL_Q_WORD_W = 288;
	(* ramstyle = "M10K, no_rw_check" *) reg [NORMAL_Q_WORD_W - 1:0] normal_q_mem [0:NORMAL_Q_DEPTH - 1];
	reg [NORMAL_Q_WORD_W - 1:0] normal_q_push_word;
	reg [NORMAL_Q_WORD_W - 1:0] normal_launch_word;
	reg [NORMAL_Q_WORD_W - 1:0] launch_image_r;
	reg [NORMAL_Q_PTR_W - 1:0] normal_q_wptr;
	reg [NORMAL_Q_PTR_W - 1:0] normal_q_rptr;
	reg [NORMAL_Q_CNT_W - 1:0] normal_q_count;
	(* preserve *) reg normal_q_overflow_r;
	(* preserve *) reg [NORMAL_Q_CNT_W - 1:0] normal_q_highwater_r;
	reg setup_from_normal_q_r;
	wire normal_q_wptr_last = normal_q_wptr == (NORMAL_Q_DEPTH - 1);
	wire normal_q_rptr_last = normal_q_rptr == (NORMAL_Q_DEPTH - 1);
	integer qi;
	localparam [4:0] wolf_pkg_DMA_COMMAND = 5'd1;
	always @(*) begin
		if (_sv2v_0)
			;
		for (qi = 0; qi < wolf_pkg_DMA_NREGS; qi = qi + 1)
			normal_q_push_word[qi * 16+:16] = regf[qi];
		normal_q_push_word[wolf_pkg_DMA_COMMAND * 16+:16] = reg_wdata;
	end
	wire [15:0] cmd_reg = regf[wolf_pkg_DMA_COMMAND];
	localparam [4:0] wolf_pkg_DMA_LRSKIP = 5'd0;
	wire [15:0] r_lrskip = regf[wolf_pkg_DMA_LRSKIP];
	localparam [4:0] wolf_pkg_DMA_OFFSETLO = 5'd2;
	wire [15:0] r_offlo = regf[wolf_pkg_DMA_OFFSETLO];
	localparam [4:0] wolf_pkg_DMA_OFFSETHI = 5'd3;
	wire [15:0] r_offhi = regf[wolf_pkg_DMA_OFFSETHI];
	localparam [4:0] wolf_pkg_DMA_XSTART = 5'd4;
	wire [15:0] r_xstart = regf[wolf_pkg_DMA_XSTART];
	localparam [4:0] wolf_pkg_DMA_YSTART = 5'd5;
	wire [15:0] r_ystart = regf[wolf_pkg_DMA_YSTART];
	localparam [4:0] wolf_pkg_DMA_WIDTH = 5'd6;
	wire [15:0] r_width = regf[wolf_pkg_DMA_WIDTH];
	localparam [4:0] wolf_pkg_DMA_HEIGHT = 5'd7;
	wire [15:0] r_height = regf[wolf_pkg_DMA_HEIGHT];
	localparam [4:0] wolf_pkg_DMA_PALETTE = 5'd8;
	wire [15:0] r_pal = regf[wolf_pkg_DMA_PALETTE];
	localparam [4:0] wolf_pkg_DMA_COLOR = 5'd9;
	wire [15:0] r_color = regf[wolf_pkg_DMA_COLOR];
	localparam [4:0] wolf_pkg_DMA_SCALE_X = 5'd10;
	wire [15:0] r_scalex = regf[wolf_pkg_DMA_SCALE_X];
	localparam [4:0] wolf_pkg_DMA_SCALE_Y = 5'd11;
	wire [15:0] r_scaley = regf[wolf_pkg_DMA_SCALE_Y];
	localparam [4:0] wolf_pkg_DMA_TOPCLIP = 5'd12;
	wire [15:0] r_top = regf[wolf_pkg_DMA_TOPCLIP];
	localparam [4:0] wolf_pkg_DMA_BOTCLIP = 5'd13;
	wire [15:0] r_bot = regf[wolf_pkg_DMA_BOTCLIP];
	localparam [4:0] wolf_pkg_DMA_LEFTCLIP = 5'd16;
	wire [15:0] r_left = regf[wolf_pkg_DMA_LEFTCLIP];
	localparam [4:0] wolf_pkg_DMA_RIGHTCLIP = 5'd17;
	wire [15:0] r_right = regf[wolf_pkg_DMA_RIGHTCLIP];
	localparam [4:0] wolf_pkg_DMA_CONFIG = 5'd15;
	wire [15:0] r_config = regf[wolf_pkg_DMA_CONFIG];
	wire cfg_bank = r_config[5];
	function automatic [4:0] wolf_pkg_dma_regmap;
		input reg bank;
		input reg [3:0] off;
		case (off)
			4'd12: wolf_pkg_dma_regmap = (bank ? wolf_pkg_DMA_TOPCLIP : wolf_pkg_DMA_LEFTCLIP);
			4'd13: wolf_pkg_dma_regmap = (bank ? wolf_pkg_DMA_BOTCLIP : wolf_pkg_DMA_RIGHTCLIP);
			default: wolf_pkg_dma_regmap = {1'b0, off};
		endcase
	endfunction
	wire [4:0] regnum_w = wolf_pkg_dma_regmap(cfg_bank, reg_addr);
	localparam signed [31:0] wolf_pkg_DMA_CMD_TRIG_BIT = 15;
	wire wdata_trig = reg_wdata[wolf_pkg_DMA_CMD_TRIG_BIT];
	wire reg_write_accepted_w = reg_we && (!REG_WRITE_BACKPRESSURE || reg_ready);
	wire command_w = reg_write_accepted_w && (regnum_w == wolf_pkg_DMA_COMMAND);
	wire offered_go_w = (reg_we && (regnum_w == wolf_pkg_DMA_COMMAND)) && wdata_trig;
	wire trig_w = command_w && wdata_trig;
	reg timeout_stop_armed_r;
	reg [5:0] timeout_stop_age_r;
	wire stop_w_raw = (reg_we && (regnum_w == wolf_pkg_DMA_COMMAND)) && !wdata_trig;
	wire timeout_stop_context_w = (DRAIN_QUEUED_ON_STOP && busy_r) && ((normal_q_count != 0) || cadence_valid_r);
	wire timeout_pair_resume_w = stop_w_raw && timeout_stop_armed_r;
	wire queued_stop_defer_w = timeout_pair_resume_w;
	wire stop_w = stop_w_raw && !timeout_pair_resume_w;
	wire resume_context_w = (busy_r && !kill_pending_r) && ((paused_r || halt_pending_r) || walker_halted_r);
	wire resume_go_w = (resume_context_w ? offered_go_w : trig_w);
	wire resume_w = resume_go_w || timeout_pair_resume_w;
	wire [15:0] cadence_xstep_w = (r_scalex != 16'h0000 ? r_scalex : 16'h0100);
	wire [15:0] cadence_ystep_w = (r_scaley != 16'h0000 ? r_scaley : 16'h0100);
	wire [17:0] cadence_width_fp_w = {r_width[9:0], 8'h00};
	wire [17:0] cadence_height_fp_w = {r_height[9:0], 8'h00};
	wire cadence_nonzero_w = (cadence_width_fp_w >= {2'b00, cadence_xstep_w}) && (cadence_height_fp_w >= {2'b00, cadence_ystep_w});
	wire cadence_start_w = (TIMED_IRQ_PUMP && trig_w) && (cadence_nonzero_w || RETIRE_IRQ_FENCE);
	wire [17:0] cadence_x_init_w = (cadence_width_fp_w - {2'b00, cadence_xstep_w}) + 18'd1;
	wire [17:0] cadence_y_init_w = (cadence_height_fp_w - {2'b00, cadence_ystep_w}) + 18'd1;
	wire cadence_immediate_w = (TIMED_IRQ_PUMP && trig_w) && !cadence_nonzero_w;
	wire [7:0] cadence_phase_next_w = {1'b0, cadence_phase_r} + 8'd32;
	wire cadence_pixel_tick_w = cadence_phase_next_w >= 8'd105;
	wire cadence_time_elapsed_w = (((TIMED_IRQ_PUMP && cadence_valid_r) && cadence_pixel_tick_w) && (cadence_x_rem_r <= {2'b00, cadence_xstep_r})) && (cadence_y_rem_r <= {2'b00, cadence_ystep_r});
	assign busy = busy_r;
	assign dma_palette = r_pal;
	assign dbg_q_overflow = normal_q_overflow_r;
	assign dbg_q_highwater = normal_q_highwater_r;
	wire [3:0] eff_raddr = (reg_addr == 4'd0 ? 4'd1 : reg_addr);
	wire [14:0] cmd_lo15 = cmd_reg[14:0];
	assign reg_rdata = regf[{1'b0, eff_raddr}];
	reg [4:0] state;
	reg [4:0] state_n;
	localparam signed [31:0] FBQ_DEPTH = 4;
	reg [18:0] fbq_addr [0:3];
	reg [15:0] fbq_data [0:3];
	reg [1:0] fbq_wptr_r;
	reg [1:0] fbq_rptr_r;
	reg [2:0] fbq_count_r;
	reg fb_writer_active_r;
	wire fbq_empty_w = fbq_count_r == 3'd0;
	wire fbq_full_w = fbq_count_r == 3'd4;
	wire fb_writer_idle_w = !fb_writer_active_r && !fb_we;
	wire local_writes_drained_w = fbq_empty_w && fb_writer_idle_w;
	wire source_wait_w = src_req;
	wire walker_boundary_w = !source_wait_w || src_ack;
	wire first_stop_w = ((((stop_w && busy_r) && !paused_r) && !halt_pending_r) && !walker_halted_r) && !kill_pending_r;
	wire second_stop_w = (stop_w && busy_r) && (((paused_r || halt_pending_r) || walker_halted_r) || kill_pending_r);
	wire halt_request_w = halt_pending_r || first_stop_w;
	wire kill_request_w = kill_pending_r || second_stop_w;
	wire stop_boundary_enter_w = (((!resume_w && !walker_halted_r) && !paused_r) && (halt_request_w || kill_request_w)) && walker_boundary_w;
	wire stop_source_advance_w = (stop_boundary_enter_w && source_wait_w) && src_ack;
	wire walker_kill_safe_w = (walker_halted_r || paused_r) || walker_boundary_w;
	wire kill_enter_w = ((!resume_w && kill_request_w) && walker_kill_safe_w) && !fb_writer_active_r;
	wire pause_enter_w = (((!resume_go_w && !kill_request_w) && !paused_r) && (walker_halted_r || stop_boundary_enter_w)) && local_writes_drained_w;
	wire fsm_step_w = (!paused_r && !walker_halted_r) && (resume_w || ((!(halt_request_w || kill_request_w) || source_wait_w) && ((!kill_request_w || fb_writer_active_r) || (source_wait_w && !src_ack))));
	wire nosrc_step_w = (!paused_r && !walker_halted_r) && (resume_w || !(halt_request_w || kill_request_w));
	wire srcstate_step_w = (!paused_r && !walker_halted_r) && (((resume_w || !kill_request_w) || fb_writer_active_r) || !src_ack);
	wire normal_q_idle_clear_w = (!busy_r && (state == 5'd0)) && (kill_pending_r || (!resume_w && ((paused_r || !local_writes_drained_w) || (!walker_halted_r && !halt_pending_r))));
	wire normal_q_clear_w = kill_enter_w || normal_q_idle_clear_w;
	reg [3:0] straddle_limit_c;
	reg [3:0] bpp_c;
	reg [1:0] zero_c;
	reg [1:0] nz_c;
	reg need_px_c;
	reg xflip_c;
	reg yflip_c;
	reg skip_c;
	reg scale_c;
	reg [1:0] preskip_c;
	reg [1:0] postskip_c;
	reg [15:0] xstep_c;
	reg [15:0] ystep_c;
	reg [9:0] width_c;
	reg [9:0] xpos_c;
	reg [9:0] height_c;
	reg [15:0] pal16_c;
	reg [15:0] color16_c;
	reg [8:0] topclip_c;
	reg [8:0] botclip_c;
	reg [9:0] leftclip_c;
	reg [9:0] rightclip_c;
	reg signed [31:0] startskip_c;
	reg signed [31:0] endskip_c;
	reg [31:0] offset_r;
	reg [31:0] o_r;
	localparam integer CURSOR_W = (COMPACT_WALKER ? 20 : 32);
	localparam integer WIDTH_FP_W = (COMPACT_WALKER ? 25 : 32);
	reg signed [CURSOR_W - 1:0] ix;
	reg signed [CURSOR_W - 1:0] iy;
	reg signed [WIDTH_FP_W - 1:0] width_fp;
	reg [9:0] sx;
	reg [8:0] sy;
	reg signed [31:0] pre_r;
	reg signed [31:0] post_r;
	reg [7:0] b0_r;
	reg [7:0] b1_r;
	reg [31:0] bc_prev0;
	reg [31:0] bc_prev1;
	reg [31:0] bc_a0;
	reg [31:0] bc_a1;
	reg [7:0] bc_d0;
	reg [7:0] bc_d1;
	reg bc_v0;
	reg bc_v1;
	reg [7:0] skipval_r;
	reg [7:0] px_r;
	localparam integer SA_COUNT_W = (COMPACT_WALKER ? 8 : 32);
	reg [SA_COUNT_W - 1:0] sa_cnt;
	reg [31:0] fast_src_prefetch_addr_r;
	reg fast_src_prefetch_ready_r;
	reg fast_src_carry_r;
	reg [31:0] src_state_addr_r;
	reg src_early_valid_r;
	reg [4:0] state_q1;
	reg drun;
	reg [5:0] dcnt;
	localparam integer QUOT_W = (COMPACT_WALKER ? 16 : 32);
	reg [QUOT_W - 1:0] dquo;
	wire [18:0] dquo_mul_w = dquo;
	reg [31:0] dnum;
	reg [31:0] dden;
	localparam integer DIV_REM_W = (COMPACT_DIVIDER ? 16 : 32);
	reg [DIV_REM_W - 1:0] drem;
	wire [DIV_REM_W:0] drem_trial_w = {drem, dnum[31]};
	reg [QUOT_W - 1:0] txm_r;
	wire [31:0] txm_u32_w = txm_r;
	reg clip_gap;
	reg [13:0] rowbits_r;
	reg [8:0] tyr_r;
	reg [10:0] w2p_r;
	reg [10:0] w3p_r;
	reg [31:0] radv_r;
	reg [31:0] w2adv_r;
	reg [31:0] w3adv_r;
	wire [15:0] s_cmd = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_COMMAND * 16+:16] : cmd_reg) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_COMMAND * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_COMMAND] : cmd_reg)));
	wire [15:0] s_lrskip = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_LRSKIP * 16+:16] : r_lrskip) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_LRSKIP * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_LRSKIP] : r_lrskip)));
	wire [15:0] s_offlo = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_OFFSETLO * 16+:16] : r_offlo) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_OFFSETLO * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_OFFSETLO] : r_offlo)));
	wire [15:0] s_offhi = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_OFFSETHI * 16+:16] : r_offhi) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_OFFSETHI * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_OFFSETHI] : r_offhi)));
	wire [15:0] s_xstart = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_XSTART * 16+:16] : r_xstart) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_XSTART * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_XSTART] : r_xstart)));
	wire [15:0] s_ystart = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_YSTART * 16+:16] : r_ystart) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_YSTART * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_YSTART] : r_ystart)));
	wire [15:0] s_width = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_WIDTH * 16+:16] : r_width) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_WIDTH * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_WIDTH] : r_width)));
	wire [15:0] s_height = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_HEIGHT * 16+:16] : r_height) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_HEIGHT * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_HEIGHT] : r_height)));
	wire [15:0] s_pal = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_PALETTE * 16+:16] : r_pal) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_PALETTE * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_PALETTE] : r_pal)));
	wire [15:0] s_color = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_COLOR * 16+:16] : r_color) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_COLOR * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_COLOR] : r_color)));
	wire [15:0] s_scalex = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_SCALE_X * 16+:16] : r_scalex) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_SCALE_X * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_SCALE_X] : r_scalex)));
	wire [15:0] s_scaley = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_SCALE_Y * 16+:16] : r_scaley) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_SCALE_Y * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_SCALE_Y] : r_scaley)));
	wire [15:0] s_top = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_TOPCLIP * 16+:16] : r_top) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_TOPCLIP * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_TOPCLIP] : r_top)));
	wire [15:0] s_bot = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_BOTCLIP * 16+:16] : r_bot) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_BOTCLIP * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_BOTCLIP] : r_bot)));
	wire [15:0] s_left = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_LEFTCLIP * 16+:16] : r_left) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_LEFTCLIP * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_LEFTCLIP] : r_left)));
	wire [15:0] s_right = (SHARED_COMMAND_IMAGE ? (setup_from_normal_q_r || setup_from_restart_r ? launch_image_r[wolf_pkg_DMA_RIGHTCLIP * 16+:16] : r_right) : (setup_from_normal_q_r ? normal_launch_word[wolf_pkg_DMA_RIGHTCLIP * 16+:16] : (setup_from_restart_r ? restart_regf[wolf_pkg_DMA_RIGHTCLIP] : r_right)));
	wire [3:0] mode_w = s_cmd[3:0];
	wire xflip_w = s_cmd[4];
	wire yflip_w = s_cmd[5];
	wire lrsplit_w = s_cmd[6];
	wire skip_w = s_cmd[7];
	wire [1:0] preskip_w = s_cmd[9:8];
	wire [1:0] postskip_w = s_cmd[11:10];
	function automatic [3:0] wolf_pkg_dma_bpp;
		input reg [15:0] command;
		reg [2:0] b;
		begin
			b = command[14:12];
			wolf_pkg_dma_bpp = (b == 3'd0 ? 4'd8 : {1'b0, b});
		end
	endfunction
	wire [3:0] bpp_w = wolf_pkg_dma_bpp(s_cmd);
	wire [15:0] xstep_w = (s_scalex == 16'd0 ? 16'h0100 : s_scalex);
	wire [15:0] ystep_w = (s_scaley == 16'd0 ? 16'h0100 : s_scaley);
	wire scale_w = (xstep_w != 16'h0100) || (ystep_w != 16'h0100);
	reg [1:0] zero_w;
	reg [1:0] nz_w;
	always @(*) begin
		if (_sv2v_0)
			;
		case (mode_w)
			4'h1: begin
				zero_w = OP_COPY;
				nz_w = OP_SKIP;
			end
			4'h2: begin
				zero_w = OP_SKIP;
				nz_w = OP_COPY;
			end
			4'h3: begin
				zero_w = OP_COPY;
				nz_w = OP_COPY;
			end
			4'h4, 4'h5: begin
				zero_w = OP_COLOR;
				nz_w = OP_SKIP;
			end
			4'h6, 4'h7: begin
				zero_w = OP_COLOR;
				nz_w = OP_COPY;
			end
			4'h8, 4'ha: begin
				zero_w = OP_SKIP;
				nz_w = OP_COLOR;
			end
			4'h9, 4'hb: begin
				zero_w = OP_COPY;
				nz_w = OP_COLOR;
			end
			4'hc, 4'hd, 4'he, 4'hf: begin
				zero_w = OP_COLOR;
				nz_w = OP_COLOR;
			end
			default: begin
				zero_w = OP_SKIP;
				nz_w = OP_SKIP;
			end
		endcase
	end
	wire draw_none_w = mode_w == 4'h0;
	wire need_px_w = (zero_w != nz_w) || (zero_w == OP_COPY);
	wire [31:0] gfxoff0 = (mode_w == 4'hc ? 32'd0 : {s_offhi, s_offlo});
	wire [31:0] gfxoff1 = ((GFX_ROM_LARGE == 1'b0) && (gfxoff0 >= 32'h02000000) ? gfxoff0 - 32'h02000000 : gfxoff0);
	wire [31:0] gfxoff2 = (gfxoff1 >= 32'hf8000000 ? gfxoff1 - 32'hf8000000 : gfxoff1);
	wire skipdma_w = gfxoff2 >= 32'h10000000;
	wire [31:0] startskip_w = (lrsplit_w ? {24'd0, s_lrskip[7:0]} : 32'd0);
	wire [31:0] endskip_w = (lrsplit_w ? {24'd0, s_lrskip[15:8]} : {16'd0, s_lrskip});
	wire [9:0] w_width10 = s_width[9:0];
	(* multstyle = "logic" *) wire [13:0] rowbits_setup_w;
	assign rowbits_setup_w = w_width10 * bpp_w;
	wire [9:0] w_height10 = s_height[9:0];
	wire [9:0] w_xpos10 = s_xstart[9:0];
	wire [8:0] w_ypos9 = s_ystart[8:0];
	wire [7:0] w_color8 = s_color[7:0];
	wire [8:0] w_top9 = s_top[8:0];
	wire [8:0] w_bot9 = s_bot[8:0];
	wire [9:0] w_left10 = s_left[9:0];
	wire [9:0] w_right10 = s_right[9:0];
	wire [31:0] xstep32 = {16'd0, xstep_c};
	wire signed [31:0] xstep_s = $signed({16'd0, xstep_c});
	wire [31:0] bpp32 = {28'd0, bpp_c};
	wire [31:0] width32 = {22'd0, width_c};
	wire signed [31:0] height_fp = $signed({22'd0, height_c}) <<< 8;
	wire [31:0] o_byte0 = {3'b000, o_r[31:3]};
	wire [31:0] o_byte1 = o_byte0 + 32'd1;
	wire [2:0] o_lo3 = o_r[2:0];
	wire [7:0] b1_eff = (((state == 5'd16) || (state == 5'd5)) || (state == 5'd23) ? src_data : b1_r);
	wire [15:0] win_now = {b1_eff, b0_r};
	wire [15:0] win_sh = win_now >> o_lo3;
	wire [7:0] byte_now = win_sh[7:0];
	wire [8:0] maskfull = (9'd1 << bpp_c) - 9'd1;
	wire px_straddle = {1'b0, o_lo3} > straddle_limit_c;
	reg [31:0] scaled_lookup_o_r;
	wire [8:0] sc_fraction_sum_w = {1'b0, ix[7:0]} + {1'b0, xstep_c[7:0]};
	reg [11:0] sc_step_ceil_r;
	reg [11:0] sc_step_floor_r;
	wire [11:0] sc_step_bits_w = (sc_fraction_sum_w[8] ? sc_step_ceil_r : sc_step_floor_r);
	wire [31:0] sc_next_o_w = o_r + {20'd0, sc_step_bits_w};
	always @(posedge clk)
		if (rst)
			scaled_lookup_o_r <= 32'd0;
		else
			scaled_lookup_o_r <= sc_next_o_w;
	wire [31:0] ns_next_o_w = o_r + bpp32;
	wire [31:0] lookup_o_w = (scale_c ? scaled_lookup_o_r : ns_next_o_w);
	wire [31:0] lookup_byte0_w = {3'b000, lookup_o_w[31:3]};
	wire [31:0] lookup_byte1_w = lookup_byte0_w + 32'd1;
	(* keep = "true" *) wire [3:0] lookup_cache0_equal_byte_w;
	(* keep = "true" *) wire [3:0] lookup_cache1_equal_byte_w;
	genvar _gv_lookup_cache_chunk_1;
	generate
		for (_gv_lookup_cache_chunk_1 = 0; _gv_lookup_cache_chunk_1 < 4; _gv_lookup_cache_chunk_1 = _gv_lookup_cache_chunk_1 + 1) begin : lookup_cache_equal_bytes
			localparam lookup_cache_chunk = _gv_lookup_cache_chunk_1;
			assign lookup_cache0_equal_byte_w[lookup_cache_chunk] = bc_a0[8 * lookup_cache_chunk+:8] == lookup_byte0_w[8 * lookup_cache_chunk+:8];
			assign lookup_cache1_equal_byte_w[lookup_cache_chunk] = bc_a1[8 * lookup_cache_chunk+:8] == lookup_byte0_w[8 * lookup_cache_chunk+:8];
		end
	endgenerate
	wire lookup_hit0_w = (bc_v0 && &lookup_cache0_equal_byte_w) || (bc_v1 && &lookup_cache1_equal_byte_w);
	(* keep = "true" *) wire [3:0] lookup_prev0_equal_byte_w;
	(* keep = "true" *) wire [3:0] lookup_prev1_equal_byte_w;
	genvar _gv_lookup_chunk_1;
	generate
		for (_gv_lookup_chunk_1 = 0; _gv_lookup_chunk_1 < 4; _gv_lookup_chunk_1 = _gv_lookup_chunk_1 + 1) begin : lookup_equal_bytes
			localparam lookup_chunk = _gv_lookup_chunk_1;
			assign lookup_prev0_equal_byte_w[lookup_chunk] = bc_prev0[8 * lookup_chunk+:8] == lookup_byte0_w[8 * lookup_chunk+:8];
			assign lookup_prev1_equal_byte_w[lookup_chunk] = bc_prev1[8 * lookup_chunk+:8] == lookup_byte0_w[8 * lookup_chunk+:8];
		end
	endgenerate
	wire lookup_hit1_w = (bc_v0 && &lookup_prev0_equal_byte_w) || (bc_v1 && &lookup_prev1_equal_byte_w);
	wire lookup_straddle_w = {1'b0, lookup_o_w[2:0]} > straddle_limit_c;
	wire [31:0] lookup_req_addr_w = ((lookup_hit0_w && lookup_straddle_w) && !lookup_hit1_w ? lookup_byte1_w : lookup_byte0_w);
	wire hit0 = (bc_v0 && (bc_a0 == o_byte0)) || (bc_v1 && (bc_a1 == o_byte0));
	wire hit1 = (bc_v0 && (bc_prev0 == o_byte0)) || (bc_v1 && (bc_prev1 == o_byte0));
	wire [7:0] hitd0 = (bc_v0 && (bc_a0 == o_byte0) ? bc_d0 : bc_d1);
	wire [7:0] hitd1 = (bc_v0 && (bc_prev0 == o_byte0) ? bc_d0 : bc_d1);
	wire need_f0 = !hit0;
	wire need_f1 = px_straddle && !hit1;
	wire [31:0] cur_req_addr_w = (!need_f0 && need_f1 ? o_byte1 : o_byte0);
	wire [31:0] ns_next_byte0_w = {3'b000, ns_next_o_w[31:3]};
	wire [31:0] ns_next_byte1_w = ns_next_byte0_w + 32'd1;
	wire ns_next_straddle_w = {1'b0, ns_next_o_w[2:0]} > straddle_limit_c;
	wire ns_next_hit0_w = (bc_v0 && (bc_a0 == ns_next_byte0_w)) || (bc_v1 && (bc_a1 == ns_next_byte0_w));
	wire ns_next_hit1_w = (bc_v0 && (bc_a0 == ns_next_byte1_w)) || (bc_v1 && (bc_a1 == ns_next_byte1_w));
	wire ns_next_need0_w = !ns_next_hit0_w;
	wire ns_next_need1_w = ns_next_straddle_w && !ns_next_hit1_w;
	wire [31:0] ns_next_req_addr_w = (!ns_next_need0_w && ns_next_need1_w ? ns_next_byte1_w : ns_next_byte0_w);
	wire [7:0] pixmask = maskfull[7:0];
	wire [15:0] win_cache = {hitd1, hitd0};
	wire [7:0] px_cache = (win_cache >> o_lo3) & {8'd0, pixmask};
	wire [7:0] px_now = byte_now & pixmask;
	wire [4:0] presh_w = {3'd0, preskip_c} + 5'd8;
	wire [4:0] postsh_w = {3'd0, postskip_c} + 5'd8;
	wire [31:0] pre_fp_w = {28'd0, skipval_r[3:0]} << presh_w;
	wire [31:0] post_fp_w = {28'd0, skipval_r[7:4]} << postsh_w;
	wire [9:0] tx_skip10 = dquo[9:0];
	wire y_clip_w = (sy < topclip_c) || (sy > botclip_c);
	wire signed [31:0] ss_fp = startskip_c <<< 8;
	wire [31:0] ss_diff_w = $unsigned(ss_fp - ix);
	wire entering_skdiv = (state == 5'd6) && (state_q1 != 5'd6);
	wire entering_rpdiv = (state == 5'd10) && (state_q1 != 5'd10);
	wire xstep_unity_w = xstep_c == 16'h0100;
	wire fast_skdiv_w = entering_skdiv && xstep_unity_w;
	wire fast_rpdiv_w = entering_rpdiv && xstep_unity_w;
	wire div_go = (entering_skdiv | entering_rpdiv) && !xstep_unity_w;
	wire [31:0] div_num = (entering_skdiv ? pre_fp_w : ss_diff_w);
	wire [31:0] div_den = xstep32;
	wire div_busy = drun | div_go;
	wire signed [31:0] we_lim = $signed(width32) - endskip_c;
	wire pix_remain = ix < width_fp;
	wire in_clip = (sx >= leftclip_c) && (sx <= rightclip_c);
	wire [31:0] ix_u = $unsigned(ix);
	wire [16:0] dx_fp_sum_w = {9'd0, ix[7:0]} + {1'b0, xstep_c};
	wire [31:0] dx_w = (SHARED_WALKER_ARITH ? {23'd0, dx_fp_sum_w[16:8]} : ((ix_u + xstep32) >> 8) - (ix_u >> 8));
	wire [11:0] sc_step_base_w = xstep_c[15:8] * bpp_c;
	always @(posedge clk)
		if (rst) begin
			sc_step_floor_r <= 0;
			sc_step_ceil_r <= 0;
		end
		else begin
			sc_step_floor_r <= sc_step_base_w;
			sc_step_ceil_r <= sc_step_base_w + {8'd0, bpp_c};
		end
	wire [31:0] sc_next_byte0_w = {3'b000, sc_next_o_w[31:3]};
	wire [31:0] sc_next_byte1_w = sc_next_byte0_w + 32'd1;
	wire sc_next_straddle_w = {1'b0, sc_next_o_w[2:0]} > straddle_limit_c;
	wire sc_next_hit0_w = (bc_v0 && (bc_a0 == sc_next_byte0_w)) || (bc_v1 && (bc_a1 == sc_next_byte0_w));
	wire sc_next_hit1_w = (bc_v0 && (bc_a0 == sc_next_byte1_w)) || (bc_v1 && (bc_a1 == sc_next_byte1_w));
	wire sc_next_need0_w = !sc_next_hit0_w;
	wire sc_next_need1_w = sc_next_straddle_w && !sc_next_hit1_w;
	wire [31:0] sc_next_req_addr_w = (!sc_next_need0_w && sc_next_need1_w ? sc_next_byte1_w : sc_next_byte0_w);
	wire signed [31:0] ix_next_unity_w = ix + 32'sd256;
	wire [9:0] sx_next_unity_w = (xflip_c ? sx - 10'd1 : sx + 10'd1);
	wire next_unity_in_clip_w = (sx_next_unity_w >= leftclip_c) && (sx_next_unity_w <= rightclip_c);
	wire [31:0] o_next_bpp8_w = o_r + 32'd8;
	wire [31:0] o_next_byte0_w = {3'b000, o_next_bpp8_w[31:3]};
	wire [31:0] o_next_byte1_w = o_next_byte0_w + 32'd1;
	wire fast_src_prefetch_w = ((state == 5'd17) && !fbq_full_w) && fast_src_prefetch_ready_r;
	wire [31:0] fast_src_prefetch_addr_w = fast_src_prefetch_addr_r;
	wire pix_src_demand_w = ((((state == 5'd14) && pix_remain) && in_clip) && need_px_c) && (need_f0 || need_f1);
	wire [1:0] op_eff_w = (zero_c == nz_c ? zero_c : (px_r != 8'd0 ? nz_c : zero_c));
	wire do_write_w = op_eff_w != OP_SKIP;
	wire [15:0] pix_data_w = (op_eff_w == OP_COLOR ? color16_c : {8'd0, px_r} | pal16_c);
	localparam signed [31:0] wolf_pkg_FB_ROWSHIFT = 9;
	wire [18:0] fb_addr_w = ({{10 {1'b0}}, sy} << wolf_pkg_FB_ROWSHIFT) + {{9 {1'b0}}, sx};
	wire fbq_push_w = ((fsm_step_w && (state == 5'd17)) && do_write_w) && !fbq_full_w;
	wire fbq_discard_w = kill_request_w;
	wire fbq_pop_w = (!fb_writer_active_r && !fbq_empty_w) && !kill_request_w;
	wire fbq_backpressure_w = ((state == 5'd17) && do_write_w) && fbq_full_w;
	wire dma_done_ready_w = local_writes_drained_w && !wr_busy;
	wire blit_retire_w = ((state == 5'd27) && dma_done_ready_w) && nosrc_step_w;
	wire normal_pop_w = ((blit_retire_w && !trig_w) && !restart_pending_r) && (normal_q_count != 0);
	wire final_done_w = ((blit_retire_w && !trig_w) && !restart_pending_r) && (normal_q_count == 0);
	wire cadence_complete_w = cadence_time_elapsed_w && ((!RETIRE_IRQ_FENCE || !busy_r) || final_done_w);
	wire normal_push_context_w = (((busy_r && !kill_pending_r) && !paused_r) && !walker_halted_r) && !halt_pending_r;
	wire proposed_go_w = (regnum_w == wolf_pkg_DMA_COMMAND) && wdata_trig;
	wire publication_blocks_go = (go_hold === 1'b1) && !((busy_r && !kill_pending_r) && ((paused_r || walker_halted_r) || halt_pending_r));
	assign reg_ready = !proposed_go_w || ((!publication_blocks_go && (!normal_push_context_w || (!WAIT_GO_RETIRED && (normal_q_count < NORMAL_Q_DEPTH)))) && !(kill_pending_r && restart_pending_r));
	wire normal_push_eligible_w = trig_w && normal_push_context_w;
	wire normal_push_w = normal_push_eligible_w && (normal_q_count < NORMAL_Q_DEPTH);
	wire normal_overflow_w = normal_push_eligible_w && (normal_q_count == NORMAL_Q_DEPTH);
	wire [31:0] iy_u = $unsigned(iy);
	wire [16:0] ty_fp_sum_w = {9'd0, iy[7:0]} + {1'b0, ystep_c};
	wire [31:0] ty_w = (SHARED_WALKER_ARITH ? {23'd0, ty_fp_sum_w[16:8]} : ((iy_u + {16'd0, ystep_c}) >> 8) - (iy_u >> 8));
	wire signed [31:0] w2_ns = $signed(width32) - ((pre_r + post_r) >>> 8);
	wire [31:0] pre2_w = {28'd0, skipval_r[3:0]} << preskip_c;
	wire [31:0] post2_w = {28'd0, skipval_r[7:4]} << postskip_c;
	wire signed [31:0] w3_ns = ($signed(width32) - $signed(pre2_w)) - $signed(post2_w);
	(* multstyle = "logic" *) wire [QUOT_W - 5:0] rp_skip_bits_w = txm_r[QUOT_W - 1:8] * bpp_c;
	reg [31:0] walker_o_delta_w;
	always @(*) begin
		if (_sv2v_0)
			;
		case (state)
			5'd8: walker_o_delta_w = 32'd8;
			5'd12: walker_o_delta_w = rp_skip_bits_w;
			5'd20: walker_o_delta_w = 32'd8 + w2adv_r;
			5'd26: walker_o_delta_w = 32'd8 + w3adv_r;
			default: walker_o_delta_w = (scale_c ? {20'd0, sc_step_bits_w} : bpp32);
		endcase
	end
	wire [31:0] walker_o_sum_w = (state == 5'd20 ? offset_r : o_r) + walker_o_delta_w;
	wire [31:0] walker_offset_delta_w = (scale_c ? radv_r : (skip_c ? 32'd8 + w2adv_r : {18'd0, rowbits_r}));
	wire [31:0] walker_offset_sum_w = offset_r + walker_offset_delta_w;
	wire [31:0] walker_ix_delta_w = ((state == 5'd8) || (state == 5'd12) ? txm_r : (scale_c ? {16'd0, xstep_c} : 32'd256));
	wire signed [31:0] walker_ix_sum_w = ix + $signed(walker_ix_delta_w);
	wire signed [31:0] walker_iy_sum_w = iy + $signed((scale_c ? {16'd0, ystep_c} : 32'd256));
	wire [9:0] walker_sx_delta_w = (state == 5'd8 ? tx_skip10 : 10'd1);
	wire [9:0] walker_sx_sum_w = (sx + (walker_sx_delta_w ^ {10 {xflip_c}})) + {9'd0, xflip_c};
	always @(*) begin
		if (_sv2v_0)
			;
		state_n = state;
		case (state)
			5'd0:
				if (trig_w)
					state_n = 5'd1;
			5'd1: state_n = 5'd2;
			5'd2:
				if (skipdma_w || draw_none_w)
					state_n = 5'd27;
				else
					state_n = 5'd3;
			5'd3:
				if (iy < height_fp) begin
					if (skip_c)
						state_n = 5'd4;
					else
						state_n = 5'd9;
				end
				else
					state_n = 5'd27;
			5'd4:
				if (src_ack)
					state_n = 5'd5;
			5'd5:
				if (src_ack)
					state_n = 5'd6;
			5'd6:
				if (xstep_unity_w)
					state_n = 5'd8;
				else if (!div_busy)
					state_n = 5'd7;
			5'd7: state_n = 5'd8;
			5'd8: state_n = 5'd9;
			5'd9:
				if (y_clip_w)
					state_n = 5'd18;
				else if (ix < ss_fp)
					state_n = 5'd10;
				else
					state_n = 5'd14;
			5'd10:
				if (xstep_unity_w)
					state_n = 5'd12;
				else if (!div_busy)
					state_n = 5'd11;
			5'd11: state_n = 5'd12;
			5'd12: state_n = 5'd13;
			5'd13: state_n = 5'd14;
			5'd14:
				if (!pix_remain)
					state_n = 5'd18;
				else if (!in_clip)
					state_n = 5'd14;
				else if ((need_px_c && need_f0) && src_ack) begin
					if (need_f1)
						state_n = 5'd16;
					else
						state_n = 5'd17;
				end
				else if ((need_px_c && need_f1) && src_ack)
					state_n = 5'd17;
				else if (need_px_c && need_f0)
					state_n = 5'd15;
				else if (need_px_c && need_f1)
					state_n = 5'd16;
				else
					state_n = 5'd17;
			5'd15:
				if (src_ack) begin
					if (need_f1)
						state_n = 5'd16;
					else
						state_n = 5'd17;
				end
			5'd16:
				if (src_ack)
					state_n = 5'd17;
			5'd17:
				if (do_write_w && fbq_full_w)
					state_n = 5'd17;
				else
					state_n = 5'd14;
			5'd18: state_n = 5'd19;
			5'd19: state_n = 5'd20;
			5'd20:
				if ((scale_c && skip_c) && (tyr_r != 9'd0))
					state_n = 5'd21;
				else
					state_n = 5'd3;
			5'd21:
				if (sa_cnt == 32'd0)
					state_n = 5'd3;
				else
					state_n = 5'd22;
			5'd22:
				if (src_ack)
					state_n = 5'd23;
			5'd23:
				if (src_ack)
					state_n = 5'd24;
			5'd24: state_n = 5'd25;
			5'd25: state_n = 5'd26;
			5'd26: state_n = 5'd21;
			5'd27:
				if (!dma_done_ready_w)
					state_n = 5'd27;
				else if (trig_w)
					state_n = 5'd27;
				else if ((trig_w || restart_pending_r) || (normal_q_count != 0))
					state_n = 5'd1;
				else
					state_n = 5'd0;
			default: state_n = 5'd0;
		endcase
	end
	assign src_req = (!paused_r && !walker_halted_r) && (((((((fast_src_prefetch_w || (((fast_src_carry_r || src_early_valid_r) && (state == 5'd14)) && pix_src_demand_w)) || (state == 5'd4)) || (state == 5'd5)) || (state == 5'd15)) || (state == 5'd16)) || (state == 5'd22)) || (state == 5'd23));
	assign src_addr = (fast_src_prefetch_w ? fast_src_prefetch_addr_w : (fast_src_carry_r ? fast_src_prefetch_addr_w : src_state_addr_r));
	assign src_active = (busy_r && need_px_c) && !scale_c;
	assign src_stream = src_active && (bpp_c == 4'd8);
	wire sw_final_done_w = final_done_w && !(TIMED_IRQ_PUMP && cadence_valid_r);
	wire done_clear_w = sw_final_done_w || cadence_complete_w;
	wire cadence_retire_uncommanded_w = ((((((((state == 5'd27) && local_writes_drained_w) && !wr_busy) && !paused_r) && !walker_halted_r) && !halt_pending_r) && !kill_pending_r) && !restart_pending_r) && (normal_q_count == 0);
	wire cadence_y_end_uncommanded_w = (cadence_retire_uncommanded_w && !cadence_valid_r) || (cadence_time_elapsed_w && ((!RETIRE_IRQ_FENCE || !busy_r) || cadence_retire_uncommanded_w));
	always @(posedge clk)
		if (rst)
			cadence_y_rem_r <= 18'd0;
		else if (TIMED_IRQ_PUMP) begin
			if (command_w)
				cadence_y_rem_r <= (wdata_trig && cadence_nonzero_w ? cadence_y_init_w : 18'd0);
			else if (cadence_y_end_uncommanded_w)
				cadence_y_rem_r <= 18'd0;
			else if (((cadence_valid_r && cadence_pixel_tick_w) && (cadence_x_rem_r <= {2'b00, cadence_xstep_r})) && (cadence_y_rem_r > {2'b00, cadence_ystep_r}))
				cadence_y_rem_r <= cadence_y_rem_r - {2'b00, cadence_ystep_r};
		end
		else if (((fsm_step_w && (state == 5'd27)) && nosrc_step_w) && sw_final_done_w)
			cadence_y_rem_r <= 18'd0;
	wire [4:0] done_idx_w = wolf_pkg_DMA_COMMAND;
	wire [15:0] done_val_w = {1'b0, cmd_lo15};
	always @(posedge clk)
		if (rst)
			launch_image_r <= 1'sb0;
		else if (SHARED_COMMAND_IMAGE) begin
			if ((trig_w && kill_pending_r) && !restart_pending_r)
				launch_image_r <= normal_q_push_word;
			else if (normal_pop_w)
				launch_image_r <= normal_q_mem[normal_q_rptr];
		end
	always @(posedge clk)
		if (rst) begin
			fbq_wptr_r <= 2'd0;
			fbq_rptr_r <= 2'd0;
			fbq_count_r <= 3'd0;
			fb_writer_active_r <= 1'b0;
			fb_we <= 1'b0;
			fb_addr <= 1'sb0;
			fb_wdata <= 16'd0;
		end
		else begin
			if (fb_writer_active_r) begin
				if (fb_ack) begin
					fb_writer_active_r <= 1'b0;
					fb_we <= 1'b0;
				end
			end
			else begin
				fb_we <= 1'b0;
				if (fbq_pop_w) begin
					fb_writer_active_r <= 1'b1;
					fb_we <= 1'b1;
					fb_addr <= fbq_addr[fbq_rptr_r];
					fb_wdata <= fbq_data[fbq_rptr_r];
				end
			end
			if (fbq_discard_w) begin
				fbq_rptr_r <= fbq_wptr_r;
				fbq_count_r <= 3'd0;
			end
			else begin
				if (fbq_push_w) begin
					fbq_addr[fbq_wptr_r] <= fb_addr_w;
					fbq_data[fbq_wptr_r] <= pix_data_w;
					fbq_wptr_r <= fbq_wptr_r + 2'd1;
				end
				if (fbq_pop_w)
					fbq_rptr_r <= fbq_rptr_r + 2'd1;
				case ({fbq_push_w, fbq_pop_w})
					2'b10: fbq_count_r <= fbq_count_r + 3'd1;
					2'b01: fbq_count_r <= fbq_count_r - 3'd1;
					default:
						;
				endcase
			end
		end
	always @(posedge clk)
		if (rst) begin
			state_q1 <= 5'd0;
			drun <= 1'b0;
			dcnt <= 6'd0;
			dnum <= 32'd0;
			dden <= 32'd0;
			drem <= 32'd0;
			dquo <= 32'd0;
		end
		else if (kill_enter_w) begin
			state_q1 <= 5'd0;
			drun <= 1'b0;
			dcnt <= 6'd0;
			dnum <= 32'd0;
			dden <= 32'd0;
			drem <= 32'd0;
			dquo <= 32'd0;
		end
		else if (((!paused_r && !walker_halted_r) && !stop_boundary_enter_w) && !pause_enter_w) begin
			state_q1 <= state;
			if (fast_skdiv_w) begin
				drun <= 1'b0;
				dcnt <= 6'd0;
				dquo <= pre_fp_w >> 8;
			end
			else if (fast_rpdiv_w) begin
				drun <= 1'b0;
				dcnt <= 6'd0;
				dquo <= ss_diff_w >> 8;
			end
			else if (div_go) begin
				drun <= 1'b1;
				dcnt <= 6'd32;
				dnum <= div_num;
				dden <= div_den;
				drem <= 32'd0;
				dquo <= 32'd0;
			end
			else if (drun) begin
				if (drem_trial_w >= dden) begin
					drem <= drem_trial_w - dden;
					dquo <= {dquo[QUOT_W - 2:0], 1'b1};
				end
				else begin
					drem <= drem_trial_w;
					dquo <= {dquo[QUOT_W - 2:0], 1'b0};
				end
				dnum <= {dnum[30:0], 1'b0};
				dcnt <= dcnt - 6'd1;
				if (dcnt == 6'd1)
					drun <= 1'b0;
			end
		end
	integer i;
	always @(posedge clk)
		if (rst) begin
			state <= 5'd0;
			blit_irq <= 1'b0;
			busy_r <= 1'b0;
			cadence_valid_r <= 1'b0;
			cadence_x_reload_r <= 18'd0;
			cadence_x_rem_r <= 18'd0;
			cadence_xstep_r <= 16'h0100;
			cadence_ystep_r <= 16'h0100;
			cadence_phase_r <= 7'd0;
			timeout_stop_armed_r <= 1'b0;
			timeout_stop_age_r <= 6'd0;
			halt_pending_r <= 1'b0;
			walker_halted_r <= 1'b0;
			paused_r <= 1'b0;
			kill_pending_r <= 1'b0;
			restart_pending_r <= 1'b0;
			setup_from_restart_r <= 1'b0;
			normal_q_wptr <= 1'sb0;
			normal_q_rptr <= 1'sb0;
			normal_q_count <= 1'sb0;
			normal_q_overflow_r <= 1'b0;
			normal_q_highwater_r <= 1'sb0;
			normal_launch_word <= 1'sb0;
			setup_from_normal_q_r <= 1'b0;
			for (i = 0; i < wolf_pkg_DMA_NREGS; i = i + 1)
				begin
					regf[i] <= 16'h0000;
					restart_regf[i] <= 16'h0000;
				end
			straddle_limit_c <= 4'd8;
			bpp_c <= 4'd0;
			zero_c <= OP_SKIP;
			nz_c <= OP_SKIP;
			need_px_c <= 1'b0;
			xflip_c <= 1'b0;
			yflip_c <= 1'b0;
			skip_c <= 1'b0;
			scale_c <= 1'b0;
			preskip_c <= 2'd0;
			postskip_c <= 2'd0;
			xstep_c <= 16'h0100;
			ystep_c <= 16'h0100;
			width_c <= 10'd0;
			height_c <= 10'd0;
			xpos_c <= 10'd0;
			pal16_c <= 16'd0;
			color16_c <= 16'd0;
			topclip_c <= 9'd0;
			botclip_c <= 9'd0;
			leftclip_c <= 10'd0;
			rightclip_c <= 10'd0;
			startskip_c <= 32'sd0;
			endskip_c <= 32'sd0;
			offset_r <= 32'd0;
			o_r <= 32'd0;
			ix <= 32'sd0;
			iy <= 32'sd0;
			width_fp <= 32'sd0;
			clip_gap <= 1'b1;
			sx <= 10'd0;
			sy <= 9'd0;
			pre_r <= 32'sd0;
			post_r <= 32'sd0;
			b0_r <= 8'd0;
			b1_r <= 8'd0;
			skipval_r <= 8'd0;
			px_r <= 8'd0;
			fast_src_prefetch_addr_r <= 32'd0;
			fast_src_prefetch_ready_r <= 1'b0;
			fast_src_carry_r <= 1'b0;
			src_state_addr_r <= 32'd0;
			src_early_valid_r <= 1'b0;
			bc_prev0 <= 32'hfffffffe;
			bc_prev1 <= 32'hfffffffe;
			bc_a0 <= 32'hffffffff;
			bc_a1 <= 32'hffffffff;
			bc_d0 <= 8'd0;
			bc_d1 <= 8'd0;
			bc_v0 <= 1'b0;
			bc_v1 <= 1'b0;
			sa_cnt <= 32'd0;
			txm_r <= 32'd0;
			rowbits_r <= 14'd0;
			tyr_r <= 9'd0;
			w2p_r <= 11'd0;
			w3p_r <= 11'd0;
			radv_r <= 32'd0;
			w2adv_r <= 32'd0;
			w3adv_r <= 32'd0;
		end
		else begin
			state <= state_n;
			if (trig_w || !busy_r) begin
				timeout_stop_armed_r <= 1'b0;
				timeout_stop_age_r <= 6'd0;
			end
			else if (timeout_pair_resume_w) begin
				timeout_stop_armed_r <= 1'b0;
				timeout_stop_age_r <= 6'd0;
			end
			else if (stop_w_raw && timeout_stop_context_w) begin
				timeout_stop_armed_r <= 1'b1;
				timeout_stop_age_r <= 6'd63;
			end
			else if (timeout_stop_armed_r) begin
				if (timeout_stop_age_r == 6'd0)
					timeout_stop_armed_r <= 1'b0;
				else
					timeout_stop_age_r <= timeout_stop_age_r - 6'd1;
			end
			if (TIMED_IRQ_PUMP && cadence_valid_r) begin
				if (cadence_pixel_tick_w) begin
					cadence_phase_r <= cadence_phase_next_w - 8'd105;
					if (cadence_x_rem_r <= {2'b00, cadence_xstep_r}) begin
						if (cadence_y_rem_r <= {2'b00, cadence_ystep_r}) begin
							if (cadence_complete_w) begin
								cadence_valid_r <= 1'b0;
								cadence_x_rem_r <= 18'd0;
								blit_irq <= 1'b1;
							end
						end
						else
							cadence_x_rem_r <= cadence_x_reload_r;
					end
					else
						cadence_x_rem_r <= cadence_x_rem_r - {2'b00, cadence_xstep_r};
				end
				else
					cadence_phase_r <= cadence_phase_next_w[6:0];
			end
			if (paused_r || walker_halted_r)
				state <= state;
			if (stop_boundary_enter_w)
				state <= (stop_source_advance_w ? state_n : state);
			if (kill_enter_w)
				state <= (restart_pending_r ? 5'd1 : 5'd0);
			if (kill_enter_w)
				fast_src_carry_r <= 1'b0;
			if (kill_enter_w)
				src_early_valid_r <= 1'b0;
			if (fsm_step_w) begin
				if ((state != 5'd17) && (state_n == 5'd17)) begin
					fast_src_prefetch_addr_r <= (o_next_bpp8_w[2:0] != 3'd0 ? o_next_byte1_w : o_next_byte0_w);
					fast_src_prefetch_ready_r <= (((need_px_c && !scale_c) && (bpp_c == 4'd8)) && (ix_next_unity_w < width_fp)) && next_unity_in_clip_w;
				end
				else if ((state == 5'd17) && (state_n != 5'd17))
					fast_src_prefetch_ready_r <= 1'b0;
				if (((state == 5'd17) && (state_n != 5'd17)) && fast_src_prefetch_w)
					fast_src_carry_r <= 1'b1;
				if (fast_src_carry_r && src_ack)
					fast_src_carry_r <= 1'b0;
				if (state_n == 5'd9) begin
					fast_src_carry_r <= 1'b0;
					fast_src_prefetch_ready_r <= 1'b0;
				end
				if ((state == 5'd9) && (state_n == 5'd14)) begin
					src_state_addr_r <= cur_req_addr_w;
					src_early_valid_r <= 1'b1;
				end
				else if ((state == 5'd17) && (state_n == 5'd14)) begin
					src_state_addr_r <= (SHARED_SOURCE_LOOKUP ? lookup_req_addr_w : (scale_c ? sc_next_req_addr_w : ns_next_req_addr_w));
					src_early_valid_r <= 1'b1;
				end
				else if ((((state == 5'd14) && pix_remain) && !in_clip) && !clip_gap) begin
					src_state_addr_r <= (SHARED_SOURCE_LOOKUP ? lookup_req_addr_w : (scale_c ? sc_next_req_addr_w : ns_next_req_addr_w));
					src_early_valid_r <= 1'b1;
				end
				else if ((state == 5'd12) || ((state_n == 5'd17) && (state != 5'd17)))
					src_early_valid_r <= 1'b0;
				if ((state == 5'd3) && (state_n == 5'd4))
					src_state_addr_r <= {3'b000, offset_r[31:3]};
				else if ((state == 5'd4) && src_ack)
					src_state_addr_r <= o_byte1;
				else if ((state == 5'd14) && !fast_src_carry_r) begin
					if (state_n == 5'd15)
						src_state_addr_r <= o_byte0;
					else if (state_n == 5'd16)
						src_state_addr_r <= o_byte1;
				end
				else if (((state == 5'd15) && src_ack) && (state_n == 5'd16))
					src_state_addr_r <= o_byte1;
				else if ((state == 5'd21) && (state_n == 5'd22))
					src_state_addr_r <= o_byte0;
				else if ((state == 5'd22) && src_ack)
					src_state_addr_r <= o_byte1;
			end
			case (state)
				5'd2:
					if (nosrc_step_w) begin
						straddle_limit_c <= 4'd8 - bpp_w;
						bpp_c <= bpp_w;
						zero_c <= zero_w;
						nz_c <= nz_w;
						need_px_c <= need_px_w;
						xflip_c <= xflip_w;
						yflip_c <= yflip_w;
						skip_c <= skip_w;
						scale_c <= scale_w;
						preskip_c <= preskip_w;
						postskip_c <= postskip_w;
						xstep_c <= xstep_w;
						ystep_c <= ystep_w;
						width_c <= w_width10;
						rowbits_r <= rowbits_setup_w;
						height_c <= w_height10;
						xpos_c <= w_xpos10;
						pal16_c <= s_pal & 16'h7f00;
						color16_c <= (s_pal & 16'h7f00) | {8'd0, w_color8};
						topclip_c <= w_top9;
						botclip_c <= w_bot9;
						leftclip_c <= w_left10;
						rightclip_c <= w_right10;
						startskip_c <= $signed(startskip_w);
						endskip_c <= $signed(endskip_w);
						offset_r <= gfxoff2;
						sy <= w_ypos9;
						iy <= 32'sd0;
						pre_r <= 32'sd0;
						post_r <= 32'sd0;
						clip_gap <= 1'b1;
					end
				5'd3:
					if (nosrc_step_w) begin
						if (iy < height_fp) begin
							width_fp <= $signed(width32) <<< 8;
							sx <= xpos_c;
							ix <= 32'sd0;
							o_r <= offset_r;
						end
					end
				5'd4:
					if (srcstate_step_w) begin
						if (src_ack)
							b0_r <= src_data;
					end
				5'd5:
					if (srcstate_step_w) begin
						if (src_ack)
							skipval_r <= byte_now;
					end
				5'd6:
					if (nosrc_step_w) begin
						if (xstep_unity_w)
							txm_r <= pre_fp_w;
					end
				5'd7:
					if (nosrc_step_w)
						txm_r <= dquo_mul_w * xstep_c;
				5'd8:
					if (nosrc_step_w) begin
						pre_r <= $signed(pre_fp_w);
						post_r <= $signed(post_fp_w);
						sx <= (SHARED_WALKER_ARITH ? walker_sx_sum_w : (xflip_c ? sx - tx_skip10 : sx + tx_skip10));
						ix <= (SHARED_WALKER_ARITH ? walker_ix_sum_w : ix + $signed(txm_u32_w));
						width_fp <= width_fp - $signed(post_fp_w);
						o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : o_r + 32'd8);
					end
				5'd9:
					if (nosrc_step_w) begin
						if (!y_clip_w) begin
							if ((width_fp >>> 8) > we_lim)
								width_fp <= we_lim <<< 8;
						end
					end
				5'd10:
					if (nosrc_step_w) begin
						if (xstep_unity_w)
							txm_r <= ss_diff_w;
					end
				5'd11:
					if (nosrc_step_w)
						txm_r <= dquo_mul_w * xstep_c;
				5'd12:
					if (nosrc_step_w) begin
						ix <= (SHARED_WALKER_ARITH ? walker_ix_sum_w : ix + $signed(txm_u32_w));
						o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : o_r + rp_skip_bits_w);
						clip_gap <= 1'b1;
					end
				5'd14:
					if (fsm_step_w) begin
						if ((pix_remain && in_clip) && need_px_c) begin
							if (hit0)
								b0_r <= hitd0;
							if (px_straddle && hit1)
								b1_r <= hitd1;
							if (!need_f0 && !need_f1)
								px_r <= px_cache;
							if (src_ack && (need_f0 || need_f1)) begin
								if (need_f0) begin
									b0_r <= src_data;
									if (!need_f1)
										px_r <= ({b1_r, src_data} >> o_lo3) & {8'd0, pixmask};
								end
								else begin
									b1_r <= src_data;
									px_r <= ({src_data, hitd0} >> o_lo3) & {8'd0, pixmask};
								end
							end
						end
						if (pix_remain && !in_clip) begin
							if (clip_gap)
								clip_gap <= 1'b0;
							else begin
								sx <= (SHARED_WALKER_ARITH ? walker_sx_sum_w : (xflip_c ? sx - 10'd1 : sx + 10'd1));
								clip_gap <= 1'b1;
								if (!scale_c) begin
									ix <= (SHARED_WALKER_ARITH ? walker_ix_sum_w : ix + 32'sd256);
									o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : o_r + bpp32);
								end
								else begin
									ix <= (SHARED_WALKER_ARITH ? walker_ix_sum_w : ix + xstep_s);
									o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : o_r + {20'd0, sc_step_bits_w});
								end
							end
						end
					end
				5'd15:
					if (srcstate_step_w) begin
						if (src_ack) begin
							b0_r <= src_data;
							if (!need_f1)
								px_r <= ({b1_r, src_data} >> o_lo3) & {8'd0, pixmask};
						end
					end
				5'd16:
					if (srcstate_step_w) begin
						if (src_ack)
							px_r <= px_now;
					end
				5'd17:
					if (fsm_step_w) begin
						if (!do_write_w || !fbq_full_w) begin
							sx <= (SHARED_WALKER_ARITH ? walker_sx_sum_w : (xflip_c ? sx - 10'd1 : sx + 10'd1));
							clip_gap <= 1'b1;
							if (!scale_c) begin
								ix <= (SHARED_WALKER_ARITH ? walker_ix_sum_w : ix + 32'sd256);
								o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : o_r + bpp32);
							end
							else begin
								ix <= (SHARED_WALKER_ARITH ? walker_ix_sum_w : ix + xstep_s);
								o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : o_r + {20'd0, sc_step_bits_w});
							end
						end
					end
				5'd18:
					if (nosrc_step_w) begin
						tyr_r <= ty_w[8:0];
						w2p_r <= (w2_ns > 32'sd0 ? w2_ns[10:0] : 11'd0);
					end
				5'd19:
					if (nosrc_step_w) begin
						radv_r <= tyr_r * rowbits_r;
						w2adv_r <= w2p_r * bpp_c;
					end
				5'd20:
					if (nosrc_step_w) begin
						sy <= (yflip_c ? sy - 9'd1 : sy + 9'd1);
						if (!scale_c) begin
							iy <= (SHARED_WALKER_ARITH ? walker_iy_sum_w : iy + 32'sd256);
							if (skip_c)
								offset_r <= (SHARED_WALKER_ARITH ? walker_offset_sum_w : (offset_r + 32'd8) + w2adv_r);
							else
								offset_r <= (SHARED_WALKER_ARITH ? walker_offset_sum_w : offset_r + {18'd0, rowbits_r});
						end
						else begin
							iy <= (SHARED_WALKER_ARITH ? walker_iy_sum_w : iy + $signed({16'd0, ystep_c}));
							if (!skip_c)
								offset_r <= (SHARED_WALKER_ARITH ? walker_offset_sum_w : offset_r + radv_r);
							else if (tyr_r != 9'd0) begin
								o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : (offset_r + 32'd8) + w2adv_r);
								sa_cnt <= {23'd0, tyr_r} - 32'd1;
							end
						end
					end
				5'd21:
					if (nosrc_step_w) begin
						if (sa_cnt == 32'd0)
							offset_r <= o_r;
					end
				5'd22:
					if (srcstate_step_w) begin
						if (src_ack)
							b0_r <= src_data;
					end
				5'd23:
					if (srcstate_step_w) begin
						if (src_ack)
							skipval_r <= byte_now;
					end
				5'd24:
					if (nosrc_step_w)
						w3p_r <= (w3_ns > 32'sd0 ? w3_ns[10:0] : 11'd0);
				5'd25:
					if (nosrc_step_w)
						w3adv_r <= w3p_r * bpp_c;
				5'd26:
					if (nosrc_step_w) begin
						o_r <= (SHARED_WALKER_ARITH ? walker_o_sum_w : (o_r + 32'd8) + w3adv_r);
						sa_cnt <= sa_cnt - 32'd1;
					end
				5'd27:
					if (nosrc_step_w) begin
						if (final_done_w) begin
							busy_r <= 1'b0;
							if (sw_final_done_w) begin
								blit_irq <= 1'b1;
								cadence_valid_r <= 1'b0;
								cadence_x_reload_r <= 18'd0;
								cadence_x_rem_r <= 18'd0;
								cadence_phase_r <= 7'd0;
							end
						end
					end
				default:
					;
			endcase
			if (src_req && src_ack) begin
				if (bc_v0 && (bc_a0 == src_addr))
					bc_d0 <= src_data;
				else begin
					bc_prev1 <= bc_prev0;
					bc_prev0 <= src_addr - 32'd1;
					bc_a1 <= bc_a0;
					bc_d1 <= bc_d0;
					bc_v1 <= bc_v0;
					bc_a0 <= src_addr;
					bc_d0 <= src_data;
					bc_v0 <= 1'b1;
				end
			end
			if (done_clear_w)
				regf[done_idx_w] <= done_val_w;
			if (reg_write_accepted_w)
				regf[regnum_w] <= reg_wdata;
			if ((command_w && cadence_immediate_w) && !RETIRE_IRQ_FENCE)
				regf[wolf_pkg_DMA_COMMAND] <= {1'b0, reg_wdata[14:0]};
			if ((trig_w && kill_pending_r) && !restart_pending_r) begin
				for (i = 0; i < wolf_pkg_DMA_NREGS; i = i + 1)
					restart_regf[i] <= regf[i];
				restart_regf[wolf_pkg_DMA_COMMAND] <= reg_wdata;
				restart_pending_r <= 1'b1;
			end
			if (normal_push_w) begin
				normal_q_mem[normal_q_wptr] <= normal_q_push_word;
				normal_q_wptr <= (normal_q_wptr_last ? {NORMAL_Q_PTR_W {1'sb0}} : normal_q_wptr + 1'b1);
				normal_q_count <= normal_q_count + 1'b1;
				if ((normal_q_count + 1'b1) > normal_q_highwater_r)
					normal_q_highwater_r <= normal_q_count + 1'b1;
			end
			if (normal_overflow_w)
				normal_q_overflow_r <= 1'b1;
			if (command_w) begin
				blit_irq <= 1'b0;
				if (TIMED_IRQ_PUMP) begin
					cadence_valid_r <= cadence_start_w;
					cadence_x_reload_r <= (cadence_start_w && cadence_nonzero_w ? cadence_x_init_w : 18'd0);
					cadence_x_rem_r <= (cadence_start_w && cadence_nonzero_w ? cadence_x_init_w : 18'd0);
					cadence_xstep_r <= cadence_xstep_w;
					cadence_ystep_r <= cadence_ystep_w;
					cadence_phase_r <= 7'd0;
					if (cadence_immediate_w && !RETIRE_IRQ_FENCE)
						blit_irq <= 1'b1;
				end
				if (state == 5'd0)
					busy_r <= wdata_trig;
				else if ((((((state == 5'd27) && trig_w) && !paused_r) && !halt_pending_r) && !walker_halted_r) && !kill_pending_r)
					busy_r <= 1'b1;
			end
			if (normal_pop_w) begin
				normal_launch_word <= normal_q_mem[normal_q_rptr];
				normal_q_rptr <= (normal_q_rptr_last ? {NORMAL_Q_PTR_W {1'sb0}} : normal_q_rptr + 1'b1);
				normal_q_count <= normal_q_count - 1'b1;
				setup_from_normal_q_r <= 1'b1;
				busy_r <= 1'b1;
				blit_irq <= 1'b0;
			end
			if (resume_w && !kill_pending_r) begin
				halt_pending_r <= 1'b0;
				walker_halted_r <= 1'b0;
				paused_r <= 1'b0;
				kill_pending_r <= 1'b0;
			end
			else if (kill_enter_w) begin
				halt_pending_r <= 1'b0;
				walker_halted_r <= 1'b0;
				paused_r <= 1'b0;
				kill_pending_r <= 1'b0;
				restart_pending_r <= 1'b0;
				setup_from_restart_r <= restart_pending_r;
				normal_q_wptr <= 1'sb0;
				normal_q_count <= 1'sb0;
				setup_from_normal_q_r <= 1'b0;
				busy_r <= restart_pending_r;
				blit_irq <= 1'b0;
			end
			else if (pause_enter_w) begin
				halt_pending_r <= 1'b0;
				walker_halted_r <= 1'b0;
				paused_r <= 1'b1;
				kill_pending_r <= 1'b0;
			end
			else begin
				if (first_stop_w)
					halt_pending_r <= 1'b1;
				if (second_stop_w)
					kill_pending_r <= 1'b1;
				if (stop_boundary_enter_w)
					walker_halted_r <= 1'b1;
				if (!busy_r && (state == 5'd0)) begin
					halt_pending_r <= 1'b0;
					walker_halted_r <= 1'b0;
					paused_r <= 1'b0;
					kill_pending_r <= 1'b0;
					restart_pending_r <= 1'b0;
					setup_from_restart_r <= 1'b0;
					normal_q_wptr <= 1'sb0;
					normal_q_count <= 1'sb0;
					setup_from_normal_q_r <= 1'b0;
				end
			end
			if (normal_q_clear_w)
				normal_q_rptr <= 1'sb0;
			if (fsm_step_w && (state == 5'd2))
				setup_from_restart_r <= 1'b0;
			if (fsm_step_w && (state == 5'd2))
				setup_from_normal_q_r <= 1'b0;
		end
	reg [2:0] sim_ix_age_r;
	wire sim_ix_write_w = fsm_step_w && ((((((state == 5'd3) && (iy < height_fp)) || (state == 5'd8)) || (state == 5'd12)) || ((((state == 5'd14) && pix_remain) && !in_clip) && !clip_gap)) || ((state == 5'd17) && (!do_write_w || !fbq_full_w)));
	wire sim_scaled_lookahead_capture_w = (fsm_step_w && scale_c) && (((state == 5'd17) && (state_n == 5'd14)) || ((((state == 5'd14) && pix_remain) && !in_clip) && !clip_gap));
	always @(posedge clk)
		if (rst)
			sim_ix_age_r <= 3'd7;
		else begin
			if ((sim_scaled_lookahead_capture_w && SHARED_SOURCE_LOOKUP) && (scaled_lookup_o_r !== sc_next_o_w)) begin
				$display("Fatal [%0t] src/upstream/wolf-unit/rtl/wolf/wolf_dma.sv:1813:9 - wolf_dma.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Scaled look-ahead pipeline consumed an unstable pointer");
				$finish(1);
			end
			if (sim_scaled_lookahead_capture_w && (sim_ix_age_r < 3'd1)) begin
				$display("Fatal [%0t] src/upstream/wolf-unit/rtl/wolf/wolf_dma.sv:1815:9 - wolf_dma.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "wolf_dma: scaled look-ahead captured before ix two-cycle gap");
				$finish(1);
			end
			if (sim_ix_write_w)
				sim_ix_age_r <= 3'd0;
			else if (sim_ix_age_r != 3'd7)
				sim_ix_age_r <= sim_ix_age_r + 3'd1;
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_pic (
	clk,
	rst,
	cmd_we,
	cmd_data,
	resp_re,
	reset_w,
	reset_val,
	resp_data,
	status
);
	parameter [127:0] RESPONSE_BYTES = 128'h2b1e4a0e02176c60b4082509db019af6;
	input wire clk;
	input wire rst;
	input wire cmd_we;
	input wire [7:0] cmd_data;
	input wire resp_re;
	input wire reset_w;
	input wire reset_val;
	output wire [7:0] resp_data;
	output wire status;
	function automatic [7:0] pic_byte;
		input reg [3:0] a;
		case (a)
			4'h0: pic_byte = RESPONSE_BYTES[7:0];
			4'h1: pic_byte = RESPONSE_BYTES[15:8];
			4'h2: pic_byte = RESPONSE_BYTES[23:16];
			4'h3: pic_byte = RESPONSE_BYTES[31:24];
			4'h4: pic_byte = RESPONSE_BYTES[39:32];
			4'h5: pic_byte = RESPONSE_BYTES[47:40];
			4'h6: pic_byte = RESPONSE_BYTES[55:48];
			4'h7: pic_byte = RESPONSE_BYTES[63:56];
			4'h8: pic_byte = RESPONSE_BYTES[71:64];
			4'h9: pic_byte = RESPONSE_BYTES[79:72];
			4'ha: pic_byte = RESPONSE_BYTES[87:80];
			4'hb: pic_byte = RESPONSE_BYTES[95:88];
			4'hc: pic_byte = RESPONSE_BYTES[103:96];
			4'hd: pic_byte = RESPONSE_BYTES[111:104];
			4'he: pic_byte = RESPONSE_BYTES[119:112];
			default: pic_byte = RESPONSE_BYTES[127:120];
		endcase
	endfunction
	reg [7:0] buff;
	reg [3:0] idx;
	reg stat;
	always @(posedge clk)
		if (rst) begin
			idx <= 4'd0;
			stat <= 1'b0;
			buff <= 8'd0;
		end
		else if (reset_w && reset_val) begin
			idx <= 4'd0;
			stat <= 1'b0;
			buff <= 8'd0;
		end
		else begin
			if (cmd_we) begin
				stat <= cmd_data[4];
				if (!cmd_data[4]) begin
					if (cmd_data[3:0] != 4'd0)
						buff <= {4'h0, cmd_data[3:0]};
					else begin
						buff <= pic_byte(idx);
						idx <= idx + 4'd1;
					end
				end
			end
			if (resp_re)
				stat <= 1'b1;
		end
	assign resp_data = buff;
	assign status = stat;
endmodule
`default_nettype wire
`default_nettype none
module vram_sdram (
	clk,
	rst,
	req,
	we,
	widx,
	boff,
	sz,
	wd,
	videobank,
	dma_palette,
	rdata,
	done,
	active,
	sd_addr,
	sd_din,
	sd_be,
	sd_rd,
	sd_wr,
	sd_dout,
	sd_ack
);
	reg _sv2v_0;
	parameter signed [31:0] VRAMW = 32'h00040000;
	parameter signed [31:0] SD_AW = 21;
	parameter [SD_AW - 1:0] VRAM_BASE = 1'sb0;
	input wire clk;
	input wire rst;
	input wire req;
	input wire we;
	input wire [27:0] widx;
	input wire [3:0] boff;
	input wire [5:0] sz;
	input wire [31:0] wd;
	input wire videobank;
	input wire [15:0] dma_palette;
	output reg [31:0] rdata;
	output reg done;
	output wire active;
	output reg [SD_AW - 1:0] sd_addr;
	output reg [15:0] sd_din;
	output reg [1:0] sd_be;
	output reg sd_rd;
	output reg sd_wr;
	input wire [15:0] sd_dout;
	input wire sd_ack;
	reg we_l;
	reg vb_l;
	reg [27:0] wi;
	reg [3:0] bo;
	reg [5:0] szl;
	reg [31:0] wd_l;
	reg [15:0] pal_l;
	wire [18:0] e0 = wi << 1;
	wire [18:0] e1 = (wi << 1) + 19'd1;
	wire [18:0] e2 = (wi + 28'd1) << 1;
	wire [18:0] e3 = ((wi + 28'd1) << 1) + 19'd1;
	wire [18:0] ea = (wi << 1) + {18'd0, bo[3]};
	wire v01 = ((wi << 1) + 28'd1) < VRAMW;
	wire v23 = (((wi + 28'd1) << 1) + 28'd1) < VRAMW;
	wire vea_v = ((wi << 1) + {27'd0, bo[3]}) < VRAMW;
	reg [15:0] o0;
	reg [15:0] o1;
	reg [15:0] o2;
	reg [15:0] o3;
	wire [7:0] oea = o0[7:0];
	wire [15:0] vnew0 = (vb_l ? {pal_l[7:0], wd_l[7:0]} : {wd_l[7:0], o0[7:0]});
	wire [15:0] vnew1 = (vb_l ? {pal_l[15:8], wd_l[15:8]} : {wd_l[15:8], o1[7:0]});
	wire [15:0] vnew2 = (vb_l ? {pal_l[7:0], wd_l[23:16]} : {wd_l[23:16], o2[7:0]});
	wire [15:0] vnew3 = (vb_l ? {pal_l[15:8], wd_l[31:24]} : {wd_l[31:24], o3[7:0]});
	wire [15:0] vnewea = (vb_l ? {(bo[3] ? pal_l[15:8] : pal_l[7:0]), wd_l[7:0]} : {wd_l[7:0], oea});
	wire [15:0] vword = (vb_l ? {o1[7:0], o0[7:0]} : {o1[15:8], o0[15:8]});
	wire [47:0] rmask = (48'd1 << szl) - 48'd1;
	wire [2:0] nread = (we_l ? (szl <= 6'd8 ? 3'd1 : (szl <= 6'd16 ? 3'd2 : 3'd4)) : 3'd2);
	wire [2:0] nwrite = (we_l ? (szl <= 6'd8 ? 3'd1 : (szl <= 6'd16 ? 3'd2 : 3'd4)) : 3'd0);
	wire is8 = we_l & (szl <= 6'd8);
	function automatic [18:0] raddr;
		input [1:0] i;
		if (is8)
			raddr = ea;
		else
			case (i)
				2'd0: raddr = e0;
				2'd1: raddr = e1;
				2'd2: raddr = e2;
				default: raddr = e3;
			endcase
	endfunction
	function automatic rvalid;
		input [1:0] i;
		if (is8)
			rvalid = vea_v;
		else
			rvalid = (i < 2'd2 ? v01 : v23);
	endfunction
	function automatic [18:0] waddr;
		input [1:0] i;
		if (is8)
			waddr = ea;
		else
			case (i)
				2'd0: waddr = e0;
				2'd1: waddr = e1;
				2'd2: waddr = e2;
				default: waddr = e3;
			endcase
	endfunction
	function automatic [15:0] wdata;
		input [1:0] i;
		if (is8)
			wdata = vnewea;
		else
			case (i)
				2'd0: wdata = vnew0;
				2'd1: wdata = vnew1;
				2'd2: wdata = vnew2;
				default: wdata = vnew3;
			endcase
	endfunction
	function automatic wvalid;
		input [1:0] i;
		if (is8)
			wvalid = vea_v;
		else
			wvalid = (i < 2'd2 ? v01 : v23);
	endfunction
	reg [1:0] st;
	reg [2:0] idx;
	assign active = st != 2'd0;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			st <= 2'd0;
			done <= 1'b0;
			sd_rd <= 1'b0;
			sd_wr <= 1'b0;
			idx <= 2'd0;
		end
		else begin
			done <= 1'b0;
			case (st)
				2'd0: begin
					sd_rd <= 1'b0;
					sd_wr <= 1'b0;
					if (req) begin
						we_l <= we;
						wi <= widx;
						bo <= boff;
						szl <= sz;
						wd_l <= wd;
						vb_l <= videobank;
						pal_l <= dma_palette;
						idx <= 2'd0;
						st <= 2'd1;
					end
				end
				2'd1:
					if (idx >= nread) begin
						sd_rd <= 1'b0;
						if (we_l) begin
							idx <= 2'd0;
							st <= 2'd2;
						end
						else
							st <= 2'd3;
					end
					else if (!rvalid(idx)) begin
						case (idx)
							2'd0: o0 <= 16'h0000;
							2'd1: o1 <= 16'h0000;
							2'd2: o2 <= 16'h0000;
							default: o3 <= 16'h0000;
						endcase
						idx <= idx + 2'd1;
					end
					else if (sd_ack) begin
						case (idx)
							2'd0: o0 <= sd_dout;
							2'd1: o1 <= sd_dout;
							2'd2: o2 <= sd_dout;
							default: o3 <= sd_dout;
						endcase
						sd_rd <= 1'b0;
						idx <= idx + 2'd1;
					end
					else begin
						sd_addr <= VRAM_BASE + raddr(idx);
						sd_be <= 2'b00;
						sd_rd <= 1'b1;
					end
				2'd2:
					if (idx >= nwrite) begin
						sd_wr <= 1'b0;
						st <= 2'd3;
					end
					else if (!wvalid(idx))
						idx <= idx + 2'd1;
					else if (sd_ack) begin
						sd_wr <= 1'b0;
						idx <= idx + 2'd1;
					end
					else begin
						sd_addr <= VRAM_BASE + waddr(idx);
						sd_din <= wdata(idx);
						sd_be <= 2'b11;
						sd_wr <= 1'b1;
					end
				2'd3: begin
					rdata <= sv2v_cast_32(({32'h00000000, vword} >> bo) & rmask);
					done <= 1'b1;
					st <= 2'd0;
				end
				default: st <= 2'd0;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module vram_sdram_top (
	clk,
	rst,
	req,
	we,
	widx,
	boff,
	sz,
	wd,
	videobank,
	dma_palette,
	rdata,
	done,
	fb_we,
	fb_addr,
	fb_wdata,
	fb_ack,
	erase_start,
	erase_row0,
	erase_lines,
	erase_busy,
	scan_req,
	scan_addr,
	scan_data,
	scan_ack,
	sd_addr,
	sd_din,
	sd_be,
	sd_rd,
	sd_wr,
	sd_dout,
	sd_ack
);
	reg _sv2v_0;
	parameter signed [31:0] VRAMW = 32'h00040000;
	parameter signed [31:0] SD_AW = 21;
	parameter [SD_AW - 1:0] VRAM_BASE = 1'sb0;
	input wire clk;
	input wire rst;
	input wire req;
	input wire we;
	input wire [27:0] widx;
	input wire [3:0] boff;
	input wire [5:0] sz;
	input wire [31:0] wd;
	input wire videobank;
	input wire [15:0] dma_palette;
	output wire [31:0] rdata;
	output wire done;
	input wire fb_we;
	input wire [18:0] fb_addr;
	input wire [15:0] fb_wdata;
	output reg fb_ack;
	input wire erase_start;
	input wire [8:0] erase_row0;
	input wire [9:0] erase_lines;
	output wire erase_busy;
	input wire scan_req;
	input wire [18:0] scan_addr;
	output wire [15:0] scan_data;
	output reg scan_ack;
	output reg [SD_AW - 1:0] sd_addr;
	output reg [15:0] sd_din;
	output reg [1:0] sd_be;
	output reg sd_rd;
	output reg sd_wr;
	input wire [15:0] sd_dout;
	input wire sd_ack;
	reg c_ack_i;
	reg f_ack_i;
	reg ae_ack_i;
	wire [SD_AW - 1:0] c_addr;
	wire [15:0] c_din;
	wire [1:0] c_be;
	wire c_rd;
	wire c_wr;
	wire c_active;
	vram_sdram #(
		.VRAMW(VRAMW),
		.SD_AW(SD_AW),
		.VRAM_BASE(VRAM_BASE)
	) u_cpu(
		.clk(clk),
		.rst(rst),
		.req(req),
		.we(we),
		.widx(widx),
		.boff(boff),
		.sz(sz),
		.wd(wd),
		.videobank(videobank),
		.dma_palette(dma_palette),
		.rdata(rdata),
		.done(done),
		.active(c_active),
		.sd_addr(c_addr),
		.sd_din(c_din),
		.sd_be(c_be),
		.sd_rd(c_rd),
		.sd_wr(c_wr),
		.sd_dout(sd_dout),
		.sd_ack(c_ack_i)
	);
	reg [18:0] f_a;
	reg [15:0] f_d;
	reg f_pending;
	reg fb_we_d;
	always @(posedge clk)
		if (rst) begin
			f_pending <= 1'b0;
			fb_ack <= 1'b0;
			fb_we_d <= 1'b0;
		end
		else begin
			fb_ack <= 1'b0;
			fb_we_d <= fb_we;
			if (!f_pending) begin
				if (fb_we & ~fb_we_d) begin
					f_a <= fb_addr;
					f_d <= fb_wdata;
					f_pending <= 1'b1;
				end
			end
			else if (f_ack_i) begin
				f_pending <= 1'b0;
				fb_ack <= 1'b1;
			end
		end
	localparam [1:0] AE_IDLE = 2'd0;
	localparam [1:0] AE_RD = 2'd1;
	localparam [1:0] AE_WR = 2'd2;
	localparam [1:0] AE_ADV = 2'd3;
	reg [1:0] ae;
	reg er_run;
	reg [8:0] er_row;
	reg [8:0] er_x;
	reg [9:0] er_left;
	reg [15:0] er_data;
	wire [17:0] ae_src = {8'hff, er_row[0], er_x};
	wire [17:0] ae_dst = {er_row, er_x};
	wire ae_skip = (er_row == 9'd510) || (er_row == 9'd511);
	wire ae_rd_req = (ae == AE_RD) & ~ae_skip;
	wire ae_wr_req = ae == AE_WR;
	assign erase_busy = er_run;
	always @(posedge clk)
		if (rst) begin
			ae <= AE_IDLE;
			er_run <= 1'b0;
		end
		else
			case (ae)
				AE_IDLE:
					if (erase_start && (erase_lines != 10'd0)) begin
						er_run <= 1'b1;
						er_row <= erase_row0 - 9'd1;
						er_x <= 9'd0;
						er_left <= erase_lines + 10'd1;
						ae <= AE_RD;
					end
				AE_RD:
					if (ae_skip)
						ae <= AE_ADV;
					else if (ae_ack_i) begin
						er_data <= sd_dout;
						ae <= AE_WR;
					end
				AE_WR:
					if (ae_ack_i)
						ae <= AE_ADV;
				AE_ADV:
					if (er_x == 9'd511) begin
						er_x <= 9'd0;
						er_row <= er_row + 9'd1;
						er_left <= er_left - 10'd1;
						if (er_left <= 10'd1) begin
							er_run <= 1'b0;
							ae <= AE_IDLE;
						end
						else
							ae <= AE_RD;
					end
					else begin
						er_x <= er_x + 9'd1;
						ae <= AE_RD;
					end
				default: ae <= AE_IDLE;
			endcase
	wire cpu_req = c_rd | c_wr;
	wire fb_req = f_pending;
	wire ae_req = ae_rd_req | ae_wr_req;
	reg [2:0] gnt;
	reg gnt_held;
	reg [2:0] gnt_r;
	reg bubble;
	always @(*) begin
		if (_sv2v_0)
			;
		if (gnt_held)
			gnt = gnt_r;
		else if (bubble)
			gnt = 3'd0;
		else if (scan_req)
			gnt = 3'd1;
		else if (cpu_req)
			gnt = 3'd2;
		else if (fb_req)
			gnt = 3'd3;
		else if (ae_req)
			gnt = 3'd4;
		else
			gnt = 3'd0;
	end
	always @(posedge clk)
		if (rst) begin
			gnt_held <= 1'b0;
			gnt_r <= 3'd0;
			bubble <= 1'b0;
		end
		else begin
			bubble <= 1'b0;
			if (!gnt_held) begin
				if (!bubble && (gnt != 3'd0)) begin
					gnt_held <= 1'b1;
					gnt_r <= gnt;
				end
			end
			else if (sd_ack) begin
				gnt_held <= 1'b0;
				bubble <= 1'b1;
			end
		end
	always @(*) begin
		if (_sv2v_0)
			;
		sd_addr = 1'sb0;
		sd_din = 16'h0000;
		sd_be = 2'b00;
		sd_rd = 1'b0;
		sd_wr = 1'b0;
		c_ack_i = 1'b0;
		f_ack_i = 1'b0;
		ae_ack_i = 1'b0;
		scan_ack = 1'b0;
		case (gnt)
			3'd1: begin
				sd_addr = VRAM_BASE + {{SD_AW - 19 {1'b0}}, scan_addr};
				sd_be = 2'b00;
				sd_rd = scan_req;
				scan_ack = sd_ack;
			end
			3'd2: begin
				sd_addr = c_addr;
				sd_din = c_din;
				sd_be = c_be;
				sd_rd = c_rd;
				sd_wr = c_wr;
				c_ack_i = sd_ack;
			end
			3'd3: begin
				sd_addr = VRAM_BASE + {{SD_AW - 19 {1'b0}}, f_a};
				sd_din = f_d;
				sd_be = 2'b11;
				sd_wr = f_pending;
				f_ack_i = sd_ack;
			end
			3'd4: begin
				if (ae_rd_req) begin
					sd_addr = VRAM_BASE + {{SD_AW - 18 {1'b0}}, ae_src};
					sd_be = 2'b00;
					sd_rd = 1'b1;
				end
				else begin
					sd_addr = VRAM_BASE + {{SD_AW - 18 {1'b0}}, ae_dst};
					sd_din = er_data;
					sd_be = 2'b11;
					sd_wr = 1'b1;
				end
				ae_ack_i = sd_ack;
			end
			default:
				;
		endcase
	end
	assign scan_data = sd_dout;
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module ram_sdram (
	clk,
	rst,
	req,
	we,
	widx,
	boff,
	sz,
	wd,
	rdata,
	done,
	active,
	sd_addr,
	sd_din,
	sd_be,
	sd_rd,
	sd_wr,
	sd_dout,
	sd_ack
);
	reg _sv2v_0;
	parameter signed [31:0] RAMW = 32'h00040000;
	parameter signed [31:0] SD_AW = 25;
	parameter [SD_AW - 1:0] RAM_BASE = 1'sb0;
	input wire clk;
	input wire rst;
	input wire req;
	input wire we;
	input wire [27:0] widx;
	input wire [3:0] boff;
	input wire [5:0] sz;
	input wire [31:0] wd;
	output reg [31:0] rdata;
	output reg done;
	output wire active;
	output reg [SD_AW - 1:0] sd_addr;
	output reg [15:0] sd_din;
	output reg [1:0] sd_be;
	output reg sd_rd;
	output reg sd_wr;
	input wire [15:0] sd_dout;
	input wire sd_ack;
	reg we_l;
	reg [27:0] wi;
	reg [3:0] bo;
	reg [5:0] szl;
	reg [31:0] wd_l;
	wire [27:0] w0 = wi;
	wire [27:0] w1 = wi + 28'd1;
	wire [27:0] w2 = wi + 28'd2;
	wire v0 = w0 < RAMW[27:0];
	wire v1 = w1 < RAMW[27:0];
	wire v2 = w2 < RAMW[27:0];
	wire [5:0] lastb = (bo + szl) - 6'd1;
	wire [2:0] ntouch = (lastb < 6'd16 ? 3'd1 : (lastb < 6'd32 ? 3'd2 : 3'd3));
	wire [47:0] rmask = (48'd1 << szl) - 48'd1;
	wire [47:0] smask = rmask << bo;
	reg [15:0] o0;
	reg [15:0] o1;
	reg [15:0] o2;
	wire [47:0] win = {(v2 ? o2 : 16'h0000), (v1 ? o1 : 16'h0000), (v0 ? o0 : 16'h0000)};
	wire [47:0] merged = (win & ~smask) | (({16'h0000, wd_l} << bo) & smask);
	function automatic [27:0] wsel;
		input [1:0] i;
		case (i)
			2'd0: wsel = w0;
			2'd1: wsel = w1;
			default: wsel = w2;
		endcase
	endfunction
	function automatic vsel;
		input [1:0] i;
		case (i)
			2'd0: vsel = v0;
			2'd1: vsel = v1;
			default: vsel = v2;
		endcase
	endfunction
	function automatic [15:0] msel;
		input [1:0] i;
		case (i)
			2'd0: msel = merged[15:0];
			2'd1: msel = merged[31:16];
			default: msel = merged[47:32];
		endcase
	endfunction
	reg [1:0] st;
	reg [2:0] idx;
	assign active = st != 2'd0;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			st <= 2'd0;
			done <= 1'b0;
			sd_rd <= 1'b0;
			sd_wr <= 1'b0;
			idx <= 3'd0;
			o0 <= 16'h0000;
			o1 <= 16'h0000;
			o2 <= 16'h0000;
		end
		else begin
			done <= 1'b0;
			case (st)
				2'd0: begin
					sd_rd <= 1'b0;
					sd_wr <= 1'b0;
					if (req) begin
						we_l <= we;
						wi <= widx;
						bo <= boff;
						szl <= sz;
						wd_l <= wd;
						o0 <= 16'h0000;
						o1 <= 16'h0000;
						o2 <= 16'h0000;
						idx <= 3'd0;
						st <= 2'd1;
					end
				end
				2'd1:
					if (idx >= ntouch) begin
						sd_rd <= 1'b0;
						if (we_l) begin
							idx <= 3'd0;
							st <= 2'd2;
						end
						else
							st <= 2'd3;
					end
					else if (!vsel(idx[1:0])) begin
						case (idx[1:0])
							2'd0: o0 <= 16'h0000;
							2'd1: o1 <= 16'h0000;
							default: o2 <= 16'h0000;
						endcase
						idx <= idx + 3'd1;
					end
					else if (sd_ack) begin
						case (idx[1:0])
							2'd0: o0 <= sd_dout;
							2'd1: o1 <= sd_dout;
							default: o2 <= sd_dout;
						endcase
						sd_rd <= 1'b0;
						idx <= idx + 3'd1;
					end
					else begin
						sd_addr <= RAM_BASE + wsel(idx[1:0]);
						sd_be <= 2'b00;
						sd_rd <= 1'b1;
					end
				2'd2:
					if (idx >= ntouch) begin
						sd_wr <= 1'b0;
						st <= 2'd3;
					end
					else if (!vsel(idx[1:0]))
						idx <= idx + 3'd1;
					else if (sd_ack) begin
						sd_wr <= 1'b0;
						idx <= idx + 3'd1;
					end
					else begin
						sd_addr <= RAM_BASE + wsel(idx[1:0]);
						sd_din <= msel(idx[1:0]);
						sd_be <= 2'b11;
						sd_wr <= 1'b1;
					end
				2'd3: begin
					rdata <= sv2v_cast_32((win >> bo) & rmask);
					done <= 1'b1;
					st <= 2'd0;
				end
				default: st <= 2'd0;
			endcase
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module stv_vram_ddr_agent (
	clk,
	sdram_por,
	tst_wr_req,
	tst_rd_req,
	tst_addr,
	tst_wdata,
	tst_be,
	tst_burstcnt,
	tst_rdata,
	tst_rd_valid,
	tst_busy,
	tst_wr_done,
	tst_wr_base,
	tst_wr_count,
	tst_wr_last_data,
	tst_wnext,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready
);
	parameter [28:0] VRAM_DDR_BASE = 29'h06400000;
	input wire clk;
	input wire sdram_por;
	input wire tst_wr_req;
	input wire tst_rd_req;
	input wire [25:0] tst_addr;
	input wire [63:0] tst_wdata;
	input wire [7:0] tst_be;
	input wire [7:0] tst_burstcnt;
	output reg [63:0] tst_rdata;
	output reg tst_rd_valid;
	output reg tst_busy;
	output reg tst_wr_done;
	output reg [25:0] tst_wr_base;
	output reg [7:0] tst_wr_count;
	output reg [63:0] tst_wr_last_data;
	output wire tst_wnext;
	output reg [28:0] ddram_addr;
	output reg [7:0] ddram_burstcnt;
	output reg ddram_rd;
	output reg ddram_we;
	output wire [63:0] ddram_din;
	output reg [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	localparam ST_IDLE = 3'd0;
	localparam ST_WR = 3'd1;
	localparam ST_RD_REQ = 3'd2;
	localparam ST_RD_RCV = 3'd3;
	localparam ST_WRB = 3'd4;
	reg [2:0] state;
	reg [63:0] ddram_din_r;
	reg [7:0] beat;
	reg [7:0] bcnt;
	assign ddram_din = (state == ST_WRB ? tst_wdata : ddram_din_r);
	assign tst_wnext = (((state == ST_WRB) && ddram_we) && !ddram_busy) && (beat != (bcnt - 8'd1));
	always @(posedge clk)
		if (sdram_por) begin
			state <= ST_IDLE;
			beat <= 8'd0;
			bcnt <= 8'd1;
			ddram_addr <= 29'd0;
			ddram_burstcnt <= 8'd1;
			ddram_rd <= 1'b0;
			ddram_we <= 1'b0;
			ddram_din_r <= 64'd0;
			ddram_be <= 8'hff;
			tst_rdata <= 64'd0;
			tst_rd_valid <= 1'b0;
			tst_busy <= 1'b0;
			tst_wr_done <= 1'b0;
			tst_wr_base <= 26'd0;
			tst_wr_count <= 8'd1;
			tst_wr_last_data <= 64'd0;
		end
		else begin
			ddram_rd <= 1'b0;
			ddram_we <= 1'b0;
			tst_rd_valid <= 1'b0;
			tst_wr_done <= 1'b0;
			case (state)
				ST_IDLE:
					if (tst_wr_req) begin
						ddram_addr <= VRAM_DDR_BASE + {3'd0, tst_addr};
						ddram_be <= tst_be;
						tst_busy <= 1'b1;
						tst_wr_base <= tst_addr;
						tst_wr_count <= (tst_burstcnt == 8'd0 ? 8'd1 : tst_burstcnt);
						if (tst_burstcnt <= 8'd1) begin
							ddram_din_r <= tst_wdata;
							ddram_burstcnt <= 8'd1;
							state <= ST_WR;
						end
						else begin
							ddram_burstcnt <= tst_burstcnt;
							bcnt <= tst_burstcnt;
							beat <= 8'd0;
							state <= ST_WRB;
						end
					end
					else if (tst_rd_req) begin
						ddram_addr <= VRAM_DDR_BASE + {3'd0, tst_addr};
						ddram_burstcnt <= (tst_burstcnt == 8'd0 ? 8'd1 : tst_burstcnt);
						bcnt <= (tst_burstcnt == 8'd0 ? 8'd1 : tst_burstcnt);
						beat <= 8'd0;
						ddram_rd <= 1'b1;
						tst_busy <= 1'b1;
						state <= ST_RD_REQ;
					end
				ST_WR: begin
					ddram_we <= 1'b1;
					if (ddram_we && !ddram_busy) begin
						ddram_we <= 1'b0;
						tst_busy <= 1'b0;
						state <= ST_IDLE;
						tst_wr_last_data <= ddram_din_r;
						tst_wr_done <= 1'b1;
					end
				end
				ST_WRB: begin
					ddram_we <= 1'b1;
					if (ddram_we && !ddram_busy) begin
						if (beat == (bcnt - 8'd1)) begin
							ddram_we <= 1'b0;
							tst_busy <= 1'b0;
							state <= ST_IDLE;
							tst_wr_last_data <= tst_wdata;
							tst_wr_done <= 1'b1;
						end
						beat <= beat + 8'd1;
					end
				end
				ST_RD_REQ:
					if (ddram_busy)
						ddram_rd <= 1'b1;
					else
						state <= ST_RD_RCV;
				ST_RD_RCV:
					if (ddram_dout_ready) begin
						tst_rdata <= ddram_dout;
						tst_rd_valid <= 1'b1;
						if (beat == (bcnt - 8'd1)) begin
							tst_busy <= 1'b0;
							state <= ST_IDLE;
						end
						beat <= beat + 8'd1;
					end
				default: state <= ST_IDLE;
			endcase
		end
endmodule
`default_nettype wire
`default_nettype none
module stv_vram_ddr_top (
	clk,
	rst,
	sdram_por,
	req,
	we,
	widx,
	boff,
	sz,
	wd,
	videobank,
	dma_palette,
	rdata,
	done,
	fb_we,
	fb_addr,
	fb_wdata,
	fb_ack,
	wr_busy,
	dbg_cst,
	erase_start,
	erase_row0,
	erase_lines,
	erase_busy,
	scan_req,
	scan_addr,
	scan_data,
	scan_ack,
	srt_req,
	srt_we,
	srt_entry,
	srt_done,
	srt_e0e1,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready
);
	reg _sv2v_0;
	parameter [0:0] CACHED_FIFO_RUN = 1'b1;
	parameter [0:0] MLAB_WRITE_FIFO = 1'b1;
	parameter signed [31:0] VRAMW = 32'h00040000;
	parameter [28:0] VRAM_DDR_BASE = 29'h06400000;
	parameter signed [31:0] POSTED_WRITE_GUARD = 255;
	input wire clk;
	input wire rst;
	input wire sdram_por;
	input wire req;
	input wire we;
	input wire [27:0] widx;
	input wire [3:0] boff;
	input wire [5:0] sz;
	input wire [31:0] wd;
	input wire videobank;
	input wire [15:0] dma_palette;
	output wire [31:0] rdata;
	output wire done;
	input wire fb_we;
	input wire [18:0] fb_addr;
	input wire [15:0] fb_wdata;
	output reg fb_ack;
	output wire wr_busy;
	output wire [2:0] dbg_cst;
	input wire erase_start;
	input wire [8:0] erase_row0;
	input wire [9:0] erase_lines;
	output wire erase_busy;
	input wire scan_req;
	input wire [18:0] scan_addr;
	output reg [15:0] scan_data;
	output reg scan_ack;
	input wire srt_req;
	input wire srt_we;
	input wire [18:0] srt_entry;
	output reg srt_done;
	output wire [31:0] srt_e0e1;
	output wire [28:0] ddram_addr;
	output wire [7:0] ddram_burstcnt;
	output wire ddram_rd;
	output wire ddram_we;
	output wire [63:0] ddram_din;
	output wire [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	function automatic [7:0] lane_be;
		input [1:0] l;
		case (l)
			2'd0: lane_be = 8'h03;
			2'd1: lane_be = 8'h0c;
			2'd2: lane_be = 8'h30;
			default: lane_be = 8'hc0;
		endcase
	endfunction
	wire [20:0] sd_addr;
	wire [15:0] sd_din;
	wire [1:0] sd_be;
	wire sd_rd;
	wire sd_wr;
	reg [15:0] sd_dout;
	reg sd_ack;
	vram_sdram_top #(
		.VRAMW(VRAMW),
		.SD_AW(21),
		.VRAM_BASE(21'd0)
	) u_acc(
		.clk(clk),
		.rst(rst),
		.req(req),
		.we(we),
		.widx(widx),
		.boff(boff),
		.sz(sz),
		.wd(wd),
		.videobank(videobank),
		.dma_palette(dma_palette),
		.rdata(rdata),
		.done(done),
		.fb_we(1'b0),
		.fb_addr(19'd0),
		.fb_wdata(16'd0),
		.fb_ack(),
		.erase_start(erase_start),
		.erase_row0(erase_row0),
		.erase_lines(erase_lines),
		.erase_busy(erase_busy),
		.scan_req(1'b0),
		.scan_addr(19'd0),
		.scan_data(),
		.scan_ack(),
		.sd_addr(sd_addr),
		.sd_din(sd_din),
		.sd_be(sd_be),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_dout(sd_dout),
		.sd_ack(sd_ack)
	);
	reg a_start;
	reg a_wr;
	reg [25:0] a_addr;
	reg [63:0] a_wdata;
	reg [7:0] a_be;
	reg a_done;
	wire a_rd_valid;
	wire [63:0] a_rdata;
	reg [1:0] a_lane;
	reg [15:0] rmw_din;
	reg [63:0] rmw_beat;
	wire [63:0] rmw_merged = (a_lane == 2'd0 ? {rmw_beat[63:16], rmw_din} : (a_lane == 2'd1 ? {rmw_beat[63:32], rmw_din, rmw_beat[15:0]} : (a_lane == 2'd2 ? {rmw_beat[63:48], rmw_din, rmw_beat[31:0]} : {rmw_din, rmw_beat[47:0]})));
	reg [63:0] fwd_beat;
	reg [25:0] fwd_addr;
	reg fwd_valid;
	reg [63:0] c_fwd;
	reg [16:0] c_fwd_beat;
	reg c_fwd_v;
	wire a_own_fwd_hit = fwd_valid && (fwd_addr == a_addr);
	wire c_to_a_fwd_hit = c_fwd_v && (c_fwd_beat == a_addr[16:0]);
	wire fwd_hit = a_own_fwd_hit || c_to_a_fwd_hit;
	wire [63:0] a_fwd_data = (a_own_fwd_hit ? fwd_beat : c_fwd);
	localparam [2:0] A_IDLE = 3'd0;
	localparam [2:0] A_DRAIN = 3'd1;
	localparam [2:0] A_WAIT = 3'd2;
	localparam [2:0] A_ACK = 3'd3;
	localparam [2:0] A_RMW_RD = 3'd4;
	localparam [2:0] A_RMW_MRG = 3'd5;
	reg [2:0] ats;
	reg a_op_wr;
	wire c_busy;
	reg c_start;
	reg c_wr;
	wire a_block = ats != A_IDLE;
	reg a_rmw_lock;
	always @(posedge clk)
		if (rst) begin
			ats <= A_IDLE;
			a_start <= 1'b0;
			a_wr <= 1'b0;
			a_addr <= 26'd0;
			a_wdata <= 64'd0;
			a_be <= 8'd0;
			a_lane <= 2'd0;
			rmw_din <= 16'd0;
			rmw_beat <= 64'd0;
			sd_ack <= 1'b0;
			sd_dout <= 16'd0;
			fwd_beat <= 64'd0;
			fwd_addr <= 26'd0;
			fwd_valid <= 1'b0;
			a_rmw_lock <= 1'b0;
			a_op_wr <= 1'b0;
		end
		else begin
			sd_ack <= 1'b0;
			if (c_start && c_wr)
				fwd_valid <= 1'b0;
			case (ats)
				A_IDLE:
					if (sd_rd || sd_wr) begin
						a_lane <= sd_addr[1:0];
						a_addr <= {9'd0, sd_addr[18:2]};
						rmw_din <= sd_din;
						a_op_wr <= sd_wr;
						ats <= A_DRAIN;
					end
				A_DRAIN:
					if (!c_busy) begin
						if (!a_op_wr && fwd_hit) begin
							case (a_lane)
								2'd0: sd_dout <= a_fwd_data[15:0];
								2'd1: sd_dout <= a_fwd_data[31:16];
								2'd2: sd_dout <= a_fwd_data[47:32];
								default: sd_dout <= a_fwd_data[63:48];
							endcase
							sd_ack <= 1'b1;
							ats <= A_ACK;
						end
						else if (!a_op_wr) begin
							a_wr <= 1'b0;
							a_start <= 1'b1;
							ats <= A_WAIT;
						end
						else if (fwd_hit) begin
							rmw_beat <= a_fwd_data;
							a_rmw_lock <= 1'b1;
							ats <= A_RMW_MRG;
						end
						else begin
							a_wr <= 1'b0;
							a_start <= 1'b1;
							a_rmw_lock <= 1'b1;
							ats <= A_RMW_RD;
						end
					end
				A_WAIT: begin
					if (a_rd_valid)
						case (a_lane)
							2'd0: sd_dout <= a_rdata[15:0];
							2'd1: sd_dout <= a_rdata[31:16];
							2'd2: sd_dout <= a_rdata[47:32];
							default: sd_dout <= a_rdata[63:48];
						endcase
					if (a_done) begin
						a_start <= 1'b0;
						a_wr <= 1'b0;
						a_rmw_lock <= 1'b0;
						sd_ack <= 1'b1;
						ats <= A_ACK;
					end
				end
				A_RMW_RD: begin
					if (a_rd_valid)
						rmw_beat <= a_rdata;
					if (a_done) begin
						a_start <= 1'b0;
						a_rmw_lock <= 1'b1;
						ats <= A_RMW_MRG;
					end
				end
				A_RMW_MRG: begin
					a_wdata <= rmw_merged;
					a_be <= 8'hff;
					a_wr <= 1'b1;
					a_start <= 1'b1;
					ats <= A_WAIT;
					fwd_beat <= rmw_merged;
					fwd_addr <= a_addr;
					fwd_valid <= 1'b1;
				end
				A_ACK: ats <= A_IDLE;
				default: ats <= A_IDLE;
			endcase
		end
	(* ramstyle = "no_rw_check" *) reg [63:0] rc [0:127];
	reg [9:0] rc_row;
	reg rc_valid;
	reg [9:0] b_fill_row;
	reg b_fill_dirty;
	wire cache_wr_evt;
	wire [9:0] cache_wr_row0;
	wire [9:0] cache_wr_row1;
	wire rc_write_hit = cache_wr_evt && ((rc_row == cache_wr_row0) || (rc_row == cache_wr_row1));
	wire fill_write_hit = cache_wr_evt && ((b_fill_row == cache_wr_row0) || (b_fill_row == cache_wr_row1));
	wire [9:0] req_row = scan_addr[18:9];
	wire [8:0] req_col = scan_addr[8:0];
	reg [63:0] rc_q;
	wire [6:0] rc_raddr = req_col[8:2];
	reg [1:0] rc_rlane;
	always @(posedge clk) rc_q <= rc[rc_raddr];
	reg b_start;
	reg [25:0] b_addr;
	reg [7:0] b_burstlen;
	reg b_done;
	wire b_rd_valid;
	wire [63:0] b_rdata;
	reg [7:0] fillbeat;
	localparam [7:0] BMAX = 8'd32;
	localparam [2:0] B_IDLE = 3'd0;
	localparam [2:0] B_REQ = 3'd1;
	localparam [2:0] B_FILL = 3'd2;
	localparam [2:0] B_HIT = 3'd3;
	localparam [2:0] B_WAIT = 3'd4;
	reg [2:0] bts;
	wire pocket_scan_available = ((rc_valid && !rc_write_hit) && (rc_row == req_row)) || ((((((bts == B_REQ) || (bts == B_FILL)) && !b_fill_dirty) && !fill_write_hit) && (b_fill_row == req_row)) && (fillbeat > {1'b0, req_col[8:2]}));
	reg [1:0] pocket_scan_state;
	reg [18:0] pocket_scan_addr;
	always @(posedge clk)
		if (rst) begin
			pocket_scan_state <= 0;
			pocket_scan_addr <= 0;
			scan_ack <= 0;
			scan_data <= 0;
		end
		else begin
			scan_ack <= 0;
			case (pocket_scan_addr[1:0])
				0: scan_data <= rc_q[15:0];
				1: scan_data <= rc_q[31:16];
				2: scan_data <= rc_q[47:32];
				3: scan_data <= rc_q[63:48];
			endcase
			case (pocket_scan_state)
				0:
					if (scan_req && pocket_scan_available) begin
						pocket_scan_addr <= scan_addr;
						pocket_scan_state <= 1;
					end
				1:
					if ((scan_req && (scan_addr == pocket_scan_addr)) && pocket_scan_available) begin
						scan_ack <= 1;
						pocket_scan_state <= 2;
					end
					else
						pocket_scan_state <= 0;
				2:
					if (!scan_req)
						pocket_scan_state <= 0;
				default: pocket_scan_state <= 0;
			endcase
		end
	always @(posedge clk)
		if (rst) begin
			bts <= B_IDLE;
			b_start <= 1'b0;
			b_addr <= 26'd0;
			b_burstlen <= 8'd0;
			rc_valid <= 1'b0;
			rc_row <= 10'd0;
			b_fill_row <= 10'd0;
			b_fill_dirty <= 1'b0;
			fillbeat <= 8'd0;
			rc_rlane <= 2'd0;
		end
		else begin
			case (bts)
				B_IDLE:
					if (scan_req) begin
						if ((!rc_valid || rc_write_hit) || (rc_row != req_row)) begin
							fillbeat <= 8'd0;
							b_fill_row <= req_row;
							b_fill_dirty <= 1'b0;
							bts <= B_REQ;
						end
					end
				B_REQ: begin
					b_addr <= {9'd0, b_fill_row, 7'd0} + {18'd0, fillbeat};
					b_burstlen <= ((8'd128 - fillbeat) > BMAX ? BMAX : 8'd128 - fillbeat);
					b_start <= 1'b1;
					bts <= B_FILL;
				end
				B_FILL: begin
					if (b_rd_valid) begin
						rc[fillbeat[6:0]] <= b_rdata;
						fillbeat <= fillbeat + 8'd1;
					end
					if (b_done) begin
						b_start <= 1'b0;
						if (fillbeat >= 8'd128) begin
							if (b_fill_dirty || fill_write_hit)
								rc_valid <= 1'b0;
							else begin
								rc_valid <= 1'b1;
								rc_row <= b_fill_row;
							end
							bts <= B_IDLE;
						end
						else
							bts <= B_REQ;
					end
				end
				default: bts <= B_IDLE;
			endcase
			if (rc_write_hit)
				rc_valid <= 1'b0;
			if (((bts == B_REQ) || (bts == B_FILL)) && fill_write_hit)
				b_fill_dirty <= 1'b1;
		end
	(* ramstyle = "no_rw_check" *) reg [63:0] dbuf [0:255];
	reg [16:0] d_base_beat;
	reg d_op_we;
	reg [8:0] d_fill;
	reg d_start;
	reg d_wr;
	reg [25:0] d_addr;
	reg [7:0] d_blen;
	reg d_done;
	wire d_rd_valid;
	reg [63:0] dbuf_q;
	wire d_burst_next;
	reg [31:0] srt_e0e1_r;
	assign srt_e0e1 = srt_e0e1_r;
	localparam [2:0] D_IDLE = 3'd0;
	localparam [2:0] D_DRAIN = 3'd1;
	localparam [2:0] D_RREQ = 3'd2;
	localparam [2:0] D_RFILL = 3'd3;
	localparam [2:0] D_WREQ = 3'd4;
	localparam [2:0] D_WSTREAM = 3'd5;
	localparam [2:0] D_FIN = 3'd6;
	reg [2:0] dst;
	wire d_block = dst != D_IDLE;
	wire d_cache_wr_evt = d_start && d_wr;
	reg [16:0] wc_beat;
	reg [3:0] wc_mask;
	reg [63:0] wc_data;
	reg [7:0] wc_idle;
	localparam [7:0] FB_WFLUSH_IDLE = 8'd64;
	reg fb_we_d;
	reg fb_pend;
	wire [16:0] fb_beat = fb_addr[18:2];
	wire fb_same = (wc_mask != 4'd0) && (fb_beat == wc_beat);
	wire fb_new = fb_we & ~fb_we_d;
	wire fb_req = fb_new | fb_pend;
	wire wc_flush_req = (wc_mask != 4'd0) && ((((fb_req && !fb_same) || (wc_idle >= FB_WFLUSH_IDLE)) || a_block) || d_block);
	reg [25:0] c_addr;
	reg [63:0] c_wdata;
	reg [7:0] c_be;
	reg c_done;
	wire c_rd_valid;
	wire [63:0] c_rdata;
	reg [3:0] cf_mask;
	reg [63:0] cf_data;
	reg [16:0] cf_beat;
	localparam [2:0] C_IDLE = 3'd0;
	localparam [2:0] C_RD = 3'd1;
	localparam [2:0] C_MRG = 3'd2;
	localparam [2:0] C_WR = 3'd3;
	localparam [2:0] C_BURST = 3'd4;
	reg [2:0] cst;
	localparam signed [31:0] WF_DEPTH = 16;
	localparam signed [31:0] WF_AW = 4;
	reg [3:0] wf_mask [0:15];
	reg [16:0] wf_beat [0:15];
	reg [63:0] wf_data [0:15];
	localparam [0:0] USE_MLAB_FIFO = MLAB_WRITE_FIFO && CACHED_FIFO_RUN;
	(* ramstyle = "MLAB, no_rw_check" *) reg [80:0] wf_payload [0:15];
	reg wf_up [0:15];
	reg wf_down [0:15];
	reg [16:0] wf_last_beat;
	reg wf_last_full;
	reg [WF_AW:0] wf_wptr;
	reg [WF_AW:0] wf_rptr;
	wire wf_empty = wf_wptr == wf_rptr;
	wire wf_full = (wf_wptr[3:0] == wf_rptr[3:0]) && (wf_wptr[WF_AW] != wf_rptr[WF_AW]);
	assign c_busy = ((cst != C_IDLE) || (wc_mask != 4'd0)) || !wf_empty;
	assign wr_busy = ((c_busy || sd_wr) || (a_block && a_op_wr)) || (d_block && d_op_we);
	assign dbg_cst = cst;
	function automatic [63:0] lane_merge;
		input [63:0] base;
		input [63:0] neu;
		input [3:0] m;
		lane_merge = {(m[3] ? neu[63:48] : base[63:48]), (m[2] ? neu[47:32] : base[47:32]), (m[1] ? neu[31:16] : base[31:16]), (m[0] ? neu[15:0] : base[15:0])};
	endfunction
	wire [3:0] wf_wp = wf_wptr[3:0];
	wire [3:0] wf_rp = wf_rptr[3:0];
	wire same_or_empty = (wc_mask == 4'd0) || fb_same;
	reg c_is_burst;
	reg [7:0] c_blen;
	reg [16:0] c_burst_last_r;
	reg [25:0] c_burst_addr;
	reg c_dir;
	reg [3:0] c_bp;
	reg [7:0] wf_idle;
	wire [WF_AW:0] wf_occ = wf_wptr - wf_rptr;
	wire [3:0] wf_payload_raddr = (cst == C_BURST ? c_bp : wf_rp);
	wire [80:0] wf_payload_q = wf_payload[wf_payload_raddr];
	wire wf_accept_pixel = ((fb_req && !a_block) && !d_block) && same_or_empty;
	wire wf_payload_push = (((!rst && !wf_accept_pixel) && (wc_mask != 0)) && !wf_full) && ((((((fb_req && !a_block) && !d_block) && !fb_same) || (wc_idle >= FB_WFLUSH_IDLE)) || a_block) || d_block);
	always @(posedge clk)
		if (USE_MLAB_FIFO && wf_payload_push)
			wf_payload[wf_wp] <= {wc_beat, wc_data};
	wire [63:0] c_burst_data = (USE_MLAB_FIFO ? wf_payload_q[63:0] : wf_data[c_bp]);
	wire c_burst_next;
	wire a_cache_wr_evt = a_start && a_wr;
	wire c_cache_wr_evt = c_start && c_wr;
	wire [16:0] c_cache_first = (c_is_burst ? c_burst_addr[16:0] : c_addr[16:0]);
	wire [16:0] c_cache_last = (c_is_burst ? c_burst_last_r : c_addr[16:0]);
	assign cache_wr_evt = (a_cache_wr_evt || c_cache_wr_evt) || d_cache_wr_evt;
	assign cache_wr_row0 = (a_cache_wr_evt ? a_addr[16:7] : (d_cache_wr_evt ? d_base_beat[16:7] : c_cache_first[16:7]));
	assign cache_wr_row1 = (a_cache_wr_evt ? a_addr[16:7] : (d_cache_wr_evt ? d_base_beat[16:7] + 10'd1 : c_cache_last[16:7]));
	wire head_full = wf_mask[wf_rp] == 4'hf;
	wire pair_asc = ((wf_occ >= 2) && head_full) && (CACHED_FIFO_RUN ? wf_up[wf_rp + 1'b1] : (wf_mask[wf_rp + 1'b1] == 4'hf) && (wf_beat[wf_rp + 1'b1] == (wf_beat[wf_rp] + 17'd1)));
	wire pair_desc = ((wf_occ >= 2) && head_full) && (CACHED_FIFO_RUN ? wf_down[wf_rp + 1'b1] : (wf_mask[wf_rp + 1'b1] == 4'hf) && (wf_beat[wf_rp + 1'b1] == (wf_beat[wf_rp] - 17'd1)));
	localparam signed [31:0] SCAN_MAX = 4;
	reg [7:0] run_len;
	reg [3:0] cons;
	integer k;
	always @(*) begin
		if (_sv2v_0)
			;
		if (CACHED_FIFO_RUN) begin
			cons[0] = (wf_occ != 0) && head_full;
			for (k = 1; k < SCAN_MAX; k = k + 1)
				cons[k] = (cons[k - 1] && (k < wf_occ)) && (pair_asc ? wf_up[wf_rp + k[3:0]] : pair_desc && wf_down[wf_rp + k[3:0]]);
		end
		else
			for (k = 0; k < SCAN_MAX; k = k + 1)
				cons[k] = ((k < wf_occ) && (wf_mask[wf_rp + k[3:0]] == 4'hf)) && (pair_asc ? wf_beat[wf_rp + k[3:0]] == (wf_beat[wf_rp] + k[16:0]) : (pair_desc ? wf_beat[wf_rp + k[3:0]] == (wf_beat[wf_rp] - k[16:0]) : k == 0));
		casez (cons)
			4'bzzz0: run_len = 8'd0;
			4'bzz01: run_len = 8'd1;
			4'bz011: run_len = 8'd2;
			4'b0111: run_len = 8'd3;
			default: run_len = 8'd4;
		endcase
	end
	wire wf_nearfull = wf_occ >= 12;
	reg [63:0] hd_data;
	reg [16:0] hd_beat;
	reg [3:0] hd_mask;
	reg [7:0] run_len_r;
	reg pair_asc_r;
	reg pair_desc_r;
	reg [WF_AW:0] wf_rptr_q;
	reg wf_ne_q;
	wire c_own_fwd_hit = c_fwd_v && (c_fwd_beat == hd_beat);
	wire a_to_c_fwd_hit = fwd_valid && (fwd_addr[16:0] == hd_beat);
	wire [63:0] c_fwd_data = (c_own_fwd_hit ? c_fwd : fwd_beat);
	wire hd_full = hd_mask == 4'hf;
	wire hd_valid = (!wf_empty && (wf_rptr == wf_rptr_q)) && wf_ne_q;
	wire drain_go_r = (hd_full ? ((((run_len_r < wf_occ) || wf_nearfull) || (wf_idle >= FB_WFLUSH_IDLE)) || a_block) || d_block : 1'b1);
	always @(posedge clk)
		if (rst) begin
			wc_beat <= 17'd0;
			wc_mask <= 4'd0;
			wc_data <= 64'd0;
			wc_idle <= 8'd0;
			fb_we_d <= 1'b0;
			fb_ack <= 1'b0;
			fb_pend <= 1'b0;
			c_start <= 1'b0;
			c_wr <= 1'b0;
			c_addr <= 26'd0;
			c_wdata <= 64'd0;
			c_be <= 8'd0;
			c_fwd <= 64'd0;
			c_fwd_beat <= 17'd0;
			c_fwd_v <= 1'b0;
			cf_mask <= 4'd0;
			cf_data <= 64'd0;
			cf_beat <= 17'd0;
			cst <= C_IDLE;
			wf_wptr <= 0;
			wf_rptr <= 0;
			wf_last_beat <= 0;
			wf_last_full <= 0;
			c_is_burst <= 1'b0;
			c_burst_last_r <= 17'd0;
			c_blen <= 8'd1;
			c_burst_addr <= 26'd0;
			c_dir <= 1'b0;
			c_bp <= 0;
			wf_idle <= 8'd0;
			hd_data <= 64'd0;
			hd_beat <= 17'd0;
			hd_mask <= 4'd0;
			run_len_r <= 8'd0;
			pair_asc_r <= 1'b0;
			pair_desc_r <= 1'b0;
			wf_rptr_q <= 0;
			wf_ne_q <= 1'b0;
		end
		else begin
			fb_ack <= 1'b0;
			fb_we_d <= fb_we;
			if (a_start && a_wr)
				c_fwd_v <= 1'b0;
			hd_data <= (USE_MLAB_FIFO ? wf_payload_q[63:0] : wf_data[wf_rp]);
			hd_beat <= (USE_MLAB_FIFO ? wf_payload_q[80:64] : wf_beat[wf_rp]);
			hd_mask <= wf_mask[wf_rp];
			run_len_r <= run_len;
			pair_asc_r <= pair_asc;
			pair_desc_r <= pair_desc;
			wf_rptr_q <= wf_rptr;
			wf_ne_q <= !wf_empty;
			if ((wc_mask != 4'd0) && (wc_idle != 8'hff))
				wc_idle <= wc_idle + 8'd1;
			if (wf_idle != 8'hff)
				wf_idle <= wf_idle + 8'd1;
			if (fb_new)
				fb_pend <= 1'b1;
			if (((fb_req && !a_block) && !d_block) && same_or_empty) begin
				fb_pend <= 1'b0;
				fb_ack <= 1'b1;
				wc_idle <= 8'd0;
				wc_beat <= fb_beat;
				wc_mask[fb_addr[1:0]] <= 1'b1;
				wc_data[fb_addr[1:0] * 16+:16] <= fb_wdata;
			end
			else if (((((fb_req && !a_block) && !d_block) && (wc_mask != 4'd0)) && !fb_same) && !wf_full) begin
				wf_mask[wf_wp] <= wc_mask;
				if (!USE_MLAB_FIFO) begin
					wf_beat[wf_wp] <= wc_beat;
					wf_data[wf_wp] <= wc_data;
				end
				if (CACHED_FIFO_RUN) begin
					wf_up[wf_wp] <= (wf_last_full && &wc_mask) && (wc_beat == (wf_last_beat + 17'd1));
					wf_down[wf_wp] <= (wf_last_full && &wc_mask) && (wc_beat == (wf_last_beat - 17'd1));
					wf_last_beat <= wc_beat;
					wf_last_full <= &wc_mask;
				end
				wf_wptr <= wf_wptr + 1'b1;
				wf_idle <= 8'd0;
				fb_pend <= 1'b0;
				fb_ack <= 1'b1;
				wc_idle <= 8'd0;
				wc_beat <= fb_beat;
				wc_mask <= 4'd1 << fb_addr[1:0];
				wc_data[fb_addr[1:0] * 16+:16] <= fb_wdata;
			end
			else if (((wc_mask != 4'd0) && !wf_full) && (((wc_idle >= FB_WFLUSH_IDLE) || a_block) || d_block)) begin
				wf_mask[wf_wp] <= wc_mask;
				if (!USE_MLAB_FIFO) begin
					wf_beat[wf_wp] <= wc_beat;
					wf_data[wf_wp] <= wc_data;
				end
				if (CACHED_FIFO_RUN) begin
					wf_up[wf_wp] <= (wf_last_full && &wc_mask) && (wc_beat == (wf_last_beat + 17'd1));
					wf_down[wf_wp] <= (wf_last_full && &wc_mask) && (wc_beat == (wf_last_beat - 17'd1));
					wf_last_beat <= wc_beat;
					wf_last_full <= &wc_mask;
				end
				wf_wptr <= wf_wptr + 1'b1;
				wf_idle <= 8'd0;
				wc_mask <= 4'd0;
			end
			if (cst == C_IDLE)
				c_wdata <= (hd_full ? hd_data : lane_merge(c_fwd_data, hd_data, hd_mask));
			if (((cst == C_IDLE) && hd_valid) && drain_go_r) begin
				if (hd_full) begin
					if (run_len_r >= 8'd2) begin
						c_blen <= run_len_r;
						c_is_burst <= 1'b1;
						c_wr <= 1'b1;
						c_start <= 1'b1;
						cst <= C_BURST;
						c_fwd_v <= 1'b0;
						if (pair_asc_r) begin
							c_dir <= 1'b0;
							c_bp <= wf_rp;
							c_burst_addr <= {9'd0, hd_beat};
							c_burst_last_r <= (hd_beat + {9'd0, run_len_r}) - 17'd1;
						end
						else begin
							c_dir <= 1'b1;
							c_bp <= (wf_rp + run_len_r[3:0]) - 1'b1;
							c_burst_addr <= {9'd0, hd_beat - ({9'd0, run_len_r} - 17'd1)};
							c_burst_last_r <= hd_beat;
						end
					end
					else begin
						wf_rptr <= wf_rptr + 1'b1;
						c_addr <= {9'd0, hd_beat};
						c_be <= 8'hff;
						c_wr <= 1'b1;
						c_start <= 1'b1;
						cst <= C_WR;
						c_fwd <= hd_data;
						c_fwd_beat <= hd_beat;
						c_fwd_v <= 1'b1;
					end
				end
				else if (c_own_fwd_hit || a_to_c_fwd_hit) begin
					cf_mask <= hd_mask;
					cf_data <= hd_data;
					cf_beat <= hd_beat;
					wf_rptr <= wf_rptr + 1'b1;
					c_addr <= {9'd0, hd_beat};
					c_be <= 8'hff;
					c_wr <= 1'b1;
					c_start <= 1'b1;
					cst <= C_WR;
					c_fwd <= lane_merge(c_fwd_data, hd_data, hd_mask);
					c_fwd_beat <= hd_beat;
					c_fwd_v <= 1'b1;
				end
				else begin
					cf_mask <= hd_mask;
					cf_data <= hd_data;
					cf_beat <= hd_beat;
					wf_rptr <= wf_rptr + 1'b1;
					c_addr <= {9'd0, hd_beat};
					c_wr <= 1'b0;
					c_start <= 1'b1;
					cst <= C_RD;
				end
			end
			case (cst)
				C_RD: begin
					if (c_rd_valid)
						c_wdata <= lane_merge(c_rdata, cf_data, cf_mask);
					if (c_done) begin
						c_start <= 1'b0;
						cst <= C_MRG;
					end
				end
				C_MRG: begin
					c_addr <= {9'd0, cf_beat};
					c_be <= 8'hff;
					c_wr <= 1'b1;
					c_start <= 1'b1;
					c_fwd <= c_wdata;
					c_fwd_beat <= cf_beat;
					c_fwd_v <= 1'b1;
					cst <= C_WR;
				end
				C_WR:
					if (c_done) begin
						c_start <= 1'b0;
						c_wr <= 1'b0;
						cst <= C_IDLE;
					end
				C_BURST: begin
					if (c_burst_next)
						c_bp <= (c_dir ? c_bp - 1'b1 : c_bp + 1'b1);
					if (c_done) begin
						c_start <= 1'b0;
						c_wr <= 1'b0;
						c_is_burst <= 1'b0;
						wf_rptr <= wf_rptr + {1'b0, c_blen[3:0]};
						c_fwd <= c_burst_data;
						c_fwd_beat <= c_burst_last_r;
						c_fwd_v <= 1'b1;
						cst <= C_IDLE;
					end
				end
				default:
					;
			endcase
		end
	reg tst_wr_req;
	reg tst_rd_req;
	reg [25:0] tst_addr;
	reg [63:0] tst_wdata_lat;
	wire [63:0] tst_rdata;
	wire [63:0] tst_wdata;
	wire tst_wnext;
	reg [7:0] tst_be;
	reg [7:0] tst_burstcnt;
	wire tst_rd_valid;
	wire tst_busy;
	wire tst_wr_done;
	wire [25:0] tst_wr_base;
	wire [7:0] tst_wr_count;
	wire [63:0] tst_wr_last_data;
	reg [2:0] l_gnt;
	localparam [1:0] L_IDLE = 2'd0;
	localparam [1:0] L_ACCEPT = 2'd1;
	localparam [1:0] L_RUN = 2'd2;
	localparam [1:0] L_DONE = 2'd3;
	reg [1:0] ls;
	reg l_write;
	reg l_burst_write;
	reg [7:0] posted_guard;
	reg [16:0] posted_base;
	reg [16:0] posted_last;
	reg [3:0] scan_dirty;
	reg [16:0] scan_fence_addr [0:3];
	reg [63:0] scan_fence_expect [0:3];
	reg [1:0] scan_fence_page;
	wire [16:0] retired_write_base = tst_wr_base[16:0];
	wire [16:0] retired_write_last = (tst_wr_base[16:0] + {{9 {1'b0}}, tst_wr_count}) - 17'd1;
	wire [1:0] retired_page_first = retired_write_base[16:15];
	wire [1:0] retired_page_last = retired_write_last[16:15];
	wire [3:0] retired_page_mask = (4'b0001 << retired_page_first) | (4'b0001 << retired_page_last);
	wire fence_complete_evt = ((ls == L_RUN) && !tst_busy) && (l_gnt == 3'd3);
	wire fence_match_evt = (fence_complete_evt && tst_rd_valid) && (tst_rdata == scan_fence_expect[scan_fence_page]);
	localparam signed [31:0] LEGACY_SCAN_POSTED_GUARD = 2047;
	localparam signed [31:0] LEGACY_SCAN_GW = 11;
	localparam [10:0] LEGACY_SCAN_GUARD_RELOAD = LEGACY_SCAN_POSTED_GUARD;
	reg [10:0] scan_legacy_guard [0:3];
	wire [16:0] completed_burst_base = tst_addr[16:0];
	wire [16:0] completed_burst_last = (tst_addr[16:0] + {{9 {1'b0}}, tst_burstcnt}) - 17'd1;
	wire a_posted_hazard = ((posted_guard != 8'd0) && (a_addr[16:0] >= posted_base)) && (a_addr[16:0] <= posted_last);
	wire c_posted_hazard = ((posted_guard != 8'd0) && (c_addr[16:0] >= posted_base)) && (c_addr[16:0] <= posted_last);
	wire b_publication_pending = scan_dirty[b_fill_row[9:8]];
	wire b_retire_collision = tst_wr_done && retired_page_mask[b_fill_row[9:8]];
	assign tst_wdata = ((l_gnt == 3'd2) && c_is_burst ? c_burst_data : (l_gnt == 3'd4 ? dbuf_q : tst_wdata_lat));
	assign c_burst_next = (((l_gnt == 3'd2) && c_is_burst) && (ls == L_RUN)) && tst_wnext;
	assign d_burst_next = ((l_gnt == 3'd4) && (ls == L_RUN)) && tst_wnext;
	wire issue_slot = (ls == L_IDLE) && !tst_busy;
	wire a_eligible = a_start && (a_wr || !a_posted_hazard);
	wire c_eligible = c_start && (c_wr || !c_posted_hazard);
	wire grant_fence = ((issue_slot && b_start) && !b_retire_collision) && b_publication_pending;
	wire grant_b = ((issue_slot && b_start) && !b_retire_collision) && !b_publication_pending;
	wire grant_c = ((issue_slot && !b_start) && !a_rmw_lock) && c_eligible;
	wire grant_d = (((issue_slot && !b_start) && !a_rmw_lock) && !c_eligible) && d_start;
	wire grant_a = ((issue_slot && !b_start) && a_eligible) && (a_rmw_lock || ((!c_eligible && !d_start) && !c_busy));
	wire grant_any = (((grant_a || grant_b) || grant_c) || grant_d) || grant_fence;
	wire grant_c_burst = grant_c && c_is_burst;
	wire grant_c_single = grant_c && !c_is_burst;
	wire grant_write = ((grant_a && a_wr) || (grant_c && (c_is_burst || c_wr))) || (grant_d && d_wr);
	wire [25:0] issue_addr = ((((({26 {grant_a}} & a_addr) | ({26 {grant_b}} & b_addr)) | ({26 {grant_c_single}} & c_addr)) | ({26 {grant_c_burst}} & c_burst_addr)) | ({26 {grant_d}} & d_addr)) | ({26 {grant_fence}} & {9'd0, scan_fence_addr[b_fill_row[9:8]]});
	wire [7:0] issue_length = ((({8 {(grant_a || grant_c_single) || grant_fence}} & 8'd1) | ({8 {grant_b}} & b_burstlen)) | ({8 {grant_c_burst}} & c_blen)) | ({8 {grant_d}} & d_blen);
	integer pg;
	always @(posedge clk)
		if (sdram_por) begin
			scan_dirty <= 4'b0000;
			for (pg = 0; pg < 4; pg = pg + 1)
				begin
					scan_fence_addr[pg] <= 17'd0;
					scan_fence_expect[pg] <= 64'd0;
					scan_legacy_guard[pg] <= {LEGACY_SCAN_GW {1'b0}};
				end
		end
		else begin
			for (pg = 0; pg < 4; pg = pg + 1)
				if (|scan_legacy_guard[pg])
					scan_legacy_guard[pg] <= scan_legacy_guard[pg] - 1'b1;
			if (fence_match_evt)
				scan_dirty[scan_fence_page] <= 1'b0;
			if (tst_wr_done) begin
				for (pg = 0; pg < 4; pg = pg + 1)
					if (scan_dirty[pg] || retired_page_mask[pg]) begin
						scan_dirty[pg] <= 1'b1;
						scan_fence_addr[pg] <= retired_write_last;
						scan_fence_expect[pg] <= tst_wr_last_data;
						if (retired_page_mask[pg])
							scan_legacy_guard[pg] <= LEGACY_SCAN_GUARD_RELOAD;
					end
			end
		end
	always @(posedge clk)
		if (rst) begin
			ls <= L_IDLE;
			l_gnt <= 3'd0;
			l_write <= 1'b0;
			l_burst_write <= 1'b0;
			posted_guard <= 8'd0;
			posted_base <= 17'd0;
			posted_last <= 17'd0;
			scan_fence_page <= 2'd0;
			tst_rd_req <= 1'b0;
			tst_wr_req <= 1'b0;
			tst_addr <= 26'd0;
			tst_wdata_lat <= 64'd0;
			tst_be <= 8'd0;
			tst_burstcnt <= 8'd1;
			a_done <= 1'b0;
			b_done <= 1'b0;
		end
		else begin
			tst_rd_req <= 1'b0;
			tst_wr_req <= 1'b0;
			a_done <= 1'b0;
			b_done <= 1'b0;
			c_done <= 1'b0;
			d_done <= 1'b0;
			if (posted_guard != 8'd0)
				posted_guard <= posted_guard - 8'd1;
			if (issue_slot)
				tst_wdata_lat <= (((!a_rmw_lock && c_start) && !c_is_burst) && c_wr ? c_wdata : a_wdata);
			case (ls)
				L_IDLE:
					if (grant_any) begin
						l_gnt <= ((({3 {grant_b}} & 3'd1) | ({3 {grant_c}} & 3'd2)) | ({3 {grant_fence}} & 3'd3)) | ({3 {grant_d}} & 3'd4);
						l_write <= grant_write;
						l_burst_write <= grant_c_burst || (grant_d && d_wr);
						tst_addr <= issue_addr;
						tst_burstcnt <= issue_length;
						tst_wr_req <= grant_write;
						tst_rd_req <= !grant_write;
						if (grant_fence)
							scan_fence_page <= b_fill_row[9:8];
						if (grant_a && a_wr)
							tst_be <= a_be;
						if (grant_c_single && c_wr)
							tst_be <= c_be;
						if (grant_c_burst || (grant_d && d_wr))
							tst_be <= 8'hff;
						ls <= L_ACCEPT;
					end
				L_ACCEPT:
					if (tst_busy)
						ls <= L_RUN;
				L_RUN:
					if (!tst_busy) begin
						if (l_gnt == 3'd1)
							b_done <= 1'b1;
						else if (l_gnt == 3'd2)
							c_done <= 1'b1;
						else if (l_gnt == 3'd0)
							a_done <= 1'b1;
						else if (l_gnt == 3'd4)
							d_done <= 1'b1;
						if (l_write && l_burst_write) begin
							posted_guard <= POSTED_WRITE_GUARD[7:0];
							if (posted_guard != 8'd0) begin
								posted_base <= (completed_burst_base < posted_base ? completed_burst_base : posted_base);
								posted_last <= (completed_burst_last > posted_last ? completed_burst_last : posted_last);
							end
							else begin
								posted_base <= completed_burst_base;
								posted_last <= completed_burst_last;
							end
						end
						ls <= L_DONE;
					end
				L_DONE: ls <= L_IDLE;
				default: ls <= L_IDLE;
			endcase
		end
	assign a_rd_valid = ((l_gnt == 3'd0) && (ls == L_RUN)) && tst_rd_valid;
	assign b_rd_valid = ((l_gnt == 3'd1) && (ls == L_RUN)) && tst_rd_valid;
	assign c_rd_valid = ((l_gnt == 3'd2) && (ls == L_RUN)) && tst_rd_valid;
	assign d_rd_valid = ((l_gnt == 3'd4) && (ls == L_RUN)) && tst_rd_valid;
	assign a_rdata = tst_rdata;
	assign b_rdata = tst_rdata;
	assign c_rdata = tst_rdata;
	wire srt_go = srt_req;
	wire [8:0] d_fill_rd_n = d_fill + (d_rd_valid ? 9'd1 : 9'd0);
	wire [7:0] dbuf_ra = (d_burst_next ? d_fill[7:0] + 8'd1 : d_fill[7:0]);
	always @(posedge clk) dbuf_q <= dbuf[dbuf_ra];
	always @(posedge clk)
		if (d_rd_valid && !d_op_we)
			dbuf[d_fill[7:0]] <= tst_rdata;
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			dst <= D_IDLE;
			d_start <= 1'b0;
			d_wr <= 1'b0;
			d_addr <= 26'd0;
			d_blen <= 8'd1;
			d_fill <= 9'd0;
			d_base_beat <= 17'd0;
			d_op_we <= 1'b0;
			srt_done <= 1'b0;
			srt_e0e1_r <= 32'd0;
		end
		else begin
			srt_done <= 1'b0;
			case (dst)
				D_IDLE:
					if (srt_go) begin
						d_base_beat <= srt_entry[18:2];
						d_op_we <= srt_we;
						d_fill <= 9'd0;
						dst <= D_DRAIN;
					end
				D_DRAIN:
					if ((!c_busy && (ats == A_IDLE)) && (d_op_we || (posted_guard == 8'd0)))
						dst <= (d_op_we ? D_WREQ : D_RREQ);
				D_RREQ: begin
					d_addr <= {9'd0, d_base_beat} + {17'd0, d_fill};
					d_blen <= ((9'd256 - d_fill) > 9'h020 ? BMAX : sv2v_cast_8(9'd256 - d_fill));
					d_wr <= 1'b0;
					d_start <= 1'b1;
					dst <= D_RFILL;
				end
				D_RFILL: begin
					if (d_rd_valid) begin
						if (d_fill == 9'd0)
							srt_e0e1_r <= tst_rdata[31:0];
						d_fill <= d_fill_rd_n;
					end
					if (d_done) begin
						d_start <= 1'b0;
						dst <= (d_fill_rd_n >= 9'd256 ? D_FIN : D_RREQ);
					end
				end
				D_WREQ: begin
					d_addr <= {9'd0, d_base_beat} + {17'd0, d_fill};
					d_blen <= ((9'd256 - d_fill) > 9'h020 ? BMAX : sv2v_cast_8(9'd256 - d_fill));
					d_wr <= 1'b1;
					d_start <= 1'b1;
					dst <= D_WSTREAM;
				end
				D_WSTREAM: begin
					if (d_burst_next)
						d_fill <= d_fill + 9'd1;
					if (d_done) begin
						d_start <= 1'b0;
						d_wr <= 1'b0;
						d_fill <= d_fill + 9'd1;
						dst <= ((d_fill + 9'd1) >= 9'd256 ? D_FIN : D_WREQ);
					end
				end
				D_FIN: begin
					srt_done <= 1'b1;
					dst <= D_IDLE;
				end
				default: dst <= D_IDLE;
			endcase
		end
	stv_vram_ddr_agent #(.VRAM_DDR_BASE(VRAM_DDR_BASE)) u_agent(
		.clk(clk),
		.sdram_por(sdram_por),
		.tst_wr_req(tst_wr_req),
		.tst_rd_req(tst_rd_req),
		.tst_addr(tst_addr),
		.tst_wdata(tst_wdata),
		.tst_be(tst_be),
		.tst_burstcnt(tst_burstcnt),
		.tst_rdata(tst_rdata),
		.tst_rd_valid(tst_rd_valid),
		.tst_busy(tst_busy),
		.tst_wnext(tst_wnext),
		.tst_wr_done(tst_wr_done),
		.tst_wr_base(tst_wr_base),
		.tst_wr_count(tst_wr_count),
		.tst_wr_last_data(tst_wr_last_data),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_be(ddram_be),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready)
	);
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_gfx_ddr_top (
	clk,
	rst,
	sdram_por,
	src_req,
	src_addr,
	src_active,
	src_stream,
	src_data,
	src_ack,
	dcs_safe,
	cg_req,
	cg_addr,
	cg_data,
	cg_ack,
	dl_wr,
	dl_addr,
	dl_data,
	dl_ack,
	dl_idle,
	dbg_wbeats,
	dbg_srd,
	dbg_cgrd,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready
);
	reg _sv2v_0;
	parameter [28:0] GFX_DDR_BASE = 29'h06800000;
	parameter [0:0] USE_STREAM_HINT = 1'b0;
	parameter [0:0] DIRECT_PREFETCH = 1'b1;
	input wire clk;
	input wire rst;
	input wire sdram_por;
	input wire src_req;
	input wire [31:0] src_addr;
	input wire src_active;
	input wire src_stream;
	output reg [7:0] src_data;
	output reg src_ack;
	output wire dcs_safe;
	input wire cg_req;
	input wire [25:0] cg_addr;
	output reg [7:0] cg_data;
	output reg cg_ack;
	input wire dl_wr;
	input wire [24:0] dl_addr;
	input wire [7:0] dl_data;
	output reg dl_ack;
	output wire dl_idle;
	output reg [25:0] dbg_wbeats;
	output reg [15:0] dbg_srd;
	output reg [15:0] dbg_cgrd;
	output wire [28:0] ddram_addr;
	output wire [7:0] ddram_burstcnt;
	output wire ddram_rd;
	output wire ddram_we;
	output wire [63:0] ddram_din;
	output wire [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	reg tst_rd_req;
	reg tst_wr_req;
	wire [25:0] tst_addr;
	wire [63:0] tst_wdata;
	wire [7:0] tst_burstcnt;
	wire [63:0] tst_rdata;
	wire tst_rd_valid;
	wire tst_busy;
	stv_vram_ddr_agent #(.VRAM_DDR_BASE(GFX_DDR_BASE)) u_agent(
		.clk(clk),
		.sdram_por(sdram_por),
		.tst_wr_req(tst_wr_req),
		.tst_rd_req(tst_rd_req),
		.tst_addr(tst_addr),
		.tst_wdata(tst_wdata),
		.tst_be(8'hff),
		.tst_burstcnt(tst_burstcnt),
		.tst_rdata(tst_rdata),
		.tst_rd_valid(tst_rd_valid),
		.tst_busy(tst_busy),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_be(ddram_be),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready)
	);
	localparam [7:0] WFLUSH_IDLE = 8'd64;
	reg wc_valid;
	reg [21:0] wc_beat;
	reg [7:0] wc_mask;
	reg [63:0] wc_data;
	reg [7:0] widle_cnt;
	wire [21:0] dl_beat = dl_addr[24:3];
	wire wc_same = wc_valid && (dl_beat == wc_beat);
	wire wr_taking;
	wire wflush_req = wc_valid && (((dl_wr && !dl_ack) && !wc_same) || (widle_cnt >= WFLUSH_IDLE));
	always @(posedge clk)
		if (sdram_por) begin
			wc_valid <= 1'b0;
			wc_beat <= 22'd0;
			wc_mask <= 8'd0;
			wc_data <= 64'd0;
			dl_ack <= 1'b0;
			widle_cnt <= 8'd0;
			dbg_wbeats <= 26'd0;
		end
		else begin
			dl_ack <= 1'b0;
			if (wc_valid && (widle_cnt != 8'hff))
				widle_cnt <= widle_cnt + 8'd1;
			if (wr_taking) begin
				wc_valid <= 1'b0;
				wc_mask <= 8'd0;
			end
			else if ((dl_wr && !dl_ack) && (!wc_valid || wc_same)) begin
				wc_beat <= dl_beat;
				wc_mask[dl_addr[2:0]] <= 1'b1;
				wc_data[dl_addr[2:0] * 8+:8] <= dl_data;
				wc_valid <= 1'b1;
				dl_ack <= 1'b1;
				widle_cnt <= 8'd0;
				dbg_wbeats <= dbg_wbeats + 26'd1;
			end
		end
	localparam integer PF_DEPTH = 4;
	reg [PF_DEPTH - 1:0] pf_valid;
	reg [21:0] pf_tag [0:PF_DEPTH - 1];
	reg [63:0] pf_data [0:PF_DEPTH - 1];
	reg [21:0] pf_target;
	reg [2:0] pf_left;
	reg [2:0] pf_goal;
	reg src_line_valid;
	reg [21:0] src_line_tag;
	reg [63:0] src_line_data;
	reg cg_line_valid;
	reg [21:0] cg_line_tag;
	reg [63:0] cg_line_data;
	wire src_hit = src_line_valid && (src_addr[24:3] == src_line_tag);
	reg src_pf_hit;
	reg [PF_DEPTH - 1:0] src_pf_hit_by_slot_w;
	reg [1:0] src_pf_slot_w;
	reg [63:0] src_pf_data_w;
	always @(*) begin
		if (_sv2v_0)
			;
		src_pf_hit = 1'b0;
		src_pf_hit_by_slot_w = 1'sb0;
		src_pf_slot_w = 2'd0;
		src_pf_data_w = 64'd0;
		if (DIRECT_PREFETCH) begin
			src_pf_slot_w = src_addr[4:3];
			begin : sv2v_autoblock_1
				reg signed [31:0] p;
				for (p = 0; p < PF_DEPTH; p = p + 1)
					src_pf_hit_by_slot_w[p] = pf_valid[p] && (src_addr[24:5] == pf_tag[p][21:2]);
			end
			src_pf_hit = src_pf_hit_by_slot_w[src_addr[4:3]];
			src_pf_data_w = pf_data[src_addr[4:3]];
		end
		else begin : sv2v_autoblock_2
			reg signed [31:0] p;
			for (p = 0; p < PF_DEPTH; p = p + 1)
				if (pf_valid[p] && (src_addr[24:3] == pf_tag[p])) begin
					src_pf_hit = 1'b1;
					src_pf_slot_w = p[1:0];
					src_pf_data_w = pf_data[p];
				end
		end
	end
	wire cg_hit = cg_line_valid && (cg_addr[24:3] == cg_line_tag);
	reg src_hit_q;
	reg cg_hit_q;
	reg [24:0] src_qaddr;
	reg [24:0] cg_qaddr;
	reg [7:0] src_byte_q;
	reg [7:0] cg_byte_q;
	reg src_pend;
	reg cg_pend;
	reg src_cool;
	reg cg_cool;
	reg src_done;
	reg cg_done;
	reg src_pf_served;
	reg [1:0] src_pf_served_slot;
	always @(posedge clk)
		if (rst) begin
			src_pend <= 1'b0;
			cg_pend <= 1'b0;
			src_cool <= 1'b0;
			cg_cool <= 1'b0;
			src_pf_served <= 1'b0;
			src_pf_served_slot <= 2'd0;
			src_hit_q <= 1'b0;
			cg_hit_q <= 1'b0;
			src_qaddr <= 25'd0;
			cg_qaddr <= 25'd0;
			src_byte_q <= 8'h00;
			cg_byte_q <= 8'h00;
			src_ack <= 1'b0;
			cg_ack <= 1'b0;
			src_data <= 8'h00;
			cg_data <= 8'h00;
			dbg_srd <= 16'd0;
			dbg_cgrd <= 16'd0;
		end
		else begin
			src_ack <= 1'b0;
			cg_ack <= 1'b0;
			src_pf_served <= 1'b0;
			src_pf_served_slot <= src_pf_slot_w;
			src_cool <= src_ack;
			cg_cool <= cg_ack;
			src_data <= (src_pend ? src_byte_q : (src_hit ? src_line_data[src_addr[2:0] * 8+:8] : src_pf_data_w[src_addr[2:0] * 8+:8]));
			src_hit_q <= src_hit;
			cg_hit_q <= cg_hit;
			src_qaddr <= src_addr[24:0];
			cg_qaddr <= cg_addr[24:0];
			src_byte_q <= src_line_data[src_addr[2:0] * 8+:8];
			cg_byte_q <= cg_line_data[cg_addr[2:0] * 8+:8];
			if (((!src_pend && src_req) && !src_ack) && !src_cool) begin
				if (src_hit || src_pf_hit) begin
					src_ack <= 1'b1;
					src_pf_served <= src_pf_hit && !src_hit;
					dbg_srd <= dbg_srd + 16'd1;
				end
				else
					src_pend <= 1'b1;
			end
			if (((!cg_pend && cg_req) && !cg_ack) && !cg_cool) begin
				if ((cg_hit && cg_hit_q) && (cg_qaddr == cg_addr[24:0])) begin
					cg_data <= cg_byte_q;
					cg_ack <= 1'b1;
					dbg_cgrd <= dbg_cgrd + 16'd1;
				end
				else if (!cg_hit)
					cg_pend <= 1'b1;
			end
			if (src_pend && src_done) begin
				src_ack <= 1'b1;
				src_pend <= 1'b0;
				dbg_srd <= dbg_srd + 16'd1;
			end
			if (cg_pend && cg_done) begin
				cg_data <= cg_byte_q;
				cg_ack <= 1'b1;
				cg_pend <= 1'b0;
				dbg_cgrd <= dbg_cgrd + 16'd1;
			end
		end
	localparam [3:0] O_IDLE = 4'd0;
	localparam [3:0] O_FRD = 4'd1;
	localparam [3:0] O_FRDW = 4'd2;
	localparam [3:0] O_FWR = 4'd3;
	localparam [3:0] O_FWW = 4'd4;
	localparam [3:0] O_RISSUE = 4'd5;
	localparam [3:0] O_RWAIT = 4'd6;
	localparam [3:0] O_GAP = 4'd7;
	localparam [3:0] O_PISSUE = 4'd8;
	localparam [3:0] O_PWAIT = 4'd9;
	reg [3:0] ost;
	reg o_is_src;
	reg o_done_pend;
	reg [21:0] o_line;
	reg [21:0] wl_beat;
	reg [7:0] wl_mask;
	reg [63:0] wl_data;
	reg fwd_valid;
	reg [21:0] fwd_beat;
	reg [63:0] fwd_data;
	wire src_live_miss_w = (src_req && !src_hit) && !src_pf_hit;
	wire cg_live_miss_w = cg_req && !cg_hit;
	wire stream_prefetch_w = USE_STREAM_HINT && src_stream;
	reg pf_pend_hit_w;
	reg [1:0] pf_pend_slot_w;
	reg [2:0] pf_valid_count_w;
	reg [2:0] pf_valid_after_consume_w;
	reg [2:0] pf_next_goal_w;
	reg [2:0] pf_refill_after_consume_w;
	always @(*) begin
		if (_sv2v_0)
			;
		pf_pend_hit_w = 1'b0;
		pf_pend_slot_w = 2'd0;
		pf_valid_count_w = 3'd0;
		begin : sv2v_autoblock_3
			reg signed [31:0] p;
			for (p = 0; p < PF_DEPTH; p = p + 1)
				begin
					if (pf_valid[p])
						pf_valid_count_w = pf_valid_count_w + 3'd1;
					if ((!DIRECT_PREFETCH && pf_valid[p]) && (src_qaddr[24:3] == pf_tag[p])) begin
						pf_pend_hit_w = 1'b1;
						pf_pend_slot_w = p[1:0];
					end
				end
		end
		if (DIRECT_PREFETCH) begin
			pf_pend_slot_w = src_qaddr[4:3];
			pf_pend_hit_w = pf_valid[src_qaddr[4:3]] && (src_qaddr[24:5] == pf_tag[src_qaddr[4:3]][21:2]);
		end
		pf_valid_after_consume_w = (pf_valid_count_w != 3'd0 ? pf_valid_count_w - 3'd1 : 3'd0);
		if (stream_prefetch_w)
			pf_next_goal_w = (pf_goal < 3'd2 ? 3'd2 : 3'd4);
		else if (USE_STREAM_HINT && src_active)
			pf_next_goal_w = 3'd2;
		else
			pf_next_goal_w = 3'd1;
		if (pf_next_goal_w > pf_valid_after_consume_w)
			pf_refill_after_consume_w = pf_next_goal_w - pf_valid_after_consume_w;
		else
			pf_refill_after_consume_w = 3'd0;
	end
	assign dcs_safe = (!USE_STREAM_HINT || !src_active) || ((pf_left == 3'd0) && (pf_valid_count_w >= (src_stream ? 3'd3 : 3'd2)));
	localparam signed [31:0] SRC_IDLE_MAX = 16;
	reg [4:0] src_idle_cnt;
	always @(posedge clk)
		if (sdram_por)
			src_idle_cnt <= 5'd0;
		else if (!src_active || src_req)
			src_idle_cnt <= 5'd0;
		else if (src_idle_cnt < SRC_IDLE_MAX[4:0])
			src_idle_cnt <= src_idle_cnt + 5'd1;
	wire src_stalled_w = src_idle_cnt >= SRC_IDLE_MAX[4:0];
	wire cg_safe_w = ((!USE_STREAM_HINT || !src_active) || dcs_safe) || src_stalled_w;
	wire [1:0] pf_promote_slot_w = (src_pf_served && pf_valid[src_pf_served_slot] ? src_pf_served_slot : pf_pend_slot_w);
	wire [63:0] pf_promote_data_w = pf_data[pf_promote_slot_w];
	wire [21:0] pf_promote_tag_w = pf_tag[pf_promote_slot_w];
	assign wr_taking = (ost == O_IDLE) && wflush_req;
	always @(posedge clk)
		if (sdram_por) begin
			ost <= O_IDLE;
			o_is_src <= 1'b0;
			o_done_pend <= 1'b0;
			o_line <= 22'd0;
			wl_beat <= 22'd0;
			wl_mask <= 8'd0;
			wl_data <= 64'd0;
			fwd_valid <= 1'b0;
			fwd_beat <= 22'd0;
			fwd_data <= 64'd0;
			pf_valid <= 1'sb0;
			pf_target <= 22'd0;
			pf_left <= 3'd0;
			pf_goal <= 3'd1;
			begin : sv2v_autoblock_4
				reg signed [31:0] p;
				for (p = 0; p < PF_DEPTH; p = p + 1)
					begin
						pf_tag[p] <= 22'd0;
						pf_data[p] <= 64'd0;
					end
			end
			src_line_valid <= 1'b0;
			src_line_tag <= 22'd0;
			src_line_data <= 64'd0;
			cg_line_valid <= 1'b0;
			cg_line_tag <= 22'd0;
			cg_line_data <= 64'd0;
			tst_rd_req <= 1'b0;
			tst_wr_req <= 1'b0;
			src_done <= 1'b0;
			cg_done <= 1'b0;
		end
		else begin
			tst_rd_req <= 1'b0;
			tst_wr_req <= 1'b0;
			src_done <= 1'b0;
			cg_done <= 1'b0;
			case (ost)
				O_IDLE:
					if (wflush_req) begin
						wl_beat <= wc_beat;
						wl_mask <= wc_mask;
						if (fwd_valid && (wc_beat == fwd_beat)) begin
							begin : sv2v_autoblock_5
								reg signed [31:0] i;
								for (i = 0; i < 8; i = i + 1)
									wl_data[8 * i+:8] <= (wc_mask[i] ? wc_data[8 * i+:8] : fwd_data[8 * i+:8]);
							end
							ost <= O_FWR;
						end
						else begin
							wl_data <= wc_data;
							ost <= O_FRD;
						end
					end
					else if (src_pf_served && pf_valid[src_pf_served_slot]) begin
						src_line_data <= (DIRECT_PREFETCH ? pf_promote_data_w : pf_data[src_pf_served_slot]);
						src_line_valid <= 1'b1;
						src_line_tag <= (DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[src_pf_served_slot]);
						if (src_line_valid && ((DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[src_pf_served_slot]) == (src_line_tag + 22'd1))) begin
							pf_valid[src_pf_served_slot] <= 1'b0;
							pf_goal <= pf_next_goal_w;
							pf_left <= pf_refill_after_consume_w;
						end
						else begin
							pf_valid <= 1'sb0;
							pf_target <= (DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[src_pf_served_slot]) + 22'd1;
							pf_left <= 3'd1;
							pf_goal <= 3'd1;
						end
					end
					else if (src_pend && !src_done) begin
						o_is_src <= 1'b1;
						o_line <= src_qaddr[24:3];
						if (pf_pend_hit_w) begin
							src_line_data <= (DIRECT_PREFETCH ? pf_promote_data_w : pf_data[pf_pend_slot_w]);
							src_line_valid <= 1'b1;
							src_line_tag <= (DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[pf_pend_slot_w]);
							if (src_line_valid && ((DIRECT_PREFETCH ? pf_promote_tag_w : pf_tag[pf_pend_slot_w]) == (src_line_tag + 22'd1))) begin
								pf_valid[pf_pend_slot_w] <= 1'b0;
								pf_goal <= pf_next_goal_w;
								pf_left <= pf_refill_after_consume_w;
							end
							else begin
								pf_valid <= 1'sb0;
								pf_target <= src_qaddr[24:3] + 22'd1;
								pf_left <= 3'd1;
								pf_goal <= 3'd1;
							end
							o_done_pend <= 1'b1;
							ost <= O_GAP;
						end
						else
							ost <= O_RISSUE;
					end
					else if ((cg_pend && !cg_done) && cg_safe_w) begin
						o_is_src <= 1'b0;
						o_line <= cg_addr[24:3];
						ost <= O_RISSUE;
					end
					else if (((pf_left != 3'd0) && !src_live_miss_w) && !(cg_live_miss_w && cg_safe_w))
						ost <= O_PISSUE;
				O_FRD: begin
					tst_rd_req <= 1'b1;
					ost <= O_FRDW;
				end
				O_FRDW:
					if (tst_rd_valid) begin
						begin : sv2v_autoblock_6
							reg signed [31:0] i;
							for (i = 0; i < 8; i = i + 1)
								if (!wl_mask[i])
									wl_data[8 * i+:8] <= tst_rdata[8 * i+:8];
						end
						ost <= O_FWR;
					end
				O_FWW:
					if (!tst_busy && !tst_wr_req) begin
						fwd_valid <= 1'b1;
						fwd_beat <= wl_beat;
						fwd_data <= wl_data;
						if (src_line_valid && (wl_beat == src_line_tag))
							src_line_valid <= 1'b0;
						if (cg_line_valid && (wl_beat == cg_line_tag))
							cg_line_valid <= 1'b0;
						begin : sv2v_autoblock_7
							reg signed [31:0] p;
							for (p = 0; p < PF_DEPTH; p = p + 1)
								if (pf_valid[p] && (wl_beat == pf_tag[p]))
									pf_valid[p] <= 1'b0;
						end
						ost <= O_GAP;
					end
				O_FWR: begin
					tst_wr_req <= 1'b1;
					ost <= O_FWW;
				end
				O_RISSUE: begin
					tst_rd_req <= 1'b1;
					ost <= O_RWAIT;
				end
				O_RWAIT:
					if (tst_rd_valid) begin
						if (o_is_src) begin
							src_line_data <= tst_rdata;
							src_line_valid <= 1'b1;
							src_line_tag <= o_line;
							pf_valid <= 1'sb0;
							pf_target <= o_line + 22'd1;
							pf_left <= 3'd1;
							pf_goal <= 3'd1;
						end
						else begin
							cg_line_data <= tst_rdata;
							cg_line_valid <= 1'b1;
							cg_line_tag <= o_line;
						end
						o_done_pend <= 1'b1;
						ost <= O_GAP;
					end
				O_GAP: begin
					if (o_done_pend) begin
						if (o_is_src)
							src_done <= 1'b1;
						else
							cg_done <= 1'b1;
						o_done_pend <= 1'b0;
					end
					ost <= O_IDLE;
				end
				O_PISSUE:
					if (((wflush_req || src_pend) || src_live_miss_w) || ((cg_pend || cg_live_miss_w) && cg_safe_w))
						ost <= O_IDLE;
					else begin
						tst_rd_req <= 1'b1;
						ost <= O_PWAIT;
					end
				O_PWAIT:
					if (tst_rd_valid) begin
						if (src_pend && (src_qaddr[24:3] == pf_target)) begin
							src_line_data <= tst_rdata;
							src_line_valid <= 1'b1;
							src_line_tag <= pf_target;
							pf_valid <= 1'sb0;
							pf_target <= pf_target + 22'd1;
							pf_left <= 3'd1;
							pf_goal <= 3'd1;
							o_is_src <= 1'b1;
							o_done_pend <= 1'b1;
							ost <= O_GAP;
						end
						else begin
							pf_data[pf_target[1:0]] <= tst_rdata;
							pf_tag[pf_target[1:0]] <= pf_target;
							pf_valid[pf_target[1:0]] <= 1'b1;
							pf_target <= pf_target + 22'd1;
							if (pf_left != 3'd0)
								pf_left <= pf_left - 3'd1;
							ost <= O_IDLE;
						end
					end
				default: ost <= O_IDLE;
			endcase
		end
	wire fsel = (((ost == O_FRD) || (ost == O_FRDW)) || (ost == O_FWR)) || (ost == O_FWW);
	wire psel = (ost == O_PISSUE) || (ost == O_PWAIT);
	assign tst_addr = (fsel ? {4'd0, wl_beat} : (psel ? {4'd0, pf_target} : {4'd0, o_line}));
	assign tst_burstcnt = 8'd1;
	assign tst_wdata = wl_data;
	assign dl_idle = (((!wc_valid && (ost == O_IDLE)) && !tst_busy) && !tst_rd_req) && !tst_wr_req;
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_dcs_ddr_top (
	clk,
	sdram_por,
	dl_wr,
	dl_addr,
	dl_data,
	dl_ack,
	dl_busy,
	rom_req,
	rom_addr,
	rom_rdy,
	rom_q,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready
);
	reg _sv2v_0;
	parameter [28:0] DCS_DDR_BASE = 29'h06c00000;
	input wire clk;
	input wire sdram_por;
	input wire dl_wr;
	input wire [21:0] dl_addr;
	input wire [7:0] dl_data;
	output wire dl_ack;
	output wire dl_busy;
	input wire rom_req;
	input wire [18:0] rom_addr;
	output wire rom_rdy;
	output wire [63:0] rom_q;
	output wire [28:0] ddram_addr;
	output wire [7:0] ddram_burstcnt;
	output wire ddram_rd;
	output wire ddram_we;
	output wire [63:0] ddram_din;
	output wire [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	reg ag_wr_req;
	reg ag_rd_req;
	reg [25:0] ag_addr;
	reg [63:0] ag_wdata;
	wire [63:0] ag_rdata;
	wire ag_rd_valid;
	wire ag_busy;
	wire ag_wnext;
	stv_vram_ddr_agent #(.VRAM_DDR_BASE(DCS_DDR_BASE)) u_agent(
		.clk(clk),
		.sdram_por(sdram_por),
		.tst_wr_req(ag_wr_req),
		.tst_rd_req(ag_rd_req),
		.tst_addr(ag_addr),
		.tst_wdata(ag_wdata),
		.tst_be(8'hff),
		.tst_burstcnt(8'd1),
		.tst_rdata(ag_rdata),
		.tst_rd_valid(ag_rd_valid),
		.tst_busy(ag_busy),
		.tst_wnext(ag_wnext),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_be(ddram_be),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready)
	);
	reg buf_valid;
	reg wr_pending;
	reg wr_inflight;
	reg rd_inflight;
	reg read_seen;
	reg [18:0] read_tag;
	reg [18:0] buf_beat;
	reg [7:0] buf_mask;
	reg [63:0] buf_data;
	wire [18:0] dl_beat = dl_addr[21:3];
	wire [7:0] dl_lane = 8'h01 << dl_addr[2:0];
	wire dl_same = buf_valid && (dl_beat == buf_beat);
	wire dl_take = (((dl_wr && !sdram_por) && !wr_pending) && !wr_inflight) && (!buf_valid || dl_same);
	assign dl_ack = dl_take;
	assign dl_busy = (buf_valid | wr_pending) | wr_inflight;
	always @(*) begin
		if (_sv2v_0)
			;
		ag_wr_req = (!ag_busy && wr_pending) && !wr_inflight;
		ag_rd_req = ((((!ag_busy && !wr_pending) && !wr_inflight) && rom_req) && !rd_inflight) && !read_seen;
		if (ag_wr_req) begin
			ag_addr = {7'd0, buf_beat};
			ag_wdata = buf_data;
		end
		else begin
			ag_addr = {7'd0, rom_addr};
			ag_wdata = 64'd0;
		end
	end
	assign rom_rdy = (((rd_inflight && ag_rd_valid) && read_seen) && rom_req) && (rom_addr == read_tag);
	assign rom_q = ag_rdata;
	always @(posedge clk)
		if (sdram_por) begin
			buf_valid <= 1'b0;
			buf_beat <= 1'sb0;
			buf_mask <= 1'sb0;
			buf_data <= 1'sb0;
			wr_pending <= 1'b0;
			wr_inflight <= 1'b0;
			rd_inflight <= 1'b0;
			read_seen <= 1'b0;
			read_tag <= 19'd0;
		end
		else begin
			if (!rom_req)
				read_seen <= 1'b0;
			if (ag_rd_req) begin
				read_seen <= 1'b1;
				read_tag <= rom_addr;
			end
			if (ag_wr_req) begin
				wr_pending <= 1'b0;
				wr_inflight <= 1'b1;
			end
			if (ag_rd_req)
				rd_inflight <= 1'b1;
			if (rd_inflight && ag_rd_valid)
				rd_inflight <= 1'b0;
			if (wr_inflight && !ag_busy) begin
				wr_inflight <= 1'b0;
				buf_valid <= 1'b0;
				buf_mask <= 1'sb0;
			end
			if (dl_take) begin
				if (!buf_valid) begin
					buf_valid <= 1'b1;
					buf_beat <= dl_beat;
					buf_mask <= dl_lane;
					buf_data <= 64'd0;
					buf_data[8 * dl_addr[2:0]+:8] <= dl_data;
					if (dl_lane == 8'hff)
						wr_pending <= 1'b1;
				end
				else begin
					buf_mask <= buf_mask | dl_lane;
					buf_data[8 * dl_addr[2:0]+:8] <= dl_data;
					if ((buf_mask | dl_lane) == 8'hff)
						wr_pending <= 1'b1;
				end
			end
			else if ((((dl_wr && buf_valid) && !wr_pending) && !wr_inflight) && (dl_beat != buf_beat))
				wr_pending <= 1'b1;
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_ddr3_arb (
	clk,
	b_allow,
	a_addr,
	a_burstcnt,
	a_rd,
	a_we,
	a_din,
	a_be,
	a_busy,
	a_dout,
	a_dout_ready,
	b_addr,
	b_burstcnt,
	b_rd,
	b_we,
	b_din,
	b_be,
	b_busy,
	b_dout,
	b_dout_ready,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready
);
	reg _sv2v_0;
	parameter [0:0] HONOR_B_ALLOW = 1'b0;
	input wire clk;
	input wire b_allow;
	input wire [28:0] a_addr;
	input wire [7:0] a_burstcnt;
	input wire a_rd;
	input wire a_we;
	input wire [63:0] a_din;
	input wire [7:0] a_be;
	output reg a_busy;
	output reg [63:0] a_dout;
	output reg a_dout_ready;
	input wire [28:0] b_addr;
	input wire [7:0] b_burstcnt;
	input wire b_rd;
	input wire b_we;
	input wire [63:0] b_din;
	input wire [7:0] b_be;
	output reg b_busy;
	output reg [63:0] b_dout;
	output reg b_dout_ready;
	output reg [28:0] ddram_addr;
	output reg [7:0] ddram_burstcnt;
	output reg ddram_rd;
	output reg ddram_we;
	output reg [63:0] ddram_din;
	output reg [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	localparam [1:0] G_NONE = 2'd0;
	localparam [1:0] G_A = 2'd1;
	localparam [1:0] G_B = 2'd2;
	reg [1:0] gnt;
	reg [7:0] beats_left;
	reg gnt_wr;
	wire a_req = a_rd | a_we;
	wire b_req = b_rd | b_we;
	wire b_eligible = !HONOR_B_ALLOW || b_allow;
	always @(posedge clk)
		case (gnt)
			G_NONE:
				if (a_req) begin
					gnt <= G_A;
					gnt_wr <= a_we;
					if (a_rd)
						beats_left <= (a_burstcnt == 8'd0 ? 8'd1 : a_burstcnt);
				end
				else if (b_req && b_eligible) begin
					gnt <= G_B;
					gnt_wr <= b_we;
					if (b_rd)
						beats_left <= (b_burstcnt == 8'd0 ? 8'd1 : b_burstcnt);
				end
			G_A:
				if (gnt_wr) begin
					if (!a_we)
						gnt <= G_NONE;
				end
				else if (ddram_dout_ready) begin
					if (beats_left <= 8'd1)
						gnt <= G_NONE;
					else
						beats_left <= beats_left - 8'd1;
				end
			G_B:
				if (gnt_wr) begin
					if (!b_we)
						gnt <= G_NONE;
				end
				else if (ddram_dout_ready) begin
					if (beats_left <= 8'd1)
						gnt <= G_NONE;
					else
						beats_left <= beats_left - 8'd1;
				end
			default: gnt <= G_NONE;
		endcase
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (gnt)
			G_A: begin
				ddram_addr = a_addr;
				ddram_burstcnt = a_burstcnt;
				ddram_rd = a_rd;
				ddram_we = a_we;
				ddram_din = a_din;
				ddram_be = a_be;
			end
			G_B: begin
				ddram_addr = b_addr;
				ddram_burstcnt = b_burstcnt;
				ddram_rd = b_rd;
				ddram_we = b_we;
				ddram_din = b_din;
				ddram_be = b_be;
			end
			default: begin
				ddram_addr = 29'd0;
				ddram_burstcnt = 8'd0;
				ddram_rd = 1'b0;
				ddram_we = 1'b0;
				ddram_din = 64'd0;
				ddram_be = 8'd0;
			end
		endcase
		a_busy = (gnt == G_A ? ddram_busy : a_req);
		a_dout = ddram_dout;
		a_dout_ready = (gnt == G_A ? ddram_dout_ready : 1'b0);
		b_busy = (gnt == G_B ? ddram_busy : b_req);
		b_dout = ddram_dout;
		b_dout_ready = (gnt == G_B ? ddram_dout_ready : 1'b0);
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_memsys (
	clk,
	rst,
	mem_req,
	mem_we,
	mem_addr,
	mem_size,
	mem_wdata,
	mem_rdata,
	mem_ack,
	mem_srt,
	publication_hold,
	src_req,
	src_addr,
	src_active,
	src_stream,
	src_data,
	src_ack,
	inputs,
	game_profile,
	int1,
	snd_data_wr,
	snd_data_o,
	snd_data_rd,
	snd_reset,
	snd_rdata,
	snd_stat,
	pic_wr,
	pic_wdata,
	pic_reset,
	pic_rdata,
	pic_status,
	watchdog_kick,
	gfxbank_o,
	erase_start,
	erase_row0,
	erase_lines,
	erase_busy,
	nvram_ext_en,
	nvram_ext_wr,
	nvram_ext_addr,
	nvram_ext_wdata,
	nvram_ext_rdata,
	nvram_cpu_write,
	vram_wr_busy,
	dbg_vram_cst,
	blit_busy,
	dbg_dma_q_overflow,
	dbg_dma_q_highwater,
	cpu_gfx_rd,
	cpu_gfx_raddr,
	cpu_gfx_rdata,
	cpu_gfx_rack,
	cpu_gfx_is_rom,
	scan_req,
	scan_addr,
	scan_data,
	scan_ack,
	sdram_por,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready,
	rsd_addr,
	rsd_din,
	rsd_be,
	rsd_rd,
	rsd_wr,
	rsd_dout,
	rsd_ack,
	palv_we_a,
	palv_aa,
	palv_awd,
	palv_we_b,
	palv_ba,
	palv_bwd
);
	reg _sv2v_0;
	parameter signed [31:0] ROM_WORDS = 32'h00080000;
	parameter [27:0] ROM_PROG_OFF = 28'h0000000;
	parameter signed [31:0] RAM_WORDS = 32'h00040000;
	parameter ROM_HEX = "umk3_maindata.hex";
	parameter GFX_HEX = "build/umk3_gfx.hex";
	parameter CMOS_HEX = "build/umk3_cmos.hex";
	parameter NB_VRAM_HEX = "../../mame-gospel/trace/nearblit/vram.hex";
	parameter NB_RAM_HEX = "../../mame-gospel/trace/nearblit/ram.hex";
	parameter NB_PAL_HEX = "../../mame-gospel/trace/nearblit/pal.hex";
	parameter NB_CMOS_HEX = "../../mame-gospel/trace/nearblit/cmos.hex";
	parameter [127:0] PIC_RESPONSE_BYTES = 128'h2b1e4a0e02176c60b4082509db019af6;
	parameter [0:0] WWF_IO_SHUFFLE = 1'b0;
	parameter [0:0] TIMED_IRQ_PUMP = 1'b1;
	parameter [0:0] DMA_REG_BACKPRESSURE = 1'b1;
	parameter [0:0] DMA_GO_WAIT_RETIRED = 1'b1;
	parameter [0:0] PIC_STATUS_DELAY = 1'b1;
	parameter signed [31:0] PIC_COLD_TURN = 865560;
	parameter signed [31:0] PIC_WARM_TURN = 3184;
	input wire clk;
	input wire rst;
	input wire mem_req;
	input wire mem_we;
	input wire [31:0] mem_addr;
	input wire [5:0] mem_size;
	input wire [31:0] mem_wdata;
	output wire [31:0] mem_rdata;
	output wire mem_ack;
	input wire mem_srt;
	input wire publication_hold;
	output wire src_req;
	output wire [31:0] src_addr;
	output wire src_active;
	output wire src_stream;
	input wire [7:0] src_data;
	input wire src_ack;
	input wire [63:0] inputs;
	input wire [2:0] game_profile;
	output wire int1;
	output wire snd_data_wr;
	output wire [7:0] snd_data_o;
	output wire snd_data_rd;
	output wire snd_reset;
	input wire [7:0] snd_rdata;
	input wire [15:0] snd_stat;
	output wire pic_wr;
	output wire [7:0] pic_wdata;
	output wire pic_reset;
	input wire [7:0] pic_rdata;
	input wire [3:0] pic_status;
	output wire watchdog_kick;
	output wire [1:0] gfxbank_o;
	input wire erase_start;
	input wire [8:0] erase_row0;
	input wire [9:0] erase_lines;
	output wire erase_busy;
	input wire nvram_ext_en;
	input wire nvram_ext_wr;
	input wire [15:0] nvram_ext_addr;
	input wire [7:0] nvram_ext_wdata;
	output wire [7:0] nvram_ext_rdata;
	output wire nvram_cpu_write;
	output wire vram_wr_busy;
	output wire [2:0] dbg_vram_cst;
	output wire blit_busy;
	output wire dbg_dma_q_overflow;
	output wire [8:0] dbg_dma_q_highwater;
	output wire cpu_gfx_rd;
	output wire [25:0] cpu_gfx_raddr;
	input wire [7:0] cpu_gfx_rdata;
	input wire cpu_gfx_rack;
	output wire cpu_gfx_is_rom;
	input wire scan_req;
	input wire [18:0] scan_addr;
	output wire [15:0] scan_data;
	output wire scan_ack;
	input wire sdram_por;
	output wire [28:0] ddram_addr;
	output wire [7:0] ddram_burstcnt;
	output wire ddram_rd;
	output wire ddram_we;
	output wire [63:0] ddram_din;
	output wire [7:0] ddram_be;
	input wire ddram_busy;
	input wire [63:0] ddram_dout;
	input wire ddram_dout_ready;
	output wire [24:0] rsd_addr;
	output wire [15:0] rsd_din;
	output wire [1:0] rsd_be;
	output wire rsd_rd;
	output wire rsd_wr;
	input wire [15:0] rsd_dout;
	input wire rsd_ack;
	output wire palv_we_a;
	output wire [14:0] palv_aa;
	output wire [15:0] palv_awd;
	output wire palv_we_b;
	output wire [14:0] palv_ba;
	output wire [15:0] palv_bwd;
	wire is_dma_now = mem_addr[31:20] == 12'h01a;
	wire mem_req_m;
	wire [31:0] mem_rdata_m;
	wire mem_ack_m;
	reg [7:0] pic_rdata_int;
	reg pic_status_raw;
	wire pic_status_int;
	reg wwf_io_shuffle_active;
	reg pic_status_delay_active;
	always @(*) begin
		if (_sv2v_0)
			;
		wwf_io_shuffle_active = WWF_IO_SHUFFLE;
		pic_status_delay_active = PIC_STATUS_DELAY;
		case (game_profile)
			3'd1: begin
				wwf_io_shuffle_active = 1'b1;
				pic_status_delay_active = 1'b0;
			end
			3'd0, 3'd2, 3'd4, 3'd5: pic_status_delay_active = 1'b0;
			3'd3, 3'd6: pic_status_delay_active = 1'b1;
			default: begin
				wwf_io_shuffle_active = WWF_IO_SHUFFLE;
				pic_status_delay_active = PIC_STATUS_DELAY;
			end
		endcase
	end
	wire dma_reg_we;
	wire dma_reg_offer;
	wire dma_reg_ready;
	wire [3:0] dma_reg_addr;
	wire [15:0] dma_reg_wdata;
	wire [15:0] dma_reg_rdata;
	wire dma_fb_we;
	localparam signed [31:0] wolf_pkg_FB_ADDR_W = 19;
	wire [18:0] dma_fb_addr;
	wire [15:0] dma_fb_wdata;
	wire [15:0] dma_palette;
	wire mem_fb_ack;
	wire dma_fb_ack = mem_fb_ack;
	wire dma_wr_busy;
	reg cpu_vram_write_pending;
	wire cpu_vram_now = mem_addr[31:22] == 10'd0;
	wire publication_hold_i = DMA_REG_BACKPRESSURE && (publication_hold === 1'b1);
	always @(posedge clk)
		if (rst)
			cpu_vram_write_pending <= 1'b0;
		else if (mem_ack_m)
			cpu_vram_write_pending <= 1'b0;
		else if ((mem_req_m && mem_we) && cpu_vram_now)
			cpu_vram_write_pending <= 1'b1;
	assign vram_wr_busy = dma_wr_busy || (DMA_REG_BACKPRESSURE && cpu_vram_write_pending);
	wolf_mem #(
		.ROM_WORDS(ROM_WORDS),
		.ROM_PROG_OFF(ROM_PROG_OFF),
		.RAM_WORDS(RAM_WORDS),
		.ROM_HEX(ROM_HEX),
		.GFX_HEX(GFX_HEX),
		.CMOS_HEX(CMOS_HEX),
		.NB_VRAM_HEX(NB_VRAM_HEX),
		.NB_RAM_HEX(NB_RAM_HEX),
		.NB_PAL_HEX(NB_PAL_HEX),
		.NB_CMOS_HEX(NB_CMOS_HEX),
		.WWF_IO_SHUFFLE(WWF_IO_SHUFFLE)
	) u_mem(
		.clk(clk),
		.rst(rst),
		.mem_req(mem_req_m),
		.mem_we(mem_we),
		.mem_addr(mem_addr),
		.mem_size(mem_size),
		.mem_wdata(mem_wdata),
		.mem_rdata(mem_rdata_m),
		.mem_ack(mem_ack_m),
		.mem_srt(mem_srt),
		.fb_we(dma_fb_we),
		.fb_addr(dma_fb_addr),
		.fb_wdata(dma_fb_wdata),
		.dma_palette(dma_palette),
		.inputs(inputs),
		.wwf_io_shuffle_i(wwf_io_shuffle_active),
		.snd_data_wr(snd_data_wr),
		.snd_data_o(snd_data_o),
		.snd_data_rd(snd_data_rd),
		.snd_reset(snd_reset),
		.snd_rdata(snd_rdata),
		.snd_stat(snd_stat),
		.pic_wr(pic_wr),
		.pic_wdata(pic_wdata),
		.pic_reset(pic_reset),
		.pic_rdata(pic_rdata_int),
		.pic_status({3'h0, pic_status_int}),
		.watchdog_kick(watchdog_kick),
		.gfxbank_o(gfxbank_o),
		.erase_start(erase_start),
		.erase_row0(erase_row0),
		.erase_lines(erase_lines),
		.erase_busy(erase_busy),
		.nvram_ext_en(nvram_ext_en),
		.nvram_ext_wr(nvram_ext_wr),
		.nvram_ext_addr(nvram_ext_addr),
		.nvram_ext_wdata(nvram_ext_wdata),
		.nvram_ext_rdata(nvram_ext_rdata),
		.nvram_cpu_write(nvram_cpu_write),
		.dbg_vram_cst(dbg_vram_cst),
		.gfx_rd(cpu_gfx_rd),
		.gfx_raddr(cpu_gfx_raddr),
		.gfx_rdata(cpu_gfx_rdata),
		.gfx_rack(cpu_gfx_rack),
		.cgfx_is_rom(cpu_gfx_is_rom),
		.fb_ack(mem_fb_ack),
		.fb_wr_busy(dma_wr_busy),
		.scan_req(scan_req),
		.scan_addr(scan_addr),
		.scan_data(scan_data),
		.scan_ack(scan_ack),
		.sdram_por(sdram_por),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_be(ddram_be),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready),
		.rsd_addr(rsd_addr),
		.rsd_din(rsd_din),
		.rsd_be(rsd_be),
		.rsd_rd(rsd_rd),
		.rsd_wr(rsd_wr),
		.rsd_dout(rsd_dout),
		.rsd_ack(rsd_ack),
		.palv_we_a(palv_we_a),
		.palv_aa(palv_aa),
		.palv_awd(palv_awd),
		.palv_we_b(palv_we_b),
		.palv_ba(palv_ba),
		.palv_bwd(palv_bwd)
	);
	wolf_dma #(
		.TIMED_IRQ_PUMP(TIMED_IRQ_PUMP),
		.WAIT_GO_RETIRED(DMA_GO_WAIT_RETIRED),
		.REG_WRITE_BACKPRESSURE(DMA_REG_BACKPRESSURE),
		.DRAIN_QUEUED_ON_STOP(1'b1)
	) u_dma(
		.clk(clk),
		.rst(rst),
		.reg_we(dma_reg_offer),
		.reg_addr(dma_reg_addr),
		.reg_wdata(dma_reg_wdata),
		.reg_rdata(dma_reg_rdata),
		.reg_ready(dma_reg_ready),
		.go_hold(publication_hold_i),
		.src_req(src_req),
		.src_addr(src_addr),
		.src_active(src_active),
		.src_stream(src_stream),
		.src_data(src_data),
		.src_ack(src_ack),
		.fb_we(dma_fb_we),
		.fb_addr(dma_fb_addr),
		.fb_wdata(dma_fb_wdata),
		.fb_ack(dma_fb_ack),
		.wr_busy(dma_wr_busy),
		.busy(blit_busy),
		.blit_irq(int1),
		.dma_palette(dma_palette),
		.dbg_q_overflow(dbg_dma_q_overflow),
		.dbg_q_highwater(dbg_dma_q_highwater)
	);
	reg pic_ack_q;
	reg pic_reset_q;
	wire sec_rd_now = (((mem_req && !mem_we) && !is_dma_now) && (mem_addr[31:4] == 28'h0160000)) && mem_ack;
	wire pic_resp_re = sec_rd_now && !pic_ack_q;
	wire pic_reset_w = pic_reset ^ pic_reset_q;
	always @(posedge clk)
		if (rst) begin
			pic_ack_q <= 1'b0;
			pic_reset_q <= 1'b0;
		end
		else begin
			pic_ack_q <= sec_rd_now;
			pic_reset_q <= pic_reset;
		end
	wire [7:0] pic_rdata_param;
	wire [7:0] pic_rdata_dev;
	wire [7:0] pic_rdata_umk3;
	wire [7:0] pic_rdata_rwt;
	wire pic_status_param;
	wire pic_status_dev;
	wire pic_status_umk3;
	wire pic_status_rwt;
	wolf_pic #(.RESPONSE_BYTES(PIC_RESPONSE_BYTES)) u_pic_param(
		.clk(clk),
		.rst(rst),
		.cmd_we(pic_wr),
		.cmd_data(pic_wdata),
		.resp_re(pic_resp_re),
		.reset_w(pic_reset_w),
		.reset_val(pic_reset),
		.resp_data(pic_rdata_param),
		.status(pic_status_param)
	);
	wolf_pic #(.RESPONSE_BYTES(128'h00004a0ea01845800614c3b203018444)) u_pic_dev528(
		.clk(clk),
		.rst(rst),
		.cmd_we(pic_wr),
		.cmd_data(pic_wdata),
		.resp_re(pic_resp_re),
		.reset_w(pic_reset_w),
		.reset_val(pic_reset),
		.resp_data(pic_rdata_dev),
		.status(pic_status_dev)
	);
	wolf_pic #(.RESPONSE_BYTES(128'h2b1e4a0e02176c60b4082509db019af6)) u_pic_umk3(
		.clk(clk),
		.rst(rst),
		.cmd_we(pic_wr),
		.cmd_data(pic_wdata),
		.resp_re(pic_resp_re),
		.reset_w(pic_reset_w),
		.reset_val(pic_reset),
		.resp_data(pic_rdata_umk3),
		.status(pic_status_umk3)
	);
	wolf_pic #(.RESPONSE_BYTES(128'h8c0969cd25197f61d70d41101003085b)) u_pic_rwt(
		.clk(clk),
		.rst(rst),
		.cmd_we(pic_wr),
		.cmd_data(pic_wdata),
		.resp_re(pic_resp_re),
		.reset_w(pic_reset_w),
		.reset_val(pic_reset),
		.resp_data(pic_rdata_rwt),
		.status(pic_status_rwt)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		pic_rdata_int = pic_rdata_param;
		pic_status_raw = pic_status_param;
		case (game_profile)
			3'd0, 3'd1, 3'd2, 3'd4, 3'd5: begin
				pic_rdata_int = pic_rdata_dev;
				pic_status_raw = pic_status_dev;
			end
			3'd3: begin
				pic_rdata_int = pic_rdata_umk3;
				pic_status_raw = pic_status_umk3;
			end
			3'd6: begin
				pic_rdata_int = pic_rdata_rwt;
				pic_status_raw = pic_status_rwt;
			end
			default: begin
				pic_rdata_int = pic_rdata_param;
				pic_status_raw = pic_status_param;
			end
		endcase
	end
	reg [19:0] pic_turn_cnt;
	reg pic_cold;
	reg pic_gate;
	always @(posedge clk)
		if (rst) begin
			pic_turn_cnt <= PIC_COLD_TURN[19:0];
			pic_cold <= 1'b1;
			pic_gate <= 1'b0;
		end
		else if (pic_reset_w && pic_reset) begin
			pic_turn_cnt <= PIC_COLD_TURN[19:0];
			pic_cold <= 1'b1;
			pic_gate <= 1'b0;
		end
		else if (pic_wr) begin
			pic_gate <= 1'b0;
			pic_turn_cnt <= (pic_cold ? PIC_COLD_TURN[19:0] : PIC_WARM_TURN[19:0]);
		end
		else if (pic_turn_cnt != 20'd0)
			pic_turn_cnt <= pic_turn_cnt - 20'd1;
		else begin
			pic_gate <= pic_status_raw;
			pic_cold <= 1'b0;
		end
	assign pic_status_int = (pic_status_delay_active ? pic_gate & pic_status_raw : pic_status_raw);
	reg [1:0] dstate;
	reg [31:0] d_addr_q;
	reg d_we_q;
	reg [31:0] d_wd_q;
	reg [5:0] d_sz_q;
	reg dma_ack;
	wire d_second = dstate == 2'd2;
	assign dma_reg_addr = (d_second ? d_addr_q[7:4] + 4'd1 : d_addr_q[7:4]);
	assign dma_reg_wdata = (d_second ? d_wd_q[31:16] : d_wd_q[15:0]);
	wire dma_word_accept = !DMA_REG_BACKPRESSURE || dma_reg_ready;
	assign dma_reg_offer = (dstate == 2'd1) || (dstate == 2'd2);
	assign dma_reg_we = dma_reg_offer && dma_word_accept;
	always @(posedge clk)
		if (rst) begin
			dstate <= 2'd0;
			dma_ack <= 1'b0;
		end
		else
			(* full_case, parallel_case *)
			case (dstate)
				2'd0: begin
					dma_ack <= 1'b0;
					if ((mem_req && is_dma_now) && !mem_ack) begin
						d_addr_q <= mem_addr;
						d_we_q <= mem_we;
						d_wd_q <= mem_wdata;
						d_sz_q <= mem_size;
						dstate <= (mem_we ? 2'd1 : 2'd3);
					end
				end
				2'd1:
					if (dma_word_accept)
						dstate <= (d_sz_q > 6'd16 ? 2'd2 : 2'd3);
				2'd2:
					if (dma_word_accept)
						dstate <= 2'd3;
				2'd3: begin
					dma_ack <= 1'b1;
					dstate <= 2'd0;
				end
				default: dstate <= 2'd0;
			endcase
	assign mem_req_m = (mem_req && !is_dma_now) && !((publication_hold_i && cpu_vram_now) && mem_we);
	assign mem_ack = (is_dma_now ? dma_ack : mem_ack_m);
	assign mem_rdata = (is_dma_now ? {16'h0000, dma_reg_rdata} : mem_rdata_m);
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_dcs_stub (
	clk,
	rst,
	snd_reset,
	snd_data_wr,
	snd_data_i,
	snd_data_rd,
	snd_rdata,
	snd_stat
);
	parameter signed [31:0] ACK_DELAY = 4;
	input wire clk;
	input wire rst;
	input wire snd_reset;
	input wire snd_data_wr;
	input wire [7:0] snd_data_i;
	input wire snd_data_rd;
	output wire [7:0] snd_rdata;
	output wire [15:0] snd_stat;
	localparam signed [31:0] CW = (ACK_DELAY <= 1 ? 1 : $clog2(ACK_DELAY + 1));
	localparam [CW - 1:0] ACK_LOAD = (ACK_DELAY <= 1 ? {CW {1'b0}} : ACK_DELAY - 1);
	reg input_full;
	reg output_full;
	reg [CW - 1:0] ack_cnt;
	reg [7:0] prev_cmd;
	reg [7:0] output_data;
	reg reply_pending;
	always @(posedge clk)
		if (rst || snd_reset) begin
			input_full <= 1'b0;
			output_full <= 1'b0;
			ack_cnt <= 1'sb0;
			prev_cmd <= 8'h00;
			output_data <= 8'hff;
			reply_pending <= 1'b0;
		end
		else begin
			if (snd_data_rd)
				output_full <= 1'b0;
			if (snd_data_wr) begin
				input_full <= 1'b1;
				ack_cnt <= ACK_LOAD;
				reply_pending <= (prev_cmd == 8'h03) && (snd_data_i == 8'he7);
				prev_cmd <= snd_data_i;
			end
			else if (input_full) begin
				if (ack_cnt == {CW {1'sb0}}) begin
					input_full <= 1'b0;
					if (reply_pending) begin
						output_data <= 8'h02;
						output_full <= 1'b1;
						reply_pending <= 1'b0;
					end
				end
				else
					ack_cnt <= ack_cnt - 1'b1;
			end
		end
	assign snd_stat = {4'h0, ~input_full, ~output_full, 10'h000};
	assign snd_rdata = (output_full ? output_data : 8'hff);
endmodule
module dcs_mem (
	clk,
	rst,
	core_ce,
	rom_req,
	rom_boot,
	rom_addr,
	rom_rdy,
	boot_rom_addr,
	boot_rom_rdy,
	rom_q,
	ext_req,
	ext_addr,
	ext_rdy,
	ext_q
);
	parameter DDR_LATENCY = 8;
	parameter PF_LINES = 512;
	parameter EXT_ROM = 0;
	parameter CORE_CE_EN = 0;
	input wire clk;
	input wire rst;
	input wire core_ce;
	input wire rom_req;
	input wire rom_boot;
	input wire [21:0] rom_addr;
	output wire rom_rdy;
	input wire [21:0] boot_rom_addr;
	output wire boot_rom_rdy;
	output wire [7:0] rom_q;
	output wire ext_req;
	output wire [18:0] ext_addr;
	input wire ext_rdy;
	input wire [63:0] ext_q;
	function [7:0] rom_byte;
		input [21:0] idx;
		rom_byte = idx[7:0];
	endfunction
	localparam IDXW = $clog2(PF_LINES);
	localparam TAGW = 19 - IDXW;
	(* ramstyle = "no_rw_check, M10K" *) reg [63:0] pf_data [0:PF_LINES - 1];
	(* ramstyle = "no_rw_check, M10K" *) reg [TAGW - 1:0] pf_tag [0:PF_LINES - 1];
	reg pf_valid [0:PF_LINES - 1];
	localparam [2:0] R_IDLE = 3'd0;
	localparam [2:0] R_ADDR = 3'd1;
	localparam [2:0] R_LOOK = 3'd2;
	localparam [2:0] R_FILL = 3'd3;
	localparam [2:0] R_SERVE = 3'd4;
	reg [2:0] rstate = R_IDLE;
	reg [21:0] srv_addr;
	reg srv_boot;
	reg [7:0] srv_byte;
	reg [15:0] ddr_cnt;
	reg [63:0] ddr_beat;
	reg [63:0] pfd_q;
	reg [TAGW - 1:0] pft_q;
	reg pfv_q;
	reg ext_rsp_valid;
	reg [63:0] ext_rsp_q;
	wire mem_ce = (CORE_CE_EN != 0 ? core_ce : 1'b1);
	wire [IDXW - 1:0] req_idx = rom_addr[3+:IDXW];
	wire [TAGW - 1:0] req_tag = rom_addr[21-:TAGW];
	wire [IDXW - 1:0] srv_idx = srv_addr[3+:IDXW];
	wire [TAGW - 1:0] srv_tag = srv_addr[21-:TAGW];
	assign rom_rdy = ((rstate == R_SERVE) && rom_req) && (rom_addr == srv_addr);
	assign boot_rom_rdy = ((rstate == R_SERVE) && rom_boot) && (boot_rom_addr == srv_addr);
	assign rom_q = srv_byte;
	assign ext_req = ((EXT_ROM != 0) && (rstate == R_FILL)) && !ext_rsp_valid;
	assign ext_addr = srv_addr[21:3];
	always @(posedge clk)
		if (mem_ce) begin
			pfd_q <= pf_data[srv_idx];
			pft_q <= pf_tag[srv_idx];
			pfv_q <= pf_valid[srv_idx];
		end
	always @(posedge clk)
		if (rst) begin
			ext_rsp_valid <= 1'b0;
			ext_rsp_q <= 64'd0;
		end
		else if ((((EXT_ROM != 0) && ext_rdy) && (rstate == R_FILL)) && !ext_rsp_valid) begin
			ext_rsp_valid <= 1'b1;
			ext_rsp_q <= ext_q;
		end
		else if ((mem_ce && (rstate == R_FILL)) && ext_rsp_valid)
			ext_rsp_valid <= 1'b0;
	integer pf_hits_w = 0;
	integer pf_miss_w = 0;
	integer pf_hits_b = 0;
	integer pf_miss_b = 0;
	function [63:0] ddr_beat_fn;
		input [21:0] a;
		integer bi;
		for (bi = 0; bi < 8; bi = bi + 1)
			ddr_beat_fn[8 * bi+:8] = rom_byte({a[21:3], 3'b000} + bi[21:0]);
	endfunction
	integer ri;
	always @(posedge clk)
		if (rst) begin
			rstate <= R_IDLE;
			srv_addr <= 1'sb0;
			srv_boot <= 1'b0;
			srv_byte <= 8'h00;
			ddr_cnt <= 1'sb0;
			ddr_beat <= 1'sb0;
			for (ri = 0; ri < PF_LINES; ri = ri + 1)
				pf_valid[ri] <= 1'b0;
		end
		else if (mem_ce)
			case (rstate)
				R_IDLE:
					if (rom_req) begin
						srv_addr <= rom_addr;
						srv_boot <= rom_boot;
						rstate <= R_ADDR;
					end
				R_ADDR: rstate <= R_LOOK;
				R_LOOK:
					if (pfv_q && (pft_q == srv_tag)) begin
						srv_byte <= pfd_q[8 * srv_addr[2:0]+:8];
						rstate <= R_SERVE;
					end
					else begin
						if (EXT_ROM == 0)
							ddr_cnt <= DDR_LATENCY[15:0];
						rstate <= R_FILL;
					end
				R_FILL:
					if (((EXT_ROM != 0) && ext_rsp_valid) || ((EXT_ROM == 0) && (ddr_cnt <= 16'd1))) begin
						if (EXT_ROM != 0)
							ddr_beat = ext_rsp_q;
						else
							ddr_beat = ddr_beat_fn(srv_addr);
						pf_data[srv_idx] <= ddr_beat;
						pf_tag[srv_idx] <= srv_tag;
						pf_valid[srv_idx] <= 1'b1;
						srv_byte <= ddr_beat[8 * srv_addr[2:0]+:8];
						rstate <= R_SERVE;
					end
					else if (EXT_ROM == 0)
						ddr_cnt <= ddr_cnt - 16'd1;
				R_SERVE:
					if (!rom_req)
						rstate <= R_IDLE;
					else if (rom_addr != srv_addr) begin
						srv_addr <= rom_addr;
						srv_boot <= rom_boot;
						rstate <= R_ADDR;
					end
			endcase
	integer k;
	integer romfd;
endmodule
module adsp2105 (
	clk,
	rst,
	core_ce,
	host_rst,
	host_cmd_w,
	host_cmd_data,
	host_status_r,
	host_response_r,
	host_resp_rd,
	rom_ddr_req,
	rom_ddr_addr,
	rom_ddr_rdy,
	rom_ddr_q,
	dac_ce_in,
	o_ppc,
	o_valid,
	o_unimpl,
	dac_sample,
	dac_ce
);
	reg _sv2v_0;
	parameter PMFILE = "pm.hex";
	parameter RD_LATENCY = 1;
	parameter DDR_LATENCY = 8;
	parameter PF_LINES = 512;
	parameter EXT_ROM = 0;
	parameter CORE_CE_EN = 0;
	parameter EXPLICIT_RAM_CE = 1;
	parameter SHARED_REG_READ = 1;
	parameter MLAB_PC_STACK = 1;
	parameter SHARED_DAG_WRITE = 1;
	parameter SHARED_MAC = 1;
	parameter MLAB_STATUS_STACK = 1;
	parameter SHARED_ALU = 1;
	parameter SHARED_SHIFT = 1;
	parameter SHARED_EXEC = 1;
	parameter SHARED_PM = 1;
	parameter PCM_STREAM = 0;
	input wire clk;
	input wire rst;
	input wire core_ce;
	input wire host_rst;
	input wire host_cmd_w;
	input wire [15:0] host_cmd_data;
	output wire [15:0] host_status_r;
	output wire [15:0] host_response_r;
	input wire host_resp_rd;
	output wire rom_ddr_req;
	output wire [18:0] rom_ddr_addr;
	input wire rom_ddr_rdy;
	input wire [63:0] rom_ddr_q;
	input wire dac_ce_in;
	output reg [13:0] o_ppc;
	output reg o_valid;
	output reg o_unimpl;
	output reg [15:0] dac_sample;
	output reg dac_ce;
	reg [15:0] gr [0:31];
	wire cpu_ce = (CORE_CE_EN != 0 ? core_ce : 1'b1);
	reg [15:0] iR [0:7];
	reg [15:0] mR [0:7];
	reg [15:0] lR [0:7];
	reg [13:0] baseR [0:7];
	reg [13:0] lmask [0:7];
	reg [15:0] astat;
	reg [15:0] mstat;
	reg [15:0] sstat;
	reg [15:0] imask;
	reg [15:0] icntl;
	reg [15:0] px;
	reg [15:0] afb [0:1];
	reg [15:0] mfb [0:1];
	reg [15:0] sbb [0:1];
	reg [15:0] mrzb [0:1];
	wire bnk = mstat[0];
	reg [13:0] cntr;
	reg [10:0] data_bank;
	(* ramstyle = "no_rw_check, M10K" *) reg [23:0] pm [0:16383];
	(* ramstyle = "no_rw_check, M10K" *) reg [23:0] pm2 [0:16383];
	(* ramstyle = "no_rw_check, M10K" *) reg [15:0] dm [0:16383];
	reg pm_we;
	reg [13:0] pm_wa;
	reg [23:0] pm_wd;
	reg [13:0] pm_port_b_addr;
	reg [13:0] pc;
	wire [13:0] fetch_addr = pc;
	reg [23:0] fetch_r;
	wire [23:0] fetch_q = fetch_r;
	wire [13:0] pmb_addr;
	reg [23:0] pmb_q;
	wire [13:0] dm_addr;
	reg [15:0] dm_q;
	always @(posedge clk)
		if (cpu_ce && !EXPLICIT_RAM_CE) begin
			fetch_r <= pm[fetch_addr];
			if (!SHARED_PM)
				pmb_q <= pm2[pmb_addr];
			dm_q <= dm[dm_addr];
		end
	wire rom_req;
	wire [21:0] rom_addr;
	wire rom_rdy;
	wire boot_rom_rdy;
	wire [7:0] rom_q;
	reg boot_active;
	reg [11:0] boot_idx;
	reg [1:0] boot_phase;
	reg [10:0] boot_bank;
	wire [23:0] boot_rom_base = {13'h0000, boot_bank} << 12;
	wire [23:0] boot_rom_addr24 = (boot_phase == 2'd0 ? boot_rom_base + 24'd3 : (boot_rom_base + ({12'h000, boot_idx} << 2)) + {22'h000000, boot_phase - 2'd1});
	dcs_mem #(
		.DDR_LATENCY(DDR_LATENCY),
		.PF_LINES(PF_LINES),
		.EXT_ROM(EXT_ROM),
		.CORE_CE_EN(CORE_CE_EN)
	) u_mem(
		.clk(clk),
		.rst(rst),
		.core_ce(cpu_ce),
		.rom_req(rom_req),
		.rom_boot(boot_active),
		.rom_addr(rom_addr),
		.rom_rdy(rom_rdy),
		.rom_q(rom_q),
		.boot_rom_addr(boot_rom_addr24[21:0]),
		.boot_rom_rdy(boot_rom_rdy),
		.ext_req(rom_ddr_req),
		.ext_addr(rom_ddr_addr),
		.ext_rdy(rom_ddr_rdy),
		.ext_q(rom_ddr_q)
	);
	function [7:0] snd_byte;
		input [21:0] idx;
		snd_byte = 8'hff;
	endfunction
	localparam [2:0] S_BOOT = 3'd0;
	localparam [2:0] S_FETCH = 3'd1;
	localparam [2:0] S_DECODE = 3'd2;
	localparam [2:0] S_DRAIN = 3'd3;
	localparam [2:0] S_DIV = 3'd4;
	localparam [2:0] S_ROM = 3'd5;
	localparam [2:0] S_MEM = 3'd6;
	localparam [2:0] S_EXEC = 3'd7;
	reg [2:0] state;
	reg [13:0] loop_end [0:3];
	reg [3:0] loop_cond [0:3];
	integer loop_sp;
	reg [13:0] pc_stack [0:15];
	(* ramstyle = "MLAB, no_rw_check" *) reg [13:0] pc_mem [0:15];
	integer pc_sp;
	reg pc_push_we;
	reg [31:0] pc_push_addr;
	reg [31:0] pc_last_addr;
	reg [13:0] pc_push_data;
	reg [13:0] pc_last_data;
	reg pc_last_valid;
	reg pc_write_toggle;
	reg pc_written_toggle;
	wire [31:0] pc_read_addr = pc_sp - 1;
	wire [13:0] pc_top = (MLAB_PC_STACK ? (pc_last_valid && (pc_read_addr == pc_last_addr) ? pc_last_data : pc_mem[pc_read_addr]) : pc_stack[pc_read_addr]);
	task automatic push_pc;
		input [13:0] value;
		if (MLAB_PC_STACK) begin
			pc_push_we = 1'b1;
			pc_push_addr = pc_sp;
			pc_push_data = value;
		end
		else
			pc_stack[pc_sp] <= value;
	endtask
	reg [13:0] cntr_stack [0:3];
	integer cntr_sp;
	reg host_rst_r;
	reg reboot_pending;
	reg [10:0] reboot_bank;
	reg [11:0] boot_plen;
	reg [7:0] boot_b0;
	reg [7:0] boot_b1;
	reg [15:0] stat_mstat [0:15];
	reg [15:0] stat_imask [0:15];
	reg [15:0] stat_astat [0:15];
	integer stat_sp;
	(* ramstyle = "MLAB, no_rw_check" *) reg [47:0] status_mem [0:15];
	reg [31:0] status_last_addr;
	reg [47:0] status_last_data;
	reg status_last_valid;
	wire [31:0] status_read_addr = stat_sp - 1;
	wire [47:0] status_top = (status_last_valid && (status_read_addr == status_last_addr) ? status_last_data : status_mem[status_read_addr]);
	reg [8:0] tim_scale;
	reg [15:0] tim_count;
	reg [15:0] tim_period;
	reg [8:0] tim_scale_cnt;
	reg tim_irq_latch;
	reg ab_active;
	reg [2:0] ab_ireg;
	reg [15:0] ab_base;
	reg [15:0] ab_size;
	reg [15:0] ab_incs;
	reg [15:0] dac_slot_ctr;
	reg dac_slot_go;
	reg [15:0] ab_cfg;
	integer ab_ir;
	integer ab_mr;
	integer ab_lr;
	integer ab_cnt;
	integer ab_reg;
	reg [15:0] input_data;
	reg irq2_line;
	reg irq2_latch;
	reg [15:0] latch_control;
	reg [15:0] output_data;
	assign host_status_r = latch_control;
	assign host_response_r = output_data;
	reg irq1_pulse;
	integer ab_i;
	reg [15:0] ab_smp;
	reg [15:0] dac_emit_burst [0:511];
	integer dac_burst_len;
	localparam [13:0] NO_LOOP = 14'h3fff;
	reg [15:0] ctl_s1_autobuf;
	reg [15:0] ctl_syscontrol;
	localparam [1:0] RG_DM = 2'd0;
	localparam [1:0] RG_ALIAS = 2'd1;
	localparam [1:0] RG_BANK = 2'd2;
	localparam [1:0] RG_LATCH = 2'd3;
	function [1:0] dm_region;
		input [15:0] a;
		if ((a >= 16'h0800) && (a <= 16'h1fff))
			dm_region = RG_ALIAS;
		else if ((a >= 16'h2000) && (a <= 16'h2fff))
			dm_region = RG_BANK;
		else if ((a >= 16'h3400) && (a <= 16'h3403))
			dm_region = RG_LATCH;
		else
			dm_region = RG_DM;
	endfunction
	reg pre_dm_rd;
	reg pre_dm_wr;
	reg pre_pm_rd;
	reg [15:0] pre_addr;
	reg [13:0] pre_pm_addr;
	function [13:0] rev14;
		input [13:0] a;
		integer j;
		for (j = 0; j < 14; j = j + 1)
			rev14[j] = a[13 - j];
	endfunction
	function [15:0] dag_addr;
		input [2:0] w;
		if (!w[2] && mstat[1])
			dag_addr = {2'b00, rev14(iR[w][13:0])};
		else
			dag_addr = iR[w];
	endfunction
	always @(*) begin
		pre_dm_rd = 1'b0;
		pre_dm_wr = 1'b0;
		pre_pm_rd = 1'b0;
		pre_addr = 16'h0000;
		pre_pm_addr = 14'h0000;
		casez (fetch_q[23:16])
			8'h11:
				if (!fetch_q[15]) begin
					pre_pm_rd = 1'b1;
					pre_pm_addr = iR[{1'b1, fetch_q[3:2]}][13:0];
				end
			8'h12, 8'h13: begin
				pre_addr = dag_addr({fetch_q[16], fetch_q[3:2]});
				if (fetch_q[15])
					pre_dm_wr = 1'b1;
				else
					pre_dm_rd = 1'b1;
			end
			8'b0101zzzz:
				if (!fetch_q[19]) begin
					pre_pm_rd = 1'b1;
					pre_pm_addr = iR[{1'b1, fetch_q[3:2]}][13:0];
				end
			8'b011zzzzz: begin
				pre_addr = dag_addr({fetch_q[20], fetch_q[3:2]});
				if (fetch_q[19])
					pre_dm_wr = 1'b1;
				else
					pre_dm_rd = 1'b1;
			end
			8'b100zzzzz: begin
				pre_addr = {2'b00, fetch_q[17:4]};
				if (fetch_q[20])
					pre_dm_wr = 1'b1;
				else
					pre_dm_rd = 1'b1;
			end
			8'b101zzzzz: begin
				pre_addr = dag_addr({fetch_q[20], fetch_q[3:2]});
				pre_dm_wr = 1'b1;
			end
			default:
				;
		endcase
	end
	wire [1:0] pre_region = dm_region(pre_addr);
	wire pre_bank_rd = pre_dm_rd && (pre_region == RG_BANK);
	wire [1:0] mem_need = ((((pre_dm_rd && (pre_region != RG_LATCH)) && (pre_region != RG_BANK)) || (pre_dm_wr && (pre_region == RG_ALIAS))) || pre_pm_rd ? 2'd1 : 2'd0);
	reg [23:0] op_r;
	reg [5:0] generic_read_select_r;
	reg [15:0] ea_addr_r;
	reg [13:0] pm_addr_r;
	reg pm_rd_r;
	reg bank_rd_r;
	reg tx1_r;
	reg [1:0] mem_need_r;
	wire pre_tx1_wr = ((((fetch_q[23:16] == 8'h0d) && (fetch_q[11:10] == 2'd3)) && (fetch_q[7:4] == 4'hb)) || (((fetch_q[23:20] == 4'h3) && (fetch_q[19:18] == 2'd3)) && (fetch_q[3:0] == 4'hb))) || ((((fetch_q[23:21] == 3'b100) && !fetch_q[20]) && (fetch_q[19:18] == 2'd3)) && (fetch_q[3:0] == 4'hb));
	wire [2:0] pre_ab_lr = ctl_s1_autobuf[11:9];
	wire [2:0] pre_ab_mr = {ctl_s1_autobuf[11], ctl_s1_autobuf[8:7]};
	wire [15:0] pre_ab_incs = (mR[pre_ab_mr] == 16'h0000 ? 16'h0001 : mR[pre_ab_mr]);
	reg div_done;
	reg [4:0] div_i;
	reg [15:0] div_q;
	reg [15:0] div_nd;
	reg [16:0] div_rem;
	reg [16:0] div_v;
	reg [17:0] div_t;
	reg [15:0] ab_drain_cnt;
	reg dr_done;
	integer dr_idx;
	integer dr_acc;
	integer dr_cnt;
	reg [1:0] dr_region;
	reg [21:0] dr_rom_a;
	reg [15:0] dr_smp;
	wire drain_pend = ab_active && dac_slot_go;
	wire [31:0] dr_cur = (dr_idx == 0 ? {16'h0000, iR[ab_ireg]} : dr_acc);
	assign pmb_addr = (state == S_DRAIN ? dr_cur[13:0] : (pm_rd_r ? pm_addr_r : ea_addr_r[13:0]));
	assign dm_addr = (state == S_DRAIN ? dr_cur[13:0] : ea_addr_r[13:0]);
	assign rom_addr = (boot_active ? boot_rom_addr24[21:0] : (state == S_DECODE ? {data_bank, 12'h000} + {10'h000, pre_addr[11:0]} : {data_bank, 12'h000} + {10'h000, ea_addr_r[11:0]}));
	assign rom_req = (boot_active | ((state == S_DECODE) && pre_bank_rd)) | ((((((state == S_DRAIN) || (state == S_DIV)) || (state == S_ROM)) || (state == S_MEM)) || (state == S_EXEC)) && bank_rd_r);
	function automatic integer cond_true;
		input [3:0] c;
		reg az;
		reg an;
		reg av;
		reg ac;
		reg as;
		reg mv;
		begin
			az = astat[0];
			an = astat[1];
			av = astat[2];
			ac = astat[3];
			as = astat[4];
			mv = astat[6];
			case (c)
				4'h0: cond_true = az;
				4'h1: cond_true = !az;
				4'h2: cond_true = !((an ^ av) | az);
				4'h3: cond_true = (an ^ av) | az;
				4'h4: cond_true = an ^ av;
				4'h5: cond_true = !(an ^ av);
				4'h6: cond_true = av;
				4'h7: cond_true = !av;
				4'h8: cond_true = ac;
				4'h9: cond_true = !ac;
				4'ha: cond_true = as;
				4'hb: cond_true = !as;
				4'hc: cond_true = mv;
				4'hd: cond_true = !mv;
				4'he: cond_true = 1'bx;
				4'hf: cond_true = 1'b1;
			endcase
		end
	endfunction
	task automatic cond_eval;
		input [3:0] c;
		output reg ct;
		if (c == 4'hf)
			ct = 1'b1;
		else if (c == 4'he) begin
			if (($signed({1'b0, cntr}) - 1) > 0) begin
				cntr <= cntr - 1'b1;
				ct = 1'b1;
			end
			else begin
				cntr <= cntr_stack[cntr_sp - 1];
				cntr_sp <= cntr_sp - 1;
				ct = 1'b0;
			end
		end
		else
			ct = (cond_true(c) ? 1'b1 : 1'b0);
	endtask
	function [13:0] mask_fn;
		input [13:0] l;
		integer mb;
		for (mb = 0; mb < 14; mb = mb + 1)
			mask_fn[mb] = l <= (14'h0001 << mb);
	endfunction
	task automatic wr_ireg;
		input [2:0] w;
		input [15:0] val;
		begin
			iR[w] <= val;
			baseR[w] <= val[13:0] & lmask[w];
		end
	endtask
	task automatic wr_lreg;
		input [2:0] w;
		input [15:0] val;
		begin
			lR[w] <= val;
			lmask[w] <= mask_fn(val[13:0]);
			baseR[w] <= iR[w][13:0] & mask_fn(val[13:0]);
		end
	endtask
	task automatic dag_modify;
		input [2:0] w;
		input [2:0] m;
		reg [13:0] i2;
		begin
			i2 = (iR[w][13:0] + mR[m][13:0]) & 14'h3fff;
			if (i2 < baseR[w])
				i2 = i2 + lR[w][13:0];
			else if (i2 >= (baseR[w] + lR[w][13:0]))
				i2 = i2 - lR[w][13:0];
			iR[w] <= {2'b00, i2};
		end
	endtask
	reg exec_reg_we;
	reg exec_dag_we;
	reg exec_dm_we;
	reg [15:0] exec_dm_addr;
	reg [15:0] exec_dm_data;
	reg [1:0] exec_reg_group;
	reg [3:0] exec_reg_index;
	reg [15:0] exec_reg_data;
	reg [2:0] exec_dag_index;
	reg [2:0] exec_dag_modifier;
	task automatic request_dag_modify;
		input [2:0] w;
		input [2:0] m;
		if (SHARED_EXEC) begin
			exec_dag_we = 1'b1;
			exec_dag_index = w;
			exec_dag_modifier = m;
		end
		else
			dag_modify(w, m);
	endtask
	task automatic set_mstat;
		input [15:0] nm;
		mstat <= nm;
	endtask
	task automatic wr_reg;
		input [1:0] grp;
		input [3:0] idx;
		input [15:0] val;
		reg [2:0] dag_index;
		if (SHARED_DAG_WRITE && ((grp == 2'd1) || (grp == 2'd2))) begin
			dag_index = {grp[1], idx[1:0]};
			case (idx[3:2])
				2'd0:
					wr_ireg(dag_index, {2'b00, val[13:0]});
				2'd1: mR[dag_index] <= {{2 {val[13]}}, val[13:0]};
				2'd2:
					wr_lreg(dag_index, {2'b00, val[13:0]});
				default:
					;
			endcase
		end
		else
			case (grp)
				2'd0:
					case (idx)
						4'h9: gr[{bnk, 4'b0000} + 9] <= {{8 {val[7]}}, val[7:0]};
						4'hc: begin
							gr[{bnk, 4'b0000} + 12] <= val;
							gr[{bnk, 4'b0000} + 13] <= {16 {val[15]}};
						end
						4'hd: gr[{bnk, 4'b0000} + 13] <= {{8 {val[7]}}, val[7:0]};
						default: gr[{bnk, 4'b0000} + idx] <= val;
					endcase
				2'd1:
					case (idx)
						4'd0, 4'd1, 4'd2, 4'd3:
							wr_ireg(idx[2:0], {2'b00, val[13:0]});
						4'd4, 4'd5, 4'd6, 4'd7: mR[idx - 4] <= {{2 {val[13]}}, val[13:0]};
						4'd8, 4'd9, 4'd10, 4'd11:
							wr_lreg(idx[2:0], {2'b00, val[13:0]});
						default:
							;
					endcase
				2'd2:
					case (idx)
						4'd0, 4'd1, 4'd2, 4'd3:
							wr_ireg(idx[2:0] + 3'd4, {2'b00, val[13:0]});
						4'd4, 4'd5, 4'd6, 4'd7: mR[idx] <= {{2 {val[13]}}, val[13:0]};
						4'd8, 4'd9, 4'd10, 4'd11:
							wr_lreg(idx[2:0] + 3'd4, {2'b00, val[13:0]});
						default:
							;
					endcase
				2'd3:
					case (idx)
						4'd0: astat <= val;
						4'd1:
							set_mstat(val);
						4'd2: sstat <= val;
						4'd3: imask <= val;
						4'd4: icntl <= val;
						4'd5: begin
							cntr_stack[cntr_sp] <= cntr;
							cntr_sp <= cntr_sp + 1;
							cntr <= val[13:0];
						end
						4'd6: sbb[bnk] <= val;
						4'd7: px <= val;
						4'hd: cntr <= val[13:0];
						4'hf: begin
							push_pc(val[13:0]);
							pc_sp <= pc_sp + 1;
						end
						4'hb: begin
							ab_cfg = ctl_s1_autobuf;
							if ((ctl_syscontrol & 16'h0800) && (ab_cfg & 16'h0002)) begin
								ab_ir = (ab_cfg >> 9) & 7;
								ab_mr = ((ab_cfg >> 7) & 3) | (((ab_cfg >> 9) & 7) & 4);
								ab_lr = (ab_cfg >> 9) & 7;
								iR[ab_ir] <= iR[ab_ir] & 16'hfff0;
								baseR[ab_ir] <= (iR[ab_ir][13:0] & 14'h3ff0) & lmask[ab_ir];
								ab_base <= iR[ab_ir] & 16'hfff0;
								ab_size <= lR[ab_lr];
								ab_incs <= mR[ab_mr];
								ab_ireg <= ab_ir[2:0];
								ab_cnt = div_q;
								ab_drain_cnt <= div_q;
								dac_slot_ctr <= ab_cnt[15:0];
								dac_slot_go <= 1'b0;
								ab_active <= 1'b1;
							end
						end
						default:
							;
					endcase
			endcase
	endtask
	task automatic request_reg_write;
		input [1:0] grp;
		input [3:0] idx;
		input [15:0] val;
		if (SHARED_EXEC) begin
			exec_reg_we = 1'b1;
			exec_reg_group = grp;
			exec_reg_index = idx;
			exec_reg_data = val;
		end
		else
			wr_reg(grp, idx, val);
	endtask
	task automatic dm_write;
		input [15:0] addr;
		input [15:0] val;
		if ((addr >= 16'h0800) && (addr <= 16'h1fff)) begin
			pm_we = 1'b1;
			pm_wa = addr[13:0];
			pm_wd = {val, pmb_q[7:0]};
		end
		else if (addr == 16'h3000)
			data_bank <= val[10:0];
		else if ((addr >= 16'h3400) && (addr <= 16'h3403)) begin
			output_data <= val;
			latch_control <= latch_control & ~16'h0400;
		end
		else begin
			if (!EXPLICIT_RAM_CE)
				dm[addr[13:0]] <= val;
			if (addr == 16'h3fef)
				ctl_s1_autobuf <= val;
			if (addr == 16'h3ffb) begin
				tim_scale <= {1'b0, val[7:0]} + 9'd1;
				tim_scale_cnt <= {1'b0, val[7:0]} + 9'd1;
			end
			if (addr == 16'h3ffc) begin
				tim_count <= val;
				tim_scale_cnt <= tim_scale;
			end
			if (addr == 16'h3ffd)
				tim_period <= val;
			if (addr == 16'h3fff) begin
				ctl_syscontrol <= val;
				if (val[9]) begin
					reboot_pending <= 1'b1;
					reboot_bank <= data_bank;
				end
			end
		end
	endtask
	task automatic request_dm_write;
		input [15:0] addr;
		input [15:0] val;
		if (SHARED_EXEC) begin
			exec_dm_we = 1'b1;
			exec_dm_addr = addr;
			exec_dm_data = val;
		end
		else
			dm_write(addr, val);
	endtask
	function automatic [15:0] rd_reg;
		input [1:0] grp;
		input [3:0] idx;
		case (grp)
			2'd0: rd_reg = gr[{bnk, 4'b0000} + idx];
			2'd1:
				case (idx)
					4'd0, 4'd1, 4'd2, 4'd3: rd_reg = iR[idx];
					4'd4, 4'd5, 4'd6, 4'd7: rd_reg = mR[idx - 4];
					4'd8, 4'd9, 4'd10, 4'd11: rd_reg = lR[idx - 8];
					default: rd_reg = 16'h0000;
				endcase
			2'd2:
				case (idx)
					4'd0, 4'd1, 4'd2, 4'd3: rd_reg = iR[idx + 4];
					4'd4, 4'd5, 4'd6, 4'd7: rd_reg = mR[idx];
					4'd8, 4'd9, 4'd10, 4'd11: rd_reg = lR[idx - 4];
					default: rd_reg = 16'h0000;
				endcase
			2'd3:
				case (idx)
					4'd0: rd_reg = astat;
					4'd1: rd_reg = mstat;
					4'd2: rd_reg = sstat;
					4'd3: rd_reg = imask;
					4'd4: rd_reg = icntl;
					4'd5: rd_reg = {2'b00, cntr};
					4'd6: rd_reg = sbb[bnk];
					4'd7: rd_reg = px;
					default: rd_reg = 16'h0000;
				endcase
		endcase
	endfunction
	function automatic [5:0] shared_reg_read_select;
		input [23:0] instruction;
		reg [7:0] opcode_hi;
		reg [1:0] read_group;
		reg [3:0] read_index;
		begin
			opcode_hi = instruction[23:16];
			if (opcode_hi == 8'h0d)
				read_group = instruction[9:8];
			else if (opcode_hi[7:5] == 3'b100)
				read_group = instruction[19:18];
			else
				read_group = 2'd0;
			if ((((opcode_hi == 8'h0d) || (opcode_hi == 8'h10)) || (opcode_hi[7:3] == 5'b00101)) || (opcode_hi[7:5] == 3'b100))
				read_index = instruction[3:0];
			else
				read_index = instruction[7:4];
			shared_reg_read_select = {read_group, read_index};
		end
	endfunction
	function [15:0] alu_xread;
		input [2:0] xi;
		case (xi)
			3'd0: alu_xread = gr[{bnk, 4'b0000} + 0];
			3'd1: alu_xread = gr[{bnk, 4'b0000} + 1];
			3'd2: alu_xread = gr[{bnk, 4'b0000} + 10];
			3'd3: alu_xread = gr[{bnk, 4'b0000} + 11];
			3'd4: alu_xread = gr[{bnk, 4'b0000} + 12];
			3'd5: alu_xread = gr[{bnk, 4'b0000} + 13];
			3'd6: alu_xread = gr[{bnk, 4'b0000} + 14];
			3'd7: alu_xread = gr[{bnk, 4'b0000} + 15];
		endcase
	endfunction
	function [15:0] alu_yread;
		input [1:0] yi;
		case (yi)
			2'd0: alu_yread = gr[{bnk, 4'b0000} + 4];
			2'd1: alu_yread = gr[{bnk, 4'b0000} + 5];
			2'd2: alu_yread = afb[bnk];
			2'd3: alu_yread = 16'h0000;
		endcase
	endfunction
	function [15:0] c_nz;
		input [15:0] a;
		input [31:0] r;
		begin
			c_nz = a;
			if ((r & 32'h0000ffff) == 0)
				c_nz = c_nz | 16'h0001;
			c_nz = c_nz | ((r >> 14) & 16'h0002);
		end
	endfunction
	function [15:0] c_v;
		input [15:0] a;
		input [31:0] s;
		input [31:0] d;
		input [31:0] r;
		c_v = a | (((((s ^ d) ^ r) ^ (r >> 1)) >> 13) & 16'h0004);
	endfunction
	function automatic [31:0] alu_eval;
		input [3:0] sub;
		input [15:0] xv;
		input [15:0] yv;
		reg [16:0] r;
		reg [15:0] astn;
		reg cin;
		reg [31:0] s32;
		reg [31:0] d32;
		reg [31:0] r32;
		reg [16:0] add_a;
		reg [16:0] add_b;
		reg [16:0] add_result;
		reg add_cin;
		begin
			cin = astat[3];
			astn = astat & ~16'h000f;
			if (SHARED_ALU) begin
				add_a = {1'b0, xv};
				add_b = {1'b0, yv};
				add_cin = 1'b0;
				case (sub)
					4'h1: begin
						add_a = {1'b0, yv};
						add_b = 17'd0;
						add_cin = 1'b1;
					end
					4'h2: add_cin = cin;
					4'h5: begin
						add_a = 17'd0;
						add_b = ~{1'b0, yv};
						add_cin = 1'b1;
					end
					4'h6, 4'h7: begin
						add_b = ~{1'b0, yv};
						add_cin = (sub == 4'h7) | cin;
					end
					4'h8: begin
						add_a = {1'b0, yv};
						add_b = 17'h1ffff;
					end
					4'h9, 4'ha: begin
						add_a = {1'b0, yv};
						add_b = ~{1'b0, xv};
						add_cin = (sub == 4'h9) | cin;
					end
					4'hf: begin
						add_a = 17'd0;
						add_b = ~{1'b0, xv};
						add_cin = 1'b1;
					end
					default:
						;
				endcase
				add_result = (add_a + add_b) + {16'd0, add_cin};
				case (sub)
					4'h0: r = {1'b0, yv};
					4'h4: r = {1'b0, ~yv};
					4'hb: r = {1'b0, ~xv};
					4'hc: r = {1'b0, xv & yv};
					4'hd: r = {1'b0, xv | yv};
					4'he: r = {1'b0, xv ^ yv};
					4'hf: r = (xv[15] ? add_result : {1'b0, xv});
					default: r = add_result;
				endcase
			end
			else
				case (sub)
					4'h0: r = {1'b0, yv};
					4'h1: r = {1'b0, yv} + 17'd1;
					4'h2: r = ({1'b0, xv} + {1'b0, yv}) + {16'h0000, cin};
					4'h3: r = {1'b0, xv} + {1'b0, yv};
					4'h4: r = {1'b0, ~yv};
					4'h5: r = 17'h00000 - {1'b0, yv};
					4'h6: r = (({1'b0, xv} - {1'b0, yv}) + {16'h0000, cin}) - 17'd1;
					4'h7: r = {1'b0, xv} - {1'b0, yv};
					4'h8: r = {1'b0, yv} - 17'd1;
					4'h9: r = {1'b0, yv} - {1'b0, xv};
					4'ha: r = (({1'b0, yv} - {1'b0, xv}) + {16'h0000, cin}) - 17'd1;
					4'hb: r = {1'b0, ~xv};
					4'hc: r = {1'b0, xv & yv};
					4'hd: r = {1'b0, xv | yv};
					4'he: r = {1'b0, xv ^ yv};
					4'hf: r = (xv[15] ? 17'h00000 - {1'b0, xv} : {1'b0, xv});
				endcase
			astn = c_nz(astn, {15'h0000, r});
			s32 = {16'h0000, xv};
			d32 = {16'h0000, yv};
			r32 = {15'h0000, r};
			case (sub)
				4'h2, 4'h3: begin
					astn = c_v(astn, s32, d32, r32);
					astn = astn | ((r32 >> 13) & 16'h0008);
				end
				4'h6, 4'h7: begin
					astn = c_v(astn, s32, d32, r32);
					astn = astn | ((~r32 >> 13) & 16'h0008);
				end
				4'h9, 4'ha: begin
					astn = c_v(astn, d32, s32, r32);
					astn = astn | ((~r32 >> 13) & 16'h0008);
				end
				4'h1:
					if (yv == 16'h7fff)
						astn = astn | 16'h0004;
					else if (yv == 16'hffff)
						astn = astn | 16'h0008;
				4'h5: begin
					if (yv == 16'h8000)
						astn = astn | 16'h0004;
					if (yv == 16'h0000)
						astn = astn | 16'h0008;
				end
				4'h8:
					if (yv == 16'h8000)
						astn = astn | 16'h0004;
					else if (yv == 16'h0000)
						astn = astn | 16'h0008;
				4'hf: begin
					astn = astat & ~16'h001f;
					if (xv == 16'h0000)
						astn = astn | 16'h0001;
					if (xv == 16'h8000)
						astn = astn | 16'h0006;
					if (xv[15])
						astn = astn | 16'h0010;
				end
				default:
					;
			endcase
			alu_eval = {astn, r[15:0]};
		end
	endfunction
	function [15:0] mac_xread;
		input [2:0] xi;
		case (xi)
			3'd0: mac_xread = gr[{bnk, 4'b0000} + 2];
			3'd1: mac_xread = gr[{bnk, 4'b0000} + 3];
			3'd2: mac_xread = gr[{bnk, 4'b0000} + 10];
			3'd3: mac_xread = gr[{bnk, 4'b0000} + 11];
			3'd4: mac_xread = gr[{bnk, 4'b0000} + 12];
			3'd5: mac_xread = gr[{bnk, 4'b0000} + 13];
			3'd6: mac_xread = gr[{bnk, 4'b0000} + 14];
			3'd7: mac_xread = gr[{bnk, 4'b0000} + 15];
		endcase
	endfunction
	function [15:0] mac_yread;
		input [1:0] yi;
		case (yi)
			2'd0: mac_yread = gr[{bnk, 4'b0000} + 6];
			2'd1: mac_yread = gr[{bnk, 4'b0000} + 7];
			2'd2: mac_yread = mfb[bnk];
			2'd3: mac_yread = 16'h0000;
		endcase
	endfunction
	reg [23:0] op;
	function automatic [63:0] mac_r64_f;
		input [3:0] sub;
		reg [15:0] xv;
		reg [15:0] yv;
		reg xs;
		reg ys;
		reg [1:0] acc;
		reg rnd;
		reg sh;
		reg signed [31:0] xe;
		reg signed [31:0] ye;
		reg signed [31:0] p32;
		reg signed [63:0] prod;
		reg signed [63:0] r;
		reg signed [63:0] mrold;
		reg signed [16:0] narrow_x;
		reg signed [16:0] narrow_y;
		reg [63:0] add_a;
		reg [63:0] add_b;
		reg subtract;
		begin
			r = 64'sh0000000000000000;
			if (sub != 4'h0) begin
				xv = mac_xread(op[10:8]);
				yv = mac_yread(op[12:11]);
				case (sub)
					4'h1, 4'h2, 4'h3, 4'h4, 4'h8, 4'hc: begin
						xs = 1'b1;
						ys = 1'b1;
					end
					4'h5, 4'h9, 4'hd: begin
						xs = 1'b1;
						ys = 1'b0;
					end
					4'h6, 4'ha, 4'he: begin
						xs = 1'b0;
						ys = 1'b1;
					end
					default: begin
						xs = 1'b0;
						ys = 1'b0;
					end
				endcase
				case (sub)
					4'h2, 4'h8, 4'h9, 4'ha, 4'hb: acc = 2'd1;
					4'h3, 4'hc, 4'hd, 4'he, 4'hf: acc = 2'd2;
					default: acc = 2'd0;
				endcase
				rnd = ((sub == 4'h1) || (sub == 4'h2)) || (sub == 4'h3);
				sh = ~mstat[4];
				xe = (xs ? $signed({{16 {xv[15]}}, xv}) : $signed({16'b0000000000000000, xv}));
				ye = (ys ? $signed({{16 {yv[15]}}, yv}) : $signed({16'b0000000000000000, yv}));
				if (SHARED_MAC) begin
					narrow_x = $signed({xs & xv[15], xv});
					narrow_y = $signed({ys & yv[15], yv});
					p32 = narrow_x * narrow_y;
				end
				else
					p32 = xe * ye;
				if (sh)
					p32 = p32 <<< 1;
				prod = {{32 {p32[31]}}, p32};
				mrold = $signed({mrzb[bnk], gr[{bnk, 4'b0000} + 13], gr[{bnk, 4'b0000} + 12], gr[{bnk, 4'b0000} + 11]});
				if (SHARED_MAC) begin
					subtract = acc == 2'd2;
					add_a = (acc == 2'd0 ? 64'd0 : mrold);
					add_b = prod ^ {64 {subtract}};
					r = (add_a + add_b) + {{63 {1'b0}}, subtract};
				end
				else
					case (acc)
						2'd1: r = mrold + prod;
						2'd2: r = mrold - prod;
						default: r = prod;
					endcase
				if (rnd) begin
					r = r + 64'sh0000000000008000;
					if (prod[15:0] == 16'h8000)
						r[16] = 1'b0;
				end
			end
			mac_r64_f = r;
		end
	endfunction
	reg [31:0] shift_res_v;
	reg [15:0] shift_sbr_v;
	reg shift_sbr_we;
	reg [15:0] shift_se_v;
	reg shift_se_we;
	reg shift_ss_v;
	reg shift_ss_we;
	task automatic shift_wb;
		input [3:0] mode;
		begin
			if (mode < 4'hc) begin
				gr[{bnk, 4'b0000} + 14] <= shift_res_v[15:0];
				gr[{bnk, 4'b0000} + 15] <= shift_res_v[31:16];
			end
			if (shift_ss_we)
				astat[7] <= shift_ss_v;
			if (shift_se_we)
				gr[{bnk, 4'b0000} + 9] <= shift_se_v;
			if (shift_sbr_we)
				sbb[bnk] <= shift_sbr_v;
		end
	endtask
	reg [31:0] alu_res;
	task automatic alu_wb;
		input dst_af;
		begin
			astat <= alu_res[31:16];
			if (dst_af)
				afb[bnk] <= alu_res[15:0];
			else
				gr[{bnk, 4'b0000} + 10] <= alu_res[15:0];
		end
	endtask
	reg signed [63:0] mac_r;
	task automatic mac_wb;
		input [3:0] sub;
		input dst_mf;
		if (sub != 4'h0) begin
			if (dst_mf)
				mfb[bnk] <= mac_r[31:16];
			else begin
				if ((mac_r[39:31] != 9'h000) && (mac_r[39:31] != 9'h1ff))
					astat <= astat | 16'h0040;
				else
					astat <= astat & ~16'h0040;
				gr[{bnk, 4'b0000} + 11] <= mac_r[15:0];
				gr[{bnk, 4'b0000} + 12] <= mac_r[31:16];
				gr[{bnk, 4'b0000} + 13] <= mac_r[47:32];
				mrzb[bnk] <= mac_r[63:48];
			end
		end
	endtask
	task automatic launch_boot;
		input [10:0] bank;
		begin
			boot_active <= 1'b1;
			state <= S_BOOT;
			boot_bank <= bank;
			boot_idx <= 12'h000;
			boot_plen <= 12'h000;
			boot_phase <= 2'd0;
		end
	endtask
	function [15:0] dm_read;
		input [15:0] addr;
		case (dm_region(addr))
			RG_ALIAS: dm_read = pmb_q[23:8];
			RG_BANK: dm_read = {8'hff, rom_q};
			RG_LATCH: dm_read = input_data;
			default: dm_read = (addr == 16'h3ffc ? tim_count : dm_q);
		endcase
	endfunction
	task automatic dm_load;
		input [15:0] addr;
		output reg [15:0] val;
		begin
			val = dm_read(addr);
			if ((addr >= 16'h3400) && (addr <= 16'h3403)) begin
				irq2_line <= 1'b0;
				latch_control <= latch_control | 16'h0800;
			end
		end
	endtask
	integer wrlog_en = 0;
	integer wrlog_fd = 0;
	integer wrlog_cnt = 0;
	reg wrlog_on = 1'b0;
	function [15:0] shift_xreg;
		input [2:0] xi;
		case (xi)
			3'd0: shift_xreg = gr[{bnk, 4'b0000} + 8];
			3'd1: shift_xreg = gr[{bnk, 4'b0000} + 8];
			3'd2: shift_xreg = gr[{bnk, 4'b0000} + 10];
			3'd3: shift_xreg = gr[{bnk, 4'b0000} + 11];
			3'd4: shift_xreg = gr[{bnk, 4'b0000} + 12];
			3'd5: shift_xreg = gr[{bnk, 4'b0000} + 13];
			3'd6: shift_xreg = gr[{bnk, 4'b0000} + 14];
			3'd7: shift_xreg = gr[{bnk, 4'b0000} + 15];
		endcase
	endfunction
	function automatic integer clz32;
		input [31:0] v;
		integer j;
		begin
			clz32 = 32;
			for (j = 31; j >= 0; j = j - 1)
				if (v[j] && (clz32 == 32))
					clz32 = 31 - j;
		end
	endfunction
	task automatic shift_eval;
		input [3:0] mode;
		input [2:0] xi;
		input signed [7:0] sc;
		output reg [31:0] o_res;
		output reg [15:0] o_se;
		output reg o_ss;
		output reg [15:0] o_sbr;
		output reg o_se_we;
		output reg o_ss_we;
		output reg o_sbr_we;
		reg [15:0] xr;
		reg signed [31:0] xs;
		reg [31:0] xu;
		reg [31:0] res;
		integer e;
		reg signed [15:0] sev;
		reg [31:0] shift_value;
		reg [31:0] shift_input;
		reg [31:0] shifted;
		reg signed [32:0] barrel_value;
		reg signed [32:0] barrel_result;
		reg [7:0] amount;
		reg shift_left;
		reg sign_fill;
		reg [15:0] exp_bits;
		integer exp_count;
		begin
			o_res = 32'h00000000;
			o_se = 16'h0000;
			o_ss = 1'b0;
			o_sbr = 16'h0000;
			o_se_we = 1'b0;
			o_ss_we = 1'b0;
			o_sbr_we = 1'b0;
			xr = shift_xreg(xi);
			res = 32'h00000000;
			exp_bits = xr ^ {16 {(mode == 4'he ? astat[7] : xr[15])}};
			exp_count = clz32({16'b0000000000000000, exp_bits});
			if (SHARED_SHIFT && (mode < 4'hc)) begin
				shift_left = (mode[3] ? sc <= 0 : sc > 0);
				amount = (sc[7] ? -sc : sc);
				shift_value = (mode[1] ? {16'b0000000000000000, xr} : {xr, 16'b0000000000000000});
				if ((mode[3:2] == 2'b01) && mode[1])
					shift_value = {{16 {xr[15]}}, xr};
				sign_fill = ((mode[3:2] == 2'b01) && !shift_left) && xr[15];
				if ((mode[3:1] == 3'b100) && (sc > 0)) begin
					shift_value = {astat[3], xr, 15'b000000000000000};
					amount = $unsigned(sc) - 8'd1;
				end
				begin : sv2v_autoblock_1
					integer bit_index;
					for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
						shift_input[bit_index] = (shift_left ? shift_value[31 - bit_index] : shift_value[bit_index]);
				end
				barrel_value = $signed({sign_fill, shift_input});
				barrel_result = barrel_value >>> amount[4:0];
				shifted = (amount >= 32 ? {32 {sign_fill}} : barrel_result[31:0]);
				begin : sv2v_autoblock_2
					integer bit_index;
					for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
						res[bit_index] = (shift_left ? shifted[31 - bit_index] : shifted[bit_index]);
				end
			end
			else
				case (mode)
					4'h0, 4'h1: begin
						xu = {xr, 16'h0000};
						if (sc > 0)
							res = (sc < 32 ? xu << sc : 32'h00000000);
						else
							res = (sc > -32 ? xu >> -sc : 32'h00000000);
					end
					4'h2, 4'h3: begin
						xu = {16'h0000, xr};
						if (sc > 0)
							res = (sc < 32 ? xu << sc : 32'h00000000);
						else
							res = (sc > -32 ? xu >> -sc : 32'h00000000);
					end
					4'h4, 4'h5: begin
						xs = $signed({xr, 16'h0000});
						if (sc > 0)
							res = (sc < 32 ? xs << sc : 32'h00000000);
						else
							res = (sc > -32 ? xs >>> -sc : xs >>> 31);
					end
					4'h6, 4'h7: begin
						xs = $signed({{16 {xr[15]}}, xr});
						if (sc > 0)
							res = (sc < 32 ? xs << sc : 32'h00000000);
						else
							res = (sc > -32 ? xs >>> -sc : xs >>> 31);
					end
					4'h8, 4'h9: begin
						xs = $signed({xr, 16'h0000});
						if (sc > 0) begin
							xu = {astat[3], xs[31:1]};
							res = xu >> (sc - 1);
						end
						else
							res = (sc > -32 ? xs << -sc : 32'h00000000);
					end
					4'ha, 4'hb: begin
						xu = {16'h0000, xr};
						if (sc > 0)
							res = (sc < 32 ? xu >> sc : 32'h00000000);
						else
							res = (sc > -32 ? xu << -sc : 32'h00000000);
					end
					4'hc: begin
						xs = $signed({{16 {xr[15]}}, xr});
						if (xs < 0) begin
							o_ss = 1'b1;
							o_ss_we = 1'b1;
							e = (SHARED_SHIFT ? exp_count : clz32(~xs)) - 17;
						end
						else begin
							o_ss = 1'b0;
							o_ss_we = 1'b1;
							e = (SHARED_SHIFT ? exp_count : clz32(xs)) - 17;
						end
						sev = -e;
						o_se = sev;
						o_se_we = 1'b1;
					end
					4'hd: begin
						xs = $signed({{16 {xr[15]}}, xr});
						if (astat[2]) begin
							sev = 16'sd1;
							o_se = sev;
							o_se_we = 1'b1;
							if (xs < 0) begin
								o_ss = 1'b0;
								o_ss_we = 1'b1;
							end
							else begin
								o_ss = 1'b1;
								o_ss_we = 1'b1;
							end
						end
						else begin
							if (xs < 0) begin
								o_ss = 1'b1;
								o_ss_we = 1'b1;
								e = (SHARED_SHIFT ? exp_count : clz32(~xs)) - 17;
							end
							else begin
								o_ss = 1'b0;
								o_ss_we = 1'b1;
								e = (SHARED_SHIFT ? exp_count : clz32(xs)) - 17;
							end
							sev = -e;
							o_se = sev;
							o_se_we = 1'b1;
						end
					end
					4'he:
						if ($signed(gr[{bnk, 4'b0000} + 9][7:0]) == -8'sd15) begin
							xs = $signed({{16 {xr[15]}}, xr});
							e = (SHARED_SHIFT ? exp_count : clz32((astat[7] ? ~xs : xs) & 32'h0000ffff)) - 1;
							sev = -e;
							o_se = sev;
							o_se_we = 1'b1;
						end
					4'hf: begin
						xs = $signed({{16 {xr[15]}}, xr});
						e = (SHARED_SHIFT ? exp_count : clz32((xs < 0 ? ~xs : xs))) - 17;
						if (e < -$signed(sbb[bnk])) begin
							sev = -e;
							o_sbr = sev;
							o_sbr_we = 1'b1;
						end
					end
				endcase
			if (mode < 4'hc) begin
				if (mode[0])
					res = {gr[{bnk, 4'b0000} + 15], gr[{bnk, 4'b0000} + 14]} | res;
				o_res = res;
			end
		end
	endtask
	reg ram_pm_we;
	reg ram_dm_we;
	reg [13:0] ram_pm_wa;
	reg [13:0] ram_dm_wa;
	reg [23:0] ram_pm_wd;
	reg [15:0] ram_dm_wd;
	reg mem_dm_request;
	reg [15:0] mem_dm_address;
	reg [15:0] mem_dm_value;
	reg [15:0] mem_register_value;
	reg [2:0] mem_dag_index;
	wire [13:0] ram_pm_addr = (ram_pm_we ? ram_pm_wa : pmb_addr);
	always @(mem_dm_value or mem_dm_address[13:0] or mem_dm_address or mem_dm_address or mem_dm_address or pmb_q[7:0] or mem_dm_value or mem_dm_address[13:0] or mem_dm_address or mem_dm_address or mem_dm_request or op_r[19:4] or mem_dag_index or iR or iR or mstat[1] or op_r[23:21] or mem_register_value or op_r[17:4] or op_r[23:20] or mem_register_value or mem_dag_index or iR or iR or mstat[1] or op_r[19] or op_r[23:21] or mem_register_value or mem_dag_index or iR or iR or mstat[1] or op_r[3:2] or op_r[16] or op_r[15] or op_r[23:16] or op_r[23:16] or px[7:0] or mem_register_value or op_r[3:2] or iR or op_r[19] or op_r[23:20] or op_r[15] or op_r[23:16] or state or rom_q or boot_b1 or boot_b0 or boot_idx or boot_phase or boot_rom_rdy or state or rst or op_r[7:4] or op_r[3:0] or op_r[23:21] or op_r[19:18] or op_r[23:21] or px or bnk or sbb or cntr or icntl or imask or sstat or mstat or astat or lR or mR or iR or lR or mR or iR or bnk or gr or generic_read_select_r[3:0] or generic_read_select_r[5:4] or px or bnk or sbb or cntr or icntl or imask or sstat or mstat or astat or lR or mR or iR or lR or mR or iR or bnk or gr or op_r[3:2] or op_r[20] or _sv2v_0) begin
		if (_sv2v_0)
			;
		ram_pm_we = 0;
		ram_pm_wa = 0;
		ram_pm_wd = 0;
		ram_dm_we = 0;
		ram_dm_wa = 0;
		ram_dm_wd = 0;
		mem_dm_request = 0;
		mem_dm_address = 0;
		mem_dm_value = 0;
		mem_dag_index = {op_r[20], op_r[3:2]};
		mem_register_value = (SHARED_REG_READ ? rd_reg(generic_read_select_r[5:4], generic_read_select_r[3:0]) : rd_reg((op_r[23:21] == 3'b100 ? op_r[19:18] : 2'd0), (op_r[23:21] == 3'b100 ? op_r[3:0] : op_r[7:4])));
		if (!rst) begin
			if (((state == S_BOOT) && boot_rom_rdy) && (boot_phase == 2'd3)) begin
				ram_pm_we = 1;
				ram_pm_wa = {2'b00, boot_idx};
				ram_pm_wd = {boot_b0, boot_b1, rom_q};
			end
			if (state == S_EXEC) begin
				if (((op_r[23:16] == 8'h11) && op_r[15]) || ((op_r[23:20] == 4'h5) && op_r[19])) begin
					ram_pm_we = 1;
					ram_pm_wa = iR[{1'b1, op_r[3:2]}][13:0];
					ram_pm_wd = {mem_register_value, px[7:0]};
				end
				if (((op_r[23:16] == 8'h12) || (op_r[23:16] == 8'h13)) && op_r[15]) begin
					mem_dag_index = {op_r[16], op_r[3:2]};
					mem_dm_request = 1;
					mem_dm_address = dag_addr(mem_dag_index);
					mem_dm_value = mem_register_value;
				end
				else if ((op_r[23:21] == 3'b011) && op_r[19]) begin
					mem_dm_request = 1;
					mem_dm_address = dag_addr(mem_dag_index);
					mem_dm_value = mem_register_value;
				end
				else if (op_r[23:20] == 4'h9) begin
					mem_dm_request = 1;
					mem_dm_address = {2'b00, op_r[17:4]};
					mem_dm_value = mem_register_value;
				end
				else if (op_r[23:21] == 3'b101) begin
					mem_dm_request = 1;
					mem_dm_address = dag_addr(mem_dag_index);
					mem_dm_value = op_r[19:4];
				end
				if (mem_dm_request) begin
					if ((mem_dm_address >= 16'h0800) && (mem_dm_address <= 16'h1fff)) begin
						ram_pm_we = 1;
						ram_pm_wa = mem_dm_address[13:0];
						ram_pm_wd = {mem_dm_value, pmb_q[7:0]};
					end
					else if ((mem_dm_address != 16'h3000) && !((mem_dm_address >= 16'h3400) && (mem_dm_address <= 16'h3403))) begin
						ram_dm_we = 1;
						ram_dm_wa = mem_dm_address[13:0];
						ram_dm_wd = mem_dm_value;
					end
				end
			end
		end
	end
	generate
		if (EXPLICIT_RAM_CE) begin : g_ce_ram
			wire [24:1] sv2v_tmp_pm_store_q_a;
			always @(*) pmb_q = sv2v_tmp_pm_store_q_a;
			wire [24:1] sv2v_tmp_pm_store_q_b;
			always @(*) fetch_r = sv2v_tmp_pm_store_q_b;
			dcs_ce_ram #(
				.WIDTH(24),
				.READ_WRITE_A(1),
				.SIM_INIT(PMFILE)
			) pm_store(
				.clk(clk),
				.ce(cpu_ce),
				.write_enable(ram_pm_we),
				.address_a(ram_pm_addr),
				.write_data(ram_pm_wd),
				.q_a(sv2v_tmp_pm_store_q_a),
				.address_b(fetch_addr),
				.q_b(sv2v_tmp_pm_store_q_b)
			);
			wire [16:1] sv2v_tmp_dm_store_q_b;
			always @(*) dm_q = sv2v_tmp_dm_store_q_b;
			dcs_ce_ram #(
				.WIDTH(16),
				.READ_WRITE_A(0)
			) dm_store(
				.clk(clk),
				.ce(cpu_ce),
				.write_enable(ram_dm_we),
				.address_a(ram_dm_wa),
				.write_data(ram_dm_wd),
				.q_a(),
				.address_b(dm_addr),
				.q_b(sv2v_tmp_dm_store_q_b)
			);
		end
	endgenerate
	integer k;
	initial begin
		data_bank = 11'h000;
		input_data = 16'h0000;
		latch_control = 16'h0c00;
		output_data = 16'h0000;
		host_rst_r = 1'b0;
		tim_scale = 9'd1;
		tim_count = 16'h0000;
		tim_period = 16'h0000;
		tim_scale_cnt = 9'd1;
		tim_irq_latch = 1'b0;
		dac_sample = 16'h0000;
		dac_ce = 1'b0;
		dac_burst_len = 0;
		boot_active = 1'b0;
		boot_idx = 12'h000;
		boot_plen = 12'h000;
		boot_bank = 11'h000;
		boot_phase = 2'd0;
		boot_b0 = 8'h00;
		boot_b1 = 8'h00;
		state = S_FETCH;
		dr_done = 1'b0;
		dr_idx = 0;
		dr_acc = 0;
		dr_cnt = 0;
		div_done = 1'b0;
		div_i = 5'd0;
		div_q = 16'h0000;
		ab_drain_cnt = 16'h0000;
		dr_region = RG_DM;
		dr_rom_a = 22'h000000;
		dr_smp = 16'h0000;
		ctl_s1_autobuf = 16'h0000;
		ctl_syscontrol = 16'h0000;
	end
	reg [7:0] hi;
	reg [13:0] tgt;
	reg [1:0] grp;
	reg [3:0] ridx;
	reg [13:0] daddr;
	reg [2:0] iidx;
	reg [2:0] midx;
	reg do_loop_back;
	reg do_loop_exit;
	reg [15:0] mstat_tmp;
	reg [15:0] dmv;
	reg [15:0] mvtmp;
	reg [5:0] generic_read_select;
	reg [15:0] generic_read_data;
	reg cflag;
	integer li;
	always @(posedge clk) begin
		dac_ce <= 1'b0;
		exec_reg_we = 1'b0;
		exec_dag_we = 1'b0;
		exec_dm_we = 1'b0;
		pc_push_we = 1'b0;
		pm_we = 1'b0;
		if (rst) begin
			dr_done <= 1'b0;
			dr_idx <= 0;
			div_done <= 1'b0;
			div_i <= 5'd0;
			pc <= 14'h0000;
			o_valid <= 1'b0;
			o_unimpl <= 1'b0;
			o_ppc <= 14'h0000;
			dac_sample <= 16'h0000;
			loop_sp <= 0;
			pc_sp <= 0;
			cntr_sp <= 0;
			cntr <= 14'h0000;
			astat <= 0;
			mstat <= 0;
			sstat <= 0;
			imask <= 0;
			icntl <= 0;
			px <= 0;
			afb[0] <= 0;
			afb[1] <= 0;
			mfb[0] <= 0;
			mfb[1] <= 0;
			sbb[0] <= 0;
			sbb[1] <= 0;
			mrzb[0] <= 0;
			mrzb[1] <= 0;
			for (k = 0; k < 8; k = k + 1)
				begin
					iR[k] <= 0;
					mR[k] <= 0;
					lR[k] <= 0;
					baseR[k] <= 0;
					lmask[k] <= 14'h3fff;
				end
			for (k = 0; k < 32; k = k + 1)
				gr[k] <= 0;
			for (k = 0; k < 4; k = k + 1)
				loop_end[k] <= NO_LOOP;
			stat_sp <= 0;
			status_last_valid <= 1'b0;
			pc_last_valid <= 1'b0;
			data_bank <= 11'h000;
			reboot_pending <= 1'b0;
			launch_boot(11'h000);
			latch_control <= 16'h0c00;
			output_data <= 16'h0000;
			ab_active <= 1'b0;
			dac_slot_ctr <= 16'h0000;
			dac_slot_go <= 1'b0;
			irq2_line <= 1'b0;
			irq2_latch <= 1'b0;
			irq1_pulse <= 1'b0;
			host_rst_r <= 1'b0;
			tim_scale <= 9'd1;
			tim_count <= 16'h0000;
			tim_period <= 16'h0000;
			tim_scale_cnt <= 9'd1;
			tim_irq_latch <= 1'b0;
		end
		else if (cpu_ce) begin
			case (state)
				S_BOOT: begin
					o_valid <= 1'b0;
					if (boot_rom_rdy)
						case (boot_phase)
							2'd0: begin
								boot_plen <= ({4'h0, rom_q} + 12'd1) << 3;
								boot_phase <= 2'd1;
							end
							2'd1: begin
								boot_b0 <= rom_q;
								boot_phase <= 2'd2;
							end
							2'd2: begin
								boot_b1 <= rom_q;
								boot_phase <= 2'd3;
							end
							2'd3: begin
								pm_we = 1'b1;
								pm_wa = {2'b00, boot_idx};
								pm_wd = {boot_b0, boot_b1, rom_q};
								boot_phase <= 2'd1;
								if ((boot_idx + 12'd1) >= boot_plen) begin
									boot_active <= 1'b0;
									state <= S_FETCH;
								end
								else
									boot_idx <= boot_idx + 12'd1;
							end
						endcase
				end
				S_FETCH: begin
					o_valid <= 1'b0;
					state <= S_DECODE;
				end
				S_DECODE, S_DRAIN, S_DIV, S_ROM, S_MEM: begin
					o_valid <= 1'b0;
					if (reboot_pending) begin
						dr_done <= 1'b0;
						dr_idx <= 0;
						div_done <= 1'b0;
						div_i <= 5'd0;
						pc <= 14'h0000;
						o_valid <= 1'b0;
						o_unimpl <= 1'b0;
						loop_sp <= 0;
						pc_sp <= 0;
						cntr_sp <= 0;
						cntr <= 14'h0000;
						stat_sp <= 0;
						status_last_valid <= 1'b0;
						pc_last_valid <= 1'b0;
						astat <= 0;
						mstat <= 0;
						sstat <= 0;
						imask <= 0;
						icntl <= 0;
						px <= 0;
						afb[0] <= 0;
						afb[1] <= 0;
						mfb[0] <= 0;
						mfb[1] <= 0;
						sbb[0] <= 0;
						sbb[1] <= 0;
						mrzb[0] <= 0;
						mrzb[1] <= 0;
						for (k = 0; k < 8; k = k + 1)
							begin
								iR[k] <= 0;
								mR[k] <= 0;
								lR[k] <= 0;
								baseR[k] <= 0;
								lmask[k] <= 14'h3fff;
							end
						for (k = 0; k < 32; k = k + 1)
							gr[k] <= 0;
						for (k = 0; k < 4; k = k + 1)
							loop_end[k] <= NO_LOOP;
						launch_boot(reboot_bank);
						reboot_pending <= 1'b0;
						irq2_line <= 1'b0;
						irq2_latch <= 1'b0;
						irq1_pulse <= 1'b0;
						tim_irq_latch <= 1'b0;
					end
					else if (host_rst_r) begin
						dr_done <= 1'b0;
						dr_idx <= 0;
						div_done <= 1'b0;
						div_i <= 5'd0;
						pc <= 14'h0000;
						o_valid <= 1'b0;
						o_unimpl <= 1'b0;
						loop_sp <= 0;
						pc_sp <= 0;
						cntr_sp <= 0;
						cntr <= 14'h0000;
						stat_sp <= 0;
						status_last_valid <= 1'b0;
						pc_last_valid <= 1'b0;
						astat <= 0;
						mstat <= 0;
						sstat <= 0;
						imask <= 0;
						icntl <= 0;
						px <= 0;
						afb[0] <= 0;
						afb[1] <= 0;
						mfb[0] <= 0;
						mfb[1] <= 0;
						sbb[0] <= 0;
						sbb[1] <= 0;
						mrzb[0] <= 0;
						mrzb[1] <= 0;
						for (k = 0; k < 8; k = k + 1)
							begin
								iR[k] <= 0;
								mR[k] <= 0;
								lR[k] <= 0;
								baseR[k] <= 0;
								lmask[k] <= 14'h3fff;
							end
						for (k = 0; k < 32; k = k + 1)
							gr[k] <= 0;
						for (k = 0; k < 4; k = k + 1)
							loop_end[k] <= NO_LOOP;
						data_bank <= 11'h000;
						launch_boot(11'h000);
						latch_control <= 16'h0c00;
						irq2_line <= 1'b0;
						irq2_latch <= 1'b0;
						irq1_pulse <= 1'b0;
						tim_scale <= 9'd1;
						tim_scale_cnt <= 9'd1;
						tim_irq_latch <= 1'b0;
					end
					else if ((((icntl[2] ? irq2_latch : irq2_line) && imask[5]) || (irq1_pulse && imask[2])) || (tim_irq_latch && imask[0])) begin
						state <= S_FETCH;
						dr_done <= 1'b0;
						dr_idx <= 0;
						div_done <= 1'b0;
						div_i <= 5'd0;
						push_pc(pc);
						pc_sp <= pc_sp + 1;
						if (MLAB_STATUS_STACK) begin
							status_mem[stat_sp] <= {mstat, imask, astat};
							status_last_addr <= stat_sp;
							status_last_data <= {mstat, imask, astat};
							status_last_valid <= 1'b1;
						end
						else begin
							stat_mstat[stat_sp] <= mstat;
							stat_imask[stat_sp] <= imask;
							stat_astat[stat_sp] <= astat;
						end
						stat_sp <= stat_sp + 1;
						if ((icntl[2] ? irq2_latch : irq2_line) && imask[5]) begin
							imask <= (icntl[4] ? imask & ~(16'h003f >> 0) : imask & ~16'h003f);
							pc <= 14'h0004;
							irq2_latch <= 1'b0;
						end
						else if (irq1_pulse && imask[2]) begin
							imask <= (icntl[4] ? imask & ~(16'h003f >> 3) : imask & ~16'h003f);
							pc <= 14'h0010;
							irq1_pulse <= 1'b0;
						end
						else begin
							imask <= (icntl[4] ? imask & ~(16'h003f >> 5) : imask & ~16'h003f);
							pc <= 14'h0018;
							tim_irq_latch <= 1'b0;
						end
						o_valid <= 1'b0;
					end
					else
						case (state)
							S_DECODE: begin
								op_r <= fetch_q;
								generic_read_select_r <= shared_reg_read_select(fetch_q);
								ea_addr_r <= pre_addr;
								pm_addr_r <= pre_pm_addr;
								pm_rd_r <= pre_pm_rd;
								bank_rd_r <= pre_bank_rd;
								tx1_r <= pre_tx1_wr;
								mem_need_r <= mem_need;
								if (drain_pend && !dr_done)
									state <= S_DRAIN;
								else if (pre_tx1_wr && !div_done)
									state <= S_DIV;
								else if (pre_bank_rd && !rom_rdy)
									state <= S_ROM;
								else if (mem_need != 2'd0)
									state <= S_MEM;
								else
									state <= S_EXEC;
							end
							S_DRAIN: begin
								o_valid <= 1'b0;
								if (dr_idx == 0)
									dr_cnt = ab_drain_cnt;
								if ((dr_idx > 0) && (dr_idx <= dr_cnt)) begin
									case (dr_region)
										RG_ALIAS: dr_smp = pmb_q[23:8];
										RG_BANK: dr_smp = {8'hff, snd_byte(dr_rom_a)};
										RG_LATCH: dr_smp = input_data;
										default: dr_smp = dm_q;
									endcase
									dac_emit_burst[dr_idx - 1] <= dr_smp;
									dac_sample <= dr_smp;
									if (PCM_STREAM)
										dac_ce <= 1'b1;
								end
								if (dr_idx < dr_cnt) begin
									dr_region <= dm_region(dr_cur[15:0]);
									dr_rom_a <= {data_bank, 12'h000} + {10'h000, dr_cur[11:0]};
									dr_acc <= dr_cur + {16'h0000, ab_incs};
									dr_idx <= dr_idx + 1;
								end
								else begin
									dr_done <= 1'b1;
									state <= (tx1_r && !div_done ? S_DIV : (bank_rd_r && !rom_rdy ? S_ROM : (mem_need_r != 2'd0 ? S_MEM : S_EXEC)));
								end
							end
							S_DIV: begin
								o_valid <= 1'b0;
								if (div_i == 5'd0) begin
									div_v <= {pre_ab_incs, 1'b0};
									div_nd <= lR[pre_ab_lr];
									div_rem <= 17'h00000;
									div_q <= 16'h0000;
									div_i <= 5'd1;
								end
								else begin
									div_t = {div_rem, div_nd[15]};
									if (div_t >= {1'b0, div_v}) begin
										div_rem <= div_t - {1'b0, div_v};
										div_q <= {div_q[14:0], 1'b1};
									end
									else begin
										div_rem <= div_t[16:0];
										div_q <= {div_q[14:0], 1'b0};
									end
									div_nd <= {div_nd[14:0], 1'b0};
									if (div_i == 5'd16) begin
										div_done <= 1'b1;
										state <= (bank_rd_r && !rom_rdy ? S_ROM : (mem_need_r != 2'd0 ? S_MEM : S_EXEC));
									end
									else
										div_i <= div_i + 5'd1;
								end
							end
							S_ROM:
								if (rom_rdy)
									state <= (mem_need_r != 2'd0 ? S_MEM : S_EXEC);
							S_MEM: state <= S_EXEC;
							default:
								;
						endcase
				end
				S_EXEC: begin
					state <= S_FETCH;
					dr_done <= 1'b0;
					dr_idx <= 0;
					div_done <= 1'b0;
					div_i <= 5'd0;
					o_ppc <= pc;
					o_valid <= 1'b1;
					o_unimpl <= 1'b0;
					if (mstat[5]) begin
						if (tim_scale_cnt <= 9'd1) begin
							tim_scale_cnt <= tim_scale;
							if (tim_count == 16'h0000) begin
								tim_count <= tim_period;
								tim_irq_latch <= 1'b1;
							end
							else
								tim_count <= tim_count - 16'h0001;
						end
						else
							tim_scale_cnt <= tim_scale_cnt - 9'd1;
					end
					if (irq1_pulse)
						irq1_pulse <= 1'b0;
					if ((ab_active && dac_slot_go) && dr_done) begin
						ab_cnt = dr_cnt;
						ab_reg = dr_cur;
						dac_burst_len = ab_cnt;
						if (!PCM_STREAM)
							dac_ce <= 1'b1;
						if (ab_reg >= ({16'h0000, baseR[ab_ireg]} + ab_size)) begin
							ab_reg = {16'h0000, baseR[ab_ireg]};
							irq1_pulse <= 1'b1;
						end
						iR[ab_ireg] <= ab_reg & 16'h3fff;
						baseR[ab_ireg] <= ab_reg[13:0] & lmask[ab_ireg];
						dac_slot_go <= 1'b0;
					end
					op = op_r;
					hi = op[23:16];
					generic_read_select = generic_read_select_r;
					generic_read_data = rd_reg(generic_read_select[5:4], generic_read_select[3:0]);
					mac_r = mac_r64_f(op[16:13]);
					alu_res = alu_eval(op[16:13], alu_xread(op[10:8]), alu_yread(op[12:11]));
					shift_eval(op[14:11], op[10:8], (hi == 8'h0f ? op[7:0] : gr[{bnk, 4'b0000} + 9][7:0]), shift_res_v, shift_se_v, shift_ss_v, shift_sbr_v, shift_se_we, shift_ss_we, shift_sbr_we);
					do_loop_back = 1'b0;
					do_loop_exit = 1'b0;
					if ((loop_sp != 0) && (pc == loop_end[loop_sp - 1])) begin
						if (loop_cond[loop_sp - 1] == 4'he) begin
							if (($signed({1'b0, cntr}) - 1) > 0) begin
								cntr <= cntr - 1'b1;
								do_loop_back = 1'b1;
							end
							else begin
								cntr <= cntr - 1'b1;
								cntr <= cntr_stack[cntr_sp - 1];
								cntr_sp <= cntr_sp - 1;
								do_loop_exit = 1'b1;
							end
						end
						else if (cond_true(loop_cond[loop_sp - 1]))
							do_loop_back = 1'b1;
						else
							do_loop_exit = 1'b1;
					end
					if (do_loop_back)
						pc <= pc_top;
					else if (do_loop_exit) begin
						loop_sp <= loop_sp - 1;
						pc_sp <= pc_sp - 1;
						pc <= pc + 1'b1;
					end
					else
						pc <= pc + 1'b1;
					case (hi)
						8'h00:
							;
						8'h05:
							if (astat[6]) begin
								if (gr[{bnk, 4'b0000} + 13][7]) begin
									gr[{bnk, 4'b0000} + 13] <= 16'hffff;
									gr[{bnk, 4'b0000} + 12] <= 16'h8000;
									gr[{bnk, 4'b0000} + 11] <= 16'h0000;
								end
								else begin
									gr[{bnk, 4'b0000} + 13] <= 16'h0000;
									gr[{bnk, 4'b0000} + 12] <= 16'h7fff;
									gr[{bnk, 4'b0000} + 11] <= 16'hffff;
								end
							end
						8'h06: begin
							dmv = alu_yread(op[12:11]);
							mvtmp = alu_xread(op[10:8]) ^ dmv;
							astat <= (astat & ~16'h0020) | (mvtmp[15] ? 16'h0020 : 16'h0000);
							afb[bnk] <= {dmv[14:0], gr[{bnk, 4'b0000} + 4][15]};
							gr[{bnk, 4'b0000} + 4] <= {gr[{bnk, 4'b0000} + 4][14:0], mvtmp[15]};
						end
						8'h07: begin
							if (astat[5])
								dmv = afb[bnk] + alu_xread(op[10:8]);
							else
								dmv = afb[bnk] - alu_xread(op[10:8]);
							mvtmp = dmv ^ alu_xread(op[10:8]);
							astat <= (astat & ~16'h0020) | (mvtmp[15] ? 16'h0020 : 16'h0000);
							afb[bnk] <= {dmv[14:0], gr[{bnk, 4'b0000} + 4][15]};
							gr[{bnk, 4'b0000} + 4] <= {gr[{bnk, 4'b0000} + 4][14:0], ~mvtmp[15]};
						end
						8'h09:
							request_dag_modify(op[4:2], {op[4], op[1:0]});
						8'h0b: begin
							cond_eval(op[3:0], cflag);
							if (cflag) begin
								if (op[4]) begin
									push_pc(pc + 1'b1);
									pc_sp <= pc_sp + 1;
								end
								pc <= iR[{1'b1, op[7:6]}][13:0];
							end
						end
						8'h0a: begin
							cond_eval(op[3:0], cflag);
							if (cflag) begin
								pc <= pc_top;
								pc_sp <= pc_sp - 1;
								if (op[4]) begin
									set_mstat((MLAB_STATUS_STACK ? status_top[47:32] : stat_mstat[stat_sp - 1]));
									imask <= (MLAB_STATUS_STACK ? status_top[31:16] : stat_imask[stat_sp - 1]);
									astat <= (MLAB_STATUS_STACK ? status_top[15:0] : stat_astat[stat_sp - 1]);
									stat_sp <= stat_sp - 1;
								end
							end
						end
						8'h0c: begin
							mstat_tmp = mstat;
							if (op[3])
								mstat_tmp = (mstat_tmp & ~16'h0040) | (op[2] ? 16'h0040 : 16'h0000);
							if (op[13])
								mstat_tmp = (mstat_tmp & ~16'h0010) | (op[12] ? 16'h0010 : 16'h0000);
							if (op[15])
								mstat_tmp = (mstat_tmp & ~16'h0020) | (op[14] ? 16'h0020 : 16'h0000);
							if (op[5])
								mstat_tmp = (mstat_tmp & ~16'h0001) | ((op >> 4) & 16'h0001);
							if (op[7])
								mstat_tmp = (mstat_tmp & ~16'h0002) | ((op >> 5) & 16'h0002);
							if (op[9])
								mstat_tmp = (mstat_tmp & ~16'h0004) | ((op >> 6) & 16'h0004);
							if (op[11])
								mstat_tmp = (mstat_tmp & ~16'h0008) | ((op >> 7) & 16'h0008);
							set_mstat(mstat_tmp);
						end
						8'h0d:
							request_reg_write(op[11:10], op[7:4], (SHARED_REG_READ ? generic_read_data : rd_reg(op[9:8], op[3:0])));
						8'h0e: begin
							cond_eval(op[3:0], cflag);
							if (cflag)
								shift_wb(op[14:11]);
						end
						8'h0f:
							shift_wb(op[14:11]);
						8'h10: begin
							shift_wb(op[14:11]);
							request_reg_write(2'd0, op[7:4], (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[3:0])));
						end
						8'h11: begin
							iidx = {1'b1, op[3:2]};
							midx = {1'b1, op[1:0]};
							if (op[15]) begin
								pm_we = 1'b1;
								pm_wa = iR[iidx][13:0];
								pm_wd = {(SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])), px[7:0]};
								shift_wb(op[14:11]);
							end
							else begin
								shift_wb(op[14:11]);
								request_reg_write(2'd0, op[7:4], pmb_q[23:8]);
								px <= {8'h00, pmb_q[7:0]};
							end
							request_dag_modify(iidx, midx);
						end
						8'h12, 8'h13: begin
							iidx = {op[16], op[3:2]};
							midx = {op[16], op[1:0]};
							if (op[15]) begin
								request_dm_write(dag_addr(iidx), (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])));
								shift_wb(op[14:11]);
							end
							else begin
								shift_wb(op[14:11]);
								dm_load(dag_addr(iidx), dmv);
								request_reg_write(2'd0, op[7:4], dmv);
							end
							request_dag_modify(iidx, midx);
						end
						8'h14, 8'h15, 8'h16, 8'h17: begin
							loop_end[loop_sp] <= op[17:4];
							loop_cond[loop_sp] <= op[3:0];
							loop_sp <= loop_sp + 1;
							push_pc(pc + 1'b1);
							pc_sp <= pc_sp + 1;
						end
						8'h18, 8'h19, 8'h1a, 8'h1b, 8'h1c, 8'h1d, 8'h1e, 8'h1f: begin
							tgt = op[17:4];
							cond_eval(op[3:0], cflag);
							if (cflag) begin
								if (op[18]) begin
									push_pc(pc + 1'b1);
									pc_sp <= pc_sp + 1;
								end
								pc <= tgt;
							end
						end
						8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27: begin
							cond_eval(op[3:0], cflag);
							if (cflag) begin
								if (op[17])
									alu_wb(op[18]);
								else
									mac_wb(op[16:13], op[18]);
							end
						end
						8'h28, 8'h29, 8'h2a, 8'h2b, 8'h2c, 8'h2d, 8'h2e, 8'h2f: begin
							mvtmp = (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[3:0]));
							if (op[17])
								alu_wb(op[18]);
							else
								mac_wb(op[16:13], op[18]);
							request_reg_write(2'd0, op[7:4], mvtmp);
						end
						8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39, 8'h3a, 8'h3b, 8'h3c, 8'h3d, 8'h3e, 8'h3f: begin
							grp = op[19:18];
							ridx = op[3:0];
							request_reg_write(grp, ridx, {2'b00, op[17:4]});
						end
						8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47, 8'h48, 8'h49, 8'h4a, 8'h4b, 8'h4c, 8'h4d, 8'h4e, 8'h4f:
							request_reg_write(2'd0, op[3:0], op[19:4]);
						8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58, 8'h59, 8'h5a, 8'h5b, 8'h5c, 8'h5d, 8'h5e, 8'h5f: begin
							if (op[17:13] != 5'h00) begin
								if (op[17])
									alu_wb(op[18]);
								else
									mac_wb(op[16:13], op[18]);
							end
							iidx = {1'b1, op[3:2]};
							midx = {1'b1, op[1:0]};
							if (op[19]) begin
								pm_we = 1'b1;
								pm_wa = iR[iidx][13:0];
								pm_wd = {(SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])), px[7:0]};
							end
							else begin
								request_reg_write(2'd0, op[7:4], pmb_q[23:8]);
								px <= {8'h00, pmb_q[7:0]};
							end
							request_dag_modify(iidx, midx);
						end
						8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67, 8'h68, 8'h69, 8'h6a, 8'h6b, 8'h6c, 8'h6d, 8'h6e, 8'h6f, 8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77, 8'h78, 8'h79, 8'h7a, 8'h7b, 8'h7c, 8'h7d, 8'h7e, 8'h7f: begin
							if (op[17:13] != 5'h00) begin
								if (op[17])
									alu_wb(op[18]);
								else
									mac_wb(op[16:13], op[18]);
							end
							iidx = {op[20], op[3:2]};
							midx = {op[20], op[1:0]};
							if (op[19])
								request_dm_write(dag_addr(iidx), (SHARED_REG_READ ? generic_read_data : rd_reg(2'd0, op[7:4])));
							else begin
								dm_load(dag_addr(iidx), dmv);
								request_reg_write(2'd0, op[7:4], dmv);
							end
							request_dag_modify(iidx, midx);
						end
						8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87, 8'h88, 8'h89, 8'h8a, 8'h8b, 8'h8c, 8'h8d, 8'h8e, 8'h8f, 8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97, 8'h98, 8'h99, 8'h9a, 8'h9b, 8'h9c, 8'h9d, 8'h9e, 8'h9f: begin
							daddr = op[17:4];
							grp = op[19:18];
							ridx = op[3:0];
							if (op[20])
								request_dm_write({2'b00, daddr}, (SHARED_REG_READ ? generic_read_data : rd_reg(grp, ridx)));
							else begin
								dm_load({2'b00, daddr}, dmv);
								request_reg_write(grp, ridx, dmv);
							end
						end
						8'ha0, 8'ha1, 8'ha2, 8'ha3, 8'ha4, 8'ha5, 8'ha6, 8'ha7, 8'ha8, 8'ha9, 8'haa, 8'hab, 8'hac, 8'had, 8'hae, 8'haf, 8'hb0, 8'hb1, 8'hb2, 8'hb3, 8'hb4, 8'hb5, 8'hb6, 8'hb7, 8'hb8, 8'hb9, 8'hba, 8'hbb, 8'hbc, 8'hbd, 8'hbe, 8'hbf: begin
							iidx = {op[20], op[3:2]};
							midx = {op[20], op[1:0]};
							request_dm_write(dag_addr(iidx), op[19:4]);
							request_dag_modify(iidx, midx);
						end
						default: o_unimpl <= 1'b1;
					endcase
					if (SHARED_EXEC) begin
						if (exec_dm_we)
							dm_write(exec_dm_addr, exec_dm_data);
						if (exec_reg_we)
							wr_reg(exec_reg_group, exec_reg_index, exec_reg_data);
						if (exec_dag_we)
							dag_modify(exec_dag_index, exec_dag_modifier);
					end
				end
			endcase
			if (!rst)
				host_rst_r <= host_rst;
			if ((!rst && dac_ce_in) && ab_active) begin
				if (dac_slot_ctr <= 16'd1) begin
					dac_slot_ctr <= ab_drain_cnt;
					dac_slot_go <= 1'b1;
				end
				else
					dac_slot_ctr <= dac_slot_ctr - 16'd1;
			end
			if (host_cmd_w && !rst) begin
				input_data <= host_cmd_data;
				if (!irq2_line)
					irq2_latch <= 1'b1;
				irq2_line <= 1'b1;
				latch_control <= latch_control & ~16'h0800;
			end
			if (host_resp_rd && !rst)
				latch_control <= latch_control | 16'h0400;
			if ((!EXPLICIT_RAM_CE && !SHARED_PM) && pm_we)
				pm2[pm_wa] <= pm_wd;
		end
		pm_port_b_addr = (SHARED_PM && !pm_we ? pmb_addr : pm_wa);
		if (rst) begin
			pc_write_toggle <= 1'b0;
			pc_written_toggle <= 1'b0;
		end
		else begin
			pc_written_toggle <= pc_write_toggle;
			if (MLAB_PC_STACK && (pc_write_toggle != pc_written_toggle))
				pc_mem[pc_last_addr] <= pc_last_data;
		end
		if (cpu_ce) begin
			if (MLAB_PC_STACK && pc_push_we) begin
				pc_write_toggle <= ~pc_write_toggle;
				pc_last_addr <= pc_push_addr;
				pc_last_data <= pc_push_data;
				pc_last_valid <= 1'b1;
			end
			if (!EXPLICIT_RAM_CE) begin
				if (pm_we)
					pm[pm_port_b_addr] <= pm_wd;
				if (SHARED_PM)
					pmb_q <= pm[pm_port_b_addr];
			end
		end
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype none
module wolf_dcs_board (
	clk,
	rst,
	host_reset,
	host_cmd_wr,
	host_cmd_data,
	host_resp_rd,
	host_resp_data,
	host_status,
	rom_req,
	rom_addr,
	rom_rdy,
	rom_q,
	audio,
	dbg_valid,
	dbg_unimpl,
	dbg_pcm_push,
	dbg_pc
);
	reg _sv2v_0;
	parameter integer CLK_HZ = 80000000;
	parameter integer DCS_CORE_HZ = 32000000;
	parameter DCS_PMFILE = "pm.hex";
	parameter integer PCM_AW = 10;
	parameter integer STARTUP_RAMP_BITS = 10;
	parameter integer RESET_FADE_BITS = 8;
	input wire clk;
	input wire rst;
	input wire host_reset;
	input wire host_cmd_wr;
	input wire [7:0] host_cmd_data;
	input wire host_resp_rd;
	output wire [7:0] host_resp_data;
	output wire [15:0] host_status;
	output wire rom_req;
	output wire [18:0] rom_addr;
	input wire rom_rdy;
	input wire [63:0] rom_q;
	output reg signed [15:0] audio;
	output wire dbg_valid;
	output wire dbg_unimpl;
	output wire dbg_pcm_push;
	output wire [13:0] dbg_pc;
	localparam integer DAC_DIV = CLK_HZ / 31250;
	localparam integer PCM_N = 1 << PCM_AW;
	wire [15:0] host_response;
	wire [13:0] dcs_ppc;
	wire dcs_valid;
	wire dcs_unimpl;
	wire [15:0] dcs_sample;
	wire dcs_sample_we;
	wire [15:0] dcs_status;
	function automatic integer phase_rate_gcd;
		input integer a;
		input integer b;
		integer remainder;
		begin
			while (b != 0) begin
				remainder = a % b;
				a = b;
				b = remainder;
			end
			phase_rate_gcd = a;
		end
	endfunction
	localparam integer DCS_PHASE_GCD = ((DCS_CORE_HZ > 0) && (DCS_CORE_HZ < CLK_HZ) ? phase_rate_gcd(CLK_HZ, DCS_CORE_HZ) : 1);
	localparam integer DCS_PHASE_MOD_INT = CLK_HZ / DCS_PHASE_GCD;
	localparam integer DCS_PHASE_W = $clog2(DCS_PHASE_MOD_INT);
	localparam [DCS_PHASE_W:0] DCS_PHASE_STEP = DCS_CORE_HZ / DCS_PHASE_GCD;
	localparam [DCS_PHASE_W:0] DCS_PHASE_MOD = DCS_PHASE_MOD_INT;
	reg [DCS_PHASE_W - 1:0] dcs_phase;
	reg [DCS_PHASE_W:0] dcs_phase_sum;
	wire dcs_ce = dcs_phase_sum >= DCS_PHASE_MOD;
	always @(*) begin
		if (_sv2v_0)
			;
		dcs_phase_sum = {1'b0, dcs_phase} + DCS_PHASE_STEP;
	end
	always @(posedge clk)
		if (rst)
			dcs_phase <= 1'sb0;
		else if (dcs_ce)
			dcs_phase <= dcs_phase_sum - DCS_PHASE_MOD;
		else
			dcs_phase <= dcs_phase_sum[DCS_PHASE_W - 1:0];
	reg [$clog2(DAC_DIV) - 1:0] dac_div_ctr;
	wire dac_slot_ce = dac_div_ctr == (DAC_DIV - 1);
	always @(posedge clk)
		if (rst)
			dac_div_ctr <= 1'sb0;
		else if (dac_slot_ce)
			dac_div_ctr <= 1'sb0;
		else
			dac_div_ctr <= dac_div_ctr + 1'b1;
	reg dac_slot_pending;
	wire dcs_dac_ce = dac_slot_ce | dac_slot_pending;
	always @(posedge clk)
		if (rst)
			dac_slot_pending <= 1'b0;
		else if (dac_slot_ce)
			dac_slot_pending <= !dcs_ce;
		else if (dcs_ce)
			dac_slot_pending <= 1'b0;
	reg cmd_pending;
	reg resp_rd_pending;
	reg [7:0] cmd_pending_data;
	always @(posedge clk)
		if (rst || host_reset) begin
			cmd_pending <= 1'b0;
			cmd_pending_data <= 8'h00;
			resp_rd_pending <= 1'b0;
		end
		else begin
			if (host_cmd_wr) begin
				cmd_pending <= 1'b1;
				cmd_pending_data <= host_cmd_data;
			end
			else if (cmd_pending && dcs_ce)
				cmd_pending <= 1'b0;
			if (host_resp_rd)
				resp_rd_pending <= 1'b1;
			else if (resp_rd_pending && dcs_ce)
				resp_rd_pending <= 1'b0;
		end
	adsp2105 #(
		.PMFILE(DCS_PMFILE),
		.EXT_ROM(1),
		.CORE_CE_EN(1),
		.PCM_STREAM(1)
	) u_adsp(
		.clk(clk),
		.rst(rst),
		.core_ce(dcs_ce),
		.host_rst(host_reset),
		.host_cmd_w(cmd_pending && dcs_ce),
		.host_cmd_data({8'h00, cmd_pending_data}),
		.host_status_r(dcs_status),
		.host_response_r(host_response),
		.host_resp_rd(resp_rd_pending && dcs_ce),
		.rom_ddr_req(rom_req),
		.rom_ddr_addr(rom_addr),
		.rom_ddr_rdy(rom_rdy),
		.rom_ddr_q(rom_q),
		.dac_ce_in(dcs_dac_ce),
		.o_ppc(dcs_ppc),
		.o_valid(dcs_valid),
		.o_unimpl(dcs_unimpl),
		.dac_sample(dcs_sample),
		.dac_ce(dcs_sample_we)
	);
	assign host_resp_data = host_response[7:0];
	assign host_status = dcs_status;
	assign dbg_valid = dcs_valid;
	assign dbg_unimpl = dcs_unimpl;
	assign dbg_pcm_push = dcs_sample_we;
	assign dbg_pc = dcs_ppc;
	reg [15:0] pcm_fifo [0:PCM_N - 1];
	reg [PCM_AW - 1:0] pcm_wp;
	reg [PCM_AW - 1:0] pcm_rp;
	reg [PCM_AW:0] pcm_used;
	wire pcm_push = dcs_sample_we && (pcm_used != PCM_N);
	wire pcm_pop = dac_slot_ce && (pcm_used != 0);
	localparam [STARTUP_RAMP_BITS:0] STARTUP_GAIN_FULL = {1'b1, {STARTUP_RAMP_BITS {1'b0}}};
	reg [STARTUP_RAMP_BITS:0] startup_gain;
	wire signed [15:0] pcm_head = $signed(pcm_fifo[pcm_rp]);
	wire signed [STARTUP_RAMP_BITS + 1:0] startup_gain_signed = $signed({1'b0, startup_gain});
	wire signed [STARTUP_RAMP_BITS + 17:0] startup_product = pcm_head * startup_gain_signed;
	reg host_reset_d;
	reg reset_fade_active;
	reg [15:0] reset_fade_step;
	localparam [16:0] RESET_FADE_ROUND = (17'd1 << RESET_FADE_BITS) - 1'b1;
	wire [16:0] reset_fade_magnitude = (audio[15] ? {1'b0, ~audio} + 1'b1 : {1'b0, audio});
	wire [16:0] reset_fade_rounded = reset_fade_magnitude + RESET_FADE_ROUND;
	wire [15:0] reset_fade_step_next = reset_fade_rounded >> RESET_FADE_BITS;
	always @(posedge clk)
		if (rst) begin
			pcm_wp <= 1'sb0;
			pcm_rp <= 1'sb0;
			pcm_used <= 1'sb0;
			audio <= 1'sb0;
			startup_gain <= 1'sb0;
			host_reset_d <= 1'b0;
			reset_fade_active <= 1'b0;
			reset_fade_step <= 1'sb0;
		end
		else begin
			host_reset_d <= host_reset;
			if (host_reset && !host_reset_d) begin
				if (audio != 0) begin
					reset_fade_active <= 1'b1;
					reset_fade_step <= reset_fade_step_next;
				end
				else begin
					reset_fade_active <= 1'b0;
					reset_fade_step <= 1'sb0;
				end
			end
			if (host_reset) begin
				pcm_wp <= 1'sb0;
				pcm_rp <= 1'sb0;
				pcm_used <= 1'sb0;
				startup_gain <= 1'sb0;
			end
			else begin
				if (pcm_push) begin
					pcm_fifo[pcm_wp] <= dcs_sample;
					pcm_wp <= pcm_wp + 1'b1;
				end
				if (pcm_pop) begin
					if (!reset_fade_active) begin
						if (startup_gain != STARTUP_GAIN_FULL) begin
							audio <= startup_product >>> STARTUP_RAMP_BITS;
							if (pcm_head != 16'sh0000)
								startup_gain <= startup_gain + 1'b1;
						end
						else
							audio <= pcm_head;
					end
					pcm_rp <= pcm_rp + 1'b1;
				end
				(* full_case, parallel_case *)
				case ({pcm_push, pcm_pop})
					2'b10: pcm_used <= pcm_used + 1'b1;
					2'b01: pcm_used <= pcm_used - 1'b1;
					default:
						;
				endcase
			end
			if (reset_fade_active && dac_slot_ce) begin
				if (!audio[15]) begin
					if ({1'b0, audio} <= {1'b0, reset_fade_step}) begin
						audio <= 1'sb0;
						reset_fade_active <= 1'b0;
					end
					else
						audio <= $signed(audio) - $signed({1'b0, reset_fade_step});
				end
				else if (reset_fade_magnitude <= {1'b0, reset_fade_step}) begin
					audio <= 1'sb0;
					reset_fade_active <= 1'b0;
				end
				else
					audio <= $signed(audio) + $signed({1'b0, reset_fade_step});
			end
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_video (
	clk,
	rst,
	ce_pix,
	raster_vblank_start,
	disp_row0,
	wr_busy,
	publication_pending,
	active_row0,
	vram_raddr,
	vram_rdata,
	pal_raddr,
	pal_rdata,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de,
	vblank_irq
);
	reg _sv2v_0;
	parameter signed [31:0] H_ACT = 400;
	parameter signed [31:0] H_FP = 5;
	parameter signed [31:0] H_SYNC = 43;
	parameter signed [31:0] H_BP = 58;
	parameter signed [31:0] V_ACT = 254;
	parameter signed [31:0] V_FP = 15;
	parameter signed [31:0] V_SYNC = 3;
	parameter signed [31:0] V_BP = 17;
	parameter [11:0] COL_TAP = 56;
	parameter signed [31:0] FLIP_SETTLE_CYCLES = 128;
	parameter signed [31:0] FLIP_PREFETCH_LINES = 4;
	parameter [0:0] USE_TMS_RASTER_SYNC = 0;
	input wire clk;
	input wire rst;
	input wire ce_pix;
	input wire raster_vblank_start;
	localparam signed [31:0] wolf_pkg_FB_ADDR_W = 19;
	input wire [18:0] disp_row0;
	input wire wr_busy;
	output wire publication_pending;
	output wire [18:0] active_row0;
	output wire [18:0] vram_raddr;
	input wire [15:0] vram_rdata;
	output wire [14:0] pal_raddr;
	input wire [15:0] pal_rdata;
	output reg [7:0] vid_r;
	output reg [7:0] vid_g;
	output reg [7:0] vid_b;
	output reg hsync;
	output reg vsync;
	output reg hblank;
	output reg vblank;
	output reg de;
	output reg vblank_irq;
	localparam signed [31:0] H_TOTAL = ((H_ACT + H_FP) + H_SYNC) + H_BP;
	localparam signed [31:0] V_TOTAL = ((V_ACT + V_FP) + V_SYNC) + V_BP;
	reg [11:0] hc;
	reg [11:0] vc;
	reg s0_de;
	reg s0_hs;
	reg s0_vs;
	reg s0_hb;
	reg s0_vb;
	reg [11:0] s0_x;
	reg [11:0] s0_y;
	localparam [7:0] FLIP_SETTLE = FLIP_SETTLE_CYCLES[7:0];
	localparam signed [31:0] FLIP_COMMIT_LIMIT = V_TOTAL - FLIP_PREFETCH_LINES;
	reg [18:0] base_row;
	reg [18:0] disp_row0_pend;
	reg flip_armed;
	reg flip_wait_drain;
	reg tms_blank_window;
	reg [7:0] flip_settle;
	wire wr_busy_i = wr_busy === 1'b1;
	wire raster_sync_i = USE_TMS_RASTER_SYNC && (raster_vblank_start === 1'b1);
	wire local_frame_start = (!USE_TMS_RASTER_SYNC && (hc == (H_TOTAL - 1))) && (vc == (V_ACT - 1));
	wire frame_start = raster_sync_i || local_frame_start;
	assign active_row0 = base_row;
	assign publication_pending = (flip_armed && (disp_row0_pend[8:0] != base_row[8:0])) || ((USE_TMS_RASTER_SYNC && (tms_blank_window || raster_sync_i)) && (disp_row0[8:0] != base_row[8:0]));
	always @(posedge clk)
		if (rst) begin
			hc <= 1'sb0;
			vc <= 1'sb0;
			vblank_irq <= 1'b0;
			base_row <= 1'sb0;
			disp_row0_pend <= 1'sb0;
			flip_armed <= 1'b0;
			flip_wait_drain <= 1'b0;
			flip_settle <= FLIP_SETTLE;
			tms_blank_window <= 1'b0;
		end
		else begin
			if ((flip_armed && flip_wait_drain) && !wr_busy_i) begin
				flip_wait_drain <= 1'b0;
				flip_settle <= FLIP_SETTLE;
			end
			if (ce_pix) begin
				vblank_irq <= 1'b0;
				if (raster_sync_i) begin
					hc <= H_ACT + H_FP;
					vc <= V_ACT - 1;
					tms_blank_window <= 1'b1;
				end
				else if (hc == (H_TOTAL - 1)) begin
					hc <= 1'sb0;
					if (vc == (V_TOTAL - 1)) begin
						vc <= 1'sb0;
						tms_blank_window <= 1'b0;
					end
					else
						vc <= vc + 12'd1;
				end
				else
					hc <= hc + 12'd1;
				if (frame_start) begin
					vblank_irq <= 1'b1;
					disp_row0_pend <= disp_row0;
					flip_armed <= 1'b1;
					flip_wait_drain <= wr_busy_i;
					flip_settle <= FLIP_SETTLE;
				end
				else if ((USE_TMS_RASTER_SYNC && tms_blank_window) && (disp_row0 != disp_row0_pend)) begin
					disp_row0_pend <= disp_row0;
					flip_armed <= 1'b1;
					flip_wait_drain <= wr_busy_i;
					flip_settle <= FLIP_SETTLE;
				end
				else if (flip_armed) begin
					if (flip_wait_drain) begin
						if (!wr_busy_i) begin
							flip_wait_drain <= 1'b0;
							flip_settle <= FLIP_SETTLE;
						end
					end
					else if (flip_settle != 8'd0)
						flip_settle <= flip_settle - 8'd1;
					else if (s0_vb && (vc < FLIP_COMMIT_LIMIT)) begin
						base_row <= disp_row0_pend;
						flip_armed <= 1'b0;
					end
				end
			end
		end
	always @(*) begin
		if (_sv2v_0)
			;
		s0_x = hc;
		s0_y = vc;
		s0_de = (hc < H_ACT) && (vc < V_ACT);
		s0_hb = hc >= H_ACT;
		s0_vb = vc >= V_ACT;
		s0_hs = (hc >= (H_ACT + H_FP)) && (hc < ((H_ACT + H_FP) + H_SYNC));
		s0_vs = (vc >= (V_ACT + V_FP)) && (vc < ((V_ACT + V_FP) + V_SYNC));
	end
	localparam signed [31:0] wolf_pkg_FB_ROWSHIFT = 9;
	function automatic [18:0] sv2v_cast_19;
		input reg [18:0] inp;
		sv2v_cast_19 = inp;
	endfunction
	assign vram_raddr = sv2v_cast_19((((base_row + s0_y) << wolf_pkg_FB_ROWSHIFT) & 32'h0003fe00) + ((s0_x + COL_TAP) & 12'h1ff));
	reg s1_de;
	reg s1_hs;
	reg s1_vs;
	reg s1_hb;
	reg s1_vb;
	reg s2_de;
	reg s2_hs;
	reg s2_vs;
	reg s2_hb;
	reg s2_vb;
	always @(posedge clk)
		if (rst) begin
			s1_de <= 0;
			s1_hs <= 0;
			s1_vs <= 0;
			s1_hb <= 0;
			s1_vb <= 0;
			s2_de <= 0;
			s2_hs <= 0;
			s2_vs <= 0;
			s2_hb <= 0;
			s2_vb <= 0;
		end
		else if (ce_pix) begin
			s1_de <= s0_de;
			s1_hs <= s0_hs;
			s1_vs <= s0_vs;
			s1_hb <= s0_hb;
			s1_vb <= s0_vb;
			s2_de <= s1_de;
			s2_hs <= s1_hs;
			s2_vs <= s1_vs;
			s2_hb <= s1_hb;
			s2_vb <= s1_vb;
		end
	assign pal_raddr = vram_rdata[14:0];
	wire [23:0] rgb;
	function automatic [23:0] wolf_pkg_rgb555_to_888;
		input reg [15:0] c;
		reg [4:0] r5;
		reg [4:0] g5;
		reg [4:0] b5;
		begin
			r5 = c[14:10];
			g5 = c[9:5];
			b5 = c[4:0];
			wolf_pkg_rgb555_to_888 = {r5, r5[4:2], g5, g5[4:2], b5, b5[4:2]};
		end
	endfunction
	assign rgb = wolf_pkg_rgb555_to_888(pal_rdata);
	always @(posedge clk)
		if (rst) begin
			de <= 0;
			hsync <= 0;
			vsync <= 0;
			hblank <= 0;
			vblank <= 0;
			vid_r <= 0;
			vid_g <= 0;
			vid_b <= 0;
		end
		else if (ce_pix) begin
			de <= s2_de;
			hsync <= s2_hs;
			vsync <= s2_vs;
			hblank <= s2_hb;
			vblank <= s2_vb;
			vid_r <= (s2_de ? rgb[23:16] : 8'h00);
			vid_g <= (s2_de ? rgb[15:8] : 8'h00);
			vid_b <= (s2_de ? rgb[7:0] : 8'h00);
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module yunit_scanline (
	clk,
	rst,
	ce_pix,
	vblank,
	frame_row0,
	vram_raddr,
	vram_rdata,
	scan_req,
	scan_addr,
	scan_data,
	scan_ack
);
	parameter signed [31:0] FB_ADDR_W = 18;
	parameter signed [31:0] NCOL = 512;
	parameter signed [31:0] FIRST_ROW = 0;
	parameter signed [31:0] ROW_ADDR_W = 9;
	input wire clk;
	input wire rst;
	input wire ce_pix;
	input wire vblank;
	input wire [ROW_ADDR_W - 1:0] frame_row0;
	input wire [FB_ADDR_W - 1:0] vram_raddr;
	output reg [15:0] vram_rdata;
	output reg scan_req;
	output wire [18:0] scan_addr;
	input wire [15:0] scan_data;
	input wire scan_ack;
	localparam signed [31:0] ROWW = ROW_ADDR_W;
	wire [ROWW - 1:0] req_row = vram_raddr[(9 + ROWW) - 1:9];
	wire [8:0] req_col = vram_raddr[8:0];
	(* ramstyle = "no_rw_check, M10K" *) reg [15:0] lb [0:1023];
	reg disp_sel;
	reg [ROWW - 1:0] disp_row;
	wire sel_now = (req_row == disp_row ? disp_sel : ~disp_sel);
	always @(posedge clk)
		if (ce_pix)
			vram_rdata <= lb[{sel_now, req_col}];
	reg [ROWW - 1:0] buf_row [0:1];
	reg buf_valid [0:1];
	wire [ROWW - 1:0] next_row = disp_row + 1'b1;
	reg loading;
	reg tgt_sel;
	reg [ROWW - 1:0] tgt_row;
	reg [8:0] li;
	reg vbl_q;
	wire disp_stale = !buf_valid[disp_sel] || (buf_row[disp_sel] != disp_row);
	wire load_stale = !buf_valid[~disp_sel] || (buf_row[~disp_sel] != next_row);
	always @(posedge clk)
		if (rst) begin
			loading <= 1'b0;
			scan_req <= 1'b0;
			disp_sel <= 1'b0;
			disp_row <= 1'sb0;
			buf_valid[0] <= 1'b0;
			buf_valid[1] <= 1'b0;
			vbl_q <= 1'b0;
		end
		else begin
			vbl_q <= vblank;
			if ((!vbl_q && vblank) || (vblank && (frame_row0 != disp_row))) begin
				disp_sel <= 1'b0;
				disp_row <= frame_row0;
				buf_valid[0] <= 1'b0;
				buf_valid[1] <= 1'b0;
				loading <= 1'b0;
				scan_req <= 1'b0;
			end
			else begin
				if (!vblank && (req_row != disp_row)) begin
					disp_sel <= ~disp_sel;
					disp_row <= req_row;
				end
				if (!loading) begin
					if (disp_stale) begin
						tgt_sel <= disp_sel;
						tgt_row <= disp_row;
						li <= 9'd0;
						loading <= 1'b1;
					end
					else if (load_stale) begin
						tgt_sel <= ~disp_sel;
						tgt_row <= next_row;
						li <= 9'd0;
						loading <= 1'b1;
					end
				end
				else if (scan_req && scan_ack) begin
					lb[{tgt_sel, li}] <= scan_data;
					scan_req <= 1'b0;
					if (li == (NCOL - 1)) begin
						loading <= 1'b0;
						buf_row[tgt_sel] <= tgt_row;
						buf_valid[tgt_sel] <= 1'b1;
					end
					else
						li <= li + 9'd1;
				end
				else if (!scan_req)
					scan_req <= 1'b1;
			end
		end
	assign scan_addr = {tgt_row[8:0], li};
endmodule
`default_nettype wire
`default_nettype none
module wolf_video_top (
	clk,
	rst,
	ce_pix,
	raster_vblank_start,
	disp_row0,
	wr_busy,
	blit_busy,
	pal_raddr,
	pal_rdata,
	scan_req,
	scan_addr,
	scan_data,
	scan_ack,
	active_row0_diag,
	publication_pending,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de,
	vblank_irq
);
	parameter signed [31:0] H_ACT = 400;
	parameter signed [31:0] H_FP = 5;
	parameter signed [31:0] H_SYNC = 43;
	parameter signed [31:0] H_BP = 58;
	parameter signed [31:0] V_ACT = 254;
	parameter signed [31:0] V_FP = 15;
	parameter signed [31:0] V_SYNC = 3;
	parameter signed [31:0] V_BP = 17;
	parameter [11:0] COL_TAP = 56;
	parameter signed [31:0] NCOL = 400;
	parameter signed [31:0] FLIP_SETTLE_CYCLES = 128;
	parameter signed [31:0] FLIP_PREFETCH_LINES = 4;
	parameter [0:0] USE_TMS_RASTER_SYNC = 0;
	parameter [0:0] WAIT_FOR_RENDER_IDLE = 1;
	input wire clk;
	input wire rst;
	input wire ce_pix;
	input wire raster_vblank_start;
	localparam signed [31:0] wolf_pkg_FB_ADDR_W = 19;
	input wire [18:0] disp_row0;
	input wire wr_busy;
	input wire blit_busy;
	output wire [14:0] pal_raddr;
	input wire [15:0] pal_rdata;
	output wire scan_req;
	output wire [18:0] scan_addr;
	input wire [15:0] scan_data;
	input wire scan_ack;
	output wire [18:0] active_row0_diag;
	output wire publication_pending;
	output wire [7:0] vid_r;
	output wire [7:0] vid_g;
	output wire [7:0] vid_b;
	output wire hsync;
	output wire vsync;
	output wire hblank;
	output wire vblank;
	output wire de;
	output wire vblank_irq;
	wire [18:0] vram_raddr;
	wire [18:0] active_row0;
	wire [15:0] vram_rdata;
	wire vblank_i;
	wire render_busy = WAIT_FOR_RENDER_IDLE && ((wr_busy === 1'b1) || (blit_busy === 1'b1));
	assign active_row0_diag = active_row0;
	wolf_video #(
		.H_ACT(H_ACT),
		.H_FP(H_FP),
		.H_SYNC(H_SYNC),
		.H_BP(H_BP),
		.V_ACT(V_ACT),
		.V_FP(V_FP),
		.V_SYNC(V_SYNC),
		.V_BP(V_BP),
		.COL_TAP(COL_TAP),
		.FLIP_SETTLE_CYCLES(FLIP_SETTLE_CYCLES),
		.FLIP_PREFETCH_LINES(FLIP_PREFETCH_LINES),
		.USE_TMS_RASTER_SYNC(USE_TMS_RASTER_SYNC)
	) u_video(
		.clk(clk),
		.rst(rst),
		.ce_pix(ce_pix),
		.raster_vblank_start(raster_vblank_start),
		.disp_row0(disp_row0),
		.wr_busy(render_busy),
		.active_row0(active_row0),
		.publication_pending(publication_pending),
		.vram_raddr(vram_raddr),
		.vram_rdata(vram_rdata),
		.pal_raddr(pal_raddr),
		.pal_rdata(pal_rdata),
		.vid_r(vid_r),
		.vid_g(vid_g),
		.vid_b(vid_b),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank_i),
		.de(de),
		.vblank_irq(vblank_irq)
	);
	assign vblank = vblank_i;
	yunit_scanline #(
		.FB_ADDR_W(wolf_pkg_FB_ADDR_W),
		.NCOL(NCOL),
		.FIRST_ROW(0),
		.ROW_ADDR_W(9)
	) u_scan(
		.clk(clk),
		.rst(rst),
		.ce_pix(ce_pix),
		.vblank(vblank_i),
		.frame_row0(active_row0[8:0]),
		.vram_raddr(vram_raddr),
		.vram_rdata(vram_rdata),
		.scan_req(scan_req),
		.scan_addr(scan_addr),
		.scan_data(scan_data),
		.scan_ack(scan_ack)
	);
endmodule
`default_nettype wire
`default_nettype none
module wolf_palram (
	clk,
	rst,
	we_a,
	aa,
	awd,
	we_b,
	ba,
	bwd,
	raddr,
	rdata
);
	reg _sv2v_0;
	parameter signed [31:0] AW = 15;
	parameter signed [31:0] DEPTH = 1 << AW;
	input wire clk;
	input wire rst;
	input wire we_a;
	input wire [AW - 1:0] aa;
	input wire [15:0] awd;
	input wire we_b;
	input wire [AW - 1:0] ba;
	input wire [15:0] bwd;
	input wire [AW - 1:0] raddr;
	output wire [15:0] rdata;
	(* ramstyle = "no_rw_check" *) reg [15:0] mem [0:DEPTH - 1];
	localparam signed [31:0] QAW = 2;
	reg [AW + 15:0] q [0:3];
	reg [QAW:0] wptr;
	reg [QAW:0] rptr;
	wire qempty = wptr == rptr;
	reg w_we;
	reg [AW - 1:0] w_aa;
	reg [15:0] w_awd;
	wire [AW + 15:0] q_head = q[rptr[1:0]];
	wire [AW - 1:0] q_head_a = q_head[AW + 15:16];
	wire [15:0] q_head_d = q_head[15:0];
	always @(*) begin
		if (_sv2v_0)
			;
		w_we = !qempty;
		w_aa = q_head_a;
		w_awd = q_head_d;
	end
	always @(posedge clk)
		if (rst) begin
			wptr <= 1'sb0;
			rptr <= 1'sb0;
		end
		else begin
			if (!qempty)
				rptr <= rptr + 1'b1;
			if (we_a && we_b) begin
				q[wptr[1:0]] <= {aa, awd};
				q[wptr[1:0] + 1'b1] <= {ba, bwd};
				wptr <= wptr + 2'd2;
			end
			else if (we_a) begin
				q[wptr[1:0]] <= {aa, awd};
				wptr <= wptr + 1'b1;
			end
			else if (we_b) begin
				q[wptr[1:0]] <= {ba, bwd};
				wptr <= wptr + 1'b1;
			end
		end
	always @(posedge clk)
		if (w_we)
			mem[w_aa] <= w_awd;
	reg rdw_hit_q;
	reg [15:0] rdw_data_q;
	reg [15:0] mem_q;
	always @(posedge clk) begin
		mem_q <= mem[raddr];
		rdw_hit_q <= w_we && (w_aa == raddr);
		rdw_data_q <= w_awd;
	end
	assign rdata = (rdw_hit_q ? rdw_data_q : mem_q);
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_video_post (
	clk,
	ce_pix,
	vid_r_pre,
	vid_g_pre,
	vid_b_pre,
	hsync_pre,
	vsync_pre,
	hblank_pre,
	vblank_pre,
	de_pre,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de
);
	parameter signed [31:0] H_ACT = 400;
	parameter signed [31:0] V_ACT = 254;
	input wire clk;
	input wire ce_pix;
	input wire [7:0] vid_r_pre;
	input wire [7:0] vid_g_pre;
	input wire [7:0] vid_b_pre;
	input wire hsync_pre;
	input wire vsync_pre;
	input wire hblank_pre;
	input wire vblank_pre;
	input wire de_pre;
	output wire [7:0] vid_r;
	output wire [7:0] vid_g;
	output wire [7:0] vid_b;
	output wire hsync;
	output wire vsync;
	output wire hblank;
	output wire vblank;
	output wire de;
	assign vid_r = vid_r_pre;
	assign vid_g = vid_g_pre;
	assign vid_b = vid_b_pre;
	assign hsync = hsync_pre;
	assign vsync = vsync_pre;
	assign hblank = hblank_pre;
	assign vblank = vblank_pre;
	assign de = de_pre;
endmodule
`default_nettype wire
`default_nettype none
module yunit_sdram_arb (
	clk,
	rst,
	vsd_addr,
	vsd_din,
	vsd_be,
	vsd_rd,
	vsd_wr,
	vsd_dout,
	vsd_ack,
	rsd_addr,
	rsd_din,
	rsd_be,
	rsd_rd,
	rsd_wr,
	rsd_dout,
	rsd_ack,
	cgfx_rd,
	cgfx_addr,
	cgfx_data,
	cgfx_ack,
	src_rd,
	src_addr,
	src_data,
	src_ack,
	iol_rd,
	iol_wr,
	iol_addr,
	iol_din,
	iol_be,
	iol_dout,
	iol_ack,
	sd_addr,
	sd_din,
	sd_be,
	sd_rd,
	sd_wr,
	sd_dout,
	sd_ack
);
	reg _sv2v_0;
	parameter signed [31:0] SD_AW = 25;
	parameter [SD_AW - 1:0] GFXW_BASE = 25'h0000000;
	parameter [SD_AW - 1:0] ROMW_BASE = 25'h00c0000;
	parameter [SD_AW - 1:0] VRAMW_BASE = 25'h00e0000;
	parameter [SD_AW - 1:0] RAMW_BASE = 25'h0180000;
	parameter [23:0] GFX_BYTES = 24'h180000;
	input wire clk;
	input wire rst;
	input wire [SD_AW - 1:0] vsd_addr;
	input wire [15:0] vsd_din;
	input wire [1:0] vsd_be;
	input wire vsd_rd;
	input wire vsd_wr;
	output reg [15:0] vsd_dout;
	output reg vsd_ack;
	input wire [SD_AW - 1:0] rsd_addr;
	input wire [15:0] rsd_din;
	input wire [1:0] rsd_be;
	input wire rsd_rd;
	input wire rsd_wr;
	output reg [15:0] rsd_dout;
	output reg rsd_ack;
	input wire cgfx_rd;
	input wire [23:0] cgfx_addr;
	output reg [7:0] cgfx_data;
	output reg cgfx_ack;
	input wire src_rd;
	input wire [23:0] src_addr;
	output reg [7:0] src_data;
	output reg src_ack;
	input wire iol_rd;
	input wire iol_wr;
	input wire [SD_AW - 1:0] iol_addr;
	input wire [15:0] iol_din;
	input wire [1:0] iol_be;
	output reg [15:0] iol_dout;
	output reg iol_ack;
	output reg [SD_AW - 1:0] sd_addr;
	output reg [15:0] sd_din;
	output reg [1:0] sd_be;
	output reg sd_rd;
	output reg sd_wr;
	input wire [15:0] sd_dout;
	input wire sd_ack;
	wire [SD_AW - 1:0] cgfx_word = (cgfx_addr < GFX_BYTES ? GFXW_BASE + {1'b0, cgfx_addr[23:1]} : ROMW_BASE + {1'b0, (cgfx_addr - GFX_BYTES) >> 1});
	wire cgfx_bsel = cgfx_addr[0];
	wire [SD_AW - 1:0] src_word = GFXW_BASE + {1'b0, src_addr[23:1]};
	wire src_bsel = src_addr[0];
	wire [SD_AW - 1:0] vsd_word = VRAMW_BASE + vsd_addr;
	wire [SD_AW - 1:0] rsd_word = RAMW_BASE + rsd_addr;
	reg cgfx_cache_valid;
	reg [SD_AW - 1:0] cgfx_cache_word;
	reg [15:0] cgfx_cache_data;
	reg cgfx_hit_pending;
	reg [7:0] cgfx_hit_data;
	wire cgfx_cache_hit = cgfx_cache_valid && (cgfx_cache_word == cgfx_word);
	wire [7:0] cgfx_cache_byte = (cgfx_bsel ? cgfx_cache_data[15:8] : cgfx_cache_data[7:0]);
	wire cgfx_miss_req = (cgfx_rd && !cgfx_cache_hit) && !cgfx_hit_pending;
	wire alias_cache_write = (iol_wr && cgfx_cache_valid) && (iol_addr == cgfx_cache_word);
	localparam [2:0] G_NONE = 3'd0;
	localparam [2:0] G_IOL = 3'd1;
	localparam [2:0] G_VSD = 3'd2;
	localparam [2:0] G_CGFX = 3'd3;
	localparam [2:0] G_SRC = 3'd4;
	localparam [2:0] G_RSD = 3'd5;
	wire vsd_req = vsd_rd | vsd_wr;
	wire rsd_req = rsd_rd | rsd_wr;
	wire iol_req = iol_rd | iol_wr;
	reg [2:0] gnt;
	reg gnt_held;
	reg [2:0] gnt_r;
	reg bubble;
	always @(*) begin
		if (_sv2v_0)
			;
		if (gnt_held)
			gnt = gnt_r;
		else if (bubble)
			gnt = G_NONE;
		else if (iol_req)
			gnt = G_IOL;
		else if (vsd_req)
			gnt = G_VSD;
		else if (cgfx_miss_req)
			gnt = G_CGFX;
		else if (rsd_req)
			gnt = G_RSD;
		else if (src_rd)
			gnt = G_SRC;
		else
			gnt = G_NONE;
	end
	wire gnt_done = sd_ack;
	always @(posedge clk)
		if (rst) begin
			gnt_held <= 1'b0;
			gnt_r <= G_NONE;
			bubble <= 1'b0;
		end
		else begin
			bubble <= 1'b0;
			if (!gnt_held) begin
				if (!bubble && (gnt != G_NONE)) begin
					if (gnt_done) begin
						gnt_held <= 1'b0;
						bubble <= 1'b1;
					end
					else begin
						gnt_held <= 1'b1;
						gnt_r <= gnt;
					end
				end
			end
			else if (gnt_done) begin
				gnt_held <= 1'b0;
				bubble <= 1'b1;
			end
		end
	always @(posedge clk)
		if (rst) begin
			cgfx_hit_pending <= 1'b0;
			cgfx_hit_data <= 8'h00;
		end
		else if (cgfx_hit_pending)
			cgfx_hit_pending <= 1'b0;
		else if ((cgfx_rd && cgfx_cache_hit) && !alias_cache_write) begin
			cgfx_hit_pending <= 1'b1;
			cgfx_hit_data <= cgfx_cache_byte;
		end
	always @(posedge clk)
		if (rst) begin
			cgfx_cache_valid <= 1'b0;
			cgfx_cache_word <= 1'sb0;
			cgfx_cache_data <= 16'h0000;
		end
		else if (alias_cache_write)
			cgfx_cache_valid <= 1'b0;
		else if (sd_ack && (gnt == G_CGFX)) begin
			cgfx_cache_valid <= 1'b1;
			cgfx_cache_word <= sd_addr;
			cgfx_cache_data <= sd_dout;
		end
	reg cgfx_bsel_q;
	reg src_bsel_q;
	reg [SD_AW - 1:0] cgfx_word_q;
	wire [7:0] rd_byte = (cgfx_bsel_q ? sd_dout[15:8] : sd_dout[7:0]);
	always @(posedge clk) begin
		if (!gnt_held && (gnt == G_CGFX)) begin
			cgfx_bsel_q <= cgfx_bsel;
			cgfx_word_q <= cgfx_word;
		end
		if (gnt == G_SRC)
			src_bsel_q <= src_bsel;
	end
	wire cgfx_hit_ack = !rst && cgfx_hit_pending;
	always @(*) begin
		if (_sv2v_0)
			;
		sd_addr = 1'sb0;
		sd_din = 16'h0000;
		sd_be = 2'b00;
		sd_rd = 1'b0;
		sd_wr = 1'b0;
		vsd_ack = 1'b0;
		cgfx_ack = cgfx_hit_ack;
		src_ack = 1'b0;
		iol_ack = 1'b0;
		rsd_ack = 1'b0;
		vsd_dout = sd_dout;
		iol_dout = sd_dout;
		rsd_dout = sd_dout;
		cgfx_data = (cgfx_hit_ack ? cgfx_hit_data : (cgfx_bsel_q ? sd_dout[15:8] : sd_dout[7:0]));
		src_data = (src_bsel_q ? sd_dout[15:8] : sd_dout[7:0]);
		case (gnt)
			G_IOL: begin
				sd_addr = iol_addr;
				sd_din = iol_din;
				sd_be = iol_be;
				sd_rd = iol_rd;
				sd_wr = iol_wr;
				iol_ack = sd_ack;
			end
			G_VSD: begin
				sd_addr = vsd_word;
				sd_din = vsd_din;
				sd_be = vsd_be;
				sd_rd = vsd_rd;
				sd_wr = vsd_wr;
				vsd_ack = sd_ack;
			end
			G_RSD: begin
				sd_addr = rsd_word;
				sd_din = rsd_din;
				sd_be = rsd_be;
				sd_rd = rsd_rd;
				sd_wr = rsd_wr;
				rsd_ack = sd_ack;
			end
			G_CGFX: begin
				sd_addr = (gnt_held ? cgfx_word_q : cgfx_word);
				sd_be = 2'b00;
				sd_rd = 1'b1;
				cgfx_ack = sd_ack;
				cgfx_data = ((gnt_held ? cgfx_bsel_q : cgfx_bsel) ? sd_dout[15:8] : sd_dout[7:0]);
			end
			G_SRC: begin
				sd_addr = src_word;
				sd_be = 2'b00;
				sd_rd = 1'b1;
				src_ack = sd_ack;
			end
			default:
				;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
module sdram_stock (
	init,
	clk,
	SDRAM_DQ,
	SDRAM_A,
	SDRAM_DQML,
	SDRAM_DQMH,
	SDRAM_BA,
	SDRAM_nCS,
	SDRAM_nWE,
	SDRAM_nRAS,
	SDRAM_nCAS,
	SDRAM_CKE,
	wtbt,
	addr,
	dout,
	din,
	we,
	rd,
	ready
);
	input init;
	input clk;
	inout [15:0] SDRAM_DQ;
	output reg [12:0] SDRAM_A;
	output reg SDRAM_DQML;
	output reg SDRAM_DQMH;
	output reg [1:0] SDRAM_BA;
	output wire SDRAM_nCS;
	output wire SDRAM_nWE;
	output wire SDRAM_nRAS;
	output wire SDRAM_nCAS;
	output wire SDRAM_CKE;
	input [1:0] wtbt;
	input [24:0] addr;
	output wire [15:0] dout;
	input [15:0] din;
	input we;
	input rd;
	output reg ready;
	localparam BURST_LENGTH = 3'b000;
	localparam ACCESS_TYPE = 1'b0;
	localparam CAS_LATENCY = 3'd2;
	localparam OP_MODE = 2'b00;
	localparam NO_WRITE_BURST = 1'b1;
	localparam MODE = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};
	localparam sdram_startup_cycles = 14'd16040;
	localparam cycles_per_refresh = 14'd300;
	localparam startup_refresh_max = 14'b11111111111111;
	localparam [2:0] CMD_NOP = 3'b111;
	localparam [2:0] CMD_ACTIVE = 3'b011;
	localparam [2:0] CMD_READ = 3'b101;
	localparam [2:0] CMD_WRITE = 3'b100;
	localparam [2:0] CMD_PRECHARGE = 3'b010;
	localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
	localparam [2:0] CMD_LOAD_MODE = 3'b000;
	reg [2:0] command;
	reg [13:0] refresh_count = startup_refresh_max - sdram_startup_cycles;
	reg [24:0] save_addr;
	reg [15:0] data;
	reg old_we;
	reg old_rd;
	reg [CAS_LATENCY:0] data_ready_delay;
	reg [15:0] new_data;
	reg [1:0] new_wtbt;
	reg new_we;
	reg new_rd;
	reg save_we = 1'b1;
	reg [31:0] state = 32'd0;
	reg [15:0] sdram_dq_out;
	reg sdram_dq_oe;
	assign SDRAM_DQ = (sdram_dq_oe ? sdram_dq_out : 16'bzzzzzzzzzzzzzzzz);
	assign SDRAM_CKE = 1;
	assign SDRAM_nCS = 0;
	assign SDRAM_nRAS = command[2];
	assign SDRAM_nCAS = command[1];
	assign SDRAM_nWE = command[0];
	wire [2:1] sv2v_tmp_7A9FC;
	assign sv2v_tmp_7A9FC = (state == 32'd0 ? 2'b11 : SDRAM_A[12:11]);
	always @(*) {SDRAM_DQMH, SDRAM_DQML} = sv2v_tmp_7A9FC;
	assign dout = (save_addr[0] ? {data[7:0], data[15:8]} : {data[15:8], data[7:0]});
	always @(posedge clk) begin
		sdram_dq_oe <= 1'b0;
		command <= CMD_NOP;
		refresh_count <= refresh_count + 1'b1;
		data_ready_delay <= {1'b0, data_ready_delay[CAS_LATENCY:1]};
		if (data_ready_delay[0])
			{ready, data} <= {1'b1, SDRAM_DQ};
		case (state)
			32'd0: begin
				SDRAM_A <= 0;
				SDRAM_BA <= 0;
				if (refresh_count == 16352) begin
					command <= CMD_PRECHARGE;
					SDRAM_A[10] <= 1;
					SDRAM_BA <= 2'b00;
				end
				if (refresh_count == 16360)
					command <= CMD_AUTO_REFRESH;
				if (refresh_count == 16368)
					command <= CMD_AUTO_REFRESH;
				if (refresh_count == 16376) begin
					command <= CMD_LOAD_MODE;
					SDRAM_A <= MODE;
				end
				if (refresh_count == 16380) begin
					command <= CMD_LOAD_MODE;
					SDRAM_BA <= 2'b10;
					SDRAM_A <= 0;
				end
				if (!refresh_count) begin
					state <= 32'd3;
					ready <= 1;
					refresh_count <= 0;
				end
			end
			32'd10: state <= 32'd9;
			32'd9: state <= 32'd8;
			32'd8: state <= 32'd7;
			32'd7: state <= 32'd6;
			32'd6: state <= 32'd5;
			32'd5: state <= 32'd4;
			32'd4: begin
				state <= 32'd3;
				if (refresh_count > cycles_per_refresh) begin
					state <= 32'd10;
					command <= CMD_AUTO_REFRESH;
					refresh_count <= 0;
				end
			end
			32'd3:
				if (refresh_count > (cycles_per_refresh << 1))
					state <= 32'd4;
				else if (new_rd | new_we) begin
					new_we <= 0;
					new_rd <= 0;
					save_we <= new_we;
					state <= 32'd1;
					command <= CMD_ACTIVE;
					SDRAM_A <= save_addr[13:1];
					SDRAM_BA <= save_addr[24:23];
				end
			32'd1: state <= 32'd2;
			32'd2: begin
				SDRAM_A <= {save_we & (new_wtbt ? ~new_wtbt[1] : ~save_addr[0]), save_we & (new_wtbt ? ~new_wtbt[0] : save_addr[0]), 2'b10, save_addr[22:14]};
				if (save_we) begin
					command <= CMD_WRITE;
					sdram_dq_out <= (new_wtbt ? new_data : {new_data[7:0], new_data[7:0]});
					sdram_dq_oe <= 1'b1;
					ready <= 1;
					state <= 32'd7;
				end
				else begin
					command <= CMD_READ;
					data_ready_delay[CAS_LATENCY] <= 1;
					state <= 32'd8;
				end
			end
			default: state <= 32'd3;
		endcase
		if (init) begin
			state <= 32'd0;
			refresh_count <= startup_refresh_max - sdram_startup_cycles;
		end
		old_we <= we;
		if (we & ~old_we) begin
			save_addr <= addr;
			{ready, new_we, new_data, new_wtbt} <= {2'b01, din, wtbt};
		end
		old_rd <= rd;
		if (rd & ~old_rd) begin
			save_addr <= addr;
			if (!((ready & ~save_we) & (save_addr[24:1] == addr[24:1])))
				{ready, new_rd} <= 2'b01;
		end
		if (init) begin
			ready <= 1'b0;
			new_we <= 1'b0;
			new_rd <= 1'b0;
			data_ready_delay <= 1'sb0;
		end
	end
endmodule
`default_nettype none
module yunit_sdram_adapter (
	clk,
	rst,
	sd_addr,
	sd_din,
	sd_be,
	sd_rd,
	sd_wr,
	sd_dout,
	sd_ack,
	sdram_ready,
	ctl_addr,
	ctl_din,
	ctl_wtbt,
	ctl_rd,
	ctl_we,
	ctl_dout,
	ctl_ready
);
	input wire clk;
	input wire rst;
	input wire [24:0] sd_addr;
	input wire [15:0] sd_din;
	input wire [1:0] sd_be;
	input wire sd_rd;
	input wire sd_wr;
	output reg [15:0] sd_dout;
	output reg sd_ack;
	output wire sdram_ready;
	output reg [24:0] ctl_addr;
	output reg [15:0] ctl_din;
	output reg [1:0] ctl_wtbt;
	output reg ctl_rd;
	output reg ctl_we;
	input wire [15:0] ctl_dout;
	input wire ctl_ready;
	reg startup_done;
	reg [1:0] astate;
	always @(posedge clk)
		if (rst) begin
			astate <= 2'd0;
			ctl_rd <= 1'b0;
			ctl_we <= 1'b0;
			sd_ack <= 1'b0;
			startup_done <= 1'b0;
		end
		else begin
			sd_ack <= 1'b0;
			ctl_rd <= 1'b0;
			ctl_we <= 1'b0;
			if (ctl_ready)
				startup_done <= 1'b1;
			case (astate)
				2'd0:
					if (((sd_rd | sd_wr) & ctl_ready) & startup_done) begin
						ctl_addr <= {sd_addr[23:0], 1'b0};
						ctl_din <= sd_din;
						ctl_wtbt <= sd_be;
						ctl_rd <= sd_rd;
						ctl_we <= sd_wr;
						astate <= 2'd1;
					end
				2'd1: astate <= 2'd2;
				2'd2:
					if (ctl_ready) begin
						sd_dout <= ctl_dout;
						sd_ack <= 1'b1;
						astate <= 2'd3;
					end
				2'd3: astate <= 2'd0;
			endcase
		end
	assign sdram_ready = startup_done;
endmodule
`default_nettype wire
`default_nettype none
module yunit_mem_cdc (
	clk_cpu,
	ce_cpu,
	rst_cpu,
	c_req,
	c_we,
	c_addr,
	c_size,
	c_wdata,
	c_ack,
	c_rdata,
	clk_sys,
	rst_sys,
	m_req,
	m_we,
	m_addr,
	m_size,
	m_wdata,
	m_rdata,
	m_ack
);
	parameter AW = 32;
	parameter DW = 32;
	parameter SW = 6;
	input wire clk_cpu;
	input wire ce_cpu;
	input wire rst_cpu;
	input wire c_req;
	input wire c_we;
	input wire [AW - 1:0] c_addr;
	input wire [SW - 1:0] c_size;
	input wire [DW - 1:0] c_wdata;
	output reg c_ack;
	output reg [DW - 1:0] c_rdata;
	input wire clk_sys;
	input wire rst_sys;
	output reg m_req;
	output reg m_we;
	output reg [AW - 1:0] m_addr;
	output reg [SW - 1:0] m_size;
	output reg [DW - 1:0] m_wdata;
	input wire [DW - 1:0] m_rdata;
	input wire m_ack;
	reg req_tgl;
	reg ack_tgl;
	reg p_we;
	reg [AW - 1:0] p_addr;
	reg [SW - 1:0] p_size;
	reg [DW - 1:0] p_wdata;
	reg [DW - 1:0] resp;
	reg [1:0] cst;
	reg [2:0] ackt_sync;
	always @(posedge clk_cpu)
		if (rst_cpu || (ce_cpu !== 1'b0)) begin
			if (rst_cpu) begin
				cst <= 2'd0;
				req_tgl <= 1'b0;
				c_ack <= 1'b0;
				ackt_sync <= 3'b000;
			end
			else begin
				ackt_sync <= {ackt_sync[1:0], ack_tgl};
				c_ack <= 1'b0;
				case (cst)
					2'd0:
						if (c_req) begin
							p_we <= c_we;
							p_addr <= c_addr;
							p_size <= c_size;
							p_wdata <= c_wdata;
							req_tgl <= ~req_tgl;
							cst <= 2'd1;
						end
					2'd1:
						if (ackt_sync[2] ^ ackt_sync[1]) begin
							c_rdata <= resp;
							c_ack <= 1'b1;
							cst <= 2'd2;
						end
					2'd2: cst <= 2'd0;
					default: cst <= 2'd0;
				endcase
			end
		end
	reg [1:0] sst;
	reg [2:0] reqt_sync;
	always @(posedge clk_sys)
		if (rst_sys) begin
			sst <= 2'd0;
			m_req <= 1'b0;
			ack_tgl <= 1'b0;
			reqt_sync <= 3'b000;
		end
		else begin
			reqt_sync <= {reqt_sync[1:0], req_tgl};
			case (sst)
				2'd0:
					if (reqt_sync[2] ^ reqt_sync[1]) begin
						m_we <= p_we;
						m_addr <= p_addr;
						m_size <= p_size;
						m_wdata <= p_wdata;
						m_req <= 1'b1;
						sst <= 2'd1;
					end
				2'd1:
					if (m_ack) begin
						resp <= m_rdata;
						m_req <= 1'b0;
						ack_tgl <= ~ack_tgl;
						sst <= 2'd0;
					end
				default: sst <= 2'd0;
			endcase
		end
endmodule
module yunit_mem_sameclock (
	clk_cpu,
	ce_cpu,
	rst_cpu,
	c_req,
	c_we,
	c_addr,
	c_size,
	c_wdata,
	c_ack,
	c_rdata,
	clk_sys,
	rst_sys,
	m_req,
	m_we,
	m_addr,
	m_size,
	m_wdata,
	m_rdata,
	m_ack
);
	parameter AW = 32;
	parameter DW = 32;
	parameter SW = 6;
	input wire clk_cpu;
	input wire ce_cpu;
	input wire rst_cpu;
	input wire c_req;
	input wire c_we;
	input wire [AW - 1:0] c_addr;
	input wire [SW - 1:0] c_size;
	input wire [DW - 1:0] c_wdata;
	output reg c_ack;
	output reg [DW - 1:0] c_rdata;
	input wire clk_sys;
	input wire rst_sys;
	output reg m_req;
	output reg m_we;
	output reg [AW - 1:0] m_addr;
	output reg [SW - 1:0] m_size;
	output reg [DW - 1:0] m_wdata;
	input wire [DW - 1:0] m_rdata;
	input wire m_ack;
	reg [1:0] scst;
	always @(posedge clk_sys)
		if (rst_sys || rst_cpu) begin
			scst <= 2'd0;
			c_ack <= 1'b0;
			c_rdata <= 1'sb0;
			m_req <= 1'b0;
			m_we <= 1'b0;
			m_addr <= 1'sb0;
			m_size <= 1'sb0;
			m_wdata <= 1'sb0;
		end
		else
			case (scst)
				2'd0: begin
					c_ack <= 1'b0;
					if ((ce_cpu !== 1'b0) && c_req) begin
						m_we <= c_we;
						m_addr <= c_addr;
						m_size <= c_size;
						m_wdata <= c_wdata;
						m_req <= 1'b1;
						scst <= 2'd1;
					end
				end
				2'd1:
					if (m_ack) begin
						c_rdata <= m_rdata;
						c_ack <= 1'b1;
						m_req <= 1'b0;
						scst <= 2'd2;
					end
				2'd2:
					if (ce_cpu !== 1'b0) begin
						c_ack <= 1'b0;
						scst <= 2'd3;
					end
				2'd3:
					if (ce_cpu !== 1'b0)
						scst <= 2'd0;
				default: scst <= 2'd0;
			endcase
endmodule
`default_nettype wire
`default_nettype none
module wolf_gfxdl_guard (
	clk,
	sdram_por,
	rom_download,
	gfx_download,
	fifo_idle,
	writer_idle,
	core_hold
);
	parameter integer QUIET_CYCLES = 512;
	input wire clk;
	input wire sdram_por;
	input wire rom_download;
	input wire gfx_download;
	input wire fifo_idle;
	input wire writer_idle;
	output wire core_hold;
	localparam integer QUIET_W = $clog2(QUIET_CYCLES + 1);
	reg drain_hold;
	reg gfx_seen;
	reg [QUIET_W - 1:0] quiet_count;
	always @(posedge clk)
		if (sdram_por) begin
			drain_hold <= 1'b0;
			gfx_seen <= 1'b0;
			quiet_count <= 1'sb0;
		end
		else if (rom_download) begin
			drain_hold <= 1'b1;
			gfx_seen <= 1'b0;
			quiet_count <= 1'sb0;
		end
		else if (gfx_download) begin
			drain_hold <= 1'b1;
			gfx_seen <= 1'b1;
			quiet_count <= 1'sb0;
		end
		else if (drain_hold && gfx_seen) begin
			if (!fifo_idle || !writer_idle)
				quiet_count <= 1'sb0;
			else if (quiet_count == (QUIET_CYCLES - 1)) begin
				drain_hold <= 1'b0;
				quiet_count <= 1'sb0;
			end
			else
				quiet_count <= quiet_count + 1'b1;
		end
		else
			quiet_count <= 1'sb0;
	assign core_hold = (rom_download | gfx_download) | drain_hold;
endmodule
`default_nettype wire
`default_nettype none
module wolf_top (
	clk,
	clk_cpu,
	ce_pix,
	clk_snd,
	rst,
	rst_pon,
	sdram_por,
	inputs,
	status,
	game_profile,
	nvram_busy,
	nvram_ext_en,
	nvram_ext_wr,
	nvram_ext_addr,
	nvram_ext_wdata,
	nvram_ext_rdata,
	nvram_cpu_write,
	ioctl_download,
	ioctl_wr,
	ioctl_addr,
	ioctl_dout,
	ioctl_be,
	ioctl_wait,
	pocket_download_idle,
	snd_dl_wr,
	snd_dl_addr,
	snd_dl_data,
	dcs_dl_active,
	dcs_dl_wr,
	dcs_dl_addr,
	dcs_dl_data,
	dcs_dl_ack,
	gfx_dl_wr,
	gfx_dl_addr,
	gfx_dl_data,
	gfx_dl_ack,
	gfx_dl_idle,
	SDRAM_DQ,
	SDRAM_A,
	SDRAM_BA,
	SDRAM_DQML,
	SDRAM_DQMH,
	SDRAM_nCS,
	SDRAM_nRAS,
	SDRAM_nCAS,
	SDRAM_nWE,
	SDRAM_CKE,
	DDRAM_ADDR,
	DDRAM_BURSTCNT,
	DDRAM_RD,
	DDRAM_DIN,
	DDRAM_BE,
	DDRAM_WE,
	DDRAM_BUSY,
	DDRAM_DOUT,
	DDRAM_DOUT_READY,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de,
	audio_l,
	audio_r,
	pc_dbg,
	illegal_dbg,
	dbg_core_rst,
	dbg_sdram_ready,
	dbg_unp_done,
	dbg_cpu_req,
	dbg_mem_ack,
	dbg_int1,
	dbg_vblank_irq,
	dbg_cpu_ce,
	dbg_derailed,
	dbg_culprit_pc,
	dbg_culprit_instr,
	dbg_derail_pc,
	dbg_iol_drop,
	dbg_iol_wrs,
	dbg_gfx_wbeats,
	dbg_gfx_srd,
	dbg_gfx_cgrd,
	dbg_dma_q_overflow,
	dbg_dma_q_highwater
);
	reg _sv2v_0;
	parameter ROM_HEX = "umk3_maindata.hex";
	parameter [127:0] PIC_RESPONSE_BYTES = 128'h2b1e4a0e02176c60b4082509db019af6;
	parameter [0:0] WWF_IO_SHUFFLE = 1'b0;
	parameter [0:0] PIC_STATUS_DELAY = 1'b1;
	parameter [0:0] TIMED_IRQ_PUMP = 1'b1;
	parameter signed [31:0] H_ACT = 400;
	parameter signed [31:0] H_FP = 5;
	parameter signed [31:0] H_SYNC = 43;
	parameter signed [31:0] H_BP = 58;
	parameter signed [31:0] V_ACT = 254;
	parameter signed [31:0] V_FP = 15;
	parameter signed [31:0] V_SYNC = 3;
	parameter signed [31:0] V_BP = 17;
	parameter [11:0] COL_TAP = 56;
	parameter signed [31:0] DISP_ROW0 = 0;
	parameter [24:0] GFXW_BASE = 25'h0000000;
	parameter [24:0] ROMW_BASE = 25'h00c0000;
	parameter [24:0] VRAMW_BASE = 25'h0140000;
	parameter [24:0] RAMW_BASE = 25'h0180000;
	parameter [23:0] GFX_BYTES = 24'h180000;
	parameter [24:0] SCRATCH_WBASE = 25'h0120000;
	parameter [23:0] PLANE_WORDS = 24'h030000;
	input wire clk;
	input wire clk_cpu;
	input wire ce_pix;
	input wire clk_snd;
	input wire rst;
	input wire rst_pon;
	input wire sdram_por;
	input wire [63:0] inputs;
	input wire [31:0] status;
	input wire [2:0] game_profile;
	input wire nvram_busy;
	input wire nvram_ext_en;
	input wire nvram_ext_wr;
	input wire [15:0] nvram_ext_addr;
	input wire [7:0] nvram_ext_wdata;
	output wire [7:0] nvram_ext_rdata;
	output wire nvram_cpu_write;
	input wire ioctl_download;
	input wire ioctl_wr;
	input wire [24:0] ioctl_addr;
	input wire [15:0] ioctl_dout;
	input wire [1:0] ioctl_be;
	output wire ioctl_wait;
	output wire pocket_download_idle;
	input wire snd_dl_wr;
	input wire [17:0] snd_dl_addr;
	input wire [7:0] snd_dl_data;
	input wire dcs_dl_active;
	input wire dcs_dl_wr;
	input wire [21:0] dcs_dl_addr;
	input wire [7:0] dcs_dl_data;
	output wire dcs_dl_ack;
	input wire gfx_dl_wr;
	input wire [24:0] gfx_dl_addr;
	input wire [7:0] gfx_dl_data;
	output wire gfx_dl_ack;
	output wire gfx_dl_idle;
	inout wire [15:0] SDRAM_DQ;
	output wire [12:0] SDRAM_A;
	output wire [1:0] SDRAM_BA;
	output wire SDRAM_DQML;
	output wire SDRAM_DQMH;
	output wire SDRAM_nCS;
	output wire SDRAM_nRAS;
	output wire SDRAM_nCAS;
	output wire SDRAM_nWE;
	output wire SDRAM_CKE;
	output wire [28:0] DDRAM_ADDR;
	output wire [7:0] DDRAM_BURSTCNT;
	output wire DDRAM_RD;
	output wire [63:0] DDRAM_DIN;
	output wire [7:0] DDRAM_BE;
	output wire DDRAM_WE;
	input wire DDRAM_BUSY;
	input wire [63:0] DDRAM_DOUT;
	input wire DDRAM_DOUT_READY;
	output wire [7:0] vid_r;
	output wire [7:0] vid_g;
	output wire [7:0] vid_b;
	output wire hsync;
	output wire vsync;
	output wire hblank;
	output wire vblank;
	output wire de;
	output wire signed [15:0] audio_l;
	output wire signed [15:0] audio_r;
	output wire [31:0] pc_dbg;
	output wire illegal_dbg;
	output wire dbg_core_rst;
	output wire dbg_sdram_ready;
	output wire dbg_unp_done;
	output wire dbg_cpu_req;
	output wire dbg_mem_ack;
	output wire dbg_int1;
	output wire dbg_vblank_irq;
	output wire dbg_cpu_ce;
	output reg dbg_derailed;
	output reg [31:0] dbg_culprit_pc;
	output reg [15:0] dbg_culprit_instr;
	output reg [31:0] dbg_derail_pc;
	output wire [31:0] dbg_iol_drop;
	output wire [31:0] dbg_iol_wrs;
	output wire [25:0] dbg_gfx_wbeats;
	output wire [15:0] dbg_gfx_srd;
	output wire [15:0] dbg_gfx_cgrd;
	output wire dbg_dma_q_overflow;
	output wire [8:0] dbg_dma_q_highwater;
	wire sdram_ready;
	wire unp_done;
	wire dcs_dl_busy;
	wire nvram_busy_active = nvram_busy === 1'b1;
	wire core_rst = (((((rst | ~sdram_ready) | ioctl_download) | dcs_dl_active) | dcs_dl_busy) | ~unp_done) | nvram_busy_active;
	reg [2:0] ce_div;
	reg rampage_profile;
	always @(*) begin
		if (_sv2v_0)
			;
		rampage_profile = 1'b0;
		case (game_profile)
			3'd6: rampage_profile = 1'b1;
			default: rampage_profile = 1'b0;
		endcase
	end
	always @(posedge clk)
		if (rst)
			ce_div <= 3'd0;
		else if (ce_div == (rampage_profile ? 3'd4 : 3'd3))
			ce_div <= 3'd0;
		else
			ce_div <= ce_div + 3'd1;
	wire cpu_ce = ce_div == 3'd0;
	reg core_rst_sys_m;
	reg core_rst_sys;
	always @(posedge clk) begin
		core_rst_sys_m <= core_rst;
		core_rst_sys <= core_rst_sys_m;
	end
	wire int1;
	wire cpu_req;
	wire cpu_we;
	localparam [31:0] tms34010_pkg_ADDR_WIDTH = 32;
	wire [31:0] cpu_addr;
	localparam [31:0] tms34010_pkg_FIELD_SIZE_WIDTH = 6;
	wire [5:0] cpu_size;
	localparam [31:0] tms34010_pkg_DATA_WIDTH = 32;
	wire [31:0] cpu_wdata;
	wire [31:0] cpu_rdata;
	wire cpu_ack;
	wire cpu_srt;
	wire [5:0] state_w;
	localparam [31:0] tms34010_pkg_INSTR_WORD_WIDTH = 16;
	wire [15:0] instr_w;
	wire [15:0] dpystrt_w;
	wire [15:0] dpyadr_w;
	wire tms_vblank_start;
	wire [15:0] disp_heblnk;
	wire [15:0] disp_hsblnk;
	wire [15:0] disp_veblnk;
	wire [15:0] disp_vsblnk;
	tms34010_core u_core(
		.clk(clk),
		.ce_cpu(cpu_ce),
		.ce_pix(ce_pix),
		.rst(core_rst_sys),
		.mem_req(cpu_req),
		.mem_we(cpu_we),
		.mem_addr(cpu_addr),
		.mem_size(cpu_size),
		.mem_wdata(cpu_wdata),
		.mem_rdata(cpu_rdata),
		.mem_ack(cpu_ack),
		.mem_srt(cpu_srt),
		.state_o(state_w),
		.pc_o(pc_dbg),
		.instr_word_o(instr_w),
		.illegal_opcode_o(illegal_dbg),
		.dpystrt_o(dpystrt_w),
		.dpyadr_o(dpyadr_w),
		.vblank_start_o(tms_vblank_start),
		.lint1_in(int1),
		.heblnk_o(disp_heblnk),
		.hsblnk_o(disp_hsblnk),
		.veblnk_o(disp_veblnk),
		.vsblnk_o(disp_vsblnk)
	);
	wire mem_req;
	wire mem_we;
	wire [31:0] mem_addr;
	wire [5:0] mem_size;
	wire [31:0] mem_wdata;
	wire [31:0] mem_rdata;
	wire mem_ack;
	reg mem_srt_r;
	always @(posedge clk)
		if (core_rst_sys)
			mem_srt_r <= 1'b0;
		else if (cpu_ce)
			mem_srt_r <= cpu_srt;
	yunit_mem_sameclock #(
		.AW(tms34010_pkg_ADDR_WIDTH),
		.DW(tms34010_pkg_DATA_WIDTH),
		.SW(tms34010_pkg_FIELD_SIZE_WIDTH)
	) u_memcdc(
		.clk_cpu(clk),
		.ce_cpu(cpu_ce),
		.rst_cpu(core_rst_sys),
		.c_req(cpu_req),
		.c_we(cpu_we),
		.c_addr(cpu_addr),
		.c_size(cpu_size),
		.c_wdata(cpu_wdata),
		.c_ack(cpu_ack),
		.c_rdata(cpu_rdata),
		.clk_sys(clk),
		.rst_sys(core_rst_sys),
		.m_req(mem_req),
		.m_we(mem_we),
		.m_addr(mem_addr),
		.m_size(mem_size),
		.m_wdata(mem_wdata),
		.m_rdata(mem_rdata),
		.m_ack(mem_ack)
	);
	wire src_req;
	wire [31:0] src_addr;
	wire [7:0] src_data;
	wire src_ack;
	wire src_active;
	wire src_stream;
	wire cgfx_rd;
	wire [25:0] cgfx_addr;
	wire [7:0] cgfx_data;
	wire cgfx_ack;
	wire cgfx_is_rom;
	wire [7:0] arb_cgfx_data;
	wire [7:0] gfx_cgfx_data;
	wire arb_cgfx_ack;
	wire gfx_cgfx_ack;
	assign cgfx_data = (cgfx_is_rom ? arb_cgfx_data : gfx_cgfx_data);
	assign cgfx_ack = (cgfx_is_rom ? arb_cgfx_ack : gfx_cgfx_ack);
	wire scan_req;
	wire [18:0] scan_addr;
	wire [15:0] scan_data;
	wire scan_ack;
	wire [24:0] vsd_addr;
	wire [15:0] vsd_din;
	wire [15:0] vsd_dout;
	wire [1:0] vsd_be;
	wire vsd_rd;
	wire vsd_wr;
	wire vsd_ack;
	wire [24:0] rsd_addr;
	wire [15:0] rsd_din;
	wire [15:0] rsd_dout;
	wire [1:0] rsd_be;
	wire rsd_rd;
	wire rsd_wr;
	wire rsd_ack;
	wire [28:0] vram_ddram_addr;
	wire [7:0] vram_ddram_bc;
	wire vram_ddram_rd;
	wire vram_ddram_we;
	wire [63:0] vram_ddram_din;
	wire [7:0] vram_ddram_be;
	wire vram_ddram_busy;
	wire [63:0] vram_ddram_dout;
	wire vram_ddram_dready;
	wire erase_busy;
	wire blit_busy;
	wire [2:0] dbg_vram_cst;
	wire publication_pending;
	wire vram_wr_busy;
	wire snd_data_wr_w;
	wire snd_data_rd_w;
	wire snd_reset_w;
	wire [7:0] snd_data_wdata_w;
	wire [7:0] snd_rdata_w;
	wire [15:0] snd_stat_w;
	wire signed [15:0] dcs_audio;
	wire dcs_rom_req;
	wire dcs_rom_rdy;
	wire [18:0] dcs_rom_addr;
	wire [63:0] dcs_rom_q;
	wire [28:0] dcs_ddram_addr;
	wire [7:0] dcs_ddram_bc;
	wire dcs_ddram_rd;
	wire dcs_ddram_we;
	wire [63:0] dcs_ddram_din;
	wire [7:0] dcs_ddram_be;
	wire dcs_ddram_busy;
	wire [63:0] dcs_ddram_dout;
	wire dcs_ddram_dready;
	wolf_dcs_board u_dcs_board(
		.clk(clk),
		.rst(core_rst),
		.host_reset(snd_reset_w),
		.host_cmd_wr(snd_data_wr_w),
		.host_cmd_data(snd_data_wdata_w),
		.host_resp_rd(snd_data_rd_w),
		.host_resp_data(snd_rdata_w),
		.host_status(snd_stat_w),
		.rom_req(dcs_rom_req),
		.rom_addr(dcs_rom_addr),
		.rom_rdy(dcs_rom_rdy),
		.rom_q(dcs_rom_q),
		.audio(dcs_audio)
	);
	wolf_dcs_ddr_top u_dcs_ddr(
		.clk(clk),
		.sdram_por(sdram_por),
		.dl_wr(dcs_dl_wr),
		.dl_addr(dcs_dl_addr),
		.dl_data(dcs_dl_data),
		.dl_ack(dcs_dl_ack),
		.dl_busy(dcs_dl_busy),
		.rom_req(dcs_rom_req),
		.rom_addr(dcs_rom_addr),
		.rom_rdy(dcs_rom_rdy),
		.rom_q(dcs_rom_q),
		.ddram_addr(dcs_ddram_addr),
		.ddram_burstcnt(dcs_ddram_bc),
		.ddram_rd(dcs_ddram_rd),
		.ddram_we(dcs_ddram_we),
		.ddram_din(dcs_ddram_din),
		.ddram_be(dcs_ddram_be),
		.ddram_busy(dcs_ddram_busy),
		.ddram_dout(dcs_ddram_dout),
		.ddram_dout_ready(dcs_ddram_dready)
	);
	wire palv_we_a;
	wire palv_we_b;
	wire [14:0] palv_aa;
	wire [14:0] palv_ba;
	wire [15:0] palv_awd;
	wire [15:0] palv_bwd;
	wire vblank_irq;
	wolf_memsys #(
		.ROM_HEX(ROM_HEX),
		.RAM_WORDS(32'h00040000),
		.PIC_RESPONSE_BYTES(PIC_RESPONSE_BYTES),
		.WWF_IO_SHUFFLE(WWF_IO_SHUFFLE),
		.PIC_STATUS_DELAY(PIC_STATUS_DELAY),
		.TIMED_IRQ_PUMP(TIMED_IRQ_PUMP)
	) u_sys(
		.clk(clk),
		.rst(core_rst),
		.mem_req(mem_req),
		.mem_we(mem_we),
		.mem_addr(mem_addr),
		.mem_size(mem_size),
		.mem_wdata(mem_wdata),
		.mem_rdata(mem_rdata),
		.mem_ack(mem_ack),
		.mem_srt(mem_srt_r),
		.src_req(src_req),
		.src_addr(src_addr),
		.src_active(src_active),
		.src_stream(src_stream),
		.src_data(src_data),
		.src_ack(src_ack),
		.inputs(inputs),
		.game_profile(game_profile),
		.int1(int1),
		.snd_data_wr(snd_data_wr_w),
		.snd_data_o(snd_data_wdata_w),
		.snd_data_rd(snd_data_rd_w),
		.snd_reset(snd_reset_w),
		.snd_rdata(snd_rdata_w),
		.snd_stat(snd_stat_w),
		.pic_wr(),
		.pic_wdata(),
		.pic_reset(),
		.pic_rdata(8'h00),
		.pic_status(4'h0),
		.watchdog_kick(),
		.gfxbank_o(),
		.erase_start(1'b0),
		.erase_row0(9'd0),
		.erase_lines(10'd0),
		.erase_busy(erase_busy),
		.blit_busy(blit_busy),
		.vram_wr_busy(vram_wr_busy),
		.publication_hold(publication_pending),
		.nvram_ext_en(nvram_ext_en),
		.nvram_ext_wr(nvram_ext_wr),
		.nvram_ext_addr(nvram_ext_addr),
		.nvram_ext_wdata(nvram_ext_wdata),
		.nvram_ext_rdata(nvram_ext_rdata),
		.nvram_cpu_write(nvram_cpu_write),
		.dbg_vram_cst(dbg_vram_cst),
		.dbg_dma_q_overflow(dbg_dma_q_overflow),
		.dbg_dma_q_highwater(dbg_dma_q_highwater),
		.cpu_gfx_rd(cgfx_rd),
		.cpu_gfx_raddr(cgfx_addr),
		.cpu_gfx_rdata(cgfx_data),
		.cpu_gfx_rack(cgfx_ack),
		.cpu_gfx_is_rom(cgfx_is_rom),
		.scan_req(scan_req),
		.scan_addr(scan_addr),
		.scan_data(scan_data),
		.scan_ack(scan_ack),
		.sdram_por(sdram_por),
		.ddram_addr(vram_ddram_addr),
		.ddram_burstcnt(vram_ddram_bc),
		.ddram_rd(vram_ddram_rd),
		.ddram_we(vram_ddram_we),
		.ddram_din(vram_ddram_din),
		.ddram_be(vram_ddram_be),
		.ddram_busy(vram_ddram_busy),
		.ddram_dout(vram_ddram_dout),
		.ddram_dout_ready(vram_ddram_dready),
		.rsd_addr(rsd_addr),
		.rsd_din(rsd_din),
		.rsd_be(rsd_be),
		.rsd_rd(rsd_rd),
		.rsd_wr(rsd_wr),
		.rsd_dout(rsd_dout),
		.rsd_ack(rsd_ack),
		.palv_we_a(palv_we_a),
		.palv_aa(palv_aa),
		.palv_awd(palv_awd),
		.palv_we_b(palv_we_b),
		.palv_ba(palv_ba),
		.palv_bwd(palv_bwd)
	);
	wire [14:0] pal_raddr;
	wire [15:0] pal_rdata;
	wire [7:0] vid_r_pre;
	wire [7:0] vid_g_pre;
	wire [7:0] vid_b_pre;
	wire hsync_pre;
	wire vsync_pre;
	wire hblank_pre;
	wire vblank_pre;
	wire de_pre;
	localparam signed [31:0] yunit_pkg_FB_ADDR_W = 18;
	wire [17:0] active_row0_diag;
	function automatic [18:0] sv2v_cast_19;
		input reg [18:0] inp;
		sv2v_cast_19 = inp;
	endfunction
	wolf_video_top #(
		.H_ACT(H_ACT),
		.H_FP(H_FP),
		.H_SYNC(H_SYNC),
		.H_BP(H_BP),
		.V_ACT(V_ACT),
		.V_FP(V_FP),
		.V_SYNC(V_SYNC),
		.V_BP(V_BP),
		.COL_TAP(COL_TAP),
		.USE_TMS_RASTER_SYNC(1),
		.WAIT_FOR_RENDER_IDLE(1),
		.NCOL(H_ACT + COL_TAP)
	) u_video(
		.clk(clk),
		.rst(core_rst),
		.ce_pix(ce_pix),
		.raster_vblank_start(tms_vblank_start),
		.disp_row0(sv2v_cast_19((dpyadr_w ^ 16'hfffc) >> 4)),
		.wr_busy(vram_wr_busy),
		.blit_busy(blit_busy),
		.pal_raddr(pal_raddr),
		.pal_rdata(pal_rdata),
		.scan_req(scan_req),
		.scan_addr(scan_addr),
		.scan_data(scan_data),
		.scan_ack(scan_ack),
		.active_row0_diag(active_row0_diag),
		.publication_pending(publication_pending),
		.vid_r(vid_r_pre),
		.vid_g(vid_g_pre),
		.vid_b(vid_b_pre),
		.hsync(hsync_pre),
		.vsync(vsync_pre),
		.hblank(hblank_pre),
		.vblank(vblank_pre),
		.de(de_pre),
		.vblank_irq(vblank_irq)
	);
	wolf_palram #(.AW(15)) u_pal(
		.clk(clk),
		.rst(core_rst),
		.we_a(palv_we_a),
		.aa(palv_aa),
		.awd(palv_awd),
		.we_b(palv_we_b),
		.ba(palv_ba),
		.bwd(palv_bwd),
		.raddr(pal_raddr),
		.rdata(pal_rdata)
	);
	wire [7:0] face_r = vid_r_pre;
	wire [7:0] face_g = vid_g_pre;
	wire [7:0] face_b = vid_b_pre;
	wire face_hs = hsync_pre;
	wire face_vs = vsync_pre;
	wire face_hb = hblank_pre;
	wire face_vb = vblank_pre;
	wire face_de = de_pre;
	wolf_video_post #(
		.H_ACT(H_ACT),
		.V_ACT(V_ACT)
	) u_video_post(
		.clk(clk),
		.ce_pix(ce_pix),
		.vid_r_pre(face_r),
		.vid_g_pre(face_g),
		.vid_b_pre(face_b),
		.hsync_pre(face_hs),
		.vsync_pre(face_vs),
		.hblank_pre(face_hb),
		.vblank_pre(face_vb),
		.de_pre(face_de),
		.vid_r(vid_r),
		.vid_g(vid_g),
		.vid_b(vid_b),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),
		.de(de)
	);
	wire [24:0] sd_addr;
	wire [15:0] sd_din;
	wire [15:0] sd_dout;
	wire [1:0] sd_be;
	wire sd_rd;
	wire sd_wr;
	wire sd_ack;
	wire iol_ack;
	localparam signed [31:0] IOL_AW = 9;
	localparam signed [31:0] IOL_HWM = 256;
	reg [42:0] iol_fifo [0:511];
	reg [IOL_AW:0] iol_wp;
	reg [IOL_AW:0] iol_rp;
	wire [IOL_AW:0] iol_occ = iol_wp - iol_rp;
	wire iol_full = iol_occ == 512;
	wire iol_empty = iol_wp == iol_rp;
	reg iol_hold;
	reg [24:0] iol_addr_r;
	reg [15:0] iol_din_r;
	reg [1:0] iol_be_r;
	reg [31:0] iol_drop_cnt;
	reg [31:0] iol_wr_cnt;
	always @(posedge clk)
		if (sdram_por) begin
			iol_wp <= 1'sb0;
			iol_rp <= 1'sb0;
			iol_hold <= 1'b0;
			iol_drop_cnt <= 1'sb0;
			iol_wr_cnt <= 1'sb0;
		end
		else begin
			if (ioctl_wr && !iol_full) begin
				iol_fifo[iol_wp[8:0]] <= {ioctl_addr, ioctl_dout, ioctl_be};
				iol_wp <= iol_wp + 1'b1;
				iol_wr_cnt <= iol_wr_cnt + 1'b1;
			end
			else if (ioctl_wr && iol_full)
				iol_drop_cnt <= iol_drop_cnt + 1'b1;
			if (iol_hold && iol_ack)
				iol_hold <= 1'b0;
			if ((!iol_hold || (iol_hold && iol_ack)) && !iol_empty) begin
				{iol_addr_r, iol_din_r, iol_be_r} <= iol_fifo[iol_rp[8:0]];
				iol_hold <= 1'b1;
				iol_rp <= iol_rp + 1'b1;
			end
		end
	assign ioctl_wait = iol_occ >= IOL_HWM[IOL_AW:0];
	assign pocket_download_idle = ((iol_empty && !iol_hold) && gfx_dl_idle) && !dcs_dl_busy;
	wire unp_rd;
	wire unp_wr;
	wire unp_ack;
	wire [24:0] unp_addr;
	wire [15:0] unp_din;
	wire [15:0] unp_dout;
	wire boot_unp = unp_rd | unp_wr;
	wire b_iol_rd = unp_rd;
	wire b_iol_wr = (boot_unp ? unp_wr : iol_hold);
	wire [24:0] b_iol_addr = (boot_unp ? unp_addr : iol_addr_r);
	wire [15:0] b_iol_din = (boot_unp ? unp_din : iol_din_r);
	wire [1:0] b_iol_be = (boot_unp ? 2'b11 : iol_be_r);
	wire [15:0] iol_dout;
	assign unp_dout = iol_dout;
	assign unp_ack = iol_ack & boot_unp;
	yunit_sdram_arb #(
		.SD_AW(25),
		.GFXW_BASE(GFXW_BASE),
		.ROMW_BASE(ROMW_BASE),
		.VRAMW_BASE(VRAMW_BASE),
		.RAMW_BASE(RAMW_BASE),
		.GFX_BYTES(GFX_BYTES)
	) u_arb(
		.clk(clk),
		.rst(sdram_por),
		.vsd_addr(25'd0),
		.vsd_din(16'd0),
		.vsd_be(2'd0),
		.vsd_rd(1'b0),
		.vsd_wr(1'b0),
		.vsd_dout(),
		.vsd_ack(),
		.rsd_addr(rsd_addr),
		.rsd_din(rsd_din),
		.rsd_be(rsd_be),
		.rsd_rd(rsd_rd),
		.rsd_wr(rsd_wr),
		.rsd_dout(rsd_dout),
		.rsd_ack(rsd_ack),
		.cgfx_rd(cgfx_rd & cgfx_is_rom),
		.cgfx_addr(cgfx_addr[23:0]),
		.cgfx_data(arb_cgfx_data),
		.cgfx_ack(arb_cgfx_ack),
		.src_rd(1'b0),
		.src_addr(24'd0),
		.src_data(),
		.src_ack(),
		.iol_rd(b_iol_rd),
		.iol_wr(b_iol_wr),
		.iol_addr(b_iol_addr),
		.iol_din(b_iol_din),
		.iol_be(b_iol_be),
		.iol_dout(iol_dout),
		.iol_ack(iol_ack),
		.sd_addr(sd_addr),
		.sd_din(sd_din),
		.sd_be(sd_be),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_dout(sd_dout),
		.sd_ack(sd_ack)
	);
	wire [28:0] gfx_ddram_addr;
	wire [7:0] gfx_ddram_bc;
	wire gfx_ddram_rd;
	wire gfx_ddram_we;
	wire [63:0] gfx_ddram_din;
	wire [7:0] gfx_ddram_be;
	wire gfx_ddram_busy;
	wire [63:0] gfx_ddram_dout;
	wire gfx_ddram_dready;
	wire gfx_dcs_safe;
	wire [28:0] vg_ddram_addr;
	wire [7:0] vg_ddram_bc;
	wire vg_ddram_rd;
	wire vg_ddram_we;
	wire [63:0] vg_ddram_din;
	wire [7:0] vg_ddram_be;
	wire vg_ddram_busy;
	wire [63:0] vg_ddram_dout;
	wire vg_ddram_dready;
	wolf_gfx_ddr_top #(.USE_STREAM_HINT(1'b1)) u_gfxddr(
		.clk(clk),
		.rst(core_rst),
		.sdram_por(sdram_por),
		.src_req(src_req),
		.src_addr(src_addr),
		.src_active(src_active),
		.src_stream(src_stream),
		.src_data(src_data),
		.src_ack(src_ack),
		.dcs_safe(gfx_dcs_safe),
		.cg_req(cgfx_rd & ~cgfx_is_rom),
		.cg_addr(cgfx_addr),
		.cg_data(gfx_cgfx_data),
		.cg_ack(gfx_cgfx_ack),
		.dl_wr(gfx_dl_wr),
		.dl_addr(gfx_dl_addr),
		.dl_data(gfx_dl_data),
		.dl_ack(gfx_dl_ack),
		.dl_idle(gfx_dl_idle),
		.dbg_wbeats(dbg_gfx_wbeats),
		.dbg_srd(dbg_gfx_srd),
		.dbg_cgrd(dbg_gfx_cgrd),
		.ddram_addr(gfx_ddram_addr),
		.ddram_burstcnt(gfx_ddram_bc),
		.ddram_rd(gfx_ddram_rd),
		.ddram_we(gfx_ddram_we),
		.ddram_din(gfx_ddram_din),
		.ddram_be(gfx_ddram_be),
		.ddram_busy(gfx_ddram_busy),
		.ddram_dout(gfx_ddram_dout),
		.ddram_dout_ready(gfx_ddram_dready)
	);
	wolf_ddr3_arb u_ddr3arb(
		.clk(clk),
		.a_addr(vram_ddram_addr),
		.a_burstcnt(vram_ddram_bc),
		.a_rd(vram_ddram_rd),
		.a_we(vram_ddram_we),
		.a_din(vram_ddram_din),
		.a_be(vram_ddram_be),
		.a_busy(vram_ddram_busy),
		.a_dout(vram_ddram_dout),
		.a_dout_ready(vram_ddram_dready),
		.b_addr(gfx_ddram_addr),
		.b_burstcnt(gfx_ddram_bc),
		.b_rd(gfx_ddram_rd),
		.b_we(gfx_ddram_we),
		.b_din(gfx_ddram_din),
		.b_be(gfx_ddram_be),
		.b_busy(gfx_ddram_busy),
		.b_dout(gfx_ddram_dout),
		.b_dout_ready(gfx_ddram_dready),
		.ddram_addr(vg_ddram_addr),
		.ddram_burstcnt(vg_ddram_bc),
		.ddram_rd(vg_ddram_rd),
		.ddram_we(vg_ddram_we),
		.ddram_din(vg_ddram_din),
		.ddram_be(vg_ddram_be),
		.ddram_busy(vg_ddram_busy),
		.ddram_dout(vg_ddram_dout),
		.ddram_dout_ready(vg_ddram_dready)
	);
	wolf_ddr3_arb #(.HONOR_B_ALLOW(1'b1)) u_ddr3arb_dcs(
		.clk(clk),
		.b_allow(gfx_dcs_safe),
		.a_addr(vg_ddram_addr),
		.a_burstcnt(vg_ddram_bc),
		.a_rd(vg_ddram_rd),
		.a_we(vg_ddram_we),
		.a_din(vg_ddram_din),
		.a_be(vg_ddram_be),
		.a_busy(vg_ddram_busy),
		.a_dout(vg_ddram_dout),
		.a_dout_ready(vg_ddram_dready),
		.b_addr(dcs_ddram_addr),
		.b_burstcnt(dcs_ddram_bc),
		.b_rd(dcs_ddram_rd),
		.b_we(dcs_ddram_we),
		.b_din(dcs_ddram_din),
		.b_be(dcs_ddram_be),
		.b_busy(dcs_ddram_busy),
		.b_dout(dcs_ddram_dout),
		.b_dout_ready(dcs_ddram_dready),
		.ddram_addr(DDRAM_ADDR),
		.ddram_burstcnt(DDRAM_BURSTCNT),
		.ddram_rd(DDRAM_RD),
		.ddram_we(DDRAM_WE),
		.ddram_din(DDRAM_DIN),
		.ddram_be(DDRAM_BE),
		.ddram_busy(DDRAM_BUSY),
		.ddram_dout(DDRAM_DOUT),
		.ddram_dout_ready(DDRAM_DOUT_READY)
	);
	assign unp_done = 1'b1;
	assign unp_rd = 1'b0;
	assign unp_wr = 1'b0;
	assign unp_addr = 25'd0;
	assign unp_din = 16'd0;
	wire [24:0] ctl_addr;
	wire [15:0] ctl_din;
	wire [15:0] ctl_dout;
	wire [1:0] ctl_wtbt;
	wire ctl_rd;
	wire ctl_we;
	wire ctl_ready;
	yunit_sdram_adapter u_sdadapt(
		.clk(clk),
		.rst(sdram_por),
		.sd_addr(sd_addr),
		.sd_din(sd_din),
		.sd_be(sd_be),
		.sd_rd(sd_rd),
		.sd_wr(sd_wr),
		.sd_dout(sd_dout),
		.sd_ack(sd_ack),
		.sdram_ready(sdram_ready),
		.ctl_addr(ctl_addr),
		.ctl_din(ctl_din),
		.ctl_wtbt(ctl_wtbt),
		.ctl_rd(ctl_rd),
		.ctl_we(ctl_we),
		.ctl_dout(ctl_dout),
		.ctl_ready(ctl_ready)
	);
	sdram_stock u_sdram(
		.init(sdram_por),
		.clk(clk),
		.addr(ctl_addr),
		.din(ctl_din),
		.wtbt(ctl_wtbt),
		.we(ctl_we),
		.rd(ctl_rd),
		.dout(ctl_dout),
		.ready(ctl_ready),
		.SDRAM_DQ(SDRAM_DQ),
		.SDRAM_A(SDRAM_A),
		.SDRAM_BA(SDRAM_BA),
		.SDRAM_DQML(SDRAM_DQML),
		.SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_nCS(SDRAM_nCS),
		.SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_nWE(SDRAM_nWE),
		.SDRAM_CKE(SDRAM_CKE)
	);
	assign audio_l = dcs_audio;
	assign audio_r = dcs_audio;
	assign dbg_core_rst = core_rst;
	assign dbg_sdram_ready = sdram_ready;
	assign dbg_unp_done = unp_done;
	assign dbg_cpu_req = cpu_req;
	assign dbg_mem_ack = mem_ack;
	assign dbg_int1 = int1;
	assign dbg_vblank_irq = vblank_irq;
	assign dbg_cpu_ce = cpu_ce;
	assign dbg_iol_drop = iol_drop_cnt;
	assign dbg_iol_wrs = iol_wr_cnt;
	reg [1:0] rd_cnt;
	reg ack_q;
	reg d_started;
	reg [31:0] d_prevpc;
	always @(posedge clk)
		if (cpu_ce) begin
			if (core_rst_sys) begin
				dbg_derailed <= 1'b0;
				rd_cnt <= 2'd0;
				ack_q <= 1'b0;
				d_started <= 1'b0;
				d_prevpc <= 32'hffffffff;
				dbg_culprit_pc <= 32'hdeadbeef;
				dbg_culprit_instr <= 16'hdead;
				dbg_derail_pc <= 32'hdeadbeef;
			end
			else begin
				ack_q <= cpu_ack;
				if (((cpu_ack && !ack_q) && !cpu_we) && (rd_cnt == 2'd0)) begin
					dbg_culprit_pc <= cpu_rdata;
					rd_cnt <= 2'd1;
				end
				if (pc_dbg !== d_prevpc) begin
					d_prevpc <= pc_dbg;
					if (pc_dbg[31:23] == 9'h1ff)
						d_started <= 1'b1;
					else if ((d_started && !dbg_derailed) && (^pc_dbg !== 1'bx)) begin
						dbg_derailed <= 1'b1;
						dbg_derail_pc <= pc_dbg;
						dbg_culprit_instr <= d_prevpc[15:0];
					end
				end
			end
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module smashtv_diag2_overlay (
	clk,
	ce_pix,
	rst,
	core_rst,
	sdram_ready,
	unp_done,
	ioctl_download,
	cpu_req,
	mem_ack,
	int1,
	vblank_irq,
	cpu_ce,
	pc,
	illegal,
	derailed,
	culprit_pc,
	culprit_instr,
	derail_pc,
	g_r,
	g_g,
	g_b,
	g_hs,
	g_vs,
	g_hb,
	g_vb,
	g_de,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de
);
	reg _sv2v_0;
	parameter signed [31:0] H_ACT = 410;
	parameter signed [31:0] H_FP = 6;
	parameter signed [31:0] H_SYNC = 40;
	parameter signed [31:0] H_BP = 50;
	parameter signed [31:0] V_ACT = 256;
	parameter signed [31:0] V_FP = 13;
	parameter signed [31:0] V_SYNC = 8;
	parameter signed [31:0] V_BP = 12;
	input wire clk;
	input wire ce_pix;
	input wire rst;
	input wire core_rst;
	input wire sdram_ready;
	input wire unp_done;
	input wire ioctl_download;
	input wire cpu_req;
	input wire mem_ack;
	input wire int1;
	input wire vblank_irq;
	input wire cpu_ce;
	input wire [31:0] pc;
	input wire illegal;
	input wire derailed;
	input wire [31:0] culprit_pc;
	input wire [15:0] culprit_instr;
	input wire [31:0] derail_pc;
	input wire [7:0] g_r;
	input wire [7:0] g_g;
	input wire [7:0] g_b;
	input wire g_hs;
	input wire g_vs;
	input wire g_hb;
	input wire g_vb;
	input wire g_de;
	output reg [7:0] vid_r;
	output reg [7:0] vid_g;
	output reg [7:0] vid_b;
	output reg hsync;
	output reg vsync;
	output reg hblank;
	output reg vblank;
	output reg de;
	localparam signed [31:0] H_TOTAL = ((H_ACT + H_FP) + H_SYNC) + H_BP;
	localparam signed [31:0] V_TOTAL = ((V_ACT + V_FP) + V_SYNC) + V_BP;
	function automatic [14:0] glyph;
		input [3:0] v;
		case (v)
			4'h0: glyph = 15'b111101101101111;
			4'h1: glyph = 15'b010110010010111;
			4'h2: glyph = 15'b111001111100111;
			4'h3: glyph = 15'b111001111001111;
			4'h4: glyph = 15'b101101111001001;
			4'h5: glyph = 15'b111100111001111;
			4'h6: glyph = 15'b111100111101111;
			4'h7: glyph = 15'b111001001010010;
			4'h8: glyph = 15'b111101111101111;
			4'h9: glyph = 15'b111101111001111;
			4'ha: glyph = 15'b111101111101101;
			4'hb: glyph = 15'b110101110101110;
			4'hc: glyph = 15'b111100100100111;
			4'hd: glyph = 15'b110101101101110;
			4'he: glyph = 15'b111100111100111;
			default: glyph = 15'b111100111100100;
		endcase
	endfunction
	function automatic fpix;
		input [3:0] d;
		input [2:0] col;
		input [2:0] row;
		reg [14:0] g;
		reg [2:0] rb;
		begin
			g = glyph(d);
			case (row)
				3'd0: rb = g[14:12];
				3'd1: rb = g[11:9];
				3'd2: rb = g[8:6];
				3'd3: rb = g[5:3];
				default: rb = g[2:0];
			endcase
			fpix = (col == 3'd0 ? rb[2] : (col == 3'd1 ? rb[1] : (col == 3'd2 ? rb[0] : 1'b0)));
		end
	endfunction
	reg [11:0] gx;
	reg [11:0] gy;
	reg de_q;
	reg vb_q;
	reg [23:0] frame;
	reg [31:0] pc_q;
	reg [31:0] pc_qq;
	reg [31:0] pc_show;
	always @(posedge clk)
		if (rst) begin
			gx <= 0;
			gy <= 0;
			de_q <= 0;
			vb_q <= 0;
			frame <= 0;
			pc_q <= 0;
			pc_qq <= 0;
			pc_show <= 0;
		end
		else if (ce_pix) begin
			de_q <= g_de;
			vb_q <= g_vb;
			pc_q <= pc;
			pc_qq <= pc_q;
			if (g_vb && !vb_q) begin
				gy <= 12'd0;
				gx <= 12'd0;
				frame <= frame + 24'd1;
				if (frame[4:0] == 5'd0)
					pc_show <= pc_qq;
			end
			else if (g_de)
				gx <= gx + 12'd1;
			else if (de_q && !g_de) begin
				gx <= 12'd0;
				gy <= gy + 12'd1;
			end
		end
	wire [11:0] hc = gx << 1;
	wire [11:0] vc = gy << 1;
	wire s0_de = (hc < H_ACT) && (vc < V_ACT);
	wire frame_tick = (ce_pix && g_vb) && !vb_q;
	reg a1_req;
	reg a0_req;
	reg a1_ack;
	reg a0_ack;
	reg a1_i1;
	reg a0_i1;
	reg a1_vb;
	reg a0_vb;
	reg a1_ce;
	reg a0_ce;
	reg alive_req;
	reg alive_ack;
	reg alive_i1;
	reg alive_vb;
	reg alive_ce;
	reg illegal_sticky;
	always @(posedge clk)
		if (rst) begin
			a1_req <= 0;
			a0_req <= 0;
			a1_ack <= 0;
			a0_ack <= 0;
			a1_i1 <= 0;
			a0_i1 <= 0;
			a1_vb <= 0;
			a0_vb <= 0;
			a1_ce <= 0;
			a0_ce <= 0;
			alive_req <= 0;
			alive_ack <= 0;
			alive_i1 <= 0;
			alive_vb <= 0;
			alive_ce <= 0;
			illegal_sticky <= 0;
		end
		else begin
			if (illegal)
				illegal_sticky <= 1'b1;
			if (cpu_req)
				a1_req <= 1'b1;
			else
				a0_req <= 1'b1;
			if (mem_ack)
				a1_ack <= 1'b1;
			else
				a0_ack <= 1'b1;
			if (int1)
				a1_i1 <= 1'b1;
			else
				a0_i1 <= 1'b1;
			if (vblank_irq)
				a1_vb <= 1'b1;
			else
				a0_vb <= 1'b1;
			if (cpu_ce)
				a1_ce <= 1'b1;
			else
				a0_ce <= 1'b1;
			if (frame_tick) begin
				alive_req <= a1_req & a0_req;
				a1_req <= 1'b0;
				a0_req <= 1'b0;
				alive_ack <= a1_ack & a0_ack;
				a1_ack <= 1'b0;
				a0_ack <= 1'b0;
				alive_i1 <= a1_i1 & a0_i1;
				a1_i1 <= 1'b0;
				a0_i1 <= 1'b0;
				alive_vb <= a1_vb & a0_vb;
				a1_vb <= 1'b0;
				a0_vb <= 1'b0;
				alive_ce <= a1_ce & a0_ce;
				a1_ce <= 1'b0;
				a0_ce <= 1'b0;
			end
		end
	localparam signed [31:0] LEDW = H_ACT / 10;
	wire in_leds = (vc >= 12'd44) && (vc < 12'd52);
	wire [3:0] led_lane = (hc < LEDW ? 4'd0 : (hc < (2 * LEDW) ? 4'd1 : (hc < (3 * LEDW) ? 4'd2 : (hc < (4 * LEDW) ? 4'd3 : (hc < (5 * LEDW) ? 4'd4 : (hc < (6 * LEDW) ? 4'd5 : (hc < (7 * LEDW) ? 4'd6 : (hc < (8 * LEDW) ? 4'd7 : (hc < (9 * LEDW) ? 4'd8 : 4'd9)))))))));
	wire [11:0] led_x = hc - (led_lane * LEDW);
	wire led_body = (led_x >= 12'd2) && (led_x < (LEDW - 2));
	reg led_good;
	always @(*) begin
		if (_sv2v_0)
			;
		case (led_lane)
			4'd0: led_good = ~core_rst;
			4'd1: led_good = sdram_ready;
			4'd2: led_good = unp_done;
			4'd3: led_good = ~ioctl_download;
			4'd4: led_good = ~illegal_sticky;
			4'd5: led_good = alive_req;
			4'd6: led_good = alive_ack;
			4'd7: led_good = alive_i1;
			4'd8: led_good = alive_vb;
			default: led_good = alive_ce;
		endcase
	end
	localparam signed [31:0] HE = H_ACT / 8;
	reg [7:0] cbr;
	reg [7:0] cbg;
	reg [7:0] cbb;
	wire [2:0] barx = (hc < HE ? 3'd0 : (hc < (2 * HE) ? 3'd1 : (hc < (3 * HE) ? 3'd2 : (hc < (4 * HE) ? 3'd3 : (hc < (5 * HE) ? 3'd4 : (hc < (6 * HE) ? 3'd5 : (hc < (7 * HE) ? 3'd6 : 3'd7)))))));
	always @(*) begin
		if (_sv2v_0)
			;
		case (barx)
			3'd0: {cbr, cbg, cbb} = 24'hffffff;
			3'd1: {cbr, cbg, cbb} = 24'hffff00;
			3'd2: {cbr, cbg, cbb} = 24'h00ffff;
			3'd3: {cbr, cbg, cbb} = 24'h00ff00;
			3'd4: {cbr, cbg, cbb} = 24'hff00ff;
			3'd5: {cbr, cbg, cbb} = 24'hff0000;
			3'd6: {cbr, cbg, cbb} = 24'h0000ff;
			default: {cbr, cbg, cbb} = 24'h202020;
		endcase
	end
	reg [31:0] rowval;
	reg in_hex;
	reg [11:0] ry0;
	always @(*) begin
		if (_sv2v_0)
			;
		in_hex = 1'b0;
		rowval = 32'd0;
		ry0 = 12'd0;
		if ((vc >= 12'd52) && (vc < 12'd96)) begin
			in_hex = 1'b1;
			ry0 = 12'd52;
			rowval = culprit_pc;
		end
		else if ((vc >= 12'd100) && (vc < 12'd144)) begin
			in_hex = 1'b1;
			ry0 = 12'd100;
			rowval = {16'h0000, culprit_instr};
		end
		else if ((vc >= 12'd148) && (vc < 12'd192)) begin
			in_hex = 1'b1;
			ry0 = 12'd148;
			rowval = derail_pc;
		end
		else if ((vc >= 12'd200) && (vc < 12'd244)) begin
			in_hex = 1'b1;
			ry0 = 12'd200;
			rowval = pc_show;
		end
	end
	localparam signed [31:0] PX0 = 77;
	wire hxin = (hc >= PX0) && (hc < 333);
	wire [7:0] hrx = hc - PX0[11:0];
	wire [2:0] hdig = hrx[7:5];
	wire [1:0] hfcol = hrx[4:3];
	wire [11:0] hry12 = vc - ry0;
	wire [2:0] hfrow = hry12[5:3];
	wire [4:0] hsh = {2'b00, 3'd7 - hdig} << 2;
	wire [3:0] hnyb = rowval >> hsh;
	wire hex_on = (((in_hex && hxin) && (hfcol < 2'd3)) && (hfrow < 3'd5)) && fpix(hnyb, {1'b0, hfcol}, hfrow);
	wire in_status = (vc >= 12'd24) && (vc < 12'd44);
	wire live_col = hc == frame[8:0];
	always @(posedge clk)
		if (ce_pix) begin
			de <= g_de;
			hsync <= g_hs;
			vsync <= g_vs;
			hblank <= g_hb;
			vblank <= g_vb;
			if (!g_de) begin
				vid_r <= 8'd0;
				vid_g <= 8'd0;
				vid_b <= 8'd0;
			end
			else if (!s0_de) begin
				vid_r <= g_r;
				vid_g <= g_g;
				vid_b <= g_b;
			end
			else if (vc < 12'd20) begin
				vid_r <= cbr;
				vid_g <= cbg;
				vid_b <= cbb;
			end
			else if (live_col) begin
				vid_r <= 8'hff;
				vid_g <= 8'hff;
				vid_b <= 8'hff;
			end
			else if (in_status) begin
				if (derailed) begin
					vid_r <= 8'hc0;
					vid_g <= 8'h00;
					vid_b <= 8'h00;
				end
				else begin
					vid_r <= 8'h00;
					vid_g <= 8'hc0;
					vid_b <= 8'h00;
				end
			end
			else if (in_leds) begin
				if (led_body) begin
					if (led_good) begin
						vid_r <= 8'h00;
						vid_g <= 8'he0;
						vid_b <= 8'h00;
					end
					else begin
						vid_r <= 8'he0;
						vid_g <= 8'h00;
						vid_b <= 8'h00;
					end
				end
				else begin
					vid_r <= 8'h00;
					vid_g <= 8'h00;
					vid_b <= 8'h00;
				end
			end
			else if (in_hex) begin
				if (hex_on) begin
					vid_r <= 8'hff;
					vid_g <= 8'hff;
					vid_b <= 8'h00;
				end
				else begin
					vid_r <= 8'h10;
					vid_g <= 8'h10;
					vid_b <= 8'h30;
				end
			end
			else begin
				vid_r <= 8'h08;
				vid_g <= 8'h08;
				vid_b <= 8'h08;
			end
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_diag_geom_overlay (
	clk,
	ce_pix,
	rst,
	g_r,
	g_g,
	g_b,
	g_hs,
	g_vs,
	g_hb,
	g_vb,
	g_de,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de
);
	reg _sv2v_0;
	input wire clk;
	input wire ce_pix;
	input wire rst;
	input wire [7:0] g_r;
	input wire [7:0] g_g;
	input wire [7:0] g_b;
	input wire g_hs;
	input wire g_vs;
	input wire g_hb;
	input wire g_vb;
	input wire g_de;
	output reg [7:0] vid_r;
	output reg [7:0] vid_g;
	output reg [7:0] vid_b;
	output reg hsync;
	output reg vsync;
	output reg hblank;
	output reg vblank;
	output reg de;
	function automatic [14:0] glyph;
		input [3:0] v;
		case (v)
			4'h0: glyph = 15'b111101101101111;
			4'h1: glyph = 15'b010110010010111;
			4'h2: glyph = 15'b111001111100111;
			4'h3: glyph = 15'b111001111001111;
			4'h4: glyph = 15'b101101111001001;
			4'h5: glyph = 15'b111100111001111;
			4'h6: glyph = 15'b111100111101111;
			4'h7: glyph = 15'b111001001010010;
			4'h8: glyph = 15'b111101111101111;
			4'h9: glyph = 15'b111101111001111;
			4'ha: glyph = 15'b111101111101101;
			4'hb: glyph = 15'b110101110101110;
			4'hc: glyph = 15'b111100100100111;
			4'hd: glyph = 15'b110101101101110;
			4'he: glyph = 15'b111100111100111;
			default: glyph = 15'b111100111100100;
		endcase
	endfunction
	function automatic fpix;
		input [3:0] d;
		input [1:0] col;
		input [2:0] row;
		reg [14:0] g;
		reg [2:0] rb;
		begin
			g = glyph(d);
			case (row)
				3'd0: rb = g[14:12];
				3'd1: rb = g[11:9];
				3'd2: rb = g[8:6];
				3'd3: rb = g[5:3];
				default: rb = g[2:0];
			endcase
			fpix = (col == 2'd0 ? rb[2] : (col == 2'd1 ? rb[1] : rb[0]));
		end
	endfunction
	reg [11:0] gx;
	reg [11:0] gy;
	reg de_q;
	reg vb_q;
	reg hs_q;
	reg [11:0] de_cnt;
	reg [11:0] hb_cnt;
	reg [11:0] line_pix;
	reg saw_de;
	reg [11:0] awidth_ln;
	reg [11:0] hblow_ln;
	reg [11:0] ltotal_ln;
	reg [11:0] frame_lines;
	reg [11:0] deh_lines;
	reg [11:0] cmin_acc;
	reg [11:0] cmax_acc;
	reg [11:0] m_awidth;
	reg [11:0] m_hbcnt;
	reg [11:0] m_ltotal;
	reg [11:0] m_cmin;
	reg [11:0] m_cmax;
	reg [11:0] m_aheight;
	reg [5:0] grat_x;
	reg [5:0] grat_y;
	wire nonblack = |{g_r, g_g, g_b};
	wire hs_rise = g_hs & ~hs_q;
	wire vb_rise = g_vb & ~vb_q;
	always @(posedge clk)
		if (rst) begin
			gx <= 0;
			gy <= 0;
			de_q <= 0;
			vb_q <= 0;
			hs_q <= 0;
			de_cnt <= 0;
			hb_cnt <= 0;
			line_pix <= 0;
			saw_de <= 0;
			awidth_ln <= 0;
			hblow_ln <= 0;
			ltotal_ln <= 0;
			frame_lines <= 0;
			deh_lines <= 0;
			cmin_acc <= 12'hfff;
			cmax_acc <= 0;
			m_awidth <= 0;
			m_hbcnt <= 0;
			m_ltotal <= 0;
			m_cmin <= 0;
			m_cmax <= 0;
			m_aheight <= 0;
			grat_x <= 0;
			grat_y <= 0;
		end
		else if (ce_pix) begin
			de_q <= g_de;
			vb_q <= g_vb;
			hs_q <= g_hs;
			if (vb_rise) begin
				gy <= 0;
				gx <= 0;
				grat_y <= 0;
				grat_x <= 0;
			end
			else if (g_de) begin
				gx <= gx + 12'd1;
				grat_x <= (grat_x == 6'd49 ? 6'd0 : grat_x + 6'd1);
			end
			else if (de_q && !g_de) begin
				gx <= 0;
				grat_x <= 0;
				gy <= gy + 12'd1;
				grat_y <= (grat_y == 6'd31 ? 6'd0 : grat_y + 6'd1);
			end
			line_pix <= line_pix + 12'd1;
			if (g_de) begin
				de_cnt <= de_cnt + 12'd1;
				saw_de <= 1'b1;
			end
			if (!g_hb)
				hb_cnt <= hb_cnt + 12'd1;
			if (g_de && nonblack) begin
				if (gx < cmin_acc)
					cmin_acc <= gx;
				if (gx > cmax_acc)
					cmax_acc <= gx;
			end
			if (hs_rise) begin
				ltotal_ln <= line_pix;
				if (saw_de) begin
					awidth_ln <= de_cnt;
					hblow_ln <= hb_cnt;
					deh_lines <= deh_lines + 12'd1;
				end
				frame_lines <= frame_lines + 12'd1;
				de_cnt <= 0;
				hb_cnt <= 0;
				line_pix <= 0;
				saw_de <= 0;
			end
			if (vb_rise) begin
				m_awidth <= awidth_ln;
				m_hbcnt <= hblow_ln;
				m_ltotal <= ltotal_ln;
				m_aheight <= deh_lines;
				m_cmin <= (cmax_acc == 0 ? 12'd0 : cmin_acc);
				m_cmax <= cmax_acc;
				frame_lines <= 0;
				deh_lines <= 0;
				cmin_acc <= 12'hfff;
				cmax_acc <= 0;
			end
		end
	localparam signed [31:0] PX = 6;
	localparam signed [31:0] PY = 6;
	wire in_box = (((gx >= PX) && (gx < 54)) && (gy >= PY)) && (gy < 174);
	wire [11:0] lx = gx - PX[11:0];
	wire [11:0] ly = gy - PY[11:0];
	wire [1:0] digit = lx[5:4];
	wire [3:0] dx = lx[3:0];
	reg [11:0] rowval;
	reg [2:0] rowsel;
	reg in_rowband;
	reg [11:0] rytop;
	always @(*) begin
		if (_sv2v_0)
			;
		in_rowband = 1'b0;
		rowsel = 3'd0;
		rytop = 12'd0;
		rowval = 12'd0;
		if (ly < 12'd20) begin
			in_rowband = 1;
			rowsel = 0;
			rytop = 12'd0;
			rowval = m_awidth;
		end
		else if ((ly >= 12'd28) && (ly < 12'd48)) begin
			in_rowband = 1;
			rowsel = 1;
			rytop = 12'd28;
			rowval = m_hbcnt;
		end
		else if ((ly >= 12'd56) && (ly < 12'd76)) begin
			in_rowband = 1;
			rowsel = 2;
			rytop = 12'd56;
			rowval = m_ltotal;
		end
		else if ((ly >= 12'd84) && (ly < 12'd104)) begin
			in_rowband = 1;
			rowsel = 3;
			rytop = 12'd84;
			rowval = m_cmin;
		end
		else if ((ly >= 12'd112) && (ly < 12'd132)) begin
			in_rowband = 1;
			rowsel = 4;
			rytop = 12'd112;
			rowval = m_cmax;
		end
		else if ((ly >= 12'd140) && (ly < 12'd160)) begin
			in_rowband = 1;
			rowsel = 5;
			rytop = 12'd140;
			rowval = m_aheight;
		end
	end
	wire [11:0] ry = ly - rytop;
	wire [2:0] frow = ry[4:2];
	wire [1:0] fcol = dx[3:2];
	wire [3:0] nyb = rowval >> ({1'b0, 2'd2 - digit} << 2);
	wire glyph_on = ((((in_box && in_rowband) && (digit < 2'd3)) && (dx < 4'd12)) && (frow < 3'd5)) && fpix(nyb, fcol, frow);
	reg [23:0] rowcol;
	always @(*) begin
		if (_sv2v_0)
			;
		case (rowsel)
			3'd0: rowcol = 24'hffff00;
			3'd1: rowcol = 24'h00ffff;
			3'd2: rowcol = 24'h00ff00;
			3'd3: rowcol = 24'hff8000;
			3'd4: rowcol = 24'hff00ff;
			default: rowcol = 24'hffffff;
		endcase
	end
	wire vtick = grat_x == 6'd0;
	wire htick = grat_y == 6'd0;
	wire ledge = gx == 12'd0;
	always @(posedge clk)
		if (rst) begin
			de <= 0;
			hsync <= 0;
			vsync <= 0;
			hblank <= 0;
			vblank <= 0;
			vid_r <= 0;
			vid_g <= 0;
			vid_b <= 0;
		end
		else if (ce_pix) begin
			de <= g_de;
			hsync <= g_hs;
			vsync <= g_vs;
			hblank <= g_hb;
			vblank <= g_vb;
			if (!g_de) begin
				vid_r <= 8'h00;
				vid_g <= 8'h00;
				vid_b <= 8'h00;
			end
			else if (in_box) begin
				if (glyph_on) begin
					vid_r <= rowcol[23:16];
					vid_g <= rowcol[15:8];
					vid_b <= rowcol[7:0];
				end
				else begin
					vid_r <= 8'h00;
					vid_g <= 8'h00;
					vid_b <= 8'h30;
				end
			end
			else if (ledge) begin
				vid_r <= 8'hff;
				vid_g <= 8'h00;
				vid_b <= 8'h00;
			end
			else if (vtick) begin
				vid_r <= 8'hff;
				vid_g <= 8'hff;
				vid_b <= 8'hff;
			end
			else if (htick) begin
				vid_r <= 8'h80;
				vid_g <= 8'h80;
				vid_b <= 8'h80;
			end
			else begin
				vid_r <= g_r;
				vid_g <= g_g;
				vid_b <= g_b;
			end
		end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_faceoff_diag_overlay (
	clk,
	rst,
	ce_pix,
	enable,
	px_evt,
	px_x,
	px_y,
	px_write,
	px_copy_nz,
	px_color,
	active_row0,
	g_r,
	g_g,
	g_b,
	g_hs,
	g_vs,
	g_hb,
	g_vb,
	g_de,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de
);
	reg _sv2v_0;
	parameter signed [31:0] H_ACT = 400;
	parameter signed [31:0] V_ACT = 254;
	parameter [11:0] COL_TAP = 56;
	input wire clk;
	input wire rst;
	input wire ce_pix;
	input wire enable;
	input wire px_evt;
	input wire [9:0] px_x;
	input wire [8:0] px_y;
	input wire px_write;
	input wire px_copy_nz;
	input wire px_color;
	input wire [18:0] active_row0;
	input wire [7:0] g_r;
	input wire [7:0] g_g;
	input wire [7:0] g_b;
	input wire g_hs;
	input wire g_vs;
	input wire g_hb;
	input wire g_vb;
	input wire g_de;
	output reg [7:0] vid_r;
	output reg [7:0] vid_g;
	output reg [7:0] vid_b;
	output reg hsync;
	output reg vsync;
	output reg hblank;
	output reg vblank;
	output reg de;
	localparam [8:0] PAGE0_BASE = 9'd511;
	localparam [8:0] PAGE1_BASE = 9'd253;
	wire px_page0 = (px_y == PAGE0_BASE) || (px_y <= 9'd252);
	wire px_page1 = (px_y >= PAGE1_BASE) && (px_y <= 9'd506);
	wire [8:0] px_rel_y = (px_page0 ? px_y + 9'd1 : px_y - PAGE1_BASE);
	wire px_x_visible = (px_x >= COL_TAP) && (px_x < (COL_TAP + H_ACT));
	wire px_y_visible = px_page0 || px_page1;
	wire px_visible = ((px_evt && px_x_visible) && px_y_visible) && (px_rel_y < V_ACT);
	wire [9:0] px_rel_x = px_x - COL_TAP;
	wire [2:0] px_tile_x = px_rel_x[8:6];
	wire [2:0] px_tile_y = px_rel_y[7:5];
	wire [6:0] px_tile = {px_page1, px_tile_y, px_tile_x};
	reg [127:0] live_seen;
	reg [127:0] live_write;
	reg [127:0] live_copy_nz;
	reg [127:0] live_color;
	reg [127:0] show_seen;
	reg [127:0] show_write;
	reg [127:0] show_copy_nz;
	reg [127:0] show_color;
	reg vb_q;
	wire vb_rise = g_vb && !vb_q;
	always @(posedge clk)
		if (rst) begin
			live_seen <= 1'sb0;
			live_write <= 1'sb0;
			live_copy_nz <= 1'sb0;
			live_color <= 1'sb0;
			show_seen <= 1'sb0;
			show_write <= 1'sb0;
			show_copy_nz <= 1'sb0;
			show_color <= 1'sb0;
			vb_q <= 1'b0;
		end
		else begin
			if (ce_pix)
				vb_q <= g_vb;
			if (ce_pix && vb_rise) begin
				show_seen <= live_seen;
				show_write <= live_write;
				show_copy_nz <= live_copy_nz;
				show_color <= live_color;
				live_seen <= 1'sb0;
				live_write <= 1'sb0;
				live_copy_nz <= 1'sb0;
				live_color <= 1'sb0;
			end
			if (px_visible) begin
				live_seen[px_tile] <= 1'b1;
				if (px_write)
					live_write[px_tile] <= 1'b1;
				if (px_copy_nz)
					live_copy_nz[px_tile] <= 1'b1;
				if (px_color)
					live_color[px_tile] <= 1'b1;
			end
		end
	reg [8:0] gx;
	reg [7:0] gy;
	reg de_q;
	always @(posedge clk)
		if (rst) begin
			gx <= 9'd0;
			gy <= 8'd0;
			de_q <= 1'b0;
		end
		else if (ce_pix) begin
			de_q <= g_de;
			if (g_vb) begin
				gx <= 9'd0;
				gy <= 8'd0;
			end
			else if (g_de) begin
				if (!de_q)
					gx <= 9'd0;
				else
					gx <= gx + 9'd1;
			end
			else if (de_q) begin
				gx <= 9'd0;
				if (gy < (V_ACT - 1))
					gy <= gy + 8'd1;
			end
		end
	wire display_page1 = active_row0[8:0] == PAGE1_BASE;
	wire [2:0] show_tile_x = gx[8:6];
	wire [2:0] show_tile_y = gy[7:5];
	wire [6:0] show_tile = {display_page1, show_tile_y, show_tile_x};
	wire tile_seen = show_seen[show_tile];
	wire tile_write = show_write[show_tile];
	wire tile_copy_nz = show_copy_nz[show_tile];
	wire tile_color = show_color[show_tile];
	reg [23:0] class_rgb;
	always @(*) begin
		if (_sv2v_0)
			;
		if (!tile_seen)
			class_rgb = 24'h0060ff;
		else if (!tile_write)
			class_rgb = 24'hff00ff;
		else if (tile_copy_nz)
			class_rgb = 24'h00ff40;
		else if (tile_color)
			class_rgb = 24'hffff00;
		else
			class_rgb = 24'hff2000;
	end
	wire tile_border = (gx[5:0] < 6'd4) || (gy[4:0] < 5'd4);
	wire tile_badge = (gx[5:0] < 6'd14) && (gy[4:0] < 5'd14);
	wire key_bar = (gy < 8'd10) && (gx < 9'd160);
	reg [23:0] key_rgb;
	always @(*) begin
		if (_sv2v_0)
			;
		case (gx[7:5])
			3'd0: key_rgb = 24'h0060ff;
			3'd1: key_rgb = 24'hff00ff;
			3'd2: key_rgb = 24'hff2000;
			3'd3: key_rgb = 24'hffff00;
			default: key_rgb = 24'h00ff40;
		endcase
	end
	wire paint_diag = (enable && g_de) && ((key_bar || tile_border) || tile_badge);
	always @(*) begin
		if (_sv2v_0)
			;
		hsync = g_hs;
		vsync = g_vs;
		hblank = g_hb;
		vblank = g_vb;
		de = g_de;
		if (paint_diag) begin
			vid_r = (key_bar ? key_rgb[23:16] : class_rgb[23:16]);
			vid_g = (key_bar ? key_rgb[15:8] : class_rgb[15:8]);
			vid_b = (key_bar ? key_rgb[7:0] : class_rgb[7:0]);
		end
		else begin
			vid_r = g_r;
			vid_g = g_g;
			vid_b = g_b;
		end
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_game_inputs (
	game_profile,
	joystick_0,
	joystick_1,
	joystick_2,
	joystick_3,
	status,
	in0,
	in1,
	in2,
	dsw
);
	reg _sv2v_0;
	parameter integer PROFILE = 3;
	parameter [0:0] RUNTIME_SELECT = 1'b0;
	input wire [2:0] game_profile;
	input wire [15:0] joystick_0;
	input wire [15:0] joystick_1;
	input wire [15:0] joystick_2;
	input wire [15:0] joystick_3;
	input wire [31:0] status;
	output reg [15:0] in0;
	output reg [15:0] in1;
	output reg [15:0] in2;
	output reg [15:0] dsw;
	localparam [2:0] PROFILE_OPEN_ICE = 3'd0;
	localparam [2:0] PROFILE_WWF = 3'd1;
	localparam [2:0] PROFILE_MK3 = 3'd2;
	localparam [2:0] PROFILE_UMK3 = 3'd3;
	localparam [2:0] PROFILE_NBA = 3'd4;
	localparam [2:0] PROFILE_NBAMAX = 3'd5;
	localparam [2:0] PROFILE_RAMPAGE = 3'd6;
	reg [2:0] active_profile;
	reg [15:0] in2_active;
	reg test_switch;
	reg service_credit;
	reg vol_down;
	reg vol_up;
	always @(*) begin
		if (_sv2v_0)
			;
		active_profile = PROFILE;
		if (RUNTIME_SELECT)
			case (game_profile)
				PROFILE_OPEN_ICE, PROFILE_WWF, PROFILE_MK3, PROFILE_UMK3, PROFILE_NBA, PROFILE_NBAMAX, PROFILE_RAMPAGE: active_profile = game_profile;
				default: active_profile = PROFILE;
			endcase
	end
	always @(*) begin
		if (_sv2v_0)
			;
		in0 = 16'hffff;
		in1 = 16'hffff;
		in2_active = 16'h0000;
		dsw = 16'hffff;
		test_switch = status[8];
		service_credit = status[9];
		vol_down = status[10];
		vol_up = status[11];
		case (active_profile)
			PROFILE_OPEN_ICE: begin
				in0 = ~{1'b0, joystick_1[4], joystick_1[6], joystick_1[5], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3], 1'b0, joystick_0[4], joystick_0[6], joystick_0[5], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]};
				in1 = ~{1'b0, joystick_3[4], joystick_3[6], joystick_3[5], joystick_3[0], joystick_3[1], joystick_3[2], joystick_3[3], 1'b0, joystick_2[4], joystick_2[6], joystick_2[5], joystick_2[0], joystick_2[1], joystick_2[2], joystick_2[3]};
				service_credit = status[9] | (test_switch & joystick_0[7]);
				vol_down = status[10] | (test_switch & joystick_0[2]);
				vol_up = status[11] | (test_switch & joystick_0[3]);
				in2_active = ((((((((((joystick_0[8] ? 16'h0001 : 16'h0000) | (joystick_1[8] ? 16'h0002 : 16'h0000)) | (joystick_0[7] ? 16'h0004 : 16'h0000)) | (joystick_1[7] ? 16'h0020 : 16'h0000)) | (service_credit ? 16'h0040 : 16'h0000)) | (joystick_2[8] ? 16'h0080 : 16'h0000)) | (joystick_3[8] ? 16'h0100 : 16'h0000)) | (joystick_2[7] ? 16'h0200 : 16'h0000)) | (joystick_3[7] ? 16'h0400 : 16'h0000)) | (vol_down ? 16'h0800 : 16'h0000)) | (vol_up ? 16'h1000 : 16'h0000);
				dsw = (status[12] ? 16'hfbbe : 16'hebbe);
				if (test_switch)
					dsw = dsw & ~16'h8000;
			end
			PROFILE_WWF: begin
				in0 = ~{1'b0, joystick_1[6], joystick_1[5], joystick_1[4], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3], 1'b0, joystick_0[6], joystick_0[5], joystick_0[4], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]};
				in1 = ~{10'h000, joystick_1[8], joystick_1[7], 2'b00, joystick_0[8], joystick_0[7]};
				service_credit = status[9] | (test_switch & joystick_0[9]);
				vol_down = status[10] | (test_switch & joystick_0[2]);
				vol_up = status[11] | (test_switch & joystick_0[3]);
				in2_active = ((((((joystick_0[10] ? 16'h0001 : 16'h0000) | (joystick_1[10] ? 16'h0002 : 16'h0000)) | (joystick_0[9] ? 16'h0004 : 16'h0000)) | (joystick_1[9] ? 16'h0020 : 16'h0000)) | (service_credit ? 16'h0040 : 16'h0000)) | (vol_down ? 16'h0800 : 16'h0000)) | (vol_up ? 16'h1000 : 16'h0000);
				dsw = (test_switch ? 16'h7ffc : 16'h7ffd);
			end
			PROFILE_MK3, PROFILE_UMK3: begin
				in0 = ~{1'b0, joystick_1[7], joystick_1[6], joystick_1[4], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3], 1'b0, joystick_0[7], joystick_0[6], joystick_0[4], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]};
				in1 = ~{9'h000, joystick_1[9], joystick_1[8], joystick_1[5], 1'b0, joystick_0[9], joystick_0[8], joystick_0[5]};
				service_credit = status[9] | (test_switch & joystick_0[10]);
				vol_down = status[10] | (test_switch & joystick_0[2]);
				vol_up = status[11] | (test_switch & joystick_0[3]);
				in2_active = ((((((joystick_0[11] ? 16'h0001 : 16'h0000) | (joystick_1[11] ? 16'h0002 : 16'h0000)) | (joystick_0[10] ? 16'h0004 : 16'h0000)) | (joystick_1[10] ? 16'h0020 : 16'h0000)) | (service_credit ? 16'h0040 : 16'h0000)) | (vol_down ? 16'h0800 : 16'h0000)) | (vol_up ? 16'h1000 : 16'h0000);
				dsw = (test_switch ? 16'hfd7c : 16'hfd7d);
			end
			PROFILE_NBA, PROFILE_NBAMAX: begin
				in0 = ~{1'b0, joystick_1[4], joystick_1[6], joystick_1[5], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3], 1'b0, joystick_0[4], joystick_0[6], joystick_0[5], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]};
				in1 = ~{1'b0, joystick_3[4], joystick_3[6], joystick_3[5], joystick_3[0], joystick_3[1], joystick_3[2], joystick_3[3], 1'b0, joystick_2[4], joystick_2[6], joystick_2[5], joystick_2[0], joystick_2[1], joystick_2[2], joystick_2[3]};
				service_credit = status[9] | (test_switch & joystick_0[7]);
				vol_down = status[10] | (test_switch & joystick_0[2]);
				vol_up = status[11] | (test_switch & joystick_0[3]);
				in2_active = ((((((((((joystick_0[8] ? 16'h0001 : 16'h0000) | (joystick_1[8] ? 16'h0002 : 16'h0000)) | (joystick_0[7] ? 16'h0004 : 16'h0000)) | (joystick_1[7] ? 16'h0020 : 16'h0000)) | (service_credit ? 16'h0040 : 16'h0000)) | (joystick_2[8] ? 16'h0080 : 16'h0000)) | (joystick_3[8] ? 16'h0100 : 16'h0000)) | (joystick_2[7] ? 16'h0200 : 16'h0000)) | (joystick_3[7] ? 16'h0400 : 16'h0000)) | (vol_down ? 16'h0800 : 16'h0000)) | (vol_up ? 16'h1000 : 16'h0000);
				dsw = (status[12] ? 16'h7ffd : 16'h7f7d);
				if (test_switch)
					dsw = dsw & ~16'h0001;
			end
			default: begin
				in0 = ~{1'b0, joystick_1[4], joystick_1[6], joystick_1[5], joystick_1[0], joystick_1[1], joystick_1[2], joystick_1[3], 1'b0, joystick_0[4], joystick_0[6], joystick_0[5], joystick_0[0], joystick_0[1], joystick_0[2], joystick_0[3]};
				in1 = ~{9'd0, joystick_2[4], joystick_2[6], joystick_2[5], joystick_2[0], joystick_2[1], joystick_2[2], joystick_2[3]};
				service_credit = status[9] | (test_switch & joystick_0[7]);
				vol_down = status[10] | (test_switch & joystick_0[2]);
				vol_up = status[11] | (test_switch & joystick_0[3]);
				in2_active = ((((((((joystick_0[8] ? 16'h0001 : 16'h0000) | (joystick_1[8] ? 16'h0002 : 16'h0000)) | (joystick_0[7] ? 16'h0004 : 16'h0000)) | (joystick_1[7] ? 16'h0020 : 16'h0000)) | (service_credit ? 16'h0040 : 16'h0000)) | (joystick_2[8] ? 16'h0080 : 16'h0000)) | (joystick_2[7] ? 16'h0200 : 16'h0000)) | (vol_down ? 16'h0800 : 16'h0000)) | (vol_up ? 16'h1000 : 16'h0000);
				dsw = (test_switch ? 16'h7bbe : 16'hfbbe);
			end
		endcase
		in2 = ~in2_active;
	end
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
`default_nettype none
module wolf_gfx_interleave (
	mk3_layout_i,
	lin_addr,
	dest_addr
);
	reg _sv2v_0;
	parameter [0:0] MK3_LAYOUT = 1'b0;
	input wire mk3_layout_i;
	input wire [24:0] lin_addr;
	output wire [24:0] dest_addr;
	wire [4:0] chip_index = lin_addr[24:20];
	wire [19:0] chip_off = lin_addr[19:0];
	wire [2:0] group = chip_index[4:2];
	wire [1:0] lane = chip_index[1:0];
	reg [24:0] group_base;
	always @(*) begin
		if (_sv2v_0)
			;
		case (group)
			3'd0: group_base = 25'h0000000;
			3'd1: group_base = 25'h0400000;
			3'd2: group_base = 25'h0800000;
			3'd3: group_base = 25'h0c00000;
			3'd4: group_base = 25'h1400000;
			default: group_base = 25'h0000000;
		endcase
	end
	wire [20:0] mk3_tail_addr = lin_addr[20:0];
	wire [1:0] mk3_tail_lane = mk3_tail_addr[20:19];
	wire [18:0] mk3_tail_off = mk3_tail_addr[18:0];
	wire [24:0] normal_dest = group_base + {chip_off, lane};
	wire [24:0] mk3_tail_dest = 25'h1000000 + {mk3_tail_off, mk3_tail_lane};
	reg use_mk3_layout;
	always @(*) begin
		if (_sv2v_0)
			;
		use_mk3_layout = MK3_LAYOUT;
		case (mk3_layout_i)
			1'b1: use_mk3_layout = 1'b1;
			default: use_mk3_layout = MK3_LAYOUT;
		endcase
	end
	assign dest_addr = (use_mk3_layout && (lin_addr >= 25'h1000000) ? mk3_tail_dest : normal_dest);
	initial _sv2v_0 = 0;
endmodule
`default_nettype wire
module psram (
	clk,
	bank_sel,
	addr,
	write_en,
	data_in,
	write_high_byte,
	write_low_byte,
	read_en,
	read_avail,
	write_done,
	data_out,
	busy,
	cram_a,
	cram_dq,
	cram_wait,
	cram_clk,
	cram_adv_n,
	cram_cre,
	cram_ce0_n,
	cram_ce1_n,
	cram_oe_n,
	cram_we_n,
	cram_ub_n,
	cram_lb_n
);
	parameter CLOCK_SPEED = 133.12;
	parameter MIN_ADV_N_PULSE = 5;
	parameter MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH = 5;
	parameter MIN_ADDRESS_HOLD_AFTER_ADV_HIGH = 2;
	parameter MIN_CE_BEFORE_ADV_HIGH = 7;
	parameter MIN_DATA_SETUP_BEFORE_WE_HIGH = 20;
	parameter MIN_DATA_AFTER_ADDR_UNLATCHED = 8;
	parameter MIN_WRITE_PULSE = 45;
	parameter MIN_WRITE_TIME_FROM_ADV = 70;
	parameter MIN_OE_AFTER_ADDR_UNLATCHED = 3;
	parameter MAX_ACCESS_TIME_FROM_ADV = 70;
	input wire clk;
	input wire bank_sel;
	input wire [21:0] addr;
	input wire write_en;
	input wire [15:0] data_in;
	input wire write_high_byte;
	input wire write_low_byte;
	input wire read_en;
	output reg read_avail;
	output reg write_done = 0;
	output reg [15:0] data_out;
	output reg busy;
	output reg [21:16] cram_a;
	inout wire [15:0] cram_dq;
	input wire cram_wait;
	output reg cram_clk = 0;
	output reg cram_adv_n = 1;
	output reg cram_cre = 0;
	output reg cram_ce0_n = 1;
	output reg cram_ce1_n = 1;
	output reg cram_oe_n = 1;
	output reg cram_we_n = 1;
	output reg cram_ub_n = 1;
	output reg cram_lb_n = 1;
	localparam PERIOD = 1000.0 / CLOCK_SPEED;
	function integer rtoi;
		input integer x;
		rtoi = x;
	endfunction
	localparam ADV_PULSE_CYCLE_COUNT = (rtoi(MIN_ADV_N_PULSE / PERIOD) > (MIN_ADV_N_PULSE / PERIOD) ? rtoi(MIN_ADV_N_PULSE / PERIOD) : rtoi(MIN_ADV_N_PULSE / PERIOD) + 1);
	localparam ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT = (rtoi((MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH + 2) / PERIOD) > ((MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH + 2) / PERIOD) ? rtoi((MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH + 2) / PERIOD) : rtoi((MIN_ADDRESS_SETUP_BEFORE_ADV_HIGH + 2) / PERIOD) + 1);
	localparam CE_BEFORE_ADV_CYCLE_COUNT = (rtoi(MIN_CE_BEFORE_ADV_HIGH / PERIOD) > (MIN_CE_BEFORE_ADV_HIGH / PERIOD) ? rtoi(MIN_CE_BEFORE_ADV_HIGH / PERIOD) : rtoi(MIN_CE_BEFORE_ADV_HIGH / PERIOD) + 1);
	localparam ADV_CYCLE_COUNT = ((ADV_PULSE_CYCLE_COUNT > ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT ? ADV_PULSE_CYCLE_COUNT : ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT) > CE_BEFORE_ADV_CYCLE_COUNT ? (ADV_PULSE_CYCLE_COUNT > ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT ? ADV_PULSE_CYCLE_COUNT : ADDRESS_SETUP_BEFORE_ADV_CYCLE_COUNT) : CE_BEFORE_ADV_CYCLE_COUNT);
	localparam ADDR_HOLD_AFTER_ADV_CYCLE_COUNT = (rtoi(MIN_ADDRESS_HOLD_AFTER_ADV_HIGH / PERIOD) > (MIN_ADDRESS_HOLD_AFTER_ADV_HIGH / PERIOD) ? rtoi(MIN_ADDRESS_HOLD_AFTER_ADV_HIGH / PERIOD) : rtoi(MIN_ADDRESS_HOLD_AFTER_ADV_HIGH / PERIOD) + 1);
	localparam DATA_SETUP_BEFORE_WE_ENDS_CYCLE_COUNT = (rtoi(MIN_DATA_SETUP_BEFORE_WE_HIGH / PERIOD) > (MIN_DATA_SETUP_BEFORE_WE_HIGH / PERIOD) ? rtoi(MIN_DATA_SETUP_BEFORE_WE_HIGH / PERIOD) : rtoi(MIN_DATA_SETUP_BEFORE_WE_HIGH / PERIOD) + 1);
	localparam DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT = (rtoi(MIN_DATA_AFTER_ADDR_UNLATCHED / PERIOD) > (MIN_DATA_AFTER_ADDR_UNLATCHED / PERIOD) ? rtoi(MIN_DATA_AFTER_ADDR_UNLATCHED / PERIOD) : rtoi(MIN_DATA_AFTER_ADDR_UNLATCHED / PERIOD) + 1);
	localparam WRITE_PULSE_CYCLE_COUNT = (rtoi(MIN_WRITE_PULSE / PERIOD) > (MIN_WRITE_PULSE / PERIOD) ? rtoi(MIN_WRITE_PULSE / PERIOD) : rtoi(MIN_WRITE_PULSE / PERIOD) + 1);
	localparam TOTAL_WRITE_CYCLE_COUNT = (rtoi((MIN_WRITE_TIME_FROM_ADV > MIN_WRITE_PULSE ? MIN_WRITE_TIME_FROM_ADV : MIN_WRITE_PULSE) / PERIOD) > ((MIN_WRITE_TIME_FROM_ADV > MIN_WRITE_PULSE ? MIN_WRITE_TIME_FROM_ADV : MIN_WRITE_PULSE) / PERIOD) ? rtoi((MIN_WRITE_TIME_FROM_ADV > MIN_WRITE_PULSE ? MIN_WRITE_TIME_FROM_ADV : MIN_WRITE_PULSE) / PERIOD) : rtoi((MIN_WRITE_TIME_FROM_ADV > MIN_WRITE_PULSE ? MIN_WRITE_TIME_FROM_ADV : MIN_WRITE_PULSE) / PERIOD) + 1);
	localparam OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT = (rtoi(MIN_OE_AFTER_ADDR_UNLATCHED / PERIOD) > (MIN_OE_AFTER_ADDR_UNLATCHED / PERIOD) ? rtoi(MIN_OE_AFTER_ADDR_UNLATCHED / PERIOD) : rtoi(MIN_OE_AFTER_ADDR_UNLATCHED / PERIOD) + 1);
	localparam TOTAL_READ_CYCLE_COUNT = (rtoi(MAX_ACCESS_TIME_FROM_ADV / PERIOD) > (MAX_ACCESS_TIME_FROM_ADV / PERIOD) ? rtoi(MAX_ACCESS_TIME_FROM_ADV / PERIOD) : rtoi(MAX_ACCESS_TIME_FROM_ADV / PERIOD) + 1);
	localparam STATE_NONE = 0;
	localparam WRITE_INITIAL_COUNT = 1;
	localparam STATE_WRITE_WE_START = WRITE_INITIAL_COUNT;
	localparam STATE_WRITE_ADV_END = WRITE_INITIAL_COUNT + ADV_CYCLE_COUNT;
	localparam STATE_WRITE_ADDR_LATCH_END = STATE_WRITE_ADV_END + ADDR_HOLD_AFTER_ADV_CYCLE_COUNT;
	localparam STATE_WRITE_DATA_START = STATE_WRITE_ADDR_LATCH_END + DATA_AFTER_ADDR_UNLATCH_CYCLE_COUNT;
	localparam STATE_WRITE_DATA_END = WRITE_INITIAL_COUNT + TOTAL_WRITE_CYCLE_COUNT;
	localparam STATE_WRITE_RELEASE = STATE_WRITE_DATA_END + 1;
	localparam READ_INITIAL_COUNT = 20;
	localparam STATE_READ_ADV_END = 19 + ADV_CYCLE_COUNT;
	localparam STATE_READ_ADDR_LATCH_END = STATE_READ_ADV_END + ADDR_HOLD_AFTER_ADV_CYCLE_COUNT;
	localparam STATE_READ_DATA_ENABLE = STATE_READ_ADDR_LATCH_END + OE_AFTER_ADDR_UNLATCH_CYCLE_COUNT;
	localparam STATE_READ_DATA_RECEIVED = READ_INITIAL_COUNT + TOTAL_READ_CYCLE_COUNT;
	localparam STATE_READ_RELEASE = STATE_READ_DATA_RECEIVED + 1;
	reg [7:0] state = STATE_NONE;
	reg data_out_en = 0;
	reg [15:0] cram_data;
	reg [15:0] latched_data_in;
	assign cram_dq = (data_out_en ? cram_data : 16'hzzzz);
	always @(posedge clk) begin
		write_done <= 0;
		if (state != STATE_NONE)
			state <= state + 1;
		if (state == STATE_NONE)
			busy <= 0;
		else
			busy <= 1;
		case (state)
			STATE_NONE: begin
				read_avail <= 0;
				cram_clk <= 0;
				cram_adv_n <= 1;
				cram_cre <= 0;
				cram_ce0_n <= 1;
				cram_ce1_n <= 1;
				cram_oe_n <= 1;
				cram_we_n <= 1;
				cram_ub_n <= 1;
				cram_lb_n <= 1;
				if (write_en) begin
					state <= WRITE_INITIAL_COUNT;
					if (bank_sel)
						cram_ce1_n <= 0;
					else
						cram_ce0_n <= 0;
					cram_a <= addr[21:16];
					cram_data <= addr[15:0];
					data_out_en <= 1;
					latched_data_in <= data_in;
					cram_adv_n <= 0;
					if (write_high_byte)
						cram_ub_n <= 0;
					if (write_low_byte)
						cram_lb_n <= 0;
					busy <= 1;
				end
				else if (read_en) begin
					state <= READ_INITIAL_COUNT;
					if (bank_sel)
						cram_ce1_n <= 0;
					else
						cram_ce0_n <= 0;
					cram_a <= addr[21:16];
					cram_data <= addr[15:0];
					data_out_en <= 1;
					cram_adv_n <= 0;
					cram_ub_n <= 0;
					cram_lb_n <= 0;
					busy <= 1;
				end
			end
			STATE_WRITE_WE_START: cram_we_n <= 0;
			STATE_WRITE_ADV_END: cram_adv_n <= 1;
			STATE_WRITE_ADDR_LATCH_END: data_out_en <= 0;
			STATE_WRITE_DATA_START: begin
				data_out_en <= 1;
				cram_data <= latched_data_in;
			end
			STATE_WRITE_DATA_END: begin
				write_done <= 1;
				cram_we_n <= 1;
				cram_ce0_n <= 1;
				cram_ce1_n <= 1;
				cram_ub_n <= 1;
				cram_lb_n <= 1;
			end
			STATE_WRITE_RELEASE: begin
				state <= STATE_NONE;
				data_out_en <= 0;
				busy <= 0;
			end
			STATE_READ_ADV_END: cram_adv_n <= 1;
			STATE_READ_ADDR_LATCH_END: data_out_en <= 0;
			STATE_READ_DATA_ENABLE: cram_oe_n <= 0;
			STATE_READ_DATA_RECEIVED: begin
				read_avail <= 1;
				data_out <= cram_dq;
			end
			STATE_READ_RELEASE: begin
				state <= STATE_NONE;
				cram_ce0_n <= 1;
				cram_ce1_n <= 1;
				cram_ub_n <= 1;
				cram_lb_n <= 1;
				cram_oe_n <= 1;
				busy <= 0;
			end
		endcase
	end
endmodule
`default_nettype none
module core_top (
	clk_74a,
	clk_74b,
	cart_tran_bank2,
	cart_tran_bank2_dir,
	cart_tran_bank3,
	cart_tran_bank3_dir,
	cart_tran_bank1,
	cart_tran_bank1_dir,
	cart_tran_bank0,
	cart_tran_bank0_dir,
	cart_tran_pin30,
	cart_tran_pin30_dir,
	cart_pin30_pwroff_reset,
	cart_tran_pin31,
	cart_tran_pin31_dir,
	port_ir_rx,
	port_ir_tx,
	port_ir_rx_disable,
	port_tran_si,
	port_tran_si_dir,
	port_tran_so,
	port_tran_so_dir,
	port_tran_sck,
	port_tran_sck_dir,
	port_tran_sd,
	port_tran_sd_dir,
	cram0_a,
	cram0_dq,
	cram0_wait,
	cram0_clk,
	cram0_adv_n,
	cram0_cre,
	cram0_ce0_n,
	cram0_ce1_n,
	cram0_oe_n,
	cram0_we_n,
	cram0_ub_n,
	cram0_lb_n,
	cram1_a,
	cram1_dq,
	cram1_wait,
	cram1_clk,
	cram1_adv_n,
	cram1_cre,
	cram1_ce0_n,
	cram1_ce1_n,
	cram1_oe_n,
	cram1_we_n,
	cram1_ub_n,
	cram1_lb_n,
	dram_a,
	dram_ba,
	dram_dq,
	dram_dqm,
	dram_clk,
	dram_cke,
	dram_ras_n,
	dram_cas_n,
	dram_we_n,
	sram_a,
	sram_dq,
	sram_oe_n,
	sram_we_n,
	sram_ub_n,
	sram_lb_n,
	vblank,
	dbg_tx,
	dbg_rx,
	user1,
	user2,
	aux_sda,
	aux_scl,
	vpll_feed,
	video_rgb,
	video_rgb_clock,
	video_rgb_clock_90,
	video_de,
	video_skip,
	video_vs,
	video_hs,
	audio_mclk,
	audio_adc,
	audio_dac,
	audio_lrck,
	bridge_endian_little,
	bridge_addr,
	bridge_rd,
	bridge_rd_data,
	bridge_wr,
	bridge_wr_data,
	cont1_key,
	cont2_key,
	cont3_key,
	cont4_key,
	cont1_joy,
	cont2_joy,
	cont3_joy,
	cont4_joy,
	cont1_trig,
	cont2_trig,
	cont3_trig,
	cont4_trig
);
	input wire clk_74a;
	input wire clk_74b;
	inout wire [7:0] cart_tran_bank2;
	output wire cart_tran_bank2_dir;
	inout wire [7:0] cart_tran_bank3;
	output wire cart_tran_bank3_dir;
	inout wire [7:0] cart_tran_bank1;
	output wire cart_tran_bank1_dir;
	inout wire [7:4] cart_tran_bank0;
	output wire cart_tran_bank0_dir;
	inout wire cart_tran_pin30;
	output wire cart_tran_pin30_dir;
	output wire cart_pin30_pwroff_reset;
	inout wire cart_tran_pin31;
	output wire cart_tran_pin31_dir;
	input wire port_ir_rx;
	output wire port_ir_tx;
	output wire port_ir_rx_disable;
	inout wire port_tran_si;
	output wire port_tran_si_dir;
	inout wire port_tran_so;
	output wire port_tran_so_dir;
	inout wire port_tran_sck;
	output wire port_tran_sck_dir;
	inout wire port_tran_sd;
	output wire port_tran_sd_dir;
	output wire [21:16] cram0_a;
	inout wire [15:0] cram0_dq;
	input wire cram0_wait;
	output wire cram0_clk;
	output wire cram0_adv_n;
	output wire cram0_cre;
	output wire cram0_ce0_n;
	output wire cram0_ce1_n;
	output wire cram0_oe_n;
	output wire cram0_we_n;
	output wire cram0_ub_n;
	output wire cram0_lb_n;
	output wire [21:16] cram1_a;
	inout wire [15:0] cram1_dq;
	input wire cram1_wait;
	output wire cram1_clk;
	output wire cram1_adv_n;
	output wire cram1_cre;
	output wire cram1_ce0_n;
	output wire cram1_ce1_n;
	output wire cram1_oe_n;
	output wire cram1_we_n;
	output wire cram1_ub_n;
	output wire cram1_lb_n;
	output wire [12:0] dram_a;
	output wire [1:0] dram_ba;
	inout wire [15:0] dram_dq;
	output wire [1:0] dram_dqm;
	output wire dram_clk;
	output wire dram_cke;
	output wire dram_ras_n;
	output wire dram_cas_n;
	output wire dram_we_n;
	output wire [16:0] sram_a;
	inout wire [15:0] sram_dq;
	output wire sram_oe_n;
	output wire sram_we_n;
	output wire sram_ub_n;
	output wire sram_lb_n;
	input wire vblank;
	output wire dbg_tx;
	input wire dbg_rx;
	output wire user1;
	input wire user2;
	inout wire aux_sda;
	output wire aux_scl;
	output wire vpll_feed;
	output wire [23:0] video_rgb;
	output wire video_rgb_clock;
	output wire video_rgb_clock_90;
	output wire video_de;
	output wire video_skip;
	output wire video_vs;
	output wire video_hs;
	output wire audio_mclk;
	input wire audio_adc;
	output wire audio_dac;
	output wire audio_lrck;
	output wire bridge_endian_little;
	input wire [31:0] bridge_addr;
	input wire bridge_rd;
	output reg [31:0] bridge_rd_data;
	input wire bridge_wr;
	input wire [31:0] bridge_wr_data;
	input wire [31:0] cont1_key;
	input wire [31:0] cont2_key;
	input wire [31:0] cont3_key;
	input wire [31:0] cont4_key;
	input wire [31:0] cont1_joy;
	input wire [31:0] cont2_joy;
	input wire [31:0] cont3_joy;
	input wire [31:0] cont4_joy;
	input wire [15:0] cont1_trig;
	input wire [15:0] cont2_trig;
	input wire [15:0] cont3_trig;
	input wire [15:0] cont4_trig;
	assign port_ir_tx = 0;
	assign port_ir_rx_disable = 1;
	assign bridge_endian_little = 0;
	assign cart_tran_bank3 = 8'hzz;
	assign cart_tran_bank3_dir = 1'b0;
	assign cart_tran_bank2 = 8'hzz;
	assign cart_tran_bank2_dir = 1'b0;
	assign cart_tran_bank1 = 8'hzz;
	assign cart_tran_bank1_dir = 1'b0;
	assign cart_tran_bank0 = 4'hf;
	assign cart_tran_bank0_dir = 1'b1;
	assign cart_tran_pin30 = 1'b0;
	assign cart_tran_pin30_dir = 1'bz;
	assign cart_pin30_pwroff_reset = 1'b0;
	assign cart_tran_pin31 = 1'bz;
	assign cart_tran_pin31_dir = 1'b0;
	assign port_tran_so = 1'bz;
	assign port_tran_so_dir = 1'b0;
	assign port_tran_si = 1'bz;
	assign port_tran_si_dir = 1'b0;
	assign port_tran_sck = 1'bz;
	assign port_tran_sck_dir = 1'b0;
	assign port_tran_sd = 1'bz;
	assign port_tran_sd_dir = 1'b0;
	assign sram_a = 'h0;
	assign sram_dq = {16 {1'bz}};
	assign sram_oe_n = 1;
	assign sram_we_n = 1;
	assign sram_ub_n = 1;
	assign sram_lb_n = 1;
	assign dbg_tx = 1'bz;
	assign user1 = 1'bz;
	assign aux_scl = 1'bz;
	assign vpll_feed = 1'bz;
	wire clk_sys;
	wire clk_sdram;
	wire clk_pixel;
	wire clk_pixel_90;
	wire pll_locked;
	wolf_pocket_pll clocks(
		.refclk(clk_74a),
		.clk_sys(clk_sys),
		.clk_sdram(clk_sdram),
		.clk_pixel(clk_pixel),
		.clk_pixel_90(clk_pixel_90),
		.locked(pll_locked)
	);
	(* async_reg = "true" *) reg [2:0] por_mem = 7;
	(* async_reg = "true" *) reg [2:0] por_bridge = 7;
	(* async_reg = "true" *) reg [2:0] por_pixel = 7;
	always @(posedge clk_sys or negedge pll_locked)
		if (!pll_locked)
			por_mem <= 7;
		else
			por_mem <= {por_mem[1:0], 1'b0};
	always @(posedge clk_74a or negedge pll_locked)
		if (!pll_locked)
			por_bridge <= 7;
		else
			por_bridge <= {por_bridge[1:0], 1'b0};
	always @(posedge clk_pixel or negedge pll_locked)
		if (!pll_locked)
			por_pixel <= 7;
		else
			por_pixel <= {por_pixel[1:0], 1'b0};
	wire reset_n;
	wire allcomplete;
	wire loader_done;
	wire loader_fault;
	wire engine_fault;
	wire [31:0] cmd_data;
	wire target_read;
	wire target_ack;
	wire target_done;
	wire [2:0] target_error;
	wire [15:0] target_id;
	wire [31:0] target_offset;
	wire [31:0] target_address;
	wire [31:0] target_length;
	(* async_reg = "true" *) reg run_meta = 0;
	(* async_reg = "true" *) reg run_sync = 0;
	(* async_reg = "true" *) reg lf_meta = 0;
	(* async_reg = "true" *) reg lf_sync = 0;
	(* async_reg = "true" *) reg ef_meta = 0;
	(* async_reg = "true" *) reg ef_sync = 0;
	always @(posedge clk_sys) begin
		run_meta <= reset_n;
		run_sync <= run_meta;
		lf_meta <= loader_fault;
		lf_sync <= lf_meta;
	end
	always @(posedge clk_74a) begin
		ef_meta <= engine_fault;
		ef_sync <= ef_meta;
	end
	always @(*) begin
		bridge_rd_data = 0;
		if (bridge_addr[31:24] == 8'hf8)
			bridge_rd_data = cmd_data;
		else if (bridge_addr == 32'h20000000)
			bridge_rd_data = {29'd0, ef_sync, loader_fault, loader_done};
	end
	core_bridge_cmd commands(
		.clk(clk_74a),
		.reset_n(reset_n),
		.bridge_endian_little(bridge_endian_little),
		.bridge_addr(bridge_addr),
		.bridge_rd(bridge_rd),
		.bridge_rd_data(cmd_data),
		.bridge_wr(bridge_wr),
		.bridge_wr_data(bridge_wr_data),
		.status_boot_done(!por_bridge[2]),
		.status_setup_done(!por_bridge[2]),
		.status_running(((reset_n && loader_done) && !loader_fault) && !ef_sync),
		.dataslot_requestread(),
		.dataslot_requestread_id(),
		.dataslot_requestread_ack(1'b1),
		.dataslot_requestread_ok(1'b0),
		.dataslot_requestwrite(),
		.dataslot_requestwrite_id(),
		.dataslot_requestwrite_size(),
		.dataslot_requestwrite_ack(1'b1),
		.dataslot_requestwrite_ok(1'b1),
		.dataslot_update(),
		.dataslot_update_id(),
		.dataslot_update_size(),
		.dataslot_allcomplete(allcomplete),
		.rtc_epoch_seconds(),
		.rtc_date_bcd(),
		.rtc_time_bcd(),
		.rtc_valid(),
		.savestate_supported(1'b0),
		.savestate_addr(32'd0),
		.savestate_size(32'd0),
		.savestate_maxloadsize(32'd0),
		.savestate_start(),
		.savestate_start_ack(1'b0),
		.savestate_start_busy(1'b0),
		.savestate_start_ok(1'b0),
		.savestate_start_err(1'b0),
		.savestate_load(),
		.savestate_load_ack(1'b0),
		.savestate_load_busy(1'b0),
		.savestate_load_ok(1'b0),
		.savestate_load_err(1'b0),
		.osnotify_inmenu(),
		.target_dataslot_read(target_read),
		.target_dataslot_write(1'b0),
		.target_dataslot_getfile(1'b0),
		.target_dataslot_openfile(1'b0),
		.target_dataslot_ack(target_ack),
		.target_dataslot_done(target_done),
		.target_dataslot_err(target_error),
		.target_dataslot_id(target_id),
		.target_dataslot_slotoffset(target_offset),
		.target_dataslot_bridgeaddr(target_address),
		.target_dataslot_length(target_length),
		.target_buffer_param_struct(32'd0),
		.target_buffer_resp_struct(32'd0),
		.datatable_addr(10'd0),
		.datatable_wren(1'b0),
		.datatable_data(32'd0),
		.datatable_q()
	);
	wire load_active;
	wire load_valid;
	wire load_ready;
	wire writes_idle;
	wire [1:0] load_index;
	wire [24:0] load_addr;
	wire [7:0] load_data;
	wolf_pocket_loader loader(
		.clk_bridge(clk_74a),
		.reset_bridge(por_bridge[2]),
		.clk_mem(clk_sys),
		.reset_mem(por_mem[2]),
		.start(allcomplete),
		.bridge_wr(bridge_wr),
		.bridge_addr(bridge_addr),
		.bridge_wr_data(bridge_wr_data),
		.target_read(target_read),
		.target_id(target_id),
		.target_offset(target_offset),
		.target_address(target_address),
		.target_length(target_length),
		.target_ack(target_ack),
		.target_done(target_done),
		.target_error(target_error),
		.done(loader_done),
		.fault(loader_fault),
		.load_active(load_active),
		.load_valid(load_valid),
		.load_index(load_index),
		.load_addr(load_addr),
		.load_data(load_data),
		.load_ready(load_ready),
		.writes_idle(writes_idle)
	);
	wire ce_pix;
	wolf_pocket_pixel_enable pixel_enable(
		.clk_sys(clk_sys),
		.clk_pixel(clk_pixel),
		.ce_pix(ce_pix)
	);
	wire [7:0] r;
	wire [7:0] g;
	wire [7:0] b;
	wire hs;
	wire vs;
	wire de;
	wire signed [15:0] left;
	wire signed [15:0] right;
	wire [28:0] ddram_addr;
	wire [7:0] ddram_burstcnt;
	wire [7:0] ddram_be;
	wire [63:0] ddram_din;
	wire [63:0] ddram_dout;
	wire ddram_rd;
	wire ddram_we;
	wire ddram_busy;
	wire ddram_dout_ready;
	wire mem_fault;
	wire game_reset = !run_sync || lf_sync;
	wolf_pocket_system system_core(
		.clk(clk_sys),
		.power_reset(por_mem[2]),
		.game_reset(game_reset),
		.ce_pix(ce_pix),
		.cont1_key(cont1_key),
		.cont2_key(cont2_key),
		.cont3_key(cont3_key),
		.cont4_key(cont4_key),
		.status(32'd0),
		.load_active(load_active),
		.load_valid(load_valid),
		.load_index(load_index),
		.load_addr(load_addr),
		.load_data(load_data),
		.load_ready(load_ready),
		.writes_idle(writes_idle),
		.fault(engine_fault),
		.nvram_busy(1'b0),
		.nvram_ext_en(1'b0),
		.nvram_ext_wr(1'b0),
		.nvram_ext_addr(16'd0),
		.nvram_ext_wdata(8'd0),
		.nvram_ext_rdata(),
		.nvram_cpu_write(),
		.vid_r(r),
		.vid_g(g),
		.vid_b(b),
		.hsync(hs),
		.vsync(vs),
		.hblank(),
		.vblank(),
		.de(de),
		.audio_l(left),
		.audio_r(right),
		.pc_dbg(),
		.illegal_dbg(),
		.SDRAM_DQ(dram_dq),
		.SDRAM_A(dram_a),
		.SDRAM_BA(dram_ba),
		.SDRAM_DQML(dram_dqm[0]),
		.SDRAM_DQMH(dram_dqm[1]),
		.SDRAM_nCS(),
		.SDRAM_nRAS(dram_ras_n),
		.SDRAM_nCAS(dram_cas_n),
		.SDRAM_nWE(dram_we_n),
		.SDRAM_CKE(dram_cke),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_be(ddram_be),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready),
		.mem_fault(mem_fault)
	);
	pin_ddio_clk dram_clock(
		.datain_h(1'b1),
		.datain_l(1'b0),
		.outclock(clk_sdram),
		.dataout(dram_clk)
	);
	wolf_pocket_psram psram_backend(
		.clk(clk_sys),
		.reset(por_mem[2]),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_be(ddram_be),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready),
		.fault(mem_fault),
		.cram0_a(cram0_a),
		.cram0_dq(cram0_dq),
		.cram0_wait(cram0_wait),
		.cram0_clk(cram0_clk),
		.cram0_adv_n(cram0_adv_n),
		.cram0_cre(cram0_cre),
		.cram0_ce0_n(cram0_ce0_n),
		.cram0_ce1_n(cram0_ce1_n),
		.cram0_oe_n(cram0_oe_n),
		.cram0_we_n(cram0_we_n),
		.cram0_ub_n(cram0_ub_n),
		.cram0_lb_n(cram0_lb_n),
		.cram1_a(cram1_a),
		.cram1_dq(cram1_dq),
		.cram1_wait(cram1_wait),
		.cram1_clk(cram1_clk),
		.cram1_adv_n(cram1_adv_n),
		.cram1_cre(cram1_cre),
		.cram1_ce0_n(cram1_ce0_n),
		.cram1_ce1_n(cram1_ce1_n),
		.cram1_oe_n(cram1_oe_n),
		.cram1_we_n(cram1_we_n),
		.cram1_ub_n(cram1_ub_n),
		.cram1_lb_n(cram1_lb_n)
	);
	assign video_rgb_clock = clk_pixel;
	assign video_rgb_clock_90 = clk_pixel_90;
	assign video_skip = 0;
	wolf_pocket_video video(
		.clk_pixel(clk_pixel),
		.reset(por_pixel[2]),
		.r(r),
		.g(g),
		.b(b),
		.hs(hs),
		.vs(vs),
		.de(de),
		.rgb(video_rgb),
		.apf_hs(video_hs),
		.apf_vs(video_vs),
		.apf_de(video_de)
	);
	wolf_pocket_audio sound(
		.clk_bridge(clk_74a),
		.reset_bridge(por_bridge[2]),
		.clk_mem(clk_sys),
		.reset_mem(por_mem[2]),
		.left((game_reset || load_active ? 16'sd0 : left)),
		.right((game_reset || load_active ? 16'sd0 : right)),
		.mclk(audio_mclk),
		.lrck(audio_lrck),
		.dac(audio_dac)
	);
endmodule
`default_nettype wire
`default_nettype none
module wolf_pocket_audio (
	clk_bridge,
	reset_bridge,
	clk_mem,
	reset_mem,
	left,
	right,
	mclk,
	lrck,
	dac
);
	input wire clk_bridge;
	input wire reset_bridge;
	input wire clk_mem;
	input wire reset_mem;
	input wire signed [15:0] left;
	input wire signed [15:0] right;
	output reg mclk = 0;
	output reg lrck = 0;
	output reg dac = 0;
	reg [31:0] held = 0;
	reg [31:0] sample_pair = 0;
	reg request = 0;
	reg ack = 0;
	(* async_reg = "true" *) reg ack_meta = 0;
	(* async_reg = "true" *) reg ack_sync = 0;
	(* async_reg = "true" *) reg req_meta = 0;
	(* async_reg = "true" *) reg req_sync = 0;
	always @(posedge clk_mem) begin
		ack_meta <= ack;
		ack_sync <= ack_meta;
		if (reset_mem) begin
			held <= 0;
			request <= 0;
			ack_meta <= 0;
			ack_sync <= 0;
		end
		else if (ack_sync == request) begin
			held <= {left, right};
			request <= ~request;
		end
	end
	reg [20:0] accum = 0;
	wire [21:0] next_accum = {1'b0, accum} + 22'd245760;
	reg [1:0] divider = 0;
	reg [5:0] serial_count = 0;
	reg [31:0] frame_samples = 0;
	function automatic [20:0] sv2v_cast_21;
		input reg [20:0] inp;
		sv2v_cast_21 = inp;
	endfunction
	always @(posedge clk_bridge) begin
		req_meta <= request;
		req_sync <= req_meta;
		if (req_sync != ack) begin
			sample_pair <= held;
			ack <= req_sync;
		end
		if (next_accum >= 22'd742500) begin
			accum <= sv2v_cast_21(next_accum - 22'd742500);
			mclk <= ~mclk;
			if (!mclk) begin
				divider <= divider + 1'b1;
				if (divider == 3) begin
					serial_count <= serial_count + 1'b1;
					dac <= 0;
					if (serial_count == 0) begin
						lrck <= 0;
						frame_samples <= sample_pair;
					end
					else if (serial_count <= 16)
						dac <= frame_samples[32 - serial_count];
					else if (serial_count == 32)
						lrck <= 1;
					else if ((serial_count <= 48) && (serial_count > 32))
						dac <= frame_samples[48 - serial_count];
				end
			end
		end
		else
			accum <= next_accum[20:0];
		if (reset_bridge) begin
			req_meta <= 0;
			req_sync <= 0;
			ack <= 0;
			sample_pair <= 0;
			accum <= 0;
			mclk <= 0;
			divider <= 0;
			serial_count <= 0;
			frame_samples <= 0;
			lrck <= 0;
			dac <= 0;
		end
	end
endmodule
`default_nettype wire
`default_nettype none
module wolf_pocket_inputs (
	clk,
	reset,
	cont1_key,
	cont2_key,
	cont3_key,
	cont4_key,
	status,
	inputs
);
	input wire clk;
	input wire reset;
	input wire [31:0] cont1_key;
	input wire [31:0] cont2_key;
	input wire [31:0] cont3_key;
	input wire [31:0] cont4_key;
	input wire [31:0] status;
	output wire [63:0] inputs;
	reg [127:0] keys_meta;
	reg [127:0] keys;
	always @(posedge clk)
		if (reset) begin
			keys_meta <= 0;
			keys <= 0;
		end
		else begin
			keys_meta <= {cont4_key, cont3_key, cont2_key, cont1_key};
			keys <= keys_meta;
		end
	function automatic [15:0] joystick;
		input [31:0] key;
		joystick = {7'd0, key[14], key[15], key[6], key[5], key[4], key[0], key[1], key[2], key[3]};
	endfunction
	wolf_game_inputs #(
		.PROFILE(0),
		.RUNTIME_SELECT(1'b0)
	) harness(
		.game_profile(3'd0),
		.status(status),
		.joystick_0(joystick(keys[31:0])),
		.joystick_1(joystick(keys[63:32])),
		.joystick_2(joystick(keys[95:64])),
		.joystick_3(joystick(keys[127:96])),
		.in0(inputs[15:0]),
		.in1(inputs[31:16]),
		.in2(inputs[47:32]),
		.dsw(inputs[63:48])
	);
endmodule
`default_nettype wire
`default_nettype none
module wolf_pocket_loader (
	clk_bridge,
	reset_bridge,
	clk_mem,
	reset_mem,
	start,
	bridge_wr,
	bridge_addr,
	bridge_wr_data,
	target_read,
	target_id,
	target_offset,
	target_address,
	target_length,
	target_ack,
	target_done,
	target_error,
	done,
	fault,
	load_active,
	load_valid,
	load_index,
	load_addr,
	load_data,
	load_ready,
	writes_idle
);
	parameter integer CHUNK_BYTES = 1024;
	parameter integer PROGRAM_BYTES = 1048576;
	parameter integer GRAPHICS_BYTES = 16777216;
	parameter integer SOUND_BYTES = 4194304;
	input wire clk_bridge;
	input wire reset_bridge;
	input wire clk_mem;
	input wire reset_mem;
	input wire start;
	input wire bridge_wr;
	input wire [31:0] bridge_addr;
	input wire [31:0] bridge_wr_data;
	output reg target_read = 0;
	output wire [15:0] target_id;
	output wire [31:0] target_offset;
	output wire [31:0] target_address;
	output wire [31:0] target_length;
	input wire target_ack;
	input wire target_done;
	input wire [2:0] target_error;
	output reg done = 0;
	output reg fault = 0;
	output wire load_active;
	output wire load_valid;
	output reg [1:0] load_index = 0;
	output reg [24:0] load_addr = 0;
	output wire [7:0] load_data;
	input wire load_ready;
	input wire writes_idle;
	localparam integer WORDS = CHUNK_BYTES / 4;
	localparam integer AW = $clog2(WORDS);
	localparam [3:0] WAIT_START = 0;
	localparam [3:0] ISSUE = 1;
	localparam [3:0] ARM = 2;
	localparam [3:0] RECEIVE = 3;
	localparam [3:0] DRAIN = 4;
	localparam [3:0] ADVANCE = 5;
	localparam [3:0] FINISHED = 6;
	localparam [3:0] FAILED = 7;
	reg [3:0] state = WAIT_START;
	reg [1:0] slot = 0;
	reg [31:0] offset = 0;
	reg [31:0] received = 0;
	wire [31:0] slot_size = (slot == 0 ? PROGRAM_BYTES : (slot == 1 ? GRAPHICS_BYTES : SOUND_BYTES));
	(* ramstyle = "M10K, no_rw_check" *) reg [31:0] buffer [0:WORDS - 1];
	reg prev_wr = 0;
	reg request_toggle = 0;
	reg ack_toggle = 0;
	(* async_reg = "true" *) reg ack_meta = 0;
	(* async_reg = "true" *) reg ack_sync = 0;
	wire payload_write = (bridge_wr && !prev_wr) && (bridge_addr[31:28] == 4'h1);
	assign target_id = {14'd0, slot};
	assign target_offset = offset;
	assign target_address = 32'h10000000;
	assign target_length = CHUNK_BYTES;
	always @(posedge clk_bridge) begin
		ack_meta <= ack_toggle;
		ack_sync <= ack_meta;
		prev_wr <= bridge_wr;
		target_read <= 0;
		if (reset_bridge) begin
			state <= WAIT_START;
			slot <= 0;
			offset <= 0;
			received <= 0;
			done <= 0;
			fault <= 0;
			request_toggle <= 0;
			prev_wr <= 0;
			ack_meta <= 0;
			ack_sync <= 0;
		end
		else begin
			case (state)
				WAIT_START:
					if (start)
						state <= ISSUE;
				ISSUE: begin
					received <= 0;
					target_read <= 1;
					state <= ARM;
				end
				ARM:
					if (!target_done || target_ack)
						state <= RECEIVE;
				RECEIVE:
					if (target_done) begin
						if ((target_error != 0) || (received != CHUNK_BYTES)) begin
							fault <= 1;
							state <= FAILED;
						end
						else begin
							request_toggle <= ~request_toggle;
							state <= DRAIN;
						end
					end
				DRAIN:
					if (ack_sync == request_toggle)
						state <= ADVANCE;
				ADVANCE:
					if ((offset + CHUNK_BYTES) == slot_size) begin
						offset <= 0;
						if (slot == 2) begin
							done <= 1;
							state <= FINISHED;
						end
						else begin
							slot <= slot + 1'b1;
							state <= ISSUE;
						end
					end
					else begin
						offset <= offset + CHUNK_BYTES;
						state <= ISSUE;
					end
				default:
					;
			endcase
			if (payload_write) begin
				if ((((state != ARM) && (state != RECEIVE)) || (bridge_addr != (32'h10000000 + received))) || (received >= CHUNK_BYTES)) begin
					fault <= 1;
					done <= 0;
					state <= FAILED;
				end
				else begin
					buffer[received[AW + 1:2]] <= bridge_wr_data;
					received <= received + 4;
				end
			end
		end
	end
	(* async_reg = "true" *) reg req_meta = 0;
	(* async_reg = "true" *) reg req_sync = 0;
	(* async_reg = "true" *) reg done_meta = 0;
	(* async_reg = "true" *) reg done_sync = 0;
	localparam [2:0] M_IDLE = 0;
	localparam [2:0] M_FETCH = 1;
	localparam [2:0] M_BYTE = 2;
	localparam [2:0] M_DRAIN = 3;
	reg [2:0] mem_state = M_IDLE;
	reg [AW - 1:0] word_index = 0;
	reg [1:0] lane = 0;
	reg [31:0] read_word = 0;
	always @(posedge clk_mem) read_word <= buffer[word_index];
	assign load_active = !done_sync;
	assign load_valid = (mem_state == M_BYTE) && !reset_mem;
	assign load_data = read_word[31 - (8 * lane)-:8];
	function automatic signed [AW - 1:0] sv2v_cast_DE851_signed;
		input reg signed [AW - 1:0] inp;
		sv2v_cast_DE851_signed = inp;
	endfunction
	always @(posedge clk_mem) begin
		req_meta <= request_toggle;
		req_sync <= req_meta;
		done_meta <= done;
		done_sync <= done_meta;
		if (reset_mem) begin
			req_meta <= 0;
			req_sync <= 0;
			done_meta <= 0;
			done_sync <= 0;
			ack_toggle <= 0;
			mem_state <= M_IDLE;
			word_index <= 0;
			lane <= 0;
			load_index <= 0;
			load_addr <= 0;
		end
		else
			case (mem_state)
				M_IDLE:
					if (req_sync != ack_toggle) begin
						load_index <= slot;
						load_addr <= offset[24:0];
						word_index <= 0;
						lane <= 0;
						mem_state <= M_FETCH;
					end
				M_FETCH: mem_state <= M_BYTE;
				M_BYTE:
					if (load_ready) begin
						load_addr <= load_addr + 1'b1;
						if (lane == 3) begin
							lane <= 0;
							if (word_index == sv2v_cast_DE851_signed(WORDS - 1))
								mem_state <= M_DRAIN;
							else begin
								word_index <= word_index + 1'b1;
								mem_state <= M_FETCH;
							end
						end
						else
							lane <= lane + 1'b1;
					end
				M_DRAIN:
					if (writes_idle) begin
						ack_toggle <= req_sync;
						mem_state <= M_IDLE;
					end
				default: mem_state <= M_IDLE;
			endcase
	end
	initial if (((((CHUNK_BYTES < 8) || ((CHUNK_BYTES & (CHUNK_BYTES - 1)) != 0)) || ((PROGRAM_BYTES % CHUNK_BYTES) != 0)) || ((GRAPHICS_BYTES % CHUNK_BYTES) != 0)) || ((SOUND_BYTES % CHUNK_BYTES) != 0))
		$display("Error [%0t] src/rtl/wolf_pocket_loader.sv:137:13 - wolf_pocket_loader.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Chunk must be a power of two >=8 dividing all three ROM sizes");
endmodule
`default_nettype wire
module wolf_pocket_memory (
	clk,
	reset,
	ddram_addr,
	ddram_burstcnt,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_be,
	ddram_busy,
	ddram_dout,
	ddram_dout_ready,
	fault,
	mem_req,
	mem_chip,
	mem_writing,
	mem_address,
	mem_length,
	mem_wdata,
	mem_be,
	mem_ready,
	mem_done,
	mem_rvalid,
	mem_rdata,
	mem_windex
);
	input wire clk;
	input wire reset;
	input wire [28:0] ddram_addr;
	input wire [7:0] ddram_burstcnt;
	input wire ddram_rd;
	input wire ddram_we;
	input wire [63:0] ddram_din;
	input wire [7:0] ddram_be;
	output wire ddram_busy;
	output reg [63:0] ddram_dout = 0;
	output reg ddram_dout_ready = 0;
	output reg fault = 0;
	output wire mem_req;
	output reg mem_chip;
	output wire mem_writing;
	output reg [22:0] mem_address;
	output reg [5:0] mem_length;
	output wire [15:0] mem_wdata;
	output wire [1:0] mem_be;
	input wire mem_ready;
	input wire mem_done;
	input wire mem_rvalid;
	input wire [15:0] mem_rdata;
	input wire [4:0] mem_windex;
	localparam IDLE = 0;
	localparam PREP = 1;
	localparam WAIT_DONE = 2;
	localparam WRITE_NEXT = 3;
	localparam FAILED = 4;
	localparam COLLECT = 5;
	reg [2:0] state = IDLE;
	reg writing = 0;
	reg [30:0] ptr = 0;
	reg [9:0] read_left = 0;
	reg [7:0] beat_left = 0;
	reg [5:0] write_left = 0;
	reg [3:0] batch_beats = 0;
	reg [3:0] collected = 0;
	reg [5:0] write_cursor = 0;
	reg [63:0] write_buffer [0:7];
	reg [7:0] mask_buffer [0:7];
	wire [3:0] until_boundary = 4'd8 - {1'b0, ptr[4:2]};
	wire [3:0] next_batch = (beat_left < {4'd0, until_boundary} ? beat_left[3:0] : until_boundary);
	reg [63:0] assembly = 0;
	reg [5:0] active_len = 0;
	reg mapped;
	reg zero_fill;
	reg [15:0] shadows [0:3];
	wire shadow_access = &mem_address[21:0];
	wire [1:0] shadow_index = {mem_chip, mem_address[22]};
	wire [28:0] beat_addr = ptr[30:2];
	wire [4:0] write_lane = mem_windex;
	wire [63:0] selected_data = write_buffer[write_lane[4:2]];
	wire [7:0] selected_mask = mask_buffer[write_lane[4:2]];
	wire [63:0] shadow_data = write_buffer[write_cursor[4:2]];
	wire [7:0] shadow_mask = mask_buffer[write_cursor[4:2]];
	assign mem_wdata = selected_data[write_lane[1:0] * 16+:16];
	assign mem_be = selected_mask[write_lane[1:0] * 2+:2];
	assign mem_writing = writing;
	assign mem_req = ((((!reset && (state == PREP)) && mapped) && !zero_fill) && !shadow_access) && (writing ? write_left != 0 : read_left != 0);
	assign ddram_busy = (reset || (((state != IDLE) && (state != WRITE_NEXT)) && (state != COLLECT))) || ((state == IDLE) && !mem_ready);
	wire [5:0] normal_row_words = 6'd32 - {1'b0, mem_address[4:0]};
	(* keep *) wire request_shorter_than_row = (writing ? write_left < normal_row_words : read_left < {4'd0, normal_row_words});
	always @(*) begin
		mapped = 1;
		zero_fill = 0;
		mem_chip = 0;
		mem_address = 0;
		if ((beat_addr >= 29'h06800000) && (beat_addr < 29'h06a00000))
			mem_address = {beat_addr[20:0], ptr[1:0]};
		else if ((beat_addr >= 29'h06a00000) && (beat_addr < 29'h06c00000)) begin
			zero_fill = !writing;
			mapped = !writing;
		end
		else if ((beat_addr >= 29'h06400000) && (beat_addr < 29'h06420000)) begin
			mem_chip = 1;
			mem_address = {4'd0, beat_addr[16:0], ptr[1:0]};
		end
		else if ((beat_addr >= 29'h06c00000) && (beat_addr < 29'h06c80000)) begin
			mem_chip = 1;
			mem_address = 23'h200000 + {2'd0, beat_addr[18:0], ptr[1:0]};
		end
		else
			mapped = 0;
		if (request_shorter_than_row)
			mem_length = (writing ? write_left : read_left[5:0]);
		else if (mem_address[21:5] == 17'h1ffff)
			mem_length = {1'b0, ~mem_address[4:0]};
		else
			mem_length = normal_row_words;
	end
	task receive;
		input [15:0] value;
		begin
			assembly[ptr[1:0] * 16+:16] <= value;
			if (ptr[1:0] == 3) begin
				ddram_dout <= {value, assembly[47:0]};
				ddram_dout_ready <= 1;
			end
			ptr <= ptr + 1'b1;
			read_left <= read_left - 1'b1;
		end
	endtask
	always @(posedge clk) begin
		ddram_dout_ready <= 0;
		if (reset) begin
			state <= IDLE;
			writing <= 0;
			ptr <= 0;
			read_left <= 0;
			beat_left <= 0;
			write_left <= 0;
			write_cursor <= 0;
			batch_beats <= 0;
			collected <= 0;
			fault <= 0;
			ddram_dout <= 0;
			assembly <= 0;
		end
		else
			case (state)
				IDLE:
					if (!ddram_busy && (ddram_rd || ddram_we)) begin
						if (ddram_rd && ddram_we) begin
							fault <= 1;
							state <= FAILED;
						end
						else begin
							ptr <= {ddram_addr, 2'b00};
							writing <= ddram_we;
							beat_left <= (ddram_burstcnt == 0 ? 8'd1 : ddram_burstcnt);
							read_left <= (ddram_burstcnt == 0 ? 10'd4 : {ddram_burstcnt, 2'b00});
							write_buffer[0] <= ddram_din;
							mask_buffer[0] <= ddram_be;
							collected <= 1;
							write_cursor <= 0;
							if (ddram_burstcnt == 0) begin
								batch_beats <= 1;
								write_left <= 4;
								state <= PREP;
							end
							else if (ddram_burstcnt < (8 - {5'd0, ddram_addr[2:0]})) begin
								batch_beats <= ddram_burstcnt[3:0];
								write_left <= {ddram_burstcnt[3:0], 2'b00};
								state <= (ddram_we && (ddram_burstcnt > 1) ? COLLECT : PREP);
							end
							else begin
								batch_beats <= 4'd8 - {1'b0, ddram_addr[2:0]};
								write_left <= {4'd8 - {1'b0, ddram_addr[2:0]}, 2'b00};
								state <= (ddram_we && (ddram_addr[2:0] != 7) ? COLLECT : PREP);
							end
						end
					end
				PREP:
					if (writing && (write_left == 0)) begin
						if (beat_left == {4'd0, batch_beats})
							state <= IDLE;
						else begin
							beat_left <= beat_left - {4'd0, batch_beats};
							state <= WRITE_NEXT;
						end
					end
					else if (!writing && (read_left == 0))
						state <= IDLE;
					else if (!mapped) begin
						fault <= 1;
						state <= FAILED;
					end
					else if (zero_fill || shadow_access) begin
						if (writing) begin
							if (shadow_mask[write_cursor[1:0] * 2])
								shadows[shadow_index][7:0] <= shadow_data[write_cursor[1:0] * 16+:8];
							if (shadow_mask[(write_cursor[1:0] * 2) + 1])
								shadows[shadow_index][15:8] <= shadow_data[(write_cursor[1:0] * 16) + 8+:8];
							ptr <= ptr + 1'b1;
							write_left <= write_left - 1'b1;
							write_cursor <= write_cursor + 1'b1;
						end
						else
							receive((zero_fill ? 16'd0 : shadows[shadow_index]));
					end
					else if (mem_ready) begin
						active_len <= mem_length;
						state <= WAIT_DONE;
					end
				WAIT_DONE: begin
					if (mem_rvalid && !writing)
						receive(mem_rdata);
					if (mem_done) begin
						if (writing) begin
							ptr <= ptr + active_len;
							write_left <= write_left - active_len;
							write_cursor <= write_cursor + active_len;
						end
						state <= PREP;
					end
				end
				WRITE_NEXT:
					if (ddram_we) begin
						write_buffer[0] <= ddram_din;
						mask_buffer[0] <= ddram_be;
						collected <= 1;
						write_cursor <= 0;
						batch_beats <= next_batch;
						write_left <= {next_batch, 2'b00};
						state <= (next_batch > 1 ? COLLECT : PREP);
					end
				COLLECT:
					if (ddram_we) begin
						write_buffer[collected[2:0]] <= ddram_din;
						mask_buffer[collected[2:0]] <= ddram_be;
						collected <= collected + 1'b1;
						if ((collected + 1'b1) == batch_beats)
							state <= PREP;
					end
				default: state <= FAILED;
			endcase
	end
endmodule
module wolf_pocket_psram (
	clk,
	reset,
	ddram_addr,
	ddram_burstcnt,
	ddram_be,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_busy,
	ddram_dout_ready,
	fault,
	ddram_dout,
	cram0_a,
	cram1_a,
	cram0_dq,
	cram1_dq,
	cram0_wait,
	cram1_wait,
	cram0_clk,
	cram0_adv_n,
	cram0_cre,
	cram0_ce0_n,
	cram0_ce1_n,
	cram0_oe_n,
	cram0_we_n,
	cram0_ub_n,
	cram0_lb_n,
	cram1_clk,
	cram1_adv_n,
	cram1_cre,
	cram1_ce0_n,
	cram1_ce1_n,
	cram1_oe_n,
	cram1_we_n,
	cram1_ub_n,
	cram1_lb_n
);
	parameter integer POWER_CYCLES = 12000;
	input wire clk;
	input wire reset;
	input wire [28:0] ddram_addr;
	input wire [7:0] ddram_burstcnt;
	input wire [7:0] ddram_be;
	input wire ddram_rd;
	input wire ddram_we;
	input wire [63:0] ddram_din;
	output wire ddram_busy;
	output wire ddram_dout_ready;
	output wire fault;
	output wire [63:0] ddram_dout;
	output wire [21:16] cram0_a;
	output wire [21:16] cram1_a;
	inout wire [15:0] cram0_dq;
	inout wire [15:0] cram1_dq;
	input wire cram0_wait;
	input wire cram1_wait;
	output wire cram0_clk;
	output wire cram0_adv_n;
	output wire cram0_cre;
	output wire cram0_ce0_n;
	output wire cram0_ce1_n;
	output wire cram0_oe_n;
	output wire cram0_we_n;
	output wire cram0_ub_n;
	output wire cram0_lb_n;
	output wire cram1_clk;
	output wire cram1_adv_n;
	output wire cram1_cre;
	output wire cram1_ce0_n;
	output wire cram1_ce1_n;
	output wire cram1_oe_n;
	output wire cram1_we_n;
	output wire cram1_ub_n;
	output wire cram1_lb_n;
	wire mem_req;
	wire mem_chip;
	wire mem_writing;
	wire mem_ready;
	wire mem_done;
	wire mem_rvalid;
	wire [22:0] mem_address;
	wire [5:0] mem_length;
	wire [15:0] mem_wdata;
	wire [15:0] mem_rdata;
	wire [1:0] mem_be;
	wire [4:0] mem_windex;
	wire [3:0] configured;
	wolf_pocket_memory bridge(
		.clk(clk),
		.reset(reset),
		.ddram_addr(ddram_addr),
		.ddram_burstcnt(ddram_burstcnt),
		.ddram_rd(ddram_rd),
		.ddram_we(ddram_we),
		.ddram_din(ddram_din),
		.ddram_be(ddram_be),
		.ddram_busy(ddram_busy),
		.ddram_dout(ddram_dout),
		.ddram_dout_ready(ddram_dout_ready),
		.fault(fault),
		.mem_req(mem_req),
		.mem_chip(mem_chip),
		.mem_writing(mem_writing),
		.mem_address(mem_address),
		.mem_length(mem_length),
		.mem_wdata(mem_wdata),
		.mem_be(mem_be),
		.mem_ready(mem_ready),
		.mem_done(mem_done),
		.mem_rvalid(mem_rvalid),
		.mem_rdata(mem_rdata),
		.mem_windex(mem_windex)
	);
	wolf_pocket_psram40 #(.POWER_CYCLES(POWER_CYCLES)) physical(
		.clk(clk),
		.reset(reset),
		.req(mem_req),
		.chip(mem_chip),
		.writing(mem_writing),
		.address(mem_address),
		.length(mem_length),
		.wdata(mem_wdata),
		.wbe(mem_be),
		.ready(mem_ready),
		.done(mem_done),
		.rvalid(mem_rvalid),
		.rdata(mem_rdata),
		.windex(mem_windex),
		.configured(configured),
		.cram0_a(cram0_a),
		.cram1_a(cram1_a),
		.cram0_dq(cram0_dq),
		.cram1_dq(cram1_dq),
		.cram0_wait(cram0_wait),
		.cram1_wait(cram1_wait),
		.cram0_clk(cram0_clk),
		.cram0_adv_n(cram0_adv_n),
		.cram0_cre(cram0_cre),
		.cram0_ce0_n(cram0_ce0_n),
		.cram0_ce1_n(cram0_ce1_n),
		.cram0_oe_n(cram0_oe_n),
		.cram0_we_n(cram0_we_n),
		.cram0_ub_n(cram0_ub_n),
		.cram0_lb_n(cram0_lb_n),
		.cram1_clk(cram1_clk),
		.cram1_adv_n(cram1_adv_n),
		.cram1_cre(cram1_cre),
		.cram1_ce0_n(cram1_ce0_n),
		.cram1_ce1_n(cram1_ce1_n),
		.cram1_oe_n(cram1_oe_n),
		.cram1_we_n(cram1_we_n),
		.cram1_ub_n(cram1_ub_n),
		.cram1_lb_n(cram1_lb_n)
	);
endmodule
`default_nettype none
module wolf_pocket_system (
	clk,
	power_reset,
	game_reset,
	ce_pix,
	cont1_key,
	cont2_key,
	cont3_key,
	cont4_key,
	status,
	load_active,
	load_valid,
	load_index,
	load_addr,
	load_data,
	load_ready,
	writes_idle,
	fault,
	nvram_busy,
	nvram_ext_en,
	nvram_ext_wr,
	nvram_ext_addr,
	nvram_ext_wdata,
	nvram_ext_rdata,
	nvram_cpu_write,
	vid_r,
	vid_g,
	vid_b,
	hsync,
	vsync,
	hblank,
	vblank,
	de,
	audio_l,
	audio_r,
	pc_dbg,
	illegal_dbg,
	SDRAM_DQ,
	SDRAM_A,
	SDRAM_BA,
	SDRAM_DQML,
	SDRAM_DQMH,
	SDRAM_nCS,
	SDRAM_nRAS,
	SDRAM_nCAS,
	SDRAM_nWE,
	SDRAM_CKE,
	ddram_addr,
	ddram_burstcnt,
	ddram_be,
	ddram_rd,
	ddram_we,
	ddram_din,
	ddram_busy,
	ddram_dout_ready,
	mem_fault,
	ddram_dout
);
	input wire clk;
	input wire power_reset;
	input wire game_reset;
	input wire ce_pix;
	input wire [31:0] cont1_key;
	input wire [31:0] cont2_key;
	input wire [31:0] cont3_key;
	input wire [31:0] cont4_key;
	input wire [31:0] status;
	input wire load_active;
	input wire load_valid;
	input wire [1:0] load_index;
	input wire [24:0] load_addr;
	input wire [7:0] load_data;
	output wire load_ready;
	output wire writes_idle;
	output wire fault;
	input wire nvram_busy;
	input wire nvram_ext_en;
	input wire nvram_ext_wr;
	input wire [15:0] nvram_ext_addr;
	input wire [7:0] nvram_ext_wdata;
	output wire [7:0] nvram_ext_rdata;
	output wire nvram_cpu_write;
	output wire [7:0] vid_r;
	output wire [7:0] vid_g;
	output wire [7:0] vid_b;
	output wire hsync;
	output wire vsync;
	output wire hblank;
	output wire vblank;
	output wire de;
	output wire signed [15:0] audio_l;
	output wire signed [15:0] audio_r;
	output wire [31:0] pc_dbg;
	output wire illegal_dbg;
	inout wire [15:0] SDRAM_DQ;
	output wire [12:0] SDRAM_A;
	output wire [1:0] SDRAM_BA;
	output wire SDRAM_DQML;
	output wire SDRAM_DQMH;
	output wire SDRAM_nCS;
	output wire SDRAM_nRAS;
	output wire SDRAM_nCAS;
	output wire SDRAM_nWE;
	output wire SDRAM_CKE;
	output wire [28:0] ddram_addr;
	output wire [7:0] ddram_burstcnt;
	output wire [7:0] ddram_be;
	output wire ddram_rd;
	output wire ddram_we;
	output wire [63:0] ddram_din;
	input wire ddram_busy;
	input wire ddram_dout_ready;
	input wire mem_fault;
	input wire [63:0] ddram_dout;
	wire [63:0] inputs;
	wolf_pocket_inputs controls(
		.clk(clk),
		.reset(power_reset),
		.cont1_key(cont1_key),
		.cont2_key(cont2_key),
		.cont3_key(cont3_key),
		.cont4_key(cont4_key),
		.status(status),
		.inputs(inputs)
	);
	wire prog_wait;
	wire gfx_ack;
	wire gfx_idle;
	wire dcs_ack;
	wire engine_writes_idle;
	reg load_fault = 0;
	wire valid_range = (load_index == 0 ? load_addr < 25'h0100000 : (load_index == 1 ? load_addr < 25'h1000000 : (load_index == 2 ? load_addr < 25'h0400000 : (load_addr == 0) && (load_data == 0))));
	always @(posedge clk)
		if (power_reset)
			load_fault <= 0;
		else if (load_valid && (!load_active || !valid_range))
			load_fault <= 1;
	assign fault = load_fault | mem_fault;
	wire valid_byte = (((load_active && load_valid) && valid_range) && !fault) && !power_reset;
	assign load_ready = (((load_active && valid_range) && !fault) && !power_reset) && (load_index == 0 ? !prog_wait : (load_index == 1 ? gfx_ack : (load_index == 2 ? dcs_ack : 1'b1)));
	wire [24:0] prog_addr = 25'h00c0000 + {6'd0, load_addr[18:0]};
	wire [15:0] prog_data = (load_addr[19] ? {load_data, 8'd0} : {8'd0, load_data});
	wire [1:0] prog_be = (load_addr[19] ? 2'b10 : 2'b01);
	wire [24:0] gfx_addr;
	wolf_gfx_interleave interleave(
		.mk3_layout_i(1'b0),
		.lin_addr(load_addr),
		.dest_addr(gfx_addr)
	);
	assign writes_idle = ((engine_writes_idle && !ddram_busy) && !ddram_rd) && !ddram_we;
	wolf_top #(
		.ROM_HEX(""),
		.PIC_RESPONSE_BYTES(128'h00004a0ea01845800614c3b203018444),
		.PIC_STATUS_DELAY(1'b0),
		.WWF_IO_SHUFFLE(1'b0)
	) engine(
		.clk(clk),
		.clk_cpu(clk),
		.ce_pix(ce_pix),
		.clk_snd(1'b0),
		.rst(((game_reset | power_reset) | load_active) | fault),
		.rst_pon(game_reset | power_reset),
		.sdram_por(power_reset),
		.inputs(inputs),
		.status(status),
		.game_profile(3'd0),
		.nvram_busy(nvram_busy),
		.nvram_ext_en(nvram_ext_en),
		.nvram_ext_wr(nvram_ext_wr),
		.nvram_ext_addr(nvram_ext_addr),
		.nvram_ext_wdata(nvram_ext_wdata),
		.nvram_ext_rdata(nvram_ext_rdata),
		.nvram_cpu_write(nvram_cpu_write),
		.ioctl_download(load_active),
		.ioctl_wr((valid_byte && (load_index == 0)) && !prog_wait),
		.ioctl_addr(prog_addr),
		.ioctl_dout(prog_data),
		.ioctl_be(prog_be),
		.ioctl_wait(prog_wait),
		.pocket_download_idle(engine_writes_idle),
		.snd_dl_wr(1'b0),
		.snd_dl_addr(18'd0),
		.snd_dl_data(8'd0),
		.dcs_dl_active(load_active),
		.dcs_dl_wr(valid_byte && (load_index == 2)),
		.dcs_dl_addr(load_addr[21:0]),
		.dcs_dl_data(load_data),
		.dcs_dl_ack(dcs_ack),
		.gfx_dl_wr(valid_byte && (load_index == 1)),
		.gfx_dl_addr(gfx_addr),
		.gfx_dl_data(load_data),
		.gfx_dl_ack(gfx_ack),
		.gfx_dl_idle(gfx_idle),
		.SDRAM_DQ(SDRAM_DQ),
		.SDRAM_A(SDRAM_A),
		.SDRAM_BA(SDRAM_BA),
		.SDRAM_DQML(SDRAM_DQML),
		.SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_nCS(SDRAM_nCS),
		.SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_nWE(SDRAM_nWE),
		.SDRAM_CKE(SDRAM_CKE),
		.DDRAM_ADDR(ddram_addr),
		.DDRAM_BURSTCNT(ddram_burstcnt),
		.DDRAM_RD(ddram_rd),
		.DDRAM_DIN(ddram_din),
		.DDRAM_BE(ddram_be),
		.DDRAM_WE(ddram_we),
		.DDRAM_BUSY(ddram_busy),
		.DDRAM_DOUT(ddram_dout),
		.DDRAM_DOUT_READY(ddram_dout_ready),
		.vid_r(vid_r),
		.vid_g(vid_g),
		.vid_b(vid_b),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),
		.de(de),
		.audio_l(audio_l),
		.audio_r(audio_r),
		.pc_dbg(pc_dbg),
		.illegal_dbg(illegal_dbg)
	);
endmodule
`default_nettype wire
`default_nettype none
module wolf_pocket_pixel_enable (
	clk_sys,
	clk_pixel,
	ce_pix
);
	input wire clk_sys;
	input wire clk_pixel;
	output wire ce_pix;
	reg pixel_sample = 0;
	reg ce_pix_r = 0;
	always @(negedge clk_sys) begin
		pixel_sample <= clk_pixel;
		ce_pix_r <= clk_pixel && !pixel_sample;
	end
	assign ce_pix = ce_pix_r;
endmodule
module wolf_pocket_video (
	clk_pixel,
	reset,
	r,
	g,
	b,
	hs,
	vs,
	de,
	rgb,
	apf_hs,
	apf_vs,
	apf_de
);
	input wire clk_pixel;
	input wire reset;
	input wire [7:0] r;
	input wire [7:0] g;
	input wire [7:0] b;
	input wire hs;
	input wire vs;
	input wire de;
	output reg [23:0] rgb = 0;
	output reg apf_hs = 0;
	output reg apf_vs = 0;
	output reg apf_de = 0;
	reg prev_hs = 0;
	reg prev_vs = 0;
	always @(posedge clk_pixel) begin
		prev_hs <= hs;
		prev_vs <= vs;
		rgb <= (de ? {r, g, b} : 24'd0);
		apf_hs <= hs && !prev_hs;
		apf_vs <= vs && !prev_vs;
		apf_de <= de;
		if (reset) begin
			rgb <= 0;
			apf_hs <= 0;
			apf_vs <= 0;
			apf_de <= 0;
			prev_hs <= 0;
			prev_vs <= 0;
		end
	end
endmodule
`default_nettype wire
module wolf_pocket_psram40 (
	clk,
	reset,
	req,
	chip,
	writing,
	address,
	length,
	wdata,
	wbe,
	ready,
	done,
	rvalid,
	rdata,
	windex,
	configured,
	cram0_a,
	cram1_a,
	cram0_dq,
	cram1_dq,
	cram0_wait,
	cram1_wait,
	cram0_clk,
	cram0_adv_n,
	cram0_cre,
	cram0_ce0_n,
	cram0_ce1_n,
	cram0_oe_n,
	cram0_we_n,
	cram0_ub_n,
	cram0_lb_n,
	cram1_clk,
	cram1_adv_n,
	cram1_cre,
	cram1_ce0_n,
	cram1_ce1_n,
	cram1_oe_n,
	cram1_we_n,
	cram1_ub_n,
	cram1_lb_n
);
	parameter integer POWER_CYCLES = 12000;
	input wire clk;
	input wire reset;
	input wire req;
	input wire chip;
	input wire writing;
	input wire [22:0] address;
	input wire [5:0] length;
	input wire [15:0] wdata;
	input wire [1:0] wbe;
	output wire ready;
	output reg done = 0;
	output reg rvalid = 0;
	output reg [15:0] rdata = 0;
	output reg [4:0] windex = 0;
	output reg [3:0] configured = 0;
	output wire [21:16] cram0_a;
	output wire [21:16] cram1_a;
	inout wire [15:0] cram0_dq;
	inout wire [15:0] cram1_dq;
	input wire cram0_wait;
	input wire cram1_wait;
	output wire cram0_clk;
	output wire cram0_adv_n;
	output wire cram0_cre;
	output wire cram0_ce0_n;
	output wire cram0_ce1_n;
	output wire cram0_oe_n;
	output wire cram0_we_n;
	output wire cram0_ub_n;
	output wire cram0_lb_n;
	output wire cram1_clk;
	output wire cram1_adv_n;
	output wire cram1_cre;
	output wire cram1_ce0_n;
	output wire cram1_ce1_n;
	output wire cram1_oe_n;
	output wire cram1_we_n;
	output wire cram1_ub_n;
	output wire cram1_lb_n;
	localparam [15:0] BCR = 16'h5d14;
	localparam POWER = 0;
	localparam CRE = 1;
	localparam CFG = 2;
	localparam CFG_HOLD = 3;
	localparam START = 4;
	localparam RUN = 5;
	localparam GAP = 6;
	localparam IDLE = 7;
	localparam READ_END = 8;
	reg [3:0] state = POWER;
	reg [13:0] count = POWER_CYCLES;
	reg [7:0] step = 0;
	reg [1:0] die = 0;
	reg init_mode = 1;
	reg config_gap = 0;
	reg restart = 0;
	reg wr = 0;
	reg [21:0] addr = 0;
	reg [5:0] words = 1;
	reg [5:0] word_no = 0;
	reg write_end = 0;
	reg [21:16] a = 0;
	reg [15:0] dq_out = 0;
	reg dq_drive = 0;
	reg adv = 1;
	reg cre = 0;
	reg ce = 1;
	reg oe = 1;
	reg we = 1;
	reg phase40 = 0;
	reg clock_enable = 0;
	(* preserve *) reg pin_clk0 = 0;
	(* preserve *) reg pin_clk1 = 0;
	always @(posedge clk) begin
		phase40 <= ~phase40;
		pin_clk0 <= phase40 && clock_enable;
		pin_clk1 <= phase40 && clock_enable;
	end
	reg [1:0] be = 2'b11;
	reg [3:0] ce_n = 4'b1111;
	reg [1:0] dq_enable = 2'b00;
	(* preserve *) reg [15:0] dq0_capture = 0;
	(* preserve *) reg [15:0] dq1_capture = 0;
	reg capture_pending = 0;
	reg capture_chip = 0;
	always @(posedge clk)
		if (phase40) begin
			dq0_capture <= cram0_dq;
			dq1_capture <= cram1_dq;
		end
	assign ready = ((state == IDLE) && !reset) && !restart;
	assign cram0_a = a;
	assign cram1_a = a;
	assign cram0_dq = (dq_enable[0] ? dq_out : 16'hzzzz);
	assign cram1_dq = (dq_enable[1] ? dq_out : 16'hzzzz);
	assign cram0_clk = pin_clk0;
	assign cram1_clk = pin_clk1;
	assign cram0_ce0_n = ce_n[0];
	assign cram0_ce1_n = ce_n[1];
	assign cram1_ce0_n = ce_n[2];
	assign cram1_ce1_n = ce_n[3];
	assign cram0_adv_n = adv;
	assign cram1_adv_n = adv;
	assign cram0_cre = cre;
	assign cram1_cre = cre;
	assign cram0_oe_n = oe;
	assign cram1_oe_n = oe;
	assign cram0_we_n = we;
	assign cram1_we_n = we;
	assign cram0_lb_n = be[0];
	assign cram1_lb_n = be[0];
	assign cram0_ub_n = be[1];
	assign cram1_ub_n = be[1];
	always @(posedge clk) begin
		done <= 0;
		rvalid <= capture_pending;
		capture_pending <= 0;
		if (capture_pending)
			rdata <= (capture_chip ? dq1_capture : dq0_capture);
		if (reset)
			restart <= 1;
		case (state)
			POWER: begin
				ce <= 1;
				ce_n <= 4'b1111;
				clock_enable <= 0;
				adv <= 1;
				cre <= 0;
				oe <= 1;
				we <= 1;
				dq_drive <= 0;
				dq_enable <= 2'b00;
				be <= 3;
				configured <= 0;
				init_mode <= 1;
				die <= 0;
				if (reset)
					count <= POWER_CYCLES;
				else if (count != 0)
					count <= count - 1'b1;
				else begin
					restart <= 0;
					count <= 2;
					cre <= 1;
					state <= CRE;
				end
			end
			CRE:
				if (count != 0)
					count <= count - 1'b1;
				else begin
					a <= 6'b001000;
					dq_out <= BCR;
					dq_drive <= 1;
					dq_enable <= (die[1] ? 2'b10 : 2'b01);
					adv <= 0;
					state <= CFG;
				end
			CFG: begin
				a <= 6'b001000;
				dq_out <= BCR;
				dq_drive <= 1;
				dq_enable <= (die[1] ? 2'b10 : 2'b01);
				ce <= 0;
				ce_n <= ~(4'b0001 << die);
				adv <= 0;
				we <= 0;
				cre <= 1;
				oe <= 1;
				be <= 3;
				count <= 0;
				state <= CFG_HOLD;
			end
			CFG_HOLD: begin
				count <= count + 1'b1;
				if (count == 1)
					adv <= 1;
				if (count == 6) begin
					ce <= 1;
					ce_n <= 4'b1111;
					we <= 1;
					configured[die] <= 1;
					config_gap <= 1;
					count <= 2;
					state <= GAP;
				end
			end
			IDLE:
				if (reset || restart) begin
					count <= POWER_CYCLES;
					state <= POWER;
				end
				else if (req) begin
					die <= {chip, address[22]};
					addr <= address[21:0];
					wr <= writing;
					words <= length;
					init_mode <= 0;
					state <= START;
				end
			START:
				if (!phase40) begin
					clock_enable <= 1;
					a <= addr[21:16];
					dq_out <= addr[15:0];
					dq_drive <= 1;
					dq_enable <= (die[1] ? 2'b10 : 2'b01);
					ce <= 0;
					ce_n <= ~(4'b0001 << die);
					adv <= 0;
					cre <= 0;
					oe <= 1;
					we <= !wr;
					be <= (wr ? 2'b11 : 2'b00);
					step <= 1;
					word_no <= 0;
					windex <= 0;
					write_end <= 0;
					state <= RUN;
				end
			RUN: begin
				step <= step + 1'b1;
				if (step == 2) begin
					adv <= 1;
					we <= 1;
				end
				if (!wr) begin
					if (step == 3) begin
						dq_drive <= 0;
						dq_enable <= 2'b00;
					end
					if (step == 4)
						oe <= 0;
					if ((step >= 9) && step[0]) begin
						if (!init_mode) begin
							capture_pending <= 1;
							capture_chip <= die[1];
						end
						word_no <= word_no + 1'b1;
						if (word_no == (words - 1'b1))
							state <= READ_END;
					end
				end
				else begin
					if ((step >= 8) && !step[0]) begin
						if (write_end) begin
							ce <= 1;
							ce_n <= 4'b1111;
							dq_drive <= 0;
							dq_enable <= 2'b00;
							be <= 3;
							config_gap <= 0;
							count <= 2;
							state <= GAP;
						end
						else begin
							dq_out <= wdata;
							be <= ~wbe;
						end
					end
					if ((step >= 9) && step[0]) begin
						word_no <= word_no + 1'b1;
						windex <= windex + 1'b1;
						write_end <= word_no == (words - 1'b1);
					end
				end
			end
			READ_END: begin
				ce <= 1;
				ce_n <= 4'b1111;
				oe <= 1;
				be <= 3;
				if (init_mode)
					clock_enable <= 0;
				config_gap <= 0;
				count <= 2;
				state <= GAP;
			end
			GAP:
				if (count != 0) begin
					count <= count - 1'b1;
					if (config_gap && (count == 2)) begin
						dq_drive <= 0;
						dq_enable <= 2'b00;
					end
				end
				else begin
					cre <= 0;
					if (reset || restart) begin
						count <= POWER_CYCLES;
						state <= POWER;
					end
					else if (init_mode) begin
						if (config_gap) begin
							addr <= 0;
							wr <= 0;
							words <= 1;
							state <= START;
						end
						else if (die != 3) begin
							die <= die + 1'b1;
							count <= 2;
							cre <= 1;
							state <= CRE;
						end
						else begin
							clock_enable <= 1;
							state <= IDLE;
						end
					end
					else begin
						done <= 1;
						state <= IDLE;
					end
				end
			default: begin
				ce <= 1;
				ce_n <= 4'b1111;
				state <= POWER;
				count <= POWER_CYCLES;
			end
		endcase
	end
endmodule
module dcs_ce_ram (
	clk,
	ce,
	write_enable,
	address_a,
	address_b,
	write_data,
	q_a,
	q_b
);
	parameter integer WIDTH = 24;
	parameter integer READ_WRITE_A = 1;
	parameter SIM_INIT = "";
	input wire clk;
	input wire ce;
	input wire write_enable;
	input wire [13:0] address_a;
	input wire [13:0] address_b;
	input wire [WIDTH - 1:0] write_data;
	output wire [WIDTH - 1:0] q_a;
	output wire [WIDTH - 1:0] q_b;
	altsyncram #(
		.intended_device_family("Cyclone V"),
		.lpm_type("altsyncram"),
		.ram_block_type("M10K"),
		.operation_mode((READ_WRITE_A ? "BIDIR_DUAL_PORT" : "DUAL_PORT")),
		.width_a(WIDTH),
		.widthad_a(14),
		.numwords_a(16384),
		.width_b(WIDTH),
		.widthad_b(14),
		.numwords_b(16384),
		.width_byteena_a(1),
		.width_byteena_b(1),
		.outdata_reg_a("UNREGISTERED"),
		.outdata_reg_b("UNREGISTERED"),
		.address_reg_b("CLOCK1"),
		.indata_reg_b("CLOCK1"),
		.wrcontrol_wraddress_reg_b("CLOCK1"),
		.clock_enable_input_a("NORMAL"),
		.clock_enable_core_a("NORMAL"),
		.clock_enable_input_b("NORMAL"),
		.clock_enable_core_b("NORMAL"),
		.clock_enable_output_a("BYPASS"),
		.clock_enable_output_b("BYPASS"),
		.read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
		.read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
		.read_during_write_mode_mixed_ports("DONT_CARE"),
		.power_up_uninitialized("FALSE"),
		.init_file("UNUSED")
	) ram(
		.clock0(clk),
		.clock1(clk),
		.clocken0(ce),
		.clocken1(ce),
		.clocken2(1'b1),
		.clocken3(1'b1),
		.aclr0(1'b0),
		.aclr1(1'b0),
		.address_a(address_a),
		.data_a(write_data),
		.wren_a(write_enable),
		.rden_a(1'b1),
		.byteena_a(1'b1),
		.address_b(address_b),
		.data_b({WIDTH {1'b0}}),
		.wren_b(1'b0),
		.rden_b(1'b1),
		.byteena_b(1'b1),
		.addressstall_a(1'b0),
		.addressstall_b(1'b0),
		.q_a(q_a),
		.q_b(q_b),
		.eccstatus()
	);
endmodule

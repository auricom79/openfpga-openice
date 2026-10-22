//
// sdram_stock.sv — the stock MiSTer SDRAM controller (Sorgelig, GPLv3), vendored for
// Arcade-SmashTV to replace the hand-rolled sdram_phy. DE10-proven single 16-bit port
// (addr/din/dout/wtbt/we/rd/ready), CAS-latency shift-register read capture, and — the key
// fix — it forwards SDRAM_CLK via an altddio_out I/O cell (NOT a fabric assign), so reads
// land in the valid window on real silicon. Bridged to the yunit arbiter by
// yunit_sdram_adapter.
//
// Original: Copyright (c) 2015-2019 Sorgelig. GNU GPLv3.
// Local changes: module renamed to `sdram_stock`; all declarations hoisted to module level
// (Questa rejects the upstream in-always initialized vars + forward-referenced `command`);
// the SDRAM_CLK DDIO is guarded (SIM_NO_ALTERA) so the behavioral sim needs no altera_mf.
//
module sdram_stock
(
   input             init,
   input             clk,         // ~96-100 MHz (CAS_LATENCY=2 for <100 MHz)

   inout      [15:0] SDRAM_DQ,
   output reg [12:0] SDRAM_A,
   output reg        SDRAM_DQML,
   output reg        SDRAM_DQMH,
   output reg  [1:0] SDRAM_BA,
   output            SDRAM_nCS,
   output            SDRAM_nWE,
   output            SDRAM_nRAS,
   output            SDRAM_nCAS,
   output            SDRAM_CKE,
   // NOTE: SDRAM_CLK is NOT driven here. The emu forwards it from the phase-shifted PLL
   // output (clk_sdram, outclk_1, -3515ps) exactly like the proven tecmo/jtframe cores —
   // and rtl/sdram.sdc sources the SDRAM_CLK generated clock from that same general[1]
   // output. (An earlier build drove SDRAM_CLK from a DDIO on clk_sys here, which did NOT
   // match the SDC's general[1] source -> STA closed the read window against the wrong
   // clock edge -> garbage reads on silicon. Reverted to the proven clk_sdram forward.)

   input       [1:0] wtbt,        // write byte mask: [1]=high, [0]=low
   input      [24:0] addr,        // BYTE address; addr[0]=0 for 16-bit accesses
   output     [15:0] dout,
   input      [15:0] din,
   input             we,
   input             rd,
   output reg        ready
);

localparam BURST_LENGTH        = 3'b000;
localparam ACCESS_TYPE         = 1'b0;
localparam CAS_LATENCY         = 3'd2;     // 2 for < 100MHz
localparam OP_MODE             = 2'b00;
localparam NO_WRITE_BURST      = 1'b1;
localparam MODE                = {3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

`ifdef POCKET
// 80 MHz, AS4C32M16MSA: wait >=200 us before PRECHARGE. Idle refresh
// is triggered at 2*cycles_per_refresh, so keep even that path below 7.8125 us.
localparam sdram_startup_cycles= 14'd16040;
localparam cycles_per_refresh  = 14'd300;
`else
localparam sdram_startup_cycles= 14'd12100;
localparam cycles_per_refresh  = 14'd780;
`endif
localparam startup_refresh_max = 14'b11111111111111;

localparam [2:0] CMD_NOP          = 3'b111;
localparam [2:0] CMD_ACTIVE       = 3'b011;
localparam [2:0] CMD_READ         = 3'b101;
localparam [2:0] CMD_WRITE        = 3'b100;
localparam [2:0] CMD_PRECHARGE    = 3'b010;
localparam [2:0] CMD_AUTO_REFRESH = 3'b001;
localparam [2:0] CMD_LOAD_MODE    = 3'b000;

typedef enum {
	STATE_STARTUP,
	STATE_OPEN_1, STATE_OPEN_2,
	STATE_IDLE, STATE_IDLE_1, STATE_IDLE_2, STATE_IDLE_3,
	STATE_IDLE_4, STATE_IDLE_5, STATE_IDLE_6, STATE_IDLE_7
} state_t;

// all state hoisted to module level (declared before use)
reg  [2:0]  command;
reg  [13:0] refresh_count = startup_refresh_max - sdram_startup_cycles;
reg  [24:0] save_addr;
reg  [15:0] data;
reg         old_we, old_rd;
reg  [CAS_LATENCY:0] data_ready_delay;
reg  [15:0] new_data;
reg  [1:0]  new_wtbt;
reg         new_we;
reg         new_rd;
reg         save_we = 1'b1;
state_t     state = STATE_STARTUP;
reg  [15:0] sdram_dq_out;                 // DQ drive value + tristate enable (Questa rejects
reg         sdram_dq_oe;                  // a procedurally-driven inout net, so gate it here)

assign SDRAM_DQ   = sdram_dq_oe ? sdram_dq_out : 16'bZ;
assign SDRAM_CKE  = 1;
assign SDRAM_nCS  = 0;
assign SDRAM_nRAS = command[2];
assign SDRAM_nCAS = command[1];
assign SDRAM_nWE  = command[0];
`ifdef POCKET
// Alliance initialization diagram requires DQM high through PRE/REF/MRS.
assign {SDRAM_DQMH,SDRAM_DQML} = (state == STATE_STARTUP) ? 2'b11 : SDRAM_A[12:11];
`else
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];
`endif
assign dout = save_addr[0] ? {data[7:0], data[15:8]} : {data[15:8], data[7:0]};

always @(posedge clk) begin
	sdram_dq_oe <= 1'b0;                   // release the DQ bus by default
	command <= CMD_NOP;
	refresh_count  <= refresh_count+1'b1;

	data_ready_delay <= {1'b0, data_ready_delay[CAS_LATENCY:1]};
	if(data_ready_delay[0]) {ready, data} <= {1'b1, SDRAM_DQ};

	case(state)
		STATE_STARTUP: begin
			SDRAM_A    <= 0;
			SDRAM_BA   <= 0;
			if (refresh_count == startup_refresh_max-31) begin command <= CMD_PRECHARGE; SDRAM_A[10] <= 1; SDRAM_BA <= 2'b00; end
			if (refresh_count == startup_refresh_max-23) command <= CMD_AUTO_REFRESH;
			if (refresh_count == startup_refresh_max-15) command <= CMD_AUTO_REFRESH;
			if (refresh_count == startup_refresh_max-7)  begin command <= CMD_LOAD_MODE; SDRAM_A <= MODE; end
`ifdef POCKET
            // Mobile SDRAM extended mode: full-array refresh, full drive strength.
            if (refresh_count == startup_refresh_max-3) begin command <= CMD_LOAD_MODE; SDRAM_BA <= 2'b10; SDRAM_A <= 0; end
`endif
			if(!refresh_count) begin state <= STATE_IDLE; ready <= 1; refresh_count <= 0; end
		end
		STATE_IDLE_7: state <= STATE_IDLE_6;
		STATE_IDLE_6: state <= STATE_IDLE_5;
		STATE_IDLE_5: state <= STATE_IDLE_4;
		STATE_IDLE_4: state <= STATE_IDLE_3;
		STATE_IDLE_3: state <= STATE_IDLE_2;
		STATE_IDLE_2: state <= STATE_IDLE_1;
		STATE_IDLE_1: begin
			state <= STATE_IDLE;
			if(refresh_count > cycles_per_refresh) begin state <= STATE_IDLE_7; command <= CMD_AUTO_REFRESH; refresh_count <= 0; end
		end
		STATE_IDLE: begin
			if(refresh_count > (cycles_per_refresh<<1)) state <= STATE_IDLE_1;
			else if(new_rd | new_we) begin
				new_we <= 0; new_rd <= 0; save_we <= new_we;
				state <= STATE_OPEN_1; command <= CMD_ACTIVE;
				SDRAM_A <= save_addr[13:1]; SDRAM_BA <= save_addr[24:23];
			end
		end
		STATE_OPEN_1: state <= STATE_OPEN_2;
		STATE_OPEN_2: begin
			SDRAM_A <= {save_we & (new_wtbt ? ~new_wtbt[1] : ~save_addr[0]), save_we & (new_wtbt ? ~new_wtbt[0] : save_addr[0]), 2'b10, save_addr[22:14]};
			if(save_we) begin
				command <= CMD_WRITE;
				sdram_dq_out <= new_wtbt ? new_data : {new_data[7:0], new_data[7:0]}; sdram_dq_oe <= 1'b1;
				ready <= 1;
`ifdef POCKET
                // Alliance AS4C32M16MSA: auto-precharge must finish before
                // AUTO REFRESH. ACTIVE was only two clocks before WRITE;
                // tRAS(48ns)+tRP(18ns) needs at least six clocks at 80MHz.
                // IDLE_4 prevents refresh until four clocks after WRITE.
                state <= STATE_IDLE_4;
`else
                state <= STATE_IDLE_2;
`endif
			end
			else begin command <= CMD_READ; data_ready_delay[CAS_LATENCY] <= 1; state <= STATE_IDLE_5; end
		end
		default: state <= STATE_IDLE;
	endcase

	if(init) begin state <= STATE_STARTUP; refresh_count <= startup_refresh_max - sdram_startup_cycles; end

	old_we <= we;
	if(we & ~old_we) begin save_addr <= addr; {ready, new_we, new_data, new_wtbt} <= {1'b0, 1'b1, din, wtbt}; end

	old_rd <= rd;
	if(rd & ~old_rd) begin
		save_addr <= addr;
		if(!(ready & ~save_we & (save_addr[24:1] == addr[24:1]))) {ready, new_rd} <= {1'b0, 1'b1};
	end
`ifdef POCKET
    // A renewed PLL/power reset invalidates the old completion and queue.
    // Keep this after edge detection so reset wins over an incoming request.
    if (init) begin
        ready <= 1'b0;
        new_we <= 1'b0;
        new_rd <= 1'b0;
        data_ready_delay <= '0;
    end
`endif
end

endmodule

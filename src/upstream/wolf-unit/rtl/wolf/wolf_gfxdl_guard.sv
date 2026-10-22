`default_nettype none
module wolf_gfxdl_guard #(
    parameter integer QUIET_CYCLES = 512
) (
    input  logic clk,
    input  logic sdram_por,
    input  logic rom_download,
    input  logic gfx_download,
    input  logic fifo_idle,
    input  logic writer_idle,
    output logic core_hold
);
    localparam integer QUIET_W = $clog2(QUIET_CYCLES + 1);

    logic drain_hold;
    logic gfx_seen;
    logic [QUIET_W-1:0] quiet_count;

    always_ff @(posedge clk) begin
        if (sdram_por) begin
            drain_hold <= 1'b0;
            gfx_seen <= 1'b0;
            quiet_count <= '0;
        end else if (rom_download) begin
            // Arm at index 0 so a framework gap before index 1 cannot boot the CPU early.
            drain_hold <= 1'b1;
            gfx_seen <= 1'b0;
            quiet_count <= '0;
        end else if (gfx_download) begin
            drain_hold <= 1'b1;
            gfx_seen <= 1'b1;
            quiet_count <= '0;
        end else if (drain_hold && gfx_seen) begin
            if (!fifo_idle || !writer_idle) begin
                quiet_count <= '0;
            end else if (quiet_count == QUIET_CYCLES - 1) begin
                // Avalon has no write-response channel. Leave a bounded post-acceptance
                // margin before the CPU can issue its first graphics read.
                drain_hold <= 1'b0;
                quiet_count <= '0;
            end else begin
                quiet_count <= quiet_count + 1'b1;
            end
        end else begin
            quiet_count <= '0;
        end
    end

    assign core_hold = rom_download | gfx_download | drain_hold;
endmodule
`default_nettype wire

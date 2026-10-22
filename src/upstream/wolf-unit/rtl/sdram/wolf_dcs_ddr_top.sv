// wolf_dcs_ddr_top.sv -- packed UMK3 DCS sound-ROM store on HPS DDR3.
//
// The MRA downloads a dense 4 MB byte image in physical-chip order
// U2|U3|U4|U5. Unlike the interleaved graphics stream, every eight consecutive
// bytes form one complete DDR3 beat, so this block commits full 64-bit writes
// (BE=FF) and never relies on the f2h bridge's unreliable partial byte enables.
//
// Read side is the DCS core's cache-fill interface: one requested beat, held
// until its Avalon response arrives. Writes are accepted into an 8-byte buffer
// and take priority while a ROM download is active; normal game operation has
// only reads. The existing single-outstanding agent remains the sole Avalon
// owner, so this block is safe to place behind the established DDR arbiter.
`default_nettype none
module wolf_dcs_ddr_top #(
    parameter logic [28:0] DCS_DDR_BASE = 29'h6c00000
) (
    input  logic        clk,
    input  logic        sdram_por,

    // Byte stream after HPS backpressure FIFO
    input  logic        dl_wr,
    input  logic [21:0] dl_addr,
    input  logic [7:0]  dl_data,
    output logic        dl_ack,
    output logic        dl_busy,

    // ADSP cache-fill beat port
    input  logic        rom_req,
    input  logic [18:0] rom_addr,
    output logic        rom_rdy,
    output logic [63:0] rom_q,

    // HPS DDR3 Avalon master
    output logic [28:0] ddram_addr,
    output logic [7:0]  ddram_burstcnt,
    output logic        ddram_rd,
    output logic        ddram_we,
    output logic [63:0] ddram_din,
    output logic [7:0]  ddram_be,
    input  logic        ddram_busy,
    input  logic [63:0] ddram_dout,
    input  logic        ddram_dout_ready
);
    logic        ag_wr_req, ag_rd_req;
    logic [25:0] ag_addr;
    logic [63:0] ag_wdata, ag_rdata;
    logic        ag_rd_valid, ag_busy, ag_wnext;

    stv_vram_ddr_agent #(.VRAM_DDR_BASE(DCS_DDR_BASE)) u_agent (
        .clk(clk), .sdram_por(sdram_por),
        .tst_wr_req(ag_wr_req), .tst_rd_req(ag_rd_req),
        .tst_addr(ag_addr), .tst_wdata(ag_wdata), .tst_be(8'hff), .tst_burstcnt(8'd1),
        .tst_rdata(ag_rdata), .tst_rd_valid(ag_rd_valid), .tst_busy(ag_busy), .tst_wnext(ag_wnext),
        .ddram_addr(ddram_addr), .ddram_burstcnt(ddram_burstcnt),
        .ddram_rd(ddram_rd), .ddram_we(ddram_we), .ddram_din(ddram_din), .ddram_be(ddram_be),
        .ddram_busy(ddram_busy), .ddram_dout(ddram_dout), .ddram_dout_ready(ddram_dout_ready)
    );

    logic        buf_valid, wr_pending, wr_inflight, rd_inflight;
`ifdef POCKET
    // The CE-gated DCS cache can hold rom_req high after consuming rom_rdy.
    // Do not relaunch that same request: a duplicate response may arrive while
    // the cache is already filling a different address. Keep the request armed
    // off until it drops, and discard responses to canceled fills.
    logic read_seen;
    logic [18:0] read_tag;
`endif
    logic [18:0] buf_beat;
    logic [7:0]  buf_mask;
    logic [63:0] buf_data;
    wire [18:0]  dl_beat = dl_addr[21:3];
    wire [7:0]   dl_lane = (8'h01 << dl_addr[2:0]);
    wire         dl_same = buf_valid && (dl_beat == buf_beat);
    wire         dl_take = dl_wr && !sdram_por && !wr_pending && !wr_inflight &&
                           (!buf_valid || dl_same);

    // A non-acknowledged byte remains at the FIFO head. If an unusual source
    // changes beat before filling all eight lanes, flush the partial (zeroed
    // untouched lanes) then accept that byte after the write completes.
    assign dl_ack = dl_take;
    assign dl_busy = buf_valid | wr_pending | wr_inflight;

    // Launch requests for one agent clock. Full buffered download beats win;
    // ROM reads are otherwise level-held by dcs_mem until rom_rdy comes back.
    always_comb begin
        ag_wr_req = !ag_busy && wr_pending && !wr_inflight;
        ag_rd_req = !ag_busy && !wr_pending && !wr_inflight && rom_req && !rd_inflight
`ifdef POCKET
                    && !read_seen
`endif
                    ;
        if (ag_wr_req) begin
            ag_addr  = {7'd0, buf_beat};
            ag_wdata = buf_data;
        end else begin
            ag_addr  = {7'd0, rom_addr};
            ag_wdata = 64'd0;
        end
    end

    assign rom_rdy = rd_inflight && ag_rd_valid
`ifdef POCKET
                     && read_seen && rom_req && rom_addr==read_tag
`endif
                     ;
    assign rom_q   = ag_rdata;

    always_ff @(posedge clk) begin
        if (sdram_por) begin
            buf_valid   <= 1'b0;
            buf_beat    <= '0;
            buf_mask    <= '0;
            buf_data    <= '0;
            wr_pending  <= 1'b0;
            wr_inflight <= 1'b0;
            rd_inflight <= 1'b0;
`ifdef POCKET
            read_seen <= 1'b0;
            read_tag <= 19'd0;
`endif
        end else begin
`ifdef POCKET
            if(!rom_req)read_seen<=1'b0;
            if(ag_rd_req)begin read_seen<=1'b1;read_tag<=rom_addr;end
`endif
            if (ag_wr_req) begin
                wr_pending  <= 1'b0;
                wr_inflight <= 1'b1;
            end
            if (ag_rd_req)
                rd_inflight <= 1'b1;
            if (rd_inflight && ag_rd_valid)
                rd_inflight <= 1'b0;
            if (wr_inflight && !ag_busy) begin
                // ag_busy drops after its full-beat write commits. Only then
                // release the buffer for the next eight download bytes.
                wr_inflight <= 1'b0;
                buf_valid   <= 1'b0;
                buf_mask    <= '0;
            end

            if (dl_take) begin
                if (!buf_valid) begin
                    buf_valid <= 1'b1;
                    buf_beat  <= dl_beat;
                    buf_mask  <= dl_lane;
                    buf_data  <= 64'd0;
                    buf_data[8*dl_addr[2:0] +: 8] <= dl_data;
                    if (dl_lane == 8'hff)
                        wr_pending <= 1'b1;
                end else begin
                    buf_mask <= buf_mask | dl_lane;
                    buf_data[8*dl_addr[2:0] +: 8] <= dl_data;
                    if ((buf_mask | dl_lane) == 8'hff)
                        wr_pending <= 1'b1;
                end
            end else if (dl_wr && buf_valid && !wr_pending && !wr_inflight &&
                         (dl_beat != buf_beat)) begin
                wr_pending <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire

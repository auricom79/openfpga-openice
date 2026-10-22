// yunit_sdram_arb.sv — Phase 6 W1f: system-level SDRAM arbiter + address map. Multiplexes
// the four Y-unit SDRAM requesters onto ONE physical 16-bit word port (a real MT48LC16M16
// controller in synth; the behavioral sdram_model in sim — both honor the same
// req-held-until-ack + edge-accept + inter-command-gap contract as vram_sdram_top).
//
//   vsd    : VRAM r/w + scanout (16-bit word; already merged by vram_sdram_top)   [run-time]
//   cpu_gfx: CPU gfx/ROM read   (BYTE; read a word, return the selected byte)      [run-time]
//   src    : blitter gfx read   (BYTE; same)                                       [run-time]
//   ioctl  : ROM load           (16-bit word write)                                [boot only]
//
// SDRAM WORD address map: gfx @0, program ROM @ROMB, VRAM @VRAMB. gfx/src byte address B ->
// word (GFXW_BASE + B>>1), byte = B[0]. cpu_gfx region: byte<GFX_BYTES -> gfx; else ROM.
`timescale 1ns/1ps
`default_nettype none
module yunit_sdram_arb #(
  parameter int SD_AW      = 25,
  parameter [SD_AW-1:0] GFXW_BASE  = 25'h000000,   // gfx words   @ 0
  parameter [SD_AW-1:0] ROMW_BASE  = 25'h0C0000,   // program ROM @ 0xC0000 words (=0x180000 B)
  parameter [SD_AW-1:0] VRAMW_BASE = 25'h0E0000,   // VRAM        @ 0xE0000 words
  parameter [SD_AW-1:0] RAMW_BASE  = 25'h180000,   // main RAM    @ 0x180000 words (after VRAM)
  parameter [23:0]      GFX_BYTES  = 24'h180000    // gfx region size in bytes (ROM follows)
)(
  input  logic         clk,
  input  logic         rst,
  // VRAM channel (16-bit word, from yunit_mem/vram_sdram_top)
  input  logic [SD_AW-1:0] vsd_addr,   // VRAM entry (word)
  input  logic [15:0]  vsd_din,
  input  logic [1:0]   vsd_be,
  input  logic         vsd_rd,
  input  logic         vsd_wr,
  output logic [15:0]  vsd_dout,
  output logic         vsd_ack,
  // main-RAM channel (16-bit word RMW, from wolf_mem/ram_sdram — CPU-only, run-time)
  input  logic [SD_AW-1:0] rsd_addr,   // RAM word (region-relative; RAMW_BASE added here)
  input  logic [15:0]  rsd_din,
  input  logic [1:0]   rsd_be,
  input  logic         rsd_rd,
  input  logic         rsd_wr,
  output logic [15:0]  rsd_dout,
  output logic         rsd_ack,
  // CPU gfx/ROM read (byte; req held until ack) — the yunit_mem external read port
  input  logic         cgfx_rd,
  input  logic [23:0]  cgfx_addr,      // BYTE address in the CPU gfx/ROM space (gfx@0, ROM@GFX_BYTES)
  output logic [7:0]   cgfx_data,
  output logic         cgfx_ack,
  // blitter src read (byte)
  input  logic         src_rd,
  input  logic [23:0]  src_addr,       // BYTE address into gfx
  output logic [7:0]   src_data,
  output logic         src_ack,
  // boot SDRAM channel (word rd/wr): serves BOTH the ioctl ROM download (writes) AND the
  // gfx-unpack pass (planar-scratch reads + flat-gfx writes) — they are disjoint in time
  // (download THEN unpack), so yunit_top muxes them into this one channel. Folding them
  // keeps the run-time sd_addr mux 4-way (VSD/CGFX/SRC/IOL) instead of 5, shortening the
  // scan_req->SDRAM_A path. iol_be: 2'b11 full-word, 2'b01/2'b10 byte-interleaved ROM.
  input  logic         iol_rd,
  input  logic         iol_wr,
  input  logic [SD_AW-1:0] iol_addr,   // word address (already mapped)
  input  logic [15:0]  iol_din,
  input  logic [1:0]   iol_be,
  output logic [15:0]  iol_dout,
  output logic         iol_ack,
  // physical single-word SDRAM port
  output logic [SD_AW-1:0] sd_addr,
  output logic [15:0]  sd_din,
  output logic [1:0]   sd_be,
  output logic         sd_rd,
  output logic         sd_wr,
  input  logic [15:0]  sd_dout,
  input  logic         sd_ack
);
  // per-channel physical word address + the byte-select for the byte channels
  wire [SD_AW-1:0] cgfx_word = (cgfx_addr < GFX_BYTES)
                             ? (GFXW_BASE + {1'b0, cgfx_addr[23:1]})
                             : (ROMW_BASE + {1'b0, (cgfx_addr - GFX_BYTES) >> 1});
  wire             cgfx_bsel = cgfx_addr[0];
  wire [SD_AW-1:0] src_word  = GFXW_BASE + {1'b0, src_addr[23:1]};
  wire             src_bsel  = src_addr[0];
  wire [SD_AW-1:0] vsd_word  = VRAMW_BASE + vsd_addr;
  wire [SD_AW-1:0] rsd_word  = RAMW_BASE  + rsd_addr;

  // The CPU external interface is byte-wide, while SDRAM is 16 bits. Wolf's
  // field engine requests consecutive bytes, so without this cache the low
  // and high byte of one word each launch an identical physical SDRAM read.
  logic             cgfx_cache_valid;
  logic [SD_AW-1:0] cgfx_cache_word;
  logic [15:0]      cgfx_cache_data;
  logic             cgfx_hit_pending;
  logic [7:0]       cgfx_hit_data;
  wire              cgfx_cache_hit = cgfx_cache_valid && (cgfx_cache_word == cgfx_word);
  wire [7:0]        cgfx_cache_byte = cgfx_bsel ? cgfx_cache_data[15:8]
                                                : cgfx_cache_data[7:0];
  wire              cgfx_miss_req = cgfx_rd && !cgfx_cache_hit && !cgfx_hit_pending;
  // In the production maps, VRAM/RAM occupy regions above GFX/program ROM and
  // cannot alias this cache. IOL is the sole writer to the cached regions; the
  // CPU/video are held in reset while it is active, but compare its tag anyway.
  // Keeping VRAM's deep autoerase address path out of hit capture is also vital
  // for the 80 MHz requester-response timing boundary.
  wire              alias_cache_write = iol_wr && cgfx_cache_valid &&
                                                 (iol_addr == cgfx_cache_word);

  // grant-held arbiter with inter-command bubble (same contract vram_sdram_top proved).
  // priority: boot IOL (download/unpack) > VRAM (real-time scanout) > CPU gfx/ROM > main RAM
  // > blitter src. IOL is top priority but only active at boot (CPU/video held in reset).
  // RAM (~4.3 MB/s, latency-tolerant) sits below scanout so it can't starve the real-time video.
  localparam logic [2:0] G_NONE=3'd0, G_IOL=3'd1, G_VSD=3'd2, G_CGFX=3'd3, G_SRC=3'd4, G_RSD=3'd5;
  wire vsd_req = vsd_rd | vsd_wr;
  wire rsd_req = rsd_rd | rsd_wr;
  wire iol_req = iol_rd | iol_wr;
  logic [2:0] gnt; logic gnt_held; logic [2:0] gnt_r; logic bubble;
  always_comb begin
    if (gnt_held)     gnt = gnt_r;
    else if (bubble)  gnt = G_NONE;
    else if (iol_req) gnt = G_IOL;
`ifdef DIAG_CPU_FIRST
    // DIAG boot layer-scope proof: the display is the hex overlay, so the game
    // scanout is not needed. Give the CPU (cgfx code/ROM + rsd RAM) priority OVER
    // the scanout so it is not starved during active lines (the shared-SDRAM
    // scanout-starvation that hangs the boot into FFBAxxxx). If this boots the CPU
    // to the io-poll, starvation is confirmed -> the durable fix is VRAM->DDR3.
    else if (cgfx_miss_req) gnt = G_CGFX;
    else if (rsd_req) gnt = G_RSD;
    else if (vsd_req) gnt = G_VSD;
    else if (src_rd)  gnt = G_SRC;
`else
    else if (vsd_req) gnt = G_VSD;
    else if (cgfx_miss_req) gnt = G_CGFX;
    else if (rsd_req) gnt = G_RSD;
    else if (src_rd)  gnt = G_SRC;
`endif
    else              gnt = G_NONE;
  end
  // Cache hits never enter arbitration. They can complete while another client
  // owns SDRAM and create neither a held grant nor an inter-command bubble.
  wire gnt_done = sd_ack;
  always_ff @(posedge clk) begin
    if (rst) begin gnt_held<=1'b0; gnt_r<=G_NONE; bubble<=1'b0; end
    else begin
      bubble <= 1'b0;
      if (!gnt_held) begin
        if (!bubble && gnt!=G_NONE) begin
          if (gnt_done) begin gnt_held<=1'b0; bubble<=1'b1; end
          else begin gnt_held<=1'b1; gnt_r<=gnt; end
        end
      end else if (gnt_done) begin
        gnt_held<=1'b0; bubble<=1'b1;
      end
    end
  end

  // Register cache-hit responses. A combinational hit used to create a full
  // requester-address -> cache compare -> returned byte/ack -> field extract
  // round trip in one 80 MHz cycle. One registered response cycle keeps the
  // physical-read saving while breaking that path at a clear interface boundary.
  always_ff @(posedge clk) begin
    if (rst) begin
      cgfx_hit_pending <= 1'b0;
      cgfx_hit_data    <= 8'h00;
    end else if (cgfx_hit_pending) begin
      cgfx_hit_pending <= 1'b0;
    end else if (cgfx_rd && cgfx_cache_hit && !alias_cache_write) begin
      cgfx_hit_pending <= 1'b1;
      cgfx_hit_data    <= cgfx_cache_byte;
    end
  end

  // Fill only from a completed physical CPU read. An aliasing physical write
  // drops the cache at command issue; unrelated VRAM/RAM/src traffic preserves it.
  always_ff @(posedge clk) begin
    if (rst) begin
      cgfx_cache_valid <= 1'b0;
      cgfx_cache_word  <= '0;
      cgfx_cache_data  <= 16'h0000;
    end else if (alias_cache_write) begin
      cgfx_cache_valid <= 1'b0;
    end else if (sd_ack && (gnt == G_CGFX)) begin
      cgfx_cache_valid <= 1'b1;
      cgfx_cache_word  <= sd_addr;
      cgfx_cache_data  <= sd_dout;
    end
  end

  // route the granted requester to the physical port; return ack/data to it only.
  logic cgfx_bsel_q, src_bsel_q;   // (decl before use: Questa/Quartus need decl-before-use)
  logic [SD_AW-1:0] cgfx_word_q;
  wire [7:0] rd_byte = cgfx_bsel_q ? sd_dout[15:8] : sd_dout[7:0];  // byte-channel select (registered bsel)
  always_ff @(posedge clk) begin                     // latch the byte-select at grant time
    if (!gnt_held && gnt==G_CGFX) begin
      cgfx_bsel_q <= cgfx_bsel;
      cgfx_word_q <= cgfx_word;
    end
    if (gnt==G_SRC)  src_bsel_q  <= src_bsel;
  end
  wire cgfx_hit_ack = !rst && cgfx_hit_pending;
  always_comb begin
    sd_addr='0; sd_din=16'h0; sd_be=2'b00; sd_rd=1'b0; sd_wr=1'b0;
    vsd_ack=1'b0; cgfx_ack=cgfx_hit_ack; src_ack=1'b0; iol_ack=1'b0; rsd_ack=1'b0;
    vsd_dout=sd_dout; iol_dout=sd_dout; rsd_dout=sd_dout;
    cgfx_data = cgfx_hit_ack ? cgfx_hit_data
                             : (cgfx_bsel_q ? sd_dout[15:8] : sd_dout[7:0]);
    src_data  = src_bsel_q  ? sd_dout[15:8] : sd_dout[7:0];
    case (gnt)
      G_IOL:  begin sd_addr=iol_addr;  sd_din=iol_din; sd_be=iol_be; sd_rd=iol_rd; sd_wr=iol_wr; iol_ack=sd_ack; end
      G_VSD:  begin sd_addr=vsd_word;  sd_din=vsd_din; sd_be=vsd_be; sd_rd=vsd_rd; sd_wr=vsd_wr; vsd_ack=sd_ack; end
      G_RSD:  begin sd_addr=rsd_word;  sd_din=rsd_din; sd_be=rsd_be; sd_rd=rsd_rd; sd_wr=rsd_wr; rsd_ack=sd_ack; end
      G_CGFX: begin
        sd_addr = gnt_held ? cgfx_word_q : cgfx_word;
        sd_be=2'b00; sd_rd=1'b1; cgfx_ack=sd_ack;
        cgfx_data = (gnt_held ? cgfx_bsel_q : cgfx_bsel)
                  ? sd_dout[15:8] : sd_dout[7:0];
      end
      G_SRC:  begin sd_addr=src_word;  sd_be=2'b00; sd_rd=1'b1;                       src_ack=sd_ack; end
      default: ;
    endcase
  end
endmodule
`default_nettype wire

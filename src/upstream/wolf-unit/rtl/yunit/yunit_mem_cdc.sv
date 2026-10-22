// yunit_mem_cdc.sv — Phase 6 timing closure: clock-domain crossing for the CPU
// memory interface. The vendored TMS34010 core's combinational decode->execute->
// regfile path maxes at ~30 MHz, but memsys/SDRAM/video need ~96 MHz. So the CPU
// runs on a slow clock (clk_cpu, ~24 MHz) and everything else on clk_sys (96 MHz);
// this adapter bridges the CPU's req/ack memory interface across the two domains.
//
// The CPU holds mem_req + a STABLE {we,addr,size,wdata} until it sees mem_ack, then
// captures mem_rdata and drops mem_req. This adapter:
//   - clk_cpu side: latches the request on c_req, crosses it, presents c_ack + a
//     stable c_rdata when the response returns (held until c_req drops).
//   - clk_sys side: drives memsys with the IDENTICAL req/ack behavior the CPU would
//     (assert m_req, hold until m_ack, then drop) — so memsys needs NO change.
// Control crosses via 2-phase toggles through 2-FF synchronizers; the payload/
// response buses are stable while their toggle is in flight (SDC false-paths them).
// One transaction at a time (the CPU is strictly sequential), so no stale-ack race.
`default_nettype none
module yunit_mem_cdc #(
  parameter AW = 32, parameter DW = 32, parameter SW = 6
)(
  // ---- CPU domain (clk_cpu) ----
  input  logic          clk_cpu,
  input  logic          ce_cpu,   // P0019: CPU clock-enable. yunit_top now drives clk_cpu=clk_sys
                                   // and pulses ce_cpu 1-in-4, so this side steps in lockstep with
                                   // the CE-gated core — behaviorally identical to the old real /4
                                   // clk_cpu, but SINGLE-CLOCK so STA times it and no CDC metastability.
  input  logic          rst_cpu,
  input  logic          c_req,
  input  logic          c_we,
  input  logic [AW-1:0] c_addr,
  input  logic [SW-1:0] c_size,
  input  logic [DW-1:0] c_wdata,
  output logic          c_ack,
  output logic [DW-1:0] c_rdata,
  // ---- memsys domain (clk_sys) ----
  input  logic          clk_sys,
  input  logic          rst_sys,
  output logic          m_req,
  output logic          m_we,
  output logic [AW-1:0] m_addr,
  output logic [SW-1:0] m_size,
  output logic [DW-1:0] m_wdata,
  input  logic [DW-1:0] m_rdata,
  input  logic          m_ack
);
  // ---- cross-domain payload/response (stable while the matching toggle is crossing) ----
  logic          req_tgl;              // clk_cpu: flips per accepted request
  logic          ack_tgl;              // clk_sys: flips per completed response
  logic          p_we;  logic [AW-1:0] p_addr; logic [SW-1:0] p_size; logic [DW-1:0] p_wdata;
  logic [DW-1:0] resp;

  // ---- clk_cpu side: launch a request, PULSE c_ack when the response returns ---
  // c_ack is a 1-cycle pulse (NOT held): the TMS34010 holds mem_req across back-to-
  // back accesses (e.g. FETCH_LO->FETCH_HI) with only the address changing, so a
  // held ack would make it capture the previous word for the next access. After the
  // pulse, a 1-cycle COOL gap lets the CPU update addr/req before we re-sample it —
  // exactly the ack-blocking cycle memsys relies on in the single-clock case.
  typedef enum logic [1:0] { C_IDLE, C_WAIT, C_COOL } cstate_t;
  cstate_t cst;
  logic [2:0] ackt_sync;               // ack_tgl into clk_cpu (2-FF + prev)
  always_ff @(posedge clk_cpu) if (rst_cpu || (ce_cpu !== 1'b0)) begin
    if (rst_cpu) begin
      cst <= C_IDLE; req_tgl <= 1'b0; c_ack <= 1'b0; ackt_sync <= 3'b0;
    end else begin
      ackt_sync <= {ackt_sync[1:0], ack_tgl};
      c_ack <= 1'b0;                    // default -> pulse
      case (cst)
        C_IDLE: if (c_req) begin        // fresh request: latch payload, launch
                  p_we <= c_we; p_addr <= c_addr; p_size <= c_size; p_wdata <= c_wdata;
                  req_tgl <= ~req_tgl; cst <= C_WAIT;
                end
        C_WAIT: if (ackt_sync[2] ^ ackt_sync[1]) begin
                  c_rdata <= resp; c_ack <= 1'b1; cst <= C_COOL;   // 1-cycle ack pulse
                end
        C_COOL: cst <= C_IDLE;          // gap: CPU captures + advances addr/req here
        default: cst <= C_IDLE;
      endcase
    end
  end

  // ---- clk_sys side: drive memsys exactly like the CPU would ------------------
  typedef enum logic [1:0] { S_IDLE, S_REQ } sstate_t;
  sstate_t sst;
  logic [2:0] reqt_sync;                // req_tgl into clk_sys (2-FF + prev)
  always_ff @(posedge clk_sys) begin
    if (rst_sys) begin
      sst <= S_IDLE; m_req <= 1'b0; ack_tgl <= 1'b0; reqt_sync <= 3'b0;
    end else begin
      reqt_sync <= {reqt_sync[1:0], req_tgl};
      case (sst)
        S_IDLE: if (reqt_sync[2] ^ reqt_sync[1]) begin   // new request arrived
                  m_we <= p_we; m_addr <= p_addr; m_size <= p_size; m_wdata <= p_wdata;
                  m_req <= 1'b1; sst <= S_REQ;
                end
        S_REQ:  if (m_ack) begin                          // memsys done
                  resp <= m_rdata; m_req <= 1'b0;          // drop req the cycle we see ack (like the CPU)
                  ack_tgl <= ~ack_tgl; sst <= S_IDLE;
                end
        default: sst <= S_IDLE;
      endcase
    end
  end
endmodule

// Wolf's CPU and memsys now share one physical clock. This adapter preserves
// the same request/ack contract without crossing toggles through synchronizers.
module yunit_mem_sameclock #(
  parameter AW = 32, parameter DW = 32, parameter SW = 6
)(
  input  logic          clk_cpu,
  input  logic          ce_cpu,
  input  logic          rst_cpu,
  input  logic          c_req,
  input  logic          c_we,
  input  logic [AW-1:0] c_addr,
  input  logic [SW-1:0] c_size,
  input  logic [DW-1:0] c_wdata,
  output logic          c_ack,
  output logic [DW-1:0] c_rdata,
  input  logic          clk_sys,
  input  logic          rst_sys,
  output logic          m_req,
  output logic          m_we,
  output logic [AW-1:0] m_addr,
  output logic [SW-1:0] m_size,
  output logic [DW-1:0] m_wdata,
  input  logic [DW-1:0] m_rdata,
  input  logic          m_ack
);
  typedef enum logic [1:0] { SC_IDLE, SC_WAIT, SC_RESP, SC_COOL } scstate_t;
  scstate_t scst;

  // clk_cpu and clk_sys must be tied to the same clock. clk_cpu remains in the
  // interface so swapping adapters does not change top-level wiring.
  always_ff @(posedge clk_sys) begin
    if (rst_sys || rst_cpu) begin
      scst    <= SC_IDLE;
      c_ack   <= 1'b0;
      c_rdata <= '0;
      m_req   <= 1'b0;
      m_we    <= 1'b0;
      m_addr  <= '0;
      m_size  <= '0;
      m_wdata <= '0;
    end else begin
      case (scst)
        SC_IDLE: begin
          c_ack <= 1'b0;
          if ((ce_cpu !== 1'b0) && c_req) begin
            m_we    <= c_we;
            m_addr  <= c_addr;
            m_size  <= c_size;
            m_wdata <= c_wdata;
            m_req   <= 1'b1;
            scst    <= SC_WAIT;
          end
        end
        SC_WAIT: if (m_ack) begin
          c_rdata <= m_rdata;
          c_ack   <= 1'b1;
          m_req   <= 1'b0;
          scst    <= SC_RESP;
        end
        SC_RESP: if (ce_cpu !== 1'b0) begin
          c_ack <= 1'b0;
          scst  <= SC_COOL;
        end
        SC_COOL: if (ce_cpu !== 1'b0) scst <= SC_IDLE;
        default: scst <= SC_IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire

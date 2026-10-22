// wolf_pic.sv -- Midway serial-PIC security chip (UMK3 / Wolf-unit).
//
// Faithful transcription of the host-visible byte-shift protocol of
// midway_serial_pic_device (MAME 0.280, mame-gospel/midway/midwayic.cpp).
// UMK3 uses the *emu* PIC (midwunit.cpp:666-670) which wraps a real PIC16C57,
// but its host-observable behavior is byte-for-byte identical to the base
// serial device's {write,read,status_r,reset_w} (midwayic.cpp:179-223) --
// architect-ratified: we transcribe that C++ model, NOT synthesize a PIC16C57.
// Ports map 1:1 to wolf_mem's io_r case4 = {pic_status,12'd0} | snd_stat mux.
//
// Behavior gospel (WOLF_PIC_SPEC.md, verified against midwayic.cpp):
//   reset_w (state) : idx=0; status=0; buff=0                (midwayic.cpp:179-187)
//   status_r        : returns m_status                        (midwayic.cpp:190-193)
//   read            : returns m_buff; side effect status=1    (midwayic.cpp:196-204)
//   write(data)     : status=(data>>4)&1;                     (midwayic.cpp:207-223)
//                     if(!status) buff = (data&0x0f) ? (data&0x0f)          // self-test echo
//                                                    : m_data[m_idx++ % 16] // response advance
//
// m_data[16] response ROM for umk3 rev1.2 (fresh CMOS), captured live in
// picpoll.txt SEC_R #2..#17 (SEC_R #1 = 00 is the pre-advance buff=0 read):
//   F6 9A 01 DB 09 25 08 B4 60 6C 17 02 0E 4A 1E 2B
// (WOLF_PIC_SPEC.md §3.)

`default_nettype none

module wolf_pic #(
    // Host-visible response bytes, packed with byte 0 in bits [7:0].  Keep the
    // captured UMK3 table as the hardware default; other Wolf games select a
    // response profile at elaboration without changing the shift protocol.
    parameter logic [127:0] RESPONSE_BYTES =
        128'h2B1E_4A0E_0217_6C60_B408_2509_DB01_9AF6
) (
    input  logic       clk,
    input  logic       rst,          // synchronous reset (device power-on)

    input  logic       cmd_we,       // security_w  : @1600000 byte write pulse
    input  logic [7:0] cmd_data,     //               low nibble = command, bit4 = serial clock
    input  logic       resp_re,      // security_r  : @1600000 read pulse (side-effect status=1)

    input  logic       reset_w,      // io_w case1 write-strobe (bit5 carried in reset_val)
    input  logic       reset_val,    // io_w newword bit5; state-true (=1) => reset the FSM

    output logic [7:0] resp_data,    // -> security_r result (A0)
    output logic       status        // -> io_r case4 bit12 (pic.status_r())
);

    // --- §3 response ROM: the 16 m_data[] entries, % 16 -------------------
    function automatic logic [7:0] pic_byte(input logic [3:0] a);
        case (a)
            4'h0: pic_byte = RESPONSE_BYTES[  7:  0];
            4'h1: pic_byte = RESPONSE_BYTES[ 15:  8];
            4'h2: pic_byte = RESPONSE_BYTES[ 23: 16];
            4'h3: pic_byte = RESPONSE_BYTES[ 31: 24];
            4'h4: pic_byte = RESPONSE_BYTES[ 39: 32];
            4'h5: pic_byte = RESPONSE_BYTES[ 47: 40];
            4'h6: pic_byte = RESPONSE_BYTES[ 55: 48];
            4'h7: pic_byte = RESPONSE_BYTES[ 63: 56];
            4'h8: pic_byte = RESPONSE_BYTES[ 71: 64];
            4'h9: pic_byte = RESPONSE_BYTES[ 79: 72];
            4'hA: pic_byte = RESPONSE_BYTES[ 87: 80];
            4'hB: pic_byte = RESPONSE_BYTES[ 95: 88];
            4'hC: pic_byte = RESPONSE_BYTES[103: 96];
            4'hD: pic_byte = RESPONSE_BYTES[111:104];
            4'hE: pic_byte = RESPONSE_BYTES[119:112];
            default: pic_byte = RESPONSE_BYTES[127:120];
        endcase
    endfunction

    logic [7:0] buff;   // m_buff  (response latch)
    logic [3:0] idx;    // m_idx   (mod 16 -> 4 bits wraps naturally)
    logic       stat;   // m_status

    always_ff @(posedge clk) begin
        if (rst) begin
            idx  <= 4'd0;
            stat <= 1'b0;
            buff <= 8'd0;
        end
        // reset_w(state): base device treats state-true as reset (midwayic.cpp:181)
        else if (reset_w && reset_val) begin
            idx  <= 4'd0;
            stat <= 1'b0;
            buff <= 8'd0;
        end
        else begin
            // write() -- the core shift engine (midwayic.cpp:207-223)
            if (cmd_we) begin
                stat <= cmd_data[4];              // m_status = (data>>4)&1
                if (!cmd_data[4]) begin           // on the FALLING edge of the clock
                    if (cmd_data[3:0] != 4'd0)
                        buff <= {4'h0, cmd_data[3:0]};        // self-test echo (1F/0F -> 0F)
                    else begin
                        buff <= pic_byte(idx);                // clock out next response byte
                        idx  <= idx + 4'd1;                   // m_idx++ % 16 (4-bit wrap)
                    end
                end
            end
            // read() side effect: status=1 (midwayic.cpp:200)
            if (resp_re) begin
                stat <= 1'b1;
            end
        end
    end

    assign resp_data = buff;
    assign status    = stat;

endmodule

`default_nettype wire

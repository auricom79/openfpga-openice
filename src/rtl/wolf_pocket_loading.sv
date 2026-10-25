// SPDX-License-Identifier: MIT
// Independent 8 MHz loading raster: 400x254 active, 506x289 total.
// percent and fault must already be synchronized to clk_pixel. Latch them
// once per frame so the text and bar cannot disagree within a scanout.
// Artwork is a reduced, five-bit grayscale encoding of a rendered title
// screenshot. It contains no executable game ROM data.
`default_nettype none
module wolf_pocket_loading #(
    parameter ART_FILE = "core/openice_loading.hex"
)(
    input wire clk_pixel, reset,
    input wire [6:0] percent,
    input wire fault,
    output reg [23:0] rgb=0,
    output reg hs=0, vs=0, de=0
);
    localparam [8:0] H_ACTIVE=400, H_TOTAL=506;
    localparam [8:0] V_ACTIVE=254, V_TOTAL=289;
    reg [8:0] x=0, y=0;
    reg [6:0] shown_percent=0;
    reg shown_fault=0;
    always @(posedge clk_pixel) begin
        if(reset) begin
            x<=0; y<=0; shown_percent<=0; shown_fault<=0;
        end else begin
            if(x==H_TOTAL-9'd1) begin
                x<=0;
                if(y==V_TOTAL-9'd1) y<=0;
                else y<=y+1'b1;
            end else x<=x+1'b1;
            if(x==0 && y==0) begin
                shown_percent<=percent>100 ? 7'd100 : percent;
                shown_fault<=fault;
            end
        end
    end

    // 180x114 source pixels doubled to 360x228, with 20-pixel side margins.
    // A synchronous read keeps the image in block memory rather than logic.
    (* ramstyle="M10K" *) reg [4:0] artwork [0:20519];
    initial $readmemh(ART_FILE,artwork);
    wire in_art=x>=20 && x<380 && y<228;
    wire [7:0] art_x=8'((x-9'd20)>>1);
    wire [6:0] art_y=y[7:1];
    wire [14:0] art_addr=15'(art_y)*15'd180+{7'd0,art_x};
    reg [4:0] art_q=0;
    always @(posedge clk_pixel) art_q<=artwork[in_art ? art_addr : 15'd0];
    wire [7:0] gray={art_q,art_q[4:2]};

    function automatic [34:0] glyph(input [7:0] letter);
        case(letter)
            "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
            "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
            "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
            "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
            "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
            "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
            "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
            "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
            "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            "G":glyph={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
            "I":glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            "N":glyph={5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
            "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
            "%":glyph={5'b11001,5'b11010,5'b00010,5'b00100,5'b01000,5'b01011,5'b10011};
            default:glyph=35'd0;
        endcase
    endfunction
    function automatic [4:0] font_row(input [7:0] letter,input [2:0] row);
        reg [34:0] bits;
        begin
            bits=glyph(letter);
            font_row=bits[34-5*row -:5];
        end
    endfunction
    wire [6:0] tens=shown_percent/7'd10;
    wire [6:0] units=shown_percent%7'd10;
    wire [7:0] hundreds_char=shown_percent==100 ? "1" : " ";
    wire [7:0] tens_char=shown_percent==100 ? "0" :
                         shown_percent>=10 ? 8'd48+{1'b0,tens} : " ";
    wire [7:0] units_char=8'd48+{1'b0,units};
    wire [2:0] text_y=3'((y-9'd230)>>1);
    // Every character is 5x7 with a one-column gap, scaled two times.
    wire [71:0] text_row=shown_fault ? {
        6'd0,font_row("L",text_y),1'b0,font_row("O",text_y),1'b0,
        font_row("A",text_y),1'b0,font_row("D",text_y),1'b0,6'd0,
        font_row("E",text_y),1'b0,font_row("R",text_y),1'b0,
        font_row("R",text_y),1'b0,font_row("O",text_y),1'b0,
        font_row("R",text_y),1'b0,6'd0
    } : {
        font_row("L",text_y),1'b0,font_row("O",text_y),1'b0,
        font_row("A",text_y),1'b0,font_row("D",text_y),1'b0,
        font_row("I",text_y),1'b0,font_row("N",text_y),1'b0,
        font_row("G",text_y),1'b0,6'd0,
        font_row(hundreds_char,text_y),1'b0,font_row(tens_char,text_y),1'b0,
        font_row(units_char,text_y),1'b0,font_row("%",text_y),1'b0
    };
    wire [6:0] text_x=7'((x-9'd128)>>1);
    wire text_pixel=x>=128 && x<272 && y>=230 && y<244 && text_row[71-text_x];
    wire bar_border=x>=48 && x<=351 && y>=246 && y<=253 &&
                    (x==48 || x==351 || y==246 || y==253);
    wire [8:0] filled_pixels={2'd0,shown_percent}+({2'd0,shown_percent}<<1);
    wire bar_fill=x>=50 && x<50+filled_pixels && y>=248 && y<=251;

    reg art_valid_q=0,hs_q=0,vs_q=0,de_q=0;
    reg [23:0] overlay_q=0;
    always @(posedge clk_pixel) begin
        art_valid_q<=in_art;
        hs_q<=x>=405 && x<448;
        vs_q<=y>=269 && y<272;
        de_q<=x<H_ACTIVE && y<V_ACTIVE;
        overlay_q<=bar_border ? 24'h687480 :
                   bar_fill ? (shown_fault ? 24'hc83838 : 24'h40c8e8) :
                   text_pixel ? (shown_fault ? 24'hff7777 : 24'hf0f4f8) : 24'h000000;
        rgb<=de_q ? (art_valid_q ? {gray,gray,gray} : overlay_q) : 24'd0;
        hs<=hs_q; vs<=vs_q; de<=de_q;
        if(reset) begin
            art_valid_q<=0; hs_q<=0; vs_q<=0; de_q<=0; overlay_q<=0;
            rgb<=0; hs<=0; vs<=0; de<=0;
        end
    end
endmodule
`default_nettype wire

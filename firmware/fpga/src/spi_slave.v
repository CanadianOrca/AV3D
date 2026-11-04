// receives bytes from the Raspberry Pi over SPI
//
// THe SPI wires are seampled with our 27 MHz clock (oversampling) so SCK must
// stay at or below 4 MHz.
//
// What the pi gets back on MISO in each transaction (CS low ... CS high)
// byte 0 STATUS
// byte n >= 1: echo of the byte the Pi sent at n-1
//
// MISO is only reliable at 1 MHz or less
// Writes work at the full 4 MHz

module spi_slave #(
    parameter [7:0] CMD_GET_INDEX = 8'h0A
) (
    input wire clk,
    input wire rst,
    input wire sck, // raw pins
    input wire mosi,
    input wire cs_n,
    input wire [7:0] status, // sent as byte 0
    input wire [9:0] index, // sent after GET_INDEX
    output reg rx_valid, // 1-clock strobe: rx_byte is new
    output reg [7:0] rx_byte,
    output wire frame_start, // 1-clock strobe: CS went low
    output wire frame_end, // 1-clock strobe: CS went high
    output wire miso_bit
);

// sync three inputs
reg [2:0] sck_r = 3'b000;
reg [2:0] cs_r = 3'b111;
reg [1:0] mosi_r = 2'b00;
always @(posedge clk) begin
    sck_r <= {sck_r[1:0], sck};
    cs_r <= {cs_r[1:0], cs_n};
    mosi_r <= {mosi_r[0], mosi};
end
wire sck_rise = sck_r[1] & ~sck_r[2];
wire sck_fall = ~sck_r[1] & sck_r[2];
wire cs_active = ~cs_r[1];
wire mosi_s = mosi_r[1]; // same dealy as sck_r[1]

assign frame_start = ~cs_r[1] & cs_r[2];
assign frame_end = cs_r[1] & ~cs_r[2];

reg [2:0] bit_cnt;
reg [6:0] rx_shift;
reg [7:0] tx_shift;
reg [7:0] last_rx;
reg byte_done;
reg [1:0] byte_no;
reg is_get_index;
reg [9:0] index_hold;

always @(posedge clk) begin
    rx_valid <= 1'b0;
    if (rst || !cs_active) begin
        bit_cnt <= 3'd0;
        byte_done <= 1'b0;
        byte_no <= 2'd0;
        is_get_index <= 1'b0;
        tx_shift <= status;
        index_hold <= index;
    end else begin
        if (sck_rise) begin
            rx_shift <= {rx_shift[5:0], mosi_s};
             bit_cnt  <= bit_cnt + 1'b1;
                if (bit_cnt == 3'd7) begin
                    rx_byte   <= {rx_shift, mosi_s};
                    last_rx   <= {rx_shift, mosi_s};
                    rx_valid  <= 1'b1;
                    byte_done <= 1'b1;
                    if (byte_no == 2'd0) begin
                        is_get_index <= ({rx_shift, mosi_s} == CMD_GET_INDEX);
                        index_hold   <= index;
                    end
                    if (byte_no != 2'd3) byte_no <= byte_no + 1'b1;
                end
            end
            if (sck_fall) begin
                if (byte_done) begin
                    byte_done <= 1'b0;
                    if (is_get_index && byte_no == 2'd1)
                        tx_shift <= {6'd0, index_hold[9:8]};
                    else if (is_get_index && byte_no == 2'd2)
                        tx_shift <= index_hold[7:0];
                    else
                        tx_shift <= last_rx;
                end else begin
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end
    end

    assign miso_bit = tx_shift[7];
endmodule

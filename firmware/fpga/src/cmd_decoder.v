// turns the Pi's byts into actions readable
//
// one command per each SPI transaction, the first byte is the command code; the counter
// resets every single time CS goes low, so a cut-off command can never confuse the next one.
//
//
// 0x00 NOP - status/echo test
// 0x01 WRITE_POINT idx_hi idx_lo  ch1..ch144 RGB
// 0x02 SET_COUNT n_hi n_lo
// 0x03 SET_RATE cpp_hi cpp_lo  (40 kHz cycles per point)
// 0x04 PLAY  0x05 STOP  0x06 OFF
// 0x07 SHOW idx_hi idx_lo
// 0x08 SET_TRIM ticks (2..12)
// 0x09 TEST mode (0..3)
// 0x0A GET_INDEX (answered by spi_slave)

module cmd_decoder #(
    parameter MAX_POINTS = 680,
    parameter AW = 15
) (
    input wire clk,
    input wire rst,
    input wire frame_start,
    input wire rx_valid,
    input wire [7:0] rx_byte,
    // point ram write point
    output reg ram_we,
    output reg [AW-1:0] ram_waddr,
    output reg [17:0] ram_wdata,
    output reg col_we,
    output reg [9:0] col_waddr,
    output reg [23:0] col_wdata,
    output reg pt_written, // strobe after point is stored
    output reg [9:0] pt_written_idx,
    // control
    output reg cmd_play,
    output reg cmd_stop,
    output reg cmd_off,
    output reg cmd_show,
    output reg [9:0] show_idx,
    output reg cmd_test,
    output reg [1:0] test_value,
    output reg [9:0] count, // points in the loop
    output reg [15:0] rate, // cycles per point, >= 1
    output reg [3:0] trim // bottom board sync offset
);
    localparam [7:0] C_NOP = 8'h00, C_WRITE = 8'h01, C_COUNT = 8'h02,
                     C_RATE = 8'h03, C_PLAY = 8'h04, C_STOP = 8'h05,
                     C_OFF = 8'h06, C_SHOW = 8'h07, C_TRIM = 8'h08,
                     C_TEST = 8'h09;
    localparam [9:0] MAXP_M1 = MAX_POINTS - 1;
    localparam [15:0] MAX_POINTS16 = MAX_POINTS;
    localparam [15:0] DEFAULT_RATE = 16'd6;
    localparam [3:0] DEFAULT_TRIM = 4'd3;

    reg [7:0] cmd;
    reg [7:0] pos;
    reg [7:0] hi;
    reg [9:0] idx;
    reg idx_ok;
    reg [AW-1:0] base;
    reg [5:0] word;
    reg [1:0] sub;
    reg [11:0] pack;
    reg [7:0] red, grn;

    wire [15:0] val16 = {hi, rx_byte};
    wire [5:0] ch6 = {rx_byte[7], rx_byte[4:0]};
    wire [9:0] idx_in = {hi[1:0], rx_byte};
    wire idx_in_ok = (hi[7:2] == 6'd0) && (idx_in <= MAXP_M1);

    always @(posedge clk) begin
        ram_we <= 1'b0;
        col_we <= 1'b0;
        pt_written <= 1'b0;
        cmd_play <= 1'b0;
        cmd_stop <= 1'b0;
        cmd_off <= 1'b0;
        cmd_show <= 1'b0;
        cmd_test <= 1'b0;

        if (rst) begin
            pos <= 8'd0;
            cmd <= C_NOP;
            count <= 10'd1;
            rate <= DEFAULT_RATE;
            trim <= DEFAULT_TRIM;
            show_idx <= 10'd0;
            test_value <= 2'd0;
        end else if (frame_start) begin
            pos <= 8'd0;
        end else if (rx_valid) begin
            if (pos != 8'hFF) pos <= pos + 1'b1;

            if (pos == 8'd0) begin
                // command byte
                cmd <= rx_byte;
                case (rx_byte)
                    C_PLAY: cmd_play <= 1'b1;
                    C_STOP: cmd_stop <= 1'b1;
                    C_OFF: cmd_off <= 1'b1;
                    default: ;
                endcase
            end else begin
                case (cmd)
                    // write_point
                    C_WRITE: begin
                        if (pos == 8'd1) begin
                            hi <= rx_byte;
                        end else if (pos == 8'd2) begin
                            idx    <= idx_in;
                            idx_ok <= idx_in_ok;
                            base   <= ({{(AW-10){1'b0}}, idx_in} << 5) + ({{(AW-10){1'b0}}, idx_in} << 4);
                            word   <= 6'd0;
                            sub    <= 2'd0;
                        end else if (pos <= 8'd146) begin
                            // channl bytes
                            case (sub)
                                2'd0: begin pack[5:0]  <= ch6; sub <= 2'd1; end
                                2'd1: begin pack[11:6] <= ch6; sub <= 2'd2; end
                                default: begin
                                    ram_we    <= idx_ok;
                                    ram_waddr <= base + {{(AW-6){1'b0}}, word};
                                    ram_wdata <= {ch6, pack};
                                    word      <= word + 1'b1;
                                    sub       <= 2'd0;
                                end
                            endcase
                        end else if (pos == 8'd147) begin
                            red <= rx_byte;
                        end else if (pos == 8'd148) begin
                            grn <= rx_byte;
                        end else if (pos == 8'd149) begin
                            col_we <= idx_ok;
                            col_waddr <= idx;
                            col_wdata <= {red, grn, rx_byte};
                            pt_written <= idx_ok;
                            pt_written_idx <= idx;
                        end
                    end
                    // 16 bit setter
                    C_COUNT, C_RATE, C_SHOW: begin
                        if (pos == 8'd1) begin
                            hi <= rx_byte;
                        end else if (pos == 8'd2) begin
                            if (cmd == C_COUNT) begin
                                if (val16 == 16'd0) count <= 10'd1;
                                else if (val16 > MAX_POINTS16) count <= MAX_POINTS16[9:0];
                                else count <= val16[9:0];
                            end else if (cmd == C_RATE) begin
                                rate <= (val16 == 16'd0) ? 16'd1 : val16;
                            end else if (idx_in_ok) begin
                                show_idx <= idx_in;
                                cmd_show <= 1'b1;
                            end
                        end
                    end
                    // 8 bit setter
                    C_TRIM: if (pos == 8'd1) begin
                        if (rx_byte == 8'd2) trim <= 4'd2;
                        else if (rx_byte == 8'd12) trim <= 4'd12;
                        else trim <= rx_byte[3:0];
                    end
                    C_TEST: if (pos == 8'd1) begin
                        test_value <= rx_byte[1:0];
                        cmd_test <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule

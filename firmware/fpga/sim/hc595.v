// Testbench model of one 74AHC595 shift register (made by Claude, test use only).
//
// SER is shifted in on each SRCLK rising edge: the first bit shifted in ends up on QH
// after 8 clocks, the last one on QA. RCLK rising edge copies the shift register to the
// outputs. With /OE high the real outputs float and the 100 k pull-downs read 0.
// q[0] = QA ... q[7] = QH.

module hc595 (
    input  wire       ser,
    input  wire       srclk,
    input  wire       rclk,
    input  wire       oe_n,
    output wire [7:0] q
);
    reg [7:0] sh = 8'h00;
    reg [7:0] st = 8'h00;
    always @(posedge srclk) sh <= {sh[6:0], ser};
    always @(posedge rclk) st <= sh;
    assign q = oe_n ? 8'h00 : st;
endmodule

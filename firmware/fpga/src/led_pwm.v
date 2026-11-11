/* red, green and blue brightness control for each point

8-bit PWM at 27 MHz / 8 / 256 = 13.18359375 kHz, fast enough to give every point its own colour
a point lasts 150 us at 6667 points per second. and slow enough for the mosfets to switch cleanly

in test mode leds step red, green, blue, off at 25% brightness, about 0.6s each so LED wiring can be checked.
*/

module led_pwm (
    input wire clk,
    input wire rst,
    input wire enable, // top board
    input wire test, // test pattern
    input wire [23:0] rgb, // rgb
    output reg led_r,
    output reg led_g,
    output reg led_b
);
    reg [2:0] pre;
    reg [7:0] cnt;
    reg [24:0] slow;

    wire [1:0] phase = slow[24:23];
    wire [7:0] r = test ? ((phase == 2'd0) ? 8'd64 : 8'd0) : rgb[23:16];
    wire [7:0] g = test ? ((phase == 2'd1) ? 8'd64 : 8'd0) : rgb[15:8];
    wire [7:0] b = test ? ((phase == 2'd2) ? 8'd64 : 8'd0) : rgb[7:0];

    always @(posedge clk) begin
        if (rst) begin
            pre <= 3'd0;
            cnt <= 8'd0;
            slow <= 25'd0;
            led_r <= 1'b0;
            led_g <= 1'b0;
            led_b <= 1'b0;
        end else begin
            pre <= pre + 1'b1;
            slow <= slow + 1'b1;
            if (pre == 3'd7) cnt <= cnt + 1'b1;
            led_r <= enable & (cnt < r);
            led_g <= enable & (cnt < g);
            led_b <= enable & (cnt < b);
        end
    end
endmodule

// debouncer for tang nano's s1 button
// ensures that button does not input repeatedly due to bouncing effect
//
// requires button to be pressed for 9.7ms (2^CNT_BITS)
//
// output is only "armed" when the input has been steady after reset
// so if button was wired incorrectly nothing fires at power-up

module debounce #(
    parameter CNT_BITS = 18 // 2^18 / 27 mhz = 9.7 ms
) (
    input  wire clk,
    input  wire rst,
    input  wire din,
    output reg level,
    output reg press
);
    reg [CNT_BITS-1:0] cnt;
    reg armed;

    always @(posedge clk) begin
        press <= 1'b0;
        if (rst) begin
            cnt <= {CNT_BITS{1'b0}};
            level <= 1'b0;
            armed <= 1'b0;
        end else if (din == level) begin
            if (!armed) begin
                cnt <= cnt + 1'b1;
                if (&cnt) armed <= 1'b1;
            end else begin
                cnt <= {CNT_BITS{1'b0}};
            end
        end else begin
            cnt <= cnt + 1'b1;
            if (&cnt) begin
                level <= din;
                cnt <= {CNT_BITS{1'b0}};
                if (armed && din) press <= 1'b1;
            end
        end
    end
endmodule

// clock and power-on reset
//
// Tang Nano has 27 mhz oscillator on pin 4. all
// logic will run from it, no pll needed
//
// 27000000/40000 = 675 ticks per 40khz cycle
// 675 /32 phase steps =  21.09375 ticks per phase step
// >>> 29 steps are 21 ticks long, 10, 21 and 31 are 22 ticks
// this module only makes reset. rst is high from config until
// conunter fills 2^POR_BITS ticks, around 39 ms with default)

module clocks #(
    parameter POR_BITS = 20 // 2^20 /27 mhz = 38.8 ms
) (
    input  wire clk27, //27 mhz clock from tang nano
    output wire clk, //system clock, same as clk27
    output wire rst
);
assign clk = clk27;

// gowin resets flip-flops on power-on, so por_done = 0
// and rst = 1 from very first clock

reg [POR_BITS-1:0] por_cnt = {POR_BITS{1'b0}};
reg                por_done = 1'b0;

always @(posedge clk27) begin
    if (!por_done) begin
        por_cnt <= por_cnt + 1'b1;
        if (&por_cnt) por_done <= 1'b1;
    end
end

assign rst = ~por_done;
endmodule

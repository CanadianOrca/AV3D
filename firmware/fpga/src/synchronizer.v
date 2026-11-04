// two flip-flop synchronizer for signals from outside the FGPA
//
// every input pin that isn't clock by our 27 MHz clock
// goes through this sync before logic uses so a signal
// changing right at clock edge doesn't cause design upset

module synchronizer #(
    parameter W = 1,
    parameter [W-1:0] INIT = {W{1'b0}}
) (
    input  wire clk,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
reg [W-1:0] s1 = INIT;
reg [W-1:0] s2 = INIT;

always @(posedge clk) begin
    s1 <= d;
    s2 <= s1;
end

assign q = s2;
endmodule

// decides, for all 144 channels at once, whether or not it should be on
//
// each channel has a 6 bit setting {on, phase[4:0]}
// a channel's out B (positive leg) is high for the 16 steps
//
// high when ((step-phase) mod 32) < 16
// the result is for step_next, because shift_out sends each pattern one step ahead
//
//
// Test modes (S1 button or TEST command)
// 1: every channel on, phase 0 > all in step easy driver check
// 2: phase = 4 x position in its bank > 8 phases 45 deg apart in each bank
// 3: phase = bank number > tells you which bank is which

module channel_gen #(
    parameter  NCH = 144
) (
    input wire [NCH*6-1:0] ch_cfg, // channel n at [6n +: 6] = {on, phase}
    input wire [4:0] step_next,
    input wire [1:0] test_mode,
    input wire enable, // 0 = shift all zeros
    output wire [NCH-1:0] pattern // bit n = OUT B level for channel n (CH n+1)
);
    genvar n;
    generate
        for (n = 0; n < NCH; n = n + 1) begin : g_ch
        localparam integer PH_BIT = (n % 8) * 4; // 0, 4, ... 28
        localparam integer PH_BANK = n / 8; // 0 .. 17
        wire [5:0] cfg = ch_cfg[6*n +: 6];
        reg [4:0] ph;
        reg on;
        always @* begin
            case (test_mode)
                2'd1: begin ph = 5'd0; on = 1'b1; end
                2'd2: begin ph = PH_BIT[4:0]; on = 1'b1; end
                2'd3: begin ph = PH_BANK[4:0]; on = 1'b1; end
                default: begin ph = cfg[4:0]; on = cfg[5]; end
            endcase
        end
        wire [4:0] diff = step_next - ph;
        assign pattern[n] = enable & on & ~diff[4];
        end
    endgenerate
endmodule

// counts the 32 phase steps of each 40 khz cycle
//
// one cycle = 675 ticks of the 27 mhz clock = exactly 40 khz
//
// it is split into 32 steps, 21 ticks each, except steps 10, 21 and 31 which are 22 ticks
//
// top board (is_top = 1): free runs, and drives SYNC high for steps 0-15
// and low for steps 16-31, so the rising edge marks every cycle
//
// bottom board (is_top = 0): watrches SYNC
// the first edge it sees it will snap the counter straight into place
// after that, every edge measures how off the boards are, annd fixes gently by stalling
// or skipping up to 2 ticks in the quiet part (tick 17) when shift registers are idle
//
// trim = the tick number the counter should read when SYNC edge is seen
// 3 is exact for digital delay, delay can be removed with SET_TRIM

module cycle_timer (
    input wire clk,
    input wire rst,
    input wire is_top,
    input wire sync_in,
    input wire [3:0] trim, // raw SYNC pin (bottom board)
    output reg [4:0] step, // 2..12, default 3
    output reg [4:0] tick, // 0..31
    output wire last_tick, // 0..20 or 0..21 within step
    output wire cycle_start, //final tick of the step
    output reg sync_out, // top board SYNC wave
    output reg sync_ok // top: 1, bottom: sync edges
);

    localparam [4:0] CORR_TICK = 5'd17;

    wire long_step = (step == 5'd10) || (step == 5'd21) || (step == 5'd31);
    wire [4:0] last = long_step ? 5'd21 : 5'd20;
    assign last_tick = (tick == last);
    assign cycle_start = (step == 5'd0) && (tick == 5'd0);

    // SYNC input
    reg s1 = 1'b0, s2 = 1'b0, s3 = 1'b0;
    always @(posedge clk) begin
        s1 <= sync_in;
        s2 <= s1;
        s3 <= s2;
    end
    wire sync_rise = s2 & ~s3;

    wire signed [6:0] err_now = $signed({2'b00, tick}) - $signed({3'b000, trim});
    wire small_err = (step == 5'd0) && (err_now >= -7'sd2) && (err_now <= 7'sd2);

    reg signed [2:0] corr; // pending corrections
    reg locked;
    reg [10:0] sync_age; // ticks since last sync edge

    always @(posedge clk) begin
        if (rst) begin
            step <= 5'd0;
            tick <= 5'd0;
            corr <= 3'sd0;
            locked <= 1'b0;
            sync_age <= 11'd0;
            sync_out <= 1'b0;
            sync_ok <= 1'b0;
        end else begin
            // normal counting
            if (last_tick) begin
                tick <= 5'd0;
                step <= step + 1'b1;
            end else begin
                tick <= tick + 1'b1;
            end

            // gentle corrections (bottom)
            if (!is_top && tick == CORR_TICK && corr != 3'sd0) begin
                if (corr > 3'sd0) begin
                    tick <= tick + 1'b1; // skip a tick
                    corr <= corr - 3'sd1;
                end else begin
                    tick <= CORR_TICK + 5'd1 + {3'b000, (corr == -3'sd1) ? 2'd1 : 2'd2};
                    corr <= 3'sd0; // skip 1 or 2 ticks
                end
            end

            if (is_top) begin
                sync_out <= (step < 5'd16);
                sync_ok <= 1'b1;
                locked <= 1'b0;
                corr <= 3'sd0;
            end else begin
                sync_out <= 1'b0;
                if (sync_rise) begin
                    sync_age <= 11'd0;
                    if (locked && small_err) begin
                        corr <= err_now[2:0]; // gentle correction
                    end else begin
                        // hard lock
                        step <= 5'd0;
                        tick <= {1'b0, trim} + 5'd1; // +1 to get to tick 0 of next step
                        locked <= 1'b1;
                    end
                end else if (sync_age !=11'h7FF) begin
                    sync_age <= sync_age + 1'b1;
                end
                sync_ok <= locked && (sync_age < 11'd1400);
            end
        end
    end
endmodule

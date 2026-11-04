// drives the 18 x 74AHC595 shift registers
//
// every step 8 bits go down 18 DATA lines at once then one RCLK pulse copies them to outputs
// pattern shifted during step s is latched at the start of step s+1
//
// schedule inside one step (u = tick at which pin shows the value)
// u = 0 (RCLK = 1 latch the 9 bits during previous step)
// u = 2k+1 (SRCLK = 0, Data = slot k (k = 0..7))
// u = 2k+2 (SRCLK = 1  rising edge shifts slot k in)
// u = 17..end (idle: SRCLK = 0, DATA = 0  (cycle_timer may stall/skip here))
//
// first bit ends up on QH, last on QA. The PCB has QA as the first channel of the bank

module shift_out #(
    parameter NBANK = 18
) (
    input wire clk,
    input wire rst,
    input wire [4:0] tick,
    input wire last_tick,
    input wire cycle_start,
    input wire [NBANK*8-1:0] pattern, // pattern for the next step from channel gen
    input wire oe_request, // 1 = outputs wanted
    output reg [NBANK-1:0] sr_data,
    output reg sr_clk_a, // SRCLK_A > U10..U18
    output reg sr_clk_b, // SRCLK_B > U19..U27
    output reg sr_latch, // RCLK > all 18
    output wire sr_oe_n // /OE > all 18 (10k pull up on PCB)

);
    reg [NBANK*8-1:0] sbuf;
    reg [1:0]         arm_cnt;
    reg               oe_active = 1'b0;

    wire       shifting = (tick <= 5'd15);
    wire [2:0] slot = tick[3:1]; // ticks 2k and 2k+1 present slot k
    wire [2:0] slot_rev = ~slot; // 7 - slot: slot 0 = QH ... slot 7 = QA

    integer j;
    always @(posedge clk) begin
        if (rst) begin
            sbuf <= {NBANK*8{1'b0}};
            sr_data <= {NBANK{1'b0}};
            sr_clk_a <= 1'b0;
            sr_clk_b <= 1'b0;
            sr_latch <= 1'b0;
            arm_cnt <= 2'b0;
            oe_active <= 1'b0;
        end else begin
            // RCLK high on the first tick of every step
            sr_latch <= last_tick;

            // take a copy of the next pattern at first tick
            if (tick == 5'd0) sbuf <= pattern;

            // SRCLK high on odd ticks 1..15 (pins u = 2, 4, ... 16)\
            sr_clk_a <= shifting & tick[0];
            sr_clk_b <= shifting & tick[0];

            for (j = 0; j < NBANK; j = j + 1) begin
                if (!shifting)
                    sr_data[j] <= 1'b0;
                else if (tick == 5'd0)
                    sr_data[j] <= pattern[8*j + 7]; // slot 0, from channel gen
                else
                    sr_data[j] <= sbuf[8*j + {29'd0, slot_rev}];
            end

            // output enable control
            if (!oe_request) begin
                arm_cnt <= 2'd0;
                oe_active <= 1'b0;
            end else begin
                if (cycle_start && arm_cnt != 2'd2) arm_cnt <= arm_cnt + 1'b1;
                oe_active <= (arm_cnt == 2'd2);
            end
        end
    end

    assign sr_oe_n = ~oe_active;
endmodule

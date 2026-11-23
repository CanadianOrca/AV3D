// led_pwm unit test (made by Claude, test use only).
//
// Measures the duty cycle of each LED output over whole PWM periods (2048 clocks =
// 13.18 kHz), checks enable, and checks the LED test pattern (red, green, blue, off at 25%).
// Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
module tb_led_pwm;
    `include "tb_report.vh"
    reg clk = 0;
    always #18518 clk = ~clk;
    reg rst = 1, enable = 0, test = 0;
    reg [23:0] rgb = 0;
    wire led_r, led_g, led_b;
    led_pwm dut (.clk(clk), .rst(rst), .enable(enable), .test(test), .rgb(rgb),
                 .led_r(led_r), .led_g(led_g), .led_b(led_b));

`ifdef DUMP
    initial begin $dumpfile("build/tb_led_pwm.vcd"); $dumpvars(0, tb_led_pwm); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $fdisplay(out, "PASS %0s", name);
            else begin $fdisplay(out, "FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // count high clocks of each output over n PWM periods
    integer hr, hg, hb, toggles_r;
    reg pr;
    task measure(input integer periods);
        integer i;
        begin
            hr = 0; hg = 0; hb = 0; toggles_r = 0; pr = led_r;
            for (i = 0; i < periods * 2048; i = i + 1) begin
                @(posedge clk); #1;
                hr = hr + led_r; hg = hg + led_g; hb = hb + led_b;
                if (led_r && !pr) toggles_r = toggles_r + 1;
                pr = led_r;
            end
        end
    endtask

    initial begin
        report_open;
        repeat (10) @(posedge clk);
        rst = 0;
        // line the measurement up with the PWM period
        while (!(dut.cnt == 8'd0 && dut.pre == 3'd0)) @(posedge clk);

        rgb = {8'd0, 8'd128, 8'd255};
        measure(2);
        check("enable low: all LEDs off whatever the colour", hr == 0 && hg == 0 && hb == 0);

        enable = 1;
        measure(4);
        $fdisplay(out, "INFO duty over 4 periods: R %0d, G %0d, B %0d of %0d clocks", hr, hg, hb, 4 * 2048);
        check("red 0: always off", hr == 0);
        check("green 128: on 128/256 of the time", hg == 4 * 128 * 8);
        check("blue 255: on 255/256 of the time", hb == 4 * 255 * 8);

        rgb = {8'd1, 8'd64, 8'd200};
        measure(4);
        check("red 1, green 64, blue 200: duty exactly 1/256, 64/256, 200/256",
              hr == 4 * 1 * 8 && hg == 4 * 64 * 8 && hb == 4 * 200 * 8);
        check("one red pulse per 2048 clocks (13.18 kHz PWM)", toggles_r == 4);

        // ---- test pattern: phase from slow[24:23], each about 0.31 s; jump the slow counter
        rgb = 24'd0; test = 1;
        dut.slow = 25'h0000000; measure(2);
        check("test pattern phase 0: red at 25%, green and blue off", hr == 2 * 64 * 8 && hg == 0 && hb == 0);
        dut.slow = 25'h0800000; measure(2);
        check("test pattern phase 1: green at 25%", hg == 2 * 64 * 8 && hr == 0 && hb == 0);
        dut.slow = 25'h1000000; measure(2);
        check("test pattern phase 2: blue at 25%", hb == 2 * 64 * 8 && hr == 0 && hg == 0);
        dut.slow = 25'h1800000; measure(2);
        check("test pattern phase 3: all off", hr == 0 && hg == 0 && hb == 0);
        enable = 0; dut.slow = 25'h0000000; measure(1);
        check("test pattern also needs enable", hr == 0 && hg == 0 && hb == 0);

        $fdisplay(out, "SUMMARY failures=%0d", failures);
        report_close;
        $finish;
    end
endmodule

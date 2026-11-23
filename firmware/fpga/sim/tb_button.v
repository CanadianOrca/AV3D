// S1 button test (made by Claude, test use only), using the real debounce time (BTN_BITS default).
//
// One board (top), S1 pin driven by the testbench. Checks that:
//   - bounce at power-up and short glitches (< 9.7 ms) do not change the test mode
//   - a real 12 ms press steps the test mode 0 -> 1 exactly once
//   - releasing (with bounce) and pressing again steps it 1 -> 2
// Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ns/1ps
module tb_button;
    `include "tb_report.vh"
    reg clk = 0;
    always #18.5185 clk = ~clk;                              // 27 MHz
    reg btn = 0;
    wire [17:0] d; wire ca, cb, l, oe, miso, r, g, b;
    wire sync_w, step_w;
    pulldown(sync_w); pulldown(step_w);
    av3d_top #(.POR_BITS(10)) DUT (.clk27(clk), .btn_s1(btn),
        .sr_data(d), .sr_clk_a(ca), .sr_clk_b(cb), .sr_latch(l), .sr_oe_n(oe),
        .spi_sck(1'b0), .spi_mosi(1'b0), .spi_cs_n(1'b1), .spi_miso(miso),
        .sync_io(sync_w), .step_io(step_w), .led_r(r), .led_g(g), .led_b(b), .id_n(1'b0));

    integer failures = 0, presses = 0, i;
    always @(posedge clk) if (DUT.btn_press) presses = presses + 1;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $fdisplay(out, "PASS %0s", name);
            else begin $fdisplay(out, "FAIL %0s", name); failures = failures + 1; end
        end
    endtask
    task bounce(input integer n);                      // n random edges 20-200 us apart
        for (i = 0; i < n; i = i + 1) begin btn = ~btn; #(20_000 + ($urandom % 180_000)); end
    endtask

`ifdef DUMP
    initial begin $dumpfile("build/tb_button.vcd"); $dumpvars(1, tb_button); end
`endif

    initial begin
        report_open;
        check("debounce time is the production value (BTN_BITS = 18)", DUT.BTN_BITS == 18);
        #(50_000);
        bounce(9); btn = 0;                                 // contact noise around power-up
        #(15_000_000);
        check("noise after power-up does not change the test mode", DUT.test_mode == 2'd0 && presses == 0);
        btn = 1; #(5_000_000); btn = 0; #(12_000_000);      // 5 ms glitch
        check("a 5 ms glitch is ignored", DUT.test_mode == 2'd0 && presses == 0);
        btn = 1; #(9_000_000); btn = 0; #(12_000_000);      // 9 ms, just under 9.7 ms
        check("a 9 ms glitch is ignored", DUT.test_mode == 2'd0 && presses == 0);
        bounce(7); btn = 1; #(12_000_000);                  // real press with bounce
        check("a real 12 ms press steps the test mode 0 -> 1", DUT.test_mode == 2'd1 && presses == 1);
        #(20_000_000);
        check("holding the button does not repeat", DUT.test_mode == 2'd1 && presses == 1);
        bounce(6); btn = 0; #(15_000_000);                  // release with bounce
        check("releasing does not step the mode", DUT.test_mode == 2'd1 && presses == 1);
        bounce(5); btn = 1; #(15_000_000);
        check("a second press steps the test mode 1 -> 2", DUT.test_mode == 2'd2 && presses == 2);
        $fdisplay(out, "SUMMARY failures=%0d", failures);
        report_close;
        $finish;
    end
endmodule

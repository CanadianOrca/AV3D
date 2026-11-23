// shift_out unit test (made by Claude, test use only).
//
// A top-board cycle_timer gives the step/tick timing, shift_out drives 18 models of the
// 74AHC595 (hc595.v) exactly as on the PCB (SRCLK_A to U10-U18, SRCLK_B to U19-U27).
// The testbench feeds a different random 144-bit pattern for every step and checks that
// what the shift registers latch is that pattern, with QA = the first channel of each bank.
// Also checks the clock/latch timing and the /OE arming.
// Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
module tb_shift_out;
    `include "tb_report.vh"
    reg clk = 0;
    always #18518 clk = ~clk;
    reg rst = 1;
    reg oe_req = 0;

    wire [4:0] step, tick;
    wire last_tick, cycle_start, sync_out, sync_ok;
    cycle_timer T (.clk(clk), .rst(rst), .is_top(1'b1), .sync_in(1'b0), .trim(4'd3),
                   .step(step), .tick(tick), .last_tick(last_tick), .cycle_start(cycle_start),
                   .sync_out(sync_out), .sync_ok(sync_ok));

    // the pattern for step s is table[s]; shift_out is given the NEXT step's pattern
    reg [143:0] table_p [0:31];
    wire [4:0] step_next = step + 5'd1;
    wire [143:0] pattern = table_p[step_next];

    wire [17:0] sr_data;
    wire sr_clk_a, sr_clk_b, sr_latch, sr_oe_n;
    shift_out #(.NBANK(18)) dut (.clk(clk), .rst(rst), .tick(tick), .last_tick(last_tick),
        .cycle_start(cycle_start), .pattern(pattern), .oe_request(oe_req),
        .sr_data(sr_data), .sr_clk_a(sr_clk_a), .sr_clk_b(sr_clk_b), .sr_latch(sr_latch), .sr_oe_n(sr_oe_n));

    // 18 shift registers; outputs read with /OE forced low so the latched value is visible
    wire [143:0] q_raw, q_pins;
    genvar k;
    generate for (k = 0; k < 18; k = k + 1) begin : g_sr
        hc595 raw (.ser(sr_data[k]), .srclk(k < 9 ? sr_clk_a : sr_clk_b), .rclk(sr_latch), .oe_n(1'b0),    .q(q_raw[8*k +: 8]));
        hc595 pin (.ser(sr_data[k]), .srclk(k < 9 ? sr_clk_a : sr_clk_b), .rclk(sr_latch), .oe_n(sr_oe_n), .q(q_pins[8*k +: 8]));
    end endgenerate

`ifdef DUMP
    initial begin $dumpfile("build/tb_shift_out.vcd"); $dumpvars(0, tb_shift_out); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $fdisplay(out, "PASS %0s", name);
            else begin $fdisplay(out, "FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // ---- latched data: at each RCLK the registers must hold the pattern of the step that starts
    integer latches = 0, latch_bad = 0, check_on = 0;
    always @(posedge sr_latch) begin
        #1000;
        if (check_on) begin
            latches = latches + 1;
            if (q_raw !== table_p[step]) latch_bad = latch_bad + 1;
        end
    end

    // ---- timing inside each step
    integer clk_edges_a = 0, clk_edges_b = 0, step_clk_bad = 0, idle_bad = 0, latch_pos_bad = 0, tk;
    reg pa = 0, pb = 0;
    always @(posedge clk) if (!rst && check_on) begin
        // edges seen on the pins this tick (pins change one clock after the tick that set them)
        if (sr_clk_a && !pa) clk_edges_a = clk_edges_a + 1;
        if (sr_clk_b && !pb) clk_edges_b = clk_edges_b + 1;
        pa = sr_clk_a; pb = sr_clk_b;
        // pins during the idle part of a step (u >= 17, i.e. tick >= 17 here) must be quiet
        if (tick >= 5'd17 && (sr_clk_a || sr_clk_b || sr_data != 18'd0)) idle_bad = idle_bad + 1;
        // RCLK must only be high in the first tick of a step
        if (sr_latch && tick != 5'd0) latch_pos_bad = latch_pos_bad + 1;
        if (last_tick) begin
            if (clk_edges_a != 8 || clk_edges_b != 8) step_clk_bad = step_clk_bad + 1;
            clk_edges_a = 0; clk_edges_b = 0;
        end
    end

    integer s, n, cycles, t_req, t_on;
    reg ok;
    initial begin
        report_open;
        for (s = 0; s < 32; s = s + 1) table_p[s] = {$random, $random, $random, $random, $random};
        repeat (20) @(posedge clk);
        rst = 0;
        check("/OE is high (drivers off) after reset", sr_oe_n === 1'b1);
        // first cycle fills the registers; then check every latch for 20 cycles
        repeat (2) @(posedge cycle_start);
        check_on = 1;
        repeat (20) @(posedge cycle_start);
        check_on = 0;
        $fdisplay(out, "INFO %0d latches checked", latches);
        check("every latched 144-bit pattern equals the pattern for that step", latch_bad == 0 && latches >= 600);
        check("8 SRCLK pulses per step on both clock lines", step_clk_bad == 0);
        check("SRCLK and DATA quiet in the idle part of the step (where sync corrections happen)", idle_bad == 0);
        check("RCLK only in the first tick of a step", latch_pos_bad == 0);

        // ---- bit order: one channel at a time
        ok = 1;
        for (n = 0; n < 144; n = n + 9) begin
            for (s = 0; s < 32; s = s + 1) table_p[s] = 144'd0;
            for (s = 0; s < 32; s = s + 1) table_p[s][n] = 1'b1;
            repeat (2) @(posedge cycle_start);
            #1000;
            if (q_raw !== (144'd1 << n)) ok = 0;
        end
        check("pattern bit n lands on bank n/8, output Q[n%8] (QA = first channel of a bank)", ok);
        for (s = 0; s < 32; s = s + 1) table_p[s] = 144'd0;
        for (s = 0; s < 32; s = s + 1) table_p[s][8*3] = 1'b1;     // CH25 = bank 4 QA
        repeat (2) @(posedge cycle_start); #1000;
        check("CH25 drives U13 (bank 4) QA", g_sr[3].raw.st == 8'b0000_0001 && q_raw[24] == 1'b1);
        for (s = 0; s < 32; s = s + 1) table_p[s] = 144'd0;
        for (s = 0; s < 32; s = s + 1) table_p[s][8*17 + 7] = 1'b1; // CH144 = bank 18 QH
        repeat (2) @(posedge cycle_start); #1000;
        check("CH144 drives U27 (bank 18) QH, clocked by SRCLK_B", g_sr[17].raw.st == 8'b1000_0000);

        // ---- /OE arming: requested mid-cycle, drivers only come on after two cycle starts
        for (s = 0; s < 32; s = s + 1) table_p[s] = {$random, $random, $random, $random, $random};
        @(posedge clk); while (step != 5'd12) @(posedge clk);
        oe_req = 1; t_req = 0; cycles = 0;
        while (sr_oe_n) begin
            @(posedge clk); if (cycle_start) cycles = cycles + 1;
        end
        check("/OE goes low only after the 2nd cycle start (registers hold real data first)", cycles == 2);
        @(posedge cycle_start); #1000;
        check("with /OE low the outputs show the latched pattern", q_pins === table_p[step]);
        @(posedge clk); while (step != 5'd7) @(posedge clk);
        oe_req = 0;
        @(posedge clk); #1000;
        check("/OE goes high on the first clock after the request is dropped", sr_oe_n === 1'b1);
        check("outputs read 0 with /OE high (pull-downs)", q_pins === 144'd0);

        $fdisplay(out, "SUMMARY failures=%0d", failures);
        report_close;
        $finish;
    end
endmodule

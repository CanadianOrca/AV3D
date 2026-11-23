// Two-board system test (made by Claude, test use only).
//
// Builds a top board and a bottom board from the real av3d_top, wires them together the
// way the PCBs are (SYNC, STEP with the FPGA pull-downs), drives them from a model of the
// Pi's SPI, and models all 36 shift registers (hc595.v). Every latched output of all
// 144 channels on both boards is compared with the stored point that should be playing.
//
// Parameter PPM = how much faster the bottom board's crystal runs (+) or slower (-).
// run_sims.py runs it at +200 and -200 ppm (real crystals are within about +-50 ppm).
//
// Prints one PASS/FAIL line per check and "SUMMARY failures=N" at the end.

`timescale 1ps/1ps
module tb_system;
    parameter real PPM = 200.0;

    // ------------------------------------------------------------ clocks
    reg clk_t = 0, clk_b = 0;
    always #18518 clk_t = ~clk_t;                         // 27.000 MHz
    real hb;
    initial hb = 18518.5 * (1.0 - PPM * 1e-6);
    always #(hb) clk_b = ~clk_b;

    // ------------------------------------------------------------ the two boards
    reg sck = 0, mosi = 0, cs_t = 1, cs_b = 1;
    wire miso;
    wire sync_w, step_w;
    pulldown(sync_w);
    pulldown(step_w);                                     // PULL_MODE=DOWN in av3d.cst

    wire [17:0] d_t, d_b;
    wire ca_t, cb_t, l_t, oe_t, ca_b, cb_b, l_b, oe_b;
    wire r_t, g_t, b_t, r_b, g_b, b_b;
    av3d_top #(.POR_BITS(10), .BTN_BITS(4)) TOP (.clk27(clk_t), .btn_s1(1'b0),
        .sr_data(d_t), .sr_clk_a(ca_t), .sr_clk_b(cb_t), .sr_latch(l_t), .sr_oe_n(oe_t),
        .spi_sck(sck), .spi_mosi(mosi), .spi_cs_n(cs_t), .spi_miso(miso),
        .sync_io(sync_w), .step_io(step_w), .led_r(r_t), .led_g(g_t), .led_b(b_t), .id_n(1'b0));
    av3d_top #(.POR_BITS(10), .BTN_BITS(4)) BOT (.clk27(clk_b), .btn_s1(1'b0),
        .sr_data(d_b), .sr_clk_a(ca_b), .sr_clk_b(cb_b), .sr_latch(l_b), .sr_oe_n(oe_b),
        .spi_sck(sck), .spi_mosi(mosi), .spi_cs_n(cs_b), .spi_miso(miso),
        .sync_io(sync_w), .step_io(step_w), .led_r(r_b), .led_g(g_b), .led_b(b_b), .id_n(1'b1));

    wire [143:0] q_t, q_b;
    genvar k;
    generate for (k = 0; k < 18; k = k + 1) begin : g
        hc595 st (.ser(d_t[k]), .srclk(k < 9 ? ca_t : cb_t), .rclk(l_t), .oe_n(oe_t), .q(q_t[8*k +: 8]));
        hc595 sb (.ser(d_b[k]), .srclk(k < 9 ? ca_b : cb_b), .rclk(l_b), .oe_n(oe_b), .q(q_b[8*k +: 8]));
    end endgenerate

`ifdef DUMP
    initial begin $dumpfile("build/tb_system.vcd"); $dumpvars(1, tb_system); end
`endif

    // ------------------------------------------------------------ results
    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // ------------------------------------------------------------ SPI master, mode 0
    integer half = 125000;                                // 4 MHz
    reg [7:0] rx;
    task xfer(input [7:0] tx);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                mosi = tx[i]; #(half); sck = 1; rx = {rx[6:0], miso}; #(half); sck = 0;
            end
        end
    endtask
    task both_cs; begin cs_t = 0; cs_b = 0; #(half*2); end endtask
    task csh;     begin #(half*2); cs_t = 1; cs_b = 1; #(half*4); end endtask

    // stored points in the testbench: cfg[p][ch] = {on, phase}, rgb[p]
    reg [5:0]  cfg [0:1023][0:143];
    reg [23:0] rgb [0:1023];

    task write_point(input [9:0] p);
        integer c;
        begin
            both_cs; xfer(8'h01); xfer({6'd0, p[9:8]}); xfer(p[7:0]);
            for (c = 0; c < 144; c = c + 1) xfer({cfg[p][c][5], 2'b00, cfg[p][c][4:0]});
            xfer(rgb[p][23:16]); xfer(rgb[p][15:8]); xfer(rgb[p][7:0]);
            csh;
        end
    endtask
    // starts a WRITE_POINT with different data and cuts it off after n channel bytes
    task write_point_cut(input [9:0] p, input integer n);
        integer c;
        begin
            both_cs; xfer(8'h01); xfer({6'd0, p[9:8]}); xfer(p[7:0]);
            for (c = 0; c < n; c = c + 1) xfer({1'b1, 2'b00, c[4:0]});
            csh;
        end
    endtask
    task cmd8(input [7:0] c, input [7:0] v);   begin both_cs; xfer(c); xfer(v); csh; end endtask
    task cmd16(input [7:0] c, input [15:0] v); begin both_cs; xfer(c); xfer(v[15:8]); xfer(v[7:0]); csh; end endtask
    task cmd_both(input [7:0] c);              begin both_cs; xfer(c); csh; end endtask
    task cmd_one(input which_top, input [7:0] c);
        begin
            if (which_top) cs_t = 0; else cs_b = 0;
            #(half*2); xfer(c); csh;
        end
    endtask

    function [17:0] word_of(input integer p, input integer w);
        word_of = {cfg[p][3*w+2], cfg[p][3*w+1], cfg[p][3*w]};
    endfunction
    function point_in_ram(input integer p);   // both boards hold point p exactly
        integer w;
        begin
            point_in_ram = (TOP.u_ram.cmem[p] === rgb[p]) && (BOT.u_ram.cmem[p] === rgb[p]);
            for (w = 0; w < 48; w = w + 1)
                if (TOP.u_ram.mem[48*p + w] !== word_of(p, w) || BOT.u_ram.mem[48*p + w] !== word_of(p, w))
                    point_in_ram = 1'b0;
        end
    endfunction

    // ------------------------------------------------------------ continuous checkers
    // 1. outputs: at every latch, each enabled board's 144 outputs must match the point
    //    that was active when that pattern was generated
    integer errs_t = 0, errs_b = 0, latches_t = 0, latches_b = 0;
    reg [9:0] idx_now_t = 0, idx_now_b = 0;
    reg [4:0] stp_t, stp_b;
    integer c2;
    reg expv;
    always @(posedge l_t) begin
        #1000;
        stp_t = TOP.u_timer.step;
        if (!oe_t && TOP.outputs_on && TOP.test_mode == 2'd0) begin
            for (c2 = 0; c2 < 144; c2 = c2 + 1) begin
                expv = cfg[idx_now_t][c2][5] & ~(((stp_t - cfg[idx_now_t][c2][4:0]) >> 4) & 1);
                if (q_t[c2] !== expv) errs_t = errs_t + 1;
            end
            latches_t = latches_t + 1;
        end
        idx_now_t = TOP.u_player.cur_idx;
    end
    always @(posedge l_b) begin
        #1000;
        stp_b = BOT.u_timer.step;
        if (!oe_b && BOT.outputs_on && BOT.test_mode == 2'd0) begin
            for (c2 = 0; c2 < 144; c2 = c2 + 1) begin
                expv = cfg[idx_now_b][c2][5] & ~(((stp_b - cfg[idx_now_b][c2][4:0]) >> 4) & 1);
                if (q_b[c2] !== expv) errs_b = errs_b + 1;
            end
            latches_b = latches_b + 1;
        end
        idx_now_b = BOT.u_player.cur_idx;
    end

    // 2. both boards driving in PLAY must hold the same point (sampled mid-cycle)
    integer cycles_both = 0, idx_mismatch = 0;
    always @(posedge clk_t)
        if (TOP.u_player.playing && BOT.u_player.playing && !oe_t && !oe_b
            && TOP.u_timer.step == 5'd15 && TOP.u_timer.tick == 5'd0) begin
            cycles_both = cycles_both + 1;
            if (TOP.u_player.cur_idx !== BOT.u_player.cur_idx) idx_mismatch = idx_mismatch + 1;
        end

    // 3. sync: count hard relocks and gentle corrections on the bottom board
    integer hard = 0, soft_pos = 0, soft_neg = 0;
    always @(posedge clk_b)
        if (!BOT.rst && BOT.u_timer.sync_rise) begin
            if (BOT.u_timer.locked && BOT.u_timer.small_err) begin
                if (BOT.u_timer.err_now > 0) soft_pos = soft_pos + 1;
                if (BOT.u_timer.err_now < 0) soft_neg = soft_neg + 1;
            end else hard = hard + 1;
        end

    // 4. latch-to-latch skew between the boards at step 0
    realtime t_top0 = 0;
    real skew, skew_max = -1e9, skew_min = 1e9;
    integer nskew = 0;
    always @(posedge l_t) if (TOP.u_timer.step == 0) t_top0 = $realtime;
    always @(posedge l_b)
        if (BOT.u_timer.step == 0 && BOT.u_timer.locked && t_top0 > 0 && !oe_b) begin
            skew = ($realtime - t_top0) / 1000.0;
            if (skew > 12500) skew = skew - 25000;
            nskew = nskew + 1;
            if (nskew > 5) begin
                if (skew > skew_max) skew_max = skew;
                if (skew < skew_min) skew_min = skew;
            end
        end

    // ------------------------------------------------------------ the test sequence
    integer p, c, w, hard0, oe_b_on_during_loss, t;
    reg ok;
    initial begin
        for (p = 0; p < 1024; p = p + 1) begin
            for (c = 0; c < 144; c = c + 1) cfg[p][c] = {($random & 3) != 0, 5'($random)};
            rgb[p] = $random;
        end

        // ---- start-up
        #(200_000_000);                                   // 200 us, past the shortened POR
        check("board roles: ID jumper picks top and bottom", TOP.is_top && !BOT.is_top);
        check("outputs off after power-up (/OE high on both boards)", oe_t && oe_b);

        // ---- point memory
        for (p = 0; p < 5; p = p + 1) write_point(p);
        write_point(260);
        #(5_000_000);
        ok = 1;
        for (p = 0; p < 5; p = p + 1) ok = ok && point_in_ram(p);
        check("WRITE_POINT stores points 0-4 on both boards", ok);
        check("points above 255 keep their own colour (point 260 vs point 4)", point_in_ram(260) && point_in_ram(4));

        // ---- an upload cut off part-way must not change the stored point
        write_point_cut(10'd2, 30);
        #(5_000_000);
        check("cut-off WRITE_POINT leaves the stored point unchanged", point_in_ram(2));
        for (c = 0; c < 144; c = c + 1) cfg[3][c] = {($random & 3) != 0, 5'($random)};
        rgb[3] = $random;
        write_point(3);
        #(5_000_000);
        check("a complete rewrite after a cut-off one is stored correctly", point_in_ram(3));

        // ---- SET_TRIM must stay inside 2..12
        cmd8(8'h08, 8'd1);   #(1_000_000); check("SET_TRIM 1 clamps to 2", TOP.trim == 4'd2 && BOT.trim == 4'd2);
        cmd8(8'h08, 8'd255); #(1_000_000); check("SET_TRIM 255 clamps to 12", BOT.trim == 4'd12);
        cmd8(8'h08, 8'd16);  #(1_000_000); check("SET_TRIM 16 clamps to 12", BOT.trim == 4'd12);
        cmd8(8'h08, 8'd7);   #(1_000_000); check("SET_TRIM 7 is kept", BOT.trim == 4'd7);
        cmd8(8'h08, 8'd3);   #(1_000_000); check("SET_TRIM back to the default 3", BOT.trim == 4'd3);

        // ---- status byte at 1 MHz (top): 101, sync_ok, test, outputs, playing, is_top
        half = 500000; cs_t = 0; #(half*2); xfer(8'h00); csh; half = 125000;
        check("status byte read back: 1011_0001 (top, idle, synced)", rx == 8'b1011_0001);

        // ---- play, bottom first, for 20 ms (800 cycles)
        cmd16(8'h02, 16'd4);                              // 4 points
        cmd16(8'h03, 16'd2);                              // 2 cycles per point
        cmd_one(1'b0, 8'h04);                             // PLAY bottom
        cmd_one(1'b1, 8'h04);                             // PLAY top
        hard0 = hard;
        #(20_000_000_000);
        check("both boards switched on in PLAY", !oe_t && !oe_b);
        check("every latched output matches its point (top)", errs_t == 0 && latches_t > 1000);
        check("every latched output matches its point (bottom)", errs_b == 0 && latches_b > 1000);
        check("both boards always held the same point", idx_mismatch == 0 && cycles_both > 500);
        check("bottom stayed locked: no hard relock during play", hard == hard0);
        if (PPM > 0) check("bottom (fast crystal) was slowed by gentle corrections", soft_pos > 0);
        else         check("bottom (slow crystal) was sped up by gentle corrections", soft_neg > 0);
        $display("INFO latches top %0d bottom %0d, gentle corrections +%0d -%0d, hard relocks %0d",
                 latches_t, latches_b, soft_pos, soft_neg, hard);
        $display("INFO latch skew bottom - top: %.0f .. %.0f ns over %0d cycles", skew_min, skew_max, nskew);
        check("board-to-board latch skew within 100 ns", skew_max < 100 && skew_min > -100);

        // ---- SYNC cable unplugged for 1 ms during play
        force sync_w = 1'b0;
        #(150_000_000);                                   // 150 us: sync times out after ~52 us
        check("bottom switches its outputs off when SYNC is lost", oe_b && !BOT.sync_ok);
        check("top keeps running when SYNC is lost", !oe_t);
        oe_b_on_during_loss = 0;
        for (t = 0; t < 85; t = t + 1) begin #(10_000_000); if (!oe_b) oe_b_on_during_loss = 1; end
        check("bottom stays off for the whole time SYNC is missing", !oe_b_on_during_loss);
        release sync_w;
        #(3_000_000_000);                                 // 3 ms
        check("bottom switches back on after SYNC returns", !oe_b && BOT.sync_ok);

        // ---- SYNC and STEP both unplugged for 2 ms
        force sync_w = 1'b0; force step_w = 1'b0;
        #(2_000_000_000);
        check("bottom off while both cables are out", oe_b);
        release sync_w; release step_w;
        #(3_000_000_000);
        check("bottom back on after both cables return", !oe_b);
        check("after reconnecting, outputs still match (bottom)", errs_b == 0);
        check("after reconnecting, both boards hold the same point", idx_mismatch == 0);

        // ---- OFF, then PLAY sent to the top board first (bottom misses the first wrap)
        cmd_both(8'h06);
        #(100_000_000);
        check("OFF switches both boards off", oe_t && oe_b);
        cmd_one(1'b1, 8'h04);                             // PLAY top first
        #(300_000_000);
        cmd_one(1'b0, 8'h04);                             // then bottom
        #(5_000_000_000);
        check("PLAY top-first: bottom joins in step (same point when both on)", idx_mismatch == 0 && !oe_b);
        check("PLAY top-first: all outputs still match", errs_t == 0 && errs_b == 0);

        // ---- SHOW one point on both, then OFF
        cmd16(8'h07, 16'd260);
        #(2_000_000_000);
        check("SHOW 260: both boards on and holding point 260",
              !oe_t && !oe_b && TOP.u_player.cur_idx == 10'd260 && BOT.u_player.cur_idx == 10'd260);
        check("SHOW 260: all outputs match", errs_t == 0 && errs_b == 0);
        cmd_both(8'h06);
        #(100_000_000);
        check("OFF again: both boards off", oe_t && oe_b);

        $display("SUMMARY failures=%0d", failures);
        $finish;
    end
endmodule

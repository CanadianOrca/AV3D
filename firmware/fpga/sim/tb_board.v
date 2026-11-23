// Single-board test (made by Claude, test use only).
//
// The whole av3d_top firmware on one TOP board, driven over SPI like the Pi does, with 18
// shift register models on its outputs. Checks the player: point order, the rate (cycles
// per point), the STEP pulses sent to the bottom board, STOP, the two live slots used for
// catching/nudging the bead (SHOW), test patterns, OFF, the STATUS byte and GET_INDEX.
// A second board set as BOTTOM with no SYNC cable checks that it stays silent except for
// test patterns. Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
module tb_board;
    reg clk = 0;
    always #18518 clk = ~clk;                               // 27 MHz (both boards, no sync needed)

    reg sck = 0, mosi = 0, cs_t = 1, cs_l = 1;
    wire miso;
    wire sync_t, step_t, sync_l, step_l;
    pulldown(sync_t); pulldown(step_t); pulldown(sync_l); pulldown(step_l);

    wire [17:0] d_t, d_l;
    wire ca_t, cb_t, l_t, oe_t, ca_l, cb_l, l_l, oe_l;
    wire r_t, g_t, b_t, r_l, g_l, b_l;
    av3d_top #(.POR_BITS(10), .BTN_BITS(4)) TOP (.clk27(clk), .btn_s1(1'b0),
        .sr_data(d_t), .sr_clk_a(ca_t), .sr_clk_b(cb_t), .sr_latch(l_t), .sr_oe_n(oe_t),
        .spi_sck(sck), .spi_mosi(mosi), .spi_cs_n(cs_t), .spi_miso(miso),
        .sync_io(sync_t), .step_io(step_t), .led_r(r_t), .led_g(g_t), .led_b(b_t), .id_n(1'b0));
    av3d_top #(.POR_BITS(10), .BTN_BITS(4)) LONE (.clk27(clk), .btn_s1(1'b0),
        .sr_data(d_l), .sr_clk_a(ca_l), .sr_clk_b(cb_l), .sr_latch(l_l), .sr_oe_n(oe_l),
        .spi_sck(sck), .spi_mosi(mosi), .spi_cs_n(cs_l), .spi_miso(miso),
        .sync_io(sync_l), .step_io(step_l), .led_r(r_l), .led_g(g_l), .led_b(b_l), .id_n(1'b1));

    wire [143:0] q_t, q_l;
    genvar k;
    generate for (k = 0; k < 18; k = k + 1) begin : g
        hc595 st (.ser(d_t[k]), .srclk(k < 9 ? ca_t : cb_t), .rclk(l_t), .oe_n(oe_t), .q(q_t[8*k +: 8]));
        hc595 sl (.ser(d_l[k]), .srclk(k < 9 ? ca_l : cb_l), .rclk(l_l), .oe_n(oe_l), .q(q_l[8*k +: 8]));
    end endgenerate

`ifdef DUMP
    initial begin $dumpfile("build/tb_board.vcd"); $dumpvars(1, tb_board); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // ---------------------------------------------------------------- SPI master (mode 0)
    integer half = 125000;                                  // 4 MHz
    reg [7:0] rx;
    reg [7:0] reply [0:3];
    task xfer(input [7:0] tx);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                mosi = tx[i]; #(half); sck = 1; rx = {rx[6:0], miso}; #(half); sck = 0;
            end
        end
    endtask
    task sel(input lone); begin if (lone) cs_l = 0; else cs_t = 0; #(half * 2); end endtask
    task desel;           begin #(half * 2); cs_t = 1; cs_l = 1; #(half * 4); end endtask

    reg [5:0]  cfg [0:679][0:143];                           // the test's copy of every point
    reg [23:0] rgb [0:679];
    task new_point(input integer p);
        integer c;
        begin
            for (c = 0; c < 144; c = c + 1) cfg[p][c] = {($random & 3) != 0, 5'($random)};
            rgb[p] = $random;
        end
    endtask
    task write_point(input lone, input integer p);
        integer c;
        begin
            sel(lone); xfer(8'h01); xfer(p >> 8); xfer(p & 8'hFF);
            for (c = 0; c < 144; c = c + 1) xfer({cfg[p][c][5], 2'b00, cfg[p][c][4:0]});
            xfer(rgb[p][23:16]); xfer(rgb[p][15:8]); xfer(rgb[p][7:0]);
            desel;
        end
    endtask
    task cmd1(input lone, input [7:0] c);                 begin sel(lone); xfer(c); desel; end endtask
    task cmd2(input lone, input [7:0] c, input [7:0] v);  begin sel(lone); xfer(c); xfer(v); desel; end endtask
    task cmd3(input lone, input [7:0] c, input [15:0] v); begin sel(lone); xfer(c); xfer(v[15:8]); xfer(v[7:0]); desel; end endtask
    task read_status(input lone, output [7:0] s);
        begin half = 500000; sel(lone); xfer(8'h00); s = rx; desel; half = 125000; end
    endtask
    task get_index(output [9:0] idx);
        begin
            half = 500000; sel(0);
            xfer(8'h0A); xfer(8'h00); reply[1] = rx; xfer(8'h00); reply[2] = rx;
            desel; half = 125000;
            idx = {reply[1][1:0], reply[2]};
        end
    endtask

    // ---------------------------------------------------------------- checkers
    // 1. every latched output of the top board equals the point (or test pattern) being played
    integer errs = 0, latches = 0, c2;
    reg [9:0] idx_now = 0;
    reg [1:0] tm_now = 0;
    reg [4:0] stp, ph;
    reg on, expv;
    always @(posedge l_t) begin
        #1000;
        stp = TOP.u_timer.step;
        if (!oe_t && TOP.outputs_on) begin
            for (c2 = 0; c2 < 144; c2 = c2 + 1) begin
                case (tm_now)
                    2'd1: begin ph = 0;              on = 1; end
                    2'd2: begin ph = (c2 % 8) * 4;   on = 1; end
                    2'd3: begin ph = c2 / 8;         on = 1; end
                    default: begin ph = cfg[idx_now][c2][4:0]; on = cfg[idx_now][c2][5]; end
                endcase
                expv = on & (((stp - ph) & 5'h1F) < 16);
                if (q_t[c2] !== expv) errs = errs + 1;
            end
            latches = latches + 1;
        end
        idx_now = TOP.u_player.cur_idx;
        tm_now = TOP.test_mode;
    end

    // 2. point changes: how many 40 kHz cycles each point lasts, and the order
    integer cyc_in_point = 0, seen_changes = 0, wrong_len = 0, wrong_order = 0, expect_len = 3;
    reg [9:0] last_idx = 0;
    reg track = 0;
    always @(posedge clk) if (TOP.u_timer.cycle_start) begin
        if (track) begin
            if (TOP.u_player.cur_idx != last_idx) begin
                if (seen_changes > 0 && cyc_in_point != expect_len) wrong_len = wrong_len + 1;
                if (TOP.u_player.cur_idx != ((last_idx + 1) % TOP.count)) wrong_order = wrong_order + 1;
                seen_changes = seen_changes + 1;
                cyc_in_point = 1;
            end else cyc_in_point = cyc_in_point + 1;
        end
        last_idx = TOP.u_player.cur_idx;
    end

    // 3. STEP pulses: width in clocks, wrap or not
    integer pw = 0, pulses = 0, wraps = 0, bad_width = 0;
    reg was_wrap = 0;
    always @(posedge clk) begin
        if (step_t) begin pw = pw + 1; was_wrap = TOP.u_player.adv_wrap; end
        else if (pw != 0) begin
            pulses = pulses + 1;
            if (was_wrap) begin wraps = wraps + 1; if (pw != 506) bad_width = bad_width + 1; end
            else if (pw != 253) bad_width = bad_width + 1;
            pw = 0;
        end
    end

    // 4. LED colour follows the point
    integer rgb_bad = 0, rgb_checks = 0;
    always @(posedge clk)
        if (track && TOP.u_player.playing && TOP.u_timer.step == 5'd15 && TOP.u_timer.tick == 5'd0) begin
            rgb_checks = rgb_checks + 1;
            if (TOP.u_player.active_rgb !== rgb[TOP.u_player.cur_idx]) rgb_bad = rgb_bad + 1;
        end

    // 5. the lone bottom board must never switch its drivers on outside a test pattern
    //    (/OE follows one clock after the test pattern ends, so look at the mode one clock late)
    integer lone_on = 0;
    reg [1:0] lone_tm_d = 0;
    always @(posedge clk) begin
        if (!oe_l && LONE.test_mode == 2'd0 && lone_tm_d == 2'd0) lone_on = lone_on + 1;
        lone_tm_d = LONE.test_mode;
    end

    // ---------------------------------------------------------------- the test
    integer p, i, frozen, e0;
    reg [7:0] s;
    reg [9:0] idx, idx2;
    reg ok;
    initial begin
        for (p = 0; p < 680; p = p + 1) new_point(p);
        #(200_000_000);                                     // past the shortened power-on reset
        check("board roles: J7 shorted = TOP, open = BOTTOM", TOP.is_top && !LONE.is_top);
        check("drivers off after power-up", oe_t && oe_l);
        read_status(0, s);
        check("STATUS top, idle: 1011_0001", s == 8'b1011_0001);
        read_status(1, s);
        check("STATUS lone bottom, no SYNC: 1010_0000", s == 8'b1010_0000);

        // ---- upload 6 points and play at 3 cycles per point
        for (p = 0; p < 6; p = p + 1) write_point(0, p);
        cmd3(0, 8'h02, 16'd6);
        cmd3(0, 8'h03, 16'd3);
        cmd1(0, 8'h04);
        #(1_000_000_000);                                   // 1 ms to start
        track = 1; e0 = errs;
        #(5_000_000_000);                                   // 5 ms = 200 cycles, 66 points
        track = 0;
        $display("INFO %0d point changes, %0d STEP pulses (%0d wraps), %0d latches", seen_changes, pulses, wraps, latches);
        check("PLAY: drivers on", !oe_t);
        check("points play in order 0,1,2,3,4,5,0,...", wrong_order == 0 && seen_changes >= 60);
        check("rate 3: every point lasts exactly 3 cycles (75 us)", wrong_len == 0);
        check("every latched output matches the point being played", errs == 0 && latches > 5000);
        check("STEP pulses: 12 steps (253 clocks) normally, 24 steps (506) at the wrap to point 0", bad_width == 0 && pulses >= 60);
        check("one wrap pulse per loop of 6 points", wraps * 6 >= pulses - 6 && wraps * 6 <= pulses + 6);
        check("LED colour (active_rgb) always belongs to the point being played", rgb_bad == 0 && rgb_checks > 100);
        read_status(0, s);
        check("STATUS while playing: 1011_0111 (outputs on, playing)", s == 8'b1011_0111);
        get_index(idx);
        check("GET_INDEX returns a point of the loop (0-5)", idx < 6);

        // ---- faster: 1 cycle per point
        cmd3(0, 8'h03, 16'd1);
        #(200_000_000);
        expect_len = 1; seen_changes = 0; wrong_len = 0; wrong_order = 0; track = 1;
        #(1_000_000_000);
        track = 0;
        check("SET_RATE 1 while playing: a new point every cycle, still in order", wrong_len == 0 && wrong_order == 0 && seen_changes >= 35);

        // ---- STOP holds the current point
        cmd1(0, 8'h05);
        #(100_000_000);
        idx = TOP.u_player.cur_idx; frozen = 1;
        for (i = 0; i < 40; i = i + 1) begin #(25_000_000); if (TOP.u_player.cur_idx != idx) frozen = 0; end
        check("STOP: the point stays the same for 1 ms and the drivers stay on", frozen && !oe_t);
        get_index(idx2);
        check("GET_INDEX after STOP returns the held point", idx2 == idx);

        // ---- live slots: write the slot not in use, then SHOW it
        write_point(0, 678); cmd3(0, 8'h07, 16'd678);
        #(200_000_000);
        check("SHOW 678: holding the live point 678", TOP.u_player.cur_idx == 678 && !oe_t);
        write_point(0, 679); cmd3(0, 8'h07, 16'd679);
        #(200_000_000);
        check("SHOW 679: switched to the other live point", TOP.u_player.cur_idx == 679);
        // the Pi does this at 100 Hz; here 10 moves 0.1 ms apart (the slot being rewritten is
        // never the one on show, as in player.py)
        e0 = errs;
        for (i = 0; i < 10; i = i + 1) begin
            new_point(678 + (i % 2)); write_point(0, 678 + (i % 2)); cmd3(0, 8'h07, 678 + (i % 2));
            #(100_000_000);
        end
        #(100_000_000);
        check("10 quick live moves: each switched over, every latched output a whole point (never half old, half new)",
              errs == e0 && TOP.u_player.cur_idx == 679);

        // ---- test patterns
        e0 = errs;
        cmd2(0, 8'h09, 8'd1);
        #(200_000_000);
        check("TEST 1: drivers on with all channels at phase 0, outputs match", !oe_t && TOP.test_mode == 1 && errs == e0);
        cmd2(0, 8'h09, 8'd3);
        #(200_000_000);
        check("TEST 3: phase = bank number, outputs match", TOP.test_mode == 3 && errs == e0);

        // ---- OFF
        cmd1(0, 8'h06);
        #(2_000_000);
        check("OFF: drivers off at once and the test pattern cleared", oe_t && TOP.test_mode == 0);
        read_status(0, s);
        check("STATUS after OFF: 1011_0001", s == 8'b1011_0001);

        // ---- the lone bottom board
        write_point(1, 0);
        cmd3(1, 8'h07, 16'd0);
        cmd1(1, 8'h04);
        #(1_000_000_000);
        check("bottom board without SYNC stays off after SHOW and PLAY", oe_l && lone_on == 0);
        cmd2(1, 8'h09, 8'd1);
        #(200_000_000);
        check("bottom board without SYNC still runs test patterns (bench check)", !oe_l);
        cmd1(1, 8'h06);
        #(2_000_000);
        check("bottom board OFF", oe_l && lone_on == 0);

        $display("SUMMARY failures=%0d", failures);
        $finish;
    end
endmodule

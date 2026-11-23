// cycle_timer unit test (made by Claude, test use only).
//
// One top-board timer and three bottom-board timers listening to its SYNC wave:
//   B0 on the same clock as the top board (checks the exact alignment and SET_TRIM),
//   BF on a clock 200 ppm fast, BS on a clock 200 ppm slow (checks the gentle corrections).
// Checks the 675-tick cycle, the 21/22-tick steps, the SYNC wave, lock, loss of SYNC and
// recovery. Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
module tb_cycle_timer;
    // ---------------------------------------------------------------- clocks
    reg clk_t = 0, clk_f = 0, clk_s = 0;
    always #18518 clk_t = ~clk_t;                          // 27 MHz
    always #18514 clk_f = ~clk_f;                          // about +216 ppm
    always #18522 clk_s = ~clk_s;                          // about -216 ppm
    reg rst = 1;
    reg [3:0] trim = 4'd3;
    reg cut = 0;                                           // 1 = SYNC cable unplugged

    wire [4:0] st_t, tk_t, st_0, tk_0, st_f, tk_f, st_s, tk_s;
    wire lt_t, cs_t, so_t, ok_t, lt_0, cs_0, so_0, ok_0;
    wire lt_f, cs_f, so_f, ok_f, lt_s, cs_s, so_s, ok_s;
    wire sync_w = cut ? 1'b0 : so_t;

    cycle_timer T  (.clk(clk_t), .rst(rst), .is_top(1'b1), .sync_in(1'b0), .trim(4'd3),
                    .step(st_t), .tick(tk_t), .last_tick(lt_t), .cycle_start(cs_t), .sync_out(so_t), .sync_ok(ok_t));
    cycle_timer B0 (.clk(clk_t), .rst(rst), .is_top(1'b0), .sync_in(sync_w), .trim(trim),
                    .step(st_0), .tick(tk_0), .last_tick(lt_0), .cycle_start(cs_0), .sync_out(so_0), .sync_ok(ok_0));
    cycle_timer BF (.clk(clk_f), .rst(rst), .is_top(1'b0), .sync_in(sync_w), .trim(4'd3),
                    .step(st_f), .tick(tk_f), .last_tick(lt_f), .cycle_start(cs_f), .sync_out(so_f), .sync_ok(ok_f));
    cycle_timer BS (.clk(clk_s), .rst(rst), .is_top(1'b0), .sync_in(sync_w), .trim(4'd3),
                    .step(st_s), .tick(tk_s), .last_tick(lt_s), .cycle_start(cs_s), .sync_out(so_s), .sync_ok(ok_s));

`ifdef DUMP
    initial begin $dumpfile("build/tb_cycle_timer.vcd"); $dumpvars(0, tb_cycle_timer); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // position inside the cycle, in ticks (0..674)
    function integer pos(input [4:0] s, input [4:0] t);
        integer extra;
        begin
            extra = (s > 10) + (s > 21);                   // long steps 10 and 21 come before
            pos = 21 * s + extra + t;
        end
    endfunction
    function integer wrapd(input integer d);               // wrap a tick difference to -337..337
        begin
            wrapd = d;
            if (wrapd > 337) wrapd = wrapd - 675;
            if (wrapd < -337) wrapd = wrapd + 675;
        end
    endfunction

    // ---------------------------------------------------------------- top board measurements
    integer since_cs = 0, cyc_len_bad = 0, cycles_t = 0;
    integer step_ticks = 0, step_bad = 0, hi_cnt = 0, hi_bad = 0;
    reg [4:0] prev_st = 0;
    always @(posedge clk_t) if (!rst) begin
        since_cs = since_cs + 1;
        if (so_t) hi_cnt = hi_cnt + 1;
        if (cs_t) begin
            if (cycles_t > 2 && since_cs != 675) cyc_len_bad = cyc_len_bad + 1;
            if (cycles_t > 2 && hi_cnt != 337) hi_bad = hi_bad + 1;
            since_cs = 0; hi_cnt = 0; cycles_t = cycles_t + 1;
        end
        step_ticks = step_ticks + 1;
        if (lt_t) begin
            if (cycles_t > 1 && step_ticks != ((st_t == 10 || st_t == 21 || st_t == 31) ? 22 : 21))
                step_bad = step_bad + 1;
            step_ticks = 0;
        end
    end

    // ---------------------------------------------------------------- bottom board measurements
    integer off0, offf, offs;
    integer max0 = 0, maxf = 0, maxs = 0, measure = 0;
    integer abs_v;
    always @(posedge clk_t) if (measure) begin
        off0 = wrapd(pos(st_0, tk_0) - pos(st_t, tk_t));
        offf = wrapd(pos(st_f, tk_f) - pos(st_t, tk_t));
        offs = wrapd(pos(st_s, tk_s) - pos(st_t, tk_t));
        abs_v = off0 < 0 ? -off0 : off0; if (abs_v > max0) max0 = abs_v;
        abs_v = offf < 0 ? -offf : offf; if (abs_v > maxf) maxf = abs_v;
        abs_v = offs < 0 ? -offs : offs; if (abs_v > maxs) maxs = abs_v;
    end

    // corrections may only change the count at tick 17 (shift registers idle) and by <= 2
    integer odd_f = 0, stall_f = 0, skip_f = 0, odd_s = 0, stall_s = 0, skip_s = 0;
    reg [4:0] ptk_f = 0, ptk_s = 0, pst_f = 0, pst_s = 0;
    always @(posedge clk_f) if (!rst) begin
        if (measure) begin
            if (tk_f == ptk_f && st_f == pst_f) begin stall_f = stall_f + 1; if (tk_f != 17) odd_f = odd_f + 1; end
            else if (st_f == pst_f && tk_f > ptk_f + 1) begin skip_f = skip_f + 1; if (ptk_f != 17 || tk_f > 20) odd_f = odd_f + 1; end
        end
        ptk_f = tk_f; pst_f = st_f;
    end
    always @(posedge clk_s) if (!rst) begin
        if (measure) begin
            if (tk_s == ptk_s && st_s == pst_s) begin stall_s = stall_s + 1; if (tk_s != 17) odd_s = odd_s + 1; end
            else if (st_s == pst_s && tk_s > ptk_s + 1) begin skip_s = skip_s + 1; if (ptk_s != 17 || tk_s > 20) odd_s = odd_s + 1; end
        end
        ptk_s = tk_s; pst_s = st_s;
    end

    // hard relocks (counter snapped into place) on the drifting boards
    integer hard_f = 0, hard_s = 0;
    always @(posedge clk_f) if (!rst && BF.sync_rise && !(BF.locked && BF.small_err)) hard_f = hard_f + 1;
    always @(posedge clk_s) if (!rst && BS.sync_rise && !(BS.locked && BS.small_err)) hard_s = hard_s + 1;

    // time from the last SYNC edge to sync_ok dropping
    integer age_at_drop = -1, age = 0;
    reg ok0_prev = 0;
    always @(posedge clk_t) begin
        age = B0.sync_rise ? 0 : age + 1;
        if (ok0_prev && !ok_0) age_at_drop = age;
        ok0_prev = ok_0;
    end

    integer t0, hf0, hs0, i;
    reg ok;
    initial begin
        repeat (20) @(posedge clk_t);
        rst = 0;
        check("bottom boards report no sync before the first SYNC edge", !ok_0 && !ok_f && !ok_s);
        repeat (20 * 675) @(posedge clk_t);                 // 20 cycles
        check("top board: every cycle is exactly 675 ticks (40.000 kHz at 27 MHz)", cyc_len_bad == 0 && cycles_t >= 19);
        check("top board: steps 10, 21, 31 are 22 ticks, the other 29 are 21", step_bad == 0);
        check("top board: SYNC high for steps 0-15 (337 ticks), low for 16-31 (338)", hi_bad == 0);
        check("top board: sync_ok is always 1", ok_t);
        check("all three bottom boards locked to SYNC", ok_0 && ok_f && ok_s);

        // ---- alignment and drift over 400 cycles (10 ms)
        hf0 = hard_f; hs0 = hard_s;
        measure = 1;
        repeat (400 * 675) @(posedge clk_t);
        measure = 0;
        $display("INFO worst offset vs top: same clock %0d, +200 ppm %0d, -200 ppm %0d ticks", max0, maxf, maxs);
        $display("INFO gentle corrections: fast board %0d stalls, slow board %0d skips", stall_f, skip_s);
        check("same clock, trim 3: bottom counts in exact step with the top board", max0 == 0);
        check("bottom 200 ppm fast stays within 3 ticks (111 ns) of the top", maxf <= 3);
        check("bottom 200 ppm slow stays within 3 ticks (111 ns) of the top", maxs <= 3);
        check("fast bottom is held back by stalls, slow bottom pushed on by skips", stall_f > 0 && skip_s > 0);
        check("no hard relock while SYNC keeps arriving", hard_f == hf0 && hard_s == hs0);
        check("corrections only at tick 17 and never more than 2 ticks", odd_f == 0 && odd_s == 0);

        // ---- SET_TRIM moves the bottom board's position
        trim = 4'd5;
        repeat (5 * 675) @(posedge clk_t);
        measure = 1; max0 = 0; @(posedge clk_t); @(posedge clk_t); measure = 0;
        check("trim 5: bottom runs exactly 2 ticks ahead of the top board", off0 == 2);
        trim = 4'd3;
        repeat (5 * 675) @(posedge clk_t);
        measure = 1; @(posedge clk_t); @(posedge clk_t); measure = 0;
        check("trim back to 3: offset returns to 0", off0 == 0);

        // ---- SYNC lost
        cut = 1;
        repeat (3 * 675) @(posedge clk_t);
        check("SYNC unplugged: sync_ok drops on every bottom board", !ok_0 && !ok_f && !ok_s);
        $display("INFO sync_ok dropped %0d ticks after the last SYNC edge", age_at_drop);
        check("sync_ok drops about 1400 ticks (52 us, ~2 cycles) after the last edge",
              age_at_drop >= 1399 && age_at_drop <= 1402);
        check("top board is not affected", ok_t);
        // leave the cable out a little longer, then plug it back in
        repeat (1000) @(posedge clk_t);
        cut = 0;
        repeat (3 * 675) @(posedge clk_t);
        check("SYNC back: all bottom boards locked again within 3 cycles", ok_0 && ok_f && ok_s);
        measure = 1; max0 = 0; maxf = 0; maxs = 0;
        repeat (50 * 675) @(posedge clk_t);
        measure = 0;
        check("after relocking the offsets are back within limits", max0 == 0 && maxf <= 3 && maxs <= 3);

        $display("SUMMARY failures=%0d", failures);
        $finish;
    end
endmodule

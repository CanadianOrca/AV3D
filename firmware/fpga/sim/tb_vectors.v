// Pi-to-FPGA vector test (made by Claude, test use only).
//
// firmware/pi/tools/make_vectors.py runs the REAL Pi code (PhaseSolver + protocol.py) and
// writes the exact SPI bytes the Pi would send to each board, plus the channel bytes it
// expects for every point. This testbench plays those bytes into a top and a bottom board
// (the real av3d_top, linked by SYNC and STEP) and checks that:
//   - every stored point on both boards is exactly what the Pi code meant,
//   - SET_COUNT / SET_RATE / PLAY from the Pi code start the loop on both boards,
//   - every latched output of all 288 channels matches the Pi's phase for the point playing,
//   - the channels the Pi turned off (bottom CH17, top CH100) never switch,
//   - both boards always play the same point.
// So a mistake on either side (Python or Verilog) shows up here.
//
// Run by run_sims.py:  vvp tb_vectors.vvp +vec=<folder with the vector files>
// Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
`include "params.vh"                                       // N_POINTS, RATE, STREAM_LEN

// plays one *_stream.hex file as SPI transactions (mode 0, 4 MHz)
module stream_master #(parameter TOPFILE = 0) (
    input  wire start,
    output reg  sck = 0,
    output reg  mosi = 0,
    output reg  cs_n = 1,
    output reg  done = 0
);
    reg [8:0] stream [0:`STREAM_LEN-1];
    reg [1023:0] dir;
    integer i, b;
    initial begin
        if (!$value$plusargs("vec=%s", dir)) dir = "vectors";
        if (TOPFILE) $readmemh({dir, "/top_stream.hex"}, stream);
        else         $readmemh({dir, "/bottom_stream.hex"}, stream);
        wait (start);
        for (i = 0; i < `STREAM_LEN && stream[i] !== 9'h1FF; i = i + 1) begin
            if (stream[i] === 9'h100) begin
                #250000; cs_n = 1; #500000;                  // end of transaction
            end else begin
                if (cs_n) begin cs_n = 0; #250000; end
                for (b = 7; b >= 0; b = b - 1) begin
                    mosi = stream[i][b]; #125000; sck = 1; #125000; sck = 0;
                end
            end
        end
        done = 1;
    end
endmodule

module tb_vectors;
    reg clk_t = 0, clk_b = 0;
    always #18518 clk_t = ~clk_t;                          // 27 MHz
    always #18517 clk_b = ~clk_b;                          // bottom crystal about 54 ppm fast

    reg go = 0;
    wire sck_t, mosi_t, cs_t, done_t, sck_b, mosi_b, cs_b, done_b;
    stream_master #(.TOPFILE(1)) PI_T (.start(go), .sck(sck_t), .mosi(mosi_t), .cs_n(cs_t), .done(done_t));
    stream_master #(.TOPFILE(0)) PI_B (.start(go), .sck(sck_b), .mosi(mosi_b), .cs_n(cs_b), .done(done_b));

    wire miso_t, miso_b, sync_w, step_w;
    pulldown(sync_w); pulldown(step_w);
    wire [17:0] d_t, d_b;
    wire ca_t, cb_t, l_t, oe_t, ca_b, cb_b, l_b, oe_b, r_t, g_t, b_t, r_b, g_b, b_b;
    av3d_top #(.POR_BITS(10), .BTN_BITS(4)) TOP (.clk27(clk_t), .btn_s1(1'b0),
        .sr_data(d_t), .sr_clk_a(ca_t), .sr_clk_b(cb_t), .sr_latch(l_t), .sr_oe_n(oe_t),
        .spi_sck(sck_t), .spi_mosi(mosi_t), .spi_cs_n(cs_t), .spi_miso(miso_t),
        .sync_io(sync_w), .step_io(step_w), .led_r(r_t), .led_g(g_t), .led_b(b_t), .id_n(1'b0));
    av3d_top #(.POR_BITS(10), .BTN_BITS(4)) BOT (.clk27(clk_b), .btn_s1(1'b0),
        .sr_data(d_b), .sr_clk_a(ca_b), .sr_clk_b(cb_b), .sr_latch(l_b), .sr_oe_n(oe_b),
        .spi_sck(sck_b), .spi_mosi(mosi_b), .spi_cs_n(cs_b), .spi_miso(miso_b),
        .sync_io(sync_w), .step_io(step_w), .led_r(r_b), .led_g(g_b), .led_b(b_b), .id_n(1'b1));

    wire [143:0] q_t, q_b;
    genvar k;
    generate for (k = 0; k < 18; k = k + 1) begin : g
        hc595 st (.ser(d_t[k]), .srclk(k < 9 ? ca_t : cb_t), .rclk(l_t), .oe_n(oe_t), .q(q_t[8*k +: 8]));
        hc595 sb (.ser(d_b[k]), .srclk(k < 9 ? ca_b : cb_b), .rclk(l_b), .oe_n(oe_b), .q(q_b[8*k +: 8]));
    end endgenerate

`ifdef DUMP
    initial begin $dumpfile("build/tb_vectors.vcd"); $dumpvars(1, tb_vectors); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // expected channel bytes from the Pi code: index (point*2 + board)*144 + channel,
    // board 0 = bottom, 1 = top
    reg [7:0] exp_b [0:`N_POINTS*288-1];
    reg [1023:0] dir;
    initial begin
        if (!$value$plusargs("vec=%s", dir)) dir = "vectors";
        $readmemh({dir, "/expected.hex"}, exp_b);
    end
    function [7:0] ch(input integer p, input integer brd, input integer c);
        ch = exp_b[(p * 2 + brd) * 144 + c];
    endfunction
    function [5:0] six(input [7:0] v); six = {v[7], v[4:0]}; endfunction

    // ---- latched outputs against the Pi's phases (as in tb_system)
    integer errs_t = 0, errs_b = 0, lat_t = 0, lat_b = 0, c2;
    reg [9:0] idx_t = 0, idx_b = 0;
    reg [4:0] stp;
    reg [7:0] v;
    reg expv;
    always @(posedge l_t) begin
        #1000; stp = TOP.u_timer.step;
        if (!oe_t && TOP.u_player.playing && idx_t < `N_POINTS) begin
            for (c2 = 0; c2 < 144; c2 = c2 + 1) begin
                v = ch(idx_t, 1, c2);
                expv = v[7] & (((stp - v[4:0]) & 5'h1F) < 16);
                if (q_t[c2] !== expv) errs_t = errs_t + 1;
            end
            lat_t = lat_t + 1;
        end
        idx_t = TOP.u_player.cur_idx;
    end
    always @(posedge l_b) begin
        #1000; stp = BOT.u_timer.step;
        if (!oe_b && BOT.u_player.playing && idx_b < `N_POINTS) begin
            for (c2 = 0; c2 < 144; c2 = c2 + 1) begin
                v = ch(idx_b, 0, c2);
                expv = v[7] & (((stp - v[4:0]) & 5'h1F) < 16);
                if (q_b[c2] !== expv) errs_b = errs_b + 1;
            end
            lat_b = lat_b + 1;
        end
        idx_b = BOT.u_player.cur_idx;
    end

    // ---- dead channels never switch; both boards on the same point
    integer dead_on = 0, same_checks = 0, idx_mismatch = 0;
    reg [9:0] visited [0:1023];
    integer n_visited = 0;
    always @(posedge clk_t) begin
        if (q_b[16] || q_t[99]) dead_on = dead_on + 1;
        if (TOP.u_player.playing && BOT.u_player.playing && !oe_t && !oe_b
            && TOP.u_timer.step == 5'd15 && TOP.u_timer.tick == 5'd0) begin
            same_checks = same_checks + 1;
            if (TOP.u_player.cur_idx !== BOT.u_player.cur_idx) idx_mismatch = idx_mismatch + 1;
        end
    end

    integer p, w, b, bad_words, bad_col;
    reg [17:0] want;
    initial begin
        $display("INFO vectors: %0d points, rate %0d, %0d stream lines", `N_POINTS, `RATE, `STREAM_LEN);
        #(200_000_000);                                    // past the shortened power-on reset
        go = 1;
        wait (done_t && done_b);
        #(2_000_000);

        // ---- point memory, both boards
        bad_words = 0;
        for (p = 0; p < `N_POINTS; p = p + 1)
            for (w = 0; w < 48; w = w + 1) begin
                want = {six(ch(p, 1, 3*w+2)), six(ch(p, 1, 3*w+1)), six(ch(p, 1, 3*w))};
                if (TOP.u_ram.mem[48*p + w] !== want) bad_words = bad_words + 1;
                want = {six(ch(p, 0, 3*w+2)), six(ch(p, 0, 3*w+1)), six(ch(p, 0, 3*w))};
                if (BOT.u_ram.mem[48*p + w] !== want) bad_words = bad_words + 1;
            end
        check("every stored point on both boards equals the Pi code's channel bytes", bad_words == 0);
        bad_col = 0;
        for (p = 0; p < `N_POINTS; p = p + 1)
            if (TOP.u_ram.cmem[p] !== BOT.u_ram.cmem[p]) bad_col = bad_col + 1;
        check("both boards stored the same colour for every point", bad_col == 0);
        check("SET_COUNT and SET_RATE from the Pi code arrived on both boards",
              TOP.count == `N_POINTS && BOT.count == `N_POINTS && TOP.rate == `RATE && BOT.rate == `RATE);

        // ---- play three whole loops and check every latch (if PLAY reaches the bottom board
        //      just after the top board's wrap, the bottom joins at the next wrap: one loop later)
        repeat (3 * `N_POINTS * `RATE + 8) @(posedge TOP.u_timer.cycle_start);
        $display("INFO latches checked: top %0d, bottom %0d (errors %0d, %0d); same-point checks %0d (mismatches %0d)",
                 lat_t, lat_b, errs_t, errs_b, same_checks, idx_mismatch);
        check("both boards playing with drivers on", TOP.u_player.playing && BOT.u_player.playing && !oe_t && !oe_b);
        check("every latched output of the top board matches the Pi's phase for that point", errs_t == 0 && lat_t > 32 * `N_POINTS);
        check("every latched output of the bottom board matches the Pi's phase for that point", errs_b == 0 && lat_b > 32 * `N_POINTS);
        check("channels the Pi switched off (bottom CH17, top CH100) never switched on", dead_on == 0);
        check("both boards always played the same point", idx_mismatch == 0 && same_checks > `N_POINTS);

        $display("SUMMARY failures=%0d", failures);
        $finish;
    end
endmodule

// cmd_decoder + point_ram unit test (made by Claude, test use only).
//
// Feeds whole commands into cmd_decoder byte by byte (as spi_slave would hand them over,
// one byte every 2 us = 4 MHz SPI) and checks what lands in point_ram and on the control
// outputs: WRITE_POINT packing, index range checks, cut-off commands, and every setter's
// limits. Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
module tb_cmd_decoder;
    reg clk = 0;
    always #18518 clk = ~clk;
    reg rst = 1;
    reg frame_start = 0, rx_valid = 0;
    reg [7:0] rx_byte = 0;

    wire ram_we, col_we, pt_written;
    wire [14:0] ram_waddr;
    wire [17:0] ram_wdata;
    wire [9:0] col_waddr, pt_written_idx;
    wire [23:0] col_wdata;
    wire cmd_play, cmd_stop, cmd_off, cmd_show, cmd_test;
    wire [9:0] show_idx, count;
    wire [15:0] rate;
    wire [3:0] trim;
    wire [1:0] test_value;

    cmd_decoder #(.MAX_POINTS(680), .AW(15)) dut (
        .clk(clk), .rst(rst), .frame_start(frame_start), .rx_valid(rx_valid), .rx_byte(rx_byte),
        .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata),
        .col_we(col_we), .col_waddr(col_waddr), .col_wdata(col_wdata),
        .pt_written(pt_written), .pt_written_idx(pt_written_idx),
        .cmd_play(cmd_play), .cmd_stop(cmd_stop), .cmd_off(cmd_off),
        .cmd_show(cmd_show), .show_idx(show_idx), .cmd_test(cmd_test), .test_value(test_value),
        .count(count), .rate(rate), .trim(trim));

    reg [14:0] raddr = 0; reg [9:0] craddr = 0;
    wire [17:0] rdata; wire [23:0] crdata;
    point_ram #(.AW(15), .CW(10)) ram (.clk(clk), .we(ram_we), .waddr(ram_waddr), .wdata(ram_wdata),
        .raddr(raddr), .rdata(rdata), .cwe(col_we), .cwaddr(col_waddr), .cwdata(col_wdata),
        .craddr(craddr), .crdata(crdata));

`ifdef DUMP
    initial begin $dumpfile("build/tb_cmd_decoder.vcd"); $dumpvars(0, tb_cmd_decoder); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $display("PASS %0s", name);
            else begin $display("FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // ---- strobe counters
    integer n_play = 0, n_stop = 0, n_off = 0, n_show = 0, n_test = 0, n_written = 0, n_we = 0;
    reg [9:0] last_written = 0;
    always @(posedge clk) begin
        if (cmd_play) n_play = n_play + 1;
        if (cmd_stop) n_stop = n_stop + 1;
        if (cmd_off)  n_off  = n_off + 1;
        if (cmd_show) n_show = n_show + 1;
        if (cmd_test) n_test = n_test + 1;
        if (ram_we)   n_we   = n_we + 1;
        if (pt_written) begin n_written = n_written + 1; last_written = pt_written_idx; end
    end
    task clear_counts; begin n_play = 0; n_stop = 0; n_off = 0; n_show = 0; n_test = 0; n_written = 0; n_we = 0; end endtask

    // ---- one byte, then one whole command (bytes in msg[0..len-1])
    reg [7:0] msg [0:199];
    task send_byte(input [7:0] b);
        begin
            @(posedge clk); rx_byte <= b; rx_valid <= 1;
            @(posedge clk); rx_valid <= 0;
            repeat (52) @(posedge clk);                    // 2 us per byte at 4 MHz
        end
    endtask
    task send(input integer len);
        integer i;
        begin
            @(posedge clk); frame_start <= 1; @(posedge clk); frame_start <= 0;
            repeat (10) @(posedge clk);
            for (i = 0; i < len; i = i + 1) send_byte(msg[i]);
            repeat (60) @(posedge clk);                    // CS high time, commit finishes
        end
    endtask

    // ---- the test's own copy of a point
    reg [7:0]  chb [0:143];
    reg [23:0] col;
    task make_point(input integer seed);
        integer c;
        begin
            for (c = 0; c < 144; c = c + 1) chb[c] = $random;   // bits 6..5 random too: must be ignored
            col = $random;
        end
    endtask
    task load_write(input [15:0] idx16);
        integer c;
        begin
            msg[0] = 8'h01; msg[1] = idx16[15:8]; msg[2] = idx16[7:0];
            for (c = 0; c < 144; c = c + 1) msg[3 + c] = chb[c];
            msg[147] = col[23:16]; msg[148] = col[15:8]; msg[149] = col[7:0];
        end
    endtask
    function [5:0] six(input [7:0] b); six = {b[7], b[4:0]}; endfunction

    // read point p back from point_ram and compare with chb/col
    reg [17:0] word_rd;
    task point_matches(input integer p, output ok);
        integer w;
        begin
            ok = 1;
            for (w = 0; w < 48; w = w + 1) begin
                @(posedge clk) raddr <= 48 * p + w;
                @(posedge clk); @(posedge clk);
                if (rdata !== {six(chb[3*w+2]), six(chb[3*w+1]), six(chb[3*w])}) ok = 0;
            end
            @(posedge clk) craddr <= p; @(posedge clk); @(posedge clk);
            if (crdata !== col) ok = 0;
        end
    endtask

    reg ok, ok2;
    reg [7:0] save [0:143];
    reg [23:0] save_col;
    integer c, we0;
    initial begin
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (5) @(posedge clk);
        check("defaults after reset: count 1, rate 6, trim 3", count == 1 && rate == 6 && trim == 3);

        // ---- WRITE_POINT
        clear_counts;
        make_point(1); load_write(16'd5); send(150);
        point_matches(5, ok);
        check("WRITE_POINT 5: 48 words of 3 channels {on, phase} + colour stored", ok);
        check("exactly 48 RAM writes and one 'point written' strobe for index 5", n_we == 48 && n_written == 1 && last_written == 5);
        for (c = 0; c < 144; c = c + 1) save[c] = chb[c]; save_col = col;
        make_point(2); load_write(16'd679); send(150);
        point_matches(679, ok);
        check("WRITE_POINT 679 (the last slot) stored", ok);
        make_point(3); load_write(16'd260); send(150);
        point_matches(260, ok);
        check("WRITE_POINT 260 (index above 255) stored at its own address", ok);

        // ---- bad indexes are refused and change nothing
        clear_counts;
        make_point(4); load_write(16'd680); send(150);
        check("WRITE_POINT 680 (out of range) refused: no RAM writes", n_we == 0 && n_written == 0);
        load_write(16'h0405); send(150);              // high bits set: would alias point 5
        check("WRITE_POINT 0x0405 refused (no alias onto point 5)", n_we == 0 && n_written == 0);
        for (c = 0; c < 144; c = c + 1) chb[c] = save[c]; col = save_col;
        point_matches(5, ok);
        check("point 5 unchanged after the refused writes", ok);

        // ---- a cut-off WRITE_POINT does nothing
        clear_counts;
        make_point(5); load_write(16'd5); send(100);
        check("WRITE_POINT cut off after 100 bytes: nothing written", n_we == 0 && n_written == 0);
        for (c = 0; c < 144; c = c + 1) chb[c] = save[c]; col = save_col;
        point_matches(5, ok);
        check("point 5 still holds its old data", ok);
        // ...and the next command after it is read from its first byte
        msg[0] = 8'h04; send(1);
        check("the command after a cut-off one is decoded normally (PLAY)", n_play == 1);

        // ---- back-to-back points (the next one starts while the last is still being stored)
        make_point(6); load_write(16'd10); send(150);
        for (c = 0; c < 144; c = c + 1) save[c] = chb[c]; save_col = col;
        make_point(7); load_write(16'd11); send(150);
        point_matches(11, ok);
        for (c = 0; c < 144; c = c + 1) chb[c] = save[c]; col = save_col;
        point_matches(10, ok2);
        check("two points sent back to back are both stored correctly", ok && ok2);

        // ---- SET_COUNT limits
        msg[0] = 8'h02; msg[1] = 8'h01; msg[2] = 8'h2C; send(3);
        check("SET_COUNT 300", count == 300);
        msg[1] = 8'h00; msg[2] = 8'h00; send(3);
        check("SET_COUNT 0 becomes 1", count == 1);
        msg[1] = 8'h02; msg[2] = 8'hA8; send(3);
        check("SET_COUNT 680 kept", count == 680);
        msg[1] = 8'h02; msg[2] = 8'hA9; send(3);
        check("SET_COUNT 681 limited to 680", count == 680);
        msg[1] = 8'hFF; msg[2] = 8'hFF; send(3);
        check("SET_COUNT 65535 limited to 680", count == 680);

        // ---- SET_RATE limits
        msg[0] = 8'h03; msg[1] = 8'h00; msg[2] = 8'h00; send(3);
        check("SET_RATE 0 becomes 1", rate == 1);
        msg[1] = 8'hFF; msg[2] = 8'hFF; send(3);
        check("SET_RATE 65535 kept (16 bits)", rate == 16'hFFFF);
        msg[1] = 8'h00; msg[2] = 8'h06; send(3);
        check("SET_RATE 6", rate == 6);

        // ---- SET_TRIM clamps to 2..12
        msg[0] = 8'h08;
        msg[1] = 8'd0;   send(2); ok = (trim == 2);
        msg[1] = 8'd1;   send(2); ok = ok && (trim == 2);
        msg[1] = 8'd2;   send(2); ok = ok && (trim == 2);
        msg[1] = 8'd7;   send(2); ok = ok && (trim == 7);
        msg[1] = 8'd12;  send(2); ok = ok && (trim == 12);
        msg[1] = 8'd13;  send(2); ok = ok && (trim == 12);
        msg[1] = 8'd255; send(2); ok = ok && (trim == 12);
        check("SET_TRIM 0,1,2,7,12,13,255 gives 2,2,2,7,12,12,12", ok);

        // ---- TEST, SHOW, PLAY/STOP/OFF strobes
        clear_counts;
        msg[0] = 8'h09; msg[1] = 8'd2; send(2);
        check("TEST 2: one strobe, value 2", n_test == 1 && test_value == 2);
        msg[1] = 8'd0; send(2);
        check("TEST 0: one strobe, value 0", n_test == 2 && test_value == 0);
        msg[0] = 8'h07; msg[1] = 8'h02; msg[2] = 8'hA6; send(3);
        check("SHOW 678: one strobe, index 678", n_show == 1 && show_idx == 678);
        msg[1] = 8'h02; msg[2] = 8'hA8; send(3);
        check("SHOW 680 (out of range) ignored", n_show == 1 && show_idx == 678);
        msg[0] = 8'h04; send(1); msg[0] = 8'h05; send(1); msg[0] = 8'h06; send(1);
        check("PLAY, STOP, OFF: exactly one strobe each", n_play == 1 && n_stop == 1 && n_off == 1);
        // PLAY with extra bytes after it still counts once
        msg[0] = 8'h04; msg[1] = 8'h04; msg[2] = 8'h04; send(3);
        check("bytes after a 1-byte command are ignored (PLAY 04 04 = one PLAY)", n_play == 2);

        // ---- NOP and unknown commands change nothing
        clear_counts;
        msg[0] = 8'h00; for (c = 1; c < 20; c = c + 1) msg[c] = $random; send(20);
        msg[0] = 8'h55; for (c = 1; c < 20; c = c + 1) msg[c] = 8'h01; send(20);
        check("NOP and an unknown command (0x55) cause no action",
              n_play + n_stop + n_off + n_show + n_test + n_we == 0 && count == 680 && rate == 6 && trim == 12);

        $display("SUMMARY failures=%0d", failures);
        $finish;
    end
endmodule

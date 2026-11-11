/* av3d board firmware top module attaches all modules together

pin nums in av3d.cst
*/

module av3d_top #(
    `include "clocks.v"
    `include "synchronizer.v"
    `include "debounce.v"
    `include "cycle_timer.v"
    `include "spi_slave.v"
    `include "cmd_decoder.v"
    `include "point_ram.v"
    `include "player.v"
    `include "channel_gen.v"
    `include "shift_out.v"
    `include "led_pwm.v"
    parameter POR_BITS = 20, // power on reset (2^20 ticks)
    parameter BTN_BITS = 4 // button debounce
) (
    input  wire        clk27,              // 27 MHz oscillator
    input  wire        btn_s1,             // tnb s1 cycle test
    // 74AHC595 chain
    output wire [17:0] sr_data,            // d .. d18 > ser of u10..u27
    output wire        sr_clk_a,           // scrclk_a > u10.. u18 thru r9
    output wire        sr_clk_b,           // srclk_b > u19.. u27 thr r10
    output wire        sr_latch,           // rclk    > all 18  (thru r11)
    output wire        sr_oe_n,            // /oe     > all 18  (r12 pull-up)
    // spi from the Pi r3... r6
    input  wire        spi_sck,
    input  wire        spi_mosi,
    input  wire        spi_cs_n,           // CE0 or CE1, picked by the J8
    output wire        spi_miso,           // tri-stated unles spi_cs_n is low
    // board-to-board r7, r8
    inout  wire        sync_io,
    inout  wire        step_io,
    // led mosfet gates r13... r15
    output wire        led_r,
    output wire        led_g,
    output wire        led_b,
    // board ID jumper J7
    input  wire        id_n
);
    localparam NCH        = 144;
    localparam NBANK      = 18;
    localparam MAX_POINTS = 680;
    localparam AW         = 15;

    // clock, reset, board role
    wire clk, rst;
    clocks #(.POR_BITS(POR_BITS)) u_clocks (.clk27(clk27), .clk(clk), .rst(rst));

    wire id_s;
    synchronizer #(.W(1), .INIT(1'b1)) u_id_sync (.clk(clk), .d(id_n), .q(id_s));
    reg is_top = 1'b0; // 0 = bottom listen only
    always @(posedge clk) if (rst) is_top <= ~id_s;

    // button s1
    wire btn_s, btn_press;
    synchronizer #(.W(1)) u_btn_sync (.clk(clk), .d(btn_s1), .q(btn_s));
    debounce #(.CNT_BITS(BTN_BITS)) u_btn (
        .clk(clk), .rst(rst), .level(), .press(btn_press));

    // 40 khz cycle and sync
    wire [4:0] step, tick;
    wire       last_tick, cycle_start, sync_out, sync_ok;
    wire [3:0] trim;
    cycle_timer u_timer (
        .clk(clk), .rst(rst), .is_top(is_top), .sync_in(sync_io), .trim(trim),
        .step(step), .tick(tick), .last_tick(last_tick), .cycle_start(cycle_start),
        .sync_out(sync_out), .sync_ok(sync_ok));
    assign sync_io = is_top ? sync_out : 1'bz;

    wire step_start = (tick == 5'd0);
    wire swap_tick  = (step == 5'd30) && last_tick;

    // SPI and commands
    wire rx_valid, frame_start, frame_end, miso_bit;
    wire [7:0] rx_byte;
    wire [9:0] cur_idx;
    wire playing, showing;
    reg [1:0] test_mode;
    wire outputs_on = showing || (test_mode != 2'd0);
    wire [7:0] status = {3'b101, sync_ok, (test_mode != 2'd0), outputs_on, playing, is_top};

    spi_slave u_spi (
        .clk(clk), .rst(rst), .sck(spi_sck), .mosi(spi_mosi), .cs_n(spi_cs_n),
        .status(status), .index(cur_idx), .rx_valid(rx_valid), .rx_byte(rx_byte),
        .frame_start(frame_start), .frame_end(frame_end), .miso_bit(miso_bit));
    assign spi_miso = spi_cs_n ? 1'bz : miso_bit;

    wire ram_we, col_we, pt_written;
    wire [AW-1:0] ram_waddr;
    wire [17:0] ram_wdata;
    wire [9:0] col_waddr, pt_written_idx;
    wire [23:0] col_wdata;
    wire cmd_play, cmd_stop, cmd_off, cmd_show, cmd_test;
    wire [9:0] show_idx, count;
    wire [15:0] rate;
    wire [1:0] test_value;

    cmd_decoder #(.MAX_POINTS(MAX_POINTS), .AW(AW)) u_dec (
        .clk(clk), .rst(rst), .frame_start(frame_start),
        .rx_valid(rx_valid), .rx_byte(rx_byte),
        .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata),
        .col_we(col_we), .col_waddr(col_waddr), .col_wdata(col_wdata),
        .pt_written(pt_written), .pt_written_idx(pt_written_idx),
        .cmd_play(cmd_play), .cmd_stop(cmd_stop), .cmd_off(cmd_off),
        .cmd_show(cmd_show), .show_idx(show_idx),
        .cmd_test(cmd_test), .test_value(test_value),
        .count(count), .rate(rate), .trim(trim));

        // test mode: s1 steps 0, 1, 2, 3, 0; test sets it, anything else clears it
        always @(posedge clk) begin
            if (rst) test_mode <= 2'd0;
             else if (cmd_test) test_mode <= test_value;
             else if (cmd_off | cmd_play | cmd_show) test_mode <= 2'd0;
             else if (btn_press) test_mode <= test_mode + 1'b1;
        end

        // shape memory
        wire [AW-1:0] ram_raddr;
        wire [17:0] ram_rdata;
        wire [9:0] col_raddr;
        wire [23:0] col_rdata;
        point_ram #(.AW(AW), .CW(10)) u_ram (
            .clk(clk),
            .we(ram_we), .waddr(ram_waddr), .wdata(ram_wdata),
            .raddr(ram_raddr), .rdata(ram_rdata),
            .cw(col_we), .cwaddr(col_waddr), .cwdata(col_wdata),
            .craddr(col_raddr), .crdata(col_rdata));

        // player
        wire [NCH*6-1:0] active_cfg;
        wire [23:0] active_rgb;
        wire step_out;
        player #(.NCH(NCH), .MAX_POINTS(MAX_POINTS), .AW(AW)) u_player (
            .clk(clk), .rst(rst), .is_top(is_top),
            .step(step), .step_start(step_start), .cycle_start(cycle_start), .swap_tick(swap_tick),
            .cmd_play(cmd_play), .cmd_stop(cmd_stop), .cmd_off(cmd_off),
            .cmd_show(cmd_show), .show_idx(show_idx),
            .count(count), .rate(rate),
            .pt_written(pt_written), .pt_written_idx(pt_written_idx),
            .step_in(step_io), .step_out(step_out),
            .ram_raddr(ram_raddr), .ram_rdata(ram_rdata),
            .col_raddr(col_raddr), .col_rdata(col_rdata),
            .active_cfg(active_cfg), .active_rgb(active_rgb),
            .playing(playing), .showing(showing), .cur_idx(cur_idx));
        assign step_io = is_top ? step_out : 1'bz;

        // channel > shift registers
        wire [NCH-1:0] pattern;
        channel_gen #(.NCH(NCH)) u_chan (
            .ch_cfg(active_cfg), .step_next(step + 5'd1), .test_mode(test_mode),
        .enable(outputs_on), .pattern(pattern));

        shift_out #(.NBANK(NBANK)) u_shift (
            .clk(clk), .rst(rst), .tick(tick), .last_tick(last_tick),
            .cycle_start(cycle_start), .pattern(pattern), .oe_request(outputs_on),
            .sr_data(sr_data), .sr_clk_a(sr_clk_a), .sr_clk_b(sr_clk_b),
            .sr_latch(sr_latch), .sr_oe_n(sr_oe_n));

        // LEDs (top board only)
        led_pwm u_led (
        .clk(clk), .rst(rst), .enable(is_top && outputs_on), .test(test_mode != 2'd0),
        .rgb(active_rgb), .led_r(led_r), .led_g(led_g), .led_b(led_b));
endmodule

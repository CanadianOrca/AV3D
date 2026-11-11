
/* steps through each stored point and keeps both boards in sync
*also, I just learned about multi-line comments in verilog, cool!
i thought they wouldn't work hmmm
if a reviewer is actually reading this, coffee is lifesaver*

two buffers of 144 channel settings
active: what channel_gen is playing rn
shadow: the next point, read from block RAM ahead of actual execution

modes: off (output disabled), HOLD (play one point), play (loop 0..count-1)

keep boards together
i dont wanna explain this read rest of code to figure out what i'm doing ig :)
*/

module player #(
    parameter NCH = 144,
    parameter MAX_POINTS = 680,
    parameter AW = 15
) (
    input wire clk,
    input wire rst,
    input wire is_top,
    // timing from cycle_timer
    input wire [4:0] step,
    input wire step_start,
    input wire cycle_start,
    input wire swap_tick,
    // commands from cmd_decoder and settings
    input wire cmd_play,
    input wire cmd_stop,
    input wire cmd_off,
    input wire cmd_show,
    input wire [9:0] show_idx,
    input wire [9:0] count,
    input wire [15:0] rate,
    input wire pt_written,
    input wire [9:0] pt_written_idx,
    // step wire
    input wire step_in,
    output reg step_out,
    // block ram read port
    output reg [AW-1:0] ram_raddr,
    input wire [17:0] ram_rdata,
    output reg [9:0] col_raddr,
    input wire [23:0] col_rdata,
    // what to play
    output reg [NCH*6-1:0] active_cfg,
    output reg [23:0] active_rgb,
    output wire playing,
    output wire showing,
    output reg [9:0] cur_idx
);
    localparam [1:0] M_OFF = 2'd0, M_HOLD = 2'd1, M_PLAY = 2'd2;
    localparam integer WORDS = NCH/3; // 48 words point
    localparam [4:0] PULSE_FIRST = 5'd2;
    localparam [4:0] PULSE_LAST_NORMAL = 5'd13; // 12 steps
    localparam [4:0] PULSE_LAST_WRAP = 5'd25; // 24 steps
    localparam [4:0] WRAP_TH = 5'd18; // >= steps high = wrap
    localparam [4:0] MIN_TH = 5'd6; // shorter = glitch, ignored

    reg [1:0] mode;
    assign playing = (mode == M_PLAY);
    assign showing = (mode != M_OFF);

    function [9:0] next_of;
        input [9:0] i;
        input [9:0] n;
        reg [10:0] p1;
        begin
            p1 = {1'b0, i} + 11'd1;
            next_of = (p1 >= {1'b0, n}) ? 10'd0 : p1[9:0];
        end
    endfunction

    function [AW-1:0] base_of; // i*48
        input [9:0] i;
        begin
            base_of = ({{(AW-10){1'b0}}, i} << 5) + ({{(AW-10){1'b0}}, i} << 4);
        end
    endfunction

    wire [9:0] next_seq = next_of(cur_idx, count);

    // shdw buff n prefetch
    reg [NCH*6-1:0] shadow_cfg;
    reg [23:0] shadow_rgb;
    reg [9:0] shadow_idx;
    reg shadow_valid;
    reg [9:0] want_idx; // point in shadow

    reg pf_busy;
    reg [9:0] pf_idx;
    reg [5:0] pf_issued; // addresses sent
    reg [5:0] pf_got; // word received
    reg issue_v; //ram radd_r is valid
    reg data_v; //ram rdata is real

    wire need_fetch = !shadow_valid || (shadow_idx != want_idx);
    wire write_hits_shadow = pt_written && (pt_written_idx == shadow_idx);
    wire write_hits_pf = pt_written && (pt_written_idx == pf_idx);

    // advnace control
    reg do_adv; // swap at this cycle's swap tick
    reg adv_wrap;
    reg [9:0] adv_target;
    reg start_req; // top: PLAY received
    reg hold_pending; // SHOW received
    reg [15:0] cyc_cnt;

    // STEP pulse decoder (bottom)
    reg st1, st2, st3;
    wire st_rise = st2 & ~st3;
    wire st_fall = ~st2 & st3;
    reg in_pulse, decided;
    reg [4:0] pw_cnt;
    // still high after 18 steps = wrap, ended after 6-17 steps normal
    wire wrap_decide = in_pulse && !decided && (pw_cnt >= WRAP_TH);
    wire norm_decide = st_fall && in_pulse && !decided && !wrap_decide && (pw_cnt >= MIN_TH);
    wire follow_now = wrap_decide || norm_decide;
    wire follow_wrap = wrap_decide;

    always @(posedge clk) begin
        if (rst) begin
            mode <= M_OFF;
            cur_idx <= 10'd0;
            active_cfg <= {NCH*6{1'b0}};
            active_rgb <= 24'd0;
            shadow_cfg <= {NCH*6{1'b0}};
            shadow_rgb <= 24'd0;
            shadow_idx <= 10'd0;
            shadow_valid <= 1'b0;
            want_idx <= 10'd0;
            pf_busy      <= 1'b0;
            pf_idx       <= 10'd0;
            pf_issued    <= 6'd0;
            pf_got       <= 6'd0;
            issue_v      <= 1'b0;
            data_v       <= 1'b0;
            ram_raddr    <= {AW{1'b0}};
            col_raddr    <= 10'd0;
            do_adv       <= 1'b0;
            adv_wrap     <= 1'b0;
            adv_target   <= 10'd0;
            start_req    <= 1'b0;
            hold_pending <= 1'b0;
            cyc_cnt      <= 16'd0;
            step_out     <= 1'b0;
            st1 <= 1'b0; st2 <= 1'b0; st3 <= 1'b0;
            in_pulse     <= 1'b0;
            decided      <= 1'b0;
             pw_cnt       <= 5'd0;
        end else begin
            // prefetch read 48 words + colour into shadow
            data_v <= issue_v; // ram output is 1 lock behind
            if (pf_busy && (pf_idx != want_idx || write_hits_pf)) begin
                pf_busy <= 1'b0; // wrong point or rewritten: restart
                issue_v <= 1'b0;
                data_v <= 1'b0;
            end else if (!pf_busy && need_fetch) begin
                pf_busy <= 1'b1;
                pf_idx <= want_idx;
                ram_raddr <= base_of(want_idx);
                col_raddr <= want_idx;
                pf_issued <= 6'd1;
                pf_got <= 6'd0;
                issue_v <= 1'b1;
                data_v <= 1'b0;
                shadow_valid <= 1'b0;
            end else if (pf_busy) begin
                if (pf_issued != WORDS[5:0]) begin
                    ram_raddr <= ram_raddr + 1'b1;
                    pf_issued <= pf_issued + 1'b1;
                    issue_v <= 1'b1;
                end else begin
                    issue_v <= 1'b0;
                end
                if (data_v) begin
                    // shift in from top, after 48 words word 0 sits at 17:0
                    shadow_cfg <= {ram_rdata, shadow_cfg[NCH*6-1:18]};
                    pf_got <= pf_got + 1'b1;
                    if (pf_got == WORDS[5:0] - 6'd1) begin
                        pf_busy <= 1'b0;
                        issue_v <= 1'b0;
                        shadow_valid <= 1'b1;
                        shadow_idx <= pf_idx;
                        shadow_rgb <= col_rdata;
                    end
                end
            end
            if (write_hits_shadow) shadow_valid <= 1'b0;

            // bottom board: decode STEP pulses
            st1 <= step_in; st2 <= st1; st3 <= st2;
            if (st_rise) begin
                in_pulse <= 1'b1;
                decided <= 1'b0;
                pw_cnt <= 5'd0;
            end else if (in_pulse && step_start && pw_cnt != 5'd31) begin
                pw_cnt <= pw_cnt + 1'b1;
            end
            if (wrap_decide) decided <= 1'b1;
            if (st_fall) in_pulse <= 1'b0;
            if (!is_top && mode == M_PLAY && follow_now) begin
                do_adv <= 1'b1;
                adv_wrap <= follow_now;
                adv_target <= follow_wrap ? 10'd0 : next_seq;
                want_idx <= follow_wrap ? 10'd0 : next_seq;
            end

            // top board: decide at start
            if (is_top && mode == M_PLAY && cycle_start) begin
                if (start_req) begin
                    do_adv <= 1'b1;
                    adv_wrap <= 1'b1;
                    adv_target <= 10'd0;
                    want_idx <= 10'd0;
                    start_req <= 1'b0;
                    cyc_cnt <= 16'd0;
                end else if (({1'b0, cyc_cnt} + 17'd1) >= {1'b0, rate}) begin
                    do_adv <= 1'b1;
                    adv_wrap <= (next_seq == 10'd0);
                    adv_target <= next_seq;
                    want_idx <= next_seq;
                    cyc_cnt <= 16'd0;
                end else begin
                    cyc_cnt <= cyc_cnt + 1'b1;
                end
            end

            step_out <= is_top && do_adv && (step >= PULSE_FIRST) && (step <= (adv_wrap ? PULSE_LAST_WRAP : PULSE_LAST_NORMAL));

            // swap at last tick of 30
            if (swap_tick) begin
                if (do_adv) begin
                    if (shadow_valid && !pf_busy && shadow_idx == adv_target) begin
                        active_cfg <= shadow_cfg;
                        active_rgb <= shadow_rgb;
                        cur_idx <= adv_target;
                        want_idx <= (mode == M_PLAY) ? next_of(adv_target, count) : adv_target;
                    end
                    do_adv <= 1'b0;
                end else if (hold_pending && shadow_valid && !pf_busy && shadow_idx == want_idx) begin
                    active_cfg <= shadow_cfg;
                    active_rgb <= shadow_rgb;
                    cur_idx <= want_idx;
                    hold_pending <= 1'b0;
                end
            end

            // commands written last so wins
            if (cmd_off) begin
                mode <= M_OFF;
                do_adv <= 1'b0;
                hold_pending <= 1'b0;
                start_req <= 1'b0;
            end
            if (cmd_stop && mode == M_PLAY) begin
                mode <= M_HOLD;
                start_req <= 1'b0;
            end
            if (cmd_play) begin
                mode <= M_PLAY;
                want_idx <= 10'd0;
                hold_pending <= 1'b0;
                start_req <= is_top;
                do_adv <= 1'b0;
                cyc_cnt <= 16'd0;
            end
            if (cmd_show) begin
                mode <= M_HOLD;
                want_idx <= show_idx;
                hold_pending <= 1'b1;
                shadow_valid <= 1'b0;
                do_adv <= 1'b0;
                start_req <= 1'b0;
            end
        end
    end
endmodule

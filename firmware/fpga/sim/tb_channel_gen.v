// channel_gen unit test (made by Claude, test use only).
//
// Checks every channel at every one of the 32 steps against the rule in channel_gen.v:
//   OUT B is high when ((step - phase) mod 32) < 16, only if the channel's on bit is set
// in normal mode and in the three test modes, with enable on and off.
// Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ns/1ps
module tb_channel_gen;
    `include "tb_report.vh"
    localparam NCH = 144;

    reg  [NCH*6-1:0] cfg;
    reg  [4:0]       step_next;
    reg  [1:0]       test_mode;
    reg              enable;
    wire [NCH-1:0]   pattern;

    channel_gen #(.NCH(NCH)) dut (.ch_cfg(cfg), .step_next(step_next), .test_mode(test_mode),
                                  .enable(enable), .pattern(pattern));

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $fdisplay(out, "PASS %0s", name);
            else begin $fdisplay(out, "FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // reference model of one channel
    function expect_bit(input integer n, input [4:0] s, input [1:0] tm, input en);
        reg [4:0] ph; reg on; reg [4:0] diff;
        begin
            case (tm)
                2'd1: begin ph = 5'd0;              on = 1'b1; end
                2'd2: begin ph = (n % 8) * 4;       on = 1'b1; end
                2'd3: begin ph = n / 8;             on = 1'b1; end
                default: begin ph = cfg[6*n +: 5];  on = cfg[6*n + 5]; end
            endcase
            diff = s - ph;
            expect_bit = en & on & (diff < 5'd16);
        end
    endfunction

    integer n, s, tm, trial, errs, highs, c;
    reg ok;
    initial begin
        report_open;
        // ---- random settings, every step, every mode, enable on and off
        errs = 0;
        for (trial = 0; trial < 20; trial = trial + 1) begin
            for (n = 0; n < NCH; n = n + 1) cfg[6*n +: 6] = $random;
            for (tm = 0; tm < 4; tm = tm + 1)
                for (s = 0; s < 32; s = s + 1)
                    for (c = 0; c < 2; c = c + 1) begin
                        step_next = s; test_mode = tm; enable = c; #1;
                        for (n = 0; n < NCH; n = n + 1)
                            if (pattern[n] !== expect_bit(n, s, tm, c)) errs = errs + 1;
                    end
        end
        check("all 144 channels follow the phase rule (20 random settings x 32 steps x 4 modes)", errs == 0);

        // ---- every channel is high for exactly 16 of 32 steps and goes high at step = phase
        test_mode = 0; enable = 1; ok = 1;
        for (n = 0; n < NCH; n = n + 1) cfg[6*n +: 6] = {1'b1, n[4:0]};
        for (n = 0; n < NCH; n = n + 1) begin
            highs = 0;
            for (s = 0; s < 32; s = s + 1) begin
                step_next = s; #1;
                if (pattern[n]) highs = highs + 1;
                if (s == (n % 32) && !pattern[n]) ok = 0;                 // first high step
                if (s == ((n + 31) % 32) && pattern[n]) ok = 0;           // low just before
            end
            if (highs != 16) ok = 0;
        end
        check("50% duty: each channel is high 16 of 32 steps, rising at step = phase", ok);

        // ---- the on bit: cleared = always low
        for (n = 0; n < NCH; n = n + 1) cfg[6*n +: 6] = {1'b0, 5'($random)};
        ok = 1;
        for (s = 0; s < 32; s = s + 1) begin step_next = s; #1; if (pattern !== {NCH{1'b0}}) ok = 0; end
        check("a channel with its on bit clear never switches", ok);

        // ---- enable low = all zeros, even in a test mode
        enable = 0; ok = 1;
        for (tm = 0; tm < 4; tm = tm + 1)
            for (s = 0; s < 32; s = s + 1) begin
                test_mode = tm; step_next = s; #1; if (pattern !== {NCH{1'b0}}) ok = 0;
            end
        check("enable low gives all zeros in every mode", ok);

        // ---- channel n is read from bits [6n +: 6] (CH1 = bits 5:0)
        enable = 1; test_mode = 0; cfg = {NCH*6{1'b0}};
        cfg[5:0] = 6'b100000;                     // CH1 on, phase 0
        step_next = 0; #1;
        check("CH1 is bits 5:0 of the point (pattern bit 0)", pattern == {{NCH-1{1'b0}}, 1'b1});
        cfg = {NCH*6{1'b0}}; cfg[6*143 +: 6] = 6'b100000; #1;
        check("CH144 is bits 863:858 (pattern bit 143)", pattern == {1'b1, {NCH-1{1'b0}}});

        // ---- test mode 2: inside a bank the 8 channels are 4 steps (45 deg) apart
        test_mode = 2; step_next = 0; #1;
        // phases 0,4,..,28: at step 0 the channels with phase 0, 20, 24, 28 are in their high half
        check("test mode 2 at step 0: QA, QF, QG, QH high in every bank",
              pattern == {18{8'b1110_0001}});
        step_next = 4; #1;
        check("test mode 2 at step 4: QA, QB, QG, QH high in every bank", pattern == {18{8'b1100_0011}});
        // ---- test mode 3: bank b uses phase b
        test_mode = 3; step_next = 17; #1;
        ok = 1;
        for (n = 0; n < NCH; n = n + 1) if (pattern[n] !== ((n / 8) >= 2)) ok = 0;
        check("test mode 3 at step 17: banks 3-18 high, banks 1-2 low", ok);

        $fdisplay(out, "SUMMARY failures=%0d", failures);
        report_close;
        $finish;
    end
endmodule

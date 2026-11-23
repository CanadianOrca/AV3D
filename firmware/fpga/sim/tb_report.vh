// Result output shared by the testbenches (made by Claude, test use only).
//
// Every PASS/FAIL/INFO/SUMMARY line goes to the screen AND, when run_sims.py passes
// +report=<file>, to that file. The file is closed before $finish, so the results are
// on disk even if the simulator's screen output gets lost (seen with some Windows
// Icarus builds when the output goes through a pipe).
//
// Use inside a testbench module:  `include "tb_report.vh"
//   report_open;   first statement of the main initial block
//   $fdisplay(out, "PASS ...");   instead of $display
//   report_close;  just before $finish

integer rep_file = 0;
integer out = 32'h0000_0001;               // 1 = the screen (stdout)
reg [8*1024-1:0] rep_path;

task report_open;
    begin
        if ($value$plusargs("report=%s", rep_path)) begin
            rep_file = $fopen(rep_path);   // multichannel descriptor
            if (rep_file != 0) out = rep_file | 1;
            else $display("WARNING cannot open the report file");
        end
    end
endtask

task report_close;
    begin
        if (rep_file != 0) begin
            $fflush(rep_file);
            $fclose(rep_file);
        end
        rep_file = 0;
        out = 1;
    end
endtask

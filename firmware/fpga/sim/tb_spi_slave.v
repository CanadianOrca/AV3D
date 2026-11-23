// spi_slave unit test (made by Claude, test use only).
//
// A model of the Pi's SPI master (mode 0, MSB first) talks to spi_slave:
//   writes at 4 MHz (every byte must arrive), reads at 1 MHz (status, echo, GET_INDEX),
//   CS framing strobes, and a transaction cut off half-way through a byte.
// Prints PASS/FAIL lines and "SUMMARY failures=N".

`timescale 1ps/1ps
module tb_spi_slave;
    `include "tb_report.vh"
    reg clk = 0;
    always #18518 clk = ~clk;
    reg rst = 1;
    reg sck = 0, mosi = 0, cs_n = 1;
    reg [7:0] status = 8'hB5;
    reg [9:0] index = 10'h2A5;
    wire rx_valid, frame_start, frame_end, miso_bit;
    wire [7:0] rx_byte;
    spi_slave dut (.clk(clk), .rst(rst), .sck(sck), .mosi(mosi), .cs_n(cs_n), .status(status),
                   .index(index), .rx_valid(rx_valid), .rx_byte(rx_byte), .frame_start(frame_start),
                   .frame_end(frame_end), .miso_bit(miso_bit));
    wire miso = cs_n ? 1'bz : miso_bit;                    // as in top.v

`ifdef DUMP
    initial begin $dumpfile("build/tb_spi_slave.vcd"); $dumpvars(0, tb_spi_slave); end
`endif

    integer failures = 0;
    task check(input [8*120-1:0] name, input ok);
        begin
            if (ok) $fdisplay(out, "PASS %0s", name);
            else begin $fdisplay(out, "FAIL %0s", name); failures = failures + 1; end
        end
    endtask

    // ---- bytes the slave reports
    reg [7:0] got [0:255];
    integer ngot = 0, nstart = 0, nend = 0;
    always @(posedge clk) begin
        if (rx_valid) begin got[ngot] = rx_byte; ngot = ngot + 1; end
        if (frame_start) nstart = nstart + 1;
        if (frame_end) nend = nend + 1;
    end

    // ---- SPI master
    integer half = 125000;                                 // 125 ns = 4 MHz
    reg [7:0] rx;
    reg [7:0] reply [0:255];
    task xfer(input [7:0] tx);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                mosi = tx[i]; #(half); sck = 1; rx = {rx[6:0], miso}; #(half); sck = 0;
            end
        end
    endtask
    task cs_low;  begin cs_n = 0; #(half * 2); end endtask
    task cs_high; begin #(half * 2); cs_n = 1; #(half * 4); end endtask

    reg [7:0] sent [0:255];
    integer i, bad, n;
    initial begin
        report_open;
        repeat (10) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);
        check("MISO is released (high impedance) while CS is high", miso === 1'bz);

        // ---- writes at 4 MHz: every byte arrives, in order
        half = 125000; ngot = 0;
        cs_low;
        for (i = 0; i < 200; i = i + 1) begin sent[i] = $random; xfer(sent[i]); end
        cs_high;
        bad = 0;
        for (i = 0; i < 200; i = i + 1) if (got[i] !== sent[i]) bad = bad + 1;
        check("4 MHz: 200 bytes written, all 200 received correctly", ngot == 200 && bad == 0);
        check("one frame_start and one frame_end per transaction", nstart == 1 && nend == 1);

        // ---- reads at 1 MHz: byte 0 = STATUS, then each byte echoed one byte later
        half = 500000; ngot = 0;
        cs_low;
        for (i = 0; i < 64; i = i + 1) begin
            sent[i] = (i == 0) ? 8'h00 : $random;          // NOP then random payload
            xfer(sent[i]); reply[i] = rx;
        end
        cs_high;
        check("1 MHz: first byte back is the STATUS byte", reply[0] == 8'hB5);
        bad = 0;
        for (i = 1; i < 64; i = i + 1) if (reply[i] !== sent[i - 1]) bad = bad + 1;
        check("1 MHz: every later byte echoes the byte sent one place earlier (63 bytes)", bad == 0);

        // ---- status is sampled fresh for every transaction
        status = 8'hA2;
        cs_low; xfer(8'h00); reply[0] = rx; cs_high;
        check("a new STATUS value shows in the next transaction", reply[0] == 8'hA2);

        // ---- GET_INDEX: index high, index low, captured when the command byte arrives
        index = 10'h2A5;
        cs_low;
        xfer(8'h0A); reply[0] = rx;
        index = 10'h011;                                    // changes after the command byte
        xfer(8'h00); reply[1] = rx;
        xfer(8'h00); reply[2] = rx;
        cs_high;
        check("GET_INDEX replies STATUS, index[9:8], index[7:0]",
              reply[0] == 8'hA2 && reply[1] == 8'h02 && reply[2] == 8'hA5);
        check("GET_INDEX returns the index from when the command arrived (no torn value)", reply[2] == 8'hA5);

        // ---- a transaction cut off after 5 bits must not upset the next one
        ngot = 0;
        cs_low;
        mosi = 1;
        for (i = 0; i < 5; i = i + 1) begin #(half); sck = 1; #(half); sck = 0; end
        cs_high;
        check("a cut-off byte is thrown away (nothing reported)", ngot == 0);
        cs_low; xfer(8'h00); reply[0] = rx; xfer(8'h5C); reply[1] = rx; xfer(8'h00); reply[2] = rx; cs_high;
        check("after a cut-off, the next transaction starts clean (STATUS, then echo)",
              reply[0] == 8'hA2 && reply[1] == 8'h00 && reply[2] == 8'h5C && ngot == 3 && got[1] == 8'h5C);

        // ---- the slowest Pi setting also works for writes
        half = 2_000_000; ngot = 0;                          // 250 kHz
        cs_low; xfer(8'h3C); xfer(8'hC3); cs_high;
        check("250 kHz writes received", ngot == 2 && got[0] == 8'h3C && got[1] == 8'hC3);

        $fdisplay(out, "SUMMARY failures=%0d", failures);
        report_close;
        $finish;
    end
endmodule

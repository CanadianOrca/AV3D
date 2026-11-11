// shape memory in fgpa block ram
//
// memory: 32768 words x 18 bits. A point is 48 words (3 channels per word),
// 680 points use 32640 words, 32 of gw2ar-18 46 block rams.
//
// colour memory: 1024x24 [r,g,b]
//
// written in simple plain verilog, so synthesis turns into block ram by itself
// and is simulatable in icarus. dual port simple, decoder writes, player reads.

module point_ram #(
    parameter AW = 15,
    parameter CW = 10
) (
    input wire clk,
    // phase mem
    input wire we,
    input wire [AW-1:0] waddr,
    input wire [17:0] wdata,
    input wire [AW-1:0] raddr,
    output reg [17:0] rdata,
    // colour mem
    input wire cwe,
    input wire [CW-1:0] cwaddr,
    input wire [23:0] cwdata,
    input wire [CW-1:0] craddr,
    output reg [23:0] crdata
);
    reg [17:0] mem [0:(1<<AW)-1] /* syntheses syn_ramstyle = "block_ram" */;
    reg [23:0] cmem [0:(1<<CW)-1] /* syntheses syn_ramstyle = "block_ram" */;

`ifdef SIMULATION
    // real block ram powers up as zeros; ensures simulator does the same
    integer i;
    initial begin
        for (i = 0; i < (1<<AW); i = i + 1) mem[i] = 18'b0;
        for (i = 0; i < (1<<CW); i = i + 1) cmem[i] = 24'b0;
    end
`endif

    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end

    always @(posedge clk) begin
        if (cwe) cmem[cwaddr] <= cwdata;
        crdata <= cmem[craddr];
    end
endmodule

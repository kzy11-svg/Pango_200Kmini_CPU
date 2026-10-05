// Compile port for the Vivado DATA_MEM 65536 x 32 byte-write RAM.
module DATA_MEM (
    input wire clka,
    input wire [15:0] addra,
    input wire [31:0] dina,
    input wire [3:0] wea,
    output reg [31:0] douta
);
    reg [31:0] mem [0:65535] /* synthesis syn_ramstyle="block_ram" */;
    initial $readmemh("mem/dram.mem", mem);
    always @(posedge clka) begin
        if (wea[0]) mem[addra][7:0]   <= dina[7:0];
        if (wea[1]) mem[addra][15:8]  <= dina[15:8];
        if (wea[2]) mem[addra][23:16] <= dina[23:16];
        if (wea[3]) mem[addra][31:24] <= dina[31:24];
        // Synchronous read, with explicit write-through on enabled byte lanes.
        douta <= mem[addra];
        if (wea[0]) douta[7:0]   <= dina[7:0];
        if (wea[1]) douta[15:8]  <= dina[15:8];
        if (wea[2]) douta[23:16] <= dina[23:16];
        if (wea[3]) douta[31:24] <= dina[31:24];
    end
endmodule

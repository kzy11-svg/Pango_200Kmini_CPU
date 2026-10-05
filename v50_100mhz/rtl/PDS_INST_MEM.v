// Compile port for the Vivado INST_MEM block-memory-generator instance.
// Preserve the original 16384 x 32 synchronous read latency.
module INST_MEM (
    input wire clka,
    input wire [13:0] addra,
    output reg [31:0] douta
);
    reg [31:0] mem [0:16383] /* synthesis syn_ramstyle="block_ram" */;
    initial $readmemh("mem/irom.mem", mem);
    always @(posedge clka)
        douta <= mem[addra];
endmodule

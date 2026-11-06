// Compile port for the Vivado INST_MEM block-memory-generator instance.
// Preserve the original 16384 x 32 synchronous read latency.
module INST_MEM #(parameter BANK=-1) (
    input wire clka,
    input wire [13:0] addra,
    output reg [31:0] douta,
    output reg [16:0] jal_metadata
);
    reg [31:0] mem [0:16383] /* synthesis syn_ramstyle="block_ram" */;
    reg [16:0] jal_mem[0:16383] /* synthesis syn_ramstyle="block_ram" */;
    initial begin
        $readmemh("mem/irom.mem",mem);
        $readmemh("mem/irom_jal.mem",jal_mem);
    end
    // Simulation harness reloads alternate firmware through this helper.
    // synthesis translate_off
    task refresh_predecode;
        integer j;reg [31:0] ins,target,offset;
        begin
            for(j=0;j<16384;j=j+1)begin
                ins=mem[j];offset={{11{ins[31]}},ins[31],ins[19:12],ins[20],ins[30:21],1'b0};
                target=32'h80000000+j*4+offset;
                jal_mem[j]=(ins[6:0]==7'h6f && target[31:16]==16'h8000 && target[1:0]==0)?{1'b1,target[15:0]}:17'b0;
            end
        end
    endtask
    // synthesis translate_on
    always @(posedge clka)begin
        if(BANK==0)begin
            douta<=mem[{addra[12:0],1'b0}];jal_metadata<=jal_mem[{addra[12:0],1'b0}];
        end else if(BANK==1)begin
            douta<=mem[{addra[12:0],1'b1}];jal_metadata<=jal_mem[{addra[12:0],1'b1}];
        end else begin douta<=mem[addra];jal_metadata<=jal_mem[addra];end
    end
endmodule

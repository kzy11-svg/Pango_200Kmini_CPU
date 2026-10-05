`timescale 1ns / 1ps

`define ADD     5'b00000
`define SUB     5'b00010
`define SLT     5'b00100
`define SLTU    5'b00101
`define AND     5'b01001
`define OR      5'b01010
`define XOR     5'b01011
`define SLL     5'b01110
`define SRL     5'b01111
`define SRA     5'b10000
`define SRC0    5'b10001
`define SRC1    5'b10010

`define MUL     5'b10011
`define MULH    5'b10100
`define MULHSU  5'b10101
`define MULHU   5'b10110
`define DIV     5'b10111
`define DIVU    5'b11000
`define REM     5'b11001
`define REMU    5'b11010

module ALU (
    input       [31:0] alu_src0,
    input       [31:0] alu_src1,
    input       [ 4:0] alu_op,
    output reg  [31:0] alu_res
);

    wire [4:0] shamt = alu_src1[4:0];

    always @(*) begin
        case (alu_op)
            `ADD:    alu_res = alu_src0 + alu_src1;
            `SUB:    alu_res = alu_src0 - alu_src1;
            `SLT:    alu_res = ($signed(alu_src0) < $signed(alu_src1)) ? 32'd1 : 32'd0;
            `SLTU:   alu_res = (alu_src0 < alu_src1) ? 32'd1 : 32'd0;
            `AND:    alu_res = alu_src0 & alu_src1;
            `OR:     alu_res = alu_src0 | alu_src1;
            `XOR:    alu_res = alu_src0 ^ alu_src1;
            `SLL:    alu_res = alu_src0 << shamt;
            `SRL:    alu_res = alu_src0 >> shamt;
            `SRA:    alu_res = $signed(alu_src0) >>> shamt;
            `SRC0:   alu_res = alu_src0;
            `SRC1:   alu_res = alu_src1;

            default: alu_res = 32'h0;
        endcase
    end

endmodule

// Targeted instruction subset: sext.h and zext.h only, not full Zbb.
// Unimplemented extension encodings must remain illegal.
module ZBB_DECODE(input [31:0] inst, output reg [4:0] zbb_op);
 always @* begin
  zbb_op=0;
  if(inst[6:0]==7'h13 && inst[14:12]==3'd1 && inst[31:20]==12'h605)
   zbb_op=12; // sext.h
  else if(inst[6:0]==7'h33 && inst[14:12]==3'd4 &&
          inst[31:25]==7'h04 && inst[24:20]==0)
   zbb_op=13; // zext.h, RV32 encoding
 end
endmodule
module ZBB_ALU(input [31:0] src0,src1,input [4:0] op,output reg [31:0] result);
 always @* begin
  case(op)
   12:result={{16{src0[15]}},src0[15:0]};
   13:result={16'b0,src0[15:0]};
   default:result=0;
  endcase
 end
endmodule

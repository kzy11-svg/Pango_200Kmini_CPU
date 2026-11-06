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

module ALU #(parameter EXTERNAL_COMPARE_INPUTS=0, parameter EARLY_SHIFT_CONTROL=0) (
    input       [31:0] alu_src0,
    input       [31:0] alu_src1,
    input       [ 4:0] alu_op,
    output reg  [31:0] alu_res,
    input [31:0] compare_src0,compare_src1,
    input [31:0] shift_src_i,
    input [4:0] shift_amount_i,
    input shift_left_i,shift_arithmetic_i,
    output wire [31:0] add_result,
    output wire less_signed,less_unsigned,
    output reg [31:0] noncompare_result
);

    wire [31:0] compare_a=EXTERNAL_COMPARE_INPUTS?compare_src0:alu_src0;
    wire [31:0] compare_b=EXTERNAL_COMPARE_INPUTS?compare_src1:alu_src1;
    assign add_result=alu_src0+alu_src1;
    wire [32:0] compare_difference={1'b0,compare_a}+{1'b0,~compare_b}+33'd1;
    assign less_unsigned=!compare_difference[32];
    assign less_signed=(compare_a[31]!=compare_b[31])?compare_a[31]:less_unsigned;
    wire [4:0] shamt = EARLY_SHIFT_CONTROL?shift_amount_i:alu_src1[4:0];
    wire [31:0] shift_source=EARLY_SHIFT_CONTROL?shift_src_i:alu_src0;
    wire shift_arithmetic=EARLY_SHIFT_CONTROL?shift_arithmetic_i:(alu_op==`SRA);
    // One right barrel shifter handles SLL, SRL and SRA. Reversing wires
    // before and after a right shift implements the left-shift operation.
    wire shift_left = EARLY_SHIFT_CONTROL?shift_left_i:(alu_op==`SLL);
    wire [31:0] reversed_src, shift_input, reversed_result, shift_result;
    wire signed [32:0] shift_extended, shifted;
    genvar shift_bit;
    generate for (shift_bit=0; shift_bit<32; shift_bit=shift_bit+1) begin:shift_reverse
        assign reversed_src[shift_bit] = shift_source[31-shift_bit];
        assign reversed_result[shift_bit] = shifted[31-shift_bit];
    end endgenerate
    assign shift_input = shift_left ? reversed_src : shift_source;
    assign shift_extended = {shift_arithmetic && shift_source[31], shift_input};
    assign shifted = shift_extended >>> shamt;
    assign shift_result = shift_left ? reversed_result : shifted[31:0];


    always @(*) begin
        case (alu_op)
            `ADD:    noncompare_result = add_result;
            `SUB:    noncompare_result = compare_difference[31:0];
            `AND:    noncompare_result = alu_src0 & alu_src1;
            `OR:     noncompare_result = alu_src0 | alu_src1;
            `XOR:    noncompare_result = alu_src0 ^ alu_src1;
            `SLL:    noncompare_result = shift_result;
            `SRL:    noncompare_result = shift_result;
            `SRA:    noncompare_result = shift_result;
            `SRC0:   noncompare_result = alu_src0;
            `SRC1:   noncompare_result = alu_src1;

            default: noncompare_result = 32'h0;
        endcase
        case(alu_op)
            `SLT: alu_res={31'b0,less_signed};
            `SLTU: alu_res={31'b0,less_unsigned};
            default: alu_res=noncompare_result;
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

`timescale 1ns / 1ps
//============================================================================
// DIV_UNIT  -  输入寄存版迭代除法器
//  - 接口与原模块完全一致 (start/busy/done/result 握手不变)
//  - start 拍只锁存 src0/src1/op; 所有基于操作数的判断 (除零/溢出/取绝对值)
//    推迟到 S_PREP 拍用 *寄存值* 进行, 从而把深组合输入 alu_src0_ex 移出关键路径
//  - 每次除法比原来多 1 拍 (除法本就 30+ 拍, 可忽略)
//============================================================================
module DIV_UNIT (
    input         clk,
    input         rst,
    input         start,
    input  [4:0]  op,
    input  [31:0] src0,
    input  [31:0] src1,
    output reg        busy,
    output reg        done,
    output reg [31:0] result
);
    localparam [4:0] OP_DIV  = 5'b10111;
    localparam [4:0] OP_DIVU = 5'b11000;
    localparam [4:0] OP_REM  = 5'b11001;
    localparam [4:0] OP_REMU = 5'b11010;

    localparam [1:0] S_IDLE = 2'd0, S_PREP = 2'd1, S_CALC = 2'd2;

    reg  [1:0]  state;
    reg  [4:0]  op_r;
    reg  [31:0] src0_r, src1_r;          // 新增: 锁存的原始操作数
    reg  [5:0]  count;
    reg  [31:0] dividend;
    reg  [31:0] divisor;
    reg  [31:0] quotient;
    reg  [32:0] remainder;
    reg         quot_neg;
    reg         rem_neg;

    // 以下全部基于 *寄存值* src0_r/src1_r/op_r, 输入是寄存器, 路径短
    wire signed_op_r = (op_r == OP_DIV) || (op_r == OP_REM);
    wire [31:0] abs_src0_r = (signed_op_r && src0_r[31]) ? (~src0_r + 32'd1) : src0_r;
    wire [31:0] abs_src1_r = (signed_op_r && src1_r[31]) ? (~src1_r + 32'd1) : src1_r;
    wire div_overflow_r = (src0_r == 32'h8000_0000) && (src1_r == 32'hffff_ffff);

    wire [32:0] rem_shift     = {remainder[31:0], dividend[31]};
    wire [32:0] divisor_ext   = {1'b0, divisor};
    wire        can_sub       = (rem_shift >= divisor_ext);
    wire [32:0] rem_next      = can_sub ? (rem_shift - divisor_ext) : rem_shift;
    wire [31:0] quotient_next = {quotient[30:0], can_sub};

    wire [31:0] signed_quotient  = quot_neg ? (~quotient_next + 32'd1) : quotient_next;
    wire [31:0] signed_remainder = rem_neg  ? (~rem_next[31:0] + 32'd1) : rem_next[31:0];

    always @(posedge clk) begin
        if (rst) begin
            busy<=1'b0; done<=1'b0; result<=32'b0; state<=S_IDLE;
            op_r<=5'b0; src0_r<=32'b0; src1_r<=32'b0;
            count<=6'b0; dividend<=32'b0; divisor<=32'b0;
            quotient<=32'b0; remainder<=33'b0; quot_neg<=1'b0; rem_neg<=1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start && !busy) begin   // 仅锁存输入
                        busy   <= 1'b1;
                        op_r   <= op;
                        src0_r <= src0;
                        src1_r <= src1;
                        state  <= S_PREP;
                    end
                end

                S_PREP: begin                   // 用寄存值判断
                    if (src1_r == 32'b0) begin
                        busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
                        case (op_r)
                            OP_DIV, OP_DIVU: result <= 32'hffff_ffff;
                            OP_REM, OP_REMU: result <= src0_r;
                            default:         result <= 32'b0;
                        endcase
                    end else if (((op_r == OP_DIV) || (op_r == OP_REM)) && div_overflow_r) begin
                        busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
                        result <= (op_r == OP_DIV) ? 32'h8000_0000 : 32'b0;
                    end else begin
                        busy      <= 1'b1;
                        count     <= 6'd32;
                        dividend  <= abs_src0_r;
                        divisor   <= abs_src1_r;
                        quotient  <= 32'b0;
                        remainder <= 33'b0;
                        quot_neg  <= signed_op_r && (src0_r[31] ^ src1_r[31]);
                        rem_neg   <= signed_op_r && src0_r[31];
                        state     <= S_CALC;
                    end
                end

                default: begin                  // S_CALC: 逐位迭代
                    dividend  <= {dividend[30:0], 1'b0};
                    quotient  <= quotient_next;
                    remainder <= rem_next;
                    count     <= count - 6'd1;
                    if (count == 6'd1) begin
                        busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
                        case (op_r)
                            OP_DIV:  result <= signed_quotient;
                            OP_DIVU: result <= quotient_next;
                            OP_REM:  result <= signed_remainder;
                            OP_REMU: result <= rem_next[31:0];
                            default: result <= 32'b0;
                        endcase
                    end
                end
            endcase
        end
    end
endmodule
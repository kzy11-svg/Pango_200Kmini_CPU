`timescale 1ns / 1ps
// One-stall RV32M multiplier.
// The start edge registers the same four 17x17 partial products as before.
// During the following cycle their sum is valid, so done is asserted directly
// from busy and the pipeline can capture the result on the next edge.
module MUL_UNIT (
    input             clk,
    input             rst,
    input             start,
    input      [4:0]  op,
    input      [31:0] src0,
    input      [31:0] src1,
    output reg         busy,
    output wire        done,
    output wire [31:0] result
);

    localparam [4:0] OP_MUL    = 5'b10011;
    localparam [4:0] OP_MULH   = 5'b10100;
    localparam [4:0] OP_MULHSU = 5'b10101;
    localparam [4:0] OP_MULHU  = 5'b10110;

    wire a_signed = (op == OP_MULH) || (op == OP_MULHSU);
    wire b_signed = (op == OP_MULH);
    wire signed [32:0] a_ext = a_signed ? {src0[31], src0} : {1'b0, src0};
    wire signed [32:0] b_ext = b_signed ? {src1[31], src1} : {1'b0, src1};

    // Split the live operands so the DSP partial products are registered
    // directly on the start edge. This removes the old operand-only stage.
    wire signed [16:0] a_hi = a_ext[32:16];
    wire        [15:0] a_lo = a_ext[15:0];
    wire signed [16:0] b_hi = b_ext[32:16];
    wire        [15:0] b_lo = b_ext[15:0];

    wire signed [33:0] mul_hh = a_hi                  * b_hi;
    wire signed [33:0] mul_hl = a_hi                  * $signed({1'b0, b_lo});
    wire signed [33:0] mul_lh = $signed({1'b0, a_lo}) * b_hi;
    wire signed [33:0] mul_ll = $signed({1'b0, a_lo}) * $signed({1'b0, b_lo});

    reg  [4:0]         op_r;
    reg  signed [33:0] pp_hh, pp_hl, pp_lh, pp_ll;

    wire signed [65:0] term_hh = pp_hh;
    wire signed [65:0] term_hl = pp_hl;
    wire signed [65:0] term_lh = pp_lh;
    wire signed [65:0] term_ll = pp_ll;
    wire signed [65:0] product_sum = (term_hh <<< 32)
                                       + ((term_hl + term_lh) <<< 16)
                                       + term_ll;

    // busy is also the result-valid cycle.  Arithmetic is unchanged; only the
    // redundant extra result-register cycle is removed.
    assign done = busy;
    assign result = (op_r == OP_MUL) ? product_sum[31:0] :
                                       product_sum[63:32];

    always @(posedge clk) begin
        if (rst) begin
            busy  <= 1'b0;
            op_r  <= 5'b0;
            pp_hh <= 34'b0;
            pp_hl <= 34'b0;
            pp_lh <= 34'b0;
            pp_ll <= 34'b0;
        end else begin
            if (start && !busy) begin
                busy  <= 1'b1;
                op_r  <= op;
                pp_hh <= mul_hh;
                pp_hl <= mul_hl;
                pp_lh <= mul_lh;
                pp_ll <= mul_ll;
            end else if (busy) begin
                busy <= 1'b0;
            end
        end
    end

endmodule
`timescale 1ns / 1ps
// One-stall RV32M multiplier.
// The start edge registers the same four 17x17 partial products as before.
// During the following cycle their sum is valid, so done is asserted directly
// from busy and the pipeline can capture the result on the next edge.
module MUL_PIPE (
    input             clk,
    input             rst,
    input             start,
    input      [4:0]  op,
    input      [31:0] src0,
    input      [31:0] src1,
    output wire [31:0] result
);

    localparam [4:0] OP_MUL    = 5'b10011;
    localparam [4:0] OP_MULH   = 5'b10100;
    localparam [4:0] OP_MULHSU = 5'b10101;
    localparam [4:0] OP_MULHU  = 5'b10110;

    wire a_signed = (op == OP_MULH) || (op == OP_MULHSU);
    wire b_signed = (op == OP_MULH);
    wire signed [32:0] a_ext = a_signed ? {src0[31], src0} : {1'b0, src0};
    wire signed [32:0] b_ext = b_signed ? {src1[31], src1} : {1'b0, src1};

    // Split the live operands so the DSP partial products are registered
    // directly on the start edge. This removes the old operand-only stage.
    // Preserve the same one-edge multiply latency, but register operands
    // before the DSP multiplication rather than partial products after it.
    reg signed [16:0] a_hi, b_hi;
    reg        [15:0] a_lo, b_lo;

    wire signed [33:0] mul_hh = a_hi                  * b_hi;
    wire signed [33:0] mul_hl = a_hi                  * $signed({1'b0, b_lo});
    wire signed [33:0] mul_lh = $signed({1'b0, a_lo}) * b_hi;
    wire signed [33:0] mul_ll = $signed({1'b0, a_lo}) * $signed({1'b0, b_lo});

    reg  [4:0]         op_r;
    wire signed [33:0] pp_hh=mul_hh, pp_hl=mul_hl, pp_lh=mul_lh, pp_ll=mul_ll;

    wire signed [65:0] term_hh = pp_hh;
    wire signed [65:0] term_hl = pp_hl;
    wire signed [65:0] term_lh = pp_lh;
    wire signed [65:0] term_ll = pp_ll;
    // Compress four aligned partial products without carry propagation.
    // Only the final addition propagates carry; arithmetic is mod 2^66.
    wire [65:0] aligned_hh = term_hh <<< 32;
    wire [65:0] aligned_hl = term_hl <<< 16;
    wire [65:0] aligned_lh = term_lh <<< 16;
    wire [65:0] csa1_sum = aligned_hh ^ aligned_hl ^ aligned_lh;
    wire [65:0] csa1_carry = ((aligned_hh & aligned_hl) |
                              (aligned_hh & aligned_lh) |
                              (aligned_hl & aligned_lh)) << 1;
    wire [65:0] csa2_sum = csa1_sum ^ csa1_carry ^ term_ll;
    wire [65:0] csa2_carry = ((csa1_sum & csa1_carry) |
                              (csa1_sum & term_ll) |
                              (csa1_carry & term_ll)) << 1;
    wire signed [65:0] product_sum = csa2_sum + csa2_carry;

    assign result = (op_r == OP_MUL) ? product_sum[31:0] : product_sum[63:32];
    // start is exactly the EX-to-MEM acceptance edge. No independent WB port:
    // the product is selected by its original MEM slot, then retires in WB.
    always @(posedge clk) begin
        if (rst) begin
            op_r <= 0; a_hi <= 0; a_lo <= 0; b_hi <= 0; b_lo <= 0;
        end else if (start) begin
            op_r <= op;
            a_hi <= a_ext[32:16]; a_lo <= a_ext[15:0];
            b_hi <= b_ext[32:16]; b_lo <= b_ext[15:0];
        end
    end
endmodule

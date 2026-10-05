`timescale 1ns / 1ps

module BPU #(parameter ENABLE_JALR_BTB = 1, parameter PHT_BITS=7) (
    input wire        clk,
    input wire        rst,
    input wire [31:0] pc_if,
    input wire [31:0] pc_add4_if,
    output wire       pred_taken,
    output wire [31:0] pred_target,
    output wire [4:0] ghr_if_out,
    input wire        ras_push,
    input wire        ras_pop,
    input wire [31:0] ras_push_addr,
    output wire       ras_valid,
    output wire [31:0] ras_top,
    input wire        jalr_update_en,    // registered non-return JALR target update
    input wire        update_en,         // registered branch update enable
    input wire        mispredict_ex_r,   // registered mispredict signal
    input wire [31:0] pc_ex,
    input wire        actual_taken,
    input wire [31:0] actual_target,
    input wire [4:0]  ghr_ex_in
);

    // 64-entry direct-mapped BTB.  CoreMark has enough hot branch sites that
    // the former 32-entry table suffered avoidable PC-index conflicts.
    reg [31:0] btb_target [0:63];
    reg [23:0] btb_tag    [0:63];
    reg        btb_valid  [0:63];
    reg        btb_unconditional [0:63];

    wire [5:0] btb_idx_if = pc_if[7:2];
    wire [5:0] btb_idx_ex = pc_ex[7:2];

    // pc[7:2] selects the BTB entry and pc[1:0] is word alignment, so
    // pc[31:8] is the complete architectural tag.
    wire btb_hit = btb_valid[btb_idx_if] &&
                   (btb_tag[btb_idx_if] == pc_if[31:8]);

    reg [4:0] ghr;
    reg [1:0] pht [0:(1<<PHT_BITS)-1];

    assign ghr_if_out = ghr;

    // Keep the successful per-PC bimodal policy, but double the number of
    // counters so unrelated hot branches collide less often.
    wire [PHT_BITS-1:0] pht_idx_if = pc_if[PHT_BITS+1:2];
    wire [PHT_BITS-1:0] pht_idx_ex = pc_ex[PHT_BITS+1:2];

    assign pred_taken  = btb_hit && (btb_unconditional[btb_idx_if] || pht[pht_idx_if][1]);
    assign pred_target = btb_hit ? btb_target[btb_idx_if] : pc_add4_if;

    // Resolved, non-speculative RAS. CPU qualifies each operation by EX
    // advance and kill; wrong-path ID calls never modify this stack.
    reg [31:0] ras_stack [0:7];
    reg [2:0] ras_ptr;
    reg [3:0] ras_count;
    wire [2:0] ras_top_index = ras_ptr - 3'd1;
    assign ras_valid = ras_count != 0;
    assign ras_top = ras_valid ? ras_stack[ras_top_index] : 32'b0;
    always @(posedge clk) begin
        if (rst) begin
            ras_ptr <= 0;
            ras_count <= 0;
        end else if (ras_push && ras_pop && ras_valid) begin
            // Coroutine hint: pop old top, then push the new return address.
            ras_stack[ras_top_index] <= ras_push_addr;
        end else if (ras_push) begin
            // Full stack drops the oldest entry, preserving the newest eight.
            ras_stack[ras_ptr] <= ras_push_addr;
            ras_ptr <= ras_ptr + 3'd1;
            if (ras_count < 8) ras_count <= ras_count + 1'b1;
        end else if (ras_pop && ras_valid) begin
            ras_ptr <= ras_ptr - 3'd1;
            ras_count <= ras_count - 1'b1;
        end
    end

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            ghr <= 5'b0;
            for (i = 0; i < 64; i = i + 1) begin
                btb_valid[i] <= 1'b0;
                btb_unconditional[i] <= 1'b0;
            end
            for(i=0;i<(1<<PHT_BITS);i=i+1) pht[i]<=2'b01;
        end else begin
            // Targets and branch types have a separate update policy.
            // PHT and GHR remain conditional-branch-only.
            if ((update_en && actual_taken) || (ENABLE_JALR_BTB && jalr_update_en)) begin
                btb_valid[btb_idx_ex] <= 1'b1;
                btb_tag[btb_idx_ex] <= pc_ex[31:8];
                btb_target[btb_idx_ex] <= actual_target;
                btb_unconditional[btb_idx_ex] <= ENABLE_JALR_BTB && jalr_update_en;
            end
            if (update_en) begin
            case (pht[pht_idx_ex])
                2'b00: pht[pht_idx_ex] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: pht[pht_idx_ex] <= actual_taken ? 2'b10 : 2'b00;
                2'b10: pht[pht_idx_ex] <= actual_taken ? 2'b11 : 2'b01;
                2'b11: pht[pht_idx_ex] <= actual_taken ? 2'b11 : 2'b10;
            endcase

            // History is updated only on actual resolution, never speculated.
            // A misprediction still contributes its actual result exactly once.
            ghr <= {ghr[3:0], actual_taken};
            end
        end
    end

endmodule

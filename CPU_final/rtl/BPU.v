`timescale 1ns / 1ps

module BPU #(parameter ENABLE_JALR_BTB = 1, parameter PHT_BITS=9, parameter RAW_TARGET_PAYLOAD=0) (
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

    // 256-entry direct-mapped BTB.  CoreMark has enough hot branch sites that
    // the former 32-entry table suffered avoidable PC-index conflicts.
    // Fixed resident ROM permits compressed prediction metadata. Execution
    // and fault PCs remain full width; out-of-range targets are not installed.
    // [22] valid, [21] unconditional, [20:16] resident tag, [15:0] target.
    reg [23:0] btb_metadata[0:255] /* synthesis syn_ramstyle="lut_ram" */;
    reg btb_initializing;
    reg [8:0] btb_reset_index;
    wire [7:0] btb_idx_if = pc_if[9:2];
    wire [7:0] btb_idx_ex = pc_ex[9:2];

    // pc[7:2] selects the BTB entry and pc[1:0] is word alignment, so
    // pc[31:8] is the complete architectural tag.
    wire [23:0] btb_word=btb_metadata[btb_idx_if];
    wire btb_hit=!btb_initializing && pc_if[31:16]==16'h8000 &&
                 btb_word[23] && btb_word[21:16]==pc_if[15:10];

    reg [4:0] ghr;
    reg [5:0] pht_metadata[0:511] /* synthesis syn_ramstyle="lut_ram" */;

    assign ghr_if_out = ghr;

    // Keep the successful per-PC bimodal policy, but double the number of
    // counters so unrelated hot branches collide less often.
    wire [PHT_BITS-1:0] pht_idx_if = pc_if[PHT_BITS+1:2];
    wire [PHT_BITS-1:0] pht_idx_ex = pc_ex[PHT_BITS+1:2];

    assign pred_taken  = btb_hit && (btb_word[22] || (!btb_initializing && pht_metadata[pht_idx_if][5] && (pht_metadata[pht_idx_if][4]?pht_metadata[pht_idx_if][3]:pht_metadata[pht_idx_if][1])));
    // The integrated frontend consumes a BTB target only on pred_taken.
    // Keep the generic interface's miss-PC behavior by default.
    assign pred_target = RAW_TARGET_PAYLOAD ? {16'h8000,btb_word[15:0]} :
                        (btb_hit ? {16'h8000,btb_word[15:0]} : pc_add4_if);

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

    wire [5:0] training_word=pht_metadata[pht_idx_ex][5]?pht_metadata[pht_idx_ex]:6'b000101;
    wire [1:0] trained_counter=training_word[4]?training_word[3:2]:training_word[1:0];
    reg [1:0] next_counter;
    always @* begin
        case(trained_counter)
            2'b00:next_counter=actual_taken?2'b01:2'b00;
            2'b01:next_counter=actual_taken?2'b10:2'b00;
            2'b10:next_counter=actual_taken?2'b11:2'b01;
            default:next_counter=actual_taken?2'b11:2'b10;
        endcase
    end
    always @(posedge clk)if(!rst)begin
        if(btb_initializing)pht_metadata[btb_reset_index]<=0;
        else if(update_en)pht_metadata[pht_idx_ex]<=training_word[4]?{1'b1,actual_taken,next_counter,training_word[1:0]}:{1'b1,actual_taken,training_word[3:2],next_counter};
    end
    // Sweep RAM valid bits after reset instead of resetting all data FFs.
    // During the sweep the BTB predicts miss and ignores training. CPU keeps
    // executing; direct JAL and the architectural redirect remain available.
    always @(posedge clk) begin
        if(rst)begin btb_initializing<=1;btb_reset_index<=0;end
        else if(btb_initializing)begin
            if(btb_reset_index<256)btb_metadata[btb_reset_index[7:0]]<=0;
            if(btb_reset_index==511)btb_initializing<=0;
            else btb_reset_index<=btb_reset_index+1'b1;
        end else if((update_en && actual_taken) || (ENABLE_JALR_BTB && jalr_update_en))begin
            btb_metadata[btb_idx_ex]<={
                pc_ex[31:16]==16'h8000 && actual_target[31:16]==16'h8000 && actual_target[1:0]==0,
                ENABLE_JALR_BTB && jalr_update_en,pc_ex[15:10],actual_target[15:0]};
        end
    end
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            ghr <= 5'b0;

        end else begin
            // Targets and branch types have a separate update policy.
            // PHT and GHR remain conditional-branch-only.
            if (update_en) begin


            // History is updated only on actual resolution, never speculated.
            // A misprediction still contributes its actual result exactly once.
            ghr <= {ghr[3:0], actual_taken};
            end
        end
    end

endmodule

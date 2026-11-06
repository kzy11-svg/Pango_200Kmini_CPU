`timescale 1ns / 1ps

module JFIX_BPU_BASE_REF #(parameter ENABLE_JALR_BTB = 1, parameter RAW_TARGET_PAYLOAD=0,parameter PREPARED_QUERY_ROWS=0, parameter LOCAL_HISTORY_BITS=1,parameter REGISTER_TRAINING=0,parameter CACHED_DIRECTION=0,parameter HYBRID_LOCAL=0,parameter GLOBAL_BITS=0,parameter SPECULATIVE_GLOBAL=0,parameter TOURNAMENT_GLOBAL=0) (
    output [3:0] query_directions,input [1:0] training_directions,
    input [1:0] spec_count,spec_taken,input [12:0] recover_history,
    input [12:0] prediction_history,output [12:0] global_history,
    input wire        clk,
    input wire        rst,
    input wire [31:0] pc_if,pc_if1,
    input wire [15:0] prepared_rows,
    input wire [31:0] pc_add4_if,
    output wire       pred_taken,pred_taken1,
    output wire [31:0] pred_target,pred_target1,
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
    // Register a complete retirement training command. Query/RAS semantics
    // are unchanged; a delayed command always carries its matching identity.
    reg update_r,jalr_r,taken_r;reg [12:0] history_r;reg [1:0] directions_r;
 wire [1:0] train_directions=REGISTER_TRAINING?directions_r:training_directions;
    wire [12:0] train_snapshot=REGISTER_TRAINING?history_r:prediction_history;
    reg [31:0] pc_r,target_r;
    always @(posedge clk)begin
      if(rst)begin update_r<=0;jalr_r<=0;end
      else begin update_r<=update_en;jalr_r<=jalr_update_en;end
      history_r<=prediction_history;directions_r<=training_directions;
      pc_r<=pc_ex;target_r<=actual_target;taken_r<=actual_taken;
    end
    wire train_update=REGISTER_TRAINING?update_r:update_en;
    wire train_jalr=REGISTER_TRAINING?jalr_r:jalr_update_en;
    wire [31:0] train_pc=REGISTER_TRAINING?pc_r:pc_ex;
    wire [31:0] train_target=REGISTER_TRAINING?target_r:actual_target;
    wire train_taken=REGISTER_TRAINING?taken_r:actual_taken;


    // 256-entry direct-mapped BTB.  CoreMark has enough hot branch sites that
    // the former 32-entry table suffered avoidable PC-index conflicts.
    // Fixed resident ROM permits compressed prediction metadata. Execution
    // and fault PCs remain full width; out-of-range targets are not installed.
    // [22] valid, [21] unconditional, [20:16] resident tag, [15:0] target.
    reg btb_initializing;
    reg [8:0] btb_reset_index;
    reg [1:0] next_counter;

    // Per-PC committed local history. Prediction is advisory; updates occur
    // once at architectural branch retirement, and never on a wrong path.
    localparam integer NC = 1 << LOCAL_HISTORY_BITS;
    localparam integer CB = 2*NC;
    localparam integer PW = CB + LOCAL_HISTORY_BITS + 1;
    wire [23:0] btb_word,btb_word1;wire [23:0] bank_target[0:1];wire [PW-1:0] bank_counter[0:1],bank_training[0:1];
    wire [PW-1:0] query_pht,query_pht1,training_pht;
    wire [PW-1:0] training_word=training_pht[PW-1]?training_pht:
      {1'b0,{LOCAL_HISTORY_BITS{1'b0}},{NC{2'b01}}};
    wire [LOCAL_HISTORY_BITS-1:0] train_history=training_word[CB+:LOCAL_HISTORY_BITS];
    wire [1:0] trained_counter=training_word[2*train_history+:2];
    reg [PW-1:0] updated_word;
    always @* begin
      updated_word=training_word;
      updated_word[PW-1]=1'b1;
      updated_word[CB+:LOCAL_HISTORY_BITS]=(train_history << 1) | train_taken;
      updated_word[2*train_history+:2]=next_counter;
    end
    function predict_local;
      input [PW-1:0] entry;
      reg [LOCAL_HISTORY_BITS-1:0] h;
      begin h=entry[CB+:LOCAL_HISTORY_BITS];
        predict_local=entry[PW-1] && entry[2*h+1];
      end
    endfunction
    wire [1:0] bank_direction;
    wire [LOCAL_HISTORY_BITS-1:0] next_history=(train_history << 1) | train_taken;
    wire long_next=(next_history==train_history)?next_counter[1]:training_word[2*next_history+1];
    wire [5:0] bank_aux[0:1];
    wire [5:0] training_aux=bank_aux[train_pc[2]];
    wire [1:0] short_old=training_aux[2*train_history[0]+:2];
    wire [1:0] short_updated=train_taken?(short_old==3?2'd3:short_old+2'd1):(short_old==0?2'd0:short_old-2'd1);
    reg [5:0] aux_next;
    always @*begin
      aux_next=training_aux;
      aux_next[2*train_history[0]+:2]=short_updated;
      if(short_old[1]!=trained_counter[1])begin
        if(trained_counter[1]==train_taken)begin
          if(training_aux[5:4]!=3)aux_next[5:4]=training_aux[5:4]+2'd1;
        end else if(training_aux[5:4]!=0)aux_next[5:4]=training_aux[5:4]-2'd1;
      end
    end
    wire next_direction=HYBRID_LOCAL?(aux_next[5]?long_next:aux_next[2*train_taken+1]):long_next;
    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1)begin:parity_bank
     reg [23:0] targets[0:127] /* synthesis syn_ramstyle="lut_ram" */;
     reg [PW-1:0] counters[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     reg [5:0] auxiliary[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     reg direction[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     wire [31:0] query=pc_if[2]==bank?pc_if:pc_if1;
     wire [7:0] read_row=PREPARED_QUERY_ROWS?prepared_rows[bank*8+:8]:query[10:3];
     wire [23:0] target_read=targets[read_row[6:0]];
     wire [PW-1:0] counter_read=counters[read_row];
     assign bank_aux[bank]=auxiliary[btb_initializing?btb_reset_index[8:1]:train_pc[10:3]];
     wire [5:0] query_aux=auxiliary[read_row];
     wire query_direction=HYBRID_LOCAL?(query_aux[5]?predict_local(counter_read):
       (counter_read[PW-1] && query_aux[2*counter_read[CB]+1])):predict_local(counter_read);
     assign bank_direction[bank]=CACHED_DIRECTION?direction[read_row]:query_direction;
     assign bank_target[bank]=target_read;
     assign bank_counter[bank]=counter_read;
     assign bank_training[bank]=counters[btb_initializing?btb_reset_index[8:1]:train_pc[10:3]];
     always @(posedge clk)if(!rst)begin
      if(btb_initializing)begin
       if(btb_reset_index[0]==bank)begin
        if(btb_reset_index<256)targets[btb_reset_index[7:1]]<=0;
        counters[btb_reset_index[8:1]]<=0;
        direction[btb_reset_index[8:1]]<=0;
        auxiliary[btb_reset_index[8:1]]<=6'b100101;
       end
      end else begin
       if(train_pc[2]==bank && train_update)auxiliary[train_pc[10:3]]<=aux_next;
       if(train_pc[2]==bank && train_update)direction[train_pc[10:3]]<=next_direction;
       if(train_pc[2]==bank && train_update)counters[train_pc[10:3]]<=
        updated_word;
       if(train_pc[2]==bank && ((train_update && train_taken) || (ENABLE_JALR_BTB && train_jalr)))
        targets[train_pc[9:3]]<={
         train_pc[31:16]==16'h8000 && train_target[31:16]==16'h8000 && train_target[1:0]==0,
         ENABLE_JALR_BTB && train_jalr,train_pc[15:10],train_target[15:0]};
      end
     end
    end endgenerate
    assign btb_word=bank_target[pc_if[2]];
    assign btb_word1=bank_target[pc_if1[2]];
    assign query_pht=bank_counter[pc_if[2]];
    assign query_pht1=bank_counter[pc_if1[2]];
    assign training_pht=bank_training[train_pc[2]];
    wire [7:0] btb_idx_if = pc_if[9:2];
    wire [7:0] btb_idx_ex = train_pc[9:2];

    // pc[7:2] selects the BTB entry and pc[1:0] is word alignment, so
    // pc[31:8] is the complete architectural tag.

    wire btb_hit=!btb_initializing && pc_if[31:16]==16'h8000 &&
                 btb_word[23] && btb_word[21:16]==pc_if[15:10];

    reg [4:0] ghr;


    assign ghr_if_out = ghr;

    // Keep the successful per-PC bimodal policy, but double the number of
    // counters so unrelated hot branches collide less often.
    wire [8:0] pht_idx_if = pc_if[10:2];
    wire [8:0] pht_idx_ex = train_pc[10:2];

    wire [1:0] global_direction,choose_global;
    assign query_directions={global_direction[1],bank_direction[pc_if1[2]],global_direction[0],bank_direction[pc_if[2]]};
    generate for(genvar tb=0;tb<2;tb=tb+1)begin:tournament
      reg [1:0] choice[0:255] /* synthesis syn_ramstyle="lut_ram" */;
      wire [31:0] qp=pc_if[2]==tb?pc_if:pc_if1;
      wire [1:0] old=choice[train_pc[10:3]];
      wire win_global=train_directions[1]==train_taken;
      wire [1:0] next=win_global?(old==3?2'd3:old+2'd1):(old==0?2'd0:old-2'd1);
      assign choose_global[tb]=choice[qp[10:3]][1];
      always @(posedge clk)if(!rst)begin
        if(btb_initializing)begin if(btb_reset_index[0]==tb)choice[btb_reset_index[8:1]]<=0;end
        else if(train_update && train_pc[2]==tb && train_directions[0]!=train_directions[1])choice[train_pc[10:3]]<=next;
      end
    end endgenerate
    assign pred_taken  = btb_hit && (btb_word[22] || (!btb_initializing && ((GLOBAL_BITS!=0 && (!TOURNAMENT_GLOBAL || choose_global[pc_if[2]]))?global_direction[0]:bank_direction[pc_if[2]])));
    // The integrated frontend consumes a BTB target only on pred_taken.
    // Keep the generic interface's miss-PC behavior by default.
    assign pred_target = RAW_TARGET_PAYLOAD ? {16'h8000,btb_word[15:0]} :
                        (btb_hit ? {16'h8000,btb_word[15:0]} : pc_add4_if);

    wire btb_hit1=!btb_initializing && pc_if1[31:16]==16'h8000 &&
       btb_word1[23] && btb_word1[21:16]==pc_if1[15:10];
    assign pred_taken1=btb_hit1 && (btb_word1[22] ||
       (!btb_initializing && ((GLOBAL_BITS!=0 && (!TOURNAMENT_GLOBAL || choose_global[pc_if1[2]]))?global_direction[1]:bank_direction[pc_if1[2]])));
    assign pred_target1=RAW_TARGET_PAYLOAD?{16'h8000,btb_word1[15:0]}:
       (btb_hit1?{16'h8000,btb_word1[15:0]}:pc_if1+4);
    generate if(GLOBAL_BITS!=0)begin:global_predictor
      localparam BANK_BITS=3;
      localparam ROWS=1<<(GLOBAL_BITS-BANK_BITS);
      reg [GLOBAL_BITS-1:0] history,clear_index;
      reg clearing;
      wire [GLOBAL_BITS-1:0] index0=pc_if[GLOBAL_BITS+1:2]^history;
      wire [GLOBAL_BITS-1:0] index1=pc_if1[GLOBAL_BITS+1:2]^history;
      wire [GLOBAL_BITS-1:0] update_index=train_pc[GLOBAL_BITS+1:2]^train_snapshot[GLOBAL_BITS-1:0];
      wire [(1<<BANK_BITS)-1:0] bank_prediction;
      assign global_history={{(13-GLOBAL_BITS){1'b0}},history};
      assign global_direction={bank_prediction[index1[BANK_BITS-1:0]],bank_prediction[index0[BANK_BITS-1:0]]} & {2{!clearing}};
      always @(posedge clk)begin
        if(rst)begin history<=0;clearing<=1;clear_index<=0;end
        else begin
          if(clearing)begin clear_index<=clear_index+1'b1;if(&clear_index)clearing<=0;end
          if(SPECULATIVE_GLOBAL)begin
            if(mispredict_ex_r)history<=recover_history[GLOBAL_BITS-1:0];
            else if(spec_count==2)history<=(history<<2)|spec_taken;
            else if(spec_count==1)history<=(history<<1)|spec_taken[0];
          end else if(train_update)history<=(history<<1)|train_taken;
        end
      end
      for(genvar gb=0;gb<(1<<BANK_BITS);gb=gb+1)begin:bank
        reg [1:0] ctr[0:ROWS-1] /* synthesis syn_ramstyle="lut_ram" */;
        wire [GLOBAL_BITS-BANK_BITS-1:0] qr=index0[0]==(gb%2)?index0[GLOBAL_BITS-1:BANK_BITS]:index1[GLOBAL_BITS-1:BANK_BITS];
        wire [1:0] old=ctr[update_index[GLOBAL_BITS-1:BANK_BITS]];
        wire [1:0] next={2{train_taken}};
        assign bank_prediction[gb]=ctr[qr][1];
        always @(posedge clk)if(!rst)begin
          if(clearing)begin if(clear_index[BANK_BITS-1:0]==gb)ctr[clear_index[GLOBAL_BITS-1:BANK_BITS]]<=1;end
          else if(train_update && update_index[BANK_BITS-1:0]==gb)ctr[update_index[GLOBAL_BITS-1:BANK_BITS]]<=next;
        end
      end
    end else begin
      assign global_history=0;assign global_direction=0;
    end endgenerate
    // synthesis translate_off
    wire [7:0] expected_even_row=pc_if[10:3]+pc_if[2];
    always @(posedge clk)if(!rst && PREPARED_QUERY_ROWS &&
      prepared_rows!=={pc_if[10:3],expected_even_row})
      $fatal(1,"Prepared predictor bank rows disagree with query PC");
    always @(posedge clk)if(!rst && pc_if1!==pc_if+4)
      $fatal(1,"Paired predictor requires consecutive instruction queries");
    // synthesis translate_on
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


    always @* begin
        case(trained_counter)
            2'b00:next_counter=train_taken?2'b01:2'b00;
            2'b01:next_counter=train_taken?2'b10:2'b00;
            2'b10:next_counter=train_taken?2'b11:2'b01;
            default:next_counter=train_taken?2'b11:2'b10;
        endcase
    end
    // Sweep RAM valid bits after reset instead of resetting all data FFs.
    // During the sweep the BTB predicts miss and ignores training. CPU keeps
    // executing; direct JAL and the architectural redirect remain available.
    always @(posedge clk) begin
        if(rst)begin btb_initializing<=1;btb_reset_index<=0;end
        else if(btb_initializing)begin

            if(btb_reset_index==511)btb_initializing<=0;
            else btb_reset_index<=btb_reset_index+1'b1;
        end
    end
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            ghr <= 5'b0;

        end else begin
            // Targets and branch types have a separate update policy.
            // PHT and GHR remain conditional-branch-only.
            if (train_update) begin


            // History is updated only on actual resolution, never speculated.
            // A misprediction still contributes its actual result exactly once.
            ghr <= {ghr[3:0], train_taken};
            end
        end
    end

endmodule

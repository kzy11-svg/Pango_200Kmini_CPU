`timescale 1ns / 1ps

module JFIX_BPU_PAIR #(parameter GLOBAL_COUNTER_BITS=2, parameter ENABLE_JALR_BTB = 1, parameter RAW_TARGET_PAYLOAD=0,parameter PREPARED_QUERY_ROWS=0, parameter LOCAL_HISTORY_BITS=1,parameter REGISTER_TRAINING=0,parameter CACHED_DIRECTION=0,parameter HYBRID_LOCAL=0,parameter GLOBAL_BITS=0,parameter SPECULATIVE_GLOBAL=0,parameter TOURNAMENT_GLOBAL=0,parameter SYNC_GLOBAL=0,parameter CHOICE_HASH_INDEX=0,parameter ELIDE_TOURNAMENT_METADATA=0,parameter USE_PREINDEX1=0) (
    output [3:0] query_directions,input [1:0] training_directions,
    input [1:0] spec_count,spec_taken,input [12:0] recover_history,
    input [12:0] prediction_history,output [12:0] global_history,
    input wire        clk,
    input wire        rst,
    input wire [31:0] pc_if,pc_if1,
    input wire [31:0] next_query_pc0,next_query_pc1,
    input wire [12:0] prepared_next_index1,
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

 // synthesis translate_off
 wire btb_hit,btb_hit1;
 // synthesis translate_on
 generate if(LOCAL_HISTORY_BITS==8 && REGISTER_TRAINING && CACHED_DIRECTION)begin:byte_storage
  JFIX_BPU_PAIR_byte_shared #(.GLOBAL_COUNTER_BITS(GLOBAL_COUNTER_BITS),.ENABLE_JALR_BTB(ENABLE_JALR_BTB),.RAW_TARGET_PAYLOAD(RAW_TARGET_PAYLOAD),.PREPARED_QUERY_ROWS(PREPARED_QUERY_ROWS),.LOCAL_HISTORY_BITS(LOCAL_HISTORY_BITS),.REGISTER_TRAINING(REGISTER_TRAINING),.CACHED_DIRECTION(CACHED_DIRECTION),.HYBRID_LOCAL(HYBRID_LOCAL),.GLOBAL_BITS(GLOBAL_BITS),.SPECULATIVE_GLOBAL(SPECULATIVE_GLOBAL),.TOURNAMENT_GLOBAL(TOURNAMENT_GLOBAL),.SYNC_GLOBAL(SYNC_GLOBAL),.CHOICE_HASH_INDEX(CHOICE_HASH_INDEX),.ELIDE_TOURNAMENT_METADATA(ELIDE_TOURNAMENT_METADATA),.USE_PREINDEX1(USE_PREINDEX1)) implementation(.query_directions(query_directions),.training_directions(training_directions),.spec_count(spec_count),.spec_taken(spec_taken),.recover_history(recover_history),.prediction_history(prediction_history),.global_history(global_history),.clk(clk),.rst(rst),.pc_if(pc_if),.pc_if1(pc_if1),.next_query_pc0(next_query_pc0),.next_query_pc1(next_query_pc1),.prepared_next_index1(prepared_next_index1),.prepared_rows(prepared_rows),.pc_add4_if(pc_add4_if),.pred_taken(pred_taken),.pred_taken1(pred_taken1),.pred_target(pred_target),.pred_target1(pred_target1),.ghr_if_out(ghr_if_out),.ras_push(ras_push),.ras_pop(ras_pop),.ras_push_addr(ras_push_addr),.ras_valid(ras_valid),.ras_top(ras_top),.jalr_update_en(jalr_update_en),.update_en(update_en),.mispredict_ex_r(mispredict_ex_r),.pc_ex(pc_ex),.actual_taken(actual_taken),.actual_target(actual_target),.ghr_ex_in(ghr_ex_in));
  // synthesis translate_off
  assign btb_hit=implementation.btb_hit;assign btb_hit1=implementation.btb_hit1;
  // synthesis translate_on
 end else begin:generic_storage
  JFIX_BPU_PAIR_original #(.GLOBAL_COUNTER_BITS(GLOBAL_COUNTER_BITS),.ENABLE_JALR_BTB(ENABLE_JALR_BTB),.RAW_TARGET_PAYLOAD(RAW_TARGET_PAYLOAD),.PREPARED_QUERY_ROWS(PREPARED_QUERY_ROWS),.LOCAL_HISTORY_BITS(LOCAL_HISTORY_BITS),.REGISTER_TRAINING(REGISTER_TRAINING),.CACHED_DIRECTION(CACHED_DIRECTION),.HYBRID_LOCAL(HYBRID_LOCAL),.GLOBAL_BITS(GLOBAL_BITS),.SPECULATIVE_GLOBAL(SPECULATIVE_GLOBAL),.TOURNAMENT_GLOBAL(TOURNAMENT_GLOBAL),.SYNC_GLOBAL(SYNC_GLOBAL),.CHOICE_HASH_INDEX(CHOICE_HASH_INDEX),.ELIDE_TOURNAMENT_METADATA(ELIDE_TOURNAMENT_METADATA),.USE_PREINDEX1(USE_PREINDEX1)) implementation(.query_directions(query_directions),.training_directions(training_directions),.spec_count(spec_count),.spec_taken(spec_taken),.recover_history(recover_history),.prediction_history(prediction_history),.global_history(global_history),.clk(clk),.rst(rst),.pc_if(pc_if),.pc_if1(pc_if1),.next_query_pc0(next_query_pc0),.next_query_pc1(next_query_pc1),.prepared_next_index1(prepared_next_index1),.prepared_rows(prepared_rows),.pc_add4_if(pc_add4_if),.pred_taken(pred_taken),.pred_taken1(pred_taken1),.pred_target(pred_target),.pred_target1(pred_target1),.ghr_if_out(ghr_if_out),.ras_push(ras_push),.ras_pop(ras_pop),.ras_push_addr(ras_push_addr),.ras_valid(ras_valid),.ras_top(ras_top),.jalr_update_en(jalr_update_en),.update_en(update_en),.mispredict_ex_r(mispredict_ex_r),.pc_ex(pc_ex),.actual_taken(actual_taken),.actual_target(actual_target),.ghr_ex_in(ghr_ex_in));
  // synthesis translate_off
  assign btb_hit=implementation.btb_hit;assign btb_hit1=implementation.btb_hit1;
  // synthesis translate_on
 end endgenerate
endmodule
`timescale 1ns / 1ps

module JFIX_BPU_PAIR_original #(parameter GLOBAL_COUNTER_BITS=2, parameter ENABLE_JALR_BTB = 1, parameter RAW_TARGET_PAYLOAD=0,parameter PREPARED_QUERY_ROWS=0, parameter LOCAL_HISTORY_BITS=1,parameter REGISTER_TRAINING=0,parameter CACHED_DIRECTION=0,parameter HYBRID_LOCAL=0,parameter GLOBAL_BITS=0,parameter SPECULATIVE_GLOBAL=0,parameter TOURNAMENT_GLOBAL=0,parameter SYNC_GLOBAL=0,parameter CHOICE_HASH_INDEX=0,parameter ELIDE_TOURNAMENT_METADATA=0,parameter USE_PREINDEX1=0) (
    output [3:0] query_directions,input [1:0] training_directions,
    input [1:0] spec_count,spec_taken,input [12:0] recover_history,
    input [12:0] prediction_history,output [12:0] global_history,
    input wire        clk,
    input wire        rst,
    input wire [31:0] pc_if,pc_if1,
    input wire [31:0] next_query_pc0,next_query_pc1,
    input wire [12:0] prepared_next_index1,
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

    // Per-PC committed local history. Prediction is advisory; updates occur
    // once at architectural branch retirement, and never on a wrong path.
    localparam integer NC = 1 << LOCAL_HISTORY_BITS;
    localparam integer CB = 2*NC;
    localparam integer PW = CB + LOCAL_HISTORY_BITS + 1;
    wire [23:0] btb_word,btb_word1;wire [23:0] bank_target[0:1];wire [PW-1:0] bank_counter[0:1],bank_training[0:1];
    wire [PW-1:0] query_pht,query_pht1,training_pht;
    function automatic [1:0] saturate_counter(input [1:0] value,input taken);
      begin
        case(value)
          2'b00:saturate_counter=taken?2'b01:2'b00;
          2'b01:saturate_counter=taken?2'b10:2'b00;
          2'b10:saturate_counter=taken?2'b11:2'b01;
          default:saturate_counter=taken?2'b11:2'b10;
        endcase
      end
    endfunction
    function predict_local;
      input [PW-1:0] entry;
      reg [LOCAL_HISTORY_BITS-1:0] h;
      begin h=entry[CB+:LOCAL_HISTORY_BITS];
        predict_local=entry[PW-1] && entry[2*h+1];
      end
    endfunction
    wire [1:0] bank_direction;
    wire [5:0] bank_aux[0:1];
    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1)begin:parity_bank
     reg [23:0] targets[0:127] /* synthesis syn_ramstyle="lut_ram" */;
     reg [PW-1:0] counters[0:255] /* synthesis syn_ramstyle="block_ram" */;
     reg [5:0] auxiliary[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     reg direction[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     // Each physical bank updates its own read value. The bank bit only
     // qualifies writes, rather than selecting a wide training payload.
     reg [PW-1:0] captured_counter;
     reg [5:0] captured_auxiliary;
     wire [PW-1:0] training_read=REGISTER_TRAINING?captured_counter:counters[train_pc[10:3]];
     // Initialize invalid rows to their canonical first-training value.
     // Validity still suppresses prediction, but training needs no wide mux.
     wire [PW-1:0] training_word=training_read;
     wire [LOCAL_HISTORY_BITS-1:0] train_history=training_word[CB+:LOCAL_HISTORY_BITS];
     wire [1:0] trained_counter=training_word[2*train_history+:2];
     wire [1:0] next_counter=saturate_counter(trained_counter,train_taken);
     wire [LOCAL_HISTORY_BITS-1:0] next_history=(train_history << 1) | train_taken;
     wire long_next=(next_history==train_history)?next_counter[1]:training_word[2*next_history+1];
     reg [PW-1:0] updated_word;
     always @*begin
       updated_word=training_word;
       updated_word[PW-1]=1'b1;
       updated_word[CB+:LOCAL_HISTORY_BITS]=next_history;
       updated_word[2*train_history+:2]=next_counter;
     end
     wire [5:0] training_aux=REGISTER_TRAINING?captured_auxiliary:auxiliary[train_pc[10:3]];
     wire [1:0] short_old=training_aux[2*train_history[0]+:2];
     wire [1:0] short_updated=saturate_counter(short_old,train_taken);
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

     // Capture the row of the incoming command. Forward the write performed
     // at this same edge, including reset sweep, to preserve asynchronous RAM
     // read-after-write behavior for consecutive commands to the same row.
     always @(posedge clk)begin
       captured_counter<=counters[pc_ex[10:3]];
       captured_auxiliary<=auxiliary[pc_ex[10:3]];
       if(!rst)begin
         if(btb_initializing)begin
           if(btb_reset_index[0]==bank && btb_reset_index[8:1]==pc_ex[10:3])begin
             captured_counter<={1'b0,{LOCAL_HISTORY_BITS{1'b0}},{NC{2'b01}}};
             captured_auxiliary<=6'b100101;
           end
         end else if(train_pc[2]==bank && train_update && train_pc[10:3]==pc_ex[10:3])begin
           captured_counter<=updated_word;
           captured_auxiliary<=aux_next;
         end
       end
     end
     wire [31:0] query=pc_if[2]==bank?pc_if:pc_if1;
     wire [7:0] read_row=PREPARED_QUERY_ROWS?prepared_rows[bank*8+:8]:query[10:3];
     wire [23:0] target_read=targets[read_row[6:0]];
     wire [PW-1:0] counter_read=counters[read_row];
     // Initialization writes constants and ignores the training read ports.
     // Keep the sweep address out of the high-fanout training data cone.
     assign bank_aux[bank]=auxiliary[train_pc[10:3]];
     wire [5:0] query_aux=auxiliary[read_row];
     wire query_direction=HYBRID_LOCAL?(query_aux[5]?predict_local(counter_read):
       (counter_read[PW-1] && query_aux[2*counter_read[CB]+1])):predict_local(counter_read);
     assign bank_direction[bank]=CACHED_DIRECTION?direction[read_row]:query_direction;
     assign bank_target[bank]=target_read;
     assign bank_counter[bank]=counter_read;
     assign bank_training[bank]=counters[train_pc[10:3]];
     always @(posedge clk)if(!rst)begin
      if(btb_initializing)begin
       if(btb_reset_index[0]==bank)begin
        if(btb_reset_index<256)targets[btb_reset_index[7:1]]<=0;
        counters[btb_reset_index[8:1]]<=
         {1'b0,{LOCAL_HISTORY_BITS{1'b0}},{NC{2'b01}}};
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
    assign query_directions=ELIDE_TOURNAMENT_METADATA?4'b0:{global_direction[1],bank_direction[pc_if1[2]],global_direction[0],bank_direction[pc_if[2]]};
    generate for(genvar tb=0;tb<2;tb=tb+1)begin:tournament
      // Context-sensitive local/global chooser; each bank clears its own
      // table, so uninitialized RAM never influences a prediction.
      reg [1:0] choice[0:1023] /* synthesis syn_ramstyle="lut_ram" */;
      reg [9:0] init_index;reg choice_clearing;
      wire [31:0] qp=pc_if[2]==tb?pc_if:pc_if1;
      wire [9:0] train_idx=train_pc[12:3] ^ train_snapshot[9:0] ^ {7'b0,train_pc[15:13]};
      wire [9:0] query_idx=qp[12:3] ^ global_history[9:0] ^ {7'b0,qp[15:13]};
      wire [1:0] old=choice[train_idx];
      wire win_global=train_directions[1]==train_taken;
      wire [1:0] next=win_global?(old==3?2'd3:old+2'd1):(old==0?2'd0:old-2'd1);
      assign choose_global[tb]=!choice_clearing && choice[query_idx][1];
      always @(posedge clk)begin
       if(rst)begin init_index<=0;choice_clearing<=1;end
       else if(choice_clearing)begin
        choice[init_index]<=2'd1;init_index<=init_index+1'b1;
        if(&init_index)choice_clearing<=0;
       end else if(train_update && train_pc[2]==tb && train_directions[0]!=train_directions[1])
        choice[train_idx]<=next;
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
      wire [GLOBAL_BITS-1:0] next_history=rst?{GLOBAL_BITS{1'b0}}:
        SPECULATIVE_GLOBAL?(mispredict_ex_r?recover_history[GLOBAL_BITS-1:0]:
          spec_count==2?((history<<2)|spec_taken):
          spec_count==1?((history<<1)|spec_taken[0]):history):
          train_update?((history<<1)|train_taken):history;
      wire [GLOBAL_BITS-1:0] next_index0=next_query_pc0[GLOBAL_BITS+1:2]^next_history;
      wire [GLOBAL_BITS-1:0] next_index1_reference=next_query_pc1[GLOBAL_BITS+1:2]^next_history;
      wire [GLOBAL_BITS-1:0] next_index1=USE_PREINDEX1?prepared_next_index1[GLOBAL_BITS-1:0]:next_index1_reference;
      // synthesis translate_off
      always @(posedge clk) if (!rst && USE_PREINDEX1 && next_index1!==next_index1_reference)
       $fatal(1,"lane 1 prepared prediction index changed identity");
      // synthesis translate_on
      if(SYNC_GLOBAL)begin:synchronous
        // Two prediction read copies and a counter-training copy.
        // Registered training reads ahead; same-index writes forward.
        reg [GLOBAL_COUNTER_BITS-1:0] direction0[0:(1<<GLOBAL_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
        reg [GLOBAL_COUNTER_BITS-1:0] direction1[0:(1<<GLOBAL_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
        wire write_en=!rst && (clearing || train_update);
        wire [GLOBAL_BITS-1:0] write_index=clearing?clear_index:update_index;
        reg [GLOBAL_COUNTER_BITS-1:0] training_mem[0:(1<<GLOBAL_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
        reg [GLOBAL_COUNTER_BITS-1:0] training_old;
        wire [GLOBAL_BITS-1:0] training_query=pc_ex[GLOBAL_BITS+1:2]^prediction_history[GLOBAL_BITS-1:0];
        wire [GLOBAL_COUNTER_BITS-1:0] training_base=REGISTER_TRAINING?training_old:training_mem[update_index];
        wire [GLOBAL_COUNTER_BITS-1:0] trained_value=train_taken?
          (&training_base?training_base:training_base+1'b1):
          (|training_base?training_base-1'b1:training_base);
        wire [GLOBAL_COUNTER_BITS-1:0] write_value=clearing?((1<<(GLOBAL_COUNTER_BITS-1))-1):trained_value;
        always @(posedge clk)begin
          training_old <= write_en && write_index==training_query ? write_value : training_mem[training_query];
          if(write_en)training_mem[write_index]<=write_value;
        end
        reg read0,read1,forwarded_value;
        reg [GLOBAL_BITS-1:0] read_identity0,read_identity1,write_identity;
        reg write_identity_valid;
        wire collision0=write_identity_valid && write_identity==read_identity0;
        wire collision1=write_identity_valid && write_identity==read_identity1;
        always @(posedge clk)begin
          read0<=direction0[next_index0][GLOBAL_COUNTER_BITS-1];
          read1<=direction1[next_index1][GLOBAL_COUNTER_BITS-1];
          if(write_en)begin
            direction0[write_index]<=write_value;
            direction1[write_index]<=write_value;
          end
          // Identities and read data advance on the same original edge.
          // This preserves same-edge write/read forwarding with no new cycle.
          read_identity0<=next_index0;read_identity1<=next_index1;
          write_identity<=write_index;write_identity_valid<=write_en;
          forwarded_value<=write_value[GLOBAL_COUNTER_BITS-1];
        end
        // synthesis translate_off
        reg reference_collision0,reference_collision1;
        always @(posedge clk)begin
          reference_collision0<=write_en && write_index==next_index0;
          reference_collision1<=write_en && write_index==next_index1;
        end
        always @(negedge clk)begin
          if(collision0!==reference_collision0 || collision1!==reference_collision1)
            $fatal(1,"PHT captured read/write identities lost collision version");
        end
        // synthesis translate_on
        assign global_direction={collision1?forwarded_value:read1,
                                 collision0?forwarded_value:read0} & {2{!clearing}};
      end else begin:asynchronous
        assign global_direction={bank_prediction[index1[BANK_BITS-1:0]],bank_prediction[index0[BANK_BITS-1:0]]} & {2{!clearing}};
      end
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
      if(!SYNC_GLOBAL)begin:legacy_banks
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

`timescale 1ns / 1ps

module JFIX_BPU_PAIR_byte_shared #(parameter GLOBAL_COUNTER_BITS=2, parameter ENABLE_JALR_BTB = 1, parameter RAW_TARGET_PAYLOAD=0,parameter PREPARED_QUERY_ROWS=0, parameter LOCAL_HISTORY_BITS=1,parameter REGISTER_TRAINING=0,parameter CACHED_DIRECTION=0,parameter HYBRID_LOCAL=0,parameter GLOBAL_BITS=0,parameter SPECULATIVE_GLOBAL=0,parameter TOURNAMENT_GLOBAL=0,parameter SYNC_GLOBAL=0,parameter CHOICE_HASH_INDEX=0,parameter ELIDE_TOURNAMENT_METADATA=0,parameter USE_PREINDEX1=0) (
    output [3:0] query_directions,input [1:0] training_directions,
    input [1:0] spec_count,spec_taken,input [12:0] recover_history,
    input [12:0] prediction_history,output [12:0] global_history,
    input wire        clk,
    input wire        rst,
    input wire [31:0] pc_if,pc_if1,
    input wire [31:0] next_query_pc0,next_query_pc1,
    input wire [12:0] prepared_next_index1,
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

    // Per-PC committed local history. Prediction is advisory; updates occur
    // once at architectural branch retirement, and never on a wrong path.
    localparam integer NC = 1 << LOCAL_HISTORY_BITS;
    localparam integer CB = 2*NC;
    localparam integer PW = CB + LOCAL_HISTORY_BITS + 1;
    wire [23:0] btb_word,btb_word1;wire [23:0] bank_target[0:1];wire [PW-1:0] bank_counter[0:1],bank_training[0:1];
    wire [PW-1:0] query_pht,query_pht1,training_pht;
    function automatic [1:0] saturate_counter(input [1:0] value,input taken);
      begin
        case(value)
          2'b00:saturate_counter=taken?2'b01:2'b00;
          2'b01:saturate_counter=taken?2'b10:2'b00;
          2'b10:saturate_counter=taken?2'b11:2'b01;
          default:saturate_counter=taken?2'b11:2'b10;
        endcase
      end
    endfunction
    function predict_local;
      input [PW-1:0] entry;
      reg [LOCAL_HISTORY_BITS-1:0] h;
      begin h=entry[CB+:LOCAL_HISTORY_BITS];
        predict_local=entry[PW-1] && entry[2*h+1];
      end
    endfunction
    wire [1:0] bank_direction;
    wire [5:0] bank_aux[0:1];
    // Retirement trains one PC per cycle. Both parity banks can share
    // a 512-row counter read port, addressed by the full PC row including parity.
    // Query directions remain independently readable from the existing caches.
    wire [LOCAL_HISTORY_BITS:0] metadata_read[0:1];
    wire [5:0] auxiliary_read[0:1];
    reg prior_write;reg [8:0] prior_row;
    reg [LOCAL_HISTORY_BITS-3:0] prior_byte_index;
    reg [7:0] prior_byte_value;
    wire collision=prior_write && prior_row==train_pc[10:2];
    always @(posedge clk)begin
      prior_write<=table_writing;
      prior_row<=train_pc[10:2];
      prior_byte_index<=table_write_column;prior_byte_value<=table_write_data;
    end
    wire [7:0] shared_raw_bytes[0:NC/4-1];
    wire [7:0] table_write_byte[0:1];
    wire [LOCAL_HISTORY_BITS-3:0] table_write_index[0:1];
    wire table_writing=!rst && !btb_initializing && train_update;
    wire [7:0] table_write_data=table_write_byte[train_pc[2]];
    wire [LOCAL_HISTORY_BITS-3:0] table_write_column=table_write_index[train_pc[2]];
    generate for(genvar shared_byte=0;shared_byte<NC/4;shared_byte=shared_byte+1)begin:training_bytes
      reg [7:0] words[0:511] /* synthesis syn_ramstyle="block_ram" */;
      reg [7:0] read_q;
      assign shared_raw_bytes[shared_byte]=read_q;
      always @(posedge clk)begin
        read_q<=words[pc_ex[10:2]];
        if(!rst)begin
          if(btb_initializing)begin
            words[btb_reset_index]<=8'h55;
            if(btb_reset_index==pc_ex[10:2])read_q<=8'h55;
          end else if(table_writing && table_write_column==shared_byte)
            words[train_pc[10:2]]<=table_write_data;
        end
      end
    end endgenerate
    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1)begin:parity_bank
     reg [23:0] targets[0:127] /* synthesis syn_ramstyle="lut_ram" */;
     wire [PW-1:0] counters_unused;
     reg [5:0] auxiliary[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     reg direction[0:255] /* synthesis syn_ramstyle="lut_ram" */;
     // Each physical bank updates its own read value. The bank bit only
     // qualifies writes, rather than selecting a wide training payload.
     wire [PW-1:0] captured_counter;
     reg [5:0] captured_auxiliary;
     wire [PW-1:0] training_read=captured_counter;
     // Initialize invalid rows to their canonical first-training value.
     // Validity still suppresses prediction, but training needs no wide mux.
     wire [PW-1:0] training_word=training_read;
     wire [LOCAL_HISTORY_BITS-1:0] train_history=training_word[CB+:LOCAL_HISTORY_BITS];
     wire [1:0] trained_counter=selected_byte[2*train_history[1:0]+:2];
     wire [1:0] next_counter=saturate_counter(trained_counter,train_taken);
     wire [LOCAL_HISTORY_BITS-1:0] next_history=(train_history << 1) | train_taken;
     wire long_next=(next_history==train_history)?next_counter[1]:next_byte[2*next_history[1:0]+1];
     reg [PW-1:0] updated_word;
     always @*begin
       updated_word=training_word;
       updated_word[PW-1]=1'b1;
       updated_word[CB+:LOCAL_HISTORY_BITS]=next_history;
       updated_word[2*train_history+:2]=next_counter;
     end
     wire [5:0] training_aux=auxiliary_read[train_pc[2]];
     wire [1:0] short_old=training_aux[2*train_history[0]+:2];
     wire [1:0] short_updated=saturate_counter(short_old,train_taken);
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

     // Capture the row of the incoming command. Forward the write performed
     // at this same edge, including reset sweep, to preserve asynchronous RAM
     // read-after-write behavior for consecutive commands to the same row.
     always @(posedge clk)begin

       captured_auxiliary<=auxiliary[pc_ex[10:3]];
       if(!rst)begin
         if(btb_initializing)begin
           if(btb_reset_index[0]==bank && btb_reset_index[8:1]==pc_ex[10:3])begin

             captured_auxiliary<=6'b100101;
           end
         end else if(train_pc[2]==bank && train_update && train_pc[10:3]==pc_ex[10:3])begin

           captured_auxiliary<=aux_next;
         end
       end
     end
     wire [31:0] query=pc_if[2]==bank?pc_if:pc_if1;
     wire [7:0] read_row=PREPARED_QUERY_ROWS?prepared_rows[bank*8+:8]:query[10:3];
     wire [23:0] target_read=targets[read_row[6:0]];
     wire [PW-1:0] counter_read=0;
     // Initialization writes constants and ignores the training read ports.
     // Keep the sweep address out of the high-fanout training data cone.
     assign bank_aux[bank]=auxiliary[train_pc[10:3]];
     wire [5:0] query_aux=auxiliary[read_row];
     wire query_direction=HYBRID_LOCAL?(query_aux[5]?predict_local(counter_read):
       (counter_read[PW-1] && query_aux[2*counter_read[CB]+1])):predict_local(counter_read);
     assign bank_direction[bank]=CACHED_DIRECTION?direction[read_row]:query_direction;
     assign bank_target[bank]=target_read;
     assign bank_counter[bank]=counter_read;
     assign bank_training[bank]=0;
     always @(posedge clk)if(!rst)begin
      if(btb_initializing)begin
       if(btb_reset_index[0]==bank)begin
        if(btb_reset_index<256)targets[btb_reset_index[7:1]]<=0;

        direction[btb_reset_index[8:1]]<=0;
        auxiliary[btb_reset_index[8:1]]<=6'b100101;
       end
      end else begin
       if(train_pc[2]==bank && train_update)auxiliary[train_pc[10:3]]<=aux_next;
       if(train_pc[2]==bank && train_update)direction[train_pc[10:3]]<=next_direction;

       if(train_pc[2]==bank && ((train_update && train_taken) || (ENABLE_JALR_BTB && train_jalr)))
        targets[train_pc[9:3]]<={
         train_pc[31:16]==16'h8000 && train_target[31:16]==16'h8000 && train_target[1:0]==0,
         ENABLE_JALR_BTB && train_jalr,train_pc[15:10],train_target[15:0]};
      end
     end
     wire writing=!rst && !btb_initializing && train_pc[2]==bank && train_update;
     reg [LOCAL_HISTORY_BITS:0] metadata[0:255] /* synthesis syn_ramstyle="block_ram" */;
     reg [LOCAL_HISTORY_BITS:0] metadata_q;
     wire [7:0] raw_bytes[0:NC/4-1];
     wire [7:0] selected_byte=collision && prior_byte_index==(train_history>>2)?prior_byte_value:raw_bytes[train_history>>2];
     wire [7:0] next_byte=collision && prior_byte_index==(next_history>>2)?prior_byte_value:raw_bytes[next_history>>2];
     reg [7:0] changed_byte;
     always @*begin
       changed_byte=selected_byte;
       case(train_history[1:0])
        0:changed_byte[1:0]=next_counter;
        1:changed_byte[3:2]=next_counter;
        2:changed_byte[5:4]=next_counter;
        3:changed_byte[7:6]=next_counter;
       endcase
     end
     assign metadata_read[bank]=metadata_q;
     assign auxiliary_read[bank]=captured_auxiliary;
     // Select the active training bank before the counter/chooser arithmetic.
     assign captured_counter={metadata_read[train_pc[2]],{CB{1'b0}}};
     always @(posedge clk)begin
       metadata_q<=metadata[pc_ex[10:3]];
       if(!rst)begin
         if(btb_initializing)begin
           if(btb_reset_index[0]==bank)begin
             metadata[btb_reset_index[8:1]]<=0;
             if(btb_reset_index[8:1]==pc_ex[10:3])metadata_q<=0;
           end
         end else if(writing)begin
           metadata[train_pc[10:3]]<={1'b1,next_history};
           if(train_pc[10:3]==pc_ex[10:3])metadata_q<={1'b1,next_history};
         end
       end
     end
     assign table_write_byte[bank]=changed_byte;
     assign table_write_index[bank]=train_history>>2;
     for(genvar byte_lane=0;byte_lane<NC/4;byte_lane=byte_lane+1)begin:local_byte_view
       assign raw_bytes[byte_lane]=shared_raw_bytes[byte_lane];
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
    assign query_directions=ELIDE_TOURNAMENT_METADATA?4'b0:{global_direction[1],bank_direction[pc_if1[2]],global_direction[0],bank_direction[pc_if[2]]};
    generate for(genvar tb=0;tb<2;tb=tb+1)begin:tournament
      // Context-sensitive local/global chooser; each bank clears its own
      // table, so uninitialized RAM never influences a prediction.
      reg [1:0] choice[0:1023] /* synthesis syn_ramstyle="lut_ram" */;
      reg [9:0] init_index;reg choice_clearing;
      wire [31:0] qp=pc_if[2]==tb?pc_if:pc_if1;
      wire [9:0] train_idx=train_pc[12:3] ^ train_snapshot[9:0] ^ {7'b0,train_pc[15:13]};
      wire [9:0] query_idx=qp[12:3] ^ global_history[9:0] ^ {7'b0,qp[15:13]};
      wire [1:0] old=choice[train_idx];
      wire win_global=train_directions[1]==train_taken;
      wire [1:0] next=win_global?(old==3?2'd3:old+2'd1):(old==0?2'd0:old-2'd1);
      assign choose_global[tb]=!choice_clearing && choice[query_idx][1];
      always @(posedge clk)begin
       if(rst)begin init_index<=0;choice_clearing<=1;end
       else if(choice_clearing)begin
        choice[init_index]<=2'd1;init_index<=init_index+1'b1;
        if(&init_index)choice_clearing<=0;
       end else if(train_update && train_pc[2]==tb && train_directions[0]!=train_directions[1])
        choice[train_idx]<=next;
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
      wire [GLOBAL_BITS-1:0] next_history=rst?{GLOBAL_BITS{1'b0}}:
        SPECULATIVE_GLOBAL?(mispredict_ex_r?recover_history[GLOBAL_BITS-1:0]:
          spec_count==2?((history<<2)|spec_taken):
          spec_count==1?((history<<1)|spec_taken[0]):history):
          train_update?((history<<1)|train_taken):history;
      wire [GLOBAL_BITS-1:0] next_index0=next_query_pc0[GLOBAL_BITS+1:2]^next_history;
      wire [GLOBAL_BITS-1:0] next_index1_reference=next_query_pc1[GLOBAL_BITS+1:2]^next_history;
      wire [GLOBAL_BITS-1:0] next_index1=USE_PREINDEX1?prepared_next_index1[GLOBAL_BITS-1:0]:next_index1_reference;
      // synthesis translate_off
      always @(posedge clk) if (!rst && USE_PREINDEX1 && next_index1!==next_index1_reference)
       $fatal(1,"lane 1 prepared prediction index changed identity");
      // synthesis translate_on
      if(SYNC_GLOBAL)begin:synchronous
        // Two prediction read copies and a counter-training copy.
        // Registered training reads ahead; same-index writes forward.
        reg [GLOBAL_COUNTER_BITS-1:0] direction0[0:(1<<GLOBAL_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
        reg [GLOBAL_COUNTER_BITS-1:0] direction1[0:(1<<GLOBAL_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
        wire write_en=!rst && (clearing || train_update);
        wire [GLOBAL_BITS-1:0] write_index=clearing?clear_index:update_index;
        reg [GLOBAL_COUNTER_BITS-1:0] training_mem[0:(1<<GLOBAL_BITS)-1] /* synthesis syn_ramstyle="block_ram" */;
        reg [GLOBAL_COUNTER_BITS-1:0] training_old;
        wire [GLOBAL_BITS-1:0] training_query=pc_ex[GLOBAL_BITS+1:2]^prediction_history[GLOBAL_BITS-1:0];
        wire [GLOBAL_COUNTER_BITS-1:0] training_base=REGISTER_TRAINING?training_old:training_mem[update_index];
        wire [GLOBAL_COUNTER_BITS-1:0] trained_value=train_taken?
          (&training_base?training_base:training_base+1'b1):
          (|training_base?training_base-1'b1:training_base);
        wire [GLOBAL_COUNTER_BITS-1:0] write_value=clearing?((1<<(GLOBAL_COUNTER_BITS-1))-1):trained_value;
        always @(posedge clk)begin
          training_old <= write_en && write_index==training_query ? write_value : training_mem[training_query];
          if(write_en)training_mem[write_index]<=write_value;
        end
        reg read0,read1,forwarded_value;
        reg [GLOBAL_BITS-1:0] read_identity0,read_identity1,write_identity;
        reg write_identity_valid;
        wire collision0=write_identity_valid && write_identity==read_identity0;
        wire collision1=write_identity_valid && write_identity==read_identity1;
        always @(posedge clk)begin
          read0<=direction0[next_index0][GLOBAL_COUNTER_BITS-1];
          read1<=direction1[next_index1][GLOBAL_COUNTER_BITS-1];
          if(write_en)begin
            direction0[write_index]<=write_value;
            direction1[write_index]<=write_value;
          end
          // Identities and read data advance on the same original edge.
          // This preserves same-edge write/read forwarding with no new cycle.
          read_identity0<=next_index0;read_identity1<=next_index1;
          write_identity<=write_index;write_identity_valid<=write_en;
          forwarded_value<=write_value[GLOBAL_COUNTER_BITS-1];
        end
        // synthesis translate_off
        reg reference_collision0,reference_collision1;
        always @(posedge clk)begin
          reference_collision0<=write_en && write_index==next_index0;
          reference_collision1<=write_en && write_index==next_index1;
        end
        always @(negedge clk)begin
          if(collision0!==reference_collision0 || collision1!==reference_collision1)
            $fatal(1,"PHT captured read/write identities lost collision version");
        end
        // synthesis translate_on
        assign global_direction={collision1?forwarded_value:read1,
                                 collision0?forwarded_value:read0} & {2{!clearing}};
      end else begin:asynchronous
        assign global_direction={bank_prediction[index1[BANK_BITS-1:0]],bank_prediction[index0[BANK_BITS-1:0]]} & {2{!clearing}};
      end
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
      if(!SYNC_GLOBAL)begin:legacy_banks
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


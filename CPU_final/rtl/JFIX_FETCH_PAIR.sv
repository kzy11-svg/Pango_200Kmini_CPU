// Two-way, 16 KiB instruction cache, 32-byte lines, paired synchronous reads.
// Backing ROM is accessed through the four-beat line refill target.
module JFIX_FETCH_PAIR #(parameter GLOBAL_HISTORY_BITS=13, GLOBAL_COUNTER_BITS=2, TOURNAMENT=0, LOCAL_BITS=2, CHOICE_HASH=1)(
 input clk,rst,input [31:0] pc,input ready,redirect,input [31:0] redirect_pc,
 output [19:0] fetch_way_rs0,fetch_way_rs1,output [1:0] fetch_way_select,fetch_way_zero,
 output [5:0] static_status,
 output [3:0] fetch_directions,input [1:0] branch_directions,
 output [12:0] fetch_history,input [12:0] branch_history,recover_history,
 output valid,output [63:0] instructions,output [1:0] faults,pred_taken,
 output [63:0] pred_target,
 input branch_commit,input [31:0] branch_pc,branch_inst,branch_target,
 output reg [7:0] debug_event_q
);
 wire [1:0] bpu_taken,ras_valid;
 wire [31:0] query_pc[0:1],bpu_target[0:1],ras_top[0:1];
 wire [4:0] histories[0:1];
 reg [31:0] response_pc;
 // Registered queue isolates prediction and cache response from rename.
 // Prediction history advances when a response is enqueued; each entry
 // carries that pre-prediction history until the corresponding ROB entry.
 reg [1:0] queue_count;
 reg queue_head,queue_tail;
 reg [3:0] queue_directions[0:1];wire [3:0] raw_directions;
 reg [12:0] queue_history[0:1];wire [12:0] global_history;
 reg [63:0] queue_inst[0:1],queue_target[0:1];
 reg [1:0] queue_fault[0:1],queue_taken[0:1];
 reg [5:0] queue_status[0:1];wire [5:0] bank_status,raw_status;
 reg response_valid;
 assign fetch_directions=queue_count!=0?queue_directions[queue_head]:raw_directions;
 assign fetch_history=queue_count!=0?queue_history[queue_head]:global_history;
 // synthesis translate_off
 reg [31:0] queue_pc[0:1];
 // synthesis translate_on
 wire [63:0] raw_inst,raw_target;
 wire [63:0] bank_words;wire [33:0] bank_jal,bank_jal_plus4;
 wire [31:0] prepared_taken_plus4[0:1];
 wire [19:0] bank_way_rs0,bank_way_rs1;wire [1:0] bank_way_select,bank_way_zero;
 wire [1:0] raw_fault,raw_taken;
 wire [63:0] backing_words;wire [33:0] backing_jal;wire [3:0] bank_control;
 wire [12:0] cache_address[0:1];wire [1:0] cache_fault;
 wire cache_ready,fill_req,fill_accept,fill_valid,fill_last,fill_ready,fill_error;
 // Elastic refill register isolates backing ROM and predecode from cache RAM.
 reg refill_valid;reg [63:0] refill_data;reg [33:0] refill_jal;
 reg refill_last,refill_error;
 wire refill_take=!refill_valid || fill_ready;
 always @(posedge clk)begin
  if(rst)refill_valid<=0;
  else if(refill_take)begin
   refill_valid<=fill_valid;
   if(fill_valid)begin refill_data<=backing_words;refill_jal<=backing_jal;
    refill_last<=fill_last;refill_error<=fill_error;end
  end
 end
 wire [31:0] fill_address;wire [12:0] backing_address;
 wire legal0=query_pc[0][31:16]==16'h8000 && query_pc[0][1:0]==0;
 wire legal1=query_pc[1][31:16]==16'h8000 && query_pc[1][1:0]==0;
 wire [1:0] cache_access=response_pc[2]?{legal0,legal1}:{legal1,legal0};
 ICACHE_PAIR #(.SET_BITS(8)) icache(.clk(clk),.rst(rst),.cancel(redirect),
  .lookup0(cache_address[0]),.lookup1(cache_address[1]),.access_mask(cache_access),
  .way_rs0(bank_way_rs0),.way_rs1(bank_way_rs1),.way_select(bank_way_select),.way_zero(bank_way_zero),
  .lookup_valid(response_valid),.ready(cache_ready),.data(bank_words),.jal(bank_jal),.jal_plus4(bank_jal_plus4),
  .control(bank_control),.status(bank_status),.branch_relative(),.fault(cache_fault),
  .req_valid(fill_req),.req_ready(fill_accept),.req_address(fill_address),
  .rvalid(refill_valid),.rready(fill_ready),.rdata(refill_data),.rjal(refill_jal),.rlast(refill_last),.rerror(refill_error));
 ICACHE_ROM_BURST target(.clk(clk),.rst(rst),.req_valid(fill_req),.req_ready(fill_accept),
  .req_address(fill_address),.rvalid(fill_valid),.rready(refill_take),.rlast(fill_last),.rerror(fill_error),
  .rom_address(backing_address));
 // Predictor query identity is captured alongside its ROM response.
 // Separate copies avoid the lane-one combinational PC+4 before BTB lookup.
 reg [31:0] predictor_pc0,predictor_pc1 /* synthesis syn_preserve=1, syn_maxfan=16 */;
 assign query_pc[0]=predictor_pc0;assign query_pc[1]=predictor_pc1;
 wire consume=queue_count!=0 && ready && !redirect;
 // Form both query PCs before the late cache control/taken selection.
 // The second global-PHT port must not add four after the target mux.
 wire [31:0] taken0_plus4 /* synthesis syn_keep=1 */ =prepared_taken_plus4[0];
 wire [31:0] taken1_plus4 /* synthesis syn_keep=1 */ =prepared_taken_plus4[1];
 wire [31:0] raw_next1=raw_taken[0]?taken0_plus4:
  raw_taken[1]?taken1_plus4:response_pc+32'd12;
 wire [31:0] raw_next=raw_taken[0]?raw_target[31:0]:
  raw_taken[1]?raw_target[63:32]:response_pc+8;
 // Credit is registered occupancy only: late rename ready cannot steer
 // the instruction RAM address. A full queue may pop before credit is
 // reused, while the second entry keeps decode supplied during that cycle.
 wire enqueue=response_valid && cache_ready && queue_count<2 && !redirect && !rst;
 wire direct_offer=(queue_count==0) && enqueue;
 wire direct_fire=direct_offer && ready;
 wire queue_enqueue=enqueue && !direct_fire;
 wire [31:0] rom_pc=redirect?redirect_pc:(rst || !response_valid)?pc:
  enqueue?raw_next:response_pc;
 wire [31:0] rom_pc1=redirect?redirect_pc+32'd4:(rst || !response_valid)?pc+32'd4:
  enqueue?raw_next1:response_pc+32'd4;
 // synthesis translate_off
 always @(posedge clk)if(rom_pc1!==rom_pc+32'd4)$fatal(1,"Parallel lane-one PC changed query identity");
 // synthesis translate_on
 always @(posedge clk)begin
  response_pc<=rom_pc;predictor_pc0<=rom_pc;predictor_pc1<=rom_pc1;
  if(rst)begin response_valid<=0;queue_count<=0;queue_head<=0;queue_tail<=0;end
  else begin
   response_valid<=1;
   if(redirect)begin queue_count<=0;queue_head<=0;queue_tail<=0;end
   else begin
    case({queue_enqueue,consume})
     2'b10:queue_count<=queue_count+1'b1;
     2'b01:queue_count<=queue_count-1'b1;
    endcase
    if(consume)queue_head<=!queue_head;
    if(queue_enqueue)begin
     queue_tail<=!queue_tail;
     queue_history[queue_tail]<=global_history;
     queue_directions[queue_tail]<=raw_directions;
     queue_inst[queue_tail]<=raw_inst;queue_target[queue_tail]<=raw_target;
     queue_fault[queue_tail]<=raw_fault;queue_taken[queue_tail]<=raw_taken;
     queue_status[queue_tail]<=raw_status;
     // synthesis translate_off
     queue_pc[queue_tail]<=response_pc;
     // synthesis translate_on
    end
   end
  end
 end
 // When queued, both ways carry the already selected instruction fields.
 // When bypassing the queue, preserve the same bank-to-lane swap as raw_inst.
 genvar waylane;
 generate for(waylane=0;waylane<2;waylane=waylane+1) begin:way_identity
  wire [9:0] queued_fields={queue_inst[queue_head][waylane*32+20+:5],queue_inst[queue_head][waylane*32+15+:5]};
  assign fetch_way_rs0[waylane*10+:10]=queue_count!=0?queued_fields:
   (response_pc[2]?bank_way_rs0[(1-waylane)*10+:10]:bank_way_rs0[waylane*10+:10]);
  assign fetch_way_rs1[waylane*10+:10]=queue_count!=0?queued_fields:
   (response_pc[2]?bank_way_rs1[(1-waylane)*10+:10]:bank_way_rs1[waylane*10+:10]);
  assign fetch_way_select[waylane]=queue_count!=0?1'b0:
   (response_pc[2]?bank_way_select[1-waylane]:bank_way_select[waylane]);
  assign fetch_way_zero[waylane]=queue_count!=0?1'b0:
   (response_pc[2]?bank_way_zero[1-waylane]:bank_way_zero[waylane]);
 end endgenerate
 assign static_status=queue_count!=0?queue_status[queue_head]:raw_status;
 assign instructions=queue_count!=0?queue_inst[queue_head]:raw_inst;
 assign faults=queue_count!=0?queue_fault[queue_head]:raw_fault;
 assign pred_taken=queue_count!=0?queue_taken[queue_head]:raw_taken;
 assign pred_target=queue_count!=0?queue_target[queue_head]:raw_target;
 // synthesis translate_off
 always @(posedge clk)if(!rst && !redirect)begin
  if(queue_count>2)$fatal(1,"Fetch queue overflow");
  if(valid && (queue_count!=0?queue_pc[queue_head]:response_pc)!==pc)$fatal(1,"Fetch queue PC discontinuity");
 end
 // synthesis translate_on
 wire call_hint=(branch_inst[6:0]==7'h6f || branch_inst[6:0]==7'h67) &&
  (branch_inst[11:7]==1 || branch_inst[11:7]==5);
 wire return_hint=branch_inst[6:0]==7'h67 && (branch_inst[19:15]==1 || branch_inst[19:15]==5) &&
  (!call_hint || branch_inst[19:15]!=branch_inst[11:7]);
 wire [15:0] prepared_rows;
 wire prediction_branch0=enqueue && raw_inst[6:0]==7'h63;
 wire prediction_branch1=enqueue && !raw_taken[0] && raw_inst[38:32]==7'h63;
 wire [1:0] prediction_count={1'b0,prediction_branch0}+{1'b0,prediction_branch1};
 // Two consumed conditional branches append older then younger outcome.
 wire [1:0] prediction_outcomes={raw_taken[0],prediction_branch1?raw_taken[1]:raw_taken[0]};
 // Register the committed training command as one identity. RAS and
 // redirect remain on their existing paths. A command is either accepted
 // once each cycle or absent; the predictor receives it one cycle later.
 reg train_cmd_valid;
 reg [31:0] train_cmd_pc,train_cmd_inst,train_cmd_target;
 reg [12:0] train_cmd_history;
 reg [1:0] train_cmd_directions;
 always @(posedge clk) begin
  if (rst) train_cmd_valid<=1'b0;
  else begin
   train_cmd_valid<=branch_commit;
   if (branch_commit) begin
    train_cmd_pc<=branch_pc;train_cmd_inst<=branch_inst;
    train_cmd_target<=branch_target;train_cmd_history<=branch_history;
    train_cmd_directions<=branch_directions;
   end
  end
 end
 // Compute each next-query index in parallel before late next-PC selection.
 // This frontend instantiates the predictor in speculative-global mode.
 wire [12:0] prepared_history=rst?13'b0:redirect?recover_history:
  prediction_count==2?((global_history<<2)|prediction_outcomes):
  prediction_count==1?((global_history<<1)|prediction_outcomes[0]):global_history;
 wire [31:0] redirect_plus4_index=redirect_pc+32'd4;
 wire [31:0] pc_plus4_index=pc+32'd4;
 wire [31:0] response_plus4_index=response_pc+32'd4;
 wire [31:0] response_plus12_index=response_pc+32'd12;
 wire [12:0] preidx_redirect=redirect_plus4_index[14:2]^prepared_history;
 wire [12:0] preidx_pc=pc_plus4_index[14:2]^prepared_history;
 wire [12:0] preidx_hold=response_plus4_index[14:2]^prepared_history;
 wire [12:0] preidx_seq=response_plus12_index[14:2]^prepared_history;
 wire [12:0] preidx_t0=taken0_plus4[14:2]^prepared_history;
 wire [12:0] preidx_t1=taken1_plus4[14:2]^prepared_history;
 wire [12:0] preidx_next=raw_taken[0]?preidx_t0:raw_taken[1]?preidx_t1:preidx_seq;
 wire [12:0] prepared_next_index1=redirect?preidx_redirect:(rst || !response_valid)?preidx_pc:
  enqueue?preidx_next:preidx_hold;
 JFIX_BPU_PAIR #(.GLOBAL_COUNTER_BITS(GLOBAL_COUNTER_BITS),.RAW_TARGET_PAYLOAD(1),.PREPARED_QUERY_ROWS(1),.LOCAL_HISTORY_BITS(LOCAL_BITS),.REGISTER_TRAINING(1),.CACHED_DIRECTION(1),.HYBRID_LOCAL(1),.TOURNAMENT_GLOBAL(TOURNAMENT),.ELIDE_TOURNAMENT_METADATA(!TOURNAMENT),.SPECULATIVE_GLOBAL(1),.GLOBAL_BITS(GLOBAL_HISTORY_BITS),.SYNC_GLOBAL(1),.CHOICE_HASH_INDEX(CHOICE_HASH),.USE_PREINDEX1(1)) predictor_pair(
  .query_directions(raw_directions), .training_directions(train_cmd_directions),.spec_count(prediction_count),.spec_taken(prediction_outcomes),.recover_history(recover_history), .prediction_history(train_cmd_history),.global_history(global_history),.clk(clk),.rst(rst),.pc_if(query_pc[0]),.pc_if1(query_pc[1]),.next_query_pc0(rom_pc),.next_query_pc1(rom_pc1),.prepared_next_index1(prepared_next_index1),.prepared_rows(prepared_rows),.pc_add4_if(query_pc[0]+4),
  .pred_taken(bpu_taken[0]),.pred_taken1(bpu_taken[1]),
  .pred_target(bpu_target[0]),.pred_target1(bpu_target[1]),.ghr_if_out(histories[0]),
  .ras_push(branch_commit && call_hint),.ras_pop(branch_commit && return_hint),.ras_push_addr(branch_pc+4),
  .ras_valid(ras_valid[0]),.ras_top(ras_top[0]),
  .jalr_update_en(train_cmd_valid && (train_cmd_inst[6:0]==7'h67 || train_cmd_inst[6:0]==7'h6f)),
  .update_en(train_cmd_valid && train_cmd_inst[6:0]==7'h63),.mispredict_ex_r(redirect),
  .pc_ex(train_cmd_pc),.actual_taken(train_cmd_target!=train_cmd_pc+4),.actual_target(train_cmd_target),.ghr_ex_in(5'b0));
 assign histories[1]=histories[0];assign ras_valid[1]=ras_valid[0];assign ras_top[1]=ras_top[0];
 genvar g;
 generate for(g=0;g<2;g=g+1)begin:port
  // Even bank advances when the bundle starts at an odd word. The odd
  // bank always reads the base row. Response parity swaps the two outputs.
  wire [12:0] direct_bank=redirect_pc[15:3]+((g==0)?redirect_pc[2]:1'b0);
  wire [12:0] initial_bank=pc[15:3]+((g==0)?pc[2]:1'b0);
  wire [12:0] held_bank=response_pc[15:3]+((g==0)?response_pc[2]:1'b0);
  wire [12:0] taken0_bank=raw_target[15:3]+((g==0)?raw_target[2]:1'b0);
  wire [12:0] taken1_bank=raw_target[47:35]+((g==0)?raw_target[34]:1'b0);
  wire [12:0] sequential_bank=response_pc[15:3]+13'd1+((g==0)?response_pc[2]:1'b0);
  wire [12:0] next_bank=raw_taken[0]?taken0_bank:raw_taken[1]?taken1_bank:sequential_bank;
  wire [12:0] bank_addr=redirect?direct_bank:(rst || !response_valid)?initial_bank:
   enqueue?next_bank:held_bank;
  // synthesis translate_off
  wire [12:0] reference_bank=rom_pc[15:3]+((g==0)?rom_pc[2]:1'b0);
  always @(posedge clk)if(!rst && bank_addr!==reference_bank)$fatal(1,"Bank address transform mismatch");
  // synthesis translate_on
  assign cache_address[g]=bank_addr;
  wire [13:0] rom_addr={1'b0,backing_address};
  // Capture the same row already prepared for the synchronous instruction
  // bank. Its predictor lookup then starts directly at a registered row.
  reg [7:0] predictor_row /* synthesis syn_preserve=1, syn_maxfan=8 */;
  always @(posedge clk)predictor_row<=bank_addr[7:0];
  assign prepared_rows[g*8+:8]=predictor_row;
  wire range_fault=query_pc[g]<32'h80000000 || query_pc[g]>=32'h80010000 || |query_pc[g][1:0];
  wire [16:0] rom_jal=response_pc[2]?bank_jal[(1-g)*17+:17]:bank_jal[g*17+:17];
  INST_MEM #(.BANK(g)) rom(.clka(clk),.addra(rom_addr),.douta(backing_words[g*32+:32]),.jal_metadata(backing_jal[g*17+:17]));
  assign raw_status[g*3+:3]=response_pc[2]?bank_status[(1-g)*3+:3]:bank_status[g*3+:3];
  assign raw_inst[g*32+:32]=response_pc[2]?bank_words[(1-g)*32+:32]:bank_words[g*32+:32];
  assign raw_fault[g]=range_fault || (response_pc[2]?cache_fault[1-g]:cache_fault[g]);
  wire [31:0] ins=raw_inst[g*32+:32];
  wire direct_jal=rom_jal[16];
  wire [31:0] direct_target={16'h8000,rom_jal[15:0]};
  wire [16:0] direct_plus4_low=response_pc[2]?bank_jal_plus4[(1-g)*17+:17]:bank_jal_plus4[g*17+:17];
  wire [31:0] direct_plus4={15'h4000,direct_plus4_low};
  wire [1:0] control_word=response_pc[2]?bank_control[(1-g)*2+:2]:bank_control[g*2+:2];
  wire is_control=control_word[0];
  wire predict_return=control_word[1];
  // synthesis translate_off
  always @(posedge clk)if(!rst && response_valid && cache_ready && raw_taken[g] &&
   !direct_jal && !(predict_return && ras_valid[g]))begin
   if(!bpu_taken[g] || !(g==0?predictor_pair.btb_hit:predictor_pair.btb_hit1))
    $fatal(1,"Unqualified BTB target consumed without taken/hit permission");
  end
  // synthesis translate_on
  assign raw_taken[g]=!raw_fault[g] &&
   (direct_jal || (is_control && ((predict_return && ras_valid[g]) || bpu_taken[g])));
  assign raw_target[g*32+:32]=direct_jal?direct_target:predict_return && ras_valid[g]?ras_top[g]:bpu_target[g];
  assign prepared_taken_plus4[g]=direct_jal?direct_plus4:
   predict_return && ras_valid[g]?(ras_top[g]+32'd4):(bpu_target[g]+32'd4);
  // synthesis translate_off
  always @(posedge clk)if(!rst && response_valid && cache_ready && !raw_fault[g] &&
   !$isunknown({raw_target[g*32+:32],prepared_taken_plus4[g]}))begin
   if(prepared_taken_plus4[g] !== raw_target[g*32+:32]+32'd4)
    $fatal(1,"Candidate JAL/BTB/RAS target+4 changed");
  end
  // synthesis translate_on
 end endgenerate
 assign valid=queue_count!=0 || direct_offer;
 // Passive local sampling; observer outputs never affect fetch credit/address.
 always @(posedge clk)begin
  if(rst)debug_event_q<=0;
  else debug_event_q<={enqueue,ready,valid,redirect,queue_count,cache_ready,response_valid};
 end

endmodule

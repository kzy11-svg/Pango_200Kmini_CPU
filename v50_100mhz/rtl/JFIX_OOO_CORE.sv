// JFIX dual integer out-of-order prototype. No external generated core.
// Fixed 16-entry ROB and 48-entry PRF; serial side effects only at ROB head.
module JFIX_OOO_CORE #(parameter ROB_ENTRIES=8,
 parameter ROB_BITS=$clog2(ROB_ENTRIES),parameter PRF_ENTRIES=32+ROB_ENTRIES)(
 input clk,rst,enable,
 output reg [31:0] fetch_pc, input fetch_valid,
 input [63:0] fetch_inst, input [1:0] fetch_fault,
 input [1:0] fetch_pred_taken,input [63:0] fetch_pred_target,
 output fetch_ready, output redirect,output [31:0] redirect_pc,
 output branch_commit,output [31:0] branch_pc,branch_inst,branch_target,
 output serial_valid, input serial_ready,
 output [31:0] serial_inst,serial_pc,serial_src0,serial_src1,
 input serial_rsp_valid, output serial_rsp_ready,
 input [31:0] serial_result, input serial_fault,
 input [31:0] serial_cause,serial_tval,
 input serial_restart, input [31:0] serial_target,
 input irq_valid, input [31:0] irq_cause,trap_vector,
 output trap_valid, output [31:0] trap_pc,trap_cause,trap_tval,
 output [1:0] retire_count,
 output [63:0] retire_pc,retire_inst,retire_data,
 output [9:0] retire_rd, output [1:0] retire_write,
 output [1:0] issue_count, output [4:0] rob_occupancy
);
 reg [5:0] speculative_map[0:31],committed_map[0:31];
 wire [1:0] bypass_tag_valid;wire [11:0] completion_dest;
 // Three single-writer RAM banks plus a local last-writer selector.
 // Selector 3 denotes the reset value zero; data RAMs do not need reset.
 reg [31:0] prf_bank0[0:PRF_ENTRIES-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg [31:0] prf_bank1[0:PRF_ENTRIES-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg [31:0] prf_bank2[0:PRF_ENTRIES-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg [1:0] prf_owner[0:PRF_ENTRIES-1];
 reg [PRF_ENTRIES-1:0] physical_ready,free_mask;
 reg serial_wb_valid;reg [5:0] serial_wb_dest;reg [31:0] serial_wb_data;
 `define JFIX_PRF_READ(address) ((serial_wb_valid && serial_wb_dest==(address))?serial_wb_data:((prf_owner[address]==0)?prf_bank0[address]:((prf_owner[address]==1)?prf_bank1[address]:((prf_owner[address]==2)?prf_bank2[address]:32'b0))))
 reg [PRF_ENTRIES-1:0] committed_live;
 reg [ROB_ENTRIES-1:0] rob_source0_ready,rob_source1_ready,rob_prediction_wrong;
 reg [ROB_ENTRIES-1:0] rob_valid,rob_done,rob_issued,rob_exception,rob_write,rob_restart;
 // Resident code is in 0x80000000..0x8000ffff. Invalid fetches retain
 // their full PC in the exception payload, never truncated for mepc/tval.
 reg [15:0] rob_pc_low[0:ROB_ENTRIES-1];reg [ROB_ENTRIES-1:0] rob_fetch_fault;
 wire [31:0] rob_pc[0:ROB_ENTRIES-1];
 reg [31:0] rob_inst[0:ROB_ENTRIES-1],rob_value[0:ROB_ENTRIES-1];
 reg [31:0] rob_control_value[0:ROB_ENTRIES-1],rob_predpc[0:ROB_ENTRIES-1],rob_cause[0:ROB_ENTRIES-1];
 wire [31:0] rob_nextpc[0:ROB_ENTRIES-1],rob_tval[0:ROB_ENTRIES-1];
 reg [5:0] rob_src0[0:ROB_ENTRIES-1],rob_src1[0:ROB_ENTRIES-1],rob_dest[0:ROB_ENTRIES-1],rob_old[0:ROB_ENTRIES-1];
 reg [4:0] rob_rd[0:ROB_ENTRIES-1];reg [1:0] rob_kind[0:ROB_ENTRIES-1];
 reg [ROB_BITS-1:0] head,tail,serial_slot;reg [4:0] count;reg serial_pending,irq_pending;
 reg [31:0] pending_irq_cause;
 reg serial_request_valid;reg [ROB_BITS-1:0] serial_request_slot;
 reg [31:0] serial_request_inst,serial_request_pc;
 reg [31:0] serial_request_a,serial_request_b /* synthesis syn_preserve=1 */;
 wire [4:0] rs1[0:1],rs2[0:1],rd[0:1],op[0:1],zop[0:1];
 wire [31:0] imm[0:1];wire [1:0] kind[0:1];
 wire [1:0] use1,use2,wrd,src_pc,src_imm,illegal,ecall,ebreak;
 genvar g;
 generate for(g=0;g<2;g=g+1)begin:d
  JFIX_OOO_DECODE decode(.inst(fetch_inst[g*32+:32]),.rs1(rs1[g]),.rs2(rs2[g]),.rd(rd[g]),
   .use1(use1[g]),.use2(use2[g]),.write_rd(wrd[g]),.op(op[g]),.zop(zop[g]),.imm(imm[g]),
   .src_pc(src_pc[g]),.src_imm(src_imm[g]),.kind(kind[g]),
   .illegal(illegal[g]),.ecall(ecall[g]),.ebreak(ebreak[g]));
 end endgenerate
 reg [5:0] allocation0,allocation1; reg have0,have1;
 reg [PRF_ENTRIES-1:0] allocation_mask0,allocation_mask1,free_remaining;
 integer a,p;
 always @* begin
  allocation_mask0=free_mask & (~free_mask+1'b1);
  free_remaining=free_mask & ~allocation_mask0;
  allocation_mask1=free_remaining & (~free_remaining+1'b1);
  have0=|allocation_mask0;have1=|allocation_mask1;
  allocation0=0;allocation1=0;
  for(p=1;p<PRF_ENTRIES;p=p+1)begin
   if(allocation_mask0[p])allocation0=allocation0 | p;
   if(allocation_mask1[p])allocation1=allocation1 | p;
  end
 end
 wire [ROB_BITS-1:0] second_head=head+4'd1,second_tail=tail+4'd1;
 // Retirement is conservative at control/serial boundaries.
 wire head_ready=count!=0 && rob_done[head];
 wire head_load=rob_kind[head]==2 && rob_inst[head][6:0]==7'h03 && !rob_restart[head];
 wire second_load=rob_kind[second_head]==2 && rob_inst[second_head][6:0]==7'h03 && !rob_restart[second_head];
 // A completed head transaction may already have an irreversible side effect.
 // Retire it before taking the pending interrupt; never replay it via mepc.
 wire take_irq=irq_pending && irq_valid && !serial_pending &&
  !(head_ready && rob_kind[head]==2 && !rob_exception[head]) && enable;
 wire sync_fault=head_ready && rob_exception[head] && !take_irq && !serial_pending;
 wire retire0=head_ready && !rob_exception[head] && !take_irq && enable &&
  (!serial_pending || rob_kind[head]==0 || rob_kind[head]==3 || head_load);
 wire control_redirect=retire0 &&
  (rob_restart[head] || (rob_kind[head]==1 && rob_prediction_wrong[head]));
 wire second_branch_safe=rob_kind[second_head]==1 && !rob_restart[second_head] &&
  !rob_prediction_wrong[second_head];
 wire retire1=retire0 && !control_redirect && (rob_kind[head]!=2 || head_load) && count>1 &&
  rob_done[second_head] && !rob_exception[second_head] &&
  (rob_kind[second_head]==0 || rob_kind[second_head]==3 || second_load ||
   (rob_kind[head]!=1 && second_branch_safe)) &&
  (!serial_pending || rob_kind[second_head]==0 || rob_kind[second_head]==3 || second_load);
 wire flush_now=take_irq || (sync_fault && enable) || control_redirect;
 assign redirect=flush_now;
 assign redirect_pc=trap_valid?trap_vector:rob_nextpc[head];
 wire [ROB_BITS-1:0] branch_commit_slot=(retire0 && rob_kind[head]==1)?head:second_head;
 assign branch_commit=(retire0 && rob_kind[head]==1) || (retire1 && rob_kind[second_head]==1);
 assign branch_pc=rob_pc[branch_commit_slot];assign branch_inst=rob_inst[branch_commit_slot];
 assign branch_target=rob_nextpc[branch_commit_slot];
 assign trap_valid=enable && (take_irq || sync_fault);
 assign trap_pc=count!=0?rob_pc[head]:fetch_pc;
 assign trap_cause=take_irq?pending_irq_cause:rob_cause[head];
 assign trap_tval=take_irq?0:rob_tval[head];
 assign retire_count={1'b0,retire0}+{1'b0,retire1};
 assign retire_pc={rob_pc[second_head],rob_pc[head]};
 assign retire_inst={rob_inst[second_head],rob_inst[head]};
 assign retire_data={rob_value[second_head],rob_value[head]};
 assign retire_rd={rob_rd[second_head],rob_rd[head]};
 assign retire_write={retire1 && rob_write[second_head],retire0 && rob_write[head]};
 assign rob_occupancy=count;
 assign fetch_ready=enable && !flush_now && !irq_pending && count<=(ROB_ENTRIES-2) &&
  ((!wrd[0] && !wrd[1]) || (have0 && (!(wrd[0] && wrd[1]) || have1)));
 wire allocate=fetch_valid && fetch_ready;
 wire [1:0] allocation_count=fetch_pred_taken[0]?2'd1:2'd2;
 wire [5:0] dest0=wrd[0]?allocation0:0;
 wire [5:0] dest1=wrd[1]?(wrd[0]?allocation1:allocation0):0;
 wire [5:0] rename_a[0:1],rename_b[0:1],rename_old[0:1];
 wire [1:0] bundle_raw_a,bundle_raw_b;
 assign bundle_raw_a={wrd[0] && use1[1] && rs1[1]==rd[0],1'b0};
 assign bundle_raw_b={wrd[0] && use2[1] && rs2[1]==rd[0],1'b0};
 assign rename_a[0]=use1[0]?speculative_map[rs1[0]]:0;
 assign rename_b[0]=use2[0]?speculative_map[rs2[0]]:0;
 assign rename_a[1]=bundle_raw_a[1]?dest0:use1[1]?speculative_map[rs1[1]]:0;
 assign rename_b[1]=bundle_raw_b[1]?dest0:use2[1]?speculative_map[rs2[1]]:0;
 assign rename_old[0]=speculative_map[rd[0]];
 assign rename_old[1]=wrd[0] && rd[1]==rd[0]?dest0:speculative_map[rd[1]];
 // Only a normal, aligned BRAM load may execute before reaching the head.
 // The first incomplete serial operation is an ordering barrier; no store,
 // MMIO, CSR, custom command or load passes it. One transaction is in flight.
 reg serial_select_valid;reg [ROB_BITS-1:0] serial_select_slot;
 reg [ROB_ENTRIES-1:0] age_upper_mask;
 wire [ROB_BITS-1:0] head_after_retire=head+retire_count;
 reg [ROB_ENTRIES-1:0] serial_candidates,serial_upper,serial_absolute;
 integer q;reg serial_found;
 always @* begin
  serial_select_valid=0;serial_select_slot=0;serial_candidates=0;
  for(q=0;q<ROB_ENTRIES;q=q+1)
   serial_candidates[q]=rob_valid[q] && (rob_exception[q] ||
    (rob_kind[q]==2 && !rob_done[q] && !rob_issued[q]));
  serial_upper=serial_candidates & age_upper_mask;
  serial_absolute=(|serial_upper)?(serial_upper & (~serial_upper+1'b1)):
    (serial_candidates & (~serial_candidates+1'b1));
  serial_found=|serial_candidates;
  for(q=0;q<ROB_ENTRIES;q=q+1)if(serial_absolute[q])serial_select_slot=serial_select_slot | q;
  serial_select_valid=serial_found && !rob_exception[serial_select_slot] &&
   source_ready(rob_src0[serial_select_slot],rob_source0_ready[serial_select_slot],bypass_tag_valid,completion_dest) &&
   source_ready(rob_src1[serial_select_slot],rob_source1_ready[serial_select_slot],bypass_tag_valid,completion_dest);
 end
 // A one-entry lookahead buffer may capture young commands, but only normal
 // BRAM loads may publish before reaching the retirement head.
 wire [31:0] request_address=serial_request_a+
  {{20{serial_request_inst[31]}},serial_request_inst[31:20]};
 wire request_normal_load=serial_request_inst[6:0]==7'h03 && request_address[31:18]==14'h2004 &&
  !(serial_request_inst[13:12]==1 && request_address[0]) &&
  !(serial_request_inst[13:12]==2 && |request_address[1:0]);
 wire serial_accept;
 wire serial_capture=enable && serial_select_valid && (!serial_request_valid || serial_accept) && !flush_now && !irq_pending;
 assign serial_valid=enable && serial_request_valid && !serial_pending && !flush_now && !irq_pending &&
  (serial_request_slot==head || request_normal_load);
 assign serial_inst=serial_request_inst;assign serial_pc=serial_request_pc;
 assign serial_src0=serial_request_a;assign serial_src1=serial_request_b;
 assign serial_rsp_ready=(serial_pending || (serial_valid && serial_ready)) && !flush_now && enable;
 assign serial_accept=serial_valid && serial_ready;
 wire serial_complete=serial_rsp_valid && serial_rsp_ready;

 reg [1:0] execute_valid,execute_write,execute_mul,execute_mul_started;reg [ROB_BITS-1:0] execute_slot[0:1];
 reg [5:0] execute_dest[0:1];
 reg [31:0] execute_inst[0:1],execute_pc[0:1],execute_a[0:1],execute_b[0:1],execute_predpc[0:1];
 wire [31:0] execute_result[0:1],integer_result[0:1],execute_next[0:1],multiply_result[0:1];wire [1:0] execute_fault;
 // Completion bypass is local to issue. Faulting results never wake users.
 wire [1:0] execute_complete=execute_valid & (~execute_mul | execute_mul_started);
 wire [1:0] execute_hold=execute_valid & execute_mul & ~execute_mul_started;
 reg [1:0] read_valid,read_write,read_mul;
 reg [ROB_BITS-1:0] read_slot[0:1];reg [5:0] read_src0[0:1],read_src1[0:1],read_dest[0:1];
 reg [31:0] read_inst[0:1],read_pc[0:1],read_predpc[0:1];
 // Candidate identity and port capacity are independent of global recovery.
 // Recovery gates acceptance below; it need not steer the data-selection tree.
 wire [1:0] read_transfer=read_valid & ~execute_hold;
 wire [1:0] read_fire=read_transfer & {2{enable && !flush_now}};
 wire [1:0] read_available=~execute_hold;
 // Compact-window experiment: direct operand sampling at issue. A consumer
 // may use completed results, but cannot anticipate a not-yet-sampled MUL.
 wire [1:0] early_valid=2'b0;
 wire [11:0] early_dest={execute_hold[1]?execute_dest[1]:read_dest[1],
  execute_hold[0]?execute_dest[0]:read_dest[0]};
 // Wakeup depends on identity/latency, not ALU alignment evaluation.
 // A faulting producer may wake speculative work; ordered retirement cancels
 // all of it before any architectural side effect can be published.
 assign bypass_tag_valid={execute_complete[1] && execute_write[1],
  execute_complete[0] && execute_write[0]};
 wire [1:0] completion_valid={execute_complete[1] && execute_write[1] && !execute_fault[1],
  execute_complete[0] && execute_write[0] && !execute_fault[0]};
 assign completion_dest={execute_dest[1],execute_dest[0]};
 wire [63:0] completion_data={execute_result[1],execute_result[0]};
 function automatic source_ready(input [5:0] address,input base_ready,
   input [1:0] completed,input [11:0] destinations);
  integer b;
  begin source_ready=base_ready;
   for(b=0;b<2;b=b+1)
    if(completed[b] && destinations[b*6+:6]==address)source_ready=1;
  end
 endfunction
 function automatic [31:0] source_value(input [5:0] address,input [31:0] base_value,
   input [1:0] completed,input [11:0] destinations,input [63:0] values);
  integer b;
  begin source_value=base_value;
   for(b=0;b<2;b=b+1)
    if(completed[b] && destinations[b*6+:6]==address)source_value=values[b*32+:32];
  end
 endfunction
 // Age-order selection over the ROB resident scheduling window.
 reg [1:0] select_valid,select_capture_valid;reg [ROB_BITS-1:0] select_slot[0:1];
 integer k,slot;
 reg [ROB_ENTRIES-1:0] issue_candidates,issue_upper,issue_remaining,issue_remaining_upper;
 reg [ROB_ENTRIES-1:0] issue_absolute0,issue_absolute1;
 always @* begin
  select_valid=0;select_capture_valid=0;select_slot[0]=0;select_slot[1]=0;issue_candidates=0;
  for(k=0;k<ROB_ENTRIES;k=k+1)
   issue_candidates[k]=rob_valid[k] && !rob_issued[k] && !rob_done[k] && rob_kind[k]!=2 &&
    (source_ready(rob_src0[k],rob_source0_ready[k],bypass_tag_valid,completion_dest) ||
     source_ready(rob_src0[k],1'b0,early_valid,early_dest)) &&
    (source_ready(rob_src1[k],rob_source1_ready[k],bypass_tag_valid,completion_dest) ||
     source_ready(rob_src1[k],1'b0,early_valid,early_dest));
  // Select from [head,15] first, then wrap to [0,head-1].
  // No rotate/unrotate barrel network is needed for age ordering.
  issue_upper=issue_candidates & age_upper_mask;
  issue_absolute0=(|issue_upper)?(issue_upper & (~issue_upper+1'b1)):
    (issue_candidates & (~issue_candidates+1'b1));
  issue_remaining=issue_candidates & ~issue_absolute0;
  issue_remaining_upper=issue_remaining & age_upper_mask;
  issue_absolute1=(|issue_remaining_upper)?(issue_remaining_upper & (~issue_remaining_upper+1'b1)):
    (issue_remaining & (~issue_remaining+1'b1));
  for(k=0;k<ROB_ENTRIES;k=k+1)begin
   if(issue_absolute0[k])select_slot[0]=select_slot[0] | k;
   if(issue_absolute1[k])select_slot[1]=select_slot[1] | k;
  end
  select_valid={|issue_absolute1,|issue_absolute0};
  if(!read_available[0])begin
   select_slot[1]=select_slot[0];select_valid[1]=select_valid[0];select_valid[0]=0;
  end
  if(!read_available[1])select_valid[1]=0;
  select_capture_valid=select_valid;
  if(!enable || flush_now)select_valid=0;
 end
 assign issue_count={1'b0,select_valid[0]}+{1'b0,select_valid[1]};
 wire [1:0] fast_mul;
 reg [ROB_ENTRIES-1:0] mul_ready_candidates,mul_ready_upper,mul_ready_onehot;
 reg [ROB_BITS-1:0] mul_sample_slot;integer ms;
 always @* begin
  mul_ready_candidates=0;mul_sample_slot=0;
  for(ms=0;ms<ROB_ENTRIES;ms=ms+1)
   mul_ready_candidates[ms]=rob_valid[ms] && !rob_issued[ms] && !rob_exception[ms] && rob_kind[ms]==3 && rob_source0_ready[ms] && rob_source1_ready[ms];
  mul_ready_upper=mul_ready_candidates & age_upper_mask;
  mul_ready_onehot=(|mul_ready_upper)?(mul_ready_upper & (~mul_ready_upper+1'b1)):(mul_ready_candidates & (~mul_ready_candidates+1'b1));
  for(ms=0;ms<ROB_ENTRIES;ms=ms+1)if(mul_ready_onehot[ms])mul_sample_slot=mul_sample_slot | ms;
 end
 wire [31:0] issue_base_a[0:1],issue_base_b[0:1];
 generate for(g=0;g<2;g=g+1)begin:early_multiply
  assign issue_base_a[g]=`JFIX_PRF_READ(rob_src0[mul_sample_slot]);
  assign issue_base_b[g]=`JFIX_PRF_READ(rob_src1[mul_sample_slot]);
  // Only previously registered readiness permits the early DSP edge. A
  // same-cycle producer bypass retains the operand-register/hold path.
  assign fast_mul[g]=select_valid[g] && (|mul_ready_onehot) && select_slot[g]==mul_sample_slot;
 end endgenerate
 // Capture candidate payload locally. On recovery it is harmless data;
 // read_valid is cleared separately and therefore never authorizes its use.
 generate for(g=0;g<2;g=g+1)begin:read_identity_payload
  always @(posedge clk)if(enable && select_capture_valid[g])begin
   read_slot[g]<=select_slot[g];read_dest[g]<=rob_dest[select_slot[g]];
   read_write[g]<=rob_write[select_slot[g]];read_mul[g]<=rob_kind[select_slot[g]]==3;
   read_inst[g]<=rob_inst[select_slot[g]];read_pc[g]<=rob_pc[select_slot[g]];
   read_predpc[g]<=rob_predpc[select_slot[g]];
   read_src0[g]<=rob_src0[select_slot[g]];read_src1[g]<=rob_src1[select_slot[g]];
  end
 end endgenerate

 generate for(g=0;g<2;g=g+1)begin:e
  JFIX_OOO_INTEGER integer_unit(.inst(execute_inst[g]),.pc(execute_pc[g]),
   .a(execute_a[g]),.b(execute_b[g]),.result(integer_result[g]),
   .next_pc(execute_next[g]),.misaligned(execute_fault[g]));
  // Sample every enabled edge; validity stays with the execution slot.
  // The old product is consumed before this edge replaces partial products.
  wire [31:0] multiplier_inst=execute_hold[g]?execute_inst[g]:rob_inst[mul_sample_slot];
  MUL_PIPE multiplier(.clk(clk),.rst(rst),.start(enable),
   .op(5'd19+{2'b0,multiplier_inst[14:12]}),
   .src0(execute_hold[g]?execute_a[g]:issue_base_a[g]),
   .src1(execute_hold[g]?execute_b[g]:issue_base_b[g]),.result(multiply_result[g]));
  assign execute_result[g]=(execute_inst[g][6:0]==7'h33 && execute_inst[g][31:25]==1 && !execute_inst[g][14])?
   multiply_result[g]:integer_result[g];
 end endgenerate
 // Destinations are unique until retirement releases their ownership.
 // Local one-hot write merging avoids three cascaded whole-array mux layers.
 wire [ROB_BITS-1:0] response_slot=serial_pending?serial_slot:serial_request_slot;
 wire serial_tag_valid=serial_complete && rob_write[response_slot];
 wire serial_write=serial_tag_valid && !serial_fault;
 // LSU completion wakes the slot immediately. Physical RAM publication is
 // registered separately; the pending value forwards until it reaches RAM.
 always @(posedge clk)begin
  if(rst)begin serial_wb_valid<=0;serial_wb_dest<=0;serial_wb_data<=0;end
  else if(enable)begin
   serial_wb_valid<=serial_write;
   if(serial_write)begin serial_wb_dest<=rob_dest[response_slot];serial_wb_data<=serial_result;end
  end
 end
 genvar word_index;
 generate for(word_index=0;word_index<PRF_ENTRIES;word_index=word_index+1)begin:ownership_row
  wire old0=retire0 && rob_write[head] && rob_old[head]==word_index;
  wire new0=retire0 && rob_write[head] && rob_dest[head]==word_index;
  wire old1=retire1 && rob_write[second_head] && rob_old[second_head]==word_index;
  wire new1=retire1 && rob_write[second_head] && rob_dest[second_head]==word_index;
  wire live_next=new1?1'b1:old1?1'b0:new0?1'b1:old0?1'b0:committed_live[word_index];
  wire allocated=allocate && ((wrd[0] && dest0==word_index) || (allocation_count==2 && wrd[1] && dest1==word_index));
  always @(posedge clk) begin
   if(rst) begin committed_live[word_index]<=word_index<32;free_mask[word_index]<=word_index>=32;end
   else if(enable) begin
    committed_live[word_index]<=word_index==0?1'b1:live_next;
    free_mask[word_index]<=word_index==0?1'b0:flush_now?~live_next:allocated?1'b0:(old0 || old1)?1'b1:free_mask[word_index];
   end
  end
 end endgenerate

 // Static per-architectural-register rename rows. Lane 1 wins same-rd pairs;
 // recovery includes retirement on this edge before restoring speculation.
 generate for(word_index=0;word_index<32;word_index=word_index+1)begin:map_row
  wire c0=retire0 && rob_write[head] && rob_rd[head]==word_index;
  wire c1=retire1 && rob_write[second_head] && rob_rd[second_head]==word_index;
  wire [5:0] committed_next=c1?rob_dest[second_head]:c0?rob_dest[head]:committed_map[word_index];
  wire a0=allocate && wrd[0] && rd[0]==word_index;
  wire a1=allocate && allocation_count==2 && wrd[1] && rd[1]==word_index;
  always @(posedge clk) begin
   if(rst) begin speculative_map[word_index]<=word_index;committed_map[word_index]<=word_index;end
   else if(enable) begin
    if(c0 || c1) committed_map[word_index]<=committed_next;
    if(flush_now) speculative_map[word_index]<=committed_next;
    else if(a0 || a1) speculative_map[word_index]<=a1?dest1:dest0;
   end
  end
 end endgenerate
 generate for(word_index=0;word_index<PRF_ENTRIES;word_index=word_index+1)begin:ready_row
  always @(posedge clk) begin
   if(rst || (enable && flush_now)) physical_ready[word_index]<=1;
   else if(enable) begin
    if((completion_valid[0] && completion_dest[5:0]==word_index) ||
       (completion_valid[1] && completion_dest[11:6]==word_index) ||
       (serial_write && rob_dest[response_slot]==word_index)) physical_ready[word_index]<=1;
    if(allocate && ((wrd[0] && dest0==word_index) ||
       (allocation_count==2 && wrd[1] && dest1==word_index))) physical_ready[word_index]<=0;
    if(word_index==0) physical_ready[word_index]<=1;
   end
  end
 end endgenerate
 // Each bank has exactly one write port. Replication for read ports is
 // left to RAM inference; ownership selects the newest bank after the edge.
 always @(posedge clk)begin
  // Squashed destinations are uncommitted and become free on recovery.
  // Data publication is controlled by the architectural maps, so recovery
  // does not need to drive the physical RAM write enables.
  if(!rst && enable)begin
   if(completion_valid[0])prf_bank0[completion_dest[5:0]]<=execute_result[0];
   if(completion_valid[1])prf_bank1[completion_dest[11:6]]<=execute_result[1];
   if(serial_wb_valid)prf_bank2[serial_wb_dest]<=serial_wb_data;
  end
 end
 generate for(word_index=0;word_index<PRF_ENTRIES;word_index=word_index+1)begin:prf_word
  always @(posedge clk)begin
   if(rst)prf_owner[word_index]<=3;
   else if(enable)begin
    if(completion_valid[0] && completion_dest[5:0]==word_index)prf_owner[word_index]<=0;
    if(completion_valid[1] && completion_dest[11:6]==word_index)prf_owner[word_index]<=1;
    if(serial_wb_valid && serial_wb_dest==word_index)prf_owner[word_index]<=2;
   end
  end
 end endgenerate
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:rob_result_word
  wire hit0=execute_complete[0] && execute_slot[0]==word_index;
  wire hit1=execute_complete[1] && execute_slot[1]==word_index;
  wire hit2=serial_complete && response_slot==word_index;
  wire [31:0] merged=({32{hit0}} & execute_result[0]) |
   ({32{hit1}} & execute_result[1]) | ({32{hit2}} & serial_result);
  always @(posedge clk)begin
   if(!rst && enable && !flush_now && (hit0 || hit1 || hit2))rob_value[word_index]<=merged;
  end
 end endgenerate
 // The resolved next PC and exception tval are mutually exclusive uses.
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:control_value_alias
  assign rob_pc[word_index]=rob_fetch_fault[word_index]?rob_control_value[word_index]:{16'h8000,rob_pc_low[word_index]};
  assign rob_nextpc[word_index]=rob_control_value[word_index];
  assign rob_tval[word_index]=rob_control_value[word_index];
 end endgenerate
 wire [1:0] rename_ready_a,rename_ready_b,rename_fault;
 wire [31:0] rename_pc[0:1],rename_seqpc[0:1],rename_nextpc[0:1],rename_tval[0:1];
 wire [31:0] rename_cause[0:1];
 generate for(g=0;g<2;g=g+1)begin:rename_identity
  assign rename_ready_a[g]=!bundle_raw_a[g] &&
   (source_ready(rename_a[g],physical_ready[rename_a[g]],completion_valid,completion_dest) ||
    (serial_tag_valid && rob_dest[response_slot]==rename_a[g]));
  assign rename_ready_b[g]=!bundle_raw_b[g] &&
   (source_ready(rename_b[g],physical_ready[rename_b[g]],completion_valid,completion_dest) ||
    (serial_tag_valid && rob_dest[response_slot]==rename_b[g]));
  assign rename_pc[g]=fetch_pc+4*g;
  assign rename_seqpc[g]=rename_pc[g]+4;
  assign rename_nextpc[g]=fetch_pred_taken[g]?fetch_pred_target[g*32+:32]:rename_seqpc[g];
  assign rename_fault[g]=fetch_fault[g] || illegal[g] || ecall[g] || ebreak[g];
  assign rename_cause[g]=fetch_fault[g]?1:illegal[g]?2:ebreak[g]?3:11;
  assign rename_tval[g]=fetch_fault[g]?rename_pc[g]:illegal[g]?fetch_inst[g*32+:32]:0;
 end endgenerate
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:rob_row
  wire alloc0=allocate && tail==word_index;
  wire alloc1=allocate && allocation_count==2 && second_tail==word_index;
  wire done0=execute_complete[0] && execute_slot[0]==word_index;
  wire done1=execute_complete[1] && execute_slot[1]==word_index;
  wire serial_done=serial_complete && response_slot==word_index;
  wire lane=alloc1;
  always @(posedge clk)begin
   if(rst)begin
    rob_valid[word_index]<=0;rob_done[word_index]<=0;rob_issued[word_index]<=0;
    rob_exception[word_index]<=0;rob_write[word_index]<=0;rob_restart[word_index]<=0;
    rob_source0_ready[word_index]<=0;rob_source1_ready[word_index]<=0;rob_prediction_wrong[word_index]<=0;
   end else if(enable)begin
    if(flush_now)begin
     rob_valid[word_index]<=0;rob_done[word_index]<=0;rob_issued[word_index]<=0;
     rob_exception[word_index]<=0;rob_write[word_index]<=0;rob_restart[word_index]<=0;
    end else begin
     if((retire0 && head==word_index) || (retire1 && second_head==word_index))begin
      rob_valid[word_index]<=0;rob_done[word_index]<=0;
     end
     if(source_ready(rob_src0[word_index],rob_source0_ready[word_index],completion_valid,completion_dest) ||
       (serial_tag_valid && rob_dest[response_slot]==rob_src0[word_index]))rob_source0_ready[word_index]<=1;
     if(source_ready(rob_src1[word_index],rob_source1_ready[word_index],completion_valid,completion_dest) ||
       (serial_tag_valid && rob_dest[response_slot]==rob_src1[word_index]))rob_source1_ready[word_index]<=1;
     if((select_valid[0] && select_slot[0]==word_index) ||
       (select_valid[1] && select_slot[1]==word_index) ||
       (serial_capture && serial_select_slot==word_index))rob_issued[word_index]<=1;
     if(done0 || done1)begin
      rob_done[word_index]<=1;rob_exception[word_index]<=done1?execute_fault[1]:execute_fault[0];
      rob_control_value[word_index]<=done1?execute_next[1]:execute_next[0];
      rob_cause[word_index]<=0;
      rob_prediction_wrong[word_index]<=done1?
       execute_next[1]!=execute_predpc[1]:execute_next[0]!=execute_predpc[0];
     end
     if(serial_done)begin
      rob_done[word_index]<=1;rob_exception[word_index]<=serial_fault;
      rob_cause[word_index]<=serial_cause;
      rob_restart[word_index]<=serial_restart;
      rob_control_value[word_index]<=serial_fault?serial_tval:serial_target;
     end
     if(alloc0 || alloc1)begin
      rob_valid[word_index]<=1;rob_issued[word_index]<=0;rob_done[word_index]<=rename_fault[lane];
      rob_exception[word_index]<=rename_fault[lane];rob_restart[word_index]<=0;rob_prediction_wrong[word_index]<=0;
      rob_pc_low[word_index]<=rename_pc[lane][15:0];rob_fetch_fault[word_index]<=fetch_fault[lane];
      rob_inst[word_index]<=lane?fetch_inst[63:32]:fetch_inst[31:0];
      rob_kind[word_index]<=kind[lane];rob_rd[word_index]<=rd[lane];rob_write[word_index]<=wrd[lane];
      rob_cause[word_index]<=rename_cause[lane];rob_control_value[word_index]<=rename_tval[lane];
      rob_predpc[word_index]<=rename_nextpc[lane];
      rob_src0[word_index]<=rename_a[lane];rob_src1[word_index]<=rename_b[lane];
      rob_dest[word_index]<=lane?dest1:dest0;rob_old[word_index]<=rename_old[lane];
      rob_source0_ready[word_index]<=rename_ready_a[lane];rob_source1_ready[word_index]<=rename_ready_b[lane];
     end
    end
   end
  end
 end endgenerate
 integer i,l,s;
 always @(posedge clk)begin
  if(rst)begin
   fetch_pc<=32'h80000000;head<=0;tail<=0;count<=0;age_upper_mask<={ROB_ENTRIES{1'b1}};
   read_valid<=0;execute_valid<=0;execute_mul_started<=0;execute_mul<=0;serial_pending<=0;irq_pending<=0;
   pending_irq_cause<=0;serial_slot<=0;serial_request_valid<=0;

   for(i=0;i<2;i=i+1)execute_slot[i]<=0;
  end else if(enable)begin
   if(irq_valid && !irq_pending)begin irq_pending<=1;pending_irq_cause<=irq_cause;end
   // A head CSR may mask the interrupt before the retirement boundary.
   if(irq_pending && !irq_valid && !serial_pending)irq_pending<=0;
   if(flush_now)begin
    fetch_pc<=trap_valid?trap_vector:rob_nextpc[head];
    head<=0;tail<=0;count<=0;age_upper_mask<={ROB_ENTRIES{1'b1}};execute_valid<=0;read_valid<=0;
    serial_pending<=0;serial_request_valid<=0;if(take_irq)irq_pending<=0;
   end else begin
    count<=count+(allocate?{3'b0,allocation_count}:5'd0)-retire_count;
    head<=head_after_retire;age_upper_mask<={ROB_ENTRIES{1'b1}}<<head_after_retire;
    for(l=0;l<2;l=l+1)begin
     if(execute_hold[l])begin
      execute_valid[l]<=1;execute_mul_started[l]<=1;
     end else begin
      execute_valid[l]<=select_valid[l];execute_mul_started[l]<=fast_mul[l];
     end
     if(select_valid[l])begin
      execute_slot[l]<=select_slot[l];execute_dest[l]<=rob_dest[select_slot[l]];execute_write[l]<=rob_write[select_slot[l]];
      execute_mul[l]<=rob_kind[select_slot[l]]==3;execute_inst[l]<=rob_inst[select_slot[l]];execute_pc[l]<=rob_pc[select_slot[l]];
      execute_predpc[l]<=rob_predpc[select_slot[l]];
      execute_a[l]<=source_value(rob_src0[select_slot[l]],`JFIX_PRF_READ(rob_src0[select_slot[l]]),bypass_tag_valid,completion_dest,completion_data);
      execute_b[l]<=source_value(rob_src1[select_slot[l]],`JFIX_PRF_READ(rob_src1[select_slot[l]]),bypass_tag_valid,completion_dest,completion_data);
     end
     if(read_fire[l])read_valid[l]<=0;
     if(select_valid[l])read_valid[l]<=1;
    end
    if(serial_accept)serial_request_valid<=0;
    if(serial_capture)begin
     serial_request_valid<=1;serial_request_slot<=serial_select_slot;
     serial_request_inst<=rob_inst[serial_select_slot];serial_request_pc<=rob_pc[serial_select_slot];
     serial_request_a<=source_value(rob_src0[serial_select_slot],`JFIX_PRF_READ(rob_src0[serial_select_slot]),bypass_tag_valid,completion_dest,completion_data);
     serial_request_b<=source_value(rob_src1[serial_select_slot],`JFIX_PRF_READ(rob_src1[serial_select_slot]),bypass_tag_valid,completion_dest,completion_data);
    end
    if(serial_accept)begin serial_pending<=1;serial_slot<=serial_request_slot;end
    if(serial_complete)begin
     s=serial_pending?serial_slot:serial_request_slot;
     serial_pending<=0;
    end
    if(allocate)begin
     tail<=tail+allocation_count;
     fetch_pc<=fetch_pred_taken[0]?fetch_pred_target[31:0]:
      fetch_pred_taken[1]?fetch_pred_target[63:32]:fetch_pc+8;
    end
   end
  end
 end
`undef JFIX_PRF_READ
endmodule

module JFIX_OOO_INTEGER(input [31:0] inst,pc,a,b,
 output [31:0] result,next_pc, output misaligned);
 wire [4:0] r1,r2,rd,op,zop;wire u1,u2,wr,sp,si,ill,ec,eb;wire [31:0] imm;
 wire [1:0] kind;wire [31:0] alu_result,half_result;
 JFIX_OOO_DECODE d(.inst(inst),.rs1(r1),.rs2(r2),.rd(rd),.use1(u1),.use2(u2),
  .write_rd(wr),.op(op),.zop(zop),.imm(imm),.src_pc(sp),.src_imm(si),.kind(kind),
  .illegal(ill),.ecall(ec),.ebreak(eb));
 ALU alu(.alu_src0(sp?pc:a),.alu_src1(si?imm:b),.alu_op(op),.alu_res(alu_result));
 ZBB_ALU halfword(.src0(a),.src1(b),.op(zop),.result(half_result));
 reg taken;
 always @* begin
  taken=0;
  case(inst[14:12])
   0:taken=a==b;1:taken=a!=b;4:taken=$signed(a)<$signed(b);
   5:taken=$signed(a)>=$signed(b);6:taken=a<b;7:taken=a>=b;
   default:taken=0;
  endcase
 end
 wire jump=inst[6:0]==7'h6f || inst[6:0]==7'h67;
 wire branch=inst[6:0]==7'h63;
 wire [31:0] target=inst[6:0]==7'h67 ? ((a+imm)&32'hfffffffe):pc+imm;
 assign next_pc=jump || (branch && taken)?target:pc+4;
 assign misaligned=(jump || (branch && taken)) && |target[1:0];
 assign result=jump?pc+4:zop!=0?half_result:alu_result;
endmodule

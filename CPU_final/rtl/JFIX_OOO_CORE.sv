// JFIX dual integer out-of-order prototype. No external generated core.
// Configurable even-depth ROB; serial side effects only at ROB head.
module JFIX_OOO_CORE #(parameter ROB_ENTRIES=10,
 parameter ROB_BITS=$clog2(ROB_ENTRIES),parameter PRF_ENTRIES=42,
 parameter PRECOMPUTE_MEMORY_ADDRESS=0,parameter RESIDENT_INTEGER_PC=0,parameter FETCH_PREDECODE=0,parameter WAY_RENAME=0,parameter SERIAL_READ_PIPE=0)(
 input clk,rst,enable,
 output reg [31:0] fetch_pc, input fetch_valid,
 input [19:0] fetch_way_rs0,fetch_way_rs1,input [1:0] fetch_way_select,fetch_way_zero,
 input [5:0] fetch_status,
 input [3:0] fetch_directions,output [1:0] branch_directions,
 input [12:0] fetch_history,output [12:0] branch_history,recover_history,
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
 output [1:0] issue_count, output [4:0] rob_occupancy,
 output reg [23:0] debug_event_q,output reg [95:0] debug_payload_q
);
 // Two single-writer rename banks. Owner=2 is architectural reset identity.
 reg [ROB_BITS-1:0] spec_map0[0:31],spec_map1[0:31] /* synthesis syn_ramstyle="lut_ram" */;
 reg [1:0] spec_owner[0:31];
 `define READ_COMMITTED(address) {1'b0,address}
 `define READ_SPECULATIVE(address) (spec_owner[address]==0?(6'd32 | spec_map0[address]):spec_owner[address]==1?(6'd32 | spec_map1[address]):`READ_COMMITTED(address))
 `define READ_ROB_INST(address) ((address & 1)?meta_bank[1].rob_inst_ram[address >> 1]:meta_bank[0].rob_inst_ram[address >> 1])
 `define READ_ROB_PC_LOW(address) ((address & 1)?meta_bank[1].rob_pc_low_ram[address >> 1]:meta_bank[0].rob_pc_low_ram[address >> 1])
 `define READ_ROB_PREDPC_LOW(address) ((address & 1)?meta_bank[1].rob_predpc_low_ram[address >> 1]:meta_bank[0].rob_predpc_low_ram[address >> 1])
 `define READ_ROB_DEST(address) (rob_write[address]?(6'd32 | (address)):6'd0)
 `define READ_ROB_OLD(address) ((address & 1)?meta_bank[1].rob_old_ram[address >> 1]:meta_bank[0].rob_old_ram[address >> 1])
 `define READ_ROB_RD(address) ((address & 1)?meta_bank[1].rob_rd_ram[address >> 1]:meta_bank[0].rob_rd_ram[address >> 1])
 reg [ROB_ENTRIES-1:0] result_lane;
 `define READ_INT_VALUE(address) (result_lane[address]?publication_bank[1].values[address]:publication_bank[0].values[address])
 `define READ_INT_CONTROL(address) (result_lane[address]?publication_bank[1].controls[address]:publication_bank[0].controls[address])
 `define READ_ROB_VALUE(address) (rob_kind[address]==2?serial_values[address]:`READ_INT_VALUE(address))
 `define READ_ROB_CONTROL(address) (rob_rename_fault[address]?(rob_fetch_fault[address]?((32'b0 | `READ_ROB_PC_HIGH(address))<<16 | `READ_ROB_PC_LOW(address)):rob_initial_cause[address]==2?`READ_ROB_INST(address):32'b0):rob_kind[address]==2?serial_control[address]:`READ_INT_CONTROL(address))
 `define READ_ROB_CAUSE(address) (rob_rename_fault[address]?(32'b0 | rob_initial_cause[address]):rob_kind[address]==2?serial_causes[address]:32'b0)
 `define READ_ROB_PC_HIGH(address) ((address & 1)?meta_bank[1].rob_pc_high_ram[address >> 1]:meta_bank[0].rob_pc_high_ram[address >> 1])
 `define READ_ROB_PC(address) ((rob_fetch_fault[address]?(32'b0 | `READ_ROB_PC_HIGH(address))<<16:32'h80000000) | `READ_ROB_PC_LOW(address))
 wire [1:0] bypass_tag_valid;wire [11:0] completion_dest;
 // Architectural retirement file plus resident ROB result values.
 reg [31:0] arch_bank0[0:31],arch_bank1[0:31] /* synthesis syn_ramstyle="lut_ram" */;
 reg [1:0] arch_owner[0:31];
 reg [PRF_ENTRIES-1:0] physical_ready;
 reg [2:0] rob_mul_funct3[0:ROB_ENTRIES-1];
 wire [PRF_ENTRIES-1:0] free_mask={PRF_ENTRIES{1'b1}};
 wire [PRF_ENTRIES-1:0] committed_live=32'hffffffff;
 wire serial_wb_valid=1'b0;wire [5:0] serial_wb_dest=0;wire [31:0] serial_wb_data=0;
 // One-hot architectural ownership: 00=reset zero, 01=bank 0, 10=bank 1.
 // Direct ownership bits select the two existing RAMs without priority decode.
 `define ARCH_READ(address) (({32{arch_owner[address & 31][0]}} & arch_bank0[address & 31]) | ({32{arch_owner[address & 31][1]}} & arch_bank1[address & 31]))
 function automatic [ROB_BITS-1:0] resident_row(input [5:0] tag);
  resident_row=tag[ROB_BITS-1:0];
 endfunction
 `define JFIX_PRF_READ(address) ((address)<32?`ARCH_READ(address):`READ_ROB_VALUE(resident_row(address)))
 `define CANONICAL_TAG(address) canonical_tag(address,{retire1 && commit1_write,retire0 && commit0_write},{commit1_dest,commit0_dest},{commit1_rd,commit0_rd})
 `define CANONICAL_SPEC(address) `CANONICAL_TAG(`READ_SPECULATIVE(address))
 function automatic [5:0] canonical_tag(input [5:0] tag,input [1:0] live,input [11:0] dest,input [9:0] arch);
  canonical_tag=live[1] && tag==dest[11:6]?{1'b0,arch[9:5]}:live[0] && tag==dest[5:0]?{1'b0,arch[4:0]}:tag;
 endfunction
 wire [ROB_ENTRIES-1:0] rob_source0_ready,rob_source1_ready;
 reg [ROB_ENTRIES-1:0] producer_schedule_ready;
 reg [ROB_ENTRIES-1:0] rob_prediction_wrong;
 reg [ROB_ENTRIES-1:0] rob_valid,rob_done,rob_issued,rob_exception,rob_write,rob_restart;
 // Resident code is in 0x80000000..0x8000ffff. Invalid fetches retain
 // their full PC in the exception payload, never truncated for mepc/tval.
 wire [15:0] rob_pc_low[0:ROB_ENTRIES-1];reg [ROB_ENTRIES-1:0] rob_fetch_fault;
 wire [31:0] rob_pc[0:ROB_ENTRIES-1];
 wire [31:0] rob_inst[0:ROB_ENTRIES-1];wire [31:0] rob_value[0:ROB_ENTRIES-1];
 wire [31:0] rob_control_value[0:ROB_ENTRIES-1],rob_cause[0:ROB_ENTRIES-1];
 reg [ROB_ENTRIES-1:0] rob_rename_fault;
 reg [3:0] rob_initial_cause[0:ROB_ENTRIES-1];
 reg [31:0] serial_values[0:ROB_ENTRIES-1],serial_control[0:ROB_ENTRIES-1],serial_causes[0:ROB_ENTRIES-1] /* synthesis syn_ramstyle="lut_ram" */;
 wire [31:0] rob_nextpc[0:ROB_ENTRIES-1],rob_tval[0:ROB_ENTRIES-1];
 // Prediction is a hint: outside-resident predictions always redirect on
 // resolution. The actual next/fault PC remains full width elsewhere.
 wire [15:0] rob_predpc_low[0:ROB_ENTRIES-1];
 reg [ROB_ENTRIES-1:0] rob_pred_resident;
 wire [31:0] rob_predpc[0:ROB_ENTRIES-1];
 genvar pv;
 generate for(pv=0;pv<ROB_ENTRIES;pv=pv+1)begin:prediction_view
  assign rob_predpc[pv]={rob_pred_resident[pv]?16'h8000:16'b0,`READ_ROB_PREDPC_LOW(pv)};
 end endgenerate

 reg [ROB_ENTRIES-1:0] rob_memory_address,rob_opcode_load;reg [1:0] execute_mul;
 reg [5:0] rob_src0[0:ROB_ENTRIES-1],rob_src1[0:ROB_ENTRIES-1];wire [5:0] rob_dest[0:ROB_ENTRIES-1];wire [5:0] rob_old[0:ROB_ENTRIES-1];
 wire [4:0] rob_rd[0:ROB_ENTRIES-1];reg [1:0] rob_kind[0:ROB_ENTRIES-1];
 reg [ROB_BITS-1:0] head /* synthesis syn_maxfan=32 */;reg [ROB_BITS-1:0] tail,serial_slot;reg [4:0] count;reg serial_pending,irq_pending;
 reg [31:0] pending_irq_cause;
 wire [ROB_BITS-1:0] response_slot;
 wire serial_write;
 wire serial_expected;
 reg serial_read_valid,serial_base_valid;
 reg [ROB_BITS-1:0] serial_read_slot,serial_base_slot;
 reg [5:0] serial_read_tag_a,serial_read_tag_b;
 reg [31:0] serial_read_inst,serial_read_pc;
 reg [31:0] serial_base_inst,serial_base_pc,serial_base_a,serial_base_b;
 reg serial_request_valid;reg [ROB_BITS-1:0] serial_request_slot;
 // Preserve the destination identity with each request and accepted command.
 reg [5:0] serial_req_dest,serial_pending_dest;
 reg serial_req_writes,serial_pending_writes;
 wire [5:0] serial_expected_dest=SERIAL_READ_PIPE==0?
  (serial_pending?serial_pending_dest:serial_req_dest):`READ_ROB_DEST(response_slot);
 assign serial_expected=SERIAL_READ_PIPE==0?
  (serial_pending?serial_pending_writes:(serial_request_valid && serial_req_writes)):
  ((serial_pending || serial_request_valid) && rob_write[response_slot]);
 reg [31:0] serial_request_inst,serial_request_pc;
 reg [31:0] serial_request_a,serial_request_b /* synthesis syn_preserve=1 */;
 wire [4:0] rs1[0:1],rs2[0:1],rd[0:1],op[0:1],zop[0:1];
 wire [31:0] imm[0:1];wire [1:0] kind[0:1];
 wire [1:0] use1,use2,wrd,src_pc,src_imm,illegal,ecall,ebreak;
 genvar g;
 generate for(g=0;g<2;g=g+1)begin:d
  wire dec_illegal,dec_ecall,dec_ebreak;
  JFIX_OOO_DECODE decode(.inst(fetch_inst[g*32+:32]),.rs1(rs1[g]),.rs2(rs2[g]),.rd(rd[g]),
   .use1(use1[g]),.use2(use2[g]),.write_rd(wrd[g]),.op(op[g]),.zop(zop[g]),.imm(imm[g]),
   .src_pc(src_pc[g]),.src_imm(src_imm[g]),.kind(kind[g]),
   .illegal(dec_illegal),.ecall(dec_ecall),.ebreak(dec_ebreak));
  assign illegal[g]=FETCH_PREDECODE?fetch_status[g*3]:dec_illegal;
  assign ecall[g]=FETCH_PREDECODE?fetch_status[g*3+1]:dec_ecall;
  assign ebreak[g]=FETCH_PREDECODE?fetch_status[g*3+2]:dec_ebreak;
  // synthesis translate_off
  always @(posedge clk)if(FETCH_PREDECODE && !rst && fetch_valid && fetch_ready && !fetch_fault[g])
   if(fetch_status[g*3+:3]!=={dec_ebreak,dec_ecall,dec_illegal})$fatal(1,"Cache predecode status mismatch");
  // synthesis translate_on
 end endgenerate
 wire [5:0] allocation0=32+tail,allocation1=32+(tail+1'b1)%ROB_ENTRIES;
 wire have0=1'b1,have1=1'b1;
 function automatic [ROB_BITS-1:0] advance_row(input [ROB_BITS-1:0] row,input [1:0] amount);
  reg [ROB_BITS:0] extended;
  begin
   extended={1'b0,row}+amount;
   advance_row=extended>=ROB_ENTRIES?extended-ROB_ENTRIES:extended;
  end
 endfunction
 wire [ROB_BITS-1:0] second_head=advance_row(head,1),second_tail=advance_row(tail,1);
 // Retirement is conservative at control/serial boundaries.
 // Registered pointer decoding avoids repeated late binary-to-row muxes.
 reg [ROB_ENTRIES-1:0] commit_hot /* synthesis syn_preserve=1, syn_maxfan=12 */;
 wire [ROB_ENTRIES-1:0] second_hot={commit_hot[ROB_ENTRIES-2:0],commit_hot[ROB_ENTRIES-1]};
 reg [0:0] commit0_done,commit1_done;
 reg [0:0] commit0_exception,commit1_exception;
 reg [0:0] commit0_write,commit1_write;
 reg [0:0] commit0_restart,commit1_restart;
 reg [0:0] commit0_prediction_wrong,commit1_prediction_wrong;
 reg [1:0] commit0_kind,commit1_kind;
 reg [4:0] commit0_rd,commit1_rd;
 reg [5:0] commit0_dest,commit1_dest;
 reg [5:0] commit0_old,commit1_old;
 reg [31:0] commit0_pc,commit1_pc;
 reg [31:0] commit0_nextpc,commit1_nextpc;
 reg [31:0] commit0_inst,commit1_inst;
 reg [31:0] commit0_cause,commit1_cause;
 reg [31:0] commit0_tval,commit1_tval;
 // head and second_head always address opposite parity banks.
 wire [ROB_BITS-2:0] retire_bank_address[0:1];
 assign retire_bank_address[0]=(head[0]?second_head:head)>>1;
 assign retire_bank_address[1]=(head[0]?head:second_head)>>1;
 wire [31:0] retire_bank_inst[0:1],retire_bank_pc[0:1];
 wire [31:0] retire_bank_value[0:1],retire_bank_control[0:1];
 wire second_early_alu;wire [31:0] second_early_value;
 wire [4:0] retire_bank_rd[0:1];
 generate for(g=0;g<2;g=g+1)begin:retirement_bank_read
  assign retire_bank_inst[g]=meta_bank[g].rob_inst_ram[retire_bank_address[g]];
  assign retire_bank_pc[g]=((32'b0 | meta_bank[g].rob_pc_high_ram[retire_bank_address[g]])<<16)
    | meta_bank[g].rob_pc_low_ram[retire_bank_address[g]];
  assign retire_bank_rd[g]=meta_bank[g].rob_rd_ram[retire_bank_address[g]];
  assign retire_bank_value[g]=`READ_INT_VALUE(head[0]==g ? head : second_head);
  assign retire_bank_control[g]=`READ_INT_CONTROL(head[0]==g ? head : second_head);
 end endgenerate
 wire [31:0] retire_value0=rob_kind[head]==2?serial_values[head]:retire_bank_value[head[0]];
 wire [31:0] retire_value1=rob_kind[second_head]==2?serial_values[second_head]:second_early_alu?second_early_value:retire_bank_value[!head[0]];
 wire [31:0] retire_control0=rob_rename_fault[head]?
    (rob_fetch_fault[head]?commit0_pc:rob_initial_cause[head]==2?commit0_inst:32'b0):
    rob_kind[head]==2?serial_control[head]:retire_bank_control[head[0]];
 wire [31:0] retire_control1=rob_rename_fault[second_head]?
    (rob_fetch_fault[second_head]?commit1_pc:rob_initial_cause[second_head]==2?commit1_inst:32'b0):
    rob_kind[second_head]==2?serial_control[second_head]:retire_bank_control[!head[0]];
 // Normal branch/restart targets do not need rename-fault cause/inst/PC
 // payload selection. The original retire_control view remains the tval view.
 wire [31:0] retire_nextpc0=rob_kind[head]==2?serial_control[head]:retire_bank_control[head[0]];
 wire [31:0] retire_nextpc1=rob_kind[second_head]==2?serial_control[second_head]:retire_bank_control[!head[0]];
 integer cr;
 always @* begin
  commit0_done=0;commit1_done=0;
  commit0_exception=0;commit1_exception=0;
  commit0_write=0;commit1_write=0;
  commit0_restart=0;commit1_restart=0;
  commit0_prediction_wrong=0;commit1_prediction_wrong=0;
  commit0_kind=0;commit1_kind=0;
  commit0_rd=retire_bank_rd[head[0]];commit1_rd=retire_bank_rd[!head[0]];
  commit0_dest=`READ_ROB_DEST(head);commit1_dest=`READ_ROB_DEST(second_head);
  commit0_old=`READ_ROB_OLD(head);commit1_old=`READ_ROB_OLD(second_head);
  commit0_pc=((rob_fetch_fault[head]?retire_bank_pc[head[0]] & 32'hffff0000:32'h80000000) | (retire_bank_pc[head[0]] & 32'h0000ffff));commit1_pc=((rob_fetch_fault[second_head]?retire_bank_pc[!head[0]] & 32'hffff0000:32'h80000000) | (retire_bank_pc[!head[0]] & 32'h0000ffff));
  commit0_nextpc=0;commit1_nextpc=0;
  commit0_inst=retire_bank_inst[head[0]];commit1_inst=retire_bank_inst[!head[0]];
  commit0_cause=0;commit1_cause=0;
  commit0_tval=0;commit1_tval=0;
  commit0_nextpc=retire_nextpc0;commit1_nextpc=retire_nextpc1;
  commit0_cause=`READ_ROB_CAUSE(head);commit1_cause=`READ_ROB_CAUSE(second_head);
  commit0_tval=retire_control0;commit1_tval=retire_control1;
  for(cr=0;cr<ROB_ENTRIES;cr=cr+1)begin
   commit0_done=commit0_done | ({1{commit_hot[cr]}} & rob_done[cr]);
   commit1_done=commit1_done | ({1{second_hot[cr]}} & rob_done[cr]);
   commit0_exception=commit0_exception | ({1{commit_hot[cr]}} & rob_exception[cr]);
   commit1_exception=commit1_exception | ({1{second_hot[cr]}} & rob_exception[cr]);
   commit0_write=commit0_write | ({1{commit_hot[cr]}} & rob_write[cr]);
   commit1_write=commit1_write | ({1{second_hot[cr]}} & rob_write[cr]);
   commit0_restart=commit0_restart | ({1{commit_hot[cr]}} & rob_restart[cr]);
   commit1_restart=commit1_restart | ({1{second_hot[cr]}} & rob_restart[cr]);
   commit0_prediction_wrong=commit0_prediction_wrong | ({1{commit_hot[cr]}} & rob_prediction_wrong[cr]);
   commit1_prediction_wrong=commit1_prediction_wrong | ({1{second_hot[cr]}} & rob_prediction_wrong[cr]);
   commit0_kind=commit0_kind | ({2{commit_hot[cr]}} & rob_kind[cr]);
   commit1_kind=commit1_kind | ({2{second_hot[cr]}} & rob_kind[cr]);
  end
 end
 // One retired branch training event may wait behind this cycle's event.
 reg [12:0] rob_history[0:ROB_ENTRIES-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg [12:0] branch_q_history;reg [1:0] rob_directions[0:ROB_ENTRIES-1];reg [1:0] branch_q_directions;
 reg branch_q_valid;reg [31:0] branch_q_pc,branch_q_inst,branch_q_target;
 wire head_ready=count!=0 && commit0_done;
 wire head_load=commit0_kind==2 && (|(commit_hot & rob_opcode_load)) && !commit0_restart;
 wire second_load=commit1_kind==2 && (|(second_hot & rob_opcode_load)) && !commit1_restart;
 // synthesis translate_off
 always @(posedge clk)if(!rst)begin
  if(count!=0 && head_load!==(commit0_kind==2 && commit0_inst[6:0]==7'h03 && !commit0_restart))
   $fatal(1,"Retiring head opcode fact differs from ROB instruction");
  if(count>1 && second_load!==(commit1_kind==2 && commit1_inst[6:0]==7'h03 && !commit1_restart))
   $fatal(1,"Retiring second opcode fact differs from ROB instruction");
 end
 // synthesis translate_on
 // A completed head transaction may already have an irreversible side effect.
 // Retire it before taking the pending interrupt; never replay it via mepc.
 // Form per-row decisions before selecting the head. This avoids
 // selecting done/kind/exception separately and combining them afterwards.
 wire [ROB_ENTRIES-1:0] irq_hold_rows,fault_rows,redirect_rows,pending_redirect_rows;
 wire [ROB_ENTRIES-1:0] pair_head_rows,second_redirect_rows;
 genvar rcview;
 generate for(rcview=0;rcview<ROB_ENTRIES;rcview=rcview+1)begin:retire_local_view
  wire completed=rob_done[rcview];
  wire clean=completed && !rob_exception[rcview];
  wire branch=rob_kind[rcview]==1;
  wire simple=rob_kind[rcview]==0 || rob_kind[rcview]==3;
  assign irq_hold_rows[rcview]=commit_hot[rcview] && clean && rob_kind[rcview]==2;
  assign fault_rows[rcview]=commit_hot[rcview] && completed && rob_exception[rcview];
  assign redirect_rows[rcview]=commit_hot[rcview] && clean &&
   (rob_restart[rcview] || (branch && rob_prediction_wrong[rcview]));
  assign pending_redirect_rows[rcview]=commit_hot[rcview] && clean && simple && rob_restart[rcview];
  assign pair_head_rows[rcview]=commit_hot[rcview] && clean && (!branch || !branch_q_valid);
  assign second_redirect_rows[rcview]=second_hot[rcview] && clean && branch &&
   !rob_restart[rcview] && rob_prediction_wrong[rcview];
 end endgenerate
 wire take_irq=irq_pending && irq_valid && !serial_pending &&
  !(count!=0 && (|irq_hold_rows)) && enable;
 wire sync_fault=head_ready && commit0_exception && !take_irq && !serial_pending;
 wire retire0=head_ready && !commit0_exception && !take_irq && enable &&
  (!serial_pending || commit0_kind==0 || commit0_kind==3 || head_load ||
   (commit0_kind==1 && !commit0_restart && !commit0_prediction_wrong));
 wire head_redirect=retire0 &&
  (commit0_restart || (commit0_kind==1 && commit0_prediction_wrong));
 wire second_branch_safe=commit1_kind==1 && !commit1_restart &&
  !commit1_prediction_wrong;
 wire retire1=retire0 && !head_redirect && count>1 &&
  (commit1_done || second_early_alu) && !commit1_exception &&
  (commit1_kind==0 || commit1_kind==3 || second_load ||
   ((commit0_kind!=1 || !branch_q_valid) && commit1_kind==1 && !commit1_restart &&
     (!commit1_prediction_wrong || !serial_pending))) &&
  (!serial_pending || commit1_kind==0 || commit1_kind==3 || second_load || second_branch_safe);
 wire control_redirect=head_redirect || (retire1 && commit1_kind==1 && commit1_prediction_wrong);
 // Pair rollback is qualified from the same ROB state version as
 // head rollback. Actual retire0/retire1 and trap payload are unchanged.
 // synthesis translate_off
 always @(posedge clk)if(!rst)begin
  if(commit_hot!==( {{(ROB_ENTRIES-1){1'b0}},1'b1} << head))
   $fatal(1,"Retirement view head identity mismatch");
 end
 // synthesis translate_on
 wire no_pending_flush=(|fault_rows) || (|redirect_rows) ||
  (count>1 && (|pair_head_rows) && (|second_redirect_rows));
 wire local_flush=count!=0 && (serial_pending?(|pending_redirect_rows):no_pending_flush);
 wire flush_now=take_irq || (enable && local_flush);
 // synthesis translate_off
 always @(posedge clk) if(!rst && enable && !flush_now)begin
  if(serial_expected!==((serial_pending || serial_request_valid) && rob_write[response_slot]))
   $fatal(1,"serial destination validity mismatch");
  if(serial_expected && serial_expected_dest!==`READ_ROB_DEST(response_slot))
   $fatal(1,"serial destination identity mismatch");
 end
 // synthesis translate_on
 // synthesis translate_off
 wire reference_flush=take_irq || (sync_fault && enable) || control_redirect;
 always @(posedge clk)if(!rst && flush_now!==reference_flush)
  $fatal(1,"Local retirement view differs from original chain");
 // synthesis translate_on
 assign redirect=flush_now;
 // Payload selection does not wait for retirement qualification. When a
 // control redirect fires this predicate identifies the same retiring branch;
 // exception/interrupt targets retain priority. Invalid cycles do not consume it.
 wire head_target_select=commit0_restart || (commit0_kind==1 && commit0_prediction_wrong);
 assign redirect_pc=trap_valid?trap_vector:head_target_select?commit0_nextpc:commit1_nextpc;
 // synthesis translate_off
 always @(posedge clk)if(!rst && enable && control_redirect && !trap_valid)
  if(redirect_pc !== (head_redirect?commit0_nextpc:commit1_nextpc))$fatal(1,"Early redirect payload mismatch");
 // synthesis translate_on
 wire branch_payload_first=commit0_kind==1;
 wire [ROB_BITS-1:0] branch_commit_slot=branch_payload_first?head:second_head;
 wire branch_from_first=retire0 && commit0_kind==1;
 wire branch_from_second=retire1 && commit1_kind==1;
 wire branch_retired=branch_from_first || branch_from_second;
 wire [31:0] current_branch_pc=branch_payload_first?commit0_pc:commit1_pc;
 wire [31:0] current_branch_inst=branch_payload_first?commit0_inst:commit1_inst;
 wire [31:0] current_branch_target=branch_payload_first?commit0_nextpc:commit1_nextpc;
 // synthesis translate_off
 always @(posedge clk)if(!rst && enable)begin
  if(branch_from_first && commit0_nextpc!==retire_control0)
   $fatal(1,"Retired first branch target differs from original payload");
  if(branch_from_second && commit1_nextpc!==retire_control1)
   $fatal(1,"Retired second branch target differs from original payload");
  if(control_redirect && !trap_valid &&
     redirect_pc!==(head_redirect?retire_control0:retire_control1))
   $fatal(1,"Normal redirect target differs from original payload");
 end
 // synthesis translate_on
 // synthesis translate_off
 always @(posedge clk)if(!rst && enable && branch_retired)begin
  if(branch_payload_first!==branch_from_first ||
     branch_commit_slot!==((retire0 && commit0_kind==1)?head:second_head))
   $fatal(1,"Training payload identity disagrees with real retired branch");
 end
 // synthesis translate_on
 assign branch_commit=enable && !rst && (branch_q_valid || branch_retired);
 reg [12:0] committed_history;
 wire history_retire0=retire0 && commit0_kind==1 && commit0_inst[6:0]==7'h63;
 wire history_retire1=retire1 && commit1_kind==1 && commit1_inst[6:0]==7'h63;
 wire actual0=commit0_nextpc!=commit0_pc+4;
 wire actual1=commit1_nextpc!=commit1_pc+4;
 wire [12:0] after_history0=history_retire0?{committed_history[11:0],actual0}:committed_history;
 assign recover_history=history_retire1?{after_history0[11:0],actual1}:after_history0;
 always @(posedge clk)begin
  if(rst)committed_history<=0;
  else if(enable)committed_history<=recover_history;
 end
 assign branch_directions=branch_q_valid?branch_q_directions:rob_directions[branch_commit_slot];
 assign branch_history=branch_q_valid?branch_q_history:rob_history[branch_commit_slot];
 assign branch_pc=branch_q_valid?branch_q_pc:current_branch_pc;
 assign branch_inst=branch_q_valid?branch_q_inst:current_branch_inst;
 assign branch_target=branch_q_valid?branch_q_target:current_branch_target;
 always @(posedge clk)begin
  if(rst)branch_q_valid<=0;
  else if(enable)begin
   // Flush never cancels already retired predictor/RAS events.
   if(branch_q_valid)begin
    branch_q_valid<=branch_retired;
    branch_q_history<=rob_history[branch_commit_slot];branch_q_directions<=rob_directions[branch_commit_slot];
    branch_q_pc<=current_branch_pc;branch_q_inst<=current_branch_inst;branch_q_target<=current_branch_target;
   end else begin
    branch_q_valid<=branch_from_first && branch_from_second;
    branch_q_history<=rob_history[second_head];branch_q_directions<=rob_directions[second_head];
    branch_q_pc<=commit1_pc;branch_q_inst<=commit1_inst;branch_q_target<=commit1_nextpc;
   end
  end
 end
 // synthesis translate_off
 reg branch_q_wrong;reg [31:0] branch_q_prediction;
 wire training_wrong=branch_q_valid?branch_q_wrong:rob_prediction_wrong[branch_commit_slot];
 wire [31:0] training_prediction=branch_q_valid?branch_q_prediction:rob_predpc[branch_commit_slot];
 always @(posedge clk)if(!rst && enable)begin
  branch_q_wrong<=branch_q_valid?rob_prediction_wrong[branch_commit_slot]:rob_prediction_wrong[second_head];
  branch_q_prediction<=branch_q_valid?rob_predpc[branch_commit_slot]:rob_predpc[second_head];
  if(branch_q_valid && branch_from_first && branch_from_second)$fatal(1,"Branch training overflow");
 end
 // synthesis translate_on
 assign trap_valid=enable && (take_irq || sync_fault);
 assign trap_pc=count!=0?commit0_pc:fetch_pc;
 assign trap_cause=take_irq?pending_irq_cause:commit0_cause;
 assign trap_tval=take_irq?0:commit0_tval;
 assign retire_count={1'b0,retire0}+{1'b0,retire1};
 assign retire_pc={commit1_pc,commit0_pc};
 assign retire_inst={commit1_inst,commit0_inst};
 assign retire_data={retire_value1,retire_value0};
 assign retire_rd={commit1_rd,commit0_rd};
 assign retire_write={retire1 && commit1_write,retire0 && commit0_write};
 assign rob_occupancy=count;
 assign fetch_ready=enable && !flush_now && !irq_pending && (count-retire_count)<=(ROB_ENTRIES-2) &&
  ((!wrd[0] && !wrd[1]) || (have0 && (!(wrd[0] && wrd[1]) || have1)));
 wire allocate=fetch_valid && fetch_ready;
 wire [1:0] allocation_count=fetch_pred_taken[0]?2'd1:2'd2;
 wire [5:0] dest0=wrd[0]?(32+tail):0;
 wire [5:0] dest1=wrd[1]?(32+second_tail):0;
 wire [5:0] rename_a[0:1],rename_b[0:1],rename_old[0:1];
 wire [1:0] bundle_raw_a,bundle_raw_b;
 assign bundle_raw_a={wrd[0] && use1[1] && rs1[1]==rd[0],1'b0};
 assign bundle_raw_b={wrd[0] && use2[1] && rs2[1]==rd[0],1'b0};
 wire [5:0] source_map_a[0:1],source_map_b[0:1];
 genvar wr;
 generate for(wr=0;wr<2;wr=wr+1)begin:way_rename
  if(WAY_RENAME)begin:enabled
   wire [4:0] a0=fetch_way_rs0[wr*10+:5],b0=fetch_way_rs0[wr*10+5+:5];
   wire [4:0] a1=fetch_way_rs1[wr*10+:5],b1=fetch_way_rs1[wr*10+5+:5];
   wire [5:0] ma0=`CANONICAL_SPEC(a0),mb0=`CANONICAL_SPEC(b0);
   wire [5:0] ma1=`CANONICAL_SPEC(a1),mb1=`CANONICAL_SPEC(b1);
   assign source_map_a[wr]=fetch_way_zero[wr]?6'b0:fetch_way_select[wr]?ma1:ma0;
   assign source_map_b[wr]=fetch_way_zero[wr]?6'b0:fetch_way_select[wr]?mb1:mb0;
   // synthesis translate_off
   always @(posedge clk)if(!rst && allocate &&
    (source_map_a[wr]!==`CANONICAL_SPEC(rs1[wr]) || source_map_b[wr]!==`CANONICAL_SPEC(rs2[wr])))
    $fatal(1,"Way rename map differs from canonical instruction map");
   // synthesis translate_on
  end else begin:legacy
   assign source_map_a[wr]=`CANONICAL_SPEC(rs1[wr]);
   assign source_map_b[wr]=`CANONICAL_SPEC(rs2[wr]);
  end
 end endgenerate
 assign rename_a[0]=use1[0]?source_map_a[0]:0;
 assign rename_b[0]=use2[0]?source_map_b[0]:0;
 assign rename_a[1]=bundle_raw_a[1]?dest0:use1[1]?source_map_a[1]:0;
 assign rename_b[1]=bundle_raw_b[1]?dest0:use2[1]?source_map_b[1]:0;
 assign rename_old[0]=`CANONICAL_SPEC(rd[0]);
 assign rename_old[1]=wrd[0] && rd[1]==rd[0]?dest0:`CANONICAL_SPEC(rd[1]);
 // Only a normal, aligned BRAM load may execute before reaching the head.
 // The first incomplete serial operation is an ordering barrier; no store,
 // MMIO, CSR, custom command or load passes it. One transaction is in flight.
 reg serial_select_valid;reg [ROB_BITS-1:0] serial_select_slot;
 reg [ROB_ENTRIES-1:0] age_upper_mask;
 wire [ROB_BITS-1:0] head_after_retire=advance_row(head,retire_count);
 reg [ROB_ENTRIES-1:0] serial_candidates,serial_upper,serial_absolute;
 integer q;reg serial_found;
 wire [1:0] address_bypass_valid=bypass_tag_valid & ~execute_mul;
 wire selected_memory_address=SERIAL_READ_PIPE==0 && PRECOMPUTE_MEMORY_ADDRESS &&
  (|(serial_absolute & rob_memory_address));
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
   (source_ready(rob_src0[serial_select_slot],rob_source0_ready[serial_select_slot],selected_memory_address?address_bypass_valid:bypass_tag_valid,completion_dest) ||
    (serial_write && rob_src0[serial_select_slot]==`READ_ROB_DEST(response_slot))) &&
   (source_ready(rob_src1[serial_select_slot],rob_source1_ready[serial_select_slot],bypass_tag_valid,completion_dest) ||
    (serial_write && rob_src1[serial_select_slot]==`READ_ROB_DEST(response_slot)));
 end
 // Select source tags directly from the scheduler's one-hot choice. The
 // encoded slot remains the command identity and metadata RAM address.
 reg [5:0] serial_source_a,serial_source_b /* synthesis syn_maxfan=24 */;
 integer st;
 always @*begin
  serial_source_a=0;serial_source_b=0;
  for(st=0;st<ROB_ENTRIES;st=st+1)begin
   serial_source_a=serial_source_a | ({6{serial_absolute[st]}} & rob_src0[st]);
   serial_source_b=serial_source_b | ({6{serial_absolute[st]}} & rob_src1[st]);
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst && enable && serial_found)begin
  if((serial_absolute & (serial_absolute-1'b1))!=0)
   $fatal(1,"Serial selector is not one-hot");
  if(serial_source_a!==rob_src0[serial_select_slot] ||
     serial_source_b!==rob_src1[serial_select_slot])
   $fatal(1,"Serial source tags disagree with encoded command slot");
 end
 // synthesis translate_on
 // A one-entry lookahead buffer may capture young commands, but only normal
 // BRAM loads may publish before reaching the retirement head.
 // Match the serial execution interface: in precompute mode the held
 // request already contains EA. Do not add the load immediate a second time.
 wire [31:0] request_address=PRECOMPUTE_MEMORY_ADDRESS?serial_request_a:
  serial_request_a+{{20{serial_request_inst[31]}},serial_request_inst[31:20]};
 wire request_normal_load=serial_request_inst[6:0]==7'h03 && request_address[31:18]==14'h2004 &&
  !(serial_request_inst[13:12]==1 && request_address[0]) &&
  !(serial_request_inst[13:12]==2 && |request_address[1:0]);
 wire serial_accept;
 wire request_space=!serial_request_valid || serial_accept;
 wire serial_base_fire=SERIAL_READ_PIPE!=0 && SERIAL_READ_PIPE!=3 && serial_base_valid && request_space && enable && !flush_now && !irq_pending;
 wire serial_base_space=!serial_base_valid || serial_base_fire;
 wire [5:0] serial_read_current_a=`CANONICAL_TAG(serial_read_tag_a);
 wire [5:0] serial_read_current_b=`CANONICAL_TAG(serial_read_tag_b);
 // Address base is sampled from published state only. No EX/MMIO value
 // forwarding enters the address adder; readiness and value share an edge.
 wire [1:0] serial_add_match;
 wire serial_read_ready_a=physical_ready[serial_read_tag_a] || |serial_add_match;
 wire serial_read_ready_b=source_ready(serial_read_tag_b,physical_ready[serial_read_tag_b],bypass_tag_valid,completion_dest) ||
  (serial_write && serial_read_tag_b==`READ_ROB_DEST(response_slot));
 wire serial_read_fire=(SERIAL_READ_PIPE==2?serial_select_valid:
  (SERIAL_READ_PIPE==1 || SERIAL_READ_PIPE==3) && serial_read_valid && serial_read_ready_a && serial_read_ready_b) &&
  (SERIAL_READ_PIPE==3?request_space:serial_base_space) && enable && !flush_now && !irq_pending;
 wire serial_reserve=(SERIAL_READ_PIPE==1 || SERIAL_READ_PIPE==3) && serial_found && !rob_exception[serial_select_slot] &&
  (!serial_read_valid || serial_read_fire) && enable && !flush_now && !irq_pending;
 wire serial_capture=SERIAL_READ_PIPE==3?serial_read_fire:SERIAL_READ_PIPE?serial_base_fire:
  (enable && serial_select_valid && request_space && !flush_now && !irq_pending);
 assign serial_valid=enable && serial_request_valid && !serial_pending && !flush_now && !irq_pending &&
  (serial_request_slot==head || (retire_count!=0 && serial_request_slot==head_after_retire) || request_normal_load);
 assign serial_inst=serial_request_inst;assign serial_pc=serial_request_pc;
 assign serial_src0=serial_request_a;assign serial_src1=serial_request_b;
 assign serial_rsp_ready=(serial_pending || (serial_valid && serial_ready)) && !flush_now && enable;
 assign serial_accept=serial_valid && serial_ready;
 wire serial_complete=serial_rsp_valid && serial_rsp_ready;

 reg [1:0] execute_valid,execute_write,execute_mul_started;reg [ROB_BITS-1:0] execute_slot[0:1];
 reg [5:0] execute_dest[0:1] /* synthesis syn_maxfan=12 */;
 reg [31:0] execute_inst[0:1],execute_pc[0:1],execute_a[0:1],execute_b[0:1];
 reg [31:0] execute_imm[0:1];reg [4:0] execute_op[0:1];
 reg [9:0] execute_control[0:1];reg [1:0] execute_src_pc,execute_src_imm;
 reg [15:0] execute_predpc_low[0:1];reg [1:0] execute_pred_resident;
 wire [31:0] execute_result[0:1],integer_result[0:1],execute_next[0:1],multiply_result[0:1];wire [1:0] execute_fault;
 // Completion bypass is local to issue. Faulting results never wake users.
 wire [1:0] execute_complete=execute_valid & (~execute_mul | execute_mul_started);

 // Only ordinary integer operations can use the same-cycle second-commit
 // bypass. Their captured control must describe neither a jump nor branch;
 // the branch alignment datapath is not an input to their qualification.
 wire second_alu_complete0=execute_complete[0] && execute_slot[0]==second_head && !(|execute_control[0][9:8]);
 wire second_alu_complete1=execute_complete[1] && execute_slot[1]==second_head && !(|execute_control[1][9:8]);
 // synthesis translate_off
 wire second_ref0=execute_complete[0] && execute_slot[0]==second_head && !execute_fault[0];
 wire second_ref1=execute_complete[1] && execute_slot[1]==second_head && !execute_fault[1];
 always @(posedge clk)if(!rst && enable && count>1 && !commit1_done && commit1_kind==0 && !commit1_exception &&
  !$isunknown({execute_complete,execute_slot[0],execute_slot[1],second_head,execute_fault,execute_control[0][9:8],execute_control[1][9:8]})) begin
  if((second_alu_complete0 || second_alu_complete1)!==(second_ref0 || second_ref1))
   $fatal(1,"Early integer completion differs from original fault-qualified result");
  if((second_ref0 || second_ref1) &&
     (second_alu_complete1?integer_result[1]:integer_result[0])!==(second_ref1?integer_result[1]:integer_result[0]))
   $fatal(1,"Early integer retirement value identity changed");
 end
 // synthesis translate_on
 assign second_early_alu=count>1 && !commit1_done && commit1_kind==0 && !commit1_exception &&
  (second_alu_complete0 || second_alu_complete1);
 assign second_early_value=second_alu_complete1?integer_result[1]:integer_result[0];
 // synthesis translate_off
 always @(posedge clk) if(!rst && enable && second_early_alu)begin
  if(second_alu_complete0 && execute_result[0]!==integer_result[0])
   $fatal(1,"ordinary early retirement lane0 selected a non-ALU value");
  if(second_alu_complete1 && execute_result[1]!==integer_result[1])
   $fatal(1,"ordinary early retirement lane1 selected a non-ALU value");
 end
 // synthesis translate_on
 // synthesis translate_off
 always @(posedge clk) if(!rst && enable && second_early_alu && second_alu_complete0 && second_alu_complete1)
  $fatal(1,"two execution lanes completed one ROB row");
 // synthesis translate_on

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
 genvar add_lane;
 generate for(add_lane=0;add_lane<2;add_lane=add_lane+1)begin:serial_address_add
  assign serial_add_match[add_lane]=bypass_tag_valid[add_lane] &&
   execute_dest[add_lane]==serial_read_tag_a && execute_op[add_lane]==0 &&
   !execute_control[add_lane][9] && execute_control[add_lane][4:0]==0 && !execute_mul[add_lane];
 end endgenerate

 function automatic source_ready(input [5:0] address,input base_ready,
   input [1:0] completed,input [11:0] destinations);
  integer b;
  begin source_ready=base_ready;
   for(b=0;b<2;b=b+1)
    if(completed[b] && destinations[b*6+:6]==address)source_ready=1;
  end
 endfunction
 // synthesis translate_off
 always @(posedge clk)if(!rst && enable)begin:resident_tag_contract
  integer c;
  for(c=0;c<ROB_ENTRIES;c=c+1)if(rob_valid[c])begin
   if(rob_src0[c]>=32+ROB_ENTRIES || rob_src1[c]>=32+ROB_ENTRIES)
    $fatal(1,"Live operand tag outside architectural/resident domain");
  end
 end
 // synthesis translate_on
 function automatic [31:0] source_value(input [5:0] address,input [31:0] base_value,
   input [1:0] completed,input [11:0] destinations,input [63:0] values);
  reg match0,match1;
  begin
   match0=completed[0] && destinations[5:0]==address;
   match1=completed[1] && destinations[11:6]==address;
   source_value=({32{match1}} & values[63:32]) |
    ({32{match0 && !match1}} & values[31:0]) |
    ({32{!match0 && !match1}} & base_value);
  end
 endfunction
 // Flatten the serial override into the existing result-forwarding mux.
 // Preserve exact priority: serial, lane 1, lane 0, resident register value.
 function automatic [31:0] operand_value(input [5:0] address,input [31:0] base_value,
   input [1:0] completed,input [11:0] destinations,input [63:0] values,
   input serial_valid,input [5:0] serial_dest,input [31:0] serial_data);
  reg ms,m0,m1;
  begin
   ms=serial_valid && serial_dest==address;
   m0=completed[0] && destinations[5:0]==address;
   m1=completed[1] && destinations[11:6]==address;
   operand_value=({32{ms}} & serial_data) |
    ({32{!ms && m1}} & values[63:32]) |
    ({32{!ms && !m1 && m0}} & values[31:0]) |
    ({32{!ms && !m1 && !m0}} & base_value);
  end
 endfunction
 // Select a candidate only when none of the other entries in its parity
 // precede it. The comparisons run in parallel; no carry priority chain.
 function automatic [ROB_ENTRIES-1:0] parity_oldest(
  input [ROB_ENTRIES-1:0] candidates,input [ROB_ENTRIES-1:0] age,input parity);
  reg blocked;integer n,j,slot_n,slot_j;
  begin
   parity_oldest=0;
   for(n=0;n<ROB_ENTRIES/2;n=n+1)begin
    slot_n=2*n+parity;blocked=0;
    for(j=0;j<ROB_ENTRIES/2;j=j+1)begin
     slot_j=2*j+parity;
     if(j!=n)blocked=blocked || (candidates[slot_j] &&
      ((age[slot_j] && !age[slot_n]) ||
       ((age[slot_j]==age[slot_n]) && j<n)));
    end
    parity_oldest[slot_n]=candidates[slot_n] && !blocked;
   end
  end
 endfunction
 // Age-order selection over the ROB resident scheduling window.
 reg [1:0] select_valid,select_capture_valid;reg [ROB_BITS-1:0] select_slot[0:1];
 integer k,slot,gi,gj;
 reg [ROB_ENTRIES-1:0] issue_candidates,issue_upper,issue_remaining,issue_remaining_upper;
 reg [ROB_ENTRIES-1:0] issue_absolute0,issue_absolute1;
 reg [ROB_ENTRIES-1:0] integer_ready_a,integer_ready_b,integer_known_ready;
 always @* begin
  select_valid=0;select_capture_valid=0;select_slot[0]=0;select_slot[1]=0;issue_candidates=0;
  for(k=0;k<ROB_ENTRIES;k=k+1)begin
   integer_ready_a[k]=source_ready(rob_src0[k],rob_source0_ready[k],bypass_tag_valid,completion_dest);
   integer_ready_b[k]=source_ready(rob_src1[k],rob_source1_ready[k],bypass_tag_valid,completion_dest);
   integer_known_ready[k]=integer_ready_a[k] && integer_ready_b[k];
   issue_candidates[k]=rob_valid[k] && !rob_issued[k] && !rob_done[k] && rob_kind[k]!=2 &&
    (integer_ready_a[k] || (serial_expected && rob_src0[k]==serial_expected_dest)) &&
    (integer_ready_b[k] || (serial_expected && rob_src1[k]==serial_expected_dest));
  end
  // Local oldest-ready selection, one parity per integer port.
  issue_upper=0;issue_remaining=0;
  for(k=0;k<ROB_ENTRIES;k=k+1)begin
   if(k%2==0)issue_upper[k]=issue_candidates[k];
   else issue_remaining[k]=issue_candidates[k];
  end
  issue_remaining_upper=0;
  issue_absolute0=parity_oldest(issue_candidates,age_upper_mask,1'b0);
  issue_absolute1=parity_oldest(issue_candidates,age_upper_mask,1'b1);
  // In each parity bank identify the second-oldest candidate directly.
  // A borrowed issue is allowed only when the opposite bank is empty.
  if (read_available==2'b11) begin
   issue_upper=0;issue_remaining=0;
   for (gi=0;gi<ROB_ENTRIES;gi=gi+1) begin : parallel_local_age
    reg [ROB_ENTRIES-1:0] older_ready;
    older_ready=0;
    for (gj=0;gj<ROB_ENTRIES;gj=gj+1) begin
     if (gj!=gi && (gj%2)==(gi%2))
      older_ready[gj]=issue_candidates[gj] &&
       ((age_upper_mask[gj] && !age_upper_mask[gi]) ||
        ((age_upper_mask[gj]==age_upper_mask[gi]) && (gj<gi)));
    end
    if ((gi%2)==0)
     issue_upper[gi]=issue_candidates[gi] && (|older_ready) && !(|(older_ready & (older_ready-1'b1)));
    else
     issue_remaining[gi]=issue_candidates[gi] && (|older_ready) && !(|(older_ready & (older_ready-1'b1)));
   end
   if ((|issue_absolute0) && !(|issue_absolute1)) issue_absolute1=issue_upper;
   else if ((|issue_absolute1) && !(|issue_absolute0)) issue_absolute0=issue_remaining;
  end
  for(k=0;k<ROB_ENTRIES;k=k+1)begin
   if(issue_absolute0[k])select_slot[0]=select_slot[0] | k;
   if(issue_absolute1[k])select_slot[1]=select_slot[1] | k;
  end
  select_valid={|issue_absolute1,|issue_absolute0};
  if(!read_available[0])select_valid[0]=0;
  if(!read_available[1])select_valid[1]=0;
  // Response identity is registered, so it may select a dependent lane
  // before the cache's late response-valid/error decision. Only actual
  // successful completion authorizes the dependent execution edge.
  select_valid[0]=select_valid[0] && (serial_write || (|(issue_absolute0 & integer_known_ready)));
  select_valid[1]=select_valid[1] && (serial_write || (|(issue_absolute1 & integer_known_ready)));
  select_capture_valid=select_valid;
  if(!enable || flush_now)select_valid=0;
 end
 assign issue_count={1'b0,select_valid[0]}+{1'b0,select_valid[1]};
 // Keep selection one-hot through tag gathering. Validity remains separate.
 wire [ROB_ENTRIES-1:0] operand_mask0=issue_absolute0;
 wire [ROB_ENTRIES-1:0] operand_mask1=issue_absolute1;
 reg [5:0] operand_tag0[0:1],operand_tag1[0:1];integer ot;
 reg operand_owner0[0:1],operand_owner1[0:1];
 `define ISSUE_PRF_READ(addr,owner) ((addr)<32?`ARCH_READ(addr): \
  (rob_kind[resident_row(addr)]==2?serial_values[resident_row(addr)]: \
   ((owner)?publication_bank[1].values[resident_row(addr)]:publication_bank[0].values[resident_row(addr)])))
 always @* begin
  operand_tag0[0]=0;operand_tag1[0]=0;operand_tag0[1]=0;operand_tag1[1]=0;
  operand_owner0[0]=0;operand_owner1[0]=0;operand_owner0[1]=0;operand_owner1[1]=0;
  for(ot=0;ot<ROB_ENTRIES;ot=ot+1)begin
   operand_tag0[0]=operand_tag0[0] | ({6{operand_mask0[ot]}} & rob_src0[ot]);
   operand_tag1[0]=operand_tag1[0] | ({6{operand_mask0[ot]}} & rob_src1[ot]);
   operand_tag0[1]=operand_tag0[1] | ({6{operand_mask1[ot]}} & rob_src0[ot]);
   operand_tag1[1]=operand_tag1[1] | ({6{operand_mask1[ot]}} & rob_src1[ot]);
   operand_owner0[0]=operand_owner0[0] | (operand_mask0[ot] && rob_src0[ot][5] && result_lane[resident_row(rob_src0[ot])]);
   operand_owner1[0]=operand_owner1[0] | (operand_mask0[ot] && rob_src1[ot][5] && result_lane[resident_row(rob_src1[ot])]);
   operand_owner0[1]=operand_owner0[1] | (operand_mask1[ot] && rob_src0[ot][5] && result_lane[resident_row(rob_src0[ot])]);
   operand_owner1[1]=operand_owner1[1] | (operand_mask1[ot] && rob_src1[ot][5] && result_lane[resident_row(rob_src1[ot])]);
  end
 end

 wire [1:0] fast_mul;
 reg [ROB_ENTRIES-1:0] mul_ready_candidates,mul_ready_upper,mul_ready_onehot /* synthesis syn_maxfan=8 */;
 reg [ROB_BITS-1:0] mul_sample_slot /* synthesis syn_maxfan=8 */;integer ms;
 always @* begin
  mul_ready_candidates=0;mul_sample_slot=0;
  for(ms=0;ms<ROB_ENTRIES;ms=ms+1)
   mul_ready_candidates[ms]=rob_valid[ms] && !rob_issued[ms] && rob_kind[ms]==3;
  mul_ready_upper=mul_ready_candidates & age_upper_mask;
  mul_ready_onehot=(|mul_ready_upper)?(mul_ready_upper & (~mul_ready_upper+1'b1)):(mul_ready_candidates & (~mul_ready_candidates+1'b1));
  for(ms=0;ms<ROB_ENTRIES;ms=ms+1)if(mul_ready_onehot[ms])mul_sample_slot=mul_sample_slot | ms;
 end
 wire [31:0] issue_base_a[0:1],issue_base_b[0:1];
 // Payload may be speculative; issue validity alone authorizes consumption.
 reg [5:0] mul_tag0,mul_tag1;reg [2:0] mul_funct3;integer mt;
 always @* begin
  mul_tag0=0;mul_tag1=0;mul_funct3=0;
  for(mt=0;mt<ROB_ENTRIES;mt=mt+1)begin
   mul_tag0=mul_tag0 | ({6{mul_ready_onehot[mt]}} & rob_src0[mt]);
   mul_tag1=mul_tag1 | ({6{mul_ready_onehot[mt]}} & rob_src1[mt]);
   mul_funct3=mul_funct3 | ({3{mul_ready_onehot[mt]}} & rob_mul_funct3[mt]);
  end
 end


 // Read-port identity is captured ahead of the DSP edge. A mismatching issue
 // uses the existing held-operand fallback; prediction never authorizes issue.
 reg mul_pref_valid;
 reg [ROB_BITS-1:0] mul_pref_slot;
 reg [5:0] mul_pref_tag0,mul_pref_tag1;
 reg [2:0] mul_pref_funct3;
 always @(posedge clk)begin
  if(rst)begin mul_pref_valid<=0;mul_pref_slot<=0;mul_pref_tag0<=0;mul_pref_tag1<=0;mul_pref_funct3<=0;end
  else if(enable)begin
   mul_pref_valid<=!flush_now && (|mul_ready_onehot);
   mul_pref_slot<=mul_sample_slot;mul_pref_tag0<=`CANONICAL_TAG(mul_tag0);mul_pref_tag1<=`CANONICAL_TAG(mul_tag1);mul_pref_funct3<=mul_funct3;
   // Newly renamed MUL can use its first issue edge without another bubble.
   if(!flush_now && !(|mul_ready_onehot) && allocate)begin
    if(kind[0]==3)begin
     mul_pref_valid<=1;mul_pref_slot<=tail;mul_pref_tag0<=rename_a[0];mul_pref_tag1<=rename_b[0];mul_pref_funct3<=fetch_inst[14:12];
    end else if(allocation_count==2 && kind[1]==3)begin
     mul_pref_valid<=1;mul_pref_slot<=second_tail;mul_pref_tag0<=rename_a[1];mul_pref_tag1<=rename_b[1];mul_pref_funct3<=fetch_inst[46:44];
    end
   end
  end
 end
 wire [31:0] prefetched_mul_a=`JFIX_PRF_READ(mul_pref_tag0);
 wire [31:0] prefetched_mul_b=`JFIX_PRF_READ(mul_pref_tag1);
 generate for(g=0;g<2;g=g+1)begin:early_multiply
  assign issue_base_a[g]=`ISSUE_PRF_READ(operand_tag0[g],operand_owner0[g]);
  assign issue_base_b[g]=`ISSUE_PRF_READ(operand_tag1[g],operand_owner1[g]);
  // Only previously registered readiness permits the early DSP edge. A
  // same-cycle producer bypass retains the operand-register/hold path.
  // synthesis translate_off
  always @(posedge clk)if(!rst && fast_mul[g] && rob_kind[select_slot[g]]==3)begin
   if(prefetched_mul_a!==issue_base_a[g] || prefetched_mul_b!==issue_base_b[g])
    $fatal(1,"Registered MUL read identity/data mismatch");
  end
  // synthesis translate_on
  assign fast_mul[g]=select_valid[g] && mul_pref_valid && select_slot[g]==mul_pref_slot && rob_source0_ready[mul_pref_slot] && rob_source1_ready[mul_pref_slot];
 end endgenerate
 // Static parity issue: each valid lane reads only its own metadata bank.
 wire [31:0] lane_inst[0:1],lane_pc[0:1];
 wire [31:0] lane_imm[0:1],lane_imm_reference[0:1];wire [4:0] lane_op[0:1];
 // Format is decoded at allocation, in parallel with the later issue-bank
 // instruction read. Payload and the issue/flush contract are unchanged.
 reg [6:0] rob_imm_format[0:ROB_ENTRIES-1];
 wire [6:0] allocate_imm_format[0:1];
 reg [6:0] issue_imm_format[0:1];
 integer imf;
 always @* begin
  issue_imm_format[0]=0;issue_imm_format[1]=0;
  for(imf=0;imf<ROB_ENTRIES;imf=imf+1)begin
   issue_imm_format[0]=issue_imm_format[0] | ({7{operand_mask0[imf]}} & rob_imm_format[imf]);
   issue_imm_format[1]=issue_imm_format[1] | ({7{operand_mask1[imf]}} & rob_imm_format[imf]);
  end
 end
 generate for(genvar fi=0;fi<2;fi=fi+1)begin:allocate_immediate_format
  JFIX_IMMEDIATE_FORMAT format(.inst(fetch_inst[fi*32+:32]),.fmt(allocate_imm_format[fi]));
 end endgenerate
 wire [9:0] lane_control[0:1];wire [1:0] lane_src_pc,lane_src_imm;
 wire [15:0] lane_predpc_low[0:1];
 generate for(g=0;g<2;g=g+1)begin:lane_metadata_read
  assign lane_inst[g]=`READ_ROB_INST(select_slot[g]);
  JFIX_INTEGER_OP operation_decode(.inst(lane_inst[g]),.op(lane_op[g]));
  JFIX_INTEGER_CONTROL control_decode(.inst(lane_inst[g]),.control(lane_control[g]));
  DECODER immediate_decode(.inst(lane_inst[g]),.imm(lane_imm_reference[g]),
   .alu_src0_sel(lane_src_pc[g]),.alu_src1_sel(lane_src_imm[g]));
  JFIX_IMMEDIATE_VALUE immediate_fast(.inst(lane_inst[g]),.fmt(issue_imm_format[g]),.imm(lane_imm[g]));
  // synthesis translate_off
  always @(posedge clk)if(!rst && enable && select_valid[g] && lane_imm[g]!==lane_imm_reference[g])
   $fatal(1,"Immediate format mismatch lane=%0d inst=%h actual=%h reference=%h",g,lane_inst[g],lane_imm[g],lane_imm_reference[g]);
  // synthesis translate_on

  assign lane_pc[g]=(rob_fetch_fault[select_slot[g]]?
    ((32'b0 | `READ_ROB_PC_HIGH(select_slot[g]))<<16):32'h80000000)
    | `READ_ROB_PC_LOW(select_slot[g]);
  assign lane_predpc_low[g]=`READ_ROB_PREDPC_LOW(select_slot[g]);
 end endgenerate
 // synthesis translate_off
 always @(posedge clk)if(!rst && enable && RESIDENT_INTEGER_PC)begin
  if(select_valid[0] && (lane_pc[0][31:16]!=16'h8000 || |lane_pc[0][1:0]))
   $fatal(1,"Nonresident/faulting PC reached resident integer lane 0");
  if(select_valid[1] && (lane_pc[1][31:16]!=16'h8000 || |lane_pc[1][1:0]))
   $fatal(1,"Nonresident/faulting PC reached resident integer lane 1");
 end
 // synthesis translate_on
 // Predecode on the existing issue-to-execute edge. Invalid payload may
 // sample freely; a held MUL preserves both instruction and decoded fields.
 generate for(g=0;g<2;g=g+1)begin:execute_predecode_capture
  always @(posedge clk)if(enable && !execute_hold[g])begin
   execute_imm[g]<=lane_imm[g];execute_op[g]<=lane_op[g];
   execute_control[g]<=lane_control[g];
   execute_src_pc[g]<=lane_src_pc[g];execute_src_imm[g]<=lane_src_imm[g];
   execute_inst[g]<=lane_inst[g];
   execute_pc[g]<=RESIDENT_INTEGER_PC?{16'h8000,lane_pc[g][15:0]}:lane_pc[g];
  end
 end endgenerate
 // Capture candidate payload locally. On recovery it is harmless data;
 // read_valid is cleared separately and therefore never authorizes its use.
 generate for(g=0;g<2;g=g+1)begin:read_identity_payload
  always @(posedge clk)if(enable && select_capture_valid[g])begin
   read_slot[g]<=select_slot[g];read_dest[g]<=`READ_ROB_DEST(select_slot[g]);
   read_write[g]<=rob_write[select_slot[g]];read_mul[g]<=rob_kind[select_slot[g]]==3;
   read_inst[g]<=lane_inst[g];read_pc[g]<=lane_pc[g];
   read_predpc[g]<=rob_predpc[select_slot[g]];
   read_src0[g]<=rob_src0[select_slot[g]];read_src1[g]<=rob_src1[select_slot[g]];
  end
 end endgenerate

 // Only operand payload may prefill. Actual select/valid/issued, owner,
 // MUL hold, exceptions and side effects keep the original authorization.
 generate for(g=0;g<2;g=g+1)begin:joint_operand_prefill
  always @(posedge clk)if(enable && !execute_hold[g])begin
      execute_a[g]<=operand_value(operand_tag0[g],`ISSUE_PRF_READ(operand_tag0[g],operand_owner0[g]),bypass_tag_valid,completion_dest,completion_data,serial_expected,serial_expected_dest,serial_result);
      execute_b[g]<=operand_value(operand_tag1[g],`ISSUE_PRF_READ(operand_tag1[g],operand_owner1[g]),bypass_tag_valid,completion_dest,completion_data,serial_expected,serial_expected_dest,serial_result);
  end
 end endgenerate
 generate for(g=0;g<2;g=g+1)begin:e
  JFIX_OOO_INTEGER #(.PREPARED_DECODE(1)) integer_unit(.inst(execute_inst[g]),.pc(execute_pc[g]),
   .a(execute_a[g]),.b(execute_b[g]),.result(integer_result[g]),
   .next_pc(execute_next[g]),.misaligned(execute_fault[g]),
   .prepared_imm(execute_imm[g]),.prepared_op(execute_op[g]),
   .prepared_control(execute_control[g]),
   .prepared_src_pc(execute_src_pc[g]),.prepared_src_imm(execute_src_imm[g]));
  // Sample every enabled edge; validity stays with the execution slot.
  // The old product is consumed before this edge replaces partial products.
  wire [2:0] multiplier_funct3=execute_hold[g]?execute_inst[g][14:12]:mul_pref_funct3;
  MUL_PIPE multiplier(.clk(clk),.rst(rst),.start(enable),
   .op(5'd19+{2'b0,multiplier_funct3}),
   .src0(execute_hold[g]?execute_a[g]:prefetched_mul_a),
   .src1(execute_hold[g]?execute_b[g]:prefetched_mul_b),.result(multiply_result[g]));
  assign execute_result[g]=(execute_inst[g][6:0]==7'h33 && execute_inst[g][31:25]==1 && !execute_inst[g][14])?
   multiply_result[g]:integer_result[g];
 end endgenerate
 // Destinations are unique until retirement releases their ownership.
 // Local one-hot write merging avoids three cascaded whole-array mux layers.
 assign response_slot=serial_pending?serial_slot:serial_request_slot;
 wire serial_tag_valid=serial_complete && rob_write[response_slot];
 assign serial_write=serial_tag_valid && !serial_fault;
 // LSU completion wakes the slot immediately. Physical RAM publication is
 // registered separately; the pending value forwards until it reaches RAM.
 genvar word_index;
 wire spec_retire0=retire0 && commit0_write && `READ_SPECULATIVE(commit0_rd)==commit0_dest;
 wire spec_retire1=retire1 && commit1_write && `READ_SPECULATIVE(commit1_rd)==commit1_dest;
 // Static per-architectural-register rename rows. Lane 1 wins same-rd pairs;
 // recovery includes retirement on this edge before restoring speculation.
 always @(posedge clk)if(!rst && enable)begin
  if(!flush_now && allocate)begin
   if(wrd[0])spec_map0[rd[0]]<=tail;
   if(allocation_count==2 && wrd[1])spec_map1[rd[1]]<=second_tail;
  end
 end
 generate for(word_index=0;word_index<32;word_index=word_index+1)begin:map_row
  wire c0=retire0 && commit0_write && commit0_rd==word_index;
  wire c1=retire1 && commit1_write && commit1_rd==word_index;
  wire a0=allocate && wrd[0] && rd[0]==word_index;
  wire a1=allocate && allocation_count==2 && wrd[1] && rd[1]==word_index;
  always @(posedge clk)begin
   if(rst)begin spec_owner[word_index]<=2;end
   else if(enable)begin
    if(flush_now)spec_owner[word_index]<=2;
    else if(a0 || a1)spec_owner[word_index]<=a1?1:0;
    else if((spec_retire0 && commit0_rd==word_index) || (spec_retire1 && commit1_rd==word_index))spec_owner[word_index]<=2;
   end
  end
 end endgenerate
 generate for(word_index=0;word_index<PRF_ENTRIES;word_index=word_index+1)begin:ready_row
  always @(posedge clk) begin
   if(rst || (enable && flush_now)) physical_ready[word_index]<=1;
   else if(enable) begin
    if((completion_valid[0] && completion_dest[5:0]==word_index) ||
       (completion_valid[1] && completion_dest[11:6]==word_index) ||
       (serial_write && `READ_ROB_DEST(response_slot)==word_index)) physical_ready[word_index]<=1;
    if(allocate && ((wrd[0] && dest0==word_index) ||
       (allocation_count==2 && wrd[1] && dest1==word_index))) physical_ready[word_index]<=0;
    if(word_index==0) physical_ready[word_index]<=1;
   end
  end
 end endgenerate
 always @(posedge clk)if(!rst && enable)begin
  if(retire0 && commit0_write)arch_bank0[commit0_rd]<=retire_value0;
  if(retire1 && commit1_write)arch_bank1[commit1_rd]<=retire_value1;
 end
 generate for(word_index=0;word_index<32;word_index=word_index+1)begin:arch_row
  always @(posedge clk)begin
   if(word_index==0 || rst)arch_owner[word_index]<=0;
   else if(enable)begin
    if(retire0 && commit0_write && commit0_rd==word_index)arch_owner[word_index]<=1;
    if(retire1 && commit1_write && commit1_rd==word_index)arch_owner[word_index]<=2;
   end
  end
 end endgenerate
 generate for(g=0;g<2;g=g+1)begin:publication_bank
  reg [31:0] values[0:ROB_ENTRIES-1],controls[0:ROB_ENTRIES-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && execute_complete[g])begin
   values[execute_slot[g]]<=execute_result[g];
   controls[execute_slot[g]]<=execute_next[g];
  end
 end endgenerate
 always @(posedge clk)if(!rst && enable && !flush_now && serial_complete)begin
  serial_values[response_slot]<=serial_result;
  serial_control[response_slot]<=serial_fault?serial_tval:serial_target;
  serial_causes[response_slot]<=serial_cause;
 end
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:publication_lane_owner
  always @(posedge clk) begin
   if(rst) result_lane[word_index]<=word_index%2;
   else if(enable && !flush_now) begin
    if(execute_complete[0] && execute_slot[0]==word_index) result_lane[word_index]<=0;
    if(execute_complete[1] && execute_slot[1]==word_index) result_lane[word_index]<=1;
   end
  end
 end endgenerate
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:publication_view
  assign rob_value[word_index]=`READ_ROB_VALUE(word_index);
  assign rob_control_value[word_index]=`READ_ROB_CONTROL(word_index);
  assign rob_cause[word_index]=`READ_ROB_CAUSE(word_index);
 end endgenerate
 // The resolved next PC and exception tval are mutually exclusive uses.
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:control_value_alias
  assign rob_pc[word_index]=`READ_ROB_PC(word_index);
  assign rob_nextpc[word_index]=rob_control_value[word_index];
  assign rob_tval[word_index]=rob_control_value[word_index];
 end endgenerate
 wire [1:0] rename_ready_a,rename_ready_b,rename_fault,rename_pred_resident;
 wire [31:0] rename_pc[0:1],rename_seqpc[0:1],rename_nextpc[0:1],rename_tval[0:1];
 wire [31:0] rename_cause[0:1];
 generate for(g=0;g<2;g=g+1)begin:rename_identity
  // A pair RAW always waits for the newly allocated older destination.
  // Otherwise readiness uses the committed-to-this-cycle speculative map.
  // Read that map in parallel with operand-use/Zbb decode; do not send the
  // late use/pair-RAW decision through another physical-ready address mux.
  wire [5:0] map_a=source_map_a[g],map_b=source_map_b[g];
  wire ready_map_a=source_ready(map_a,physical_ready[map_a],completion_valid,completion_dest) ||
    (serial_tag_valid && `READ_ROB_DEST(response_slot)==map_a);
  wire ready_map_b=source_ready(map_b,physical_ready[map_b],completion_valid,completion_dest) ||
    (serial_tag_valid && `READ_ROB_DEST(response_slot)==map_b);
  assign rename_ready_a[g]=!bundle_raw_a[g] && (!use1[g] || ready_map_a);
  assign rename_ready_b[g]=!bundle_raw_b[g] && (!use2[g] || ready_map_b);
  assign rename_pc[g]=fetch_pc+4*g;
  assign rename_seqpc[g]=rename_pc[g]+4;
  assign rename_nextpc[g]=fetch_pred_taken[g]?fetch_pred_target[g*32+:32]:rename_seqpc[g];
  // Select a precomputed scalar instead of comparing a late wide PC mux.
  assign rename_pred_resident[g]=fetch_pred_taken[g]?
   fetch_pred_target[g*32+16+:16]==16'h8000:rename_seqpc[g][31:16]==16'h8000;
  // synthesis translate_off
  always @(posedge clk)if(!rst && allocate && rename_pred_resident[g]!==
    (rename_nextpc[g][31:16]==16'h8000))$fatal(1,"Prediction resident scalar mismatch");
  // synthesis translate_on
  assign rename_fault[g]=fetch_fault[g] || illegal[g] || ecall[g] || ebreak[g];
  assign rename_cause[g]=fetch_fault[g]?1:illegal[g]?2:ebreak[g]?3:11;
  assign rename_tval[g]=fetch_fault[g]?rename_pc[g]:illegal[g]?fetch_inst[g*32+:32]:0;
 end endgenerate
 // An accepted ready Load may enter the existing request buffer directly
 // from rename when no older unissued Serial operation exists. The ordinary
 // request-normal-load/head gate still controls external publication.
 wire early_lane=fetch_inst[6:0]!=7'h03;
 wire early_candidate=(!early_lane || allocation_count==2) &&
   (early_lane?fetch_inst[38:32]:fetch_inst[6:0])==7'h03;
 wire [5:0] early_arch_tag=`READ_SPECULATIVE(rs1[early_lane]);
 wire early_capture=1'b0 && PRECOMPUTE_MEMORY_ADDRESS && allocate && early_candidate && physical_ready[early_arch_tag] && !(retire0 && commit0_write && early_arch_tag==commit0_dest) && !(retire1 && commit1_write && early_arch_tag==commit1_dest) &&
   (!early_lane || kind[0]!=2) &&
   !serial_found && !serial_pending && (!serial_request_valid || serial_accept) &&
   rename_ready_a[early_lane] && !rename_fault[early_lane];
 wire [ROB_BITS-1:0] early_slot=early_lane?second_tail:tail;
 wire [31:0] early_inst=early_lane?fetch_inst[63:32]:fetch_inst[31:0];
 // Read the two decode positions independently. Opcode selection occurs
 // after both addresses, never before the map/value RAM cascade.
 wire [31:0] early_addresses[0:1];
 genvar el;
 generate for(el=0;el<2;el=el+1)begin:early_address_lane
  wire [5:0] early_tag=`READ_SPECULATIVE(rs1[el]); wire [31:0] base=`JFIX_PRF_READ(early_tag);
  wire [31:0] inst=fetch_inst[el*32+:32];
  assign early_addresses[el]=base+{{20{inst[31]}},inst[31:20]};
 end endgenerate
 wire [31:0] early_address=early_addresses[early_lane];
 // Allocation-only metadata has one write per parity bank per cycle.
 genvar mb,mv;
 generate for(mb=0;mb<2;mb=mb+1)begin:meta_bank
  wire first_in_bank=tail[0]==mb;
  wire bank_write=allocate && (first_in_bank || allocation_count==2);
  wire [ROB_BITS-2:0] bank_index=first_in_bank?tail[ROB_BITS-1:1]:second_tail[ROB_BITS-1:1];
  reg [31:0] rob_inst_ram[0:ROB_ENTRIES/2-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && bank_write)rob_inst_ram[bank_index]<=first_in_bank?fetch_inst[31:0]:fetch_inst[63:32];
  reg [15:0] rob_pc_high_ram[0:ROB_ENTRIES/2-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && bank_write)rob_pc_high_ram[bank_index]<=first_in_bank?rename_pc[0][31:16]:rename_pc[1][31:16];
  reg [15:0] rob_pc_low_ram[0:ROB_ENTRIES/2-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && bank_write)rob_pc_low_ram[bank_index]<=first_in_bank?rename_pc[0][15:0]:rename_pc[1][15:0];
  reg [15:0] rob_predpc_low_ram[0:ROB_ENTRIES/2-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && bank_write)rob_predpc_low_ram[bank_index]<=first_in_bank?rename_nextpc[0][15:0]:rename_nextpc[1][15:0];
  reg [5:0] rob_old_ram[0:ROB_ENTRIES/2-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && bank_write)rob_old_ram[bank_index]<=first_in_bank?rename_old[0]:rename_old[1];
  reg [4:0] rob_rd_ram[0:ROB_ENTRIES/2-1] /* synthesis syn_ramstyle="lut_ram" */;
  always @(posedge clk)if(!rst && enable && !flush_now && bank_write)rob_rd_ram[bank_index]<=first_in_bank?rd[0]:rd[1];
  for(mv=0;mv<ROB_ENTRIES/2;mv=mv+1)begin:view
   assign rob_inst[2*mv+mb]=rob_inst_ram[mv];
   assign rob_pc_low[2*mv+mb]=rob_pc_low_ram[mv];
   assign rob_predpc_low[2*mv+mb]=rob_predpc_low_ram[mv];
   assign rob_dest[2*mv+mb]=`READ_ROB_DEST(2*mv+mb);
   assign rob_old[2*mv+mb]=rob_old_ram[mv];
   assign rob_rd[2*mv+mb]=rob_rd_ram[mv];
  end
 end endgenerate
 generate for(word_index=0;word_index<ROB_ENTRIES;word_index=word_index+1)begin:rob_row
  wire alloc0=allocate && tail==word_index;
  wire alloc1=allocate && allocation_count==2 && second_tail==word_index;
  wire done0=execute_complete[0] && execute_slot[0]==word_index;
  wire done1=execute_complete[1] && execute_slot[1]==word_index;
  wire serial_done=serial_complete && response_slot==word_index;
  // Tail and second_tail are distinct. When allocation is valid this
  // row identity is exactly alloc1; outside allocation payload is unused.
  // Prediction/admission must authorize writes, not steer their wide data.
  wire lane=(second_tail==word_index);
  always @(posedge clk)begin
   if(rst)begin
    rob_valid[word_index]<=0;rob_done[word_index]<=0;rob_issued[word_index]<=0;
    rob_exception[word_index]<=0;rob_write[word_index]<=0;rob_restart[word_index]<=0;
    rob_prediction_wrong[word_index]<=0;
   end else if(enable)begin
    if(flush_now)begin
     rob_valid[word_index]<=0;rob_done[word_index]<=0;rob_issued[word_index]<=0;
     rob_exception[word_index]<=0;rob_write[word_index]<=0;rob_restart[word_index]<=0;
    end else begin
     if((retire0 && head==word_index) || (retire1 && second_head==word_index))begin
      rob_valid[word_index]<=0;rob_done[word_index]<=0;
     end
     if(retire0 && commit0_write)begin
      if(rob_src0[word_index]==commit0_dest)rob_src0[word_index]<={1'b0,commit0_rd};
      if(rob_src1[word_index]==commit0_dest)rob_src1[word_index]<={1'b0,commit0_rd};
     end
     if(retire1 && commit1_write)begin
      if(rob_src0[word_index]==commit1_dest)rob_src0[word_index]<={1'b0,commit1_rd};
      if(rob_src1[word_index]==commit1_dest)rob_src1[word_index]<={1'b0,commit1_rd};
     end
     if((select_valid[0] && select_slot[0]==word_index) ||
       (select_valid[1] && select_slot[1]==word_index) ||
       ((SERIAL_READ_PIPE==1 || SERIAL_READ_PIPE==3)?serial_reserve && serial_select_slot==word_index:SERIAL_READ_PIPE==2?serial_read_fire && serial_select_slot==word_index:serial_capture && serial_select_slot==word_index))rob_issued[word_index]<=1;
     if(done0 || done1)begin
      rob_done[word_index]<=1;rob_exception[word_index]<=done1?execute_fault[1]:execute_fault[0];
      rob_prediction_wrong[word_index]<=done1?
       (!execute_pred_resident[1] || execute_next[1][31:16]!=16'h8000 || execute_next[1][15:0]!=execute_predpc_low[1]):(!execute_pred_resident[0] || execute_next[0][31:16]!=16'h8000 || execute_next[0][15:0]!=execute_predpc_low[0]);
     end
     if(serial_done)begin
      rob_done[word_index]<=1;rob_exception[word_index]<=serial_fault;
      rob_restart[word_index]<=serial_restart;
     end
     if(alloc0 || alloc1)begin
      rob_history[word_index]<=fetch_history;rob_directions[word_index]<=lane?fetch_directions[3:2]:fetch_directions[1:0];
      rob_valid[word_index]<=1;rob_issued[word_index]<=early_capture && early_slot==word_index;rob_done[word_index]<=rename_fault[lane];
      rob_exception[word_index]<=rename_fault[lane];rob_restart[word_index]<=0;rob_prediction_wrong[word_index]<=0;
      rob_fetch_fault[word_index]<=fetch_fault[lane];
      
      rob_opcode_load[word_index]<=lane?(fetch_inst[38:32]==7'h03):(fetch_inst[6:0]==7'h03);
      rob_memory_address[word_index]<=lane?(fetch_inst[38:32]==7'h03 || fetch_inst[38:32]==7'h23):
       (fetch_inst[6:0]==7'h03 || fetch_inst[6:0]==7'h23);
      rob_kind[word_index]<=kind[lane];rob_imm_format[word_index]<=allocate_imm_format[lane];
      rob_mul_funct3[word_index]<=lane?fetch_inst[46:44]:fetch_inst[14:12];rob_write[word_index]<=wrd[lane];
      rob_initial_cause[word_index]<=rename_cause[lane][3:0];rob_rename_fault[word_index]<=rename_fault[lane];
      rob_pred_resident[word_index]<=rename_pred_resident[lane];
      rob_src0[word_index]<=rename_a[lane];rob_src1[word_index]<=rename_b[lane];
      

     end
    end
   end
  end
 end endgenerate

 // Invalid buffer payload is harmless. A valid unaccepted command is held;
 // on acceptance the next payload may replace it on the same edge.
 // Reuse the existing request operand register as an effective-address
 // register for memory operations. Compute before capture, not on acceptance.
 // Select memory facts in parallel from the one-hot scheduler, avoiding
 // encoded slot -> instruction RAM mux -> immediate decode -> address adder.
 wire [31:0] serial_row_inst[0:ROB_ENTRIES-1];
 for(genvar mr=0;mr<ROB_ENTRIES;mr=mr+1)begin:memory_facts
  assign serial_row_inst[mr]=`READ_ROB_INST(mr);
 end
 reg [31:0] capture_memory_imm;
 integer mi;
 always @* begin
  capture_memory_imm=0;
  for(mi=0;mi<ROB_ENTRIES;mi=mi+1)begin
   capture_memory_imm=capture_memory_imm | ({32{serial_absolute[mi]}} &
    {{20{serial_row_inst[mi][31]}},serial_row_inst[mi][31:25],
     serial_row_inst[mi][5]?serial_row_inst[mi][11:7]:serial_row_inst[mi][24:20]});
  end
 end
 wire capture_memory_op=selected_memory_address;
 // A successful ordered response may feed the next buffered command on
 // this edge. Faulting responses never make a dependent operand ready.
 wire capture_serial_a=serial_write && serial_source_a==`READ_ROB_DEST(response_slot);
 wire capture_serial_b=serial_write && serial_source_b==`READ_ROB_DEST(response_slot);
 wire [31:0] capture_base_a=capture_serial_a?serial_result:
  source_value(serial_source_a,
  `JFIX_PRF_READ(serial_source_a),bypass_tag_valid,completion_dest,completion_data);
 // The memory address path has no DSP result input. Merely masking a
 // completion valid while retaining execute_result would keep that STA arc.
 wire [31:0] capture_memory_base_a=capture_serial_a?serial_result:
  source_value(serial_source_a,`JFIX_PRF_READ(serial_source_a),address_bypass_valid,
   completion_dest,{integer_result[1],integer_result[0]});
 // synthesis translate_off
 longint address_mul_deferrals=0,address_mula_captures=0,address_mulb_captures=0;
 always @(posedge clk)if(!rst && enable && !flush_now && SERIAL_READ_PIPE==0 && PRECOMPUTE_MEMORY_ADDRESS)begin
  if(serial_found && selected_memory_address &&
     source_ready(serial_source_a,rob_source0_ready[serial_select_slot],bypass_tag_valid,completion_dest) &&
     !source_ready(serial_source_a,rob_source0_ready[serial_select_slot],address_bypass_valid,completion_dest) &&
     !(serial_write && serial_source_a==`READ_ROB_DEST(response_slot)))address_mul_deferrals<=address_mul_deferrals+1;
  if(serial_capture)begin
   if(selected_memory_address!==capture_memory_op)$fatal(1,"Memory address fact/identity mismatch");
   if(capture_memory_op && capture_memory_base_a!==capture_base_a)$fatal(1,"Deferred MUL address differs from original operand value");
   for(integer am=0;am<2;am++)if(bypass_tag_valid[am] && execute_mul[am])begin
    if(capture_memory_op && serial_source_a==execute_dest[am])begin
     address_mula_captures<=address_mula_captures+1;
     if(!rob_source0_ready[serial_select_slot])$fatal(1,"Memory A consumed unpublished MUL");
    end
    if(capture_memory_op && serial_source_b==execute_dest[am])address_mulb_captures<=address_mulb_captures+1;
   end
  end
 end
 final $display("MUL_ADDRESS_POLICY deferrals=%0d same_edge_published_a=%0d original_store_b=%0d",address_mul_deferrals,address_mula_captures,address_mulb_captures);
 // synthesis translate_on
 // Both legal captures agree on serial_found; invalid payload is ignored.
 // Keep dispatch/exception qualification on valid, away from address data.
 generate if(SERIAL_READ_PIPE)begin:serial_pipeline
 always @(posedge clk)begin
  if(rst)begin serial_read_valid<=0;serial_base_valid<=0;end
  else if(enable)begin
   if(flush_now)begin serial_read_valid<=0;serial_base_valid<=0;end
   else begin
    if(serial_base_fire)serial_base_valid<=0;
    if(serial_read_fire)begin
     serial_base_valid<=1;serial_base_slot<=SERIAL_READ_PIPE==2?serial_select_slot:serial_read_slot;
     serial_base_inst<=SERIAL_READ_PIPE==2?`READ_ROB_INST(serial_select_slot):serial_read_inst;
     serial_base_pc<=SERIAL_READ_PIPE==2?`READ_ROB_PC(serial_select_slot):serial_read_pc;
     serial_base_a<=SERIAL_READ_PIPE==2?capture_base_a:(serial_write && serial_read_tag_a==`READ_ROB_DEST(response_slot))?serial_result:
      source_value(serial_read_tag_a,`JFIX_PRF_READ(serial_read_tag_a),bypass_tag_valid,completion_dest,completion_data);
     serial_base_b<=SERIAL_READ_PIPE==2?(capture_serial_b?serial_result:source_value(serial_source_b,`JFIX_PRF_READ(serial_source_b),bypass_tag_valid,completion_dest,completion_data)):(serial_write && serial_read_tag_b==`READ_ROB_DEST(response_slot))?serial_result:
      source_value(serial_read_tag_b,`JFIX_PRF_READ(serial_read_tag_b),bypass_tag_valid,completion_dest,completion_data);
    end
    if(serial_read_fire)serial_read_valid<=0;
    if(serial_read_valid)begin
     serial_read_tag_a<=serial_read_current_a;serial_read_tag_b<=serial_read_current_b;
    end
    if(serial_reserve)begin
     serial_read_valid<=1;serial_read_slot<=serial_select_slot;
     serial_read_inst<=`READ_ROB_INST(serial_select_slot);serial_read_pc<=`READ_ROB_PC(serial_select_slot);
     serial_read_tag_a<=`CANONICAL_TAG(serial_source_a);serial_read_tag_b<=`CANONICAL_TAG(serial_source_b);
    end
   end
  end
 end
 wire serial_base_memory=serial_base_inst[6:0]==7'h03 || serial_base_inst[6:0]==7'h23;
 wire [31:0] serial_base_imm={{20{serial_base_inst[31]}},serial_base_inst[31:25],
  serial_base_inst[5]?serial_base_inst[11:7]:serial_base_inst[24:20]};
 if(SERIAL_READ_PIPE==3)begin:read_ea
 wire [31:0] read_imm={{20{serial_read_inst[31]}},serial_read_inst[31:25],
  serial_read_inst[5]?serial_read_inst[11:7]:serial_read_inst[24:20]};
 wire read_memory=serial_read_inst[6:0]==7'h03 || serial_read_inst[6:0]==7'h23;
 wire [31:0] add_x[0:1],add_y[0:1],add_base[0:1],add_ea[0:1];
 for(genvar ca=0;ca<2;ca=ca+1)begin:fused_address
  assign add_x[ca]=execute_src_pc[ca]?execute_pc[ca]:execute_a[ca];
  assign add_y[ca]=execute_src_imm[ca]?execute_imm[ca]:execute_b[ca];
  wire [31:0] csa_sum=add_x[ca]^add_y[ca]^read_imm;
  wire [31:0] csa_carry=((add_x[ca]&add_y[ca])|(add_x[ca]&read_imm)|(add_y[ca]&read_imm))<<1;
  assign add_base[ca]=add_x[ca]+add_y[ca];
  assign add_ea[ca]=csa_sum+csa_carry;
 end
 wire [31:0] stored_a=`JFIX_PRF_READ(serial_read_tag_a);
 wire [31:0] read_a=serial_add_match[1]?add_base[1]:serial_add_match[0]?add_base[0]:stored_a;
 wire [31:0] selected_ea=serial_add_match[1]?add_ea[1]:serial_add_match[0]?add_ea[0]:stored_a+read_imm;
 // synthesis translate_off
 always @(posedge clk)if(!rst && serial_read_fire)begin
  if(selected_ea!==read_a+read_imm)$fatal(1,"Fused ADD/AGU numerical mismatch");
  for(integer ac=0;ac<2;ac=ac+1)if(serial_add_match[ac] && add_base[ac]!==execute_result[ac])
   $fatal(1,"Fused address producer is not an ADD result");
  if(!physical_ready[serial_read_tag_a] && ~|serial_add_match)$fatal(1,"Address A not published or fuseable");
 end
 // synthesis translate_on
 wire [31:0] read_b=(serial_write && serial_read_tag_b==`READ_ROB_DEST(response_slot))?serial_result:
  source_value(serial_read_tag_b,`JFIX_PRF_READ(serial_read_tag_b),bypass_tag_valid,completion_dest,completion_data);
 always @(posedge clk)if(enable && request_space)begin
  serial_request_slot<=serial_read_slot;serial_request_inst<=serial_read_inst;serial_request_pc<=serial_read_pc;
  serial_request_a<=PRECOMPUTE_MEMORY_ADDRESS && read_memory?selected_ea:read_a;
  serial_request_b<=read_b;
 end
 end else begin:base_ea
 always @(posedge clk)if(enable && request_space)begin
  serial_request_slot<=serial_base_slot;serial_request_inst<=serial_base_inst;serial_request_pc<=serial_base_pc;
  serial_request_a<=PRECOMPUTE_MEMORY_ADDRESS && serial_base_memory?(serial_base_a+serial_base_imm):serial_base_a;
  serial_request_b<=serial_base_b;
 end
 end
 end else begin:serial_legacy
 always @(posedge clk)if(enable && (!serial_request_valid || serial_accept))begin
  serial_request_slot<=serial_found?serial_select_slot:early_slot;
  serial_req_dest<=serial_found?`READ_ROB_DEST(serial_select_slot):`READ_ROB_DEST(early_slot);
  serial_req_writes<=serial_found?rob_write[serial_select_slot]:rob_write[early_slot];
  serial_request_inst<=serial_found?`READ_ROB_INST(serial_select_slot):early_inst;
  serial_request_pc<=serial_found?`READ_ROB_PC(serial_select_slot):rename_pc[early_lane];
  serial_request_a<=early_capture ? early_address : PRECOMPUTE_MEMORY_ADDRESS && capture_memory_op ?
   (capture_memory_base_a+capture_memory_imm):capture_base_a;
  serial_request_b<=capture_serial_b?serial_result:source_value(serial_source_b,`JFIX_PRF_READ(serial_source_b),bypass_tag_valid,completion_dest,completion_data);
 end
 end endgenerate

 integer i,l,s;
 always @(posedge clk)begin
  if(rst)commit_hot<=1;
  else if(enable)begin
   if(flush_now)commit_hot<=1;
   else if(retire_count==2)commit_hot<={commit_hot[ROB_ENTRIES-3:0],commit_hot[ROB_ENTRIES-1:ROB_ENTRIES-2]};
   else if(retire_count==1)commit_hot<=second_hot;
  end
 end

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
    fetch_pc<=redirect_pc;
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
      execute_slot[l]<=select_slot[l];execute_dest[l]<=`READ_ROB_DEST(select_slot[l]);execute_write[l]<=rob_write[select_slot[l]];
      execute_mul[l]<=rob_kind[select_slot[l]]==3;
      execute_predpc_low[l]<=lane_predpc_low[l];execute_pred_resident[l]<=rob_pred_resident[select_slot[l]];
     end
     if(read_fire[l])read_valid[l]<=0;
     if(select_valid[l])read_valid[l]<=1;
    end
    if(serial_accept)serial_request_valid<=0;
    if(early_capture)begin
     serial_request_valid<=1;
    end
    if(serial_capture)begin
     serial_request_valid<=1;
     
     
    end
    if(serial_accept)begin serial_pending<=1;serial_slot<=serial_request_slot;serial_pending_dest<=serial_req_dest;serial_pending_writes<=serial_req_writes;end
    if(serial_complete)begin
     s=serial_pending?serial_slot:serial_request_slot;
     serial_pending<=0;
    end
    if(allocate)begin
     tail<=advance_row(tail,allocation_count);
     fetch_pc<=fetch_pred_taken[0]?fetch_pred_target[31:0]:
      fetch_pred_taken[1]?fetch_pred_target[63:32]:fetch_pc+8;
    end
   end
  end
 end

 generate for(g=0;g<ROB_ENTRIES;g=g+1)begin:producer_readiness
  assign rob_source0_ready[g]=rob_src0[g]<32?1'b1:producer_schedule_ready[resident_row(rob_src0[g])];
  assign rob_source1_ready[g]=rob_src1[g]<32?1'b1:producer_schedule_ready[resident_row(rob_src1[g])];
  always @(posedge clk)begin
   if(rst || (enable && flush_now))producer_schedule_ready[g]<=1'b1;
   else if(enable)begin
    if((completion_valid[0] && completion_dest[5:0]==(32+g)) ||
       (completion_valid[1] && completion_dest[11:6]==(32+g)) ||
       (serial_tag_valid && response_slot==g))producer_schedule_ready[g]<=1'b1;
    if(allocate && ((wrd[0] && tail==g) ||
       (allocation_count==2 && wrd[1] && second_tail==g)))producer_schedule_ready[g]<=1'b0;
   end
  end
 end endgenerate
`undef READ_ROB_INST
`undef READ_ROB_PC_LOW
`undef READ_ROB_PREDPC_LOW
`undef READ_ROB_DEST
`undef READ_ROB_OLD
`undef READ_ROB_RD
`undef READ_COMMITTED
`undef READ_SPECULATIVE
`undef READ_INT_VALUE
`undef READ_INT_CONTROL
`undef READ_ROB_VALUE
`undef READ_ROB_CONTROL
`undef READ_ROB_CAUSE
`undef READ_ROB_PC_HIGH
`undef READ_ROB_PC
`undef ARCH_READ
`undef CANONICAL_TAG
`undef CANONICAL_SPEC
`undef JFIX_PRF_READ
 // Passive debug boundary. All fields describe this exact retirement edge.
 // No observer output is consumed by functional CPU logic.
 always @(posedge clk)begin
  if(rst)debug_event_q<=0;
  else debug_event_q<={3'b0,serial_pending,rob_occupancy,flush_now,take_irq,
   trap_valid,commit1_prediction_wrong,commit0_prediction_wrong,
   commit1_kind,commit0_kind,select_valid,retire1,retire0,enable,1'b1};
  // Payload is only meaningful with the matching registered event flags.
  debug_payload_q<={redirect_pc,retire_pc};
 end

endmodule

module JFIX_OOO_INTEGER #(parameter PREPARED_DECODE=0)(input [31:0] inst,pc,a,b,
 output [31:0] result,next_pc, output misaligned,
 input [31:0] prepared_imm,input [4:0] prepared_op,
 input prepared_src_pc,prepared_src_imm,
 input [9:0] prepared_control,
 output [31:0] result_noncompare,output comparison_op,comparison_bit);
 wire [4:0] r1,r2,rd,unused_op,unused_zop,decoded_op;wire u1,u2,wr,decoded_sp,decoded_si,ill,ec,eb;
 wire [9:0] decoded_control,control;
 JFIX_INTEGER_CONTROL control_decode(.inst(inst),.control(decoded_control));
 assign control=PREPARED_DECODE?prepared_control:decoded_control;
 wire [4:0] zop=control[4:0];
 wire [31:0] decoded_imm;
 wire [31:0] imm=PREPARED_DECODE?prepared_imm:decoded_imm;
 wire [4:0] op=PREPARED_DECODE?prepared_op:decoded_op;
 wire sp=PREPARED_DECODE?prepared_src_pc:decoded_sp;
 wire si=PREPARED_DECODE?prepared_src_imm:decoded_si;
 wire [1:0] kind;wire [31:0] alu_result,half_result,alu_noncompare;
 JFIX_OOO_DECODE d(.inst(inst),.rs1(r1),.rs2(r2),.rd(rd),.use1(u1),.use2(u2),
  .write_rd(wr),.op(unused_op),.zop(unused_zop),.imm(decoded_imm),.src_pc(decoded_sp),.src_imm(decoded_si),.kind(kind),
  .illegal(ill),.ecall(ec),.ebreak(eb));
 JFIX_INTEGER_OP operation_decode(.inst(inst),.op(decoded_op));
 wire branch=control[8];
 wire signed_less,unsigned_less;
 wire [31:0] target_sum;
 // Branch/JAL/JALR address inputs are the same ADD inputs already used by
 // the ALU. Branches and SLT/SLTU share one raw-operand comparator.
 // The shared decoder remains authoritative for result selection. Direct
 // instruction fields prepare the identical shift payload in parallel,
 // without waiting for its ROM-decoded operation code.
 wire shift_i=control[5];
 wire shift_left_fast=control[6];
 wire shift_arithmetic_fast=control[7];
 ALU #(.EXTERNAL_COMPARE_INPUTS(1),.EARLY_SHIFT_CONTROL(1)) alu(.alu_src0(sp?pc:a),.alu_src1(si?imm:b),
  .alu_op(op),.alu_res(alu_result),.add_result(target_sum),
  .compare_src0(a),.compare_src1(branch?b:(si?imm:b)),
  .less_signed(signed_less),.less_unsigned(unsigned_less),
  .noncompare_result(alu_noncompare),
  .shift_src_i(a),.shift_amount_i(shift_i?inst[24:20]:b[4:0]),
  .shift_left_i(shift_left_fast),.shift_arithmetic_i(shift_arithmetic_fast));
 ZBB_ALU halfword(.src0(a),.src1(b),.op(zop),.result(half_result));
 reg taken;
 always @* begin
  taken=0;
  case(inst[14:12])
   0:taken=a==b;1:taken=a!=b;4:taken=signed_less;
   5:taken=!signed_less;6:taken=unsigned_less;7:taken=!unsigned_less;
   default:taken=0;
  endcase
 end
 wire jump=control[9];

 wire [31:0] target={target_sum[31:1],target_sum[0] && inst[6:0]!=7'h67};
 assign next_pc=jump || (branch && taken)?target:pc+4;
 assign misaligned=(jump || (branch && taken)) && |target[1:0];
 wire live_zbc=inst[6:0]==7'h33 && inst[31:25]==7'h05 && (inst[14:12]==1 || inst[14:12]==2 || inst[14:12]==3);
 // Three half-width polynomial products replace four independent quadrants.
 // This is a combinational identity; issue, latency and both lanes are retained.
 wire [63:0] zbc_tree[1:1];
 JFIX_CLMUL_KARATSUBA #(.WIDTH(32)) zbc_product(.a(a),.b(b),.product(zbc_tree[1]));
 wire [31:0] zbc_result=inst[14:12]==1?zbc_tree[1][31:0]:inst[14:12]==3?zbc_tree[1][63:32]:zbc_tree[1][62:31];
 assign result=live_zbc?zbc_result:jump?pc+4:zop!=0?half_result:alu_result;
 assign result_noncompare=live_zbc?zbc_result:jump?pc+4:zop!=0?half_result:alu_noncompare;
 assign comparison_op=!jump && zop==0 && (op==5'd4 || op==5'd5);
 assign comparison_bit=op==5'd4 ? signed_less:unsigned_less;
endmodule

// Exact operation decode shared by the generic unit and the issue stage.
module JFIX_INTEGER_CONTROL(input [31:0] inst,output [9:0] control);
 wire shift_i=inst[6:0]==7'h13;
 wire shift_r=inst[6:0]==7'h33;
 ZBB_DECODE halfword_decode(.inst(inst),.zbb_op(control[4:0]));
 assign control[5]=shift_i;
 assign control[6]=inst[14:12]==1 && (shift_i || (shift_r && inst[31:25]==0));
 assign control[7]=inst[14:12]==5 && ((shift_i && inst[30]) || (shift_r && inst[31:25]==7'h20));
 assign control[8]=inst[6:0]==7'h63;
 assign control[9]=inst[6:0]==7'h6f || inst[6:0]==7'h67;
endmodule

module JFIX_INTEGER_OP(input [31:0] inst,output reg [4:0] op);
 always @* begin
  op=5'd0;
  if(inst[6:0]==7'h37)op=5'd18;
  else if(inst[6:0]==7'h13 || inst[6:0]==7'h33)begin
   if(inst[6:0]==7'h13 || inst[31:25]==0 ||
      (inst[31:25]==7'h20 && (inst[14:12]==0 || inst[14:12]==5)))begin
    case(inst[14:12])
     0:op=(inst[6:0]==7'h33 && inst[30])?5'd2:5'd0;
     1:op=5'd14;2:op=5'd4;3:op=5'd5;
     4:op=5'd11;5:op=inst[30]?5'd16:5'd15;
     6:op=5'd10;7:op=5'd9;
    endcase
   end else if(inst[31:25]==1)op=5'd19+{2'b0,inst[14:12]};
  end else if(inst[6:0]==7'h0b && inst[31:25]==0)begin
   case(inst[14:12])
    0:op=5'd28;1:op=5'd29;2:op=5'd30;
    default:op=0;
   endcase
  end
 end
endmodule


// One-hot formats reproduce DECODER's immediate behavior, including zero
// for unused/unknown opcodes and CSR immediate operands.
module JFIX_IMMEDIATE_FORMAT(input [31:0] inst,output [6:0] fmt);
 wire [6:0] opcode=inst[6:0];wire [2:0] f3=inst[14:12];
 wire immop=opcode==7'h13;
 assign fmt[0]=(immop && f3!=3'b001 && f3!=3'b101) || opcode==7'h03 || opcode==7'h67;
 assign fmt[1]=immop && (f3==3'b001 || f3==3'b101);
 assign fmt[2]=opcode==7'h23;
 assign fmt[3]=opcode==7'h37 || opcode==7'h17;
 assign fmt[4]=opcode==7'h63;
 assign fmt[5]=opcode==7'h6f;
 assign fmt[6]=opcode==7'h73 && (f3==3'b101 || f3==3'b110 || f3==3'b111);
endmodule
module JFIX_IMMEDIATE_VALUE(input [31:0] inst,input [6:0] fmt,output [31:0] imm);
 assign imm=({32{fmt[0]}} & {{20{inst[31]}},inst[31:20]}) |
            ({32{fmt[1]}} & {27'b0,inst[24:20]}) |
            ({32{fmt[2]}} & {{20{inst[31]}},inst[31:25],inst[11:7]}) |
            ({32{fmt[3]}} & {inst[31:12],12'b0}) |
            ({32{fmt[4]}} & {{19{inst[31]}},inst[31],inst[7],inst[30:25],inst[11:8],1'b0}) |
            ({32{fmt[5]}} & {{11{inst[31]}},inst[31],inst[19:12],inst[20],inst[30:21],1'b0}) |
            ({32{fmt[6]}} & {27'b0,inst[19:15]});
endmodule

module JFIX_CLMUL_KARATSUBA #(parameter WIDTH=32)(
 input [WIDTH-1:0] a,b,output [2*WIDTH-1:0] product);
 generate if(WIDTH<=8)begin:leaf
  wire [2*WIDTH-1:0] terms[1:2*WIDTH-1];
  for(genvar i=0;i<WIDTH;i=i+1)begin:partial
   assign terms[WIDTH+i]=({{WIDTH{1'b0}},a}<<i)&{2*WIDTH{b[i]}};
  end
  for(genvar i=1;i<WIDTH;i=i+1)begin:reduce
   assign terms[i]=terms[2*i]^terms[2*i+1];
  end
  assign product=terms[1];
 end else begin:split
  localparam HALF=WIDTH/2;
  wire [WIDTH-1:0] low_product,high_product,sum_product;
  wire [WIDTH-1:0] cross_product=sum_product^low_product^high_product;
  JFIX_CLMUL_KARATSUBA #(.WIDTH(HALF)) lo(.a(a[HALF-1:0]),.b(b[HALF-1:0]),.product(low_product));
  JFIX_CLMUL_KARATSUBA #(.WIDTH(HALF)) hi(.a(a[WIDTH-1:HALF]),.b(b[WIDTH-1:HALF]),.product(high_product));
  JFIX_CLMUL_KARATSUBA #(.WIDTH(HALF)) mid(.a(a[HALF-1:0]^a[WIDTH-1:HALF]),.b(b[HALF-1:0]^b[WIDTH-1:HALF]),.product(sum_product));
  assign product={{WIDTH{1'b0}},low_product} ^ {high_product,{WIDTH{1'b0}}} ^ ({{WIDTH{1'b0}},cross_product}<<HALF);
 end endgenerate
endmodule

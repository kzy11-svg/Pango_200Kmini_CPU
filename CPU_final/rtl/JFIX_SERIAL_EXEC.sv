// R2 CPU-only execution: dedicated CoreMark accelerators removed.
module JFIX_SERIAL_EXEC #(parameter PRECOMPUTED_MEMORY_ADDRESS=0,parameter ZBC_IN_INTEGER=0,parameter REGISTER_RESPONSE=0,parameter REGISTER_COMMAND=0,parameter USE_STORE_READY=0,parameter USE_LOCAL_STATE_READY=0,parameter ISOLATE_LIST_OBSERVER=0,parameter LOCAL_LOAD_PAYLOAD=0,parameter PIPE_LOAD_CAPTURE=0,parameter DMA_DATA_ALWAYS=0,parameter EARLY_ORDER_GUARD=0,parameter LOCAL_BATCH_WRITE_FAULT=0)(
 input clk,rst,enable, input req_valid,output req_ready,
 input [31:0] req_inst,req_pc,req_a,req_b,
 output rsp_valid,input rsp_ready,output wire [31:0] rsp_result,
 output wire rsp_fault,output wire [31:0] rsp_cause,rsp_tval,
 output wire rsp_restart,output wire [31:0] rsp_target,
 output mem_valid,output mem_store_valid,input mem_ready,input mem_store_ready,input dma_store_offer,dma_store_fault,dma_uart_busy,input dma_store_nonzero_offer,output [31:0] mem_addr,mem_data,
 output [3:0] mem_mask,output mem_read,
 input [31:0] mem_result,input mem_fault,input drain_done,
 input timer_irq,software_irq,external_irq,
 input trap_valid,input [31:0] trap_pc,trap_cause,trap_tval,
 input [1:0] retire_count,
 output irq_valid,output [31:0] irq_cause,output [31:0] trap_vector
);
 wire store_accept_ready=USE_STORE_READY?mem_store_ready:mem_ready;
 reg [31:0] held_rsp_result,held_rsp_cause,held_rsp_tval,held_rsp_target;
 reg held_rsp_fault,held_rsp_restart;
 // Raw payload is captured once on accepted live completion. Public
 // registered mode never forwards Cache or request inputs to the Core.
 wire [31:0] raw_rsp_result;
 assign rsp_result=REGISTER_RESPONSE?held_rsp_result:raw_rsp_result;
 wire raw_rsp_fault;
 assign rsp_fault=REGISTER_RESPONSE?held_rsp_fault:raw_rsp_fault;
 wire [31:0] raw_rsp_cause;
 assign rsp_cause=REGISTER_RESPONSE?held_rsp_cause:raw_rsp_cause;
 wire [31:0] raw_rsp_tval;
 assign rsp_tval=REGISTER_RESPONSE?held_rsp_tval:raw_rsp_tval;
 wire raw_rsp_restart;
 assign rsp_restart=REGISTER_RESPONSE?held_rsp_restart:raw_rsp_restart;
 wire [31:0] raw_rsp_target;
 assign rsp_target=REGISTER_RESPONSE?held_rsp_target:raw_rsp_target;
 wire bypass,load_run_bypass,selected_unaligned,load_live,store_live;
 wire [31:0] live_address;wire [2:0] selected_f3;
 localparam IDLE=0,RUN=1,RESPONSE=2,LOAD_CAPTURE=3;
 reg [1:0] state;reg [31:0] inst_r,pc_r,a_r,b_r;
 // One head-owned mailbox. The Core handshake accepts ownership; execution
 // begins only from registered validity and payload. No younger command may
 // replace it while paused. Once launched, existing DMA/pause rules remain.
 reg command_valid;
 reg [31:0] mailbox_inst,mailbox_pc,mailbox_a,mailbox_b;
 wire [31:0] command_inst=REGISTER_COMMAND?mailbox_inst:req_inst;
 wire [31:0] command_pc=REGISTER_COMMAND?mailbox_pc:req_pc;
 wire [31:0] command_a=REGISTER_COMMAND?mailbox_a:req_a;
 wire [31:0] command_b=REGISTER_COMMAND?mailbox_b:req_b;
 wire [31:0] operation_inst=command_inst;
 wire mailbox_fire=req_valid && req_ready;
 wire accept=REGISTER_COMMAND?(command_valid && state==IDLE && enable):(req_valid && req_ready);
 assign req_ready=(!REGISTER_COMMAND || !command_valid) && state==IDLE && enable;
 always @(posedge clk)begin
  if(!command_valid)begin
   mailbox_inst<=req_inst;mailbox_pc<=req_pc;mailbox_a<=req_a;mailbox_b<=req_b;
  end
  if(rst)command_valid<=0;
  else if(REGISTER_COMMAND && mailbox_fire)command_valid<=1;
  else if(accept)command_valid<=0;
 end
 assign rsp_valid=state==RESPONSE || (!REGISTER_RESPONSE && (bypass || load_run_bypass));
 wire [4:0] op_live;wire [31:0] imm_live;
 wire [4:0] z0,rd0,rs10,rs20;
 wire [1:0] kind0;wire u10,u20,w0,sp0,si0,ill0,ec0,eb0;
 JFIX_OOO_DECODE live(.inst(command_inst),.rs1(rs10),.rs2(rs20),.rd(rd0),.use1(u10),.use2(u20),
  .write_rd(w0),.op(op_live),.zop(z0),.imm(imm_live),.src_pc(sp0),.src_imm(si0),.kind(kind0),
  .illegal(ill0),.ecall(ec0),.ebreak(eb0));
 wire div_live=command_inst[6:0]==7'h33 && command_inst[31:25]==1 && command_inst[14];
 wire clmul_live=command_inst[6:0]==7'h33 && command_inst[31:25]==7'h05 &&
  (command_inst[14:12]==1 || command_inst[14:12]==2 || command_inst[14:12]==3);
 wire clmul_held=inst_r[6:0]==7'h33 && inst_r[31:25]==7'h05 &&
  (inst_r[14:12]==1 || inst_r[14:12]==2 || inst_r[14:12]==3);
 wire div_held=inst_r[6:0]==7'h33 && inst_r[31:25]==1 && inst_r[14];
 wire load_held=inst_r[6:0]==3,store_held=inst_r[6:0]==7'h23;
 wire [31:0] address=state==IDLE?live_address:a_r;
 wire cpu_mem_valid;
 wire div_busy,div_done;wire [31:0] div_result;
 wire clmul_busy,clmul_done,clmul_req_ready;wire [31:0] clmul_result;
 // The complete OoO CPU routes all legal Zbc instructions to its two
 // single-cycle integer lanes. Standalone serial users retain the original unit.
 generate if(!ZBC_IN_INTEGER)begin:serial_zbc
 CLMUL_UNIT #(.CHUNK_BITS(32)) clmul(.clk(clk),.rst(rst),.enable(1'b1),.cancel(1'b0),
  .req_valid(accept && clmul_live),.req_ready(clmul_req_ready),.req_a(command_a),.req_b(command_b),
  .req_op(command_inst[14:12]==1?2'd0:command_inst[14:12]==3?2'd1:2'd2),
  .busy(clmul_busy),.rsp_valid(clmul_done),.rsp_ready(state==RUN && clmul_held),.rsp_result(clmul_result));
 end else begin:integer_zbc
  assign clmul_busy=1'b0;assign clmul_done=1'b0;
  assign clmul_req_ready=1'b0;assign clmul_result=32'b0;
  // synthesis translate_off
  always @(posedge clk)if(!rst && accept && clmul_live)
   $fatal(1,"Zbc routing contract violated: command entered serial unit");
  // synthesis translate_on
 end endgenerate
 DIV_UNIT div(.clk(clk),.rst(rst),.start(accept && div_live),.op(op_live),
  .src0(command_a),.src1(command_b),.busy(div_busy),.done(div_done),.result(div_result));
 wire [31:0] csr_data,mtvec,mepc;wire unused_mie,unused_mtie;
 wire is_csr=command_inst[6:0]==7'h73 && command_inst[14:12]!=0;
 wire csr_write=is_csr && (command_inst[13:12]==1 || command_inst[19:15]!=0);
 wire [31:0] csr_operand=command_inst[14]?{27'b0,command_inst[19:15]}:command_a;
 wire [31:0] csr_new=command_inst[13:12]==1?csr_operand:
  command_inst[13:12]==2?(csr_data|csr_operand):(csr_data&~csr_operand);
 CSR csr(.clk(clk),.rst(rst),.csr_we_ex(accept && csr_write),
  .csr_addr_ex(command_inst[31:20]),.csr_wd_ex(csr_new),.csr_rd_ex(csr_data),
  .trap_taken(trap_valid),.trap_pc(trap_pc),.trap_cause(trap_cause),.trap_tval(trap_tval),
  .timer_irq(timer_irq),.software_irq(software_irq),.external_irq(external_irq),
  .retire(retire_count),.mret_taken(accept && command_inst==32'h30200073),
  .mtvec_o(mtvec),.mepc_o(mepc),.mstatus_mie_o(unused_mie),.mie_mtie_o(unused_mtie),
  .irq_enabled(irq_valid),.irq_cause(irq_cause));
 assign trap_vector=(mtvec&32'hfffffffc)+
  ((mtvec[1:0]==1 && trap_cause[31])?{trap_cause[29:0],2'b00}:32'd0);
 // a_r holds the already computed transaction address, not the base
 // operand. Capture on the existing accept edge; retries need neither
 // another instruction decode nor another address addition.
 wire unaligned=(inst_r[13:12]==1 && address[0]) ||
  (inst_r[13:12]==2 && |address[1:0]);
 assign mem_store_valid=(state==IDLE?accept && store_live:state==RUN && store_held) && !selected_unaligned;
 assign cpu_mem_valid=(state==IDLE?accept && (load_live || store_live):state==RUN && (load_held || store_held)) && !selected_unaligned;
 assign mem_valid=cpu_mem_valid;
 assign mem_read=state==IDLE?load_live:load_held;
 wire [31:0] cpu_mem_addr=state==IDLE?live_address:address;
 assign mem_addr=cpu_mem_addr;
 assign mem_mask=mem_read?0:selected_f3[1:0]==0?(4'b0001<<mem_addr[1:0]):
  selected_f3[1:0]==1?(4'b0011<<mem_addr[1:0]):4'b1111;
 assign mem_data=(state==IDLE?command_b:b_r) << (8*mem_addr[1:0]);
 // Select byte lanes and extension bits in parallel. The controls depend
 // only on the existing owner/format/address; returned data sees AND-OR
 // selection instead of a byte barrel followed by a format-result mux.
 // Preserve all eight f3 values and all offsets, including fault/invalid
 // payload cycles: f3=2/3/6/7 returns the unshifted word; LH at offset3
 // has a zero upper byte after the original logical right shift.
 wire load_word_passthrough=selected_f3[1];
 wire load_half=selected_f3[1:0]==2'b01;
 wire load_signed_byte=selected_f3==3'b000;
 wire load_signed_half=selected_f3==3'b001;
 // During a real CPU load the arbiter must select the CPU's own address.
 // Keep its low bits local; DMA addresses are irrelevant to this payload.
 wire [1:0] load_offset=LOCAL_LOAD_PAYLOAD?cpu_mem_addr[1:0]:mem_addr[1:0];
 wire [3:0] load_byte_position={load_offset==2'd3,
  load_offset==2'd2,load_offset==2'd1,load_offset==2'd0};
 wire [3:0] load_low_select={4{!load_word_passthrough}} & load_byte_position;
 wire [2:0] load_half_select={3{load_half}} & load_byte_position[2:0];
 wire [3:0] load_byte_sign_select={4{load_signed_byte}} & load_byte_position;
 wire [2:0] load_half_sign_select={3{load_signed_half}} & load_byte_position[2:0];
 // Always sample without reset or CE: only LOAD_CAPTURE consumes this
 // word, exactly one cycle after the real accepted CPU Load response.
 reg [31:0] cpu_load_q;
 always @(posedge clk)if(PIPE_LOAD_CAPTURE)cpu_load_q<=mem_result;
 wire [31:0] cpu_load_data=PIPE_LOAD_CAPTURE?cpu_load_q:mem_result;
 wire load_middle_sign=(cpu_load_data[7] & load_byte_sign_select[0]) |
  (cpu_load_data[15] & load_byte_sign_select[1]) |
  (cpu_load_data[23] & load_byte_sign_select[2]) |
  (cpu_load_data[31] & load_byte_sign_select[3]);
 wire load_upper_sign=(cpu_load_data[7] & load_byte_sign_select[0]) |
  (cpu_load_data[15] & (load_byte_sign_select[1] | load_half_sign_select[0])) |
  (cpu_load_data[23] & (load_byte_sign_select[2] | load_half_sign_select[1])) |
  (cpu_load_data[31] & (load_byte_sign_select[3] | load_half_sign_select[2]));
 wire [31:0] extended;
 assign extended[7:0]=
  ({8{load_word_passthrough | load_low_select[0]}} & cpu_load_data[7:0]) |
  ({8{load_low_select[1]}} & cpu_load_data[15:8]) |
  ({8{load_low_select[2]}} & cpu_load_data[23:16]) |
  ({8{load_low_select[3]}} & cpu_load_data[31:24]);
 assign extended[15:8]=
  ({8{load_word_passthrough | load_half_select[0]}} & cpu_load_data[15:8]) |
  ({8{load_half_select[1]}} & cpu_load_data[23:16]) |
  ({8{load_half_select[2]}} & cpu_load_data[31:24]) | {8{load_middle_sign}};
 assign extended[31:16]=
  ({16{load_word_passthrough}} & cpu_load_data[31:16]) | {16{load_upper_sign}};
 assign load_live=command_inst[6:0]==3;assign store_live=command_inst[6:0]==7'h23;
 // In the integrated precompute mode command_a already carries memory EA.
 // DIV/CSR/custom operations continue to consume their unmodified raw operand.
 assign live_address=PRECOMPUTED_MEMORY_ADDRESS?command_a:(command_a+imm_live);
 wire live_unaligned=(command_inst[13:12]==1 && live_address[0]) ||
  (command_inst[13:12]==2 && |live_address[1:0]);
 assign selected_unaligned=state==IDLE?live_unaligned:unaligned;
 assign selected_f3=state==IDLE?command_inst[14:12]:inst_r[14:12];
 wire [31:0] live_extended=extended;
 assign bypass=accept && (((load_live || store_live) && (live_unaligned || mem_ready)) ||
  is_csr || command_inst==32'h30200073 || command_inst==32'h10500073 || (command_inst[6:0]==7'h0f && drain_done));
 // A delayed Load already has a stable instruction/address identity. Return
 // its real completion immediately; the sequential block still captures the
 // same payload into RESPONSE if the ROB cannot consume it this cycle.
 // Stores and control operations retain their original completion protocol.
 // held_rsp_target already captured command_pc+4 on accept; reuse it for RUN
 // and RESPONSE, avoiding another retained PC and address adder.
 assign load_run_bypass=state==RUN && load_held &&
  (unaligned || (mem_valid && mem_ready));
 // Select payload by registered owner state and opcode. Completion only
 // validates it; invalid-cycle data is allowed to follow the live inputs.
 assign raw_rsp_result=state==IDLE?(is_csr?csr_data:load_live?live_extended:32'd0):
  (state==RUN && load_held)?extended:held_rsp_result;
 // Valid is the completion event. These fields are payload, just like
 // rsp_result: choose them by registered owner state, not memory ready.
 wire response_idle=state==IDLE;
 wire response_run_load=state==RUN && load_held;
 assign raw_rsp_fault=response_idle?((load_live || store_live) && (live_unaligned || mem_fault)):
  response_run_load?(unaligned || mem_fault):held_rsp_fault;
 assign raw_rsp_cause=response_idle?(live_unaligned?(load_live?4:6):(load_live?5:7)):
  response_run_load?(unaligned?32'd4:32'd5):held_rsp_cause;
 assign raw_rsp_tval=response_idle?live_address:response_run_load?a_r:held_rsp_tval;
 assign raw_rsp_restart=response_idle?(command_inst==32'h30200073):response_run_load?1'b0:held_rsp_restart;
 assign raw_rsp_target=response_idle?(command_inst==32'h30200073 ? mepc:command_pc+4):held_rsp_target;
 // Completion pulses are captured even when global enable is low.
 // Response payload then remains stable until consumed.
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;inst_r<=0;pc_r<=0;a_r<=0;b_r<=0;
   held_rsp_result<=0;held_rsp_fault<=0;held_rsp_cause<=0;held_rsp_tval<=0;held_rsp_restart<=0;held_rsp_target<=0;
  end else begin
   if(accept)begin
    inst_r<=command_inst;pc_r<=command_pc;a_r<=live_address;b_r<=command_b;state<=RUN;
    held_rsp_result<=0;held_rsp_fault<=0;held_rsp_cause<=0;held_rsp_tval<=0;held_rsp_restart<=0;held_rsp_target<=command_pc+4;
    if(bypass)begin
     if(REGISTER_RESPONSE)begin
      held_rsp_result<=raw_rsp_result;held_rsp_fault<=raw_rsp_fault;
      held_rsp_cause<=raw_rsp_cause;held_rsp_tval<=raw_rsp_tval;
      held_rsp_restart<=raw_rsp_restart;held_rsp_target<=raw_rsp_target;
      state<=(PIPE_LOAD_CAPTURE && load_live && !live_unaligned)?LOAD_CAPTURE:RESPONSE;
     end else state<=IDLE;
    end
   end
   if(state==RUN)begin
    // Invalid response data may change while a load is waiting. Capture the
    // current value each cycle and hold it after completion in RESPONSE;
    // ready still solely determines completion, fault and state transition.
    if(LOCAL_LOAD_PAYLOAD && !PIPE_LOAD_CAPTURE && load_held)held_rsp_result<=extended;
    if((div_held && div_done)||(clmul_held && clmul_done))begin
     held_rsp_result<=div_held?div_result:clmul_result;state<=RESPONSE;
    end else if(load_held || store_held)begin
     if(unaligned || (mem_valid && mem_ready))begin
      held_rsp_fault<=unaligned || mem_fault;held_rsp_cause<=unaligned?(load_held?4:6):(load_held?5:7);
      held_rsp_tval<=address;
      if(!LOCAL_LOAD_PAYLOAD)held_rsp_result<=load_held?extended:0;
      state<=(PIPE_LOAD_CAPTURE && load_held && !unaligned)?LOAD_CAPTURE:RESPONSE;
     end
    end else if(inst_r[6:0]==7'h0f && drain_done)state<=RESPONSE;
   end
   if(state==LOAD_CAPTURE)begin
    held_rsp_result<=extended;state<=RESPONSE;
   end
   if(rsp_valid && rsp_ready)state<=IDLE;
  end
 end
endmodule

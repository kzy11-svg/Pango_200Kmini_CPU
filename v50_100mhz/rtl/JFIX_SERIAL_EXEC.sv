// Original JFIX arithmetic/CSR/custom blocks behind a head-only transaction.
module JFIX_SERIAL_EXEC(
 input clk,rst,enable, input req_valid,output req_ready,
 input [31:0] req_inst,req_pc,req_a,req_b,
 output rsp_valid,input rsp_ready,output wire [31:0] rsp_result,
 output wire rsp_fault,output wire [31:0] rsp_cause,rsp_tval,
 output wire rsp_restart,output wire [31:0] rsp_target,
 output mem_valid,input mem_ready,output [31:0] mem_addr,mem_data,
 output [3:0] mem_mask,output mem_read,
 input [31:0] mem_result,input mem_fault,input drain_done,
 input timer_irq,software_irq,external_irq,
 input trap_valid,input [31:0] trap_pc,trap_cause,trap_tval,
 input [1:0] retire_count,
 output irq_valid,output [31:0] irq_cause,output [31:0] trap_vector
);
 wire bypass,selected_unaligned,load_live,store_live;
 wire [31:0] live_address;wire [2:0] selected_f3;
 localparam IDLE=0,RUN=1,RESPONSE=2;
 reg [1:0] state;reg [31:0] inst_r,pc_r,a_r,b_r;
 wire accept=req_valid && req_ready;
 assign req_ready=state==IDLE && enable;
 assign rsp_valid=state==RESPONSE || bypass;
 wire [4:0] op_live,op_r;wire [31:0] imm_live,imm_r;
 wire [4:0] z0,z1,rd0,rs10,rs20,rd1,rs11,rs21;
 wire [1:0] kind0,kind1;wire u10,u20,w0,sp0,si0,ill0,ec0,eb0;
 wire u11,u21,w1,sp1,si1,ill1,ec1,eb1;
 JFIX_OOO_DECODE live(.inst(req_inst),.rs1(rs10),.rs2(rs20),.rd(rd0),.use1(u10),.use2(u20),
  .write_rd(w0),.op(op_live),.zop(z0),.imm(imm_live),.src_pc(sp0),.src_imm(si0),.kind(kind0),
  .illegal(ill0),.ecall(ec0),.ebreak(eb0));
 JFIX_OOO_DECODE held(.inst(inst_r),.rs1(rs11),.rs2(rs21),.rd(rd1),.use1(u11),.use2(u21),
  .write_rd(w1),.op(op_r),.zop(z1),.imm(imm_r),.src_pc(sp1),.src_imm(si1),.kind(kind1),
  .illegal(ill1),.ecall(ec1),.ebreak(eb1));
 wire div_live=req_inst[6:0]==7'h33 && req_inst[31:25]==1 && req_inst[14];
 wire crc_live=req_inst[6:0]==7'h0b && req_inst[14:12]==0;
 wire matrix_live=req_inst[6:0]==7'h0b && req_inst[14:12]!=0;
 wire div_held=inst_r[6:0]==7'h33 && inst_r[31:25]==1 && inst_r[14];
 wire crc_held=inst_r[6:0]==7'h0b && inst_r[14:12]==0;
 wire matrix_held=inst_r[6:0]==7'h0b && inst_r[14:12]!=0;
 // MUL-family operations belong exclusively to the two OoO MUL_PIPE lanes.
 wire div_busy,div_done,crc_busy,crc_done,matrix_busy,matrix_done;
 wire [31:0] div_result,crc_result,matrix_result;
 DIV_UNIT div(.clk(clk),.rst(rst),.start(accept && div_live),.op(op_live),
  .src0(req_a),.src1(req_b),.busy(div_busy),.done(div_done),.result(div_result));
 CRC_UNIT crc(.clk(clk),.rst(rst),.start(accept && crc_live),
  .src0(req_a[15:0]),.src1(req_b[15:0]),.busy(crc_busy),.done(crc_done),.result(crc_result));
 MATRIX_UNIT matrix(.clk(clk),.rst(rst),.start(accept && matrix_live),
  .run_op(req_inst[14:12]==2),.src0(req_a),.src1(req_b),
  .busy(matrix_busy),.done(matrix_done),.result(matrix_result));
 wire [31:0] csr_data,mtvec,mepc;wire unused_mie,unused_mtie;
 wire is_csr=req_inst[6:0]==7'h73 && req_inst[14:12]!=0;
 wire csr_write=is_csr && (req_inst[13:12]==1 || req_inst[19:15]!=0);
 wire [31:0] csr_operand=req_inst[14]?{27'b0,req_inst[19:15]}:req_a;
 wire [31:0] csr_new=req_inst[13:12]==1?csr_operand:
  req_inst[13:12]==2?(csr_data|csr_operand):(csr_data&~csr_operand);
 CSR csr(.clk(clk),.rst(rst),.csr_we_ex(accept && csr_write),
  .csr_addr_ex(req_inst[31:20]),.csr_wd_ex(csr_new),.csr_rd_ex(csr_data),
  .trap_taken(trap_valid),.trap_pc(trap_pc),.trap_cause(trap_cause),.trap_tval(trap_tval),
  .timer_irq(timer_irq),.software_irq(software_irq),.external_irq(external_irq),
  .retire(retire_count),.mret_taken(accept && req_inst==32'h30200073),
  .mtvec_o(mtvec),.mepc_o(mepc),.mstatus_mie_o(unused_mie),.mie_mtie_o(unused_mtie),
  .irq_enabled(irq_valid),.irq_cause(irq_cause));
 assign trap_vector=(mtvec&32'hfffffffc)+
  ((mtvec[1:0]==1 && trap_cause[31])?{trap_cause[29:0],2'b00}:32'd0);
 wire load_held=inst_r[6:0]==3,store_held=inst_r[6:0]==7'h23;
 wire [31:0] address=a_r+imm_r;
 wire unaligned=(inst_r[13:12]==1 && address[0]) ||
  (inst_r[13:12]==2 && |address[1:0]);
 assign mem_valid=(state==IDLE?accept && (load_live || store_live):state==RUN && (load_held || store_held)) && !selected_unaligned;
 assign mem_read=state==IDLE?load_live:load_held;
 assign mem_addr=state==IDLE?live_address:address;
 assign mem_mask=mem_read?0:selected_f3[1:0]==0?(4'b0001<<mem_addr[1:0]):
  selected_f3[1:0]==1?(4'b0011<<mem_addr[1:0]):4'b1111;
 assign mem_data=(state==IDLE?req_b:b_r) << (8*mem_addr[1:0]);
 wire [31:0] shifted=mem_result>>(8*address[1:0]);
 wire [31:0] extended=inst_r[14:12]==0?{{24{shifted[7]}},shifted[7:0]}:
  inst_r[14:12]==1?{{16{shifted[15]}},shifted[15:0]}:
  inst_r[14:12]==4?{24'b0,shifted[7:0]}:
  inst_r[14:12]==5?{16'b0,shifted[15:0]}:mem_result;
 reg [31:0] held_rsp_result,held_rsp_cause,held_rsp_tval,held_rsp_target;
 reg held_rsp_fault,held_rsp_restart;
 assign load_live=req_inst[6:0]==3;assign store_live=req_inst[6:0]==7'h23;
 assign live_address=req_a+imm_live;
 wire live_unaligned=(req_inst[13:12]==1 && live_address[0]) ||
  (req_inst[13:12]==2 && |live_address[1:0]);
 assign selected_unaligned=state==IDLE?live_unaligned:unaligned;
 assign selected_f3=state==IDLE?req_inst[14:12]:inst_r[14:12];
 wire [31:0] live_shifted=mem_result>>(8*live_address[1:0]);
 wire [31:0] live_extended=req_inst[14:12]==0?{{24{live_shifted[7]}},live_shifted[7:0]}:
  req_inst[14:12]==1?{{16{live_shifted[15]}},live_shifted[15:0]}:
  req_inst[14:12]==4?{24'b0,live_shifted[7:0]}:
  req_inst[14:12]==5?{16'b0,live_shifted[15:0]}:mem_result;
 assign bypass=accept && (((load_live || store_live) && (live_unaligned || mem_ready)) ||
  is_csr || req_inst==32'h30200073 || req_inst==32'h10500073 || (req_inst[6:0]==7'h0f && drain_done));
 assign rsp_result=bypass?(is_csr?csr_data:load_live?live_extended:32'd0):held_rsp_result;
 assign rsp_fault=bypass?((load_live || store_live) && (live_unaligned || mem_fault)):held_rsp_fault;
 assign rsp_cause=bypass?(live_unaligned?(load_live?4:6):(load_live?5:7)):held_rsp_cause;
 assign rsp_tval=bypass?live_address:held_rsp_tval;
 assign rsp_restart=bypass?(req_inst==32'h30200073):held_rsp_restart;
 assign rsp_target=bypass?(req_inst==32'h30200073 ? mepc:req_pc+4):held_rsp_target;
 // Completion pulses are captured even when global enable is low.
 // Response payload then remains stable until consumed.
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;inst_r<=0;pc_r<=0;a_r<=0;b_r<=0;
   held_rsp_result<=0;held_rsp_fault<=0;held_rsp_cause<=0;held_rsp_tval<=0;held_rsp_restart<=0;held_rsp_target<=0;
  end else begin
   if(accept)begin
    inst_r<=req_inst;pc_r<=req_pc;a_r<=req_a;b_r<=req_b;state<=RUN;
    held_rsp_result<=0;held_rsp_fault<=0;held_rsp_cause<=0;held_rsp_tval<=0;held_rsp_restart<=0;held_rsp_target<=req_pc+4;
    if(bypass)state<=IDLE;
   end
   if(state==RUN)begin
    if((div_held && div_done)||(crc_held && crc_done)||(matrix_held && matrix_done))begin
     held_rsp_result<=div_held?div_result:crc_held?crc_result:matrix_result;state<=RESPONSE;
    end else if(load_held || store_held)begin
     if(unaligned || (mem_valid && mem_ready))begin
      held_rsp_fault<=unaligned || mem_fault;held_rsp_cause<=unaligned?(load_held?4:6):(load_held?5:7);
      held_rsp_tval<=address;held_rsp_result<=load_held?extended:0;state<=RESPONSE;
     end
    end else if(inst_r[6:0]==7'h0f && drain_done)state<=RESPONSE;
   end
   if(rsp_valid && rsp_ready)state<=IDLE;
  end
 end
endmodule

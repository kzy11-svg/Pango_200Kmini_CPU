// Dual synchronous instruction scratchpad. The resident program is immutable;
// no cache refill protocol is needed for this on-chip ROM configuration.
module JFIX_FETCH_PAIR(
 input clk,rst,input [31:0] pc,input ready,redirect,input [31:0] redirect_pc,
 output valid,output [63:0] instructions,output [1:0] faults,pred_taken,
 output [63:0] pred_target,
 input branch_commit,input [31:0] branch_pc,branch_inst,branch_target
);
 wire [1:0] bpu_taken,ras_valid;
 wire [31:0] query_pc[0:1],bpu_target[0:1],ras_top[0:1];
 wire [4:0] histories[0:1];
 assign query_pc[0]=pc;assign query_pc[1]=pc+4;
 wire consume=valid && ready && !redirect;
 wire [31:0] next_pc=redirect?redirect_pc:pred_taken[0]?pred_target[31:0]:
  pred_taken[1]?pred_target[63:32]:pc+8;
 wire [31:0] rom_pc=redirect?redirect_pc:consume?next_pc:pc;
 reg [31:0] response_pc;
 reg response_valid;
 always @(posedge clk) begin
  if(rst) response_valid<=0;
  else response_valid<=1;
  response_pc<=rom_pc;
 end
 wire call_hint=(branch_inst[6:0]==7'h6f || branch_inst[6:0]==7'h67) &&
  (branch_inst[11:7]==1 || branch_inst[11:7]==5);
 wire return_hint=branch_inst[6:0]==7'h67 && (branch_inst[19:15]==1 || branch_inst[19:15]==5) &&
  (!call_hint || branch_inst[19:15]!=branch_inst[11:7]);
 genvar g;
 generate for(g=0;g<2;g=g+1)begin:port
  wire [31:0] rom_word_pc=rom_pc+4*g;
  wire [13:0] rom_addr=rom_word_pc[15:2];
  wire range_fault=query_pc[g]<32'h80000000 || query_pc[g]>=32'h80010000 || |query_pc[g][1:0];
  INST_MEM rom(.clka(clk),.addra(rom_addr),.douta(instructions[g*32+:32]));
  assign faults[g]=range_fault;
  BPU predictor(.clk(clk),.rst(rst),.pc_if(query_pc[g]),.pc_add4_if(query_pc[g]+4),
   .pred_taken(bpu_taken[g]),.pred_target(bpu_target[g]),.ghr_if_out(histories[g]),
   .ras_push(branch_commit && call_hint),.ras_pop(branch_commit && return_hint),.ras_push_addr(branch_pc+4),
   .ras_valid(ras_valid[g]),.ras_top(ras_top[g]),
   .jalr_update_en(branch_commit && (branch_inst[6:0]==7'h67 || branch_inst[6:0]==7'h6f)),
   .update_en(branch_commit && branch_inst[6:0]==7'h63),.mispredict_ex_r(redirect),
   .pc_ex(branch_pc),.actual_taken(branch_target!=branch_pc+4),.actual_target(branch_target),.ghr_ex_in(5'b0));
  wire [31:0] ins=instructions[g*32+:32];
  wire is_control=ins[6:0]==7'h63 || ins[6:0]==7'h67 || ins[6:0]==7'h6f;
  wire predict_return=ins[6:0]==7'h67 && ins[14:12]==0 &&
   (ins[19:15]==1 || ins[19:15]==5) && !(ins[11:7]==1 || ins[11:7]==5) && ins[31:20]==0;
  assign pred_taken[g]=!faults[g] && is_control &&
   ((predict_return && ras_valid[g]) || bpu_taken[g]);
  assign pred_target[g*32+:32]=predict_return && ras_valid[g]?ras_top[g]:bpu_target[g];
 end endgenerate
 assign valid=response_valid && response_pc==pc;
endmodule

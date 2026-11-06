// Independently authored decode around the original JFIX execution opcodes.
module JFIX_OOO_DECODE(
 input [31:0] inst,
 output [4:0] rs1,rs2,rd, output reg use1,use2,write_rd,
 output [4:0] op,zop, output [31:0] imm,
 output src_pc,src_imm, output reg [1:0] kind,
 output illegal, output ecall,ebreak
);
 wire unused_we, unused_csr_we,unused_ecall,unused_mret;
 wire [3:0] unused_acc,unused_br;
 wire [2:0] unused_sel,unused_csr_op;
 wire [11:0] unused_csr;
 wire base_illegal;
 DECODER original_decoder(.inst(inst),.alu_op(op),.imm(imm),
  .rf_ra0(rs1),.rf_ra1(rs2),.rf_wa(rd),.rf_we(unused_we),
  .rf_wd_sel(unused_sel),.dmem_access(unused_acc),.br_type(unused_br),
  .alu_src0_sel(src_pc),.alu_src1_sel(src_imm),.csr_addr(unused_csr),
  .csr_we(unused_csr_we),.csr_op(unused_csr_op),
  .is_ecall(unused_ecall),.is_mret(unused_mret));
 ZBB_DECODE halfword_decoder(.inst(inst),.zbb_op(zop));
 TRAP_DECODE legality(.inst(inst),.illegal(base_illegal),.ecall(ecall),.ebreak(ebreak));
 // Exact sext.h/zext.h plus the three standard Zbc encodings are supported.
 wire clmul=inst[6:0]==7'h33 && inst[31:25]==7'h05 &&
  (inst[14:12]==1 || inst[14:12]==2 || inst[14:12]==3);
 assign illegal=base_illegal && zop==0 && !clmul;
 always @* begin
  use1=0;use2=0;write_rd=0;kind=2; // serial/exception by default
  case(inst[6:0])
   7'h37,7'h17:begin write_rd=1;kind=0;end
   7'h13:begin use1=1;write_rd=1;kind=0;end
   7'h33:begin use1=1;use2=(zop==0);write_rd=1;
    kind=clmul?0:(inst[31:25]==1)?(inst[14]?2:3):0;end
   7'h63:begin use1=1;use2=1;kind=1;end
   7'h6f:begin write_rd=1;kind=1;end
   7'h67:begin use1=1;write_rd=1;kind=1;end
   7'h03:begin use1=1;write_rd=1;end
   7'h23:begin use1=1;use2=1;end
   7'h73:if(inst[14:12]!=0)begin
    use1=!inst[14];write_rd=1;
   end
   default:begin end
  endcase
  write_rd=write_rd && rd!=0;
 end
endmodule

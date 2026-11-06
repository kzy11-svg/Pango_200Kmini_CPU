// Parallel legality terms for exactly the existing RV32IM/Zicsr/custom ISA.
module TRAP_DECODE(input [31:0] inst,output wire illegal,ebreak,ecall);
 wire [6:0] op=inst[6:0],f7=inst[31:25];
 wire [2:0] f3=inst[14:12];wire [11:0] ca=inst[31:20];
 wire csr_write=(f3==1 || f3==5) || inst[19:15]!=0;
 // Exact existing address sets: 300..306,340..344,b00/b02/b80/b82,
 // c00/c02/c80/c82,f11..f14. No CSR is newly admitted.
 wire csr_exists=(ca[11:3]==9'h060 && ca[2:0]!=7) ||
  (ca[11:3]==9'h068 && ca[2:0]<=4) ||
  ((ca[11:8]==4'hb || ca[11:8]==4'hc) && ca[6:2]==0 && !ca[0]) ||
  (ca[11:4]==8'hf1 && ca[3:0]>=1 && ca[3:0]<=4);
 assign ecall=inst==32'h00000073;
 assign ebreak=inst==32'h00100073;
 wire system_legal=(f3==0 && (ecall || ebreak || inst==32'h30200073 || inst==32'h10500073)) ||
  (f3!=0 && f3!=4 && csr_exists && !(ca[11:10]==3 && csr_write));
 wire legal=(op==7'h37 || op==7'h17 || op==7'h6f) ||
  (op==7'h67 && f3==0) ||
  (op==7'h63 && (f3==0 || f3==1 || f3>=4)) ||
  (op==7'h03 && (f3<=2 || f3==4 || f3==5)) ||
  (op==7'h23 && f3<=2) ||
  (op==7'h13 && ((f3!=1 && f3!=5) || (f3==1 && f7==0) || (f3==5 && (f7==0 || f7==7'h20)))) ||
  (op==7'h33 && (f7==0 || f7==1 || (f7==7'h20 && (f3==0 || f3==5)))) ||
  (op==7'h0f && f3==0) || (op==7'h73 && system_legal);
 assign illegal=!legal;
endmodule

// Exact legality of the supported RV32IM/Zicsr + custom-0 encodings.
module TRAP_DECODE(input [31:0] inst,output reg illegal,ebreak,ecall);
 wire [6:0] op=inst[6:0],f7=inst[31:25];
 wire [2:0] f3=inst[14:12];
 wire [11:0] ca=inst[31:20];
 reg legal,csr_exists;
 wire csr_write=(f3==1 || f3==5) || (inst[19:15]!=0);
 always @* begin
  case(ca)
   12'h300,12'h301,12'h302,12'h303,12'h304,12'h305,12'h306,
   12'h340,12'h341,12'h342,12'h343,12'h344,
   12'hb00,12'hb80,12'hb02,12'hb82,
   12'hc00,12'hc80,12'hc02,12'hc82,
   12'hf11,12'hf12,12'hf13,12'hf14:csr_exists=1;
   default:csr_exists=0;
  endcase
  legal=0;ebreak=0;ecall=0;
  case(op)
   7'h37,7'h17,7'h6f:legal=1;
   7'h67:legal=f3==0;
   7'h63:legal=(f3==0 || f3==1 || f3>=4);
   7'h03:legal=(f3<=2 || f3==4 || f3==5);
   7'h23:legal=f3<=2;
   7'h13:legal=(f3!=1 && f3!=5) || (f3==1 && f7==0) || (f3==5 && (f7==0 || f7==7'h20));
   7'h33:legal=f7==0 || f7==1 || (f7==7'h20 && (f3==0 || f3==5));
   7'h0b:legal=f7==0 && f3<=2;
   // FENCE supported; no Zifencei declaration. FENCE.I traps as unsupported.
   7'h0f:legal=f3==0;
   7'h73:begin
    if(f3==0)begin
     ecall=inst==32'h00000073;ebreak=inst==32'h00100073;
     legal=ecall || ebreak || inst==32'h30200073 || inst==32'h10500073; // WFI legal NOP
    end else if(f3!=4)
     legal=csr_exists && !(ca[11:10]==2'b11 && csr_write);
   end
  endcase
  illegal=!legal;
 end
endmodule

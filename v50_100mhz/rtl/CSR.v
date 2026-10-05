`timescale 1ns/1ps
// RV32 M-only CSR bank. Lower privilege modes and PMP are not implemented.
module CSR(
 input clk,rst,csr_we_ex,
 input [11:0] csr_addr_ex,
 input [31:0] csr_wd_ex,
 output reg [31:0] csr_rd_ex,
 input trap_taken,
 input [31:0] trap_pc,trap_cause,trap_tval,
 input timer_irq,software_irq,external_irq,
 input [1:0] retire,
 input mret_taken,
 output [31:0] mtvec_o,mepc_o,
 output mstatus_mie_o,mie_mtie_o,
 output irq_enabled,
 output [31:0] irq_cause
);
 reg [31:0] mstatus_reg,mie_reg,mtvec_reg,mscratch_reg,mepc_reg,mcause_reg,mtval_reg;
 reg [63:0] mcycle_reg,minstret_reg;
 wire [31:0] mip_val={20'b0,external_irq,3'b0,timer_irq,3'b0,software_irq,3'b0};
 wire [31:0] eligible=mip_val&mie_reg;
 assign irq_enabled=mstatus_reg[3] && |(eligible & 32'h888);
 assign irq_cause=eligible[11]?32'h8000000b:eligible[3]?32'h80000003:32'h80000007;
 assign mtvec_o=mtvec_reg;
 assign mepc_o=mepc_reg;
 assign mstatus_mie_o=mstatus_reg[3];
 assign mie_mtie_o=mie_reg[7];
 always @* begin
  case(csr_addr_ex)
   12'h300:csr_rd_ex=mstatus_reg;
   12'h301:csr_rd_ex=32'h40801100; // RV32IM, non-standard custom extension X
   12'h304:csr_rd_ex=mie_reg;
   12'h305:csr_rd_ex=mtvec_reg;
   12'h340:csr_rd_ex=mscratch_reg;
   12'h341:csr_rd_ex=mepc_reg;
   12'h342:csr_rd_ex=mcause_reg;
   12'h343:csr_rd_ex=mtval_reg;
   12'h344:csr_rd_ex=mip_val;
   12'hb00:csr_rd_ex=mcycle_reg[31:0];
   12'hb80:csr_rd_ex=mcycle_reg[63:32];
   12'hb02:csr_rd_ex=minstret_reg[31:0];
   12'hb82:csr_rd_ex=minstret_reg[63:32];
   12'hc00:csr_rd_ex=mcycle_reg[31:0];
   12'hc80:csr_rd_ex=mcycle_reg[63:32];
   12'hc02:csr_rd_ex=minstret_reg[31:0];
   12'hc82:csr_rd_ex=minstret_reg[63:32];
   // Identity and M-only delegation/counter-enable WARL registers read zero.
   default:csr_rd_ex=0;
  endcase
 end
 always @(posedge clk) begin
  if(rst) begin
   mstatus_reg<=32'h1800;mie_reg<=0;mtvec_reg<=0;mscratch_reg<=0;
   mepc_reg<=0;mcause_reg<=0;mtval_reg<=0;mcycle_reg<=0;minstret_reg<=0;
  end else begin
   if(!(csr_we_ex && !trap_taken && !mret_taken && (csr_addr_ex==12'hb00 || csr_addr_ex==12'hb80)))
     mcycle_reg<=mcycle_reg+1'b1;
   if(retire && !(csr_we_ex && !trap_taken && !mret_taken && (csr_addr_ex==12'hb02 || csr_addr_ex==12'hb82)))
     minstret_reg<=minstret_reg+retire;
   if(trap_taken) begin
    mepc_reg<={trap_pc[31:2],2'b0};mcause_reg<=trap_cause;mtval_reg<=trap_tval;
    mstatus_reg[7]<=mstatus_reg[3];mstatus_reg[3]<=0;
   end else if(mret_taken) begin
    mstatus_reg[3]<=mstatus_reg[7];mstatus_reg[7]<=1;
   end else if(csr_we_ex) begin
    case(csr_addr_ex)
     12'h300:begin mstatus_reg[3]<=csr_wd_ex[3];mstatus_reg[7]<=csr_wd_ex[7];end
     12'h304:mie_reg<=csr_wd_ex & 32'h888;
     12'h305:mtvec_reg<={csr_wd_ex[31:2],(csr_wd_ex[1:0]==1)?2'b01:2'b00};
     12'h340:mscratch_reg<=csr_wd_ex;
     12'h341:mepc_reg<={csr_wd_ex[31:2],2'b0};
     12'h342:mcause_reg<=csr_wd_ex;
     12'h343:mtval_reg<=csr_wd_ex;
     12'hb00:mcycle_reg[31:0]<=csr_wd_ex;
     12'hb80:mcycle_reg[63:32]<=csr_wd_ex;
     12'hb02:minstret_reg[31:0]<=csr_wd_ex;
     12'hb82:minstret_reg[63:32]<=csr_wd_ex;
    endcase
   end
  end
 end
endmodule

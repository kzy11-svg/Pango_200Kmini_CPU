// JFIX platform shell with the independently authored out-of-order core.
module CPU_top #(
 parameter P_SW_CNT=64,P_LED_CNT=32,P_SEG_CNT=40,P_KEY_CNT=8
)(input clk,cnt_clk,rst,global_en,
 input [P_KEY_CNT-1:0] virtual_key,input [P_SW_CNT-1:0] virtual_sw,
 output [P_LED_CNT-1:0] virtual_led,output [P_SEG_CNT-1:0] virtual_seg,
 input uart_tx_busy,output uart_tx_req,output [7:0] uart_tx_data,
 input [7:0] uart_rx_data,input uart_rx_empty,uart_rx_full,uart_rx_overflow,
 input [4:0] uart_rx_count,output uart_rx_pop,inout dht11_io);
 wire [31:0] fetch_pc,redirect_pc;wire fetch_valid,fetch_ready,redirect;
 wire [63:0] fetch_inst,pred_target;wire [1:0] fetch_fault,pred_taken;
 wire branch_commit;wire [31:0] branch_pc,branch_inst,branch_target;
 wire sv,sready,rv,rr,rf,srestart;wire [31:0] si,sp,sa,sb,sres,sc,st,starget;
 wire mv,mready,mread,mfault;wire [31:0] ma,md,mresult;wire [3:0] mm;
 wire irqv;wire [31:0] irqc,tvec;wire tv;wire [31:0] tp,tc,tt;
 wire [1:0] rc,rw,ic;wire [63:0] rp,ri,rd;wire [9:0] rdest;wire [4:0] occ;
 wire timer_irq,software_irq,external_irq,drain_done;
 // Interrupt sources cross a CPU-clock boundary before CSR eligibility.
 // MIE/mstatus checks remain current-cycle CSR logic, so masking is immediate.
 reg timer_irq_sample,software_irq_sample,external_irq_sample;
 always @(posedge clk) begin
  if(rst) begin timer_irq_sample<=0;software_irq_sample<=0;external_irq_sample<=0;end
  else begin timer_irq_sample<=timer_irq;software_irq_sample<=software_irq;external_irq_sample<=external_irq;end
 end
 JFIX_OOO_CORE core(.clk(clk),.rst(rst),.enable(global_en),.fetch_pc(fetch_pc),
  .fetch_valid(fetch_valid),.fetch_inst(fetch_inst),.fetch_fault(fetch_fault),
  .fetch_pred_taken(pred_taken),.fetch_pred_target(pred_target),
  .fetch_ready(fetch_ready),.redirect(redirect),.redirect_pc(redirect_pc),
  .branch_commit(branch_commit),.branch_pc(branch_pc),.branch_inst(branch_inst),.branch_target(branch_target),
  .serial_valid(sv),.serial_ready(sready),.serial_inst(si),.serial_pc(sp),.serial_src0(sa),.serial_src1(sb),
  .serial_rsp_valid(rv),.serial_rsp_ready(rr),.serial_result(sres),.serial_fault(rf),
  .serial_cause(sc),.serial_tval(st),.serial_restart(srestart),.serial_target(starget),
  .irq_valid(irqv),.irq_cause(irqc),.trap_vector(tvec),.trap_valid(tv),.trap_pc(tp),.trap_cause(tc),.trap_tval(tt),
  .retire_count(rc),.retire_pc(rp),.retire_inst(ri),.retire_data(rd),.retire_rd(rdest),.retire_write(rw),
  .issue_count(ic),.rob_occupancy(occ));
 JFIX_FETCH_PAIR frontend(.clk(clk),.rst(rst),.pc(fetch_pc),.ready(fetch_ready),.redirect(redirect),.redirect_pc(redirect_pc),
  .valid(fetch_valid),.instructions(fetch_inst),.faults(fetch_fault),.pred_taken(pred_taken),.pred_target(pred_target),
  .branch_commit(branch_commit),.branch_pc(branch_pc),.branch_inst(branch_inst),.branch_target(branch_target));
 JFIX_SERIAL_EXEC serial(.clk(clk),.rst(rst),.enable(global_en),.req_valid(sv),.req_ready(sready),
  .req_inst(si),.req_pc(sp),.req_a(sa),.req_b(sb),.rsp_valid(rv),.rsp_ready(rr),
  .rsp_result(sres),.rsp_fault(rf),.rsp_cause(sc),.rsp_tval(st),.rsp_restart(srestart),.rsp_target(starget),
  .mem_valid(mv),.mem_ready(mready),.mem_addr(ma),.mem_data(md),.mem_mask(mm),.mem_read(mread),
  .mem_result(mresult),.mem_fault(mfault),.drain_done(drain_done),
  .timer_irq(timer_irq_sample),.software_irq(software_irq_sample),.external_irq(external_irq_sample),
  .trap_valid(tv),.trap_pc(tp),.trap_cause(tc),.trap_tval(tt),.retire_count(rc),
  .irq_valid(irqv),.irq_cause(irqc),.trap_vector(tvec));

 wire dram_select=ma[31:18]==14'h2004;
 wire mmio_select=ma[31:8]==24'h802000;
 wire fault,cache_stall,wb_empty,refill_busy,fault_write;
 wire [31:0] fault_address,cache_data,periph_data,periph_seg,periph_led;
 wire tx_wait=mmio_select && !mread && ma[7:2]==6'h18 && mm[0] && uart_tx_busy;
 assign mfault=(!dram_select && !mmio_select) || (dram_select && fault);
 assign mready=mv && (dram_select?(!cache_stall || fault):!tx_wait);
 assign mresult=mmio_select?periph_data:cache_data;
 assign drain_done=wb_empty && !refill_busy;
 wire [31:0] araddr,rdata,awaddr,wdata;wire [7:0] arlen,awlen;
 wire [2:0] arsize,awsize;wire [1:0] arburst,rresp,awburst,bresp;
 wire arvalid,arready,rvalid,rlast,rready,awvalid,awready,wvalid,wlast,wready,bvalid,bready;
 wire [3:0] wstrb;
 wire local_req,local_ready,local_error;wire [31:0] local_addr,local_data;wire [3:0] local_mask;
 wire [15:0] ram_addr;wire [31:0] ram_wdata,ram_data;wire [3:0] ram_wea;
 DCACHE #(.INDEX_BITS(7),.PRECISE_STORES(1),.LOCAL_WRITE_ACK(1)) dcache(
  .clk(clk),.rst(rst),.cpu_req(mv && dram_select),.cpu_read(mread),.cpu_advance(mv && mready),
  .clear_fault(tv),.drain(!mv),.wb_empty(wb_empty),.fault_valid(fault),.fault_write(fault_write),
  .fault_address(fault_address),.refill_busy(refill_busy),.cpu_addr(ma[17:2]),
  .cpu_wdata(md),.cpu_wea(mm),.cpu_rdata(cache_data),.stall(cache_stall),
  .axi_araddr(araddr),.axi_arlen(arlen),.axi_arsize(arsize),.axi_arburst(arburst),
  .axi_arvalid(arvalid),.axi_arready(arready),.axi_rdata(rdata),.axi_rresp(rresp),
  .axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rready(rready),
  .axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awsize(awsize),.axi_awburst(awburst),
  .axi_awvalid(awvalid),.axi_awready(awready),.axi_wdata(wdata),.axi_wstrb(wstrb),
  .axi_wvalid(wvalid),.axi_wlast(wlast),.axi_wready(wready),.axi_bvalid(bvalid),.axi_bresp(bresp),.axi_bready(bready),
  .local_req(local_req),.local_addr(local_addr),.local_data(local_data),.local_mask(local_mask),
  .local_ready(local_ready),.local_error(local_error));
 AXI_RAM_TARGET #(.LOCAL_WRITE_ACK(1)) target(.clk(clk),.rst(rst),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rvalid(rvalid),.rlast(rlast),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wvalid(wvalid),.wlast(wlast),.wready(wready),
  .bvalid(bvalid),.bresp(bresp),.bready(bready),
  .local_req(local_req),.local_addr(local_addr),.local_data(local_data),.local_mask(local_mask),
  .local_ready(local_ready),.local_error(local_error),
  .ram_addr(ram_addr),.ram_wdata(ram_wdata),.ram_wea(ram_wea),.ram_data(ram_data));
 DATA_MEM data_memory(.clka(clk),.addra(ram_addr),.wea(ram_wea),.dina(ram_wdata),.douta(ram_data));
 MMIO_PERIPH periph(.clk(clk),.rst(rst),.cnt_clk(cnt_clk),
  .we(mv && mready && mmio_select && !mread),.re(mv && mready && mmio_select && mread),
  .addr({ma[7:2],2'b00}),.wdata(md),.wstrb(mm),.rdata(periph_data),
  .virtual_sw(virtual_sw),.virtual_key(virtual_key),.virtual_led(periph_led),.virtual_seg(periph_seg),
  .uart_tx_busy(uart_tx_busy),.uart_tx_req(uart_tx_req),.uart_tx_data(uart_tx_data),
  .uart_rx_data(uart_rx_data),.uart_rx_empty(uart_rx_empty),.uart_rx_full(uart_rx_full),
  .uart_rx_overflow(uart_rx_overflow),.uart_rx_count(uart_rx_count),.uart_rx_pop(uart_rx_pop),
  .dht11_io(dht11_io),.timer_irq(timer_irq),.software_irq(software_irq),.external_irq(external_irq));
 assign virtual_led=periph_led;
 display_seg display(.clk(clk),.rst(rst),.s(periph_seg),
  .seg1(virtual_seg[6:0]),.seg2(virtual_seg[16:10]),.seg3(virtual_seg[26:20]),.seg4(virtual_seg[36:30]),
  .ans({virtual_seg[39:38],virtual_seg[29:28],virtual_seg[19:18],virtual_seg[9:8]}));
 assign virtual_seg[7]=virtual_key[0];assign virtual_seg[17]=virtual_key[1];
 assign virtual_seg[27]=virtual_key[2];assign virtual_seg[37]=virtual_key[3];
endmodule

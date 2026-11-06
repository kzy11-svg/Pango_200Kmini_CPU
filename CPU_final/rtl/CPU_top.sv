// JFIX platform shell with the independently authored out-of-order core.
module CPU_top #(
 parameter CORE_ROB_ENTRIES=10, DCACHE_INDEX_BITS=9, GLOBAL_HISTORY_BITS=13, GLOBAL_COUNTER_BITS=3, TOURNAMENT=1, LOCAL_BITS=8, CHOICE_HASH=1,
 parameter P_SW_CNT=64,P_LED_CNT=32,P_SEG_CNT=40,P_KEY_CNT=8
)(input clk,cnt_clk,rst,global_en,
 input [P_KEY_CNT-1:0] virtual_key,input [P_SW_CNT-1:0] virtual_sw,
 output [P_LED_CNT-1:0] virtual_led,output [P_SEG_CNT-1:0] virtual_seg,
 input uart_tx_busy,output uart_tx_req,output [7:0] uart_tx_data,
 input [7:0] uart_rx_data,input uart_rx_empty,uart_rx_full,uart_rx_overflow,
 input [4:0] uart_rx_count,output uart_rx_pop,inout dht11_io);
 wire [23:0] debug_core_event_q;wire [95:0] debug_core_payload_q;
 wire [7:0] debug_fetch_event_q;
 wire [19:0] fetch_way_rs0,fetch_way_rs1;wire [1:0] fetch_way_select,fetch_way_zero;
 wire [5:0] fetch_status;wire [3:0] fetch_directions;wire [1:0] branch_directions;
 wire [12:0] fetch_history,branch_history,recover_history;
 wire [31:0] fetch_pc,redirect_pc;wire fetch_valid,fetch_ready,redirect;
 wire [63:0] fetch_inst /* synthesis syn_maxfan=8 */;wire [63:0] pred_target;wire [1:0] fetch_fault,pred_taken;
 wire branch_commit;wire [31:0] branch_pc,branch_inst,branch_target;
 wire sv,sready,rv,rr,rf,srestart;wire [31:0] si,sp,sa,sb,sres,sc,st,starget;
 wire mv,mready,mready_store,mread,mfault;wire [31:0] ma,md,mresult;wire [3:0] mm;
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
 JFIX_OOO_CORE #(.ROB_ENTRIES(CORE_ROB_ENTRIES),.PRF_ENTRIES(32+CORE_ROB_ENTRIES),.PRECOMPUTE_MEMORY_ADDRESS(1),.RESIDENT_INTEGER_PC(1),.FETCH_PREDECODE(1),.WAY_RENAME(1),.SERIAL_READ_PIPE(0)) core(.clk(clk),.rst(rst),.enable(global_en),.fetch_pc(fetch_pc),
  .fetch_way_rs0(fetch_way_rs0),.fetch_way_rs1(fetch_way_rs1),.fetch_way_select(fetch_way_select),.fetch_way_zero(fetch_way_zero),
  .recover_history(recover_history),.fetch_directions(fetch_directions),.branch_directions(branch_directions),.fetch_history(fetch_history),.branch_history(branch_history),.fetch_status(fetch_status),.fetch_valid(fetch_valid),.fetch_inst(fetch_inst),.fetch_fault(fetch_fault),
  .fetch_pred_taken(pred_taken),.fetch_pred_target(pred_target),
  .fetch_ready(fetch_ready),.redirect(redirect),.redirect_pc(redirect_pc),
  .branch_commit(branch_commit),.branch_pc(branch_pc),.branch_inst(branch_inst),.branch_target(branch_target),
  .serial_valid(sv),.serial_ready(sready),.serial_inst(si),.serial_pc(sp),.serial_src0(sa),.serial_src1(sb),
  .serial_rsp_valid(rv),.serial_rsp_ready(rr),.serial_result(sres),.serial_fault(rf),
  .serial_cause(sc),.serial_tval(st),.serial_restart(srestart),.serial_target(starget),
  .irq_valid(irqv),.irq_cause(irqc),.trap_vector(tvec),.trap_valid(tv),.trap_pc(tp),.trap_cause(tc),.trap_tval(tt),
  .retire_count(rc),.retire_pc(rp),.retire_inst(ri),.retire_data(rd),.retire_rd(rdest),.retire_write(rw),
  .issue_count(ic),.rob_occupancy(occ),.debug_event_q(debug_core_event_q),
  .debug_payload_q(debug_core_payload_q));
 JFIX_FETCH_PAIR #(.GLOBAL_HISTORY_BITS(GLOBAL_HISTORY_BITS),.GLOBAL_COUNTER_BITS(GLOBAL_COUNTER_BITS),.TOURNAMENT(TOURNAMENT),.LOCAL_BITS(LOCAL_BITS),.CHOICE_HASH(CHOICE_HASH)) frontend(.clk(clk),.rst(rst),.pc(fetch_pc),.ready(fetch_ready),.redirect(redirect),.redirect_pc(redirect_pc),
  .fetch_way_rs0(fetch_way_rs0),.fetch_way_rs1(fetch_way_rs1),.fetch_way_select(fetch_way_select),.fetch_way_zero(fetch_way_zero),
  .recover_history(recover_history),.fetch_directions(fetch_directions),.branch_directions(branch_directions),.fetch_history(fetch_history),.branch_history(branch_history),.static_status(fetch_status),.valid(fetch_valid),.instructions(fetch_inst),.faults(fetch_fault),.pred_taken(pred_taken),.pred_target(pred_target),
  .branch_commit(branch_commit),.branch_pc(branch_pc),.branch_inst(branch_inst),.branch_target(branch_target),
  .debug_event_q(debug_fetch_event_q));
 wire mstore;
 wire fault,cache_stall,cache_store_stall,cache_store_offer,cache_store_nonzero_offer,wb_empty,refill_busy,fault_write;
 JFIX_SERIAL_EXEC #(.ZBC_IN_INTEGER(1),.PRECOMPUTED_MEMORY_ADDRESS(1),.REGISTER_RESPONSE(0),.REGISTER_COMMAND(0),.USE_STORE_READY(1),.USE_LOCAL_STATE_READY(1),.ISOLATE_LIST_OBSERVER(1),.LOCAL_LOAD_PAYLOAD(0),.PIPE_LOAD_CAPTURE(0),.DMA_DATA_ALWAYS(1),.EARLY_ORDER_GUARD(1),.LOCAL_BATCH_WRITE_FAULT(1)) serial(.clk(clk),.rst(rst),.enable(global_en),.req_valid(sv),.req_ready(sready),
  .req_inst(si),.req_pc(sp),.req_a(sa),.req_b(sb),.rsp_valid(rv),.rsp_ready(rr),
  .rsp_result(sres),.rsp_fault(rf),.rsp_cause(sc),.rsp_tval(st),.rsp_restart(srestart),.rsp_target(starget),
  .mem_valid(mv),.mem_store_valid(mstore),.mem_ready(mready),.mem_store_ready(mready_store),.dma_store_offer(cache_store_offer),.dma_store_nonzero_offer(cache_store_nonzero_offer),.dma_store_fault(fault),.dma_uart_busy(uart_tx_busy),.mem_addr(ma),.mem_data(md),.mem_mask(mm),.mem_read(mread),
  .mem_result(mresult),.mem_fault(mfault),.drain_done(drain_done),
  .timer_irq(timer_irq_sample),.software_irq(software_irq_sample),.external_irq(external_irq_sample),
  .trap_valid(tv),.trap_pc(tp),.trap_cause(tc),.trap_tval(tt),.retire_count(rc),
  .irq_valid(irqv),.irq_cause(irqc),.trap_vector(tvec));

 wire dram_select=ma[31:18]==14'h2004;
 wire mmio_select=ma[31:8]==24'h802000;

 // DCache housekeeping continues across global CPU pauses.
 reg dcache_clear_fault;
 always @(posedge clk)begin
  if(rst)dcache_clear_fault<=0;
  else dcache_clear_fault<=tv;
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst)begin
  if(mstore!==(mv && !mread))$fatal(1,"CPU Store request separation changed transaction");
  if(mv && !mread && mready!==mready_store)$fatal(1,"Store-ready split changed acceptance");
  if((tv || dcache_clear_fault) && (mv || !wb_empty))
   $fatal(1,"Trap/cache-clear boundary has a CPU request or unfinished WB");
  if(dcache.wb_count>1)$fatal(1,"Precise single-transaction CPU produced more than one WB store");
 end
 // synthesis translate_on
 wire [31:0] fault_address,cache_data,periph_data,periph_seg,periph_led;
 // synthesis translate_off
 always @(posedge clk)if(!rst && mv && mmio_select)
  if(mready !== !tx_wait)$fatal(1,"MMIO local acceptance differs from bus acceptance");
 // synthesis translate_on
 wire tx_wait=mmio_select && !mread && ma[7:2]==6'h18 && mm[0] && uart_tx_busy;
 assign mfault=(!dram_select && !mmio_select) || (dram_select && fault);
 assign mready=mv && (dram_select?(!cache_stall || fault):!tx_wait);
 assign mready_store=dram_select?(cache_store_offer || fault):!tx_wait;
 assign mresult=mmio_select?periph_data:cache_data;
 assign drain_done=wb_empty && !refill_busy;
 wire [31:0] araddr,rdata,awaddr,wdata;wire [7:0] arlen,awlen;
 wire [2:0] arsize,awsize;wire [1:0] arburst,rresp,awburst,bresp;
 wire arvalid,arready,rvalid,rlast,rready,awvalid,awready,wvalid,wlast,wready,bvalid,bready;
 wire [3:0] wstrb;
 wire local_req,local_ready,local_error;wire [31:0] local_addr,local_data;wire [3:0] local_mask;
 wire [15:0] ram_addr;wire [31:0] ram_wdata,ram_data;wire [3:0] ram_wea;
 DCACHE #(.INDEX_HASH_SHIFT(9),.INDEX_BITS(DCACHE_INDEX_BITS),.PRECISE_STORES(1),.LOCAL_WRITE_ACK(1),.EARLY_STORE_PAYLOAD(1),.SPLIT_STORE_REQUEST(1)) dcache(
  .clk(clk),.rst(rst),.cpu_req(mv && dram_select),.cpu_store_req(mstore && dram_select),.cpu_read(mread),.cpu_advance(mv && mready),
  .clear_fault(dcache_clear_fault),.drain(!mv),.wb_empty(wb_empty),.fault_valid(fault),.fault_write(fault_write),
  .fault_address(fault_address),.refill_busy(refill_busy),.cpu_addr(ma[17:2]),
  .cpu_wdata(md),.cpu_wea(mm),.cpu_rdata(cache_data),.stall(cache_stall),.store_stall(cache_store_stall),.store_offer(cache_store_offer),.store_nonzero_offer(cache_store_nonzero_offer),
  .axi_araddr(araddr),.axi_arlen(arlen),.axi_arsize(arsize),.axi_arburst(arburst),
  .axi_arvalid(arvalid),.axi_arready(arready),.axi_rdata(rdata),.axi_rresp(rresp),
  .axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rready(rready),
  .axi_awaddr(awaddr),.axi_awlen(awlen),.axi_awsize(awsize),.axi_awburst(awburst),
  .axi_awvalid(awvalid),.axi_awready(awready),.axi_wdata(wdata),.axi_wstrb(wstrb),
  .axi_wvalid(wvalid),.axi_wlast(wlast),.axi_wready(wready),.axi_bvalid(bvalid),.axi_bresp(bresp),.axi_bready(bready),
  .local_req(local_req),.local_addr(local_addr),.local_data(local_data),.local_mask(local_mask),
  .local_ready(local_ready),.local_error(local_error));
 AXI_RAM_TARGET #(.LOCAL_WRITE_ACK(1),.LOCAL_SHARED_WRITE_DATA(1),.SHARED_REQUEST_ADDRESS(1),.REGISTER_WRITES(1)) target(.clk(clk),.rst(rst),
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
  // MMIO acceptance is independent of the DRAM cache hit path.
  .we(mv && mmio_select && !tx_wait && !mread),.re(mv && mmio_select && !tx_wait && mread),
  .addr({ma[7:2],2'b00}),.wdata(md),.wstrb(mm),.rdata(periph_data),
  .virtual_sw(virtual_sw),.virtual_key(virtual_key),.virtual_led(periph_led),.virtual_seg(periph_seg),
  .uart_tx_busy(uart_tx_busy),.uart_tx_req(uart_tx_req),.uart_tx_data(uart_tx_data),
  .uart_rx_data(uart_rx_data),.uart_rx_empty(uart_rx_empty),.uart_rx_full(uart_rx_full),
  .uart_rx_overflow(uart_rx_overflow),.uart_rx_count(uart_rx_count),.uart_rx_pop(uart_rx_pop),
  .dht11_io(dht11_io),.timer_irq(timer_irq),.software_irq(software_irq),.external_irq(external_irq));
 assign virtual_led=periph_led;
 // No physical display or connected twin TX consumer in this build.
 // MMIO 0x80200020 remains readable/writable for software compatibility.
 assign virtual_seg = {P_SEG_CNT{1'b0}};
endmodule

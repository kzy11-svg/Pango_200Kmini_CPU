`timescale 1ns/1ps
module pure_coremark_tb;
 integer csr_cycle_reads=0; reg [31:0] csr_cycle_start=0;
 integer delayed_load_completions=0, delayed_load_consumed=0;
reg clk=0,cnt_clk=0,rst=1,busy=0,seen=0;
integer cpu_fraction=0;
// Three half-periods = 4166ps + 2*4167ps = 12500ps, exactly 120 MHz.
initial forever begin
 cpu_fraction=cpu_fraction+2;
 if(cpu_fraction>=3)begin cpu_fraction=cpu_fraction-3;#4.167;end
 else #4.166;
 clk=~clk;
end
always #10 cnt_clk=~cnt_clk;
wire tx;wire [7:0] ch;
CPU_top dut(.clk(clk),.cnt_clk(cnt_clk),.rst(rst),.global_en(1'b1),.virtual_key(8'b0),.virtual_sw(64'b0),.uart_tx_busy(busy),.uart_tx_req(tx),.uart_tx_data(ch),.uart_rx_data(8'b0),.uart_rx_empty(1'b1),.uart_rx_full(1'b0),.uart_rx_overflow(1'b0),.uart_rx_count(5'b0));
reg [127:0] text=0; reg [3:0] crc_seen=0;integer cycles=0,txwait=0; integer timer_reads=0,start_cycle=0,measured_cycles=0;

initial begin
 repeat(8)@(negedge clk);
 for(integer i=0;i<64;i=i+1)if(dut.frontend.port[0].rom.mem[i]==32'h01313eb7 && dut.frontend.port[0].rom.mem[i+1]==32'hd00e8e93)begin
  dut.frontend.port[0].rom.mem[i]=32'h00100e93;dut.frontend.port[0].rom.mem[i+1]=32'h13;
  dut.frontend.port[1].rom.mem[i]=32'h00100e93;dut.frontend.port[1].rom.mem[i+1]=32'h13;
 end
 dut.frontend.port[0].rom.refresh_predecode();dut.frontend.port[1].rom.refresh_predecode();rst=0;
end
always @(posedge clk)if(!rst)begin
 cycles=cycles+1;
 if(dut.serial.accept && dut.serial.command_inst[6:0]==7'h73 && dut.serial.command_inst[14:12]!=0 && dut.serial.command_inst[31:20]==12'hb00)begin
   csr_cycle_reads=csr_cycle_reads+1;
   if(csr_cycle_reads==1)csr_cycle_start=dut.serial.csr_data;
   else $display("CSR_WINDOW cycles=%0d CM_per_MHz=%f",dut.serial.csr_data-csr_cycle_start,3000000.0/(dut.serial.csr_data-csr_cycle_start));
 end
 if(dut.mv && dut.mready && dut.mmio_select && dut.mread && dut.ma[7:2]==6'h14)begin timer_reads=timer_reads+1; if(timer_reads==1)start_cycle=cycles; else begin measured_cycles=cycles-start_cycle; $display("MEASURE cycles=%0d CM_per_MHz=%f",measured_cycles,3000000.0/measured_cycles);end end
 if(dut.tv)$fatal(1,"Unexpected trap pc=%h cause=%h",dut.tp,dut.tc);
 if(tx!=seen)begin
  seen<=tx;busy<=1;txwait<=100;$write("%c",ch);text={text[119:0],ch}; if(text[47:0]=="0xe714")crc_seen[0]=1; if(text[47:0]=="0x1fd7")crc_seen[1]=1; if(text[47:0]=="0x8e3a")crc_seen[2]=1; if(text[47:0]=="0x2e87")crc_seen[3]=1;
  if(text[31:0]=="IPC ")begin
   if(crc_seen!=4'hf)$fatal(1,"CRC mismatch");
   $display("PURE_SMOKE_PASS: baseline short-run CRCs match; not formal CoreMark score");$finish;
  end
 end else if(txwait>0)begin txwait<=txwait-1;if(txwait==1)busy<=0;end
 if(cycles>3000000)$fatal(1,"Timeout");
end
endmodule



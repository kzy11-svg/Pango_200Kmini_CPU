`timescale 1ns / 1ps

module MMIO_PERIPH (
    input  wire         clk,
    input  wire         cnt_clk,
    input  wire         rst,

    input  wire         we,
    input  wire         re,
    input  wire [7:0]   addr,
    input  wire [31:0]  wdata,
    input  wire [3:0]   wstrb,
    output reg  [31:0]  rdata,

    input  wire [63:0]  virtual_sw,
    input  wire [7:0]   virtual_key,
    output reg  [31:0]  virtual_led,
    output reg  [31:0]  virtual_seg,

    input  wire         uart_tx_busy,
    output reg          uart_tx_req,
    output reg  [7:0]   uart_tx_data,

    input  wire [7:0]   uart_rx_data,
    input  wire         uart_rx_empty,
    input  wire         uart_rx_full,
    input  wire         uart_rx_overflow,
    input  wire [4:0]   uart_rx_count,
    output wire         uart_rx_pop,

    inout  wire         dht11_io,

    output wire         timer_irq,
    output wire         software_irq,
    output wire         external_irq
);

    function [31:0] merge_bytes;
        input [31:0] old_value, new_value;
        input [3:0] mask;
        integer k;
        begin
            merge_bytes = old_value;
            for (k=0;k<4;k=k+1)
                if (mask[k]) merge_bytes[k*8 +: 8] = new_value[k*8 +: 8];
        end
    endfunction

    // Reset assertion is asynchronous; release is synchronized to cnt_clk.
    reg [1:0] cnt_reset_pipe;
    always @(posedge cnt_clk or posedge rst)
        if (rst) cnt_reset_pipe <= 2'b11;
        else cnt_reset_pipe <= {cnt_reset_pipe[0],1'b0};
    wire cnt_rst = cnt_reset_pipe[1];

    reg [31:0] r_seg;
    reg [31:0] r_led;
    reg        cnt_enable_cpu;
    reg [31:0] timer_cmp;
    reg [1:0]  irq_control;

    // 0x7c bit0: machine software interrupt pending.
    // 0x7c bit1: enable UART RX as a machine external interrupt.
    assign software_irq = irq_control[0];
    assign external_irq = irq_control[1] && !uart_rx_empty;

    always @(posedge clk) begin
        if (rst)
            irq_control <= 2'b00;
        else if (we && (addr == 8'h7c))
            if (wstrb[0]) irq_control <= wdata[1:0];
    end

    // Optional sensor is absent. Start writes are ignored; status is
    // deterministically timeout=1, valid=0, done=0, busy=0; data=0.
    // Compatibility port is intentionally unused, with no pad/controller.
    wire dht_busy_cpu = 1'b0;
    wire dht_done_cpu = 1'b0;
    wire dht_valid_cpu = 1'b0;
    wire dht_timeout_cpu = 1'b1;
    wire [31:0] dht_data_cpu = 32'b0;

    wire [31:0] counter_rdata;

    counter u_counter (
        .cpu_clk        (clk),
        .cnt_clk        (cnt_clk),
        .rst            (rst),
        .cnt_enable_cpu (cnt_enable_cpu),
        .perip_rdata    (counter_rdata)
    );

    assign timer_irq = cnt_enable_cpu && (timer_cmp != 32'b0) && (counter_rdata >= timer_cmp);
    // Reading RXDATA consumes exactly one byte. RXSTATUS is non-destructive.
    assign uart_rx_pop = re && (addr == 8'h68) && !uart_rx_empty;

    always @(posedge clk) begin
        if (rst) begin
            cnt_enable_cpu <= 1'b0;
            timer_cmp      <= 32'b0;
        end else if (we && (addr == 8'h50) && (&wstrb)) begin
            if (wdata == 32'h8000_0000) begin
                cnt_enable_cpu <= 1'b1;
            end else if (wdata == 32'hFFFF_FFFF) begin
                cnt_enable_cpu <= 1'b0;
            end
        end else if (we && (addr == 8'h54)) begin
            timer_cmp <= merge_bytes(timer_cmp, wdata, wstrb);
        end else if (we && (addr == 8'h58)) begin
            if (wstrb[0]) cnt_enable_cpu <= wdata[0];
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            r_seg <= 32'b0;
            r_led <= 32'b0;
        end else if (we) begin
            case (addr)
                8'h20: r_seg <= merge_bytes(r_seg,wdata,wstrb);
                8'h40: r_led <= merge_bytes(r_led,wdata,wstrb);
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            uart_tx_req      <= 1'b0;
            uart_tx_data     <= 8'b0;
        end else begin
            if (we && (addr == 8'h60) && wstrb[0] && !uart_tx_busy) begin
                uart_tx_data <= wdata[7:0];
                uart_tx_req  <= ~uart_tx_req;
            end
        end
    end

    always @(*) begin
        virtual_led = r_led;
        virtual_seg = r_seg;
    end

    always @(*) begin
        rdata = 32'b0;
        case (addr)
            8'h00: rdata = virtual_sw[31:0];
            8'h04: rdata = virtual_sw[63:32];
            8'h10: rdata = {24'b0, virtual_key};
            8'h20: rdata = r_seg;
            8'h40: rdata = r_led;
            8'h50: rdata = counter_rdata;
            8'h54: rdata = timer_cmp;
            8'h58: rdata = {31'b0, cnt_enable_cpu};
            8'h5c: rdata = {31'b0, timer_irq};
            8'h64: rdata = {31'b0, uart_tx_busy};
            8'h68: rdata = uart_rx_empty ? 32'b0 : {24'b0, uart_rx_data};
            // [12:8] count, [2] overflow, [1] full, [0] data available.
            8'h6c: rdata = {19'b0, uart_rx_count, 5'b0,
                            uart_rx_overflow, uart_rx_full, ~uart_rx_empty};
            // DHT_STATUS: [3] timeout, [2] valid, [1] done, [0] busy.
            8'h74: rdata = {28'b0, dht_timeout_cpu, dht_valid_cpu,
                            dht_done_cpu, dht_busy_cpu};
            8'h78: rdata = dht_data_cpu;
            8'h7c: rdata = {30'b0, irq_control};
            default: rdata = 32'b0;
        endcase
    end

endmodule

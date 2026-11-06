`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/16/2025 06:21:44 PM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module pango_cpu_board_top(
    input  wire       i_clk_27m,
    input  wire       i_reset_n,
    input  wire [3:0] i_key_n,
    input  wire       i_uart_rx,
    output wire       o_uart_tx,
    output wire [4:0] o_led
);

    wire w_clk_50Mhz;
    wire w_clk_rst;
    wire ref_pll_lock;
    wire cpu_pll_lock;
    wire cpu_clk;
    reg [1:0] reset_50_pipe, reset_cpu_pipe;
    always @(posedge w_clk_50Mhz or negedge w_clk_rst)
        if (!w_clk_rst) reset_50_pipe <= 0;
        else reset_50_pipe <= {reset_50_pipe[0],1'b1};
    always @(posedge cpu_clk or negedge w_clk_rst)
        if (!w_clk_rst) reset_cpu_pipe <= 0;
        else reset_cpu_pipe <= {reset_cpu_pipe[0],1'b1};
    wire reset_50_n = reset_50_pipe[1];
    wire reset_cpu_n = reset_cpu_pipe[1];

    wire [7:0] virtual_key_50m;
    wire [63:0] virtual_sw_50m;

    wire [31:0] virtual_led_cpu;

    (* ASYNC_REG = "TRUE" *) reg [31:0] virtual_led_50m_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] virtual_led_50m_sync;

    (* ASYNC_REG = "TRUE" *) reg [63:0] virtual_sw_cpu_meta;
    (* ASYNC_REG = "TRUE" *) reg [63:0] virtual_sw_cpu_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0]  virtual_key_cpu_meta;
    (* ASYNC_REG = "TRUE" *) reg [7:0]  virtual_key_cpu_sync;

    // The five user LEDs show virtual LED bits 4:0.
    assign o_led = virtual_led_50m_sync[4:0];
    // Virtual display output is disabled; CPU UART and LEDs remain active.

    always @(posedge w_clk_50Mhz or negedge reset_50_n) begin
        if (!reset_50_n) begin
            virtual_led_50m_meta <= 32'b0;
            virtual_led_50m_sync <= 32'b0;
        end else begin
            virtual_led_50m_meta <= virtual_led_cpu;
            virtual_led_50m_sync <= virtual_led_50m_meta;
        end
    end

    always @(posedge cpu_clk or negedge reset_cpu_n) begin
        if (!reset_cpu_n) begin
            virtual_sw_cpu_meta  <= 64'b0;
            virtual_sw_cpu_sync  <= 64'b0;
            virtual_key_cpu_meta <= 8'b0;
            virtual_key_cpu_sync <= 8'b0;
        end else begin
            virtual_sw_cpu_meta  <= virtual_sw_50m;
            virtual_sw_cpu_sync  <= virtual_sw_cpu_meta;
            virtual_key_cpu_meta <= virtual_key_50m | {4'b0000, ~i_key_n};
            virtual_key_cpu_sync <= virtual_key_cpu_meta;
        end
    end

    wire [7:0] rx_data;
    wire rx_ready;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy;
    wire twin_tx_start;
    wire [7:0] twin_tx_data;

    wire cpu_uart_tx_req;
    wire [7:0] cpu_uart_tx_data;
    reg [2:0] cpu_uart_tx_req_sync;
    
    wire cpu_uart_rx_pop;
    wire [7:0] cpu_uart_rx_data;
    wire cpu_uart_rx_empty;
    wire cpu_uart_rx_full;
    wire cpu_uart_rx_overflow;
    wire [4:0] cpu_uart_rx_count;

    reg uart_tx_ack_50;
    reg [1:0] uart_tx_ack_cpu_sync;
    wire cpu_uart_tx_pending = cpu_uart_tx_req != uart_tx_ack_cpu_sync[1];
    // The producer keeps payload stable from request until acknowledgement.
    // ACK is generated at the actual UART acceptance edge, not at detection.
    always @(posedge cpu_clk or negedge reset_cpu_n) begin
        if (!reset_cpu_n) uart_tx_ack_cpu_sync <= 0;
        else uart_tx_ack_cpu_sync <= {uart_tx_ack_cpu_sync[0], uart_tx_ack_50};
    end

    always @(posedge w_clk_50Mhz or negedge reset_50_n) begin
        if (!reset_50_n) begin
            cpu_uart_tx_req_sync <= 3'b000;
            tx_start             <= 1'b0;
            uart_tx_ack_50 <= 0;
            tx_data <= 0;
        end else begin
            cpu_uart_tx_req_sync <= {cpu_uart_tx_req_sync[1:0], cpu_uart_tx_req};
            tx_start <= 1'b0;
            if (tx_start && !tx_busy)
                uart_tx_ack_50 <= cpu_uart_tx_req_sync[2];
            else if (!tx_start && !tx_busy &&
                     cpu_uart_tx_req_sync[2] != uart_tx_ack_50) begin
                tx_data <= cpu_uart_tx_data;
                tx_start <= 1'b1;
            end
        end
    end
    
    (* ASYNC_REG = "TRUE" *) reg [1:0] uart_tx_busy_cpu_sync;
    always @(posedge cpu_clk or negedge reset_cpu_n) begin
        if (!reset_cpu_n)
            uart_tx_busy_cpu_sync <= 2'b00;
        else
            uart_tx_busy_cpu_sync <= {uart_tx_busy_cpu_sync[0], tx_busy};
    end
    
    reg rx_ready_d;
    always @(posedge w_clk_50Mhz or negedge reset_50_n) begin
        if (!reset_50_n)
            rx_ready_d <= 1'b0;
        else
            rx_ready_d <= rx_ready;
    end
    wire uart_rx_write = rx_ready && !rx_ready_d;

    UART_RX_ASYNC_FIFO #(
        .ADDR_WIDTH(4)
    ) uart_rx_fifo (
        .wr_clk      (w_clk_50Mhz),
        .wr_rst      (~reset_50_n),
        .wr_data     (rx_data),
        .wr_en       (uart_rx_write),
        .wr_full     (),
        .rd_clk      (cpu_clk),
        .rd_rst      (~reset_cpu_n),
        .rd_data     (cpu_uart_rx_data),
        .rd_en       (cpu_uart_rx_pop),
        .rd_empty    (cpu_uart_rx_empty),
        .rd_count    (cpu_uart_rx_count),
        .rd_full     (cpu_uart_rx_full),
        .rd_overflow (cpu_uart_rx_overflow)
    );

    // Verified vendor PLL ratios: 27 -> 50 MHz, then 50 -> 100 MHz.
    PANGO_REF_PLL ref_pll_inst (
        .clkin1 (i_clk_27m),
        .clkout0(w_clk_50Mhz),
        .lock   (ref_pll_lock)
    );
    PANGO_CPU_PLL cpu_pll_inst (
        .clkin1 (w_clk_50Mhz),
        .clkout0(cpu_clk),
        .lock   (cpu_pll_lock)
    );
    assign w_clk_rst = i_reset_n & ref_pll_lock & cpu_pll_lock;

`ifdef SIM_FAST_UART
    localparam integer UART_BAUD_RATE = 1000000;
`else
    localparam integer UART_BAUD_RATE = 9600;
`endif

    uart #(
        .CLK_FREQ(50000000),
        .BAUD_RATE(UART_BAUD_RATE)
    ) uart_inst(
        .clk(w_clk_50Mhz),
        .rst_n(reset_50_n),
        .rx(i_uart_rx),
        .rx_data(rx_data),
        .rx_ready(rx_ready),
        .tx(o_uart_tx),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy)
    );

    twin_controller twin_controller_inst(
        .clk(w_clk_50Mhz),
        .rst_n(reset_50_n),
        .rx_ready(rx_ready),
        .rx_data(rx_data),
        .tx_start(twin_tx_start),
        .tx_data(twin_tx_data),
        .tx_busy(tx_busy),
        .sw(virtual_sw_50m),
        .key(virtual_key_50m),
        .seg(40'b0),
        .led(virtual_led_50m_sync)
    );


    CPU_top student_top_inst(
        .clk(cpu_clk),
        .cnt_clk(w_clk_50Mhz),
        .rst(~reset_cpu_n),
        .global_en(1'b1),
        .virtual_key(virtual_key_cpu_sync),
        .virtual_sw(virtual_sw_cpu_sync),
        .virtual_led(virtual_led_cpu),
        .virtual_seg(),
        .uart_tx_busy(cpu_uart_tx_pending || uart_tx_busy_cpu_sync[1]),
        .uart_tx_req(cpu_uart_tx_req),
        .uart_tx_data(cpu_uart_tx_data),
        .uart_rx_data(cpu_uart_rx_data),
        .uart_rx_empty(cpu_uart_rx_empty),
        .uart_rx_full(cpu_uart_rx_full),
        .uart_rx_overflow(cpu_uart_rx_overflow),
        .uart_rx_count(cpu_uart_rx_count),
        .uart_rx_pop(cpu_uart_rx_pop),
        // No DHT11 is fitted on the Mini Base.
        .dht11_io()
    );

endmodule


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/08/14 18:32:45
// Design Name: 
// Module Name: UART_RX_ASYNC_FIFO
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


module UART_RX_ASYNC_FIFO #(
    parameter ADDR_WIDTH = 4
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst,
    input  wire [7:0]            wr_data,
    input  wire                  wr_en,
    output wire                  wr_full,

    input  wire                  rd_clk,
    input  wire                  rd_rst,
    output wire [7:0]            rd_data,
    input  wire                  rd_en,
    output wire                  rd_empty,
    output wire [ADDR_WIDTH:0]   rd_count,
    output wire                  rd_full,
    output wire                  rd_overflow
);
    localparam PTR_WIDTH = ADDR_WIDTH + 1;
    localparam DEPTH     = (1 << ADDR_WIDTH);

    (* ram_style = "distributed" *) reg [7:0] mem [0:DEPTH-1];

    reg [PTR_WIDTH-1:0] wr_ptr_bin;
    reg [PTR_WIDTH-1:0] wr_ptr_gray;
    reg [PTR_WIDTH-1:0] rd_ptr_bin;
    reg [PTR_WIDTH-1:0] rd_ptr_gray;

    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_wr_d1;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_wr_d2;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_rd_d1;
    (* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_rd_d2;
    (* ASYNC_REG = "TRUE" *) reg                 overflow_rd_d1;
    (* ASYNC_REG = "TRUE" *) reg                 overflow_rd_d2;
    reg overflow_wr;

    wire wr_push = wr_en && !wr_full;
    wire rd_pop  = rd_en && !rd_empty;

    wire [PTR_WIDTH-1:0] wr_ptr_bin_next  = wr_ptr_bin + wr_push;
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next =
        (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next  = rd_ptr_bin + rd_pop;
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next =
        (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    // Invert the two most-significant synchronized read-pointer bits for the
    // standard asynchronous FIFO full comparison.
    wire [PTR_WIDTH-1:0] rd_gray_wr_full_cmp =
        {~rd_gray_wr_d2[PTR_WIDTH-1:PTR_WIDTH-2],
          rd_gray_wr_d2[PTR_WIDTH-3:0]};

    // Current full state. Using the current write pointer avoids a
    // combinational dependency between wr_full, wr_push and the next pointer.
    assign wr_full  = (wr_ptr_gray == rd_gray_wr_full_cmp);
    assign rd_empty = (rd_ptr_gray == wr_gray_rd_d2);

    // The read pointer only advances after software reads RXDATA. Once the
    // synchronized write pointer says data is present, the selected byte has
    // already been stable for at least two read-clock edges.
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    function [PTR_WIDTH-1:0] gray_to_bin;
        input [PTR_WIDTH-1:0] gray;
        integer i;
        begin
            gray_to_bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                gray_to_bin[i] = gray_to_bin[i+1] ^ gray[i];
        end
    endfunction

    wire [PTR_WIDTH-1:0] wr_ptr_bin_rd = gray_to_bin(wr_gray_rd_d2);
    assign rd_count = wr_ptr_bin_rd - rd_ptr_bin;
    assign rd_full = (rd_count == DEPTH);
    assign rd_overflow = overflow_rd_d2;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr_bin  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray <= {PTR_WIDTH{1'b0}};
            overflow_wr <= 1'b0;
        end else begin
            if (wr_push)
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
            if (wr_en && wr_full)
                overflow_wr <= 1'b1;
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr_bin    <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray   <= {PTR_WIDTH{1'b0}};
            wr_gray_rd_d1 <= {PTR_WIDTH{1'b0}};
            wr_gray_rd_d2 <= {PTR_WIDTH{1'b0}};
            overflow_rd_d1 <= 1'b0;
            overflow_rd_d2 <= 1'b0;
        end else begin
            rd_ptr_bin    <= rd_ptr_bin_next;
            rd_ptr_gray   <= rd_ptr_gray_next;
            wr_gray_rd_d1 <= wr_ptr_gray;
            wr_gray_rd_d2 <= wr_gray_rd_d1;
            overflow_rd_d1 <= overflow_wr;
            overflow_rd_d2 <= overflow_rd_d1;
        end
    end

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_gray_wr_d1 <= {PTR_WIDTH{1'b0}};
            rd_gray_wr_d2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_gray_wr_d1 <= rd_ptr_gray;
            rd_gray_wr_d2 <= rd_gray_wr_d1;
        end
    end
endmodule


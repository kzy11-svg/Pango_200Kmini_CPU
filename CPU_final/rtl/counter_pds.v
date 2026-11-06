`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/22/2025 03:04:25 PM
// Design Name: 
// Module Name: counter
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


module counter(
    input  wire         cpu_clk,
    input  wire         cnt_clk,
    input  wire         rst,

    input  wire         cnt_enable_cpu,
    output wire [31:0]  perip_rdata
);

    function [31:0] gray_to_bin;
        input [31:0] gray;
        integer i;
        begin
            gray_to_bin[31] = gray[31];
            for (i = 30; i >= 0; i = i - 1) begin
                gray_to_bin[i] = gray_to_bin[i + 1] ^ gray[i];
            end
        end
    endfunction

    /* cnt_clk is the fixed 50 MHz clock.  Divide it by 50 so the exported
     * counter advances once per microsecond.  This reg stays entirely in
     * the low-speed counter domain and does not enter the CPU datapath. */
    reg [5:0]  cnt_1us;
    reg [31:0] cnt_us_bin;
    reg [31:0] cnt_us_gray;
    reg [1:0] cnt_reset_pipe;
    always @(posedge cnt_clk or posedge rst)
        if (rst) cnt_reset_pipe <= 2'b11;
        else cnt_reset_pipe <= {cnt_reset_pipe[0],1'b0};
    wire cnt_rst = cnt_reset_pipe[1];
    wire [31:0] cnt_us_next = cnt_us_bin + 32'd1;
    reg cnt_enable_cnt_d1, cnt_enable_cnt_d2;
    reg [31:0] cnt_gray_cpu_d1, cnt_gray_cpu_d2;

    // CPU->counter CDC: synchronize level control into cnt_clk domain.
    always @(posedge cnt_clk) begin
        if (cnt_rst) begin
            cnt_enable_cnt_d1 <= 1'b0;
            cnt_enable_cnt_d2 <= 1'b0;
        end else begin
            cnt_enable_cnt_d1 <= cnt_enable_cpu;
            cnt_enable_cnt_d2 <= cnt_enable_cnt_d1;
        end
    end

    always @(posedge cnt_clk) begin
        if (cnt_rst) begin
            cnt_1us <= 0;
        end else if (cnt_enable_cnt_d2) begin
            if (cnt_1us == 6'd49) begin
                cnt_1us <= 0;
            end else begin
                cnt_1us <= cnt_1us + 1'b1;
            end
        end else begin
            cnt_1us <= 0;
        end
    end

    always @(posedge cnt_clk) begin
        if (cnt_rst) begin
            cnt_us_bin <= 0;
            cnt_us_gray <= 0;
        end else if (cnt_enable_cnt_d2 && cnt_1us == 6'd49) begin
            cnt_us_bin <= cnt_us_next;
            cnt_us_gray <= cnt_us_next ^ (cnt_us_next >> 1);
        end else begin
            cnt_us_bin <= cnt_us_bin;
        end
    end

    // Registered source Gray code prevents binary-carry glitches crossing CDC.

    // Counter->CPU CDC: Gray code allows safe multi-bit crossing.
    always @(posedge cpu_clk) begin
        if (rst) begin
            cnt_gray_cpu_d1 <= 32'd0;
            cnt_gray_cpu_d2 <= 32'd0;
        end else begin
            cnt_gray_cpu_d1 <= cnt_us_gray;
            cnt_gray_cpu_d2 <= cnt_gray_cpu_d1;
        end
    end

    // Keep the Gray bus in Gray form through both CDC sampling stages.
    // Decode only their settled output, then register the binary snapshot.
    // MMIO and timer compare now consume a local CPU-domain binary Q, with
    // one additional CPU cycle of visibility latency (no tick-rate change).
    reg [31:0] counter_binary_cpu;
    always @(posedge cpu_clk) begin
        if (rst) counter_binary_cpu <= 32'd0;
        else counter_binary_cpu <= gray_to_bin(cnt_gray_cpu_d2);
    end
    assign perip_rdata = counter_binary_cpu;

endmodule

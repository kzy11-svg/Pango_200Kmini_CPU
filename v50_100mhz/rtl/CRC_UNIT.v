`timescale 1ns / 1ps

// CoreMark-compatible CRC16 accelerator.
// src0[15:0] is the input value; src1[15:0] is the running CRC.
// Bytes are consumed little-endian, matching crcu16() -> crcu8().
module CRC_UNIT (
    input         clk,
    input         rst,
    input         start,
    input  [15:0] src0,
    input  [15:0] src1,
    output reg    busy,
    output reg    done,
    output reg [31:0] result
);
    localparam [1:0] S_IDLE = 2'd0, S_BYTE0 = 2'd1, S_BYTE1 = 2'd2;

    reg [1:0]  state;
    reg [15:0] data_r;
    reg [15:0] crc_r;

    function [15:0] crc8_next;
        input [7:0]  data;
        input [15:0] crc;
        integer i;
        reg [7:0]  d;
        reg [15:0] c;
        reg        x16;
        begin
            d = data;
            c = crc;
            for (i = 0; i < 8; i = i + 1) begin
                x16 = d[0] ^ c[0];
                d   = d >> 1;
                if (x16)
                    c = c ^ 16'h4002;
                c = c >> 1;
                c[15] = x16;
            end
            crc8_next = c;
        end
    endfunction

    wire [15:0] crc_byte0 = crc8_next(data_r[7:0],  crc_r);
    wire [15:0] crc_byte1 = crc8_next(data_r[15:8], crc_r);

    always @(posedge clk) begin
        if (rst) begin
            state  <= S_IDLE;
            data_r <= 16'b0;
            crc_r  <= 16'b0;
            busy   <= 1'b0;
            done   <= 1'b0;
            result <= 32'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start && !busy) begin
                        data_r <= src0;
                        crc_r  <= src1;
                        busy   <= 1'b1;
                        state  <= S_BYTE0;
                    end
                end
                S_BYTE0: begin
                    crc_r <= crc_byte0;
                    state <= S_BYTE1;
                end
                S_BYTE1: begin
                    result <= {16'b0, crc_byte1};
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

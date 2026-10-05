`timescale 1ns / 1ps

// DHT11 single-wire controller.
// The data pin is open-drain: the FPGA only drives low and releases the line
// for the external pull-up and sensor response.
module dht11_controller #(
    parameter integer CLK_HZ = 50_000_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start_toggle,
    inout  wire        dht11_io,
    output reg         busy,
    output reg         done,
    output reg         valid,
    output reg         timeout,
    output reg  [31:0] data
);
    localparam integer T18MS       = CLK_HZ / 1000 * 18;
    localparam integer T200US      = CLK_HZ / 5000;
    localparam integer TBIT_LIMIT  = CLK_HZ / 1000;
    // DHT11 high pulse: approximately 26 us for 0 and 70 us for 1.
    localparam integer BIT_ONE_CUT = CLK_HZ / 25000;

    localparam [3:0] IDLE          = 4'd0,
                     START         = 4'd1,
                     WAIT_BUS_HIGH = 4'd2,
                     WAIT_RESP_LOW = 4'd3,
                     RESP_LOW      = 4'd4,
                     RESP_HIGH     = 4'd5,
                     BIT_LOW       = 4'd6,
                     BIT_HIGH      = 4'd7,
                     FINISH        = 4'd8,
                     ERROR_STATE   = 4'd9;

    reg [3:0]  state;
    reg [31:0] count;
    reg [31:0] high_count;
    reg [5:0]  bit_count;
    reg [39:0] shift_reg;
    reg        start_d;
    reg        drive_low;
    reg        dht_meta;
    reg        dht_sync;

    wire dht_in = dht_sync;
    wire checksum_ok =
        ((shift_reg[39:32] + shift_reg[31:24] +
          shift_reg[23:16] + shift_reg[15:8]) & 8'hff) == shift_reg[7:0];

    // No DHT11 is fitted, so there is no pad to drive on this board.

    always @(posedge clk) begin
        dht_meta <= 1'b1; // absent bus with pull-up; start times out
        dht_sync <= dht_meta;

        if (rst) begin
            state      <= IDLE;
            count      <= 32'b0;
            high_count <= 32'b0;
            bit_count  <= 6'b0;
            shift_reg  <= 40'b0;
            start_d    <= 1'b0;
            drive_low  <= 1'b0;
            dht_meta   <= 1'b1;
            dht_sync   <= 1'b1;
            busy       <= 1'b0;
            done       <= 1'b0;
            valid      <= 1'b0;
            timeout    <= 1'b0;
            data       <= 32'b0;
        end else begin
            start_d <= start_toggle;
            case (state)
                IDLE: begin
                    drive_low <= 1'b0;
                    busy      <= 1'b0;
                    if (start_toggle != start_d) begin
                        state      <= START;
                        count      <= 32'b0;
                        bit_count  <= 6'b0;
                        shift_reg  <= 40'b0;
                        busy       <= 1'b1;
                        done       <= 1'b0;
                        valid      <= 1'b0;
                        timeout    <= 1'b0;
                    end
                end

                START: begin
                    drive_low <= 1'b1;
                    count <= count + 1'b1;
                    if (count >= T18MS - 1) begin
                        drive_low <= 1'b0;
                        count <= 32'b0;
                        state <= WAIT_BUS_HIGH;
                    end
                end

                // Wait until the released host low level has actually risen.
                WAIT_BUS_HIGH: begin
                    if (dht_in) begin
                        count <= 32'b0;
                        state <= WAIT_RESP_LOW;
                    end else begin
                        count <= count + 1'b1;
                        if (count >= T200US)
                            state <= ERROR_STATE;
                    end
                end

                WAIT_RESP_LOW: begin
                    if (!dht_in) begin
                        count <= 32'b0;
                        state <= RESP_LOW;
                    end else begin
                        count <= count + 1'b1;
                        if (count >= T200US)
                            state <= ERROR_STATE;
                    end
                end

                RESP_LOW: begin
                    if (dht_in) begin
                        count <= 32'b0;
                        state <= RESP_HIGH;
                    end else begin
                        count <= count + 1'b1;
                        if (count >= T200US)
                            state <= ERROR_STATE;
                    end
                end

                RESP_HIGH: begin
                    if (!dht_in) begin
                        count <= 32'b0;
                        state <= BIT_LOW;
                    end else begin
                        count <= count + 1'b1;
                        if (count >= T200US)
                            state <= ERROR_STATE;
                    end
                end

                BIT_LOW: begin
                    if (dht_in) begin
                        high_count <= 32'b0;
                        state <= BIT_HIGH;
                    end else begin
                        count <= count + 1'b1;
                        if (count >= TBIT_LIMIT)
                            state <= ERROR_STATE;
                    end
                end

                BIT_HIGH: begin
                    if (!dht_in) begin
                        shift_reg <= {shift_reg[38:0], high_count >= BIT_ONE_CUT};
                        count <= 32'b0;
                        if (bit_count == 6'd39)
                            state <= FINISH;
                        else begin
                            bit_count <= bit_count + 1'b1;
                            state <= BIT_LOW;
                        end
                    end else begin
                        high_count <= high_count + 1'b1;
                        if (high_count >= TBIT_LIMIT)
                            state <= ERROR_STATE;
                    end
                end

                FINISH: begin
                    // MMIO format: [23:16] temperature integer,
                    // [15:8] temperature decimal, [7:0] humidity integer.
                    data <= {shift_reg[15:8], shift_reg[23:16],
                             shift_reg[31:24], shift_reg[39:32]};
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    valid   <= checksum_ok;
                    timeout <= 1'b0;
                    state   <= IDLE;
                end

                default: begin
                    drive_low <= 1'b0;
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    valid     <= 1'b0;
                    timeout   <= 1'b1;
                    state     <= IDLE;
                end
            endcase
        end
    end
endmodule

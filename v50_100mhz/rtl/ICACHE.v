`timescale 1ns / 1ps

// 2 KiB, 256 sets x 2 ways x one word.  A miss starts one standard
// four-beat AXI WRAP read at the requested (critical) word.  The processor
// may consume each arriving word immediately; the remaining beats fill in
// the background.
module ICACHE #(parameter [31:0] RESET_PC=32'h80000000) (
    input wire clk, input wire rst, input wire icache_abort,
    input wire fetch_hold, input wire [31:0] pc_next,
    output wire [31:0] inst_out,
    output wire fetch_fault,
    (* max_fanout = 8 *) output wire icache_stall,
    output wire [31:0] axi_araddr, output wire [7:0] axi_arlen,
    output wire [2:0] axi_arsize, output wire [1:0] axi_arburst,
    output wire axi_arvalid, input wire axi_arready,
    input wire [31:0] axi_rdata, input wire [1:0] axi_rresp,
    input wire axi_rvalid, input wire axi_rlast, output wire axi_rready
);
    (* ram_style = "distributed" *) reg [31:0] data_array0 [0:255];
    (* ram_style = "distributed" *) reg [31:0] data_array1 [0:255];
    (* ram_style = "distributed" *) reg [9:0] tag_array0 [0:255];
    (* ram_style = "distributed" *) reg [9:0] tag_array1 [0:255];
    reg [255:0] valid_array0, valid_array1;
    reg [255:0] lru_array;

    (* max_fanout = 8 *) reg [7:0] pc_index_reg;
    (* max_fanout = 8 *) reg [9:0] pc_tag_reg;
    (* max_fanout = 8 *) reg [31:0] pc_bram_reg;

    localparam IDLE = 1'b0, BURST = 1'b1;
    reg state;
    reg [31:0] fill_addr_reg;
    reg [1:0] fill_beat_reg;
    reg fault_pending;

    wire [7:0] index_cur = pc_index_reg;
    wire [9:0] current_tag = pc_tag_reg;
    wire hit0 = valid_array0[index_cur] &&
                (tag_array0[index_cur] == current_tag);
    wire hit1 = valid_array1[index_cur] &&
                (tag_array1[index_cur] == current_tag);
    wire hit = hit0 || hit1;
    wire [31:0] data_out = hit1 ? data_array1[index_cur] :
                                  data_array0[index_cur];

    wire [7:0] fill_index = fill_addr_reg[9:2];
    wire [9:0] fill_tag = fill_addr_reg[19:10];
    wire fill_hit0 = valid_array0[fill_index] &&
                     (tag_array0[fill_index] == fill_tag);
    wire fill_hit1 = valid_array1[fill_index] &&
                     (tag_array1[fill_index] == fill_tag);
    wire fill_victim = !valid_array0[fill_index] ? 1'b0 :
                       !valid_array1[fill_index] ? 1'b1 :
                                                  lru_array[fill_index];
    wire [31:0] next_fill_addr = {
        fill_addr_reg[31:4], fill_addr_reg[3:2] + 2'd1, 2'b00
    };

    // AXI4 single-ID profile: 32-bit, four-beat WRAP read.  Starting at the
    // requested word preserves the old critical-word-first behavior.
    assign axi_araddr  = {pc_bram_reg[31:2], 2'b00};
    assign axi_arlen   = 8'd3;
    assign axi_arsize  = 3'd2;
    assign axi_arburst = 2'b10;
    assign axi_arvalid = (state == IDLE) && !hit && !fault_pending && !icache_abort;
    assign axi_rready  = (state == BURST);

    wire response_ok = (axi_rresp == 2'b00);
    wire response_fire = axi_rvalid && axi_rready;
    wire stream_match = (state == BURST) && axi_rvalid && response_ok &&
                        (pc_bram_reg[31:2] == fill_addr_reg[31:2]);
    // Only a failed beat for the currently awaited word is architectural.
    // A redirect kills the fault; other background beats can fail silently.
    assign fetch_fault = fault_pending && !icache_abort;
    wire current_ready = hit || stream_match || fault_pending;

    assign icache_stall = !current_ready;
    assign inst_out = fault_pending ? 32'h00000013 :
                      stream_match ? axi_rdata : data_out;

    always @(posedge clk) begin
        if (rst || icache_abort) fault_pending <= 1'b0;
        else if (fault_pending) begin
            if (!fetch_hold) fault_pending <= 1'b0;
        end else if (response_fire && !response_ok && !hit &&
                     pc_bram_reg[31:2] == fill_addr_reg[31:2])
            fault_pending <= 1'b1;
    end

    always @(posedge clk) begin
        if (rst) begin
            pc_index_reg <= RESET_PC[9:2];
            pc_tag_reg <= RESET_PC[19:10];
            pc_bram_reg <= RESET_PC;
        end else if (icache_abort) begin
            pc_index_reg <= pc_next[9:2];
            pc_tag_reg <= pc_next[19:10];
            pc_bram_reg <= pc_next;
        end else if (!fetch_hold && current_ready) begin
            pc_index_reg <= pc_next[9:2];
            pc_tag_reg <= pc_next[19:10];
            pc_bram_reg <= pc_next;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            valid_array0 <= 256'b0;
            valid_array1 <= 256'b0;
            lru_array <= 256'b0;
            fill_addr_reg <= 32'h8000_0000;
            fill_beat_reg <= 2'b0;
        end else begin
            if (response_fire && response_ok) begin
                if (fill_hit0) begin
                    lru_array[fill_index] <= 1'b1;
                end else if (fill_hit1) begin
                    lru_array[fill_index] <= 1'b0;
                end else if (!fill_victim) begin
                    valid_array0[fill_index] <= 1'b1;
                    data_array0[fill_index] <= axi_rdata;
                    tag_array0[fill_index] <= fill_tag;
                    lru_array[fill_index] <= 1'b1;
                end else begin
                    valid_array1[fill_index] <= 1'b1;
                    data_array1[fill_index] <= axi_rdata;
                    tag_array1[fill_index] <= fill_tag;
                    lru_array[fill_index] <= 1'b0;
                end
            end else if (state == IDLE && hit) begin
                lru_array[index_cur] <= hit0 ? 1'b1 : 1'b0;
            end

            if (state == IDLE) begin
                if (axi_arvalid && axi_arready) begin
                    state <= BURST;
                    fill_addr_reg <= axi_araddr;
                    fill_beat_reg <= 2'b0;
                end
            end else if (response_fire) begin
                if (axi_rlast) begin
                    state <= IDLE;
                    fill_beat_reg <= 2'b0;
                end else begin
                    fill_addr_reg <= next_fill_addr;
                    fill_beat_reg <= fill_beat_reg + 2'd1;
                end
            end
        end
    end
endmodule

// Read-only AXI target for the synchronous instruction BRAM.
module AXI_ROM_TARGET (
    input wire clk, input wire rst,
    input wire [31:0] araddr, input wire [7:0] arlen,
    input wire [2:0] arsize, input wire [1:0] arburst,
    input wire arvalid, output wire arready,
    output wire [31:0] rdata, output wire [1:0] rresp,
    output wire rvalid, output wire rlast, input wire rready,
    output wire [13:0] rom_addr, input wire [31:0] rom_data
);
    // Only the BRAM word address and four-beat position are retained.  The
    // external AXI address stays 32 bits, but the fixed 64 KiB IROM does not
    // need a 32-bit internal address adder or an 8-bit beat counter.
    reg active, bad;
    reg [13:0] read_word_addr;
    reg [1:0] read_beat;

    assign arready = !rst && !active;
    wire ar_fire = arvalid && arready;
    wire [13:0] next_word_addr = {
        read_word_addr[13:2], read_word_addr[1:0] + 2'd1
    };

    // While idle, pre-address the BRAM directly from ARADDR.  ARVALID and
    // icache_abort therefore no longer sit in the BRAM address timing path.
    assign rom_addr = active ?
        ((rready && (read_beat != 2'd3)) ? next_word_addr : read_word_addr) :
        araddr[15:2];
    assign rvalid = active;
    assign rlast = (read_beat == 2'd3);
    assign rdata = bad ? 32'b0 : rom_data;
    assign rresp = bad ? 2'b10 : 2'b00;

    wire request_bad = (arsize != 3'd2) || (arburst != 2'b10) ||
                       (arlen != 8'd3) || (araddr[1:0] != 2'b00) ||
                       (araddr[31:16] != 16'h8000);

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            bad <= 1'b0;
            read_word_addr <= 14'b0;
            read_beat <= 2'b0;
        end else if (ar_fire) begin
            active <= 1'b1;
            bad <= request_bad;
            read_word_addr <= araddr[15:2];
            read_beat <= 2'b0;
        end else if (active && rready) begin
            if (rlast) begin
                active <= 1'b0;
            end else begin
                read_word_addr <= next_word_addr;
                read_beat <= read_beat + 2'd1;
            end
        end
    end
endmodule

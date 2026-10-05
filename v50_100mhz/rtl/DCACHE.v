`timescale 1ns / 1ps

// 512-byte, two-way write-through cache.  Read misses use a four-beat AXI
// WRAP burst with critical-word-first return.  A two-entry write buffer keeps
// ordinary stores from stopping the pipeline while preserving bus ordering.
module DCACHE #(
    parameter INDEX_BITS = 7,
    parameter PRECISE_STORES = 1,
    parameter LOCAL_WRITE_ACK = 0
)(
    input wire clk, input wire rst, input wire cpu_req,
    input wire cpu_read, input wire cpu_advance,
    input wire clear_fault, input wire drain,
    output wire wb_empty, output wire fault_valid, output wire refill_busy,
    output reg fault_write, output reg [31:0] fault_address,
    input wire [15:0] cpu_addr,
    input wire [31:0] cpu_wdata, input wire [3:0] cpu_wea,
    output wire [31:0] cpu_rdata, output wire stall,
    output wire [31:0] axi_araddr, output wire [7:0] axi_arlen,
    output wire [2:0] axi_arsize, output wire [1:0] axi_arburst,
    output wire axi_arvalid, input wire axi_arready,
    input wire [31:0] axi_rdata, input wire [1:0] axi_rresp,
    input wire axi_rvalid, input wire axi_rlast, output wire axi_rready,
    output wire [31:0] axi_awaddr, output wire [7:0] axi_awlen,
    output wire [2:0] axi_awsize, output wire [1:0] axi_awburst,
    output wire axi_awvalid, input wire axi_awready,
    output wire [31:0] axi_wdata, output wire [3:0] axi_wstrb,
    output wire axi_wvalid, output wire axi_wlast, input wire axi_wready,
    input wire axi_bvalid, input wire [1:0] axi_bresp,
    output wire axi_bready,
    output wire local_req, output wire [31:0] local_addr, local_data,
    output wire [3:0] local_mask,
    input wire local_ready, input wire local_error
);
    localparam SET_INDEX_BITS = INDEX_BITS - 1;
    localparam SET_COUNT = (1 << SET_INDEX_BITS);
    localparam TAG_BITS = 16 - SET_INDEX_BITS;

    (* ram_style = "distributed" *) reg [7:0] data0_b0 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data0_b1 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data0_b2 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data0_b3 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data1_b0 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data1_b1 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data1_b2 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [7:0] data1_b3 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_array0 [0:SET_COUNT-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_array1 [0:SET_COUNT-1];
    (* max_fanout = 8 *) reg [SET_COUNT-1:0] valid_array0, valid_array1;
    reg [SET_COUNT-1:0] lru_array;

    wire [SET_INDEX_BITS-1:0] index = cpu_addr[SET_INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] tag = cpu_addr[15:SET_INDEX_BITS];
    wire hit0 = valid_array0[index] && (tag_array0[index] == tag);
    wire hit1 = valid_array1[index] && (tag_array1[index] == tag);
    wire hit = hit0 || hit1;
    wire [31:0] data_out0 = {
        data0_b3[index], data0_b2[index], data0_b1[index], data0_b0[index]
    };
    wire [31:0] data_out1 = {
        data1_b3[index], data1_b2[index], data1_b1[index], data1_b0[index]
    };
    wire [31:0] data_out = hit1 ? data_out1 : data_out0;
    wire victim_way = !valid_array0[index] ? 1'b0 :
                      !valid_array1[index] ? 1'b1 : lru_array[index];

    reg read_active;
    assign refill_busy = read_active;
    reg [15:0] fill_addr_r;
    reg [1:0] read_beat_r;
    reg bus_fault;
    reg read_failed;
    reg store_pending, store_complete;
    assign fault_valid = bus_fault;

    wire [SET_INDEX_BITS-1:0] fill_index =
        fill_addr_r[SET_INDEX_BITS-1:0];
    wire [TAG_BITS-1:0] fill_tag = fill_addr_r[15:SET_INDEX_BITS];
    wire fill_hit0 = valid_array0[fill_index] &&
                     (tag_array0[fill_index] == fill_tag);
    wire fill_hit1 = valid_array1[fill_index] &&
                     (tag_array1[fill_index] == fill_tag);
    wire fill_victim = !valid_array0[fill_index] ? 1'b0 :
                       !valid_array1[fill_index] ? 1'b1 :
                                                  lru_array[fill_index];
    wire [15:0] next_fill_addr = {
        fill_addr_r[15:2], fill_addr_r[1:0] + 2'd1
    };

    wire store_req = cpu_req && (|cpu_wea);
    wire load_miss = cpu_req && cpu_read && !hit;
    wire response_ok = (axi_rresp == 2'b00);
    wire response_fire = axi_rvalid && axi_rready;
    wire fill_write_conflict;
    wire stream_match = !fill_write_conflict && read_active && axi_rvalid && response_ok &&
                        (cpu_addr == fill_addr_r) && !read_failed &&
                        (axi_rlast == (read_beat_r == 2'd3));

    assign axi_araddr = {14'h2004, cpu_addr, 2'b00};
    assign axi_arlen = 8'd3;
    assign axi_arsize = 3'd2;
    assign axi_arburst = 2'b10;
    assign axi_arvalid = !read_active && load_miss && wb_empty && !bus_fault;
    assign axi_rready = read_active;

    // Two-entry write FIFO.  Count includes a write waiting for its B response.
    reg [15:0] wb_addr [0:1];
    reg [31:0] wb_data [0:1];
    reg [3:0] wb_mask [0:1];
    reg wb_head, wb_tail;
    reg [1:0] wb_count;
    reg wb_inflight, aw_done, w_done;

    assign wb_empty = (wb_count == 0) && !wb_inflight;
    wire wb_full = (wb_count == 2);
    // A pending byte/halfword write is newer than this background read.
    // Do not install or forward its old word; refetch after the write response.
    assign fill_write_conflict =
        ((wb_count != 0) && wb_addr[wb_head] == fill_addr_r) ||
        ((wb_count == 2) && wb_addr[!wb_head] == fill_addr_r);
    wire wb_response = wb_inflight && axi_bvalid && axi_bready;
    wire store_success_now = PRECISE_STORES && store_pending && wb_response && (axi_bresp == 2'b00);
    // Local request generation is independent of CPU advance and target ready.
    // The target checks availability/error before the write edge; AXI is unchanged.
    assign local_req = LOCAL_WRITE_ACK && PRECISE_STORES && store_req &&
        wb_empty && !store_pending && !store_complete && !bus_fault && !drain;
    assign local_addr = {14'h2004,cpu_addr,2'b00};
    assign local_data = cpu_wdata;
    assign local_mask = cpu_wea;
    wire local_fire = LOCAL_WRITE_ACK && local_req && local_ready;
    wire local_success = local_fire && !local_error;
    wire store_ready = store_complete || store_success_now || local_success;
    wire wb_pop = wb_response; // Retire a failed response too; fault metadata is held separately.
    wire can_push = !wb_full || wb_pop;
    wire wb_push = store_req && can_push && !bus_fault && !local_fire &&
        (PRECISE_STORES ? (!store_pending && !store_complete) : cpu_advance);
    // Present the first precise-store transaction while capturing its payload.
    // Unaccepted channels use the captured FIFO entry on subsequent cycles.
    // Posted mode retains its original path, without cpu_advance feedback.
    wire direct_write = PRECISE_STORES && wb_empty && wb_push && !drain;
    wire write_request = (!wb_empty && !wb_inflight) || direct_write;

    assign axi_awaddr = {14'h2004, (direct_write ? cpu_addr : wb_addr[wb_head]), 2'b00};
    assign axi_awlen = 8'd0;
    assign axi_awsize = 3'd2;
    assign axi_awburst = 2'b01;
    assign axi_awvalid = write_request && !aw_done;
    assign axi_wdata = direct_write ? cpu_wdata : wb_data[wb_head];
    assign axi_wstrb = direct_write ? cpu_wea : wb_mask[wb_head];
    assign axi_wvalid = write_request && !w_done;
    assign axi_wlast = 1'b1;
    assign axi_bready = wb_inflight;

    assign stall = bus_fault || (drain && !wb_empty) ||
                   (load_miss && !stream_match) ||
                   (store_req && (PRECISE_STORES ? !store_ready : !can_push));
    assign cpu_rdata = stream_match ? axi_rdata : data_out;

    wire prefetch_set_conflict = cpu_req && cpu_read && hit &&
        (index == fill_index) && !fill_hit0 && !fill_hit1;

    always @(posedge clk) begin
        if (rst) begin
            read_active <= 1'b0;
            fill_addr_r <= 16'b0;
            read_beat_r <= 2'b0;
            bus_fault <= 1'b0;
            fault_write <= 1'b0; fault_address <= 0; read_failed <= 0;
        end else begin
            if (clear_fault) bus_fault <= 1'b0;
            if (axi_arvalid && axi_arready) begin
                read_active <= 1'b1;
                fill_addr_r <= cpu_addr;
                read_beat_r <= 2'b0;
                read_failed <= 0;
            end else if (response_fire) begin
                if (!response_ok || (axi_rlast != (read_beat_r == 2'd3))) begin
                    read_failed <= 1;
                    // Background refill failures must not be attributed to an
                    // unrelated younger MEM instruction. A waiting load faults.
                    if (cpu_req && cpu_read && !hit && cpu_addr==fill_addr_r && !bus_fault) begin
                        bus_fault <= 1'b1; fault_write <= 0;
                        fault_address <= {14'h2004, cpu_addr, 2'b00};
                    end
                end
                if (axi_rlast) begin
                    read_active <= 1'b0;
                    read_beat_r <= 2'b0;
                end else begin
                    fill_addr_r <= next_fill_addr;
                    read_beat_r <= read_beat_r + 2'd1;
                end
            end
            if (local_fire && local_error) begin
                bus_fault <= 1'b1; fault_write <= 1;
                fault_address <= local_addr;
            end
            if (wb_response && (axi_bresp != 2'b00)) begin
                bus_fault <= 1'b1; fault_write <= 1;
                fault_address <= {14'h2004, wb_addr[wb_head], 2'b00};
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            wb_head <= 1'b0;
            wb_tail <= 1'b0;
            wb_count <= 2'b0;
            wb_inflight <= 1'b0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            store_pending <= 0; store_complete <= 0;
        end else begin
            if (clear_fault || (store_complete && cpu_advance)) begin
                store_complete <= 0; store_pending <= 0;
            end
            if (local_success) begin
                // If another pipeline stall holds MEM, remember this completed
                // write and do not issue it again while the same instruction stays.
                store_pending <= 0;
                store_complete <= !cpu_advance;
            end
            if (wb_push) begin
                if (PRECISE_STORES) store_pending <= 1;
                wb_addr[wb_tail] <= cpu_addr;
                wb_data[wb_tail] <= cpu_wdata;
                wb_mask[wb_tail] <= cpu_wea;
                wb_tail <= wb_tail + 1'b1;
            end

            if (axi_awvalid && axi_awready)
                aw_done <= 1'b1;
            if (axi_wvalid && axi_wready)
                w_done <= 1'b1;
            if (write_request &&
                (aw_done || (axi_awvalid && axi_awready)) &&
                (w_done || (axi_wvalid && axi_wready))) begin
                wb_inflight <= 1'b1;
                aw_done <= 1'b0;
                w_done <= 1'b0;
            end
            if (wb_response) begin
                wb_inflight <= 1'b0;
                wb_head <= wb_head + 1'b1;
                if (PRECISE_STORES) begin
                    store_pending <= 0;
                    // Keep completion only if another stall prevents consumption this cycle.
                    store_complete <= (axi_bresp == 0) && !cpu_advance;
                end
            end

            case ({wb_push, wb_pop})
                2'b10: wb_count <= wb_count + 2'd1;
                2'b01: wb_count <= wb_count - 2'd1;
                default: wb_count <= wb_count;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst || clear_fault) begin
            valid_array0 <= {SET_COUNT{1'b0}};
            valid_array1 <= {SET_COUNT{1'b0}};
            lru_array <= {SET_COUNT{1'b0}};
        end else if (wb_push || local_success) begin
            if (hit0) begin
                if (cpu_wea[0]) data0_b0[index] <= cpu_wdata[7:0];
                if (cpu_wea[1]) data0_b1[index] <= cpu_wdata[15:8];
                if (cpu_wea[2]) data0_b2[index] <= cpu_wdata[23:16];
                if (cpu_wea[3]) data0_b3[index] <= cpu_wdata[31:24];
                lru_array[index] <= 1'b1;
            end else if (hit1) begin
                if (cpu_wea[0]) data1_b0[index] <= cpu_wdata[7:0];
                if (cpu_wea[1]) data1_b1[index] <= cpu_wdata[15:8];
                if (cpu_wea[2]) data1_b2[index] <= cpu_wdata[23:16];
                if (cpu_wea[3]) data1_b3[index] <= cpu_wdata[31:24];
                lru_array[index] <= 1'b0;
            end else if (cpu_wea == 4'b1111) begin
                if (!victim_way) begin
                    valid_array0[index] <= 1'b1;
                    tag_array0[index] <= tag;
                    data0_b0[index] <= cpu_wdata[7:0];
                    data0_b1[index] <= cpu_wdata[15:8];
                    data0_b2[index] <= cpu_wdata[23:16];
                    data0_b3[index] <= cpu_wdata[31:24];
                    lru_array[index] <= 1'b1;
                end else begin
                    valid_array1[index] <= 1'b1;
                    tag_array1[index] <= tag;
                    data1_b0[index] <= cpu_wdata[7:0];
                    data1_b1[index] <= cpu_wdata[15:8];
                    data1_b2[index] <= cpu_wdata[23:16];
                    data1_b3[index] <= cpu_wdata[31:24];
                    lru_array[index] <= 1'b0;
                end
            end
        end else if (response_fire && response_ok && !read_failed &&
                     (axi_rlast == (read_beat_r == 2'd3)) && !prefetch_set_conflict && !fill_write_conflict) begin
            if (fill_hit0) begin
                lru_array[fill_index] <= 1'b1;
            end else if (fill_hit1) begin
                lru_array[fill_index] <= 1'b0;
            end else if (!fill_victim) begin
                valid_array0[fill_index] <= 1'b1;
                tag_array0[fill_index] <= fill_tag;
                data0_b0[fill_index] <= axi_rdata[7:0];
                data0_b1[fill_index] <= axi_rdata[15:8];
                data0_b2[fill_index] <= axi_rdata[23:16];
                data0_b3[fill_index] <= axi_rdata[31:24];
                lru_array[fill_index] <= 1'b1;
            end else begin
                valid_array1[fill_index] <= 1'b1;
                tag_array1[fill_index] <= fill_tag;
                data1_b0[fill_index] <= axi_rdata[7:0];
                data1_b1[fill_index] <= axi_rdata[15:8];
                data1_b2[fill_index] <= axi_rdata[23:16];
                data1_b3[fill_index] <= axi_rdata[31:24];
                lru_array[fill_index] <= 1'b0;
            end
        end else if (cpu_req && cpu_read && hit) begin
            lru_array[index] <= hit0 ? 1'b1 : 1'b0;
        end
    end
endmodule

// Full five-channel, single-ID AXI target for the synchronous data BRAM.
// Reads support four-beat WRAP bursts; writes are single beat with byte strobes.
module AXI_RAM_TARGET #(parameter LOCAL_WRITE_ACK = 0) (
    input wire clk, input wire rst,
    input wire [31:0] araddr, input wire [7:0] arlen,
    input wire [2:0] arsize, input wire [1:0] arburst,
    input wire arvalid, output wire arready,
    output wire [31:0] rdata, output wire [1:0] rresp,
    output wire rvalid, output wire rlast, input wire rready,
    input wire [31:0] awaddr, input wire [7:0] awlen,
    input wire [2:0] awsize, input wire [1:0] awburst,
    input wire awvalid, output wire awready,
    input wire [31:0] wdata, input wire [3:0] wstrb,
    input wire wvalid, input wire wlast, output wire wready,
    output reg bvalid, output reg [1:0] bresp, input wire bready,
    input wire local_req, input wire [31:0] local_addr, local_data,
    input wire [3:0] local_mask,
    output wire local_ready, output wire local_error,
    output wire [15:0] ram_addr, output wire [31:0] ram_wdata,
    output wire [3:0] ram_wea, input wire [31:0] ram_data
);
    // The AXI pins remain standard-width.  Internally this fixed DRAM target
    // stores only its 16-bit BRAM word address and a two-bit burst position.
    reg read_active, read_bad;
    reg [15:0] read_word_addr;
    reg [1:0] read_beat;
    reg aw_saved, w_saved, saved_aw_bad, saved_wlast;
    reg [15:0] saved_aw_word;
    reg [31:0] saved_wdata;
    reg [3:0] saved_wstrb;

    wire local_enabled = LOCAL_WRITE_ACK && local_req;
    assign local_ready = LOCAL_WRITE_ACK && !rst && !read_active &&
        !aw_saved && !w_saved && !bvalid;
    assign local_error = (local_addr[31:18] != 14'h2004) ||
        (local_addr[1:0] != 0);
    wire local_fire = local_enabled && local_ready;

    // Complete older writes before accepting a later read.  This preserves
    // store/load order for partial stores that are not allocated in DCache.
    assign arready = !rst && !read_active && !aw_saved && !w_saved &&
                     !bvalid && !awvalid && !wvalid && !local_enabled;
    assign awready = !rst && !aw_saved && !bvalid && !local_enabled;
    assign wready  = !rst && !w_saved && !bvalid && !local_enabled;

    wire ar_fire = arvalid && arready;
    wire aw_fire = awvalid && awready;
    wire w_fire = wvalid && wready;
    wire write_commit = !rst && !read_active && !bvalid && !local_fire &&
                        (aw_saved || aw_fire) && (w_saved || w_fire);

    wire [15:0] write_word = aw_saved ? saved_aw_word : awaddr[17:2];
    wire [31:0] write_value = w_saved ? saved_wdata : wdata;
    wire [3:0] write_strobe = w_saved ? saved_wstrb : wstrb;
    wire write_last = w_saved ? saved_wlast : wlast;
    wire aw_bad_now = (awlen != 0) || (awsize != 2) ||
                      (awburst != 1) || (awaddr[1:0] != 0) ||
                      (awaddr[31:18] != 14'h2004);
    wire write_error = (aw_saved ? saved_aw_bad : aw_bad_now) ||
                       !write_last;

    wire [15:0] next_read_word = {
        read_word_addr[15:2], read_word_addr[1:0] + 2'd1
    };
    wire [15:0] memory_word = read_active ?
        ((rready && (read_beat != 2'd3)) ? next_read_word : read_word_addr) :
        araddr[17:2];

    assign ram_addr = local_fire ? local_addr[17:2] : (write_commit ? write_word : memory_word);
    assign ram_wdata = local_fire ? local_data : write_value;
    assign ram_wea = local_fire ? (local_error ? 4'b0 : local_mask) :
        ((write_commit && !write_error) ? write_strobe : 4'b0);
    assign rvalid = read_active;
    assign rlast = (read_beat == 2'd3);
    assign rdata = read_bad ? 32'b0 : ram_data;
    assign rresp = read_bad ? 2'b10 : 2'b00;

    wire ar_bad = (arsize != 2) || (arburst != 2'b10) ||
                  (arlen != 3) || (araddr[1:0] != 0) ||
                  (araddr[31:18] != 14'h2004);

    always @(posedge clk) begin
        if (rst) begin
            read_active <= 1'b0;
            read_bad <= 1'b0;
            read_word_addr <= 16'b0;
            read_beat <= 2'b0;
            aw_saved <= 1'b0;
            w_saved <= 1'b0;
            saved_aw_bad <= 1'b0;
            saved_wlast <= 1'b0;
            saved_aw_word <= 16'b0;
            saved_wdata <= 32'b0;
            saved_wstrb <= 4'b0;
            bvalid <= 1'b0;
            bresp <= 2'b0;
        end else begin
            if (ar_fire) begin
                read_active <= 1'b1;
                read_bad <= ar_bad;
                read_word_addr <= araddr[17:2];
                read_beat <= 2'b0;
            end else if (read_active && rready) begin
                if (rlast) begin
                    read_active <= 1'b0;
                end else begin
                    read_word_addr <= next_read_word;
                    read_beat <= read_beat + 2'd1;
                end
            end

            if (aw_fire) begin
                aw_saved <= 1'b1;
                saved_aw_word <= awaddr[17:2];
                saved_aw_bad <= aw_bad_now;
            end
            if (w_fire) begin
                w_saved <= 1'b1;
                saved_wdata <= wdata;
                saved_wstrb <= wstrb;
                saved_wlast <= wlast;
            end
            if (write_commit) begin
                aw_saved <= 1'b0;
                w_saved <= 1'b0;
                bvalid <= 1'b1;
                bresp <= write_error ? 2'b10 : 2'b00;
            end else if (bvalid && bready) begin
                bvalid <= 1'b0;
            end
        end
    end
endmodule

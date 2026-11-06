`timescale 1ns / 1ps

// 512-byte, two-way write-through cache.  Read misses use a four-beat AXI
// WRAP burst with critical-word-first return.  A two-entry write buffer keeps
// ordinary stores from stopping the pipeline while preserving bus ordering.
module DCACHE #(
    parameter INDEX_BITS = 7,
    parameter INDEX_HASH_SHIFT = 0,
    parameter PRECISE_STORES = 1,
    parameter LOCAL_WRITE_ACK = 0,
    parameter EARLY_STORE_PAYLOAD = 0,
    parameter SPLIT_STORE_REQUEST = 0
)(
    input wire clk, input wire rst, input wire cpu_req, input wire cpu_store_req,
    input wire cpu_read, input wire cpu_advance,
    input wire clear_fault, input wire drain,
    output wire wb_empty, output wire fault_valid, output wire refill_busy,
    output reg fault_write, output reg [31:0] fault_address,
    input wire [15:0] cpu_addr,
    input wire [31:0] cpu_wdata, input wire [3:0] cpu_wea,
    output wire [31:0] cpu_rdata, output wire stall, output wire store_stall, output wire store_offer, output wire store_nonzero_offer,
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
    localparam integer SET_INDEX_BITS = INDEX_BITS - 1;
    localparam integer SET_COUNT = (1 << SET_INDEX_BITS);
    localparam integer TAG_BITS = 16 - SET_INDEX_BITS;

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
    // Sequential metadata invalidation permits true LUT RAM instead of a
    // resettable FF array with per-row multi-address update muxes.
    reg valid_array0[0:SET_COUNT-1] /* synthesis syn_ramstyle="lut_ram" */;
    reg valid_array1[0:SET_COUNT-1] /* synthesis syn_ramstyle="lut_ram" */;
    reg lru_array[0:SET_COUNT-1] /* synthesis syn_ramstyle="lut_ram" */;
    reg metadata_initializing;
    reg [SET_INDEX_BITS-1:0] metadata_index;
    wire metadata_ready=!rst && !clear_fault && !metadata_initializing;
    always @(posedge clk)begin
      if(rst || clear_fault)begin metadata_initializing<=1;metadata_index<=0;end
      else if(metadata_initializing)begin
        metadata_index<=metadata_index+1'b1;
        if(&metadata_index)metadata_initializing<=0;
      end
    end

    wire [SET_INDEX_BITS-1:0] index = cpu_addr[SET_INDEX_BITS-1:0] ^
        (INDEX_HASH_SHIFT ? (cpu_addr >> INDEX_HASH_SHIFT) : 16'b0);
    wire [TAG_BITS-1:0] tag = cpu_addr[15:SET_INDEX_BITS];
    wire hit0 = metadata_ready && valid_array0[index] && (tag_array0[index] == tag);
    wire hit1 /* synthesis syn_maxfan=24 */ = metadata_ready && valid_array1[index] && (tag_array1[index] == tag);
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
        fill_addr_r[SET_INDEX_BITS-1:0] ^
        (INDEX_HASH_SHIFT ? (fill_addr_r >> INDEX_HASH_SHIFT) : 16'b0);
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

    // In split mode the integration provides the exact selected Store
    // offer, independently of the combined Load/Store request cone.
    wire store_req = (SPLIT_STORE_REQUEST ? cpu_store_req : cpu_req) && (|cpu_wea);
    // CPU_top binds drain=!mem_valid. An active split Store therefore
    // already proves !drain; keep the generic independent interface intact.
    wire store_drain_clear = SPLIT_STORE_REQUEST ? 1'b1 : !drain;
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
    assign axi_arvalid = metadata_ready && !read_active && load_miss && wb_empty && !bus_fault;
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
    assign local_req = metadata_ready && LOCAL_WRITE_ACK && PRECISE_STORES && store_req &&
        wb_empty && !store_pending && !store_complete && !bus_fault && store_drain_clear;
    assign local_addr = {14'h2004,cpu_addr,2'b00};
    assign local_data = cpu_wdata;
    assign local_mask = cpu_wea;
    wire local_fire = LOCAL_WRITE_ACK && local_req && local_ready;
    wire local_success = local_fire && !local_error;
    wire store_ready = store_complete || store_success_now || local_success;
    wire wb_pop = wb_response; // Retire a failed response too; fault metadata is held separately.
    wire can_push = !wb_full || wb_pop;
    wire wb_push = metadata_ready && store_req && can_push && !bus_fault && !local_fire &&
        (PRECISE_STORES ? (!store_pending && !store_complete) : cpu_advance);
    // Present the first precise-store transaction while capturing its payload.
    // Unaccepted channels use the captured FIFO entry on subsequent cycles.
    // Posted mode retains its original path, without cpu_advance feedback.
    wire direct_write = PRECISE_STORES && wb_empty && wb_push && store_drain_clear;
    wire write_request = (!wb_empty && !wb_inflight) || direct_write;

    // Queue ownership selects payload. Late ready/error logic qualifies
    // VALID only; it no longer steers the wide address/data buses.
    // With an empty queue, a valid precise-store AXI request is necessarily
    // direct_write. With a nonempty queue, the oldest stored payload wins.
    wire write_payload_live = PRECISE_STORES && wb_empty;
    assign axi_awaddr = {14'h2004, (write_payload_live ? cpu_addr : wb_addr[wb_head]), 2'b00};
    assign axi_awlen = 8'd0;
    assign axi_awsize = 3'd2;
    assign axi_awburst = 2'b01;
    assign axi_awvalid = write_request && !aw_done;
    assign axi_wdata = write_payload_live ? cpu_wdata : wb_data[wb_head];
    assign axi_wstrb = write_payload_live ? cpu_wea : wb_mask[wb_head];
    assign axi_wvalid = write_request && !w_done;
    assign axi_wlast = 1'b1;
    assign axi_bready = wb_inflight;

    // When cpu_read=0, load_miss is identically false. Export that exact
    // store-only expression separately so load tag logic is not on Store ack.
    assign store_stall = (cpu_req && !metadata_ready) || bus_fault || (drain && !wb_empty) ||
                         (store_req && (PRECISE_STORES ? !store_ready : !can_push));
    // Fact for an active selected store: cpu_req=1 and drain=0.
    // The actual local request still requires store_req and drives the write.
    wire local_offer = LOCAL_WRITE_ACK && PRECISE_STORES && metadata_ready &&
        wb_empty && !store_pending && !store_complete && !bus_fault && local_ready && !local_error;
    wire selected_store_ready = PRECISE_STORES ? (store_complete || store_success_now || local_offer) : can_push;
    assign store_offer = metadata_ready && (!(|cpu_wea) || selected_store_ready);
    // Acceptance fact for a selected nonzero-mask store, independent of the
    // live shared request's mask/address. The caller supplies its own mask.
    // Actual request generation, RAM write, fault and queue ownership stay above.
    assign store_nonzero_offer = metadata_ready && selected_store_ready;
    assign stall = store_stall || (load_miss && !stream_match);
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

    // Payload ownership is available before CPU acceptance/retirement.
    // An idle nonzero mask reserves this port but cannot authorize a Store.
    wire cache_store_event = wb_push || local_success;
    wire store_payload_owner = EARLY_STORE_PAYLOAD ? (|cpu_wea) : cache_store_event;
    wire cache_store_way0 = hit0 || (!hit1 && cpu_wea==4'b1111 && !victim_way);
    wire cache_store_way1 = !hit0 && (hit1 || (cpu_wea==4'b1111 && victim_way));
    // A reserved Store payload may discard background installation. Keep
    // the complete data/tag/valid/LRU installation event atomic.
    wire cache_refill_write = !store_payload_owner && response_fire && response_ok && !read_failed &&
        (axi_rlast == (read_beat_r == 2'd3)) && !prefetch_set_conflict && !fill_write_conflict;
    wire cache_fill_way0 = !fill_hit0 && !fill_hit1 && !fill_victim;
    wire cache_fill_way1 = !fill_hit0 && !fill_hit1 && fill_victim;
    wire [INDEX_BITS-1:0] cache_write_index = store_payload_owner ? index : fill_index;
    wire [31:0] cache_write_data = store_payload_owner ? cpu_wdata : axi_rdata;
    // synthesis translate_off
    always @(posedge clk)if(!rst)begin
        if(SPLIT_STORE_REQUEST)begin
            if(cpu_store_req!==(cpu_req && !cpu_read))$fatal(1,"DCache split Store request contract");
            if(cpu_store_req && drain)$fatal(1,"DCache active split Store while draining");
            if(store_req!==(cpu_req && (|cpu_wea)))$fatal(1,"DCache Store mask/authorization changed");
        end
        if(cpu_req && cpu_read && |cpu_wea)$fatal(1,"Demand Load has Store mask");
        if(cache_store_event && !store_payload_owner)$fatal(1,"Store event without payload owner");
    end
    // synthesis translate_on
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way0 && cpu_wea[0]) ||
         (cache_refill_write && cache_fill_way0)))
        data0_b0[cache_write_index] <= cache_write_data[7:0];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way0 && cpu_wea[1]) ||
         (cache_refill_write && cache_fill_way0)))
        data0_b1[cache_write_index] <= cache_write_data[15:8];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way0 && cpu_wea[2]) ||
         (cache_refill_write && cache_fill_way0)))
        data0_b2[cache_write_index] <= cache_write_data[23:16];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way0 && cpu_wea[3]) ||
         (cache_refill_write && cache_fill_way0)))
        data0_b3[cache_write_index] <= cache_write_data[31:24];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way1 && cpu_wea[0]) ||
         (cache_refill_write && cache_fill_way1)))
        data1_b0[cache_write_index] <= cache_write_data[7:0];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way1 && cpu_wea[1]) ||
         (cache_refill_write && cache_fill_way1)))
        data1_b1[cache_write_index] <= cache_write_data[15:8];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way1 && cpu_wea[2]) ||
         (cache_refill_write && cache_fill_way1)))
        data1_b2[cache_write_index] <= cache_write_data[23:16];
    always @(posedge clk)if(!rst && !clear_fault && !metadata_initializing &&
        ((cache_store_event && cache_store_way1 && cpu_wea[3]) ||
         (cache_refill_write && cache_fill_way1)))
        data1_b3[cache_write_index] <= cache_write_data[31:24];

    always @(posedge clk) begin
        if (metadata_initializing) begin
            valid_array0[metadata_index] <= 1'b0;
            valid_array1[metadata_index] <= 1'b0;
            lru_array[metadata_index] <= 1'b0;
        end else if (!rst && !clear_fault) begin
        if (wb_push || local_success) begin
            if (hit0) begin
                lru_array[index] <= 1'b1;
            end else if (hit1) begin
                lru_array[index] <= 1'b0;
            end else if (cpu_wea == 4'b1111) begin
                if (!victim_way) begin
                    valid_array0[index] <= 1'b1;
                    tag_array0[index] <= tag;
                    lru_array[index] <= 1'b1;
                end else begin
                    valid_array1[index] <= 1'b1;
                    tag_array1[index] <= tag;
                    lru_array[index] <= 1'b0;
                end
            end
        end else if (cache_refill_write) begin
            if (fill_hit0) begin
                lru_array[fill_index] <= 1'b1;
            end else if (fill_hit1) begin
                lru_array[fill_index] <= 1'b0;
            end else if (!fill_victim) begin
                valid_array0[fill_index] <= 1'b1;
                tag_array0[fill_index] <= fill_tag;
                lru_array[fill_index] <= 1'b1;
            end else begin
                valid_array1[fill_index] <= 1'b1;
                tag_array1[fill_index] <= fill_tag;
                lru_array[fill_index] <= 1'b0;
            end
        end else if (cpu_req && cpu_read && hit) begin
            lru_array[index] <= hit0 ? 1'b1 : 1'b0;
        end
        end
    end
endmodule

// Full five-channel, single-ID AXI target for the synchronous data BRAM.
// Reads support four-beat WRAP bursts; writes are single beat with byte strobes.
module AXI_RAM_TARGET #(parameter LOCAL_WRITE_ACK = 0, parameter LOCAL_SHARED_WRITE_DATA = 0,
 parameter SHARED_REQUEST_ADDRESS = 0, parameter REGISTER_WRITES = 0) (
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
    output wire [3:0] ram_wea, input wire [31:0] ram_data,
    output wire write_pending
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
    assign arready = !rst && !write_pending && !read_active && !aw_saved && !w_saved &&
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

    wire [15:0] qualified_ram_addr = local_fire ? local_addr[17:2] :
        (write_commit ? write_word : memory_word);
    // In the precise-store CPU integration the live AW/AR/local addresses
    // share one request payload. Saved AW ownership overrides that payload.
    // Address preparation need not wait for the late acceptance controls;
    // byte-write authorization and AXI/local handshakes remain unchanged.
    wire [15:0] request_ram_addr = SHARED_REQUEST_ADDRESS ?
        (read_active ? memory_word : (aw_saved ? saved_aw_word : awaddr[17:2])) :
        qualified_ram_addr;
    // synthesis translate_off
    always @(posedge clk) if(!rst && SHARED_REQUEST_ADDRESS &&
        (read_active || ar_fire || local_fire || write_commit)) begin
        if(request_ram_addr !== qualified_ram_addr)
            $fatal(1,"Shared request address contract violated");
    end
    // synthesis translate_on
    // CPU_top binds local_data and live AXI data to the same store payload.
    // Keep the generic independent-input interface as the default.
    wire [31:0] request_ram_data = LOCAL_SHARED_WRITE_DATA ? write_value :
        (local_fire ? local_data : write_value);
    // synthesis translate_off
    always @(posedge clk) if (!rst && LOCAL_SHARED_WRITE_DATA && local_fire) begin
        if (w_saved || wdata !== local_data)
            $fatal(1,"Shared local/AXI write payload contract violated");
    end
    // synthesis translate_on
    wire [3:0] request_ram_mask = local_fire ? (local_error ? 4'b0 : local_mask) :
        ((write_commit && !write_error) ? write_strobe : 4'b0);
    // The internal BRAM has no deferred write error. Validate at admission,
    // then preserve this irrevocable transaction across trap, pause and flush.
    // The single physical port drains one accepted write per clock, including
    // when another write replaces it; a read starts only after the queue empties.
    generate if(REGISTER_WRITES) begin: write_pipeline
        reg valid;
        reg [15:0] address;
        reg [31:0] data;
        reg [3:0] mask;
        always @(posedge clk) begin
            if(rst) valid<=0;
            else valid<=|request_ram_mask;
            address<=request_ram_addr;
            data<=request_ram_data;
            mask<=request_ram_mask;
        end
        assign write_pending=valid;
        assign ram_addr=valid?address:request_ram_addr;
        assign ram_wdata=data;
        assign ram_wea=valid && !rst?mask:4'b0;
        // synthesis translate_off
        always @(posedge clk) if(!rst && valid && read_active)
            $fatal(1,"RAM write pipeline overlaps an active physical read");
        // synthesis translate_on
    end else begin: direct_writes
        assign write_pending=1'b0;
        assign ram_addr=request_ram_addr;
        assign ram_wdata=request_ram_data;
        assign ram_wea=request_ram_mask;
    end endgenerate
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

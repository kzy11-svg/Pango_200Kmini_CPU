// Passive PMU. Event ordering/meaning belongs to the producer.
// All event fields and sample_valid must describe the same registered sample.
module R2_PMU #(
 parameter integer COUNTER_BITS=32,
 parameter integer SNAPSHOT_LOG2=6
)(
 input wire clk,rst,
 input wire sample_valid,
 input wire [31:0] event_increment,
 output reg snapshot_valid,
 output reg [7:0] epoch,
 output reg [3:0] read_index,
 output reg [31:0] snapshot_value,
 output reg snapshot_overflow,
 output wire [31:0] live_cycles,
 output wire [31:0] live_retired
);
 reg [COUNTER_BITS-1:0] counter[0:15];
 reg [15:0] overflow;
 reg [COUNTER_BITS-1:0] snapshot[0:15];
 reg [15:0] saved_overflow;
 reg [SNAPSHOT_LOG2-1:0] sample_count;
 wire capture=sample_valid && (&sample_count);
 wire [3:0] next_read_index=read_index+4'd1;
 wire [COUNTER_BITS:0] next_sum[0:15];
 wire [15:0] next_overflow;

 assign live_cycles=counter[0];
 assign live_retired=counter[2];

 genvar g;
 generate for(g=0;g<16;g=g+1)begin: counts
  // This single adder feeds both the live and snapshot banks.
  assign next_sum[g]={1'b0,counter[g]}+
   {{(COUNTER_BITS-1){1'b0}},event_increment[2*g+:2]};
  assign next_overflow[g]=overflow[g] | next_sum[g][COUNTER_BITS];
  always @(posedge clk)begin
   if(rst)begin counter[g]<=0;overflow[g]<=0;end
   else if(sample_valid)begin
    counter[g]<=next_sum[g][COUNTER_BITS-1:0];
    overflow[g]<=next_overflow[g];
   end
   // Payload has no reset; snapshot_valid owns its visibility.
   if(!rst && capture)snapshot[g]<=next_sum[g][COUNTER_BITS-1:0];
  end
 end endgenerate

 always @(posedge clk)begin
  if(!rst && capture)saved_overflow<=next_overflow;
  if(rst)begin
   sample_count<=0;snapshot_valid<=0;epoch<=0;read_index<=0;
  end else begin
   if(sample_valid)sample_count<=sample_count+1'b1;
   if(capture)begin
    snapshot_valid<=1;epoch<=epoch+1'b1;read_index<=0;
    // Align the new epoch, page index, value and overflow on this edge.
    // Reading the old snapshot bank here would expose a mixed epoch.
    snapshot_value<=next_sum[0][COUNTER_BITS-1:0];
    snapshot_overflow<=next_overflow[0];
   end else if(snapshot_valid)begin
    read_index<=next_read_index;
    snapshot_value<=snapshot[next_read_index];
    snapshot_overflow<=saved_overflow[next_read_index];
   end
  end
 end

 // synthesis translate_off
 initial begin
  if(COUNTER_BITS<1 || COUNTER_BITS>32)$fatal(1,"COUNTER_BITS must be 1..32");
  if(SNAPSHOT_LOG2<1)$fatal(1,"SNAPSHOT_LOG2 must be positive");
 end
 // synthesis translate_on
endmodule

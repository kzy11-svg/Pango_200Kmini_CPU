// Generic RV32 Zbc carry-less multiply, four registered compute steps.
module CLMUL_UNIT #(parameter CHUNK_BITS=8)(
 input wire clk,rst,enable,cancel,
 input wire req_valid,output wire req_ready,
 input wire [31:0] req_a,req_b,input wire [1:0] req_op,
 output wire busy,output reg rsp_valid,input wire rsp_ready,
 output reg [31:0] rsp_result
);
 localparam STEPS=32/CHUNK_BITS;
 reg [31:0] a_q,b_q;reg [63:0] accumulator;reg [1:0] op_q;
 reg [$clog2(STEPS+1)-1:0] remaining;
 wire [CHUNK_BITS-1:0] high_chunk=b_q[31-:CHUNK_BITS];
 wire [63:0] xor_tree[1:2*CHUNK_BITS-1];
 genvar k;
 generate
  for(k=0;k<CHUNK_BITS;k=k+1)begin:product_terms
   assign xor_tree[CHUNK_BITS+k]=({32'b0,a_q}<<k)&{64{high_chunk[k]}};
  end
  for(k=1;k<CHUNK_BITS;k=k+1)begin:balanced_reduction
   assign xor_tree[k]=xor_tree[2*k]^xor_tree[2*k+1];
  end
 endgenerate
 wire [63:0] accumulator_next=(accumulator<<CHUNK_BITS)^xor_tree[1];
 assign busy=remaining!=0;
 assign req_ready=enable&&!rst&&!cancel&&!busy&&(!rsp_valid||rsp_ready);
 always @(posedge clk)begin
  if(rst||cancel)begin
   remaining<=0;rsp_valid<=0;a_q<=0;b_q<=0;accumulator<=0;op_q<=0;rsp_result<=0;
  end else if(enable)begin
   if(rsp_valid&&rsp_ready)rsp_valid<=0;
   if(req_valid&&req_ready)begin
    a_q<=req_a;b_q<=req_b;op_q<=req_op;accumulator<=0;remaining<=STEPS;
   end else if(busy)begin
    accumulator<=accumulator_next;b_q<=b_q<<CHUNK_BITS;remaining<=remaining-1'b1;
    if(remaining==1)begin
     case(op_q)
      0:rsp_result<=accumulator_next[31:0]; // clmul
      1:rsp_result<=accumulator_next[63:32]; // clmulh
      2:rsp_result<=accumulator_next[62:31]; // clmulr
      default:rsp_result<=0;
     endcase
     rsp_valid<=1;
    end
   end
  end
 end
endmodule

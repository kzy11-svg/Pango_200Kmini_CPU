// 2-way shared-tag I-cache, two synchronous word banks, one 32B line fill.
module ICACHE_PAIR #(parameter SET_BITS=6)(
 input clk,rst,cancel,input [12:0] lookup0,lookup1,input [1:0] access_mask,input lookup_valid,
 output [19:0] way_rs0,way_rs1,output [1:0] way_select,way_zero,
 output ready,output [63:0] data,output [33:0] jal,output [33:0] jal_plus4,output [3:0] control,output [5:0] status,output [35:0] branch_relative,output [1:0] fault,
 output req_valid,input req_ready,output [31:0] req_address,
 input rvalid,output rready,input [63:0] rdata,input [33:0] rjal,input rlast,rerror
);
 localparam SETS=1<<SET_BITS, WORDS=SETS*4, TAG_BITS=11-SET_BITS;
 reg [TAG_BITS-1:0] tag0[0:SETS-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg [TAG_BITS-1:0] tag1[0:SETS-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg valid0[0:SETS-1] /* synthesis syn_ramstyle="lut_ram" */;
 reg valid1[0:SETS-1] /* synthesis syn_ramstyle="lut_ram" */;
 // Consecutive fetch lines map to opposite set-parity banks. Each bank
 // has one update port; the younger query wins when both hit one set.
 reg lru_even[0:SETS/2-1],lru_odd[0:SETS/2-1] /* synthesis syn_ramstyle="lut_ram" */;
 // synthesis translate_off
 reg [SETS-1:0] lru;
 // synthesis translate_on
 reg initializing;reg [SET_BITS-1:0] reset_set;
 always @(posedge clk)begin
  if(rst)begin initializing<=1;reset_set<=0;end
  else if(initializing)begin
   if(&reset_set)initializing<=0;
   reset_set<=reset_set+1'b1;
  end
 end

 reg [12:0] query0,query1;
 wire [SET_BITS-1:0] set0=query0[SET_BITS+1:2],set1=query1[SET_BITS+1:2];
 wire [TAG_BITS-1:0] qt0=query0[12:SET_BITS+2],qt1=query1[12:SET_BITS+2];
 // Tags/data retain their synchronous read. Valid RAM is queried from
 // the registered response set, removing late redirect -> RAM -> flag FF.
 // Valid writes only occur in initialization or miss/refill transitions;
 // replay/state exclude those transitions from a legal hit decision.
 // Read tags from the registered response address, alongside valid RAM.
 // Refill replay excludes read/write collisions from a consumable hit.
 // This keeps the late predicted address out of a RAM-to-FF data path.
 wire [TAG_BITS-1:0] tq00=tag0[set0],tq01=tag1[set0],tq10=tag0[set1],tq11=tag1[set1];
 wire vq00=valid0[set0],vq01=valid1[set0],vq10=valid0[set1],vq11=valid1[set1];
 // synthesis translate_off
 reg old_vq00,old_vq01,old_vq10,old_vq11;
 always @(posedge clk)begin
  old_vq00<=valid0[lookup0[SET_BITS+1:2]];old_vq01<=valid1[lookup0[SET_BITS+1:2]];
  old_vq10<=valid0[lookup1[SET_BITS+1:2]];old_vq11<=valid1[lookup1[SET_BITS+1:2]];
 end
 // synthesis translate_on
 // synthesis translate_off
 reg [TAG_BITS-1:0] old_tq00,old_tq01,old_tq10,old_tq11;
 always @(posedge clk)begin
  old_tq00<=tag0[lookup0[SET_BITS+1:2]];old_tq01<=tag1[lookup0[SET_BITS+1:2]];
  old_tq10<=tag0[lookup1[SET_BITS+1:2]];old_tq11<=tag1[lookup1[SET_BITS+1:2]];
 end
 // synthesis translate_on
 wire h00=vq00 && tq00==qt0;
 wire h01=vq01 && tq01==qt0;
 wire h10=vq10 && tq10==qt1;
 wire h11=vq11 && tq11==qt1;
 reg [1:0] state;localparam IDLE=0,REQUEST=1,FILL=2;
 reg [10:0] fill_line,failed_line;
 reg fill_way,fill_bad,failed_valid,replay;
 reg [1:0] beat;
 wire [SET_BITS-1:0] fill_set=fill_line[SET_BITS-1:0];
 wire [TAG_BITS-1:0] fill_tag=fill_line[10:SET_BITS];
 assign fault[0]=failed_valid && query0[12:2]==failed_line && access_mask[0];
 assign fault[1]=failed_valid && query1[12:2]==failed_line && access_mask[1];
 wire ok0=!access_mask[0] || h00 || h01 || fault[0];
 wire ok1=!access_mask[1] || h10 || h11 || fault[1];
 assign ready=lookup_valid && !initializing && state==IDLE && !replay && ok0 && ok1;
 wire [10:0] miss_line=!ok0?query0[12:2]:query1[12:2];
 wire [SET_BITS-1:0] miss_set=miss_line[SET_BITS-1:0];
 assign req_valid=state==REQUEST && !rst;
 assign req_address={16'h8000,fill_line,5'b0};
 assign rready=state==FILL && !rst;
 wire fill_fire=rvalid && rready;
 wire bad_beat=rerror || (rlast!=(beat==3));
 wire [SET_BITS+1:0] fill_index={fill_set,beat};
 genvar b;
 generate for(b=0;b<2;b=b+1)begin:bank
  reg [71:0] way0[0:WORDS-1] /* synthesis syn_ramstyle="block_ram" */;
  reg [71:0] way1[0:WORDS-1] /* synthesis syn_ramstyle="block_ram" */;
  reg [71:0] read0,read1;
  wire [SET_BITS+1:0] index=(b==0)?lookup0[SET_BITS+1:0]:lookup1[SET_BITS+1:0];
  // Decode only on refill: metadata shares the existing data RAM latency.
  wire [31:0] fill_inst=rdata[b*32+:32];
  wire fill_control=fill_inst[6:0]==7'h63 || fill_inst[6:0]==7'h67 || fill_inst[6:0]==7'h6f;
  wire fill_return=fill_inst[6:0]==7'h67 && fill_inst[14:12]==0 &&
   (fill_inst[19:15]==1 || fill_inst[19:15]==5) &&
   !(fill_inst[11:7]==1 || fill_inst[11:7]==5) && fill_inst[31:20]==0;
  // Signed relative target covers -4096..69631, including both edges
  // of resident ROM. It is exact even for misaligned branch targets.
  wire [17:0] fill_branch_relative={2'b0,fill_line,beat,(b==1),2'b00}+
   {{5{fill_inst[31]}},fill_inst[31],fill_inst[7],fill_inst[30:25],fill_inst[11:8],1'b0};
  wire fill_illegal,fill_ecall,fill_ebreak;
  JFIX_OOO_DECODE refill_status(.inst(fill_inst),.illegal(fill_illegal),.ecall(fill_ecall),.ebreak(fill_ebreak));
  always @(posedge clk)begin
   read0<=way0[index];read1<=way1[index];
   if(fill_fire && !rerror)begin
    if(!fill_way)way0[fill_index]<={fill_branch_relative,fill_ebreak,fill_ecall,fill_illegal,fill_return,fill_control,rjal[b*17+:17],rdata[b*32+:32]};
    else way1[fill_index]<={fill_branch_relative,fill_ebreak,fill_ecall,fill_illegal,fill_return,fill_control,rjal[b*17+:17],rdata[b*32+:32]};
   end
  end
  wire use1=b==0?h01:h11;
  // Independent synchronous-way payloads; tag hit selects only after rename.
  assign way_rs0[b*10+:10]={read0[24:20],read0[19:15]};
  assign way_rs1[b*10+:10]={read1[24:20],read1[19:15]};
  assign way_select[b]=use1;
  assign way_zero[b]=fault[b];
  wire [71:0] value=use1?read1:read0;
  assign data[b*32+:32]=fault[b]?32'h13:value[31:0];
  assign jal[b*17+:17]=fault[b]?17'b0:value[48:32];
  // Compute each candidate's direct-JAL target+4 before the late way hit.
  // The 17th bit retains carry out of the original 16-bit ROM target.
  wire [16:0] way0_jal4={1'b0,read0[47:32]}+17'd4;
  wire [16:0] way1_jal4={1'b0,read1[47:32]}+17'd4;
  assign jal_plus4[b*17+:17]=fault[b]?17'b0:(use1?way1_jal4:way0_jal4);
  assign control[b*2+:2]=fault[b]?2'b0:value[50:49];
  assign status[b*3+:3]=fault[b]?3'b0:value[53:51];
  assign branch_relative[b*18+:18]=value[71:54];
 end endgenerate

 // Reset is a bounded sweep, so valid storage remains RAM rather than 512
 // synchronously cleared flops. No request may escape before sweep completion.
 // synthesis translate_off
 always @(posedge clk)if(!rst && !initializing && state==IDLE && !replay && lookup_valid)
  begin
  if({vq00,vq01,vq10,vq11}!=={old_vq00,old_vq01,old_vq10,old_vq11})
   $fatal(1,"Response-set valid read changed ICache hit decision");
  if((vq00 && tq00!==old_tq00) || (vq01 && tq01!==old_tq01) ||
     (vq10 && tq10!==old_tq10) || (vq11 && tq11!==old_tq11))
   $fatal(1,"Response-set tag read changed a valid ICache way");
 end
 // synthesis translate_on
 wire invalidate=state==IDLE && !initializing && lookup_valid && !cancel && !replay && (!ok0 || !ok1);
 wire install=state==FILL && fill_fire && rlast && !fill_bad && !bad_beat;
 wire miss_lru=miss_set[0]?lru_odd[miss_set[SET_BITS-1:1]]:lru_even[miss_set[SET_BITS-1:1]];
 wire invalidate_way=!valid0[miss_set]?0:!valid1[miss_set]?1:miss_lru;
 wire touch0=state==IDLE && !initializing && lookup_valid && !cancel && !replay && access_mask[0] && (h00 || h01);
 wire touch1=state==IDLE && !initializing && lookup_valid && !cancel && !replay && access_mask[1] && (h10 || h11);
 always @(posedge clk)if(!rst)begin
  if(initializing)begin
   if(!reset_set[0])lru_even[reset_set[SET_BITS-1:1]]<=0;
   else lru_odd[reset_set[SET_BITS-1:1]]<=0;
  end else if(state==IDLE)begin
   if(touch1 && !set1[0])lru_even[set1[SET_BITS-1:1]]<=h10;
   else if(touch0 && !set0[0])lru_even[set0[SET_BITS-1:1]]<=h00;
   if(touch1 && set1[0])lru_odd[set1[SET_BITS-1:1]]<=h10;
   else if(touch0 && set0[0])lru_odd[set0[SET_BITS-1:1]]<=h00;
  end else if(install)begin
   if(!fill_set[0])lru_even[fill_set[SET_BITS-1:1]]<=!fill_way;
   else lru_odd[fill_set[SET_BITS-1:1]]<=!fill_way;
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(!rst && !initializing)begin
  if(invalidate && miss_lru!==lru[miss_set])$fatal(1,"LRU banking changed replacement");
  if(touch0 && touch1 && set0!=set1 && set0[0]==set1[0])$fatal(1,"Non-consecutive ICache lookup violates parity banking");
 end
 // synthesis translate_on
 always @(posedge clk)if(!rst)begin
  if(initializing)begin valid0[reset_set]<=0;valid1[reset_set]<=0;end
  else begin
   if(invalidate && !invalidate_way)valid0[miss_set]<=0;
   else if(install && !fill_way)valid0[fill_set]<=1;
   if(invalidate && invalidate_way)valid1[miss_set]<=0;
   else if(install && fill_way)valid1[fill_set]<=1;
  end
 end
 always @(posedge clk)begin
  query0<=lookup0;query1<=lookup1;
  if(rst)begin
   // synthesis translate_off
   lru<=0;
   // synthesis translate_on
   state<=IDLE;fill_line<=0;fill_way<=0;
   beat<=0;fill_bad<=0;failed_valid<=0;failed_line<=0;replay<=0;
  end else begin
   replay<=0;
   if(initializing)replay<=1;
   if(cancel)failed_valid<=0;
   if(!initializing && state==IDLE)begin
    if(lookup_valid && !cancel && !replay)begin
     // synthesis translate_off
     if(access_mask[0] && (h00 || h01))lru[set0]<=h00;
     if(access_mask[1] && (h10 || h11))lru[set1]<=h10;
     // synthesis translate_on
     if(!ok0 || !ok1)begin
      fill_line<=miss_line;fill_bad<=0;beat<=0;
      fill_way<=invalidate_way;
      state<=REQUEST;
     end
    end
   end else if(state==REQUEST)begin
    if(req_ready)state<=FILL;
   end else if(fill_fire)begin
    fill_bad<=fill_bad || bad_beat;
    if(rlast)begin
     state<=IDLE;replay<=1;
     if(!fill_bad && !bad_beat)begin
      if(fill_way)begin tag1[fill_set]<=fill_tag;end
      else begin tag0[fill_set]<=fill_tag;end
      // synthesis translate_off
      lru[fill_set]<=!fill_way;
      // synthesis translate_on
     end else if(!cancel && ((access_mask[0] && query0[12:2]==fill_line) ||
                              (access_mask[1] && query1[12:2]==fill_line)))begin
      failed_line<=fill_line;failed_valid<=1;
     end
    end else beat<=beat+1'b1;
   end
  end
 end
endmodule

// Local burst target: a registered request, four 64bit/8-byte beats.
// Both synchronous ROM banks advance together; payload stays stable if stalled.
module ICACHE_ROM_BURST(input clk,rst,input req_valid,output req_ready,
 input [31:0] req_address,output rvalid,input rready,output rlast,rerror,
 output [12:0] rom_address);
 reg active,bad;reg [12:0] address;reg [1:0] beat;
 assign req_ready=!rst && !active;
 assign rvalid=active;assign rlast=beat==3;assign rerror=bad;
 assign rom_address=active?((rready && !rlast)?address+13'd1:address):req_address[15:3];
 always @(posedge clk)begin
  if(rst)begin active<=0;bad<=0;address<=0;beat<=0;end
  else if(req_valid && req_ready)begin
   active<=1;bad<=req_address[31:16]!=16'h8000 || |req_address[4:0];
   address<=req_address[15:3];beat<=0;
  end else if(active && rready)begin
   if(rlast)active<=0;
   else begin address<=address+1'b1;beat<=beat+1'b1;end
  end
 end
endmodule

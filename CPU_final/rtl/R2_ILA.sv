// Passive Pango debug observer. Inputs must already be locally registered.
// This module has no outputs to CPU state, handshake or reset generation.
module R2_ILA (
    input wire clk,
    input wire resetn,
    input wire [255:0] data_q,
    input wire [15:0] flags_q
);
`ifdef R2_DEBUG_SIM_STUB
// CPU/PMU functional simulation only. This branch does not simulate JTAG/ILA.
// PDS implementation must NEVER define R2_DEBUG_SIM_STUB.
`else
wire drck, hub_tdi, capt, shift;
wire [4:0] hub_id;
wire [14:0] conf_sel, hub_tdo;
assign hub_tdo[14:1] = 14'b0;
R2_TRACE_HUB u_debug_hub (
    .resetn_i(resetn), .drck_o(drck), .hub_tdi(hub_tdi),
    .capt_o(capt), .shift_o(shift), .conf_sel(conf_sel),
    .id_o(hub_id), .hub_tdo(hub_tdo)
) /* synthesis syn_noprune=1 */;
R2_TRACE_CAPTURE u_debug_capture (
    .drck_in(drck), .hub_tdi(hub_tdi), .id_i(hub_id),
    .capt_i(capt), .shift_i(shift), .conf_sel(conf_sel[0]),
    .hub_tdo(hub_tdo[0]), .clk(clk), .resetn_i(resetn),
    .data_i(data_q), .trig0_i(flags_q)
);
`endif
endmodule

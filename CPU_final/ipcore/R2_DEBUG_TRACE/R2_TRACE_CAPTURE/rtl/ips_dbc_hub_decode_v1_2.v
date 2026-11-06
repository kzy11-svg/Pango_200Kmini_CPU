//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2014 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////
// hub_data_decode module, to get the config info from jtag_hub module
// Called by     :  debug_core
// Modification history
//
//----------------------------------------------------------------------
//
//
 module ips_dbc_hub_decode_v1_2 
 #(
   parameter  NEW_JTAG_IF      = 1,
   parameter INIT_ENABLE       = 0
  )
 (
  input                       h_rstn,
  //interface for JTAG serial configuration
  input                       clk_conf,
  //common configuration interface each user unit
  input                       conf_sel,
  input                       hub_tdi,
  input   [4:0]               id_i,
  input                       capt_i,
  input                       shift_i,
  //interface with sub module unit
  output                      conf_tdi,
  output reg                  conf_rst,
  output reg                  start,  
  output reg  [22:0]          conf_sel_int,
  output reg  [19:0]          conf_rden,
  output [4:0]                conf_id_o,  
  output                      conf_sel_o,   
  output [4:0]                conf_reg_rbo
 )/* synthesis syn_preserve = 1 */;
`pragma protect begin_protected
`pragma protect version=1
`pragma protect author="default"
`pragma protect author_info="default"
`pragma protect encrypt_agent="Synplify encryptP1735.pl"
`pragma protect encrypt_agent_info="Synplify encryptP1735.pl Version 1.1"

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect key_block
c9Mt/TwlYvbJ/ec6V1q9vF4+KOsiW3SmumaJsQScwRFtDGW75gMnOd0+vhcWleZ0h6MiOpKLa31d
wWUCXmsuudDdmtlOh0W7uUewJc1zV6ED3Bb/wCacW/bNvXwyG4QtC/IxizLnZH+tDaFBwkIbosZl
bmU/HlVLnk0jzBYS1S8J8r26bOwex3thcHBAUlo4l9b1V1BAHI2asVvtFa+nbSlZ5Ewl4jYsjuHQ
ySQVrHLQkHEyrZAMGNb+UYGI7XixRnxK4jUrFAgsWwRA0lecK6M2HZ6qSZSjU2wGq0VOxf7rpNJ/
sHSPA0yqWZz+ScMjRajyK7trqdA3FWIxLwklJA==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
KiFXvRPc/7qeTQM8lcNtOa1LCLCr0j1+Mq7IlSvXIHm5DaJekkCElYSQoyi3L+Hs/1bPTt1iKgua
E9wKtkuvLRfF070Ki+nI5QyljmvJEgdciMmpHrTWqyfOAVgfwbb8rPzg/Q1zk9aSO4N3sA9Ve8DV
jglm6BIOjQUf0w5mGxl9+buSyjm22H7gLZO3FNLTriHSEXEAaBk8X6UJYuzaRnVwncbrE8Ivku7c
i17CMR9B9R5toy5d0gYvRSXamZLWtftCnhc5JMID2zlSqXfBKcR5fx3YfpSOyRU7HeBy9/BhjL0l
gaFjhRAd3HvK5cbq7M3m5iXAOc3KiDz9qS9bYQ==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=11136)
`pragma protect data_block
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
I5aMjjpyax+AJjAbonR/7OMuPkNB

`pragma protect end_protected
endmodule     

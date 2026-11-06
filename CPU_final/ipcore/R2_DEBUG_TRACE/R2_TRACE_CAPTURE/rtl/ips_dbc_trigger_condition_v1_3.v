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
// trigger_condition module, set the trigger condition
// Called by     :  debug_core
// Modification history
//change rst intitial value from parameter,2020/06/01
//----------------------------------------------------------------------

module ips_dbc_trigger_condition_v1_3
#(
  parameter NEW_JTAG_IF     = 1,
  parameter  TRIG_PIPELINE             = 0,	    //0~1, EXPERIMENTAL
  parameter  MU_PIPELINE               = 0,	    //0~4, EXPERIMENTAL
  parameter  TRIG0_TO_15_MU            = 1,	    //1~16
  parameter  MAX_SEQ_LEVEL             = 1,	    //1~16
  parameter  TRIG_COND_CHAIN_BIT       = 2,	    //{trig_m0_en,trig_m0_neg...trig_m15_en,trig_m15_neg,trig_neg_whole}
  parameter  INIT_TRIG_COND = 0 
 )
 (
  input                         h_rstn ,
  input [1:0]                   clk_conf_trig ,
  input [1:0]                   rst_conf_trig ,
  input                         conf_sel, 
  input                         conf_tdi, 
  input                         shift_i,
  input [TRIG0_TO_15_MU-1:0]    match,
  output [TRIG0_TO_15_MU-1:0]   trig_mu_neg,         
  output                        trigger,
  input                         conf_rden,
  input [4:0]                   conf_id,
  input                         conf_sel_rd,
  output                        conf_rdlast,
  output                        conf_rdata  
 );

`pragma protect begin_protected
`pragma protect version=1
`pragma protect author="default"
`pragma protect author_info="default"
`pragma protect encrypt_agent="Synplify encryptP1735.pl"
`pragma protect encrypt_agent_info="Synplify encryptP1735.pl Version 1.1"

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect key_block
saCbTN792+ovBRfTK5D1ccbSlFF+2EumYi49VEAIr4ZSnbssC+lRmLQW7QLMoNrrzMJmuo1iLf0Q
26YKldXxTZPSNvMneQJSldLhSOwPE1QURUbjOULmMBU2/NKZceKRfrmJh6MDkPJx8Nq/PPM5mtxy
F1TQZa6W4pudsfkORg69e8nUJr7WiwgUCt903h6XPPnMOYDzqYM3x9C4x+TjJo3X5zEGHmjmuwaT
0mr7aPQrZHzEV3ZBRvk79XTdYMPcBImbSGiYug8VEQ6y0oJIDnomGoEq+Q/9zVSW+jXNJOo4FmA/
u+fqwzwMvN30I1Ks9PlCa7OtVcHVj6HVexfZoA==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
p82SP2wNc4VXoFG0IcZjXUlREU9peUfpFeHk0Gfxw+2LZP4XE8/IyQHshbVl2yJuePoDe18Q1o7p
1AEB44ioajD5x3t8c9a3LuNNBri3QTWtARtte2I2DQxEVIjBpyrLB3m61X1TiTdMeDodIZE+SCKx
DhaeIqOrYXDZqsLMthtJUYFo0kYr4prLBnpi+nTrNfz/12qQ36bwlHFfn6/7yF61BYgGLsSEOdtg
QBLjpGXFZfZcdPwdpr9d99yaNjg2SWfHBfDhQaKthiSPppZT3UU/YJ5nFDl8KZIINfucqiChWHk3
MkHeBlCuYh31YZp+0grGDvvJtjyXxCcfoAmSGA==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=11360)
`pragma protect data_block
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
Jb0IZBodq95Z29zd/EYIWHk=

`pragma protect end_protected
endmodule
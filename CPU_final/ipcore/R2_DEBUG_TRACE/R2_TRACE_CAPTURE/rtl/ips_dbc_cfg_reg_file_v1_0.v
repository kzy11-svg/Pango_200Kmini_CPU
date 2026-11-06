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
//the cfg_reg_file module, which is register file of configuration 
//

  module ips_dbc_cfg_reg_file_v1_0 
  #(
   parameter NEW_JTAG_IF     = 1,
   parameter c_CFG_CHAIN_BIT = 256
   )
  (
   input   rstn,     
   input   cfg_clk,
   input   cfg_cs,
   input [4:0]  conf_id,
   input   [c_CFG_CHAIN_BIT-1:0] cfg_reg_data,
   input   cfg_rden,
   output  reg cfg_rdlast,
   output  reg cfg_rdata    //read latency is one clock cycle
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
a1KlZKRNw+ryEduf6I2ytVZ42k14pKms3IffIc41uz2yE5riIMBYsI2Gdy976g9PWOprTU3PK70g
E1AikvHaejKlrRpOmATZuL+xuXGZ+uudMjedz6Lq3+GXv9yUr7OodARqCQIB7zZ+ZKqA+yYhPany
f+xCBpeudM+q8Bf7vvXerpABUXxW3FvUGg7NN8L1FFfjP2nErtTXHohA3sS0CUEKReAGPX77HKdy
ZjkDQoY1BuhYjlBVVWX1UA7bXkg+Ultlhu/iAkYPJBle+tZLSHcRokj+03Zmt65PAt2HenRUD+KD
BZQ1B8ZZ95rJOi2loH+YAPVTtq9rZag2vrK4dw==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
G6kpuNInJBXiLpoba/eZ6e5VhoqO+LzuFjSAYXW3WnKeb5+x2qNtbbygjEWPvHw0IhLd+aGbcvEY
/lFixfFTh3SfiwQoWKAriT+3nrerUbRCLNSrBfHDT9ONQAGHSIJT9ea1YCqkEZfwtMugwCoTRJfT
S1/+LWlxV8d5MJe3CHNUxfuQoJ58ckAJul48/fQ/UEnrsYWwhv/I6He72X1MXDZPSYS/Ik1DOeoI
3ZAQDM/8c08hJ/j49o9/cgKEnp1jpscyGVMWGj/2K2tGbl8MJK0Px132nOiI4Ugm5iiMY39nAAu7
ALEk42CyaQCYOaryyKF6FGxV73b5Z0hmv+U8mQ==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=1728)
`pragma protect data_block
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
Xs6h0ti+G1jfOKE+xytu0W9u

`pragma protect end_protected
  endmodule
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
//the rd_addr_gen module, it contains tdo_mux_s function 
//
//

module ips_dbc_rd_addr_gen_v1_3
 #(
   parameter  NEW_JTAG_IF = 1,
   parameter  INFO_CHAIN_BIT = 81,                       //the total bit number of information  
   parameter  INFO_CHAIN  = 0,      //the information data
   parameter  DATA_DEPTH     = 9,	                       //the range is 9~17
   parameter  DATA_BIT       = 1,	                       //1~4096   
   parameter  DATA_CHAIN_BIT       = 2,	                 //DATA_BIT+1
   parameter  STATUS_CHAIN_BIT     = 10                  //	DATA_DEPTH +1    
 )
 (
   input                       h_rstn,          //hw resetn from user logic              
   input                       clk_conf,        //jtag clk            
   input                       rst_conf,        //sw rst from jtag_hub            
   input                       clk_trig,   
   input                       info_en,         //sw select to read the info data to tdo ,control[4]            
   input                       status_en,       //sw select to read the status data to tdo, control[5]          
   input                       ramdata_en,      //sw select to read the ram data to tdo,control[6]          
   output reg [DATA_DEPTH-1:0] ram_radr,            
   input  [DATA_DEPTH:0]       status,              
   input  [DATA_BIT:0]         ram_rdata,           
  //add others tdo             
   input  [19:0]               conf_rdlast,
   input  [19:0]               conf_rdata,
   input                       conf_sel,   
   input  [4:0]                conf_id,
   input  [4:0]                conf_reg_rb,
   input                       operation_ind,      
   output reg                  tdo_mux             
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
a3PEZlpzk4jXzm/kW8iptXSp29Pln/YZE9pTtCZIINfbTuzJ8x3qZw0DCHCyFGFMVnPLgHxsbKXr
1806docm8X6xirzOUoy09S4gWdUGbvCpqWsaRJydNOLKzDrmBoqwn0uOeEC95qBGV6BGiB0Hb/5K
OcQZdHyVIjdPkEDm+/VyWLit8qplsK6qYE5hHsZbhypEa3kPepPBTbG+NJRQbLlYs7FW7hWC9NFf
7BRFrF2Z0IfU9di2zF38tT0k5X8jkUk2oVYc84lvLVwF1sW7mjl6ta25jnsD1Fa1CJ8nNadX4RED
WVdkHLw/l+8jn1t4g5siKLVQ+WcYPvRg4inKhA==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
fNTxgF/z2skHH6wSWeuEEo/Ia8EGc8qoyRdww5hqJ/5LxN2T/yQjpQqLNX2cz3KXi6hYhcxGpA64
QlFyD8v0CkOYSwqvifb2rxppsdSL3Sk8iMki87NEfd2Q+8VMhBg9gc+MRuPVyD8efbknrKKrJz14
Q8OfsEMAoM803TBbZ7SKIhNndSpok0QwVnOd7+pOTexdA2q81WIzpxZcR16xj5p7Y+RiCaaLdZuS
Ui/UxPAvDBrtyFIakd8R8Bf7rEzoognUvWZtswgAaaXIqiRA1SWMOaZgdMLpmsjNko2Nbe2UIT6K
n/ZSvZLYqhhqDSWs0yWpd8h/P+vBLVRt/U9Jyw==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=9552)
`pragma protect data_block
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

`pragma protect end_protected
endmodule
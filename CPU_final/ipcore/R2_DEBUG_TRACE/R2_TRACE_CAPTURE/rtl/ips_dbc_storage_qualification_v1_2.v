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
// storage_qualification module, set the storage qualification, include parameter stor_neg_whole
// Called by     :  debug_core
// Modification history
//
//----------------------------------------------------------------------

module ips_dbc_storage_qualification_v1_2
#(
  parameter NEW_JTAG_IF     = 1,
  parameter  STOR_PIPELINE       = 0,    	//0~1, EXPERIMENTAL
  parameter  TRIG0_TO_15_MU      = 1,    	//1~16
  parameter  STOR_QUAL_CHAIN_BIT = 2,    	//{stor_m0_en,stor_m0_neg...stor_m15_en,stor_m15_neg,stor_neg_whole}
  parameter INIT_STOR_QUAL = 0 
 )
(
  input                         h_rstn ,
  input [1:0]                   clk_conf_trig ,
  input [1:0]                   rst_conf_trig ,
  input                         conf_sel      ,
  input                         conf_tdi      ,
  input                         shift_i      ,  
  input [TRIG0_TO_15_MU-1:0]    match         ,
  output                        stor_en       ,
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
4bOf+Ws+y/Y2Qa1F3CSbk38ydHB+boTZV3cCeJ40YMsPtrz55MLJoZmAa0C72eRpEiA8GukxZi76
O+rKiDl5QXVnlAY46mMNVISy9r9DfbzFYqOI/X9f1pkbapjEdifGae/zzKdeVHPH1ODONFlYxf9l
QEvkOYppjNY+4wIo+A0UdTH+kjRXEM/gK19e1fK4beWB9GDClZoX7iILeikmgKpXTu6AMqXb6tRx
HolXxy+6e5KkPnDXb9BiU4+tZcpUOzRJlO7h1ENRb3juDqLSnYwOBFypHrXtAeDJ9S8yRJ8uiIJg
DN+qgjv6f/T5h/et+kt2uXpLjfqZhVF1zTJlLQ==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
qOhekyDzVMRGxnNAl0E9HTxNQytqXwhalxph03+Zf5y79J8Gj2RRZkZ+1IfK/SzPsL3QmHU4n23q
ioD2zzKonRoZX96qkfjj6/HGNxVUrVK/o/fcfjfspYwaQoyh27IYnISKpafVFQBbdP644gTWqPMP
y59YUr85+QUO3LvHAVhfye7HMXIh3i/T+fVTVo497NPyAXuQgHFmekK3msXM8dRu3uDAqoBKFXH+
l2C2SZQJJojwp+gbtsyBqRTx/GSwdZurQw2/vTenQj2K7uU4Ax4oWFYjZAiKerC6fvO0qv/WCi1/
DWehKlS7Vtsfmyq13i6iIvebgFp71GCWgs/fKg==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=5792)
`pragma protect data_block
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

`pragma protect end_protected
endmodule
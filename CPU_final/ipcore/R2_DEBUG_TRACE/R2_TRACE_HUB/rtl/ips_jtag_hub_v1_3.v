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
//the jtag_hub module, it controls to select which debug_core and sub module
//note that one FPGA only support one jtag_hub
//
module ips_jtag_hub_v1_3
 #(
   parameter  CTRL_PORT_NUM = 1,     //@IPC int 1,15           //the number of usr_app connect with jtag_hub
   parameter  UJTAG_SEL     = 0      //1:use jtagif ;0:use scanchain
 )
 (
  //for user jtagif
   input            urck_in,
   input            utdi_in,
   // for JTAG_interface                        
   input            tdi_in,                    //TDI for user data register;
   output           tdo_out,                   //TDO for user data register 
   input            reset_dr,	                 //active high reset when TAP state in e_TEST_LOGIC_RESET state
   input            shift_in,	                 //TAP state in e_SHIFT_DR
   input            update_in,                 //TAP state in e_UPDATE_DR
   input            capture_in,                //TAP state in e_CAPTURE_DR
   input            sel_in,                    //user data register is selected
   input            drck_in,                   //TCK for user data register
   input            h_rstn ,                   //hw reset from user logic device, active low.    
  // for user_app interface(debug_core,etc)
   output           drck_o,                    //transfer TCK to each user_app
   output           conf_tdi,                  //transfer TDI to each user_app
   output reg [15:0]conf_sel,                  //select config module which indicated by ID  
   output reg [4:0] id_o,                      //ID number indication
   output           capt_o,                    //capture
   output           shift_d,                    //shift_in delay 1 clk
   input     [15:0] hub_tdo                    //read back signal from each user_app

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
wpw0xKWVnby+yti2dez2KoiF0f3po8tVoPIWxG1ypY6SEN+0eAqCJFbBfdiLwSUTxTAeV+4NZL13
f8RHWL8+wA30Cxi/am7sErwa1oRirBTWRK4/XmF6vyacAcZf622kAz9RW9Y/IRzboXwzJahTlfV7
PPvQhhuPiDo+xEY6xPl5OWNJU+ktNaCVU+Ti8u0Pyj++1RQdzuFh0nvkmU97nTwORs1VVKYaBXDq
WyRMR/QdgslCM7Kfwf1oXtnHajRawj6OG9dqkIO+w/Cyp3ZPPYlV1LBbvuUxpWd/3AUfKQcC7vx4
gqFhA0eybUwIxNXRIT383tO44xXVkO3pLIcFNQ==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
jM9H/mFcp3lV03sr669/QhXxHIf6s1tt8Jo165e/uvY5KYuJU9Dtea713TJixAMelKZ1Fku48eT0
21nJRXokmQwlgDoYMmacucOo1EVfGhALKEStCAcqrBm8Cpa7DmILflq7Qn3UtBvBuY9XtJN9tIdx
8NXb7hZE1ZKJjNuMi2PRfIncS/JS2hifhCF6OlkNfYSW7eILh1DzIHXiSoRivR37xlBnEDyj7T7T
iJm1v62qQy/ukH4DbSE67KS7UdhL7ITCkBlxn3wVZkoO1yo5Ncm1Rb+VGDIz4GIGI8IsFcFHab6X
iAtzxV6pFRctL0qjqxGBwTetXIuNBb8NCsX4RQ==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=11296)
`pragma protect data_block
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
2THa5r5qV1Kunw==

`pragma protect end_protected
endmodule

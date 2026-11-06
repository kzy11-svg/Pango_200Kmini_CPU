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
//the data_capture_memory module
// Called by     :  debug_core
// Modification history
//
//----------------------------------------------------------------------

module ips_dbc_data_capture_mem_v1_1
#(
 parameter  MEM_STYLE  = 0,
 parameter  DATA_DEPTH = 9,
 parameter  DATA_WIDTH = 8
 )
(
 input                   rdclock  ,
 input                   wrclock  ,
 input  [DATA_DEPTH-1:0] rdaddress,
 output reg [DATA_WIDTH-1:0] q        ,
 input                   wren     ,
 input  [DATA_DEPTH-1:0] wraddress,
 input  [DATA_WIDTH-1:0] data     
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
B3bjpcklocl6l34gUtxdXAZi5z0+eXy4h9TW/e8lV+BGxKRpQqK5ml0STzJTXAvMOJWtEpFH3Mj2
EsXoukEJgCx/Xvi8DDKYAqa8R+n37GHBn6Cx59exj02G1+fCJekHR/sfMQkn8R9Ut7sOJo3HBht2
AhS/Jd4prcDbyVVqR50Txa3ufpMwM8yDab9McodpkoS6POvYXusMPeMxFUIsVKN/q3IlBMiYjlXN
R2SgB1n6u1h5Y5HxrPqtwYpZ/d0jLTTBkko1AxP+gk0U12z4h38H7ycSzYhkEZlw3ZXVFjYZC0Po
9v+FCY056G+rLVoRFv9LbxTmG4WaF19RNv+VSQ==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
DkDSJ2IxAh3sP7P/D1RgW2BGDGzwlVRbY1ze8TYxU400KaeL4lDZaJraai+iQjYmMgiiJ7UsLxBh
8go/cJmwpPzX3Ny6bFUWBSNjhbypwUwQKgeHdvyUrMjH2h+pvejJDKfAdyJix3NHuEvDbmqLkESk
HX8USBYO1sCbCEG413JG11pMJJtBlDCBIQVCYcb3XzmZCZcc8MY7eJnntW2VWAxaW51vSQShxunw
OsdWnnBBk42D53l/SPI6ed5uHz37IuzbScN5ux9OU53PwndTgFVfOEBDxJMgjPoawyytxuHuQiKg
Y1Alcb1PtfxE/+YZP7eU2//T487iwT6XuNsiUw==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=1360)
`pragma protect data_block
ea6gzqXNNCT2RzUAwY8IXEIRlyKzHat777UPZp5JMZbGbUnTs/BHqJGvi60ZIJizkrB2reltjHs0
lgCASpp9cYIKO4JiKVXicCOGe6YtzuacqyNk6MK1UU7O+BBi0IkOPuA/b9EMN+zLHG/+bVUO2vpI
8TTXNQAOm/ZtJJJKU+njE0R2tEWvMHRe9rS9yT5i6NX02amPqFfZ+Ebtm2jc86tDZC9/b9tyUMtG
lzB0HpgwYFYciMTglzDxr+jtoY3f5PRBe9XgKBsaNfD9pLLmo7edVVpjhHkH5DnutKS+doHaZ544
LBEeuUt8NJBMfLJGoJ0tEFxYA/bzxWubDqZ2Zp+2j9cKdlamU/wv8Ff0fMe0iNGucEev/R9J0wMf
gngodqhkq4PC5ihw5DQffGaKFpdXT+6CeQNUaF7iz/iOWKnH0afG5WTnE3hU9dD2nlrhslJdocnk
drd3w18ci2XNOad0uK5I0DS+YQLYAfe96VzTS2QIqPwjExrFK8mYQSOIq0GPqBdzipdVqv67i5HZ
eUpTPbrGZMxezYiLqFEzrKecRZGIAD7WBgrKUZVtAHxAADe8OlNh681XqYmSYQJUI6keUBlQz0GA
55DbhrS4gFApBGzOk6sOay3D52XTSc5CT/Sa6/wwkOX+LiEHzzFqB6AiDb37IcJbPazNO8En1pOH
HQUNTcZdUZ31ayq/XTdcIIWlaAByp1i1vuYjV6bPwxd4b1yDW4qxDpFuPIh9HZdePxQxAJJZV6sZ
s68QrA575m7dljj3H0ITuT7Tcl71FZbFb18B55LuwdTV222zQH3vFq4q1DLyuEogoh/VdI4GAe/M
NPUBfY1n+KZQqKpIauoE3dL3YSZ3pIJHRSi5P6Ceqc1kgRHtHZEVcNHC3vr2ZJ00SAvG//Sln2MR
ZyLXFfv8BWe4b6pETKgRpr+G/opAahOiBn78bj3NJcvEM4bhGGEfr6MadbH4ALiXD6ODn+dWCiHF
Y0Cax+JkDz6TVnb5bg77jQN9Xp06gZAV6YEfd3NRsgcmS1HzN2N1ywtDoiDul609zPUo6MuB0RH2
PRF8JQHwWjTQrsnUFUGwg/KNXOBr0MUVI4sZqTMsetKCyC9Z2a9hYmWu5LTepfxH/w48NfcVYK/z
2V+TMLcyObgs/eSDaZj7D5Kn8txfxjt+vWEPtxhszhNUmbeDit41IGKysgKm6jU8FF5RKBi0YlZr
JTAmAnvXBus8AItCIkZOtXUHi1CiKky7LNF4R1Y0a6xC8NhQALIDujVDbcgY8wOVyJ73EGiwgT0s
TIaB5Ux7d6NYzlf7aEzs29tqeMPxh//VPDhoVUdQMHI+ZpUZtguQswBjZEcYryE9JM457njdpxkM
3H4MzCkbWDyCg9ZqZLMpbgrm4oHNy95oBhYUsH5dwVRc84lWBlDHYYyOX6xv5SzUuO0MjNlAbzT9
BW22U7xsJsU9uhqCa+6o0Qs/M2K2AjxtXkfZJezryrHcEe1mbqt89jVOyIFRjA6MJmPp7/67Dw5U
va+y2tRWVGF7/GzG1dogd90jiv0RWN1BFxh9LvqLYqRrf3yRG4sIb3i6TLqCHXk1cadLW7CA512x
VHIMtopmgVXh8pbUMvC4bvoeNZBmOymUG7AQASy2LUdh8gz7VZ3nyK7nyPctsARXsh0THXk/josJ
/t/pTdhy19cwJ7Pvld78BLqyPNB2662hOZiEn6+HuCtHSpFPMhaDYySbknQNw+mO3hi+Ay/oqmRd
kSd8F5ZK/GKIP8CGWR+2hLxG2JfPn6t0/Yfm4D+9erDxfhyZiDJbgSwEmLlPWlgeuA==

`pragma protect end_protected
endmodule
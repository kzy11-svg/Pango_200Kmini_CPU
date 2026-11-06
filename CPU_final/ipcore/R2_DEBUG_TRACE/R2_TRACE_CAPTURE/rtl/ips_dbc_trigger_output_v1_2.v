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
// trigger_output module, set the trigger out
// Called by     :  debug_core
// Modification history
//----------------------------------------------------------------------

module ips_dbc_trigger_output_v1_2
#(
 parameter NEW_JTAG_IF     = 1,
 parameter  AREA_SPEED = 0,                      //0~5, EXPERIMENTAL
 parameter  TRIG_OUT_CHAIN_BIT = 3,	             //{trig_out_mode}
 parameter INIT_TRIG_OUT = 0 
 )
(
  input                         h_rstn ,
  input                         clk_conf,
  input                         rst_conf,
  input                         conf_sel,
  input                         conf_tdi,
  input                         clk_trig,
  input                         rst_trig,
  input                         trigger ,
  input                         shift_i,  
  output  reg                   trig_out,
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
CHGNvsiqbz0oXaF2i84HNf2k2xknBTiScEr4cPPeFMxHXSHxq50C+kngEsOkzlov8WkuD9mIcmVN
5fKJZsEnnjGuftbTTGbaAHaFUonaELD65cC50PxcHZu+smb0JGBloclqCWbGISTf/h0hUHxq/u7z
1wSjmUUvnP2QtdoYE6BvQ0TA11BZa8Im0KbFZrEyoT8q78UOtf/yRWU1DXfyyNedzt946V+/SPcZ
CYhfL8xVFgjid7KukcKfUNEnRd6Ep3gXUxhtS1syqsUfG2GDiP4YT3c/rxy6v09Myck5OwUop+4S
96T0q8g7ln5bEZBOOYHooDbBEOkEDAZORkt9Bw==

`pragma protect encoding=(enctype="base64", line_length=76, bytes=256)
`pragma protect key_keyowner="Pango Microsystems", key_keyname="PANGO_21", key_method="rsa"
`pragma protect key_block
Uqc+qoZjnAayt3L/dmSFQiT12g/aqrhVI5sMHUpBTtOemrbz3+PkyzMNqBoME3BR6ZoHh2AfmZGb
qrBWr3A2/DZcYmFbTE4Qtcpdnjio/FZaIV9WLPq8oaoMmVu4cqboCNKWCznM1jDtKmNu79iihc2t
bvzSCsQiDK8LbzNHs/l+H8D/uVi2JOKkwu3uKWJllV+Mmdo9FOjbVFMe3cL/Km9HDreUupU6+GuB
oRlrdK6i0Dym9JldX8htbos6pnabEzkF4HAROHUczhznqhyxBtZovRYk6rRQwduyQP/JuYFSyNum
dPOAujjnEYn5QrgI+1dG8xjG3flI1rnCyfDY0Q==

`pragma protect data_method="aes128-cbc"
`pragma protect encoding=(enctype="base64", line_length=76, bytes=3968)
`pragma protect data_block
W4KDEuzRGRSq5rDsFz3xqgvB6kH5TBC2vpjtwkrVIjA6tDTLaLTfV0xWoxfjElRZnlCt+MXUnMjb
QJg7xg9U6O7qHo7Tb7GrW1crci22TRX7zgMV4X15f7ExXpxAuqjwayp7fMAOwi5S+wSGu+xIKDHV
/t96scyKt24EV1X2/Evf5HcziSqsVvNnl0QFdfwW7rSAnyp5lvNZmh8RYUOE2cAyANasOycLlQAx
IjQ19Su+taQiP5/0cED/kVUtpHjdFDxESMNvYErR4p+/MzqK76f3S3X6tU7bu4cChHl/a6obvDV2
mG+/xdcxXrJPJ5pA4bSxoSDMqFy7H+WNB2IH6UzqZf7fLNiHiEalePSrvJnce5o5Fhg7sykksooU
j8HFSnaOPbB91Yd/zUKBz7U7tCMkGfnkp+2MDomg43dO++J0pFDy/+TIrMCrZ4WgTqQw2rH/Dub8
PVktpyk8bWMXaUPm1gJTK3O4BJBq3m4VH7yeASZa1R2lsKuPItpPvuQ4SuIkp2r9hf+EwLDM6OXj
3Cphot2T7jzOWsDFIxbRkFJiT+/T3Nhw5qUHJZvOTzmSbX12zYFuL+S7VxbVyY+wIFK8MX1Jq/2f
HhL0V2moPiGy/qoGYSIgekeR5gli5NJHqiw+WRieaJV5RnZDCKynUrtkc4pZu8ChMZeu0IiV+/qx
tQ7ApyYJAX1LoZkt8JDZ5WiotOgU3hgLww8ocimhe4K3SAH91l72f8WUgHFoK24CWgXQKNPtYLMd
SuTR8uYc995PU2tJ47d66Pq+YOliDarhiEIHfl5JlA0PifEh8G1d1zRjSvpnDruw+kArDoIb4HTI
msBmZs8lB4NlX9ivTIHlkpgJQvXm7HDTIfWK4t7kJyY2NpwBmC9eGjcMY/GY5T1ayibpXkxk2xqj
bgzQ5wm3Uny3wgaaiLJmyH4xb4NUgCf7GB9Qrm9pd56uqUbnEJjEa00lQVLPiRuOTndbQBiqdipz
QBuMqsDzzQ6lDkH6rS9jcUg7ARlxT0FCFg/h+/liaUmiW44YJerg6ho3z0uDt1+baLNbFO4bIqaL
aGTVe8OkjkWsxVIpCFl+IZ+0zKr5ch7MZhXf4SJ1+hEJokfWCLLVOkOHbGpknzcUAOMYofHKSWxv
bfoezbvQO2C4PAvNkiVL0gyjJILsdpGcVPY7jxlf6nDBn9NKY5gvpD3PI2ORNfYHJAMVjYlBdx0w
XRkdJn+ZKg2lCAe9GP53PE2DuqPOKY8/wjPBJ5tSJBjSxWlYyo4o0BYyfnpNKKvK+ywbw4QWEAbC
OtQXRDKpaU47c+/iiB9zRJdxXIdoaD3xpXa61OFuHnDJp1i4Uim3wygBomGPh97opWB7f1K9dCZ8
59gehyyfubE/bhYK4seuUPj/4LABupdPzQ40/rvAC00UwKIJ6qc5PsW1hqOEo3xsI5qrWlRSCrtf
y8nq6mAqtg1WNVaDyk4WXxHcLBOnzxWMeE7Nd+4yu39mqdCScbbRz4a3mZARTy6pLSkvToGQCqFZ
xgUVX106nBzwqWbYlvJ0orY1z56cTndYgusZR2zR3W3h1SDL0P+ZpBJnafHvcFRXfrXj5ngDNXXK
yhg2sKNWjbJ3t91emGHUjPmX1cioyoaL65c7tjlPbQ7SfaodUi4k2FtElMYZzGMvbGgvqiR/V51e
yvdXg6d0l1867SiI/fIbiL5crVP1SqpVDgzEQEnbeZK2K9DMXUnfnyB1LDV/H/N5Btn2OttoKqVZ
sh6EcBHpO30SSmrJiQYqIzIPuewgLTGYPnLlJIyZiDF4VChiDYu2L6X6dSyObrub7hJW6zIbx5TH
M0mS7hx9aLlgqh+qdaPP4FtMv0W7KhTXHbS7ils7v6V9WmvmCSoISEAfuYgsN5gjFRk1fkT/jMv1
08sbKp5bpa/2YfucxbvrdPrSNCylVaga9KZwq5FBnIN4aSRf7LEEO6QhuhMLA/n9VSsIs+WscD/W
DbhfMmAoleDkz0nAhKh8fCQDPX5zsVqI4S4dWpSf9z8AdF8kNOeLlNGIj1OLUUznJX2BmQ0fvBhc
ELSZ7t2elK5A0JG3929irqg2T8dN9kRlGZUXvBvzSPNn1sj92UjfALMja8wzi1IOLrnKSPtrImkG
r4pqtEsrp3uT2daodLs5ZxB0mScgrqGDlwZZfzciZUYr0IwKU/557D/ehtGEjpXmGtQjxwTutw3f
GsIws3PVbsbd0JplmZJ1FCcjdCc1IutPubp3vnlVSY8p+l8fNyJ0+joOY15rbYh5fARJQPxiS355
bYNL6nntNknkvq2n6icJPWnJxF7pRCAe3CisZAb95Ug6aF/n4Tn5ij/VAR5roqtoNntgia5vQVez
aqWLuFmB4iN5dxJyFK7KQAssphR8olNYB+cyG3C4ZtiXl86lbM9FrE1oaQA4ySjGkKf3GptFtFaa
875jKl2s6rCgMEo8p8E8a2aAdYXF37q1HenaeIN2y7ebrX552PXzSY03yTpOjcb4RESjSrtR1Rfn
qfwEwQ76p6Jxw0HDzF4DjhUeyiR3D7YJrihF74KhDjtq5NzmEWhG1CkLjI4Wj1raAOOl+d1O4HLl
BygldAGUoQrStWe5BnVmH+HenRIa0fvyqlVfnnFSMSqCVLDoPtetmdZXlvlI+/rPKZwkm/j0U6Ca
3TJIn+AslEUZJj+j0vNdAFRXLpS3RqebsgBm+T6qVZsGEx9lKmTdWIHZeJwpWrukT4gexUmb++KS
AbXrxZf6iA2F6GabldKg8UCyV/K+Jl2l54bbiDXzLoq/P56yXUZJ3MIj65wiie73yG5n0Di005cS
nZu4eMlyBvo39kHJYoqIKzPFrVmbSf3Ut0ZeE4LW+Aan1kMMQcOkdJU0XagIX0o+Vkqw+1Ozui5E
gWn9c845YkcoYvW4XwEqfgYgMM113snnFz+a1lVGQb2Pjsh/MSoJEo8ySKi3zTlzP5Wnbcz46YC5
WzMCJlgR7AjXs5Bs3swl2UZhMEu8xvhFw9tVstAUnZ5ofx/5LBdaHVIYxCQZTsfT5HDZ/oEKyUtj
a0dS/Cw1SsMvZnPKiELDblf/5IN3y5E18waRXEbFArPftchWU2OI/qLURywpNuvNcFE4zZ/RZ6NJ
Y3naDrG4BeLuY4j3hzSkXjcPojzpkmpSxLojt8mNtaIeNByl+AGA3g+lPYZMMOORqCbsa4J/i5TR
cKcFYsOtyesFKLTlG+hScKeRBlkfmlnizgVDSi0iePtVuglpJpNWEUALsuYy+5IiN9mS61Pa2qvF
jcsL2sIqurnWlgR5GHALrr5lIm9Z1b7WucBiwyOyHXUb0mrtZ7q8Q/hKpdTctIKgK3nnNXk1Z1/b
nzIKIyjwdt1bhoy2Ly8KdickRncAAcR3AKj7Yr0E5c4giNrc8TdMG+oEkb4Ai7IvfO8T7DgKsK3W
gogZXTFaRqY6Q16yZuVGHmCCovD65a8iGvj2qhs6LWOjrhXPDud9WiZDhD/7G6BdzzgoeyzmU3Pt
5UrE1+QEZGhRQFnYuauiHgdz5cjBEA6hRbsWDL7B4Zc/Ju/4JY3MAq9pNz9SnRQqWD2SVuxYE7pp
exl0XU7u+QaRL2dNN0IGmw8ItnrsJf07N6CUfJ5EnvC5JEjwN0jMCYtHpyqmo/AkZw0F8OSRh5WI
Jv/20qvpvxQdBMrrPO8HMJWby36EFFnl0D7ypsB5lp02U4ZBwlXKhU8kGLRW9ioHCZxPXqcRDLSW
2K1QHAGTZ9PnO6TFrSo8JaOR8sVym8TuyIU7GwrXgqVUN+KPUCGNGIuLmnoa2+y3YB9cvpqjh+ho
S5XvgC39RDHe7ZZS7Ud9s/+8+jH99lffsnLqmZS90qZ35CMw/f5oDXBsL+ZJEu/qjiQW7thdIQoz
O7bJM5kwGssDq2RetErygWjR4GQIYNjxvPtadjcbcRsmZZpUEOsrSMuG2s33kj9kmjgZUmlKC2O7
PHQOBYy2GV2u3KvwJZtem2r9zff47Ea5zbMQfA06SRcRF6e/7GpyqV/u5G/dCuRZyzS4rk0LRHxZ
EuiUlr2qdFG3u5ViRVQbc5L2O++xgJmkWRvQHpohqOfd6U6O6ZKr1FrtqL6izFwJNLxaUnfZRjtt
nLxplLw4TkwEyQ6w3JLTlDMEGNwVJtyyR0lR/LOZs4f6NT9jvBs4S+rgT+oGVJBoQq7kSuVKiNqo
FVxR8PCvU/e+i+rANaU7VpyHgys1r5YjX0EERxFDMgwdiiIGUBTfD46Ql0yh1GJwzCBZY9lp2g69
dA5ylZgd5I1bUr+0etsXLoBiUD8/oFaOQMO13HEA3IEeDgQYQ7XjCV2J9lXNQKxtJaBL6NvUuvIA
26NcTa7fVnu8d5dTF6V9W/x1SZmAyocTEjd5L5LrEvqINp1JpzZuOFbMSSY5feXZFCyHX90G4ZY6
yN1OfDUDS7oSColBAHjKHi8YgiOVJHTkeNPzYLP5culAecVXP4fDodOn8S0klbRYUPrWOgUDTXD9
Mw0bYH9POcr1WDFq3FXkonEjqN2l26ZY0mLyvC++84f5mUoc9mhcp85SOfuQ6MgzcF4LeEj+pxxE
KwH1DhZOTDW3f7KfailnKyAsmTyWbKsX4iDx9Pr4dqBr7E44+Gd5RbaTpI+I+wuVjYQHfyHZX1W6
4uMLohQn6l+0WN2ZmW55fxv441Nu3Q5vYTFjYQ0y9vjUSKmQNCJWxwRqK0O8/G2NqheIXysrfKCA
jGKzgP3Ru42PlkMX7ZqrayDZRUVlIhKlGYzAIvTGcOY65kDcHWWW9FgN7BnGoe+22dHFjbBEa7fb
DFCrqOBilZGtZOjacTPZ9sBfzvRwohZQ99RSKUV/wWuwsHb39YG/ZkKmNhb3FOOfUktASjVvtSoY
v5uvJ+YbXtEpjFMeV+q/A9KkWMOhs8QVIG4cPW5MtbQKmrREsG7jzmCg4lGF4urAdiKWnsPF8aCK
S5S6rxTaS4fSk7gAmtOMiDUPRtd/5+Bh03tffJ7YrkpARudaSsz19965u45UKrnSNmN2vBEX2zu/
sloyyZOGWN6j7Oki4uqzyf7RQP3mXuBuR6w8NBT4/+ZByQKTm9x00kxwyqI52tq7XSpTDEI8reoX
bNAVOSCf5bOTQFcNMPR4mLkgT060Dng2+WwTuE6I1RZWuXTUcZ+EsW0elBStpsKrlGC5bsbaB5nH
N3A2L/ilnaL6hyWUpjYqmCVF6Q7QmNyB9WspEXNoN3mKmU9Q/HHqlqBAkUX8CRaniRhTF7yHRGQ1
auxWGq/OsJaYFxib+l/IZs0zXEDLJoTGsuzmCV580Uey56w=

`pragma protect end_protected
endmodule
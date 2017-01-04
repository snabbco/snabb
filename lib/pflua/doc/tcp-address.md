# ether[&tcp[0]] = tcp[0]


## BPF

```
Filter failed to compile: ../src/pf/libpcap.lua:66: pcap_compile failed
```


## BPF cross-compiled to Lua

```
Filter failed to compile: ../src/pf/libpcap.lua:66: pcap_compile failed
```


## Direct pflang compilation

```
local lshift = require("bit").lshift
local band = require("bit").band
local cast = require("ffi").cast
return function(P,length)
   if length < 54 then return false end
   if cast("uint16_t*", P+12)[0] ~= 8 then return false end
   if P[23] ~= 6 then return false end
   if band(cast("uint16_t*", P+20)[0],65311) ~= 0 then return false end
   local v1 = lshift(band(P[14],15),2)
   if (v1 + 15) > length then return false end
   local v2 = P[(v1 + 14)]
   return v2 == v2
end
```

## Native pflang compilation

```
7f1405509000  4883FE36          cmp rsi, +0x36
7f1405509004  7C49              jl 0x7f140550904f
7f1405509006  0FB7470C          movzx eax, word [rdi+0xc]
7f140550900a  4883F808          cmp rax, +0x08
7f140550900e  753F              jnz 0x7f140550904f
7f1405509010  0FB64717          movzx eax, byte [rdi+0x17]
7f1405509014  4883F806          cmp rax, +0x06
7f1405509018  7535              jnz 0x7f140550904f
7f140550901a  0FB74714          movzx eax, word [rdi+0x14]
7f140550901e  4881E01FFF0000    and rax, 0xff1f
7f1405509025  4883F800          cmp rax, +0x00
7f1405509029  7524              jnz 0x7f140550904f
7f140550902b  0FB6470E          movzx eax, byte [rdi+0xe]
7f140550902f  4883E00F          and rax, +0x0f
7f1405509033  48C1E002          shl rax, 0x02
7f1405509037  89C1              mov ecx, eax
7f1405509039  4883C10F          add rcx, +0x0f
7f140550903d  4839F1            cmp rcx, rsi
7f1405509040  7F0D              jg 0x7f140550904f
7f1405509042  4883C00E          add rax, +0x0e
7f1405509046  0FB60407          movzx eax, byte [rdi+rax]
7f140550904a  4839C0            cmp rax, rax
7f140550904d  7403              jz 0x7f1405509052
7f140550904f  B000              mov al, 0x0
7f1405509051  C3                ret
7f1405509052  B001              mov al, 0x1
7f1405509054  C3                ret
```


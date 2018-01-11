# ip6 proto 47


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 8
002: A = P[20:1]
003: if (A == 47) goto 7 else goto 4
004: if (A == 44) goto 5 else goto 8
005: A = P[54:1]
006: if (A == 47) goto 7 else goto 8
007: return 65535
008: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L7 end
   if 21 > length then return false end
   A = P[20]
   if (A==47) then goto L6 end
   if not (A==44) then goto L7 end
   if 55 > length then return false end
   A = P[54]
   if not (A==47) then goto L7 end
   ::L6::
   do return true end
   ::L7::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local cast = require("ffi").cast
return function(P,length)
   if length < 54 then return false end
   if cast("uint16_t*", P+12)[0] ~= 56710 then return false end
   local v1 = P[20]
   if v1 == 47 then return true end
   if length < 55 then return false end
   if v1 ~= 44 then return false end
   return P[54] == 47
end
```

## Native pflang compilation

```
7fa374c2d000  4883FE36          cmp rsi, +0x36
7fa374c2d004  7C2D              jl 0x7fa374c2d033
7fa374c2d006  0FB7470C          movzx eax, word [rdi+0xc]
7fa374c2d00a  4881F886DD0000    cmp rax, 0xdd86
7fa374c2d011  7520              jnz 0x7fa374c2d033
7fa374c2d013  0FB64714          movzx eax, byte [rdi+0x14]
7fa374c2d017  4883F82F          cmp rax, +0x2f
7fa374c2d01b  7419              jz 0x7fa374c2d036
7fa374c2d01d  4883FE37          cmp rsi, +0x37
7fa374c2d021  7C10              jl 0x7fa374c2d033
7fa374c2d023  4883F82C          cmp rax, +0x2c
7fa374c2d027  750A              jnz 0x7fa374c2d033
7fa374c2d029  0FB64736          movzx eax, byte [rdi+0x36]
7fa374c2d02d  4883F82F          cmp rax, +0x2f
7fa374c2d031  7403              jz 0x7fa374c2d036
7fa374c2d033  B000              mov al, 0x0
7fa374c2d035  C3                ret
7fa374c2d036  B001              mov al, 0x1
7fa374c2d038  C3                ret
```


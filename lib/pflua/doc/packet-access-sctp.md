# sctp[8] < 8


## BPF

```
000: A = P[12:2]
001: if (A == 2048) goto 2 else goto 10
002: A = P[23:1]
003: if (A == 132) goto 4 else goto 10
004: A = P[20:2]
005: if (A & 8191 != 0) goto 10 else goto 6
006: X = (P[14:1] & 0xF) << 2
007: A = P[X+22:1]
008: if (A >= 8) goto 10 else goto 9
009: return 65535
010: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   local X = 0
   local T = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==2048) then goto L9 end
   if 24 > length then return false end
   A = P[23]
   if not (A==132) then goto L9 end
   if 22 > length then return false end
   A = bit.bor(bit.lshift(P[20], 8), P[20+1])
   if not (bit.band(A, 8191)==0) then goto L9 end
   if 14 >= length then return false end
   X = bit.lshift(bit.band(P[14], 15), 2)
   T = bit.tobit((X+22))
   if T < 0 or T + 1 > length then return false end
   A = P[T]
   if (runtime_u32(A)>=8) then goto L9 end
   do return true end
   ::L9::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local lshift = require("bit").lshift
local band = require("bit").band
local cast = require("ffi").cast
return function(P,length)
   if length < 46 then return false end
   if cast("uint16_t*", P+12)[0] ~= 8 then return false end
   if P[23] ~= 132 then return false end
   if band(cast("uint16_t*", P+20)[0],65311) ~= 0 then return false end
   local v1 = lshift(band(P[14],15),2)
   if (v1 + 23) > length then return false end
   return P[(v1 + 22)] < 8
end
```

## Native pflang compilation

```
7ff8b99b3000  4883FE2E          cmp rsi, +0x2e
7ff8b99b3004  7C4D              jl 0x7ff8b99b3053
7ff8b99b3006  0FB7470C          movzx eax, word [rdi+0xc]
7ff8b99b300a  4883F808          cmp rax, +0x08
7ff8b99b300e  7543              jnz 0x7ff8b99b3053
7ff8b99b3010  0FB64717          movzx eax, byte [rdi+0x17]
7ff8b99b3014  4881F884000000    cmp rax, 0x84
7ff8b99b301b  7536              jnz 0x7ff8b99b3053
7ff8b99b301d  0FB74714          movzx eax, word [rdi+0x14]
7ff8b99b3021  4881E01FFF0000    and rax, 0xff1f
7ff8b99b3028  4883F800          cmp rax, +0x00
7ff8b99b302c  7525              jnz 0x7ff8b99b3053
7ff8b99b302e  0FB6470E          movzx eax, byte [rdi+0xe]
7ff8b99b3032  4883E00F          and rax, +0x0f
7ff8b99b3036  48C1E002          shl rax, 0x02
7ff8b99b303a  89C1              mov ecx, eax
7ff8b99b303c  4883C117          add rcx, +0x17
7ff8b99b3040  4839F1            cmp rcx, rsi
7ff8b99b3043  7F0E              jg 0x7ff8b99b3053
7ff8b99b3045  4883C016          add rax, +0x16
7ff8b99b3049  0FB60407          movzx eax, byte [rdi+rax]
7ff8b99b304d  4883F808          cmp rax, +0x08
7ff8b99b3051  7C03              jl 0x7ff8b99b3056
7ff8b99b3053  B000              mov al, 0x0
7ff8b99b3055  C3                ret
7ff8b99b3056  B001              mov al, 0x1
7ff8b99b3058  C3                ret
```


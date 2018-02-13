# pim[8] < 8


## BPF

```
000: A = P[12:2]
001: if (A == 2048) goto 2 else goto 10
002: A = P[23:1]
003: if (A == 103) goto 4 else goto 10
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
   if not (A==103) then goto L9 end
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
   if length < 38 then return false end
   if cast("uint16_t*", P+12)[0] ~= 8 then return false end
   if P[23] ~= 103 then return false end
   if band(cast("uint16_t*", P+20)[0],65311) ~= 0 then return false end
   local v1 = lshift(band(P[14],15),2)
   if (v1 + 23) > length then return false end
   return P[(v1 + 22)] < 8
end
```

## Native pflang compilation

```
7fdf62f4e000  4883FE26          cmp rsi, +0x26
7fdf62f4e004  7C4A              jl 0x7fdf62f4e050
7fdf62f4e006  0FB7470C          movzx eax, word [rdi+0xc]
7fdf62f4e00a  4883F808          cmp rax, +0x08
7fdf62f4e00e  7540              jnz 0x7fdf62f4e050
7fdf62f4e010  0FB64717          movzx eax, byte [rdi+0x17]
7fdf62f4e014  4883F867          cmp rax, +0x67
7fdf62f4e018  7536              jnz 0x7fdf62f4e050
7fdf62f4e01a  0FB74714          movzx eax, word [rdi+0x14]
7fdf62f4e01e  4881E01FFF0000    and rax, 0xff1f
7fdf62f4e025  4883F800          cmp rax, +0x00
7fdf62f4e029  7525              jnz 0x7fdf62f4e050
7fdf62f4e02b  0FB6470E          movzx eax, byte [rdi+0xe]
7fdf62f4e02f  4883E00F          and rax, +0x0f
7fdf62f4e033  48C1E002          shl rax, 0x02
7fdf62f4e037  89C1              mov ecx, eax
7fdf62f4e039  4883C117          add rcx, +0x17
7fdf62f4e03d  4839F1            cmp rcx, rsi
7fdf62f4e040  7F0E              jg 0x7fdf62f4e050
7fdf62f4e042  4883C016          add rax, +0x16
7fdf62f4e046  0FB60407          movzx eax, byte [rdi+rax]
7fdf62f4e04a  4883F808          cmp rax, +0x08
7fdf62f4e04e  7C03              jl 0x7fdf62f4e053
7fdf62f4e050  B000              mov al, 0x0
7fdf62f4e052  C3                ret
7fdf62f4e053  B001              mov al, 0x1
7fdf62f4e055  C3                ret
```


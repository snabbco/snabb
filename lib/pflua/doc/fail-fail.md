# tcp and tcp[100] == 1


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 11 else goto 2
002: if (A == 2048) goto 3 else goto 11
003: A = P[23:1]
004: if (A == 6) goto 5 else goto 11
005: A = P[20:2]
006: if (A & 8191 != 0) goto 11 else goto 7
007: X = (P[14:1] & 0xF) << 2
008: A = P[X+114:1]
009: if (A == 1) goto 10 else goto 11
010: return 65535
011: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   local X = 0
   local T = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if (A==34525) then goto L10 end
   if not (A==2048) then goto L10 end
   if 24 > length then return false end
   A = P[23]
   if not (A==6) then goto L10 end
   if 22 > length then return false end
   A = bit.bor(bit.lshift(P[20], 8), P[20+1])
   if not (bit.band(A, 8191)==0) then goto L10 end
   if 14 >= length then return false end
   X = bit.lshift(bit.band(P[14], 15), 2)
   T = bit.tobit((X+114))
   if T < 0 or T + 1 > length then return false end
   A = P[T]
   if not (A==1) then goto L10 end
   do return true end
   ::L10::
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
   if length < 54 then return false end
   if cast("uint16_t*", P+12)[0] ~= 8 then return false end
   if P[23] ~= 6 then return false end
   if band(cast("uint16_t*", P+20)[0],65311) ~= 0 then return false end
   local v1 = lshift(band(P[14],15),2)
   if (v1 + 115) > length then return false end
   return P[(v1 + 114)] == 1
end
```

## Native pflang compilation

```
7f53634ae000  4883FE36          cmp rsi, +0x36
7f53634ae004  7C4A              jl 0x7f53634ae050
7f53634ae006  0FB7470C          movzx eax, word [rdi+0xc]
7f53634ae00a  4883F808          cmp rax, +0x08
7f53634ae00e  7540              jnz 0x7f53634ae050
7f53634ae010  0FB64717          movzx eax, byte [rdi+0x17]
7f53634ae014  4883F806          cmp rax, +0x06
7f53634ae018  7536              jnz 0x7f53634ae050
7f53634ae01a  0FB74714          movzx eax, word [rdi+0x14]
7f53634ae01e  4881E01FFF0000    and rax, 0xff1f
7f53634ae025  4883F800          cmp rax, +0x00
7f53634ae029  7525              jnz 0x7f53634ae050
7f53634ae02b  0FB6470E          movzx eax, byte [rdi+0xe]
7f53634ae02f  4883E00F          and rax, +0x0f
7f53634ae033  48C1E002          shl rax, 0x02
7f53634ae037  89C1              mov ecx, eax
7f53634ae039  4883C173          add rcx, +0x73
7f53634ae03d  4839F1            cmp rcx, rsi
7f53634ae040  7F0E              jg 0x7f53634ae050
7f53634ae042  4883C072          add rax, +0x72
7f53634ae046  0FB60407          movzx eax, byte [rdi+rax]
7f53634ae04a  4883F801          cmp rax, +0x01
7f53634ae04e  7403              jz 0x7f53634ae053
7f53634ae050  B000              mov al, 0x0
7f53634ae052  C3                ret
7f53634ae053  B001              mov al, 0x1
7f53634ae055  C3                ret
```


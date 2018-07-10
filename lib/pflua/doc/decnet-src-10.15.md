# decnet src 10.15


## BPF

```
000: A = P[12:2]
001: if (A == 24579) goto 2 else goto 23
002: A = P[16:1]
003: A &= 7
004: if (A == 2) goto 5 else goto 7
005: A = P[19:2]
006: if (A == 3880) goto 22 else goto 7
007: A = P[16:2]
008: A &= 65287
009: if (A == 33026) goto 10 else goto 12
010: A = P[20:2]
011: if (A == 3880) goto 22 else goto 12
012: A = P[16:1]
013: A &= 7
014: if (A == 6) goto 15 else goto 17
015: A = P[31:2]
016: if (A == 3880) goto 22 else goto 17
017: A = P[16:2]
018: A &= 65287
019: if (A == 33030) goto 20 else goto 23
020: A = P[32:2]
021: if (A == 3880) goto 22 else goto 23
022: return 65535
023: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==24579) then goto L22 end
   if 17 > length then return false end
   A = P[16]
   A = bit.band(A, 7)
   if not (A==2) then goto L6 end
   if 21 > length then return false end
   A = bit.bor(bit.lshift(P[19], 8), P[19+1])
   if (A==3880) then goto L21 end
   ::L6::
   if 18 > length then return false end
   A = bit.bor(bit.lshift(P[16], 8), P[16+1])
   A = bit.band(A, 65287)
   if not (A==33026) then goto L11 end
   if 22 > length then return false end
   A = bit.bor(bit.lshift(P[20], 8), P[20+1])
   if (A==3880) then goto L21 end
   ::L11::
   if 17 > length then return false end
   A = P[16]
   A = bit.band(A, 7)
   if not (A==6) then goto L16 end
   if 33 > length then return false end
   A = bit.bor(bit.lshift(P[31], 8), P[31+1])
   if (A==3880) then goto L21 end
   ::L16::
   if 18 > length then return false end
   A = bit.bor(bit.lshift(P[16], 8), P[16+1])
   A = bit.band(A, 65287)
   if not (A==33030) then goto L22 end
   if 34 > length then return false end
   A = bit.bor(bit.lshift(P[32], 8), P[32+1])
   if not (A==3880) then goto L22 end
   ::L21::
   do return true end
   ::L22::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local band = require("bit").band
local cast = require("ffi").cast
return function(P,length)
   if length < 21 then return false end
   local v1 = band(P[16],7)
   if v1 == 2 then
      return cast("uint16_t*", P+19)[0] == 3850
   end
   if length < 22 then return false end
   local v2 = band(cast("uint16_t*", P+16)[0],2047)
   if v2 == 641 then
      return cast("uint16_t*", P+20)[0] == 3850
   end
   if length < 33 then return false end
   if v1 == 6 then
      return cast("uint16_t*", P+31)[0] == 3850
   end
   if length < 34 then return false end
   if v2 ~= 1665 then return false end
   return cast("uint16_t*", P+32)[0] == 3850
end
```

## Native pflang compilation

```
7f3cc4529000  4883FE15          cmp rsi, +0x15
7f3cc4529004  0F8C88000000      jl 0x7f3cc4529092
7f3cc452900a  0FB64710          movzx eax, byte [rdi+0x10]
7f3cc452900e  4883E007          and rax, +0x07
7f3cc4529012  4883F802          cmp rax, +0x02
7f3cc4529016  7516              jnz 0x7f3cc452902e
7f3cc4529018  0FB74F13          movzx ecx, word [rdi+0x13]
7f3cc452901c  4881F90A0F0000    cmp rcx, 0xf0a
7f3cc4529023  0F846C000000      jz 0x7f3cc4529095
7f3cc4529029  E964000000        jmp 0x7f3cc4529092
7f3cc452902e  4883FE16          cmp rsi, +0x16
7f3cc4529032  0F8C5A000000      jl 0x7f3cc4529092
7f3cc4529038  0FB74F10          movzx ecx, word [rdi+0x10]
7f3cc452903c  4881E1FF070000    and rcx, 0x7ff
7f3cc4529043  4881F981020000    cmp rcx, 0x281
7f3cc452904a  750F              jnz 0x7f3cc452905b
7f3cc452904c  0FB75714          movzx edx, word [rdi+0x14]
7f3cc4529050  4881FA0A0F0000    cmp rdx, 0xf0a
7f3cc4529057  743C              jz 0x7f3cc4529095
7f3cc4529059  EB37              jmp 0x7f3cc4529092
7f3cc452905b  4883FE21          cmp rsi, +0x21
7f3cc452905f  7C31              jl 0x7f3cc4529092
7f3cc4529061  4883F806          cmp rax, +0x06
7f3cc4529065  750F              jnz 0x7f3cc4529076
7f3cc4529067  0FB7471F          movzx eax, word [rdi+0x1f]
7f3cc452906b  4881F80A0F0000    cmp rax, 0xf0a
7f3cc4529072  7421              jz 0x7f3cc4529095
7f3cc4529074  EB1C              jmp 0x7f3cc4529092
7f3cc4529076  4883FE22          cmp rsi, +0x22
7f3cc452907a  7C16              jl 0x7f3cc4529092
7f3cc452907c  4881F981060000    cmp rcx, 0x681
7f3cc4529083  750D              jnz 0x7f3cc4529092
7f3cc4529085  0FB74F20          movzx ecx, word [rdi+0x20]
7f3cc4529089  4881F90A0F0000    cmp rcx, 0xf0a
7f3cc4529090  7403              jz 0x7f3cc4529095
7f3cc4529092  B000              mov al, 0x0
7f3cc4529094  C3                ret
7f3cc4529095  B001              mov al, 0x1
7f3cc4529097  C3                ret
```


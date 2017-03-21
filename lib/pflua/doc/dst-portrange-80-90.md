# dst portrange 80-90


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 8
002: A = P[20:1]
003: if (A == 132) goto 6 else goto 4
004: if (A == 6) goto 6 else goto 5
005: if (A == 17) goto 6 else goto 20
006: A = P[56:2]
007: if (A >= 80) goto 18 else goto 20
008: if (A == 2048) goto 9 else goto 20
009: A = P[23:1]
010: if (A == 132) goto 13 else goto 11
011: if (A == 6) goto 13 else goto 12
012: if (A == 17) goto 13 else goto 20
013: A = P[20:2]
014: if (A & 8191 != 0) goto 20 else goto 15
015: X = (P[14:1] & 0xF) << 2
016: A = P[X+16:2]
017: if (A >= 80) goto 18 else goto 20
018: if (A > 90) goto 20 else goto 19
019: return 65535
020: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   local X = 0
   local T = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L7 end
   if 21 > length then return false end
   A = P[20]
   if (A==132) then goto L5 end
   if (A==6) then goto L5 end
   if not (A==17) then goto L19 end
   ::L5::
   if 58 > length then return false end
   A = bit.bor(bit.lshift(P[56], 8), P[56+1])
   if (runtime_u32(A)>=80) then goto L17 end
   goto L19
   ::L7::
   if not (A==2048) then goto L19 end
   if 24 > length then return false end
   A = P[23]
   if (A==132) then goto L12 end
   if (A==6) then goto L12 end
   if not (A==17) then goto L19 end
   ::L12::
   if 22 > length then return false end
   A = bit.bor(bit.lshift(P[20], 8), P[20+1])
   if not (bit.band(A, 8191)==0) then goto L19 end
   if 14 >= length then return false end
   X = bit.lshift(bit.band(P[14], 15), 2)
   T = bit.tobit((X+16))
   if T < 0 or T + 2 > length then return false end
   A = bit.bor(bit.lshift(P[T], 8), P[T+1])
   if not (runtime_u32(A)>=80) then goto L19 end
   ::L17::
   if (runtime_u32(A)>90) then goto L19 end
   do return true end
   ::L19::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local rshift = require("bit").rshift
local bswap = require("bit").bswap
local cast = require("ffi").cast
local lshift = require("bit").lshift
local band = require("bit").band
return function(P,length)
   if length < 34 then return false end
   local v1 = cast("uint16_t*", P+12)[0]
   if v1 == 8 then
      local v2 = P[23]
      if v2 == 6 then goto L8 end
      do
         if v2 == 17 then goto L8 end
         if v2 == 132 then goto L8 end
         return false
      end
::L8::
      if band(cast("uint16_t*", P+20)[0],65311) ~= 0 then return false end
      local v3 = lshift(band(P[14],15),2)
      if (v3 + 18) > length then return false end
      local v4 = rshift(bswap(cast("uint16_t*", P+(v3 + 16))[0]), 16)
      if v4 < 80 then return false end
      return v4 <= 90
   else
      if length < 58 then return false end
      if v1 ~= 56710 then return false end
      local v5 = P[20]
      if v5 == 6 then goto L24 end
      do
         if v5 ~= 44 then goto L27 end
         do
            if P[54] == 6 then goto L24 end
            goto L27
         end
::L27::
         if v5 == 17 then goto L24 end
         if v5 ~= 44 then goto L33 end
         do
            if P[54] == 17 then goto L24 end
            goto L33
         end
::L33::
         if v5 == 132 then goto L24 end
         if v5 ~= 44 then return false end
         if P[54] == 132 then goto L24 end
         return false
      end
::L24::
      local v6 = rshift(bswap(cast("uint16_t*", P+56)[0]), 16)
      if v6 < 80 then return false end
      return v6 <= 90
   end
end
```

## Native pflang compilation

```
7f659fa96000  4883FE22          cmp rsi, +0x22
7f659fa96004  0F8CFB000000      jl 0x7f659fa96105
7f659fa9600a  0FB7470C          movzx eax, word [rdi+0xc]
7f659fa9600e  4883F808          cmp rax, +0x08
7f659fa96012  7576              jnz 0x7f659fa9608a
7f659fa96014  0FB64F17          movzx ecx, byte [rdi+0x17]
7f659fa96018  4883F906          cmp rcx, +0x06
7f659fa9601c  7413              jz 0x7f659fa96031
7f659fa9601e  4883F911          cmp rcx, +0x11
7f659fa96022  740D              jz 0x7f659fa96031
7f659fa96024  4881F984000000    cmp rcx, 0x84
7f659fa9602b  0F85D4000000      jnz 0x7f659fa96105
7f659fa96031  0FB74F14          movzx ecx, word [rdi+0x14]
7f659fa96035  4881E11FFF0000    and rcx, 0xff1f
7f659fa9603c  4883F900          cmp rcx, +0x00
7f659fa96040  0F85BF000000      jnz 0x7f659fa96105
7f659fa96046  0FB64F0E          movzx ecx, byte [rdi+0xe]
7f659fa9604a  4883E10F          and rcx, +0x0f
7f659fa9604e  48C1E102          shl rcx, 0x02
7f659fa96052  89CA              mov edx, ecx
7f659fa96054  4883C212          add rdx, +0x12
7f659fa96058  4839F2            cmp rdx, rsi
7f659fa9605b  0F8FA4000000      jg 0x7f659fa96105
7f659fa96061  4883C110          add rcx, +0x10
7f659fa96065  0FB70C0F          movzx ecx, word [rdi+rcx]
7f659fa96069  66C1C908          ror cx, 0x08
7f659fa9606d  480FB7C9          movzx rcx, cx
7f659fa96071  4883F950          cmp rcx, +0x50
7f659fa96075  0F8C8A000000      jl 0x7f659fa96105
7f659fa9607b  4883F95A          cmp rcx, +0x5a
7f659fa9607f  0F8E83000000      jle 0x7f659fa96108
7f659fa96085  E97B000000        jmp 0x7f659fa96105
7f659fa9608a  4883FE3A          cmp rsi, +0x3a
7f659fa9608e  0F8C71000000      jl 0x7f659fa96105
7f659fa96094  4881F886DD0000    cmp rax, 0xdd86
7f659fa9609b  0F8564000000      jnz 0x7f659fa96105
7f659fa960a1  0FB64714          movzx eax, byte [rdi+0x14]
7f659fa960a5  4883F806          cmp rax, +0x06
7f659fa960a9  7442              jz 0x7f659fa960ed
7f659fa960ab  4883F82C          cmp rax, +0x2c
7f659fa960af  750A              jnz 0x7f659fa960bb
7f659fa960b1  0FB67736          movzx esi, byte [rdi+0x36]
7f659fa960b5  4883FE06          cmp rsi, +0x06
7f659fa960b9  7432              jz 0x7f659fa960ed
7f659fa960bb  4883F811          cmp rax, +0x11
7f659fa960bf  742C              jz 0x7f659fa960ed
7f659fa960c1  4883F82C          cmp rax, +0x2c
7f659fa960c5  750A              jnz 0x7f659fa960d1
7f659fa960c7  0FB67736          movzx esi, byte [rdi+0x36]
7f659fa960cb  4883FE11          cmp rsi, +0x11
7f659fa960cf  741C              jz 0x7f659fa960ed
7f659fa960d1  4881F884000000    cmp rax, 0x84
7f659fa960d8  7413              jz 0x7f659fa960ed
7f659fa960da  4883F82C          cmp rax, +0x2c
7f659fa960de  7525              jnz 0x7f659fa96105
7f659fa960e0  0FB64736          movzx eax, byte [rdi+0x36]
7f659fa960e4  4881F884000000    cmp rax, 0x84
7f659fa960eb  7518              jnz 0x7f659fa96105
7f659fa960ed  0FB74738          movzx eax, word [rdi+0x38]
7f659fa960f1  66C1C808          ror ax, 0x08
7f659fa960f5  480FB7C0          movzx rax, ax
7f659fa960f9  4883F850          cmp rax, +0x50
7f659fa960fd  7C06              jl 0x7f659fa96105
7f659fa960ff  4883F85A          cmp rax, +0x5a
7f659fa96103  7E03              jle 0x7f659fa96108
7f659fa96105  B000              mov al, 0x0
7f659fa96107  C3                ret
7f659fa96108  B001              mov al, 0x1
7f659fa9610a  C3                ret
```


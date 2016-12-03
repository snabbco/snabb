# portrange 0-6000


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 11
002: A = P[20:1]
003: if (A == 132) goto 6 else goto 4
004: if (A == 6) goto 6 else goto 5
005: if (A == 17) goto 6 else goto 26
006: A = P[54:2]
007: if (A >= 0) goto 8 else goto 9
008: if (A > 6000) goto 9 else goto 25
009: A = P[56:2]
010: if (A >= 0) goto 24 else goto 26
011: if (A == 2048) goto 12 else goto 26
012: A = P[23:1]
013: if (A == 132) goto 16 else goto 14
014: if (A == 6) goto 16 else goto 15
015: if (A == 17) goto 16 else goto 26
016: A = P[20:2]
017: if (A & 8191 != 0) goto 26 else goto 18
018: X = (P[14:1] & 0xF) << 2
019: A = P[X+14:2]
020: if (A >= 0) goto 21 else goto 22
021: if (A > 6000) goto 22 else goto 25
022: A = P[X+16:2]
023: if (A >= 0) goto 24 else goto 26
024: if (A > 6000) goto 26 else goto 25
025: return 65535
026: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   local X = 0
   local T = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L10 end
   if 21 > length then return false end
   A = P[20]
   if (A==132) then goto L5 end
   if (A==6) then goto L5 end
   if not (A==17) then goto L25 end
   ::L5::
   if 56 > length then return false end
   A = bit.bor(bit.lshift(P[54], 8), P[54+1])
   if not (runtime_u32(A)>=0) then goto L8 end
   if not (runtime_u32(A)>6000) then goto L24 end
   ::L8::
   if 58 > length then return false end
   A = bit.bor(bit.lshift(P[56], 8), P[56+1])
   if (runtime_u32(A)>=0) then goto L23 end
   goto L25
   ::L10::
   if not (A==2048) then goto L25 end
   if 24 > length then return false end
   A = P[23]
   if (A==132) then goto L15 end
   if (A==6) then goto L15 end
   if not (A==17) then goto L25 end
   ::L15::
   if 22 > length then return false end
   A = bit.bor(bit.lshift(P[20], 8), P[20+1])
   if not (bit.band(A, 8191)==0) then goto L25 end
   if 14 >= length then return false end
   X = bit.lshift(bit.band(P[14], 15), 2)
   T = bit.tobit((X+14))
   if T < 0 or T + 2 > length then return false end
   A = bit.bor(bit.lshift(P[T], 8), P[T+1])
   if not (runtime_u32(A)>=0) then goto L21 end
   if not (runtime_u32(A)>6000) then goto L24 end
   ::L21::
   T = bit.tobit((X+16))
   if T < 0 or T + 2 > length then return false end
   A = bit.bor(bit.lshift(P[T], 8), P[T+1])
   if not (runtime_u32(A)>=0) then goto L25 end
   ::L23::
   if (runtime_u32(A)>6000) then goto L25 end
   ::L24::
   do return true end
   ::L25::
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
      local v4 = (v3 + 16)
      if v4 > length then return false end
      if rshift(bswap(cast("uint16_t*", P+(v3 + 14))[0]), 16) <= 6000 then return true end
      if (v3 + 18) > length then return false end
      return rshift(bswap(cast("uint16_t*", P+v4)[0]), 16) <= 6000
   else
      if length < 56 then return false end
      if v1 ~= 56710 then return false end
      local v5 = P[20]
      if v5 == 6 then goto L26 end
      do
         if v5 ~= 44 then goto L29 end
         do
            if P[54] == 6 then goto L26 end
            goto L29
         end
::L29::
         if v5 == 17 then goto L26 end
         if v5 ~= 44 then goto L35 end
         do
            if P[54] == 17 then goto L26 end
            goto L35
         end
::L35::
         if v5 == 132 then goto L26 end
         if v5 ~= 44 then return false end
         if P[54] == 132 then goto L26 end
         return false
      end
::L26::
      if rshift(bswap(cast("uint16_t*", P+54)[0]), 16) <= 6000 then return true end
      if length < 58 then return false end
      return rshift(bswap(cast("uint16_t*", P+56)[0]), 16) <= 6000
   end
end
```

## Native pflang compilation

```
7f438f8d6000  4883FE22          cmp rsi, +0x22
7f438f8d6004  0F8C3B010000      jl 0x7f438f8d6145
7f438f8d600a  0FB7470C          movzx eax, word [rdi+0xc]
7f438f8d600e  4883F808          cmp rax, +0x08
7f438f8d6012  0F859A000000      jnz 0x7f438f8d60b2
7f438f8d6018  0FB64F17          movzx ecx, byte [rdi+0x17]
7f438f8d601c  4883F906          cmp rcx, +0x06
7f438f8d6020  7413              jz 0x7f438f8d6035
7f438f8d6022  4883F911          cmp rcx, +0x11
7f438f8d6026  740D              jz 0x7f438f8d6035
7f438f8d6028  4881F984000000    cmp rcx, 0x84
7f438f8d602f  0F8510010000      jnz 0x7f438f8d6145
7f438f8d6035  0FB74F14          movzx ecx, word [rdi+0x14]
7f438f8d6039  4881E11FFF0000    and rcx, 0xff1f
7f438f8d6040  4883F900          cmp rcx, +0x00
7f438f8d6044  0F85FB000000      jnz 0x7f438f8d6145
7f438f8d604a  0FB64F0E          movzx ecx, byte [rdi+0xe]
7f438f8d604e  4883E10F          and rcx, +0x0f
7f438f8d6052  48C1E102          shl rcx, 0x02
7f438f8d6056  89CA              mov edx, ecx
7f438f8d6058  4883C210          add rdx, +0x10
7f438f8d605c  4839F2            cmp rdx, rsi
7f438f8d605f  0F8FE0000000      jg 0x7f438f8d6145
7f438f8d6065  4189C8            mov r8d, ecx
7f438f8d6068  4983C00E          add r8, +0x0e
7f438f8d606c  460FB70407        movzx r8d, word [rdi+r8]
7f438f8d6071  6641C1C808        ror r8w, 0x08
7f438f8d6076  4D0FB7C0          movzx r8, r8w
7f438f8d607a  4981F870170000    cmp r8, 0x1770
7f438f8d6081  0F8EC1000000      jle 0x7f438f8d6148
7f438f8d6087  4883C112          add rcx, +0x12
7f438f8d608b  4839F1            cmp rcx, rsi
7f438f8d608e  0F8FB1000000      jg 0x7f438f8d6145
7f438f8d6094  0FB71417          movzx edx, word [rdi+rdx]
7f438f8d6098  66C1CA08          ror dx, 0x08
7f438f8d609c  480FB7D2          movzx rdx, dx
7f438f8d60a0  4881FA70170000    cmp rdx, 0x1770
7f438f8d60a7  0F8E9B000000      jle 0x7f438f8d6148
7f438f8d60ad  E993000000        jmp 0x7f438f8d6145
7f438f8d60b2  4883FE38          cmp rsi, +0x38
7f438f8d60b6  0F8C89000000      jl 0x7f438f8d6145
7f438f8d60bc  4881F886DD0000    cmp rax, 0xdd86
7f438f8d60c3  0F857C000000      jnz 0x7f438f8d6145
7f438f8d60c9  0FB64714          movzx eax, byte [rdi+0x14]
7f438f8d60cd  4883F806          cmp rax, +0x06
7f438f8d60d1  7442              jz 0x7f438f8d6115
7f438f8d60d3  4883F82C          cmp rax, +0x2c
7f438f8d60d7  750A              jnz 0x7f438f8d60e3
7f438f8d60d9  0FB65736          movzx edx, byte [rdi+0x36]
7f438f8d60dd  4883FA06          cmp rdx, +0x06
7f438f8d60e1  7432              jz 0x7f438f8d6115
7f438f8d60e3  4883F811          cmp rax, +0x11
7f438f8d60e7  742C              jz 0x7f438f8d6115
7f438f8d60e9  4883F82C          cmp rax, +0x2c
7f438f8d60ed  750A              jnz 0x7f438f8d60f9
7f438f8d60ef  0FB65736          movzx edx, byte [rdi+0x36]
7f438f8d60f3  4883FA11          cmp rdx, +0x11
7f438f8d60f7  741C              jz 0x7f438f8d6115
7f438f8d60f9  4881F884000000    cmp rax, 0x84
7f438f8d6100  7413              jz 0x7f438f8d6115
7f438f8d6102  4883F82C          cmp rax, +0x2c
7f438f8d6106  753D              jnz 0x7f438f8d6145
7f438f8d6108  0FB64736          movzx eax, byte [rdi+0x36]
7f438f8d610c  4881F884000000    cmp rax, 0x84
7f438f8d6113  7530              jnz 0x7f438f8d6145
7f438f8d6115  0FB74736          movzx eax, word [rdi+0x36]
7f438f8d6119  66C1C808          ror ax, 0x08
7f438f8d611d  480FB7C0          movzx rax, ax
7f438f8d6121  4881F870170000    cmp rax, 0x1770
7f438f8d6128  7E1E              jle 0x7f438f8d6148
7f438f8d612a  4883FE3A          cmp rsi, +0x3a
7f438f8d612e  7C15              jl 0x7f438f8d6145
7f438f8d6130  0FB77738          movzx esi, word [rdi+0x38]
7f438f8d6134  66C1CE08          ror si, 0x08
7f438f8d6138  480FB7F6          movzx rsi, si
7f438f8d613c  4881FE70170000    cmp rsi, 0x1770
7f438f8d6143  7E03              jle 0x7f438f8d6148
7f438f8d6145  B000              mov al, 0x0
7f438f8d6147  C3                ret
7f438f8d6148  B001              mov al, 0x1
7f438f8d614a  C3                ret
```


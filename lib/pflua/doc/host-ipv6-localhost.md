# host ::1


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 19
002: A = P[22:4]
003: if (A == 0) goto 4 else goto 10
004: A = P[26:4]
005: if (A == 0) goto 6 else goto 10
006: A = P[30:4]
007: if (A == 0) goto 8 else goto 10
008: A = P[34:4]
009: if (A == 1) goto 18 else goto 10
010: A = P[38:4]
011: if (A == 0) goto 12 else goto 19
012: A = P[42:4]
013: if (A == 0) goto 14 else goto 19
014: A = P[46:4]
015: if (A == 0) goto 16 else goto 19
016: A = P[50:4]
017: if (A == 1) goto 18 else goto 19
018: return 65535
019: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L18 end
   if 26 > length then return false end
   A = bit.bor(bit.lshift(P[22], 24),bit.lshift(P[22+1], 16), bit.lshift(P[22+2], 8), P[22+3])
   if not (A==0) then goto L9 end
   if 30 > length then return false end
   A = bit.bor(bit.lshift(P[26], 24),bit.lshift(P[26+1], 16), bit.lshift(P[26+2], 8), P[26+3])
   if not (A==0) then goto L9 end
   if 34 > length then return false end
   A = bit.bor(bit.lshift(P[30], 24),bit.lshift(P[30+1], 16), bit.lshift(P[30+2], 8), P[30+3])
   if not (A==0) then goto L9 end
   if 38 > length then return false end
   A = bit.bor(bit.lshift(P[34], 24),bit.lshift(P[34+1], 16), bit.lshift(P[34+2], 8), P[34+3])
   if (A==1) then goto L17 end
   ::L9::
   if 42 > length then return false end
   A = bit.bor(bit.lshift(P[38], 24),bit.lshift(P[38+1], 16), bit.lshift(P[38+2], 8), P[38+3])
   if not (A==0) then goto L18 end
   if 46 > length then return false end
   A = bit.bor(bit.lshift(P[42], 24),bit.lshift(P[42+1], 16), bit.lshift(P[42+2], 8), P[42+3])
   if not (A==0) then goto L18 end
   if 50 > length then return false end
   A = bit.bor(bit.lshift(P[46], 24),bit.lshift(P[46+1], 16), bit.lshift(P[46+2], 8), P[46+3])
   if not (A==0) then goto L18 end
   if 54 > length then return false end
   A = bit.bor(bit.lshift(P[50], 24),bit.lshift(P[50+1], 16), bit.lshift(P[50+2], 8), P[50+3])
   if not (A==1) then goto L18 end
   ::L17::
   do return true end
   ::L18::
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
   if cast("uint32_t*", P+22)[0] ~= 0 then goto L9 end
   do
      if cast("uint32_t*", P+26)[0] ~= 0 then goto L9 end
      if cast("uint32_t*", P+30)[0] ~= 0 then goto L9 end
      if cast("uint32_t*", P+34)[0] == 16777216 then return true end
      goto L9
   end
::L9::
   if cast("uint32_t*", P+38)[0] ~= 0 then return false end
   if cast("uint32_t*", P+42)[0] ~= 0 then return false end
   if cast("uint32_t*", P+46)[0] ~= 0 then return false end
   return cast("uint32_t*", P+50)[0] == 16777216
end
```

## Native pflang compilation

```
7f5e7dc55000  4883FE36          cmp rsi, +0x36
7f5e7dc55004  7C5B              jl 0x7f5e7dc55061
7f5e7dc55006  0FB7770C          movzx esi, word [rdi+0xc]
7f5e7dc5500a  4881FE86DD0000    cmp rsi, 0xdd86
7f5e7dc55011  754E              jnz 0x7f5e7dc55061
7f5e7dc55013  8B7716            mov esi, [rdi+0x16]
7f5e7dc55016  4883FE00          cmp rsi, +0x00
7f5e7dc5501a  751E              jnz 0x7f5e7dc5503a
7f5e7dc5501c  8B771A            mov esi, [rdi+0x1a]
7f5e7dc5501f  4883FE00          cmp rsi, +0x00
7f5e7dc55023  7515              jnz 0x7f5e7dc5503a
7f5e7dc55025  8B771E            mov esi, [rdi+0x1e]
7f5e7dc55028  4883FE00          cmp rsi, +0x00
7f5e7dc5502c  750C              jnz 0x7f5e7dc5503a
7f5e7dc5502e  8B7722            mov esi, [rdi+0x22]
7f5e7dc55031  4881FE00000001    cmp rsi, 0x01000000
7f5e7dc55038  742A              jz 0x7f5e7dc55064
7f5e7dc5503a  8B7726            mov esi, [rdi+0x26]
7f5e7dc5503d  4883FE00          cmp rsi, +0x00
7f5e7dc55041  751E              jnz 0x7f5e7dc55061
7f5e7dc55043  8B772A            mov esi, [rdi+0x2a]
7f5e7dc55046  4883FE00          cmp rsi, +0x00
7f5e7dc5504a  7515              jnz 0x7f5e7dc55061
7f5e7dc5504c  8B772E            mov esi, [rdi+0x2e]
7f5e7dc5504f  4883FE00          cmp rsi, +0x00
7f5e7dc55053  750C              jnz 0x7f5e7dc55061
7f5e7dc55055  8B7732            mov esi, [rdi+0x32]
7f5e7dc55058  4881FE00000001    cmp rsi, 0x01000000
7f5e7dc5505f  7403              jz 0x7f5e7dc55064
7f5e7dc55061  B000              mov al, 0x0
7f5e7dc55063  C3                ret
7f5e7dc55064  B001              mov al, 0x1
7f5e7dc55066  C3                ret
```


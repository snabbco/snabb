# host 127.0.0.1


## BPF

```
000: A = P[12:2]
001: if (A == 2048) goto 2 else goto 6
002: A = P[26:4]
003: if (A == 2130706433) goto 12 else goto 4
004: A = P[30:4]
005: if (A == 2130706433) goto 12 else goto 13
006: if (A == 2054) goto 8 else goto 7
007: if (A == 32821) goto 8 else goto 13
008: A = P[28:4]
009: if (A == 2130706433) goto 12 else goto 10
010: A = P[38:4]
011: if (A == 2130706433) goto 12 else goto 13
012: return 65535
013: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==2048) then goto L5 end
   if 30 > length then return false end
   A = bit.bor(bit.lshift(P[26], 24),bit.lshift(P[26+1], 16), bit.lshift(P[26+2], 8), P[26+3])
   if (A==2130706433) then goto L11 end
   if 34 > length then return false end
   A = bit.bor(bit.lshift(P[30], 24),bit.lshift(P[30+1], 16), bit.lshift(P[30+2], 8), P[30+3])
   if (A==2130706433) then goto L11 end
   goto L12
   ::L5::
   if (A==2054) then goto L7 end
   if not (A==32821) then goto L12 end
   ::L7::
   if 32 > length then return false end
   A = bit.bor(bit.lshift(P[28], 24),bit.lshift(P[28+1], 16), bit.lshift(P[28+2], 8), P[28+3])
   if (A==2130706433) then goto L11 end
   if 42 > length then return false end
   A = bit.bor(bit.lshift(P[38], 24),bit.lshift(P[38+1], 16), bit.lshift(P[38+2], 8), P[38+3])
   if not (A==2130706433) then goto L12 end
   ::L11::
   do return true end
   ::L12::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local cast = require("ffi").cast
return function(P,length)
   if length < 34 then return false end
   local v1 = cast("uint16_t*", P+12)[0]
   if v1 == 8 then
      if cast("uint32_t*", P+26)[0] == 16777343 then return true end
      return cast("uint32_t*", P+30)[0] == 16777343
   else
      if length < 42 then return false end
      if v1 == 1544 then goto L12 end
      do
         if v1 == 13696 then goto L12 end
         return false
      end
::L12::
      if cast("uint32_t*", P+28)[0] == 16777343 then return true end
      return cast("uint32_t*", P+38)[0] == 16777343
   end
end
```

## Native pflang compilation

```
7fb06b836000  4883FE22          cmp rsi, +0x22
7fb06b836004  7C54              jl 0x7fb06b83605a
7fb06b836006  0FB7470C          movzx eax, word [rdi+0xc]
7fb06b83600a  4883F808          cmp rax, +0x08
7fb06b83600e  751A              jnz 0x7fb06b83602a
7fb06b836010  8B4F1A            mov ecx, [rdi+0x1a]
7fb06b836013  4881F97F000001    cmp rcx, 0x0100007f
7fb06b83601a  7441              jz 0x7fb06b83605d
7fb06b83601c  8B4F1E            mov ecx, [rdi+0x1e]
7fb06b83601f  4881F97F000001    cmp rcx, 0x0100007f
7fb06b836026  7435              jz 0x7fb06b83605d
7fb06b836028  EB30              jmp 0x7fb06b83605a
7fb06b83602a  4883FE2A          cmp rsi, +0x2a
7fb06b83602e  7C2A              jl 0x7fb06b83605a
7fb06b836030  4881F808060000    cmp rax, 0x608
7fb06b836037  7409              jz 0x7fb06b836042
7fb06b836039  4881F880350000    cmp rax, 0x3580
7fb06b836040  7518              jnz 0x7fb06b83605a
7fb06b836042  8B471C            mov eax, [rdi+0x1c]
7fb06b836045  4881F87F000001    cmp rax, 0x0100007f
7fb06b83604c  740F              jz 0x7fb06b83605d
7fb06b83604e  8B4726            mov eax, [rdi+0x26]
7fb06b836051  4881F87F000001    cmp rax, 0x0100007f
7fb06b836058  7403              jz 0x7fb06b83605d
7fb06b83605a  B000              mov al, 0x0
7fb06b83605c  C3                ret
7fb06b83605d  B001              mov al, 0x1
7fb06b83605f  C3                ret
```


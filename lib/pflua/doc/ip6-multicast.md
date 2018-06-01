# ip6 multicast


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 5
002: A = P[38:1]
003: if (A == 255) goto 4 else goto 5
004: return 65535
005: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L4 end
   if 39 > length then return false end
   A = P[38]
   if not (A==255) then goto L4 end
   do return true end
   ::L4::
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
   return P[38] == 255
end
```

## Native pflang compilation

```
7f0b5442c000  4883FE36          cmp rsi, +0x36
7f0b5442c004  7C1A              jl 0x7f0b5442c020
7f0b5442c006  0FB7770C          movzx esi, word [rdi+0xc]
7f0b5442c00a  4881FE86DD0000    cmp rsi, 0xdd86
7f0b5442c011  750D              jnz 0x7f0b5442c020
7f0b5442c013  0FB67726          movzx esi, byte [rdi+0x26]
7f0b5442c017  4881FEFF000000    cmp rsi, 0xff
7f0b5442c01e  7403              jz 0x7f0b5442c023
7f0b5442c020  B000              mov al, 0x0
7f0b5442c022  C3                ret
7f0b5442c023  B001              mov al, 0x1
7f0b5442c025  C3                ret
```


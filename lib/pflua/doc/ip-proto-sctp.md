# ip proto \sctp


## BPF

```
000: A = P[12:2]
001: if (A == 2048) goto 2 else goto 5
002: A = P[23:1]
003: if (A == 132) goto 4 else goto 5
004: return 65535
005: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==2048) then goto L4 end
   if 24 > length then return false end
   A = P[23]
   if not (A==132) then goto L4 end
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
   if length < 34 then return false end
   if cast("uint16_t*", P+12)[0] ~= 8 then return false end
   return P[23] == 132
end
```

## Native pflang compilation

```
7f91933dd000  4883FE22          cmp rsi, +0x22
7f91933dd004  7C17              jl 0x7f91933dd01d
7f91933dd006  0FB7770C          movzx esi, word [rdi+0xc]
7f91933dd00a  4883FE08          cmp rsi, +0x08
7f91933dd00e  750D              jnz 0x7f91933dd01d
7f91933dd010  0FB67717          movzx esi, byte [rdi+0x17]
7f91933dd014  4881FE84000000    cmp rsi, 0x84
7f91933dd01b  7403              jz 0x7f91933dd020
7f91933dd01d  B000              mov al, 0x0
7f91933dd01f  C3                ret
7f91933dd020  B001              mov al, 0x1
7f91933dd022  C3                ret
```


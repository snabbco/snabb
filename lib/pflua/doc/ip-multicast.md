# ip multicast


## BPF

```
000: A = P[12:2]
001: if (A == 2048) goto 2 else goto 5
002: A = P[30:1]
003: if (A >= 224) goto 4 else goto 5
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
   if 31 > length then return false end
   A = P[30]
   if not (runtime_u32(A)>=224) then goto L4 end
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
   return P[30] == 224
end
```

## Native pflang compilation

```
7f7e5045a000  4883FE22          cmp rsi, +0x22
7f7e5045a004  7C17              jl 0x7f7e5045a01d
7f7e5045a006  0FB7770C          movzx esi, word [rdi+0xc]
7f7e5045a00a  4883FE08          cmp rsi, +0x08
7f7e5045a00e  750D              jnz 0x7f7e5045a01d
7f7e5045a010  0FB6771E          movzx esi, byte [rdi+0x1e]
7f7e5045a014  4881FEE0000000    cmp rsi, 0xe0
7f7e5045a01b  7403              jz 0x7f7e5045a020
7f7e5045a01d  B000              mov al, 0x0
7f7e5045a01f  C3                ret
7f7e5045a020  B001              mov al, 0x1
7f7e5045a022  C3                ret
```


# ether proto 255


## BPF

```
000: A = P[12:2]
001: if (A > 1500) goto 5 else goto 2
002: A = P[14:1]
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
   if (runtime_u32(A)>1500) then goto L4 end
   if 15 > length then return false end
   A = P[14]
   if not (A==255) then goto L4 end
   do return true end
   ::L4::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local rshift = require("bit").rshift
local bswap = require("bit").bswap
local cast = require("ffi").cast
return function(P,length)
   if length < 15 then return false end
   if rshift(bswap(cast("uint16_t*", P+12)[0]), 16) > 1500 then return false end
   return P[14] == 255
end

```


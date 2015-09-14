# net ::0/16


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 7
002: A = P[22:4]
003: if (A & 4294901760 != 0) goto 4 else goto 6
004: A = P[38:4]
005: if (A & 4294901760 != 0) goto 7 else goto 6
006: return 65535
007: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L6 end
   if 26 > length then return false end
   A = bit.bor(bit.lshift(P[22], 24),bit.lshift(P[22+1], 16), bit.lshift(P[22+2], 8), P[22+3])
   if (bit.band(A, -65536)==0) then goto L5 end
   if 42 > length then return false end
   A = bit.bor(bit.lshift(P[38], 24),bit.lshift(P[38+1], 16), bit.lshift(P[38+2], 8), P[38+3])
   if not (bit.band(A, -65536)==0) then goto L6 end
   ::L5::
   do return true end
   ::L6::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local band = require("bit").band
local cast = require("ffi").cast
return function(P,length)
   if length < 54 then return false end
   if cast("uint16_t*", P+12)[0] ~= 56710 then return false end
   if band(cast("uint32_t*", P+22)[0],65535) == 0 then return true end
   return band(cast("uint32_t*", P+38)[0],65535) == 0
end

```


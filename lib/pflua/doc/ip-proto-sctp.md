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


# tcp and tcp[100] == 1


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 11 else goto 2
002: if (A == 2048) goto 3 else goto 11
003: A = P[23:1]
004: if (A == 6) goto 5 else goto 11
005: A = P[20:2]
006: if (A & 8191 != 0) goto 11 else goto 7
007: X = (P[14:1] & 0xF) << 2
008: A = P[X+114:1]
009: if (A == 1) goto 10 else goto 11
010: return 65535
011: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   local X = 0
   local T = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if (A==34525) then goto L10 end
   if not (A==2048) then goto L10 end
   if 24 > length then return false end
   A = P[23]
   if not (A==6) then goto L10 end
   if 22 > length then return false end
   A = bit.bor(bit.lshift(P[20], 8), P[20+1])
   if not (bit.band(A, 8191)==0) then goto L10 end
   if 14 >= length then return false end
   X = bit.lshift(bit.band(P[14], 15), 2)
   T = bit.tobit((X+114))
   if T < 0 or T + 1 > length then return false end
   A = P[T]
   if not (A==1) then goto L10 end
   do return true end
   ::L10::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local lshift = require("bit").lshift
local band = require("bit").band
local cast = require("ffi").cast
return function(P,length)
   if length < 54 then return false end
   if cast("uint16_t*", P+12)[0] ~= 8 then return false end
   if P[23] ~= 6 then return false end
   if band(cast("uint16_t*", P+20)[0],65311) ~= 0 then return false end
   local v1 = lshift(band(P[14],15),2)
   if (v1 + 115) > length then return false end
   return P[(v1 + 114)] == 1
end

```


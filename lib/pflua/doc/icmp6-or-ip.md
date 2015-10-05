# icmp6 or ip


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 7
002: A = P[20:1]
003: if (A == 58) goto 8 else goto 4
004: if (A == 44) goto 5 else goto 9
005: A = P[54:1]
006: if (A == 58) goto 8 else goto 9
007: if (A == 2048) goto 8 else goto 9
008: return 65535
009: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L6 end
   if 21 > length then return false end
   A = P[20]
   if (A==58) then goto L7 end
   if not (A==44) then goto L8 end
   if 55 > length then return false end
   A = P[54]
   if (A==58) then goto L7 end
   goto L8
   ::L6::
   if not (A==2048) then goto L8 end
   ::L7::
   do return true end
   ::L8::
   do return false end
   error("end of bpf")
end
```


## Direct pflang compilation

```
local cast = require("ffi").cast
return function(P,length)
   if length < 14 then return false end
   if length < 54 then goto L7 end
   do
      if cast("uint16_t*", P+12)[0] ~= 56710 then goto L7 end
      local v1 = P[20]
      if v1 == 58 then return true end
      if length < 55 then goto L7 end
      if v1 ~= 44 then goto L7 end
      if P[54] == 58 then return true end
      goto L7
   end
::L7::
   return cast("uint16_t*", P+12)[0] == 8
end

```


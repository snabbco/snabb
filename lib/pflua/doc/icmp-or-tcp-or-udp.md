# icmp or tcp or udp


## BPF

```
000: A = P[12:2]
001: if (A == 2048) goto 2 else goto 5
002: A = P[23:1]
003: if (A == 1) goto 12 else goto 4
004: if (A == 6) goto 12 else goto 11
005: if (A == 34525) goto 6 else goto 13
006: A = P[20:1]
007: if (A == 6) goto 12 else goto 8
008: if (A == 44) goto 9 else goto 11
009: A = P[54:1]
010: if (A == 6) goto 12 else goto 11
011: if (A == 17) goto 12 else goto 13
012: return 65535
013: return 0
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
   if (A==1) then goto L11 end
   if (A==6) then goto L11 end
   goto L10
   ::L4::
   if not (A==34525) then goto L12 end
   if 21 > length then return false end
   A = P[20]
   if (A==6) then goto L11 end
   if not (A==44) then goto L10 end
   if 55 > length then return false end
   A = P[54]
   if (A==6) then goto L11 end
   ::L10::
   if not (A==17) then goto L12 end
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
      local v2 = P[23]
      if v2 == 1 then return true end
      if v2 == 6 then return true end
      return v2 == 17
   else
      if length < 54 then return false end
      if v1 ~= 56710 then return false end
      local v3 = P[20]
      if v3 == 1 then return true end
      if length < 55 then goto L19 end
      do
         if v3 ~= 44 then goto L19 end
         if P[54] == 1 then return true end
         goto L19
      end
::L19::
      if v3 == 6 then return true end
      if length < 55 then goto L17 end
      do
         if v3 ~= 44 then goto L17 end
         if P[54] == 6 then return true end
         goto L17
      end
::L17::
      if v3 == 17 then return true end
      if length < 55 then return false end
      if v3 ~= 44 then return false end
      return P[54] == 17
   end
end

```


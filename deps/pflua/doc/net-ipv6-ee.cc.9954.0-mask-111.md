# net ee:cc::9954:0/111


## BPF

```
000: A = P[12:2]
001: if (A == 34525) goto 2 else goto 21
002: A = P[22:4]
003: if (A == 15597772) goto 4 else goto 11
004: A = P[26:4]
005: if (A == 0) goto 6 else goto 11
006: A = P[30:4]
007: if (A == 0) goto 8 else goto 11
008: A = P[34:4]
009: A &= 4294836224
010: if (A == 2572419072) goto 20 else goto 11
011: A = P[38:4]
012: if (A == 15597772) goto 13 else goto 21
013: A = P[42:4]
014: if (A == 0) goto 15 else goto 21
015: A = P[46:4]
016: if (A == 0) goto 17 else goto 21
017: A = P[50:4]
018: A &= 4294836224
019: if (A == 2572419072) goto 20 else goto 21
020: return 65535
021: return 0
```


## BPF cross-compiled to Lua

```
return function (P, length)
   local A = 0
   if 14 > length then return false end
   A = bit.bor(bit.lshift(P[12], 8), P[12+1])
   if not (A==34525) then goto L20 end
   if 26 > length then return false end
   A = bit.bor(bit.lshift(P[22], 24),bit.lshift(P[22+1], 16), bit.lshift(P[22+2], 8), P[22+3])
   if not (A==15597772) then goto L10 end
   if 30 > length then return false end
   A = bit.bor(bit.lshift(P[26], 24),bit.lshift(P[26+1], 16), bit.lshift(P[26+2], 8), P[26+3])
   if not (A==0) then goto L10 end
   if 34 > length then return false end
   A = bit.bor(bit.lshift(P[30], 24),bit.lshift(P[30+1], 16), bit.lshift(P[30+2], 8), P[30+3])
   if not (A==0) then goto L10 end
   if 38 > length then return false end
   A = bit.bor(bit.lshift(P[34], 24),bit.lshift(P[34+1], 16), bit.lshift(P[34+2], 8), P[34+3])
   A = bit.band(A, -131072)
   if (A==-1722548224) then goto L19 end
   ::L10::
   if 42 > length then return false end
   A = bit.bor(bit.lshift(P[38], 24),bit.lshift(P[38+1], 16), bit.lshift(P[38+2], 8), P[38+3])
   if not (A==15597772) then goto L20 end
   if 46 > length then return false end
   A = bit.bor(bit.lshift(P[42], 24),bit.lshift(P[42+1], 16), bit.lshift(P[42+2], 8), P[42+3])
   if not (A==0) then goto L20 end
   if 50 > length then return false end
   A = bit.bor(bit.lshift(P[46], 24),bit.lshift(P[46+1], 16), bit.lshift(P[46+2], 8), P[46+3])
   if not (A==0) then goto L20 end
   if 54 > length then return false end
   A = bit.bor(bit.lshift(P[50], 24),bit.lshift(P[50+1], 16), bit.lshift(P[50+2], 8), P[50+3])
   A = bit.band(A, -131072)
   if not (A==-1722548224) then goto L20 end
   ::L19::
   do return true end
   ::L20::
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
   if cast("uint32_t*", P+22)[0] ~= 3422612992 then goto L9 end
   do
      if cast("uint32_t*", P+26)[0] ~= 0 then goto L9 end
      if cast("uint32_t*", P+30)[0] ~= 0 then goto L9 end
      if band(cast("uint32_t*", P+34)[0],65279) == 21657 then return true end
      goto L9
   end
::L9::
   if cast("uint32_t*", P+38)[0] ~= 3422612992 then return false end
   if cast("uint32_t*", P+42)[0] ~= 0 then return false end
   if cast("uint32_t*", P+46)[0] ~= 0 then return false end
   return band(cast("uint32_t*", P+50)[0],65279) == 21657
end

```


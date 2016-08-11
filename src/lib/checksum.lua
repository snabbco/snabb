-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- See README.checksum.md for API.

require("lib.checksum_h")
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C
local band, lshift = bit.band, bit.lshift

-- Select ipsum(pointer, len, initial) function based on hardware
-- capability.
local cpuinfo = lib.readfile("/proc/cpuinfo", "*a")
assert(cpuinfo, "failed to read /proc/cpuinfo for hardware check")
local have_avx2 = cpuinfo:match("avx2")
local have_sse2 = cpuinfo:match("sse2")

if     have_avx2 then ipsum = C.cksum_avx2
elseif have_sse2 then ipsum = C.cksum_sse2
else                  ipsum = C.cksum_generic end


function finish_packet (buf, len, offset)
   ffi.cast('uint16_t *', buf+offset)[0] = lib.htons(ipsum(buf, len, 0))
end

function verify_packet (buf, len)
   local initial = C.pseudo_header_initial(buf, len)
   if     initial == 0xFFFF0001 then return nil
   elseif initial == 0xFFFF0002 then return false
   end

   local headersize = 0
   local ipv = band(buf[0], 0xF0)
   if ipv == 0x60 then
      headersize = 40
   elseif ipv == 0x40 then
      headersize = band(buf[0], 0x0F) * 4;
   end

   return ipsum(buf+headersize, len-headersize, initial) == 0
end

local function prepare_packet_l4 (buf, len, csum_start, csum_off)

  local hwbuf =  ffi.cast('uint16_t*', buf)

  local pheader = C.pseudo_header_initial(buf, len)
  if band(pheader, 0xFFFF0000) == 0 then
    hwbuf[(csum_start+csum_off)/2] = C.htons(band(pheader, 0x0000FFFF))
  else
    csum_start, csum_off = nil, nil
  end

  return csum_start, csum_off
end

function prepare_packet4 (buf, len)

  local hwbuf =  ffi.cast('uint16_t*', buf)
  local proto = buf[9];

  local csum_start = lshift(band(buf[0], 0x0F),2)
  local csum_off

  -- Update the IPv4 checksum (use in-place pseudoheader, by setting it to 0)
  hwbuf[5] = 0;
  hwbuf[5] = C.htons(ipsum(buf, csum_start, 0));

  -- TCP
  if proto == 6 then
    csum_off = 16
  -- UDP
  elseif proto == 17 then
    csum_off = 6
  end

  return prepare_packet_l4( buf, len, csum_start, csum_off)
end

function prepare_packet6 (buf, len)
  local hwbuf =  ffi.cast('uint16_t*', buf)
  local proto = buf[6];

  local csum_start = 40
  local csum_off

  -- TCP
  if proto == 6 then
    csum_off = 16
  -- UDP
  elseif proto == 17 then
    csum_off = 6
  end

  return prepare_packet_l4( buf, len, csum_start, csum_off)
end

-- See checksum.h for more utility functions that can be added.

function selftest ()
   print("selftest: checksum")
   local tests = 1000
   local n = 1000000
   local array = ffi.new("char[?]", n)
   for i = 0, n-1 do  array[i] = i  end
   local avx2ok, sse2ok = 0, 0
   for i = 1, tests do
      local initial = math.random(0, 0xFFFF)
      local ref =   C.cksum_generic(array+i*2, i*10+i, initial)
      if have_avx2 and C.cksum_avx2(array+i*2, i*10+i, initial) == ref then
         avx2ok = avx2ok + 1
      end
      if have_sse2 and C.cksum_sse2(array+i*2, i*10+i, initial) == ref then
         sse2ok = sse2ok + 1
      end
      assert(ipsum(array+i*2, i*10+i, initial) == ref, "API function check")
   end
   if have_avx2 then print("avx2: "..avx2ok.."/"..tests) else print("no avx2") end
   if have_sse2 then print("sse2: "..sse2ok.."/"..tests) else print("no sse2") end
   selftest_ipv4_tcp()
   assert(not have_avx2 or avx2ok == tests, "AVX2 test failed")
   assert(not have_sse2 or sse2ok == tests, "SSE2 test failed")
   print("selftest: ok")
end

function selftest_ipv4_tcp ()
   print("selftest: tcp/ipv4")
   local s = "45 00 05 DC 00 26 40 00 40 06 20 F4 0A 00 00 01 0A 00 00 02 8A DE 13 89 6C 27 3B 04 1C E9 F9 C6 80 10 00 E5 5E 47 00 00 01 01 08 0A 01 0F 3A CA 01 0B 32 A9 00 00 00 00 00 00 00 01 00 00 13 89 00 00 00 00 00 00 00 00 FF FF E8 90 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37"
   local data = lib.hexundump(s, 1500)
   assert(verify_packet(ffi.cast("char*",data), #data), "TCP/IPv4 checksum validation failed")
end

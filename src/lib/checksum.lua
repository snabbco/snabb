-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- See README.checksum.md for API.

require("lib.checksum_h")
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C
local band, lshift = bit.band, bit.lshift

ipsum = require("arch.checksum").checksum

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
   for i = 0, n-1 do array[i] = i end
   for i = 1, tests do
      local initial = math.random(0, 0xFFFF)
      local ref = C.cksum_generic(array+i*2, i*10+i, initial)
      assert(ipsum(array+i*2, i*10+i, initial) == ref, "API function check")
   end
   selftest_ipv4_tcp()
   print("selftest: ok")
end

function selftest_ipv4_tcp ()
   print("selftest: tcp/ipv4")
   local s = "45 00 05 DC 00 26 40 00 40 06 20 F4 0A 00 00 01 0A 00 00 02 8A DE 13 89 6C 27 3B 04 1C E9 F9 C6 80 10 00 E5 5E 47 00 00 01 01 08 0A 01 0F 3A CA 01 0B 32 A9 00 00 00 00 00 00 00 01 00 00 13 89 00 00 00 00 00 00 00 00 FF FF E8 90 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37 38 39 30 31 32 33 34 35 36 37"
   local data = lib.hexundump(s, 1500)
   assert(verify_packet(ffi.cast("char*",data), #data), "TCP/IPv4 checksum validation failed")
end

module(...,package.seeall)

-- This module exposes the interface:
--   checksum.ipsum(pointer, length, initial) => checksum
--
-- pointer is a pointer to an array of data to be checksummed. initial
-- is an unsigned 16-bit number in host byte order which is used as
-- the starting value of the accumulator.  The result is the IP
-- checksum over the data in host byte order.
--
-- The initial argument can be used to verify a checksum or to
-- calculate the checksum in an incremental manner over chunks of
-- memory.  The synopsis to check whether the checksum over a block of
-- data is equal to a given value is the following
--
--  if ipsum(pointer, length, value) == 0 then
--    -- checksum correct
--  else
--    -- checksum incorrect
--  end
--
-- To chain the calculation of checksums over multiple blocks of data
-- together to obtain the overall checksum, one needs to pass the
-- one's complement of the checksum of one block as initial value to
-- the call of ipsum() for the following block, e.g.
--
--  local sum1 = ipsum(data1, length1, 0)
--  local total_sum = ipsum(data2, length2, bit.bnot(sum1))
--
-- The actual implementation is chosen based on running CPU.

require("lib.checksum_h")
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C
local band = bit.band

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
   assert(not have_avx2 or avx2ok == tests, "AVX2 test failed")
   assert(not have_sse2 or sse2ok == tests, "SSE2 test failed")
   print("selftest: ok")
end


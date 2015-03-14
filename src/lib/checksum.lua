module(...,package.seeall)

-- This module exposes the interface:
--   checksum.ipsum(pointer, length, initial) => checksum
-- where checksum is in network byte order.
--
-- The actual implementation is chosen based on running CPU.

require("lib.checksum_h")
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C

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


-- See checksum.h for more utility functions that can be added.

function selftest ()
   print("selftest: checksum")
   local tests = 1000
   local n = 1000000
   local array = ffi.new("char[?]", n)
   for i = 0, n-1 do  array[i] = i  end
   local avx2ok, sse2ok = 0, 0
   for i = 1, tests do
      local ref =   C.cksum_generic(array+i*2, i*10+i, 0)
      if have_avx2 and C.cksum_avx2(array+i*2, i*10+i, 0) == ref then
	 avx2ok = avx2ok + 1
      end
      if have_sse2 and C.cksum_sse2(array+i*2, i*10+i, 0) == ref then
	 sse2ok = sse2ok + 1
      end
      assert(ipsum(array+i*2, i*10+i, 0) == ref, "API function check")
   end
   if have_avx2 then print("avx2: "..avx2ok.."/"..tests) else print("no avx2") end
   if have_sse2 then print("sse2: "..sse2ok.."/"..tests) else print("no sse2") end
   assert(not have_avx2 or avx2ok == tests, "AVX2 test failed")
   assert(not have_sse2 or sse2ok == tests, "SSE2 test failed")
   print("selftest: ok")
end


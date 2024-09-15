-- blit.lua - offload engine for memory operations

module(..., package.seeall)

local ffi = require("ffi")

-- The blit module provides "blitter" operation to offload
-- performance-critical memory operations. The API allows scheduling a
-- series of operations, that can be performed at any time and in any
-- order, and then executing a "barrier" to wait for completion.

-- The implementation in this file is very basic but could be extended
-- in the future to take advantage of the flexibility afforded by the
-- API to perform special optimizations (for example parallel memory
-- copies to amortize cache latency, etc).

function copy (dst, src, len)
   -- Trivial implementation: simply do an immediate memory copy.
   ffi.copy(dst, src, len)
end

-- Wait until all copies have completed.
function barrier ()
   -- No-op because the copies were already executed eagerly.
end

function selftest ()
   print("selftest: blit")
   -- It would be valuable to have an extensive selftest function to
   -- make it easy to develop and test new optimized blitter
   -- implementations.
   print("selftest: ok")
end

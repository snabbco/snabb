module(...,package.seeall)

local memory = require("memory")
local ffi = require("ffi")
local freelist = require("freelist")

require("packet_h")

max       = 10e5
allocated = 0
size      = 4096

buffers = freelist.new("struct buffer *", max)
buffer_t = ffi.typeof("struct buffer")

-- Return a ready-to-use buffer, or nil if none is available.
function allocate ()
   return freelist.remove(buffers) or new_buffer()
end

-- Return a newly created buffer, or nil if none can be created.
function new_buffer ()
   assert(allocated < max, "out of buffers")
   allocated = allocated + 1
   local pointer, physical, bytes = memory.dma_alloc(size)
   return ffi.new(buffer_t, pointer, physical, size)
end

-- Free a buffer that is no longer in use.
function free (b)
   freelist.add(buffers, b)
end

-- Create buffers until at least N are ready for use.
-- This is a way to pay the cost of allocating buffer memory in advance.
function preallocate (n)
   while freelist.nfree(buffers) < n do free(new_buffer()) end
end


--- Buffers represent Ethernet packets in memory. This is a young data
--- structure that is sure to undergo much evolution. For now buffers
--- have these properties:

--- - Buffers are reference-counted for automatic reuse. Buffers are
---   typically "ref'd" when they are placed on a transmit or receive
---   queue and then "deref'd" when processed by the DMA engine.
--- - Buffers consist of one 4096-byte buffer. (This won't last.)
--- - Buffers have a known physical and virtual address.

module(...,package.seeall)

local ffi = require("ffi")

ffi.cdef[[
struct buffer {
   char *ptr;    // Virtual address in this process.
   uint64_t phy; // Stable physical address.
   int maxsize;  // How many bytes available?
   int size;     // How many bytes used?
   int refcount; // How many users? minimum 1.
};
]]

buffer_t = ffi.typeof("struct buffer")

size = 4096 -- Size of every buffer allocated by this module.
max, allocated = 10e6, 0

freelist = {}
nfree = 0

--- Return a buffer with a refcount of 1.
function allocate ()
   if nfree == 0 then
      return new_buffer()
   else
      nfree = nfree - 1
      local buf = freelist[nfree]
      freelist[nfree] = nil
      return buf
   end
end

-- Get the cost of allocation (e.g. mapping huge pages) out of the way.
function preallocate (n) while nfree < n do free(new_buffer()) end end

function new_buffer ()
   assert(allocated < max)
   allocated = allocated + 1
   local ptr, phys, bytes = memory.dma_alloc(size)
   return ffi.new(buffer_t, ptr, phys, size, 0, 1)
end

function free (buf)
   freelist[nfree] = buf
   nfree = nfree + 1
end

--- A buffer is reused when it has been deref'd more than ref'd.
--- Exception: buffers with ref = 0 are not reused.

function ref (buf)
   buf.refcount = buf.refcount + 1
end

function deref (buf)
   assert(buf)
   if     buf.refcount == 0 then return 
   elseif buf.refcount == 1 then buf.size = 0  free(buf)
   else                          buf.refcount = buf.refcount -1 end
end


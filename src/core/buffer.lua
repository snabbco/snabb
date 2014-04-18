module(...,package.seeall)

local ffi = require("ffi")
local memory = require("core.memory")
local freelist = require("core.freelist")
local lib = require("core.lib")
local C = ffi.C

require("core.packet_h")

max       = 10e5
allocated = 0
size      = 4096

buffers = freelist.new("struct buffer *", max)
buffer_t = ffi.typeof("struct buffer")
buffer_ptr_t = ffi.typeof("struct buffer *")

-- Array of registered virtio devices.
-- This is used to return freed buffers to their devices.
virtio_devices = {}

--- ### Allocation

--- Return a ready-to-use buffer, or nil if none is available.
function allocate ()
   return freelist.remove(buffers) or new_buffer()
end

--- Return a newly created buffer, or nil if none can be created.
function new_buffer ()
   assert(allocated < max, "out of buffers")
   allocated = allocated + 1
   local pointer, physical, bytes = memory.dma_alloc(size)
   local b = lib.malloc("struct buffer")
   b.pointer, b.physical, b.size = pointer, physical, size
   return b
end

--- Free a buffer that is no longer in use.
function free (b)
   freelist.add(buffers, b)
   if b.origin.type == C.BUFFER_ORIGIN_VIRTIO then
      virtio_devices[b.origin.info.virtio.device_id]:return_virtio_buffer(b)
   end
end

--- Create buffers until at least N are ready for use.
--- This is a way to pay the cost of allocating buffer memory in advance.
function preallocate (n)
   while freelist.nfree(buffers) < n do free(new_buffer()) end
end

function add_virtio_device (d)
   local index = #virtio_devices + 1
   virtio_devices[index] = d
   return index
end

function delete_virtio_device (index)
   virtio_devices[index] = nil
end

-- fill's an allocated buffer with data from a string
function fill_data (b, d, offset)
   offset = offset or 0
   assert (offset+#d <= b.size, "can't fit on buffer")
   ffi.copy (b.pointer + offset, d, math.min(#d, b.size-offset))
end

-- creates a buffer from a given binary string
function from_data (d)
   local b = allocate()
   local size = math.min(#d, b.size)
   fill_data(b, d)
   return b
end

function tostring(b, size)
   return ffi.string(b.pointer, size or b.size)
end

module(...,package.seeall)

local ffi = require("ffi")
local memory = require("core.memory")
local freelist = require("core.freelist")
local lib = require("core.lib")
local C = ffi.C

require("core.packet_h")

max        = 10e5
allocated  = 0
buffersize = 4096

buffers = freelist.new("struct buffer *", max)
buffer_t = ffi.typeof("struct buffer")
buffer_ptr_t = ffi.typeof("struct buffer *")

-- Array of registered virtio devices.
-- This is used to return freed buffers to their devices.
virtio_devices = {}

-- Return a ready-to-use buffer, or nil if none is available.
function allocate ()
   return freelist.remove(buffers) or new_buffer()
end

-- Return a newly created buffer, or nil if none can be created.
function new_buffer ()
   assert(allocated < max, "out of buffers")
   allocated = allocated + 1
   local pointer, physical, bytes = memory.dma_alloc(buffersize)
   local b = lib.malloc("struct buffer")
   b.pointer, b.physical, b.size = pointer, physical, buffersize
   b.origin.type = C.BUFFER_ORIGIN_UNKNOWN
   b.refcount = 1;
   return b
end


local net_device = require("lib.virtio.net_device")
local return_virtio_buffer = net_device.VirtioNetDevice.return_virtio_buffer


-- Free a buffer that is no longer in use.
function free (b)
   if b.refcount > 1 then
      b.refcount = b.refcount - 1
   else
      if b.origin.type == C.BUFFER_ORIGIN_VIRTIO then
	 local dev = virtio_devices[b.origin.info.virtio.device_id]
	 return_virtio_buffer(dev, b)
      else
	 freelist.add(buffers, b)
      end
   end
end

-- Accessors for important structure elements.
function pointer (b)  return b.pointer  end
function physical (b) return b.physical end
function size (b)     return b.size     end

-- Create buffers until at least N are ready for use.
-- This is a way to pay the cost of allocating buffer memory in advance.
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


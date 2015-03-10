module(...,package.seeall)

local debug = _G.developer_debug

local ffi = require("ffi")
local C = ffi.C

local freelist = require("core.freelist")
local lib      = require("core.lib")
local memory   = require("core.memory")
local freelist_add, freelist_remove, freelist_nfree = freelist.add, freelist.remove, freelist.nfree

require("core.packet_h")

local packet_t = ffi.typeof("struct packet")
local packet_ptr_t = ffi.typeof("struct packet *")
local packet_size = ffi.sizeof(packet_t)
local header_size = 8
local max_payload = tonumber(C.PACKET_PAYLOAD_SIZE)

-- Freelist containing empty packets ready for use.
local max_packets = 1e5
local packet_allocation_step = 1000
local packets_allocated = 0
local packets_fl = freelist.new("struct packet *", max_packets)

-- Return an empty packet.
function allocate ()
   if freelist_nfree(packets_fl) == 0 then
      preallocate_step()
   end
   return freelist_remove(packets_fl)
end

-- Create a new empty packet.
function new_packet ()
   local p = ffi.cast(packet_ptr_t, memory.dma_alloc(packet_size))
   p.length = 0
   p.flags = 0
   p.csum_start = 0
   p.csum_offset = 0
   return p
end

-- Create an exact copy of a packet.
function clone (p)
   local p2 = allocate()
   ffi.copy(p2, p, p.length)
   p2.length = p.length
   p2.flags = p.flags
   p2.csum_start = p.csum_start
   p2.csum_offset = p.csum_offset
   return p2
end

-- Append data to the end of a packet.
function append (p, ptr, len)
   assert(p.length + len <= max_payload, "packet payload overflow")
   ffi.copy(p.data + p.length, ptr, len)
   p.length = p.length + len
   return p
end

function shift_csum (p, len)
   if p.csum_start > 0 and p.csum_start < p.length then
      p.csum_start = math.max(0, p.csum_start + len)
   end
end

-- Prepend data to the start of a packet.
function prepend (p, ptr, len, do_shift)
   assert(p.length + len <= max_payload, "packet payload overflow")
   C.memmove(p.data + len, p.data, p.length) -- Move the existing payload
   ffi.copy(p.data, ptr, len)                -- Fill the gap
   if do_shift then
      shift_csum(p, len)
   end
   p.length = p.length + len
   return p
end

-- Move packet data to the left. This shortens the packet by dropping
-- the header bytes at the front.
function shiftleft (p, bytes, do_shift)
   C.memmove(p.data, p.data+bytes, p.length-bytes)
   if do_shift then
      shift_csum(p, -bytes)
   end
   p.length = p.length - bytes
end

-- Conveniently create a packet by copying some existing data.
function from_pointer (ptr, len) return append(allocate(), ptr, len) end
function from_string (d)         return from_pointer(d, #d) end

function dump(p, w)
   w = w or io.write
   w(('packet at %s(%d): flags 0x%X, csum_start 0x%X, csum_offset 0x%X'):format(
      p.data, p.length, p.flags, p.csum_start, p.csum_offset))
   for i = 0, p.length-1 do
      if i % 16 == 0 then
         w(('\n%04X: '):format(i))
      end
      w(bit.tohex(p.data[i], -2)..' ')
   end
   w('\n')
end

-- Free a packet that is no longer in use.
function free (p)
   --ffi.fill(p, header_size, 0)
   p.length = 0
   freelist_add(packets_fl, p)
end

-- Return pointer to packet data.
function data (p) return p.data end

-- Return packet data length.
function length (p) return p.length end

function preallocate_step()
   if _G.developer_debug then
      assert(packets_allocated + packet_allocation_step <= max_packets)
   end

   for i=1, packet_allocation_step do
      free(new_packet())
   end
   packets_allocated = packets_allocated + packet_allocation_step
   packet_allocation_step = 2 * packet_allocation_step
end

--preallocate packets freelist
if freelist_nfree(packets_fl) == 0 then
   preallocate_step()
end

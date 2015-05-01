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
   return p
end

-- Create an exact copy of a packet.
function clone (p)
   local p2 = allocate()
   ffi.copy(p2, p, p.length)
   p2.length = p.length
   return p2
end

-- Append data to the end of a packet.
function append (p, ptr, len)
   assert(p.length + len <= max_payload, "packet payload overflow")
   ffi.copy(p.data + p.length, ptr, len)
   p.length = p.length + len
   return p
end

-- Prepend data to the start of a packet.
function prepend (p, ptr, len)
   assert(p.length + len <= max_payload, "packet payload overflow")
   C.memmove(p.data + len, p.data, p.length) -- Move the existing payload
   ffi.copy(p.data, ptr, len)                -- Fill the gap
   p.length = p.length + len
   return p
end

-- Move packet data to the left. This shortens the packet by dropping
-- the header bytes at the front.
function shiftleft (p, bytes)
   C.memmove(p.data, p.data+bytes, p.length-bytes)
   p.length = p.length - bytes
end

-- Conveniently create a packet by copying some existing data.
function from_pointer (ptr, len) return append(allocate(), ptr, len) end
function from_string (d)         return from_pointer(d, #d) end

-- Free a packet that is no longer in use.
local function free_internal (p)
   p.length = 0
   freelist_add(packets_fl, p)
end

function free (p)
   engine.frees = engine.frees + 1
   engine.freebytes = engine.freebytes + p.length
   -- Calculate bits of physical capacity required for packet on 10GbE
   -- Account for minimum data size and overhead of CRC and inter-packet gap
   engine.freebits = engine.freebits + (math.max(p.length, 46) + 4 + 5) * 8
   free_internal(p)
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
      free_internal(new_packet(), true)
   end
   packets_allocated = packets_allocated + packet_allocation_step
   packet_allocation_step = 2 * packet_allocation_step
end

ffi.metatype(packet_t, {__index = {
   clone = clone,
   append = append,
   prepend = prepend,
   shiftleft = shiftleft,
   free = free,
   data = data,
   length = length,
}})

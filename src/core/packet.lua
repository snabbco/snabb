-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local debug = _G.developer_debug

local ffi = require("ffi")
local bit = require("bit")
local C = ffi.C

local lib      = require("core.lib")
local memory   = require("core.memory")
local counter  = require("core.counter")

require("core.packet_h")

local packet_t = ffi.typeof("struct packet")
local packet_ptr_t = ffi.typeof("struct packet *")
local packet_size = ffi.sizeof(packet_t)
max_payload = tonumber(C.PACKET_PAYLOAD_SIZE)

-- For operations that add or remove headers from the beginning of a
-- packet, instead of copying around the payload we just move the
-- packet structure as a whole around.
local packet_alignment = 512
local default_headroom = 256

-- Freelist containing empty packets ready for use.

ffi.cdef[[
struct freelist {
    uint64_t nfree;
    uint64_t max;
    struct packet *list[?];
};
]]

local function freelist_add(freelist, element)
   -- Safety check
   if _G.developer_debug then
      assert(freelist.nfree < freelist.max, "freelist overflow")
   end
   freelist.list[freelist.nfree] = element
   freelist.nfree = freelist.nfree + 1
end

local function freelist_remove(freelist)
   if freelist.nfree == 0 then
      error("no free packets")
   else
      freelist.nfree = freelist.nfree - 1
      return freelist.list[freelist.nfree]
   end
end

local function freelist_nfree(freelist)
   return freelist.nfree
end

local max_packets = 1e6
local packet_allocation_step = 1000
local packets_allocated = 0
local packets_fl = ffi.new("struct freelist", max_packets, 0, max_packets)

-- Return an empty packet.
function allocate ()
   if freelist_nfree(packets_fl) == 0 then
      preallocate_step()
   end
   return freelist_remove(packets_fl)
end

-- Create a new empty packet.
function new_packet ()
   local base = memory.dma_alloc(packet_size + packet_alignment,
                                 packet_alignment)
   local p = ffi.cast(packet_ptr_t, base + default_headroom)
   p.length = 0
   return p
end

-- Create an exact copy of a packet.
function clone (p)
   return from_pointer(p.data, p.length)
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
   p = shiftright(p, len)
   ffi.copy(p.data, ptr, len)                -- Fill the gap
   return p
end

-- Move packet data to the left. This shortens the packet by dropping
-- the header bytes at the front.
function shiftleft (p, bytes)
   assert(bytes >= 0 and bytes <= p.length)
   local ptr = ffi.cast("char*", p)
   local len = p.length
   local headroom = bit.band(ffi.cast("uint64_t", ptr), packet_alignment - 1)
   -- We only have a certain amount of headroom, otherwise the end of
   -- p.data will point out of our allocation.  If we're withing the
   -- alignment wiggle room, just move the packet around.  Otherwise
   -- copy the payload, but also reset the headroom at the same time.
   if bytes + headroom < packet_alignment then
      p = ffi.cast(packet_ptr_t, ptr + bytes)
      p.length = len - bytes
      return p
   else
      local delta_headroom = default_headroom - headroom
      C.memmove(p.data + delta_headroom, p.data + bytes, len - bytes)
      p = ffi.cast(packet_ptr_t, ptr + delta_headroom)
      p.length = len - bytes
      return p
   end
end

-- Move packet data to the right. This leaves length bytes of data
-- at the beginning of the packet.
function shiftright (p, bytes)
   local ptr = ffi.cast("char*", p)
   local len = p.length
   local headroom = bit.band(ffi.cast("uint64_t", ptr), packet_alignment - 1)
   if bytes <= headroom then
      -- Take from the headroom.
      p = ffi.cast(packet_ptr_t, ptr - bytes)
      p.length = len + bytes
      return p
   else
      -- No headroom for the shift; re-set the headroom to the default.
      assert(bytes <= max_payload - len)
      local delta_headroom = default_headroom - headroom
      C.memmove(p.data + bytes + delta_headroom, p.data, len)
      p = ffi.cast(packet_ptr_t, ptr + delta_headroom)
      p.length = len + bytes
      return p
   end
end

-- Conveniently create a packet by copying some existing data.
function from_pointer (ptr, len) return append(allocate(), ptr, len) end
function from_string (d)         return from_pointer(d, #d) end

-- Free a packet that is no longer in use.
local function free_internal (p)
   local ptr = ffi.cast("char*", p)
   local headroom = bit.band(ffi.cast("uint64_t", ptr), packet_alignment - 1)
   p = ffi.cast(packet_ptr_t, ptr - headroom + default_headroom)
   p.length = 0
   freelist_add(packets_fl, p)
end   

function free (p)
   counter.add(engine.frees)
   counter.add(engine.freebytes, p.length)
   -- Calculate bits of physical capacity required for packet on 10GbE
   -- Account for minimum data size and overhead of CRC and inter-packet gap
   counter.add(engine.freebits, (math.max(p.length, 46) + 4 + 5) * 8)
   free_internal(p)
end

-- Set packet data length.
function resize (p, len)
   assert(len <= max_payload, "packet payload overflow")
   ffi.fill(p.data + p.length, math.max(0, len - p.length))
   p.length = len
end

function preallocate_step()
   assert(packets_allocated + packet_allocation_step <= max_packets,
          "packet allocation overflow")

   for i=1, packet_allocation_step do
      free_internal(new_packet(), true)
   end
   packets_allocated = packets_allocated + packet_allocation_step
   packet_allocation_step = 2 * packet_allocation_step
end


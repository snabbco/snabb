module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

local buffer   = require("core.buffer")
local freelist = require("core.freelist")
local memory   = require("core.memory")

require("core.packet_h")

initial_fuel = 1000
max_packets = 1e6
packets_fl = freelist.new("struct packet *", max_packets)
packets    = ffi.new("struct packet[?]", max_packets)

function module_init ()
   for i = 0, max_packets-1 do
      free(packets[i])
   end
end

-- Return a packet, or nil if none is available.
function allocate ()
   return freelist.remove(packets_fl) or error("out of packets")
end

-- Append data to a packet.
function add_iovec (p, b, length,  offset)
   assert(p.niovecs < C.PACKET_IOVEC_MAX, "packet iovec overflow")
   offset = offset or 0
   assert(length + offset <= b.size)
   local iovec = p.iovecs[p.niovecs]
   iovec.buffer = b
   iovec.length = length
   iovec.offset = offset
   p.niovecs = p.niovecs + 1
   p.length = p.length + length
end

-- Increase the reference count for packet p.
function ref (p)
   p.refcount = p.refcount + 1
   return p
end

-- Decrease the reference count for packet p.
-- The packet will be recycled if the reference count reaches 0.
function deref (p)
   if p.refcount == 1 then
      free(p)
   elseif p.refcount > 1 then
      p.refcount = p.refcount - 1
   end
   return p
end

-- Tenured packets are not reused by defref().
function tenure (p)
   p.refcount = 0
end

-- Free a packet and all of its buffers.
function free (p)
   for i = 0, p.niovecs-1 do
      buffer.free(p.iovecs[i].buffer)
   end
   p.info.flags     = 0
   p.info.gso_flags = 0
   p.refcount       = 1
   p.fuel           = initial_fuel
   p.niovecs        = 0
   freelist.add(packets_fl, p)
end

module_init()

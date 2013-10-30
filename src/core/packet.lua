module(...,package.seeall)

local debug = false

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
   if debug then assert(p.niovecs < C.PACKET_IOVEC_MAX, "packet iovec overflow") end
   offset = offset or 0
   if debug then assert(length + offset <= b.size) end
   local iovec = p.iovecs[p.niovecs]
   iovec.buffer = b
   iovec.length = length
   iovec.offset = offset
   p.niovecs = p.niovecs + 1
   p.length = p.length + length
end

-- Increase the reference count for packet p by n (default n=1).
function ref (p,  n)
   if p.refcount > 0 then
      p.refcount = p.refcount + (n or 1)
   end
   return p
end

-- Decrease the reference count for packet p.
-- The packet will be recycled if the reference count reaches 0.
function deref (p,  n)
   n = n or 1
   if p.refcount > 0 then
      assert(p.refcount >= n)
      if n == p.refcount then
         free(p)
      else
         p.refcount = p.refcount - n
      end
   end
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
   p.length         = 0
   freelist.add(packets_fl, p)
end

module_init()

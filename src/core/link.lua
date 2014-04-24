module(...,package.seeall)

local debug = true

local ffi = require("ffi")
local C = ffi.C

local packet = require("core.packet")
require("core.packet_h")
require("core.link_h")

local size = C.LINK_RING_SIZE         -- NB: Huge slow-down if this is not local
max        = C.LINK_MAX_PACKETS

function new (receiving_app)
   return ffi.new("struct link", {receiving_app = receiving_app})
end

function receive (r)
   if debug then assert(not empty(r), "receive on empty link") end
   local p = r.packets[r.read]
   r.read = (r.read + 1) % size
   r.stats.rxpackets = r.stats.rxpackets + 1
   r.stats.rxbytes   = r.stats.rxbytes + p.length
   return p
end

function transmit (r, p)
   assert(p)
   if full(r) then
      r.stats.txdrop = r.stats.txdrop + 1
   else
      r.packets[r.write] = p
      r.write = (r.write + 1) % size
      r.stats.txpackets = r.stats.txpackets + 1
      r.stats.txbytes   = r.stats.txbytes + p.length
      r.has_new_data = true
   end
end

-- Return true if the ring is empty.
function empty (r)
   return r.read == r.write
end

-- Return true if the ring is full.
function full (r)
   return (r.write + 1) % size == r.read
end

-- Return the number of packets that are ready for read.
function nreadable (r)
   if r.read > r.write then
      return r.write + size - r.read
   else
      return r.write - r.read
   end
end

function nwritable (r)
   return max - nreadable(r)
end

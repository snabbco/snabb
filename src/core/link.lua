module(...,package.seeall)

local debug = false

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
   if debug then assert(p) end
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

function stats (r)
   return r.stats
end

function selftest ()
   print("selftest: link")
   local r = new()
   local p = packet.allocate()
   packet.tenure(p)
   assert(r.stats.txpackets == 0 and empty(r) == true  and full(r) == false)
   assert(nreadable(r) == 0)
   transmit(r, p)
   assert(r.stats.txpackets == 1 and empty(r) == false and full(r) == false)
   for i = 1, max-2 do
      transmit(r, p)
   end
   assert(r.stats.txpackets == max-1 and empty(r) == false and full(r) == false)
   assert(nreadable(r) == r.stats.txpackets)
   transmit(r, p)
   assert(r.stats.txpackets == max   and empty(r) == false and full(r) == true)
   transmit(r, p)
   assert(r.stats.txpackets == max and r.stats.txdrop == 1)
   assert(not empty(r) and full(r))
   while not empty(r) do
      receive(r)
   end
   assert(r.stats.rxpackets == max)
   print("selftest OK")
end


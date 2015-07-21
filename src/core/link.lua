module(...,package.seeall)

local debug = _G.developer_debug

local ffi = require("ffi")
local C = ffi.C

local packet = require("core.packet")
require("core.packet_h")
require("core.link_h")

local band = require("bit").band

local size = C.LINK_RING_SIZE         -- NB: Huge slow-down if this is not local
max        = C.LINK_MAX_PACKETS

function new (receiving_app)
   return ffi.new("struct link", {receiving_app = receiving_app})
end

function receive (r)
--   if debug then assert(not empty(r), "receive on empty link") end
   local p = r.packets[band(r.read, size-1)]
   r.read = r.read + 1
   return p
end

function front (r)
   return (r.read ~= r.write) and r.packets[r.read] or nil
end

function transmit (r, p)
--   assert(p)
   if full(r) then
      r.stats.txdrop = r.stats.txdrop + 1
      packet.free(p)
   else
      r.packets[band(r.write, size-1)] = p
      r.write = r.write + 1
      r.has_new_data = true
   end
end

-- Return true if the ring is empty.
function empty (r)
   return r.read == r.write
end

-- Return true if the ring is full.
function full (r)
   return band(r.write + 1, size - 1) == r.read
end

-- Return the number of packets that are ready for read.
function nreadable (r)
   return r.write - r.read
end

function nwritable (r)
   return max - nreadable(r)
end

function stats (r)
   return { rxpackets = tonumber(r.read),
            txpackets = tonumber(r.write),
            txdropped = tonumber(r.dropped) }
end

function selftest ()
   print("selftest: link")
   local r = new()
   local p = packet.allocate()
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


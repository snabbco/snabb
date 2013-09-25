module(...,package.seeall)

local debug = false

local ffi = require("ffi")
local C = ffi.C

local packet = require("core.packet")
require("core.packet_h")
require("core.link_ring_h")

size = C.LINK_RING_SIZE
max  = C.LINK_RING_MAX_PACKETS

function new (name, from_app, to_app)
   return ffi.new("struct link_ring")
end

function receive (r)
   if debug then assert(not empty(r), "receive on empty link") end
   local p = r.packets[r.read]
   r.read = (r.read + 1) % size
   r.stats.rx = r.stats.rx + 1
   return p
end

function transmit (r, p)
   if debug and full(r) then
      r.stats.drop = r.stats.drop + 1
   else
      packet.ref(p)
      r.packets[r.write] = p
      r.write = (r.write + 1) % size
      r.stats.tx = r.stats.tx + 1
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

-- deref all newly read packets.
function cleanup_after_receive (r)
   while r.deref ~= r.read do
      packet.deref(r.packets[r.deref])
      r.deref = (r.deref) + 1 % size
   end
end

function selftest ()
   print("selftest: link")
   local r = new()
   local p = packet.allocate()
   packet.tenure(p)
   assert(r.stats.tx == 0 and empty(r) == true  and full(r) == false)
   assert(nreadable(r) == 0)
   transmit(r, p)
   assert(r.stats.tx == 1 and empty(r) == false and full(r) == false)
   for i = 1, max-2 do
      transmit(r, p)
   end
   assert(r.stats.tx == max-1 and empty(r) == false and full(r) == false)
   assert(nreadable(r) == r.stats.tx)
   transmit(r, p)
   assert(r.stats.tx == max   and empty(r) == false and full(r) == true)
   transmit(r, p)
   assert(r.stats.tx == max and r.stats.drop == 1)
   assert(not empty(r) and full(r))
   assert(r.deref == 0)
   cleanup_after_receive(r)
   assert(r.deref == 0)
   while not empty(r) do
      receive(r)
   end
   assert(r.stats.rx == max)
   cleanup_after_receive(r)
   assert(r.deref == r.read)
   print("selftest OK")
end


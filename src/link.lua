module(...,package.seeall)

local packet = require("packet")
local ffi = require("ffi")
local C = ffi.C

require("packet_h")
require("link_h")

size = C.LINK_RING_SIZE
max  = C.LINK_RING_MAX_PACKETS

function new (name, from_app, to_app)
   return { name = name,
	    from_app = from_app,
	    to_app = to_app,
	    ring = ffi.new("struct link") }
end

function receive (l)
   assert(not empty(l), "receive on empty link")
   local r = l.ring
   local p = r.packets[r.head]
   r.head = (r.head + 1) % size
   r.stats.rx = r.stats.rx + 1
   return p
end

function transmit (l, p)
   local r = l.ring
   if full(l) then
      r.stats.drop = r.stats.drop + 1
   else
      r.packets[r.tail] = p
      r.tail = (r.tail + 1) % size
      r.stats.tx = r.stats.tx + 1
   end
end

function empty (l)
   return l.ring.head == l.ring.tail
end

function full (l)
   return (l.ring.tail + 1) % size == l.ring.head
end

function size2 (l)
   local r = l.ring
   if r.head > r.tail then
      return max - r.tail + r.head
   else
      return r.tail - r.head
   end
end

function selftest ()
   print("selftest: link")
   local l = new()
   local r = l.ring
   local p = packet.allocate()
   assert(r.stats.tx == 0 and empty(l) == true  and full(l) == false)
   assert(size2(l) == 0)
   transmit(l, p)
   assert(r.stats.tx == 1 and empty(l) == false and full(l) == false)
   for i = 1, max-2 do
      transmit(l, p)
   end
   assert(r.stats.tx == max-1 and empty(l) == false and full(l) == false)
   assert(size2(l) == r.stats.tx)
   transmit(l, p)
   assert(r.stats.tx == max   and empty(l) == false and full(l) == true)
   transmit(l, p)
   assert(r.stats.tx == max and r.stats.drop == 1)
   assert(not empty(l) and full(l))
   while not empty(l) do
      receive(l)
   end
   assert(r.stats.rx == max)
   print("selftest OK")
end


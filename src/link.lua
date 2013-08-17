module(...,package.seeall)

local packet = require("packet")
local ffi = require("ffi")
local C = ffi.C

require("packet_h")
require("link_h")

size = C.LINK_RING_SIZE
max  = C.LINK_RING_MAX_PACKETS

function new ()
   return ffi.new("struct link")
end

function receive (l)
   assert(not empty(l), "receive on empty link")
   local p = l.packets[l.tail]
   l.tail = (l.tail + 1) % size
   l.stats.rx = l.stats.rx + 1
   return p
end

function transmit (l, p)
   if full(l) then
      l.stats.drop = l.stats.drop + 1
   else
      l.packets[l.head] = p
      l.head = (l.head + 1) % size
      l.stats.tx = l.stats.tx + 1
   end
end

function empty (l)
   return l.head == l.tail
end

function full (l)
   return (l.head + 1) % size == l.tail
end

function selftest ()
   print("selftest: link")
   l = new()
   p = packet.allocate()
   assert(l.stats.tx == 0 and empty(l) == true  and full(l) == false)
   transmit(l, p)
   assert(l.stats.tx == 1 and empty(l) == false and full(l) == false)
   for i = 1, max-2 do
      transmit(l, p)
   end
   assert(l.stats.tx == max-1 and empty(l) == false and full(l) == false)
   transmit(l, p)
   assert(l.stats.tx == max   and empty(l) == false and full(l) == true)
   transmit(l, p)
   assert(l.stats.tx == max and l.stats.drop == 1)
   assert(not empty(l) and full(l))
   while not empty(l) do
      receive(l)
   end
   assert(l.stats.rx == max)
   print("selftest OK")
end


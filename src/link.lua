module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C

require("packet_h")
require("link_h")

max = C.LINK_MAX_PACKETS;

function new ()
   return ffi.new("struct link")
end

function receive (l)
   assert(not empty(l), "receive on empty link")
   local p = l.packets[l.tail]
   l.tail = (l.tail + 1) % max
   return l.packets[index]
end

function transmit (l, p)
   if full(l) then
      l.stats.drop = l.stats.drop + 1
   else
      l.packets[l.head] = p
      l.head = (l.head + 1) % max
   end
end

function empty (l)
   return l.head == l.tail
end

function full (l)
   return (l.head + 1) % max == l.tail
end

function selftest ()
   print("selftest: link")
   l = new()
   assert(empty(l))
   
   print("link:", new())
end


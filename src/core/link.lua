module(...,package.seeall)

local debug = _G.developer_debug

local shm = require("core.shm")
local ffi = require("ffi")
local C = ffi.C

local packet = require("core.packet")
require("core.packet_h")

local counter = require("core.counter")
local counter_add, counter_read = counter.add, counter.read
require("core.counter_h")

require("core.link_h")

local band = require("bit").band

local size = C.LINK_RING_SIZE         -- NB: Huge slow-down if this is not local
max        = C.LINK_MAX_PACKETS

local counternames = {"rxpackets", "txpackets", "rxbytes", "txbytes", "txdrop"}

function new (name)
   local r = shm.map("links/"..name, "struct link")
   for _, c in ipairs(counternames) do
      r.stats[c] = counter.open("counters/"..name.."/"..c)
   end
   return r
end

function free (r, name)
   for _, c in ipairs(counternames) do
      counter.delete("counters/"..name.."/"..c)
   end
   shm.unmap(r)
   shm.unlink("links/"..name)
end

function receive (r)
--   if debug then assert(not empty(r), "receive on empty link") end
   local p = r.packets[r.read]
   r.read = band(r.read + 1, size - 1)

   counter_add(r.stats.rxpackets)
   counter_add(r.stats.rxbytes, p.length)
   return p
end

function front (r)
   return (r.read ~= r.write) and r.packets[r.read] or nil
end

function transmit (r, p)
--   assert(p)
   if full(r) then
      counter_add(r.stats.txdrop)
      packet.free(p)
   else
      r.packets[r.write] = p
      r.write = band(r.write + 1, size - 1)
      counter_add(r.stats.txpackets)
      counter_add(r.stats.txbytes, p.length)
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
   local stats = {}
   for _, c
   in ipairs(counternames) do
      stats[c] = tonumber(counter_read(r.stats[c]))
   end
   return stats
end

function selftest ()
   print("selftest: link")
   local r = new("test")
   local p = packet.allocate()
   assert(counter_read(r.stats.txpackets) == 0 and empty(r) == true  and full(r) == false)
   assert(nreadable(r) == 0)
   transmit(r, p)
   assert(counter_read(r.stats.txpackets) == 1 and empty(r) == false and full(r) == false)
   for i = 1, max-2 do
      transmit(r, p)
   end
   assert(counter_read(r.stats.txpackets) == max-1 and empty(r) == false and full(r) == false)
   assert(nreadable(r) == counter_read(r.stats.txpackets))
   transmit(r, p)
   assert(counter_read(r.stats.txpackets) == max   and empty(r) == false and full(r) == true)
   transmit(r, p)
   assert(counter_read(r.stats.txpackets) == max and counter_read(r.stats.txdrop) == 1)
   assert(not empty(r) and full(r))
   while not empty(r) do
      receive(r)
   end
   assert(counter_read(r.stats.rxpackets) == max)
   link.free(r, "test")
   print("selftest OK")
end


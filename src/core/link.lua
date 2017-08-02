-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local debug = _G.developer_debug

local shm = require("core.shm")
local ffi = require("ffi")
local C = ffi.C

local packet = require("core.packet")
require("core.packet_h")

local counter = require("core.counter")
require("core.counter_h")

require("core.link_h")
local link_t = ffi.typeof("struct link")

local band = require("bit").band

local size = C.LINK_RING_SIZE         -- NB: Huge slow-down if this is not local
max        = C.LINK_MAX_PACKETS

local provided_counters = {
   "dtime", "rxpackets", "rxbytes", "txpackets", "txbytes", "txdrop"
}

function new (name)
   local r = shm.create("links/"..name.."/link", link_t)
   counter.set(r.dtime, C.get_unix_time())
   return r
end

function open (path)
   local r = shm.open(path.."/link", link_t)
   return r
end

function free (r, name)
   shm.unlink("links/"..name)
end

local function NEXT (i)
   return band(i + 1, size - 1)
end

function receive (r)
--   if debug then assert(not empty(r), "receive on empty link") end
   local p = r.packets[r.nread]
   r.nread = NEXT(r.nread)

   counter.add(r.rxpackets)
   counter.add(r.rxbytes, p.length)
   return p
end

function front (r)
   return (not empty(r)) and r.packets[r.nread] or nil
end

-- Return true if the ring is empty.
function empty (r)
   if r.nread == r.lwrite then
      if r.nread == r.write then
         return true
      end
      r.lwrite = r.write
   end
   return false
end

function transmit (r, p)
--   assert(p)
   if full(r) then
      counter.add(r.txdrop)
      packet.free(p)
   else
      r.packets[r.nwrite] = p
      r.nwrite = NEXT(r.nwrite)
      counter.add(r.txpackets)
      counter.add(r.txbytes, p.length)
   end
end

-- Return true if the ring is full.
function full (r)
   local after_nwrite = NEXT(r.nwrite)
   if after_nwrite == r.lread then
      if after_nwrite == r.read then
         return true
      end
      r.lread = r.read
   end
   return false
end

-- Return the number of packets that are ready for read.
function nreadable (r)
   if r.nread > r.write then
      return r.write + size - r.nread
   else
      return r.write - r.nread
   end
end

function nwriteable (r)
   if r.read > r.nwrite then
      return max - (r.nwrite + size - r.read)
   else
      return max - (r.nwrite - r.read)
   end
end

function produce (r)
   r.write = r.nwrite
end

function consume (r)
   r.read = r.nread
end

function stats (r)
   local stats = {}
   for _, c in ipairs(provided_counters) do
      stats[c] = tonumber(counter.read(r[c]))
   end
   return stats
end

function selftest ()
   print("selftest: link")
   local r = new("test")
   local p = packet.allocate()
   assert(counter.read(r.stats.txpackets) == 0 and empty(r) == true  and full(r) == false)
   assert(nreadable(r) == 0)
   transmit(r, p)
   assert(counter.read(r.stats.txpackets) == 1 and empty(r) == false and full(r) == false)
   for i = 1, max-2 do
      transmit(r, p)
   end
   assert(counter.read(r.stats.txpackets) == max-1 and empty(r) == false and full(r) == false)
   assert(nreadable(r) == counter.read(r.stats.txpackets))
   transmit(r, p)
   assert(counter.read(r.stats.txpackets) == max   and empty(r) == false and full(r) == true)
   transmit(r, p)
   assert(counter.read(r.stats.txpackets) == max and counter.read(r.stats.txdrop) == 1)
   assert(not empty(r) and full(r))
   while not empty(r) do
      receive(r)
   end
   assert(counter.read(r.stats.rxpackets) == max)
   link.free(r, "test")
   print("selftest OK")
end


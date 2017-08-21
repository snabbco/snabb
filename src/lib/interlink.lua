-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- Based on MCRingBuffer, see
--   http://www.cse.cuhk.edu.hk/%7Epclee/www/pubs/ipdps10.pdf

local shm = require("core.shm")
local ffi = require("ffi")
local band = require("bit").band
local waitfor = require("core.lib").waitfor
local full_memory_barrier = ffi.C.full_memory_barrier

local SIZE = link.max + 1
local CACHELINE = 64 -- XXX - make dynamic
local INT = ffi.sizeof("int")

assert(band(SIZE, SIZE-1) == 0, "SIZE is not a power of two")

local status = { Locked = 0, Unlocked = 1 }

ffi.cdef([[ struct interlink {
   char pad0[]]..CACHELINE..[[];
   int read, write, lock;
   char pad1[]]..CACHELINE-3*INT..[[];
   int lwrite, nread;
   char pad2[]]..CACHELINE-2*INT..[[];
   int lread, nwrite;
   char pad3[]]..CACHELINE-2*INT..[[];
   struct packet *packets[]]..SIZE..[[];
}]])

function create (name)
   local r = shm.create(name, "struct interlink")
   for i = 0, link.max do
      r.packets[i] = packet.allocate()
   end
   full_memory_barrier()
   r.lock = status.Unlocked
   return r
end

function free (r)
   r.lock = status.Locked
   full_memory_barrier()
   local function ring_consistent ()
      return r.write == r.nwrite and r.read == r.nread
   end
   waitfor(ring_consistent)
   for i = 0, link.max do
      packet.free(r.packets[i])
   end
   shm.unmap(r)
end

function open (name)
   local r = shm.open(name, "struct interlink")
   waitfor(function () return r.lock == status.Unlocked end)
   full_memory_barrier()
   return r
end

local function NEXT (i)
   return band(i + 1, link.max)
end

function full (r)
   local after_nwrite = NEXT(r.nwrite)
   if after_nwrite == r.lread then
      if after_nwrite == r.read or r.lock == status.Locked then
         return true
      end
      r.lread = r.read
   end
end

function insert (r, p)
   packet.free(r.packets[r.nwrite])
   r.packets[r.nwrite] = p
   r.nwrite = NEXT(r.nwrite)
end

function push (r)
   full_memory_barrier()
   r.write = r.nwrite
end

function empty (r)
   if r.nread == r.lwrite then
      if r.nread == r.write or r.lock == status.Locked then
         return true
      end
      r.lwrite = r.write
   end
end

function extract (r)
   local p = r.packets[r.nread]
   r.packets[r.nread] = packet.allocate()
   r.nread = NEXT(r.nread)
   return p
end

function pull (r)
   full_memory_barrier()
   r.read = r.nread
end

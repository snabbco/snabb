-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local shm = require("core.shm")
local ffi = require("ffi")
local band = require("bit").band

function mcp_t (size)
   local cacheline = 64 -- XXX - make dynamic
   local int = ffi.sizeof("int")
   return ffi.typeof([[struct {
      char pad0[]]..cacheline..[[];
      int read, write;
      char pad1[]]..cacheline-2*int..[[];
      int lwrite, nread;
      char pad2[]]..cacheline-2*int..[[];
      int lread, nwrite;
      char pad3[]]..cacheline-2*int..[[];
      int max;
      char pad4[]]..cacheline-1*int..[[];
      struct packet *packets[]]..size..[[];
   }]])
end

function create (size, name)
   assert(band(size, size-1) == 0, "size is not a power of two")
   local r = shm.create(name, mcp_t(size))
   r.max = size - 1
   r.nwrite = r.max -- “full” until initlaized
   return r
end

function init (r) -- initialization must be performed by consumer
   assert(full(r) and empty(r)) -- only satisfied if uninitialized
   repeat
      r.packets[r.nwrite] = packet.allocate()
      r.nwrite = r.nwrite - 1
   until r.nwrite == 0
   r.packets[r.nwrite] = packet.allocate()
end

local function NEXT (r, i)
   return band(i + 1, r.max)
end

function full (r)
   local after_nwrite = NEXT(r, r.nwrite)
   if after_nwrite == r.lread then
      if after_nwrite == r.read then
         return true
      end
      r.lread = r.read
   end
end

function insert (r, p)
   packet.free(r.packets[r.nwrite])
   r.packets[r.nwrite] = p
   r.nwrite = NEXT(r, r.nwrite)
end

function push (r)
   r.write = r.nwrite
end

function empty (r)
   if r.nread == r.lwrite then
      if r.nread == r.write then
         return true
      end
      r.lwrite = r.write
   end
end

function extract (r)
   local p = r.packets[r.nread]
   r.packets[r.nread] = packet.allocate()
   r.nread = NEXT(r, r.nread)
   return p
end

function pull (r)
   r.read = r.nread
end

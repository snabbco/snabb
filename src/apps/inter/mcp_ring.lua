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
      int lwrite, nread, rbatch;
      char pad2[]]..cacheline-3*int..[[];
      int lread, nwrite, wbatch;
      char pad3[]]..cacheline-3*int..[[];
      int max, batch;
      char pad4[]]..cacheline-2*int..[[];
      struct packet *packets[]]..size..[[];
   }]])
end

function create_mcp (size, batch, name)
   assert(band(size, size-1) == 0, "size is not a power of two")
   assert(batch <= size, "batch is greater than size")
   local r = shm.create(name, mcp_t(size))
   r.max = size-1
   r.batch = batch
   return r
end

local function NEXT (r, i)
   return band(i + 1, r.max)
end

function mcp_insert (r, p)
   local after_nwrite = NEXT(r, r.nwrite)
   if after_nwrite == r.lread then
      if after_nwrite == r.read then
         return false
      end
      r.lread = r.read
   end
   r.packets[r.nwrite] = p
   r.nwrite = after_nwrite
   r.wbatch = r.wbatch + 1
   if r.wbatch >= r.batch then
      r.write = r.nwrite
      r.wbatch = 0
   end
   return true
end

function mcp_push (r)
   if r.wbatch > 0 then
      r.write = r.nwrite
      r.wbatch = 0
   end
end

function mcp_extract (r)
   if r.nread == r.lwrite then
      if r.nread == r.write then
         return nil
      end
      r.lwrite = r.write
   end
   local p = r.packets[r.nread]
   r.nread = NEXT(r, r.nread)
   r.rbatch = r.rbatch + 1
   if r.rbatch > r.batch then
      r.read = r.nread
      r.rbatch = 0
   end
   return p
end

function mcp_pull (r)
   if r.rbatch > 0 then
      r.read = r.nread
      r.rbatch = 0
   end
end

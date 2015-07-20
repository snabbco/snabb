
local ffi = require('ffi')
local lib = require('core.lib')
local shm = require('core.shm')

ffi.cdef [[
   typedef struct {
      uint64_t frees, freebytes, freebits;
   } stats_t;
]]

local stats_t = ffi.typeof('stats_t')
local stats = {}
stats.__index = stats


function stats:__new(pid)
   if pid == nil then
      local o = shm.map('/core.stats', stats_t)
      ffi.fill(o, ffi.sizeof(stats_t))
      return o
   else
      return shm.map(('//%d/core.stats'):format(pid), stats_t, true)
   end
end


function stats:add(p)
   self.frees = self.frees + 1
   self.freebytes = self.freebytes + p.length
   self.freebits = self.freebits + (math.max(p.length, 46) + 4 + 5) * 8
end


function stats:accumulate(o)
   self.frees = self.frees + o.frees
   self.freebytes = self.freebytes + o.freebytes
   self.freebits = self.freebits + o.freebits
end


function stats:__tostring ()
   return string.format("frees: %10s\t Bytes: %10s\t Bits: %10s\n",
      lib.comma_value(self.frees), lib.comma_value(self.freebytes), lib.comma_value(self.freebits))
end


return ffi.metatype(stats_t, stats)

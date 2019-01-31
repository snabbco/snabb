module(..., package.seeall)

local ctable = require('lib.ctable')
local math = require("math")
local os = require("os")
local S = require("syscall")
local bit = require("bit")

local bnot, bxor = bit.bnot, bit.bxor
local floor, ceil = math.floor, math.ceil
local HASH_MAX = 0xFFFFFFFF

-- This is only called when the table is 'full'.
-- Notably, it cannot be called on an empty table,
-- so there is no risk of an infinite loop.
local function evict_random_entry(ctab, cleanup_fn)
   local random_hash = math.random(0, HASH_MAX - 1)
   local index = floor(random_hash*ctab.scale + 0.5)
   local entries = ctab.entries
   while entries[index].hash == HASH_MAX do
      if index >= ctab.size + ctab.max_displacement then
         index = 0 -- Seems unreachable?
      else
         index = index + 1
      end
   end
   local ptr = ctab.entries + index
   if cleanup_fn then cleanup_fn(ptr) end
   ctab:remove_ptr(ptr)
end

-- Behave exactly like insertion, except if the table is full: if it
-- is, then evict a random entry instead of resizing.
local function add_with_random_eviction(self, key, value, updates_allowed,
                                        cleanup_fn)
   local did_evict = false
   if self.occupancy + 1 > self.occupancy_hi then
      evict_random_entry(self, cleanup_fn)
      did_evict = true
   end
   return ctable.CTable.add(self, key, value, updates_allowed), did_evict
end

function new(params)
   local ctab = ctable.new(params)
   ctab.add = add_with_random_eviction
   return ctab
end

function selftest()
   print('selftest: apps.lwaftr.ctable_wrapper')
   local ffi = require("ffi")
   local occupancy = 4
   -- 32-byte entries 
   local params = {
      key_type = ffi.typeof('uint32_t'),
      value_type = ffi.typeof('int32_t[6]'),
      max_occupancy_rate = 0.4,
      initial_size = ceil(occupancy / 0.4)
   }
   local ctab = new(params)
 
   -- Fill table fully, to the verge of being resized.
   local v = ffi.new('int32_t[6]');
   local i = 1
   while ctab.occupancy + 1 <= ctab.occupancy_hi do
      for j=0,5 do v[j] = bnot(i) end
      ctab:add(i, v)
      i = i + 1
   end

   local old_occupancy = ctab.occupancy
   for j=0,5 do v[j] = bnot(i) end
   local entry = ctab:add(i, v)
   local iterated = 0
   for entry in ctab:iterate() do iterated = iterated + 1 end
   assert(old_occupancy == ctab.occupancy, "bad random eviction!")
 
   ctab:remove_ptr(entry, false)
   local iterated = 0
   for entry in ctab:iterate() do iterated = iterated + 1 end
   assert(iterated == ctab.occupancy)
   assert(iterated == old_occupancy - 1)
   -- OK, all looking good with our ctab.
   print('selftest: ok')
end

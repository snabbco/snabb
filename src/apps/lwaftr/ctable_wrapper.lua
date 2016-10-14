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
local function random_eject(ctab)
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
   ctab:remove_ptr(ptr)
end

-- Behave exactly like insertion, except if the table is full: if it is, then
-- eject a random entry instead of resizing.
local function add_with_random_ejection(self, key, value, updates_allowed)
   if self.occupancy + 1 > self.occupancy_hi then
      random_eject(self)
   end
   return self:add(key, value, updates_allowed)
end

function new(params)
   local ctab = ctable.new(params)
   ctab.add_with_random_ejection = add_with_random_ejection
   -- Not local-ized because it's called once
   math.randomseed(bxor(os.time(), S.getpid()))
   return ctab
end

function selftest()
   local ffi = require("ffi")
   local hash_32 = ctable.hash_32

   local occupancy = 4
   -- 32-byte entries 
   local params = {
      key_type = ffi.typeof('uint32_t'),
      value_type = ffi.typeof('int32_t[6]'),
      hash_fn = hash_32,
      max_occupancy_rate = 0.4,
      initial_size = ceil(occupancy / 0.4)
   }
   local ctab = new(params)
 
   -- Fill table fully, to the verge of being resized.
   local v = ffi.new('int32_t[6]');
   local i = 1
   while ctab.occupancy + 1 <= ctab.occupancy_hi do
      for j=0,5 do v[j] = bnot(i) end
      ctab:add_with_random_ejection(i, v)
      i = i + 1
   end

   local old_occupancy = ctab.occupancy
   for j=0,5 do v[j] = bnot(i) end
   local newest_index = ctab:add_with_random_ejection(i, v)
   local iterated = 0
   for entry in ctab:iterate() do iterated = iterated + 1 end
   assert(old_occupancy == ctab.occupancy, "bad random ejection!")
 
   ctab:remove_ptr(ctab.entries + newest_index, false)
   local iterated = 0
   for entry in ctab:iterate() do iterated = iterated + 1 end
   assert(iterated == ctab.occupancy)
   assert(iterated == old_occupancy - 1)
   -- OK, all looking good with our ctab.
end

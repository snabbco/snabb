local ffi = require('ffi')
local bit = require('bit')
local hash_i32 = require("apps.lwaftr.podhashmap").hash_i32
local phm = require("apps.lwaftr.podhashmap").PodHashMap

-- e.g. ./snabb snsh apps/lwaftr/test_phm_create.lua count occupancy filename
local function run(params)
   if #params ~= 3 then error('usage: test_phm_create.lua COUNT OCCUPANCY FILENAME') end
   local count, occupancy, filename = unpack(params)
   count = assert(tonumber(count), "count not a number: "..count)
   occupancy = assert(tonumber(occupancy), "occupancy not a number: "..occupancy)
   assert(occupancy > 0 and occupancy < 1,
          "occupancy should be between 0 and 1: "..occupancy)

   print(('creating uint32->int32[6] map with %d entries, %.0f%% occupancy'):format(
         count, occupancy * 100))
   local rhh = phm.new(ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]'),
                       hash_i32)
   rhh:resize(math.ceil(count / occupancy))
   local start = ffi.C.get_time_ns()
   for i = 1, count do
      local h = hash_i32(i)
      local v = bit.bnot(i)
      rhh:add(h, i, ffi.new("int32_t[6]", {v,v,v,v,v,v}))
   end
   local stop = ffi.C.get_time_ns()
   local iter_rate = count/(tonumber(stop-start)/1e9)/1e6
   print(iter_rate..' million insertions per second')

   local max_displacement = rhh.max_displacement
   print('max displacement: '..max_displacement)
   print('saving '..filename)
   rhh:save(filename)

   print('reloading saved file')
   rhh:load(filename)

   print('verifying saved file')
   print('max displacement: '..rhh.max_displacement)
   assert(rhh.max_displacement == max_displacement)
   for i = 0, rhh.size*2-1 do
      local entry = rhh.entries[i]
      if entry.hash ~= 0xffffffff then
         assert(entry.hash == hash_i32(entry.key))
         assert(entry.value[0] == bit.bnot(entry.key))
         assert(entry.value[5] == bit.bnot(entry.key))
      end
   end

   for i = 1, count do
      local offset = rhh:lookup(hash_i32(i), i)
      assert(rhh:val_at(offset)[0] == bit.bnot(i))
   end

   -- rhh:dump()

   print("done")
end

run(main.parameters)

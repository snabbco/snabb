local ffi = require('ffi')
local bit = require('bit')
local phm = require("apps.lwaftr.podhashmap")
local stream = require("apps.lwaftr.stream")

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
   local key_t, value_t = ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]')
   local rhh = phm.PodHashMap.new(key_t, value_t, phm.hash_i32)
   rhh:resize(math.ceil(count / occupancy))
   local start = ffi.C.get_time_ns()
   do
      local value = value_t()
      for i = 1, count do
         local v = bit.bnot(i)
         value[0], value[1], value[2] = v, v, v
         value[3], value[4], value[5] = v, v, v
         rhh:add(i, value)
      end
   end
   local stop = ffi.C.get_time_ns()
   local ns = tonumber(stop-start)/count
   print(ns..' ns/insertion')

   local max_displacement = rhh.max_displacement
   print('max displacement: '..max_displacement)
   print('saving '..filename)
   local out = stream.open_temporary_output_byte_stream(filename)
   rhh:save(out)
   out:close_and_rename()

   print('reloading saved file')
   rhh = phm.load(stream.open_input_byte_stream(filename),
                  key_t, value_t, phm.hash_i32)

   print('verifying saved file')
   print('max displacement: '..rhh.max_displacement)
   assert(rhh.max_displacement == max_displacement)
   for i = 0, rhh.size + max_displacement do
      local entry = rhh.entries[i]
      if entry.hash ~= 0xffffffff then
         assert(entry.hash == phm.hash_i32(entry.key))
         assert(entry.value[0] == bit.bnot(entry.key))
         assert(entry.value[5] == bit.bnot(entry.key))
      end
   end

   for i = 1, count do
      local offset = rhh:lookup(i)
      assert(rhh:val_at(offset)[0] == bit.bnot(i))
   end

   -- rhh:dump()

   print("done")
end

run(main.parameters)

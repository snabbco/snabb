local ffi = require('ffi')
local bit = require('bit')
local hash_i32 = require("apps.lwaftr.podhashmap").hash_i32
local phm = require("apps.lwaftr.podhashmap").PodHashMap

-- e.g. ./snabb snsh apps/lwaftr/test_phm_lookup1.lua filename
local function run(params)
   if #params < 1 or #params > 2 then
      error('usage: test_phm_lookup1.lua FILENAME [ACTIVE]')
   end
   local filename, active = unpack(params)
   if active then
      active = assert(tonumber(active), 'active should be a number')
      assert(active == math.floor(active) and active > 0,
             'active should be a positive integer')
   end

   local rhh = phm.new(ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]'),
                       hash_i32)

   print('loading saved file '..filename)
   rhh:load(filename)

   print('lookup1 speed test (hits, uniform distribution)')
   local start = ffi.C.get_time_ns()
   local count = rhh.occupancy
   print(count..' lookups, '..(active or count)..' active keys')
   local result
   for i = 1, count do
      if active then i = (i % active) + 1 end
      result = rhh:lookup(i)
   end
   local stop = ffi.C.get_time_ns()
   local iter_rate = count/(tonumber(stop-start)/1e9)/1e6
   print(iter_rate..' million lookups per second (final result: '..result..')')

   print("done")
end

run(main.parameters)

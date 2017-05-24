local ffi = require('ffi')
local phm = require("apps.lwaftr.podhashmap")
local stream = require("apps.lwaftr.stream")

local function test(rhh, count, active)
   print('lookup1 speed test (hits, uniform distribution)')
   print(count..' lookups, '..(active or count)..' active keys')
   local start = ffi.C.get_time_ns()
   local result
   for i = 1, count do
      if active then i = (i % active) + 1 end
      result = rhh:val_at(rhh:lookup(i))[0]
   end
   local stop = ffi.C.get_time_ns()
   local ns = tonumber(stop-start)/count
   print(ns..' ns/lookup (final result: '..result..')')
end

local function run(params)
   if #params < 1 or #params > 2 then
      error('usage: test_phm_lookup.lua FILENAME [ACTIVE]')
   end
   local filename, active = unpack(params)
   if active then
      active = assert(tonumber(active), 'active should be a number')
      assert(active == math.floor(active) and active > 0,
             'active should be a positive integer')
   end

   local key_t, value_t = ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]')
   print('loading saved file '..filename)
   local input = stream.open_input_byte_stream(filename)
   local rhh = phm.load(input, key_t, value_t, phm.hash_i32)

   test(rhh, rhh.occupancy, active)

   print("done")
end

run(main.parameters)

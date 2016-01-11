local ffi = require('ffi')
local bit = require('bit')
local hash_i32 = require("apps.lwaftr.podhashmap").hash_i32
local phm = require("apps.lwaftr.podhashmap").PodHashMap
local pmu = require("lib.pmu")

-- e.g. ./snabb snsh apps/lwaftr/test_phm_streaming_lookup.lua foo.phm
local function run(params)
   if #params < 1 or #params > 3 then
      error('usage: test_phm_streaming_lookup.lua FILENAME [STRIDE] [ACTIVE]')
   end
   local filename, stride, active = unpack(params)
   if stride then
      stride = assert(tonumber(stride), 'stride should be a number')
      assert(stride == math.floor(stride) and stride > 0,
             'stride should be a positive integer')
   else
      stride = 32
   end
   if active then
      active = assert(tonumber(active), 'active should be a number')
      assert(active == math.floor(active) and active > 0,
             'active should be a positive integer')
   end

   local rhh = phm.new(ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]'),
                       hash_i32)

   print('loading saved file '..filename)
   rhh:load(filename)

   local streamer = rhh:make_lookup_streamer(stride)

   print('max displacement: '..rhh.max_displacement)

   print('streaming lookup speed test (hits, uniform distribution)')
   local start = ffi.C.get_time_ns()
   local count = rhh.occupancy
   print(count..' lookups, '..(active or count)..' active keys')
   print('batching '..stride..' lookups at a time')
   for i = 1, count, stride do
      local n = math.min(stride, count + 1 - i)
      for j = 0, n-1 do
         if active then
            streamer.entries[j].key = ((i+j) % active) + 1
         else
            streamer.entries[j].key = i+j
         end
      end
      streamer:stream()
   end
   local stop = ffi.C.get_time_ns()
   local iter_rate = count/(tonumber(stop-start)/1e9)/1e6
   print(iter_rate..' million lookups per second')

   print("done")
end

run(main.parameters)

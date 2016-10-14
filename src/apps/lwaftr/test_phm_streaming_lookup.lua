local ffi = require('ffi')
local phm = require("apps.lwaftr.podhashmap")
local stream = require("apps.lwaftr.stream")

local function test(rhh, count, stride, active)
   print('streaming lookup speed test (hits, uniform distribution)')
   local streamer = rhh:make_lookup_streamer(stride)
   print(count..' lookups, '..(active or count)..' active keys')
   print('batching '..stride..' lookups at a time')
   local start = ffi.C.get_time_ns()
   local result
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
      result = streamer.entries[n-1].value[0]
   end
   local stop = ffi.C.get_time_ns()
   local ns = tonumber(stop-start)/count
   print(ns..' ns/lookup (final result: '..result..')')
end

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

   local key_t, value_t = ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]')
   print('loading saved file '..filename)
   local input = stream.open_input_byte_stream(filename)
   local rhh = phm.load(input, key_t, value_t, phm.hash_i32)

   print('max displacement: '..rhh.max_displacement)

   test(rhh, rhh.occupancy, stride, active)

   print("done")
end

run(main.parameters)

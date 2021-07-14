-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- histogram.lua -- a histogram with logarithmic buckets

module(...,package.seeall)

local ffi = require("ffi")
local shm = require("core.shm")
local log, floor, max, min = math.log, math.floor, math.max, math.min

type = shm.register('histogram', getfenv())

-- Fill a 4096-byte page with buckets.  4096/8 = 512, minus the three
-- header words means 509 buckets.  The first and last buckets are catch-alls.
local bucket_count = 509
local histogram_t = ffi.typeof([[struct {
   double minimum;
   double growth_factor_log;
   uint64_t total;
   uint64_t buckets[509];
}]])

local function compute_growth_factor_log(minimum, maximum)
   assert(minimum > 0)
   assert(maximum > minimum)
   -- The first and last buckets are the catch-alls; the ones in between
   -- partition the range between the minimum and the maximum.
   return log(maximum / minimum) / (bucket_count - 2)
end

function new(minimum, maximum)
   return histogram_t(minimum, compute_growth_factor_log(minimum, maximum))
end

function create(name, minimum, maximum)
   local histogram = shm.create(name, histogram_t)
   histogram.minimum = minimum
   histogram.growth_factor_log = compute_growth_factor_log(minimum, maximum)
   histogram:clear()
   return histogram
end

function open(name)
   return shm.open(name, histogram_t)
end

function add(histogram, measurement)
   local bucket
   if measurement <= 0 then
      bucket = 0
   else
      bucket = log(measurement / histogram.minimum)
      bucket = bucket / histogram.growth_factor_log
      bucket = floor(bucket) + 1
      bucket = max(0, bucket)
      bucket = min(bucket_count - 1, bucket)
   end
   histogram.total = histogram.total + 1
   histogram.buckets[bucket] = histogram.buckets[bucket] + 1
end

function iterate(histogram, prev)
   local bucket = -1
   local factor = math.exp(histogram.growth_factor_log)
   local minimum = histogram.minimum
   local function next_bucket()
      bucket = bucket + 1
      if bucket >= bucket_count then return end
      local lo, hi
      if bucket == 0 then
	 lo, hi = 0, minimum
      else
	 lo = minimum * math.pow(factor, bucket - 1)
	 hi = minimum * math.pow(factor, bucket)
	 if bucket == bucket_count - 1 then hi = 1/0 end
      end
      local count = histogram.buckets[bucket]
      if prev then count = count - prev.buckets[bucket] end
      return count, lo, hi
   end
   return next_bucket
end

function snapshot(a, b)
   b = b or histogram_t()
   ffi.copy(b, a, ffi.sizeof(histogram_t))
   return b
end

function clear(histogram)
   histogram.total = 0
   for bucket = 0, bucket_count - 1 do histogram.buckets[bucket] = 0 end
end

function wrap_thunk(histogram, thunk, now)
   return function()
      local start = now()
      thunk()
      histogram:add(now() - start)
   end
end

function summarize (histogram, prev)
   local total = histogram.total
   if prev then total = total - prev.total end
   if total == 0 then return 0, 0, 0 end
   local min, max, cumulative = nil, 0, 0
   for count, lo, hi in histogram:iterate(prev) do
      if count ~= 0 then
	 if not min then min = lo end
	 max = hi
	 cumulative = cumulative + (lo + hi) / 2 * tonumber(count)
      end
   end
   return min, cumulative / tonumber(total), max
end

ffi.metatype(histogram_t, {__index = {
   add = add,
   iterate = iterate,
   snapshot = snapshot,
   wrap_thunk = wrap_thunk,
   clear = clear,
   summarize = summarize
},
__tostring = function (histogram)
   return ("min: %f / avg: %f / max: %f"):format(summarize(histogram))
end})

function selftest ()
   print("selftest: histogram")

   local h = new(1e-6, 1e0)
   assert(ffi.sizeof(h) == 4096)

   h:add(1e-7)
   assert(h.buckets[0] == 1)
   h:add(1e-6 + 1e-9)
   assert(h.buckets[1] == 1)
   h:add(1.0 - 1e-9)
   assert(h.buckets[bucket_count - 2] == 1)
   h:add(1.5)
   assert(h.buckets[bucket_count - 1] == 1)

   assert(h.total == 4)
   assert(h:snapshot().total == 4)
   assert(h:snapshot().buckets[bucket_count - 1] == 1)

   local total = 0
   local bucket = 0
   for count, lo, hi in h:iterate() do
      local function check(val, expected_count)
	 if val then
	    assert(lo <= val)
	    assert(val <= hi)
	 end
	 assert(count == expected_count)
      end
      if bucket == 0 then check(1e-7, 1)
      elseif bucket == 1 then check(1e-6 + 1e-9, 1)
      elseif bucket == bucket_count - 2 then check(1 - 1e-9, 1)
      elseif bucket == bucket_count - 1 then check(1.5, 1)
      else check(nil, 0) end
      total = total + count
      bucket = bucket + 1
   end
   assert(total == 4)
   assert(bucket == bucket_count)

   h:clear()
   assert(h.total == 0)
   assert(h.buckets[bucket_count - 1] == 0)

   print("selftest ok")
end


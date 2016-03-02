-- histogram.lua -- a histogram with logarithmic buckets
--
-- API:
--   histogram.new(min, max) => histogram
--     Make a new histogram, with buckets covering the range from MIN to MAX.
--     The range between MIN and MAX will be divided logarithmically.
--
--   histogram.create(name, min, max) => histogram
--     Create a histogram as in new(), but also map it into
--     /var/run/snabb/PID/NAME, exposing it for analysis by other processes.
--     If the file exists already, it will be cleared.
--
--   histogram.open(pid, name) => histogram
--     Open a histogram mapped as /var/run/snabb/PID/NAME.
--
--   histogram.add(histogram, measurement)
--     Add a measurement to a histogram.
--
--   histogram.iterate(histogram, prev)
--     When used as "for bucket, lo, hi, count in histogram:iterate()",
--     visits all buckets in a histogram.  BUCKET is the bucket index,
--     starting from zero, LO and HI are the lower and upper bounds of
--     the bucket, and COUNT is the number of samples recorded in that
--     bucket.  Note that COUNT is an unsigned 64-bit integer; to get it
--     as a Lua number, use tonumber().
--
--     If PREV is given, it should be a snapshot of the previous version
--     of the histogram.  In that case, the COUNT values will be
--     returned as a diffference between their values in HISTOGRAM and
--     their values in PREV.
--
--   histogram.snapshot(a, b)
--     Copy out the contents of A into B and return B.  If B is not given,
--     the result will be a fresh histogram.
--
--   histogram.clear(a)
--     Clear the counters in A.
--
--   histogram.wrap_thunk(histogram, thunk, now)
--     Return a closure that wraps THUNK, but which measures the difference
--     between calls to NOW before and after the thunk, recording that
--     difference into HISTOGRAM.
--
module(...,package.seeall)

local ffi = require("ffi")
local shm = require("core.shm")
local log, floor, max, min = math.log, math.floor, math.max, math.min

-- Fill a 4096-byte page with buckets.  4096/8 = 512, minus the three
-- header words means 509 buckets.  The first and last buckets are catch-alls.
local histogram_t = ffi.typeof([[struct {
   double minimum;
   double growth_factor_log;
   uint64_t total;
   uint64_t buckets[509];
}]])

local function compute_growth_factor_log(minimum, maximum)
   assert(minimum > 0)
   assert(maximum > minimum)
   -- 507 buckets for precise steps within minimum and maximum, 2 for
   -- the catch-alls.
   return log(maximum / minimum) / 507
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
      bucket = min(508, bucket)
   end
   histogram.total = histogram.total + 1
   histogram.buckets[bucket] = histogram.buckets[bucket] + 1
end

function iterate(histogram, prev)
   local function next_bucket(histogram, bucket)
      bucket = bucket + 1
      if bucket < 0 or bucket > 508 then return end
      local lo, hi
      local minimum = histogram.minimum
      if bucket == 0 then
	 lo, hi = 0, histogram.minimum
      else
	 local factor = math.exp(histogram.growth_factor_log)
	 lo = histogram.minimum * math.pow(factor, bucket - 1)
	 hi = histogram.minimum * math.pow(factor, bucket)
	 if bucket == 508 then hi = 1/0 end
      end
      local count = histogram.buckets[bucket]
      if prev then count = count - prev.buckets[bucket] end
      return bucket, lo, hi, count
   end
   return next_bucket, histogram, -1
end

function snapshot(a, b)
   b = b or histogram_t()
   ffi.copy(b, a, ffi.sizeof(histogram_t))
   return b
end

function clear(histogram)
   histogram.total = 0
   for bucket = 0, 508 do histogram.buckets[bucket] = 0 end
end

function wrap_thunk(histogram, thunk, now)
   return function()
      local start = now()
      thunk()
      histogram:add(now() - start)
   end
end

ffi.metatype(histogram_t, {__index = {
   add = add,
   iterate = iterate,
   snapshot = snapshot,
   wrap_thunk = wrap_thunk,
   clear = clear
}})

function selftest ()
   print("selftest: histogram")

   local h = new(1e-6, 1e0)
   assert(ffi.sizeof(h) == 4096)

   h:add(1e-7)
   assert(h.buckets[0] == 1)
   h:add(1e-6 + 1e-9)
   assert(h.buckets[1] == 1)
   h:add(1.0 - 1e-9)
   assert(h.buckets[507] == 1)
   h:add(1.5)
   assert(h.buckets[508] == 1)

   assert(h.total == 4)
   assert(h:snapshot().total == 4)
   assert(h:snapshot().buckets[508] == 1)

   local total = 0
   for bucket, lo, hi, count in h:iterate() do
      local function check(val, expected_count)
	 if val then
	    assert(lo <= val)
	    assert(val <= hi)
	 end
	 assert(count == expected_count)
      end
      if bucket == 0 then check(1e-7, 1)
      elseif bucket == 1 then check(1e-6 + 1e-9, 1)
      elseif bucket == 507 then check(1 - 1e-9, 1)
      elseif bucket == 508 then check(1.5, 1)
      else check(nil, 0) end
      total = total + count
   end
   assert(total == 4)

   h:clear()
   assert(h.total == 0)
   assert(h.buckets[508] == 0)

   print("selftest ok")
end


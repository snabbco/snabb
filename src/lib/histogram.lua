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
--     Any existing content in the file is cleared.  If the file exists already,
--     it will be cleared.
--
--   histogram.open(pid, name) => histogram
--     Open a histogram mapped as /var/run/snabb/PID/NAME.
--
--   histogram.add(histogram, measurement)
--     Add a measurement to a histogram.
--
--   histogram.report(histogram, prev)
--     Print out non-empty buckets and their ranges.  If PREV is given,
--     it should be a snapshot of the previous version of the histogram.
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

local app  = require("core.app")
local ffi = require("ffi")
local S = require("syscall")
local log, floor, max, min = math.log, math.floor, math.max, math.min

-- First, some private helpers to let us map histograms into shared
-- memory so that other processes can analyze them.

-- Create /var/run/snabb with mode "rwxrwxrwt" (R/W for all and sticky)
-- if it does not exist yet.
root = "/var/run/snabb"
local function ensure_root()
   if not S.stat(root) then
      local mask = S.umask(0)
      local status, err = S.mkdir(root, "01777")
      assert(status, ("Unable to create %s: %s"):format(
                root, tostring(err or "unspecified error")))
      S.umask(mask)
   end
   return root
end

local function build_path(...) return table.concat({ ... }, '/') end

-- Given the name "foo/bar/baz", create /var/run/snabb/foo and
-- /var/run/snabb/foo/bar.
local function mkdir_p (name)
   local path = ensure_root()
   local function match(x)
      S.mkdir(path, "rwxu");
      path = build_path(path, x)
   end
   name:gsub("([^/]+)", match)
   return path
end

local function map_ptr(fd, len, type)
   local mem, err = S.mmap(nil, len, "read, write", "shared", fd, 0)
   fd:close()
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   local ret = ffi.cast(ffi.typeof("$*", type), mem)
   ffi.gc(ret, function (ptr) S.munmap(ptr, len) end)
   return ret
end

local function create_ptr(name, type, ...)
   local path = mkdir_p(build_path(S.getpid(), name))
   local len = ffi.sizeof(type, ...)
   local fd, err = S.open(path, "creat, rdwr", '0664')
   if not fd then
      local err = tostring(err or "unknown error")
      error('error creating file "'..path..'": '..err)
   end
   assert(fd:ftruncate(len), "ftruncate failed")
   return map_ptr(fd, len, type)
end

local function open_ptr(name, pid, type, ...)
   local path = build_path(root, pid, name)
   local fd, err = S.open(path, "rdwr")
   if not fd then
      local err = tostring(err or "unknown error")
      error('error opening file "'..path..'": '..err)
   end
   local stat = S.fstat(fd)
   local len = stat and stat.size
   if len ~= ffi.sizeof(type, ...) then
      error("unexpected size for file: "..path)
   end
   return map_ptr(fd, len, type)
end

-- Now the histogram code.

-- Fill a 4096-byte page with buckets.  4096/8 = 512, minus the three
-- header words means 509 buckets.  The first and last buckets are catch-alls.
local histogram_t = ffi.typeof([[struct {
   double minimum;
   double growth_factor_log;
   uint64_t count;
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
   local histogram = create_ptr(name, histogram_t)
   histogram.minimum = minimum
   histogram.growth_factor_log = compute_growth_factor_log(minimum, maximum)
   histogram:clear()
   return histogram
end

function open(pid, name)
   return open_ptr(name, pid, histogram_t)
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
   histogram.count = histogram.count + 1
   histogram.buckets[bucket] = histogram.buckets[bucket] + 1
end

function report(histogram, prev)
   local lo, hi = 0, histogram.minimum
   local factor = math.exp(histogram.growth_factor_log)
   local total = histogram.count
   if prev then total = total - prev.count end
   total = tonumber(total)
   for bucket = 0, 508 do
      local count = histogram.buckets[bucket]
      if prev then count = count - prev.buckets[bucket] end
      if count ~= 0 then
         print(string.format('%.3e - %.3e: %u (%.5f%%)', lo, hi, tonumber(count),
                             tonumber(count) / total * 100.))
      end
      lo, hi = hi, hi * factor
   end
end

function summarize(histogram, prev)
   local lo, hi = 0, histogram.minimum
   local factor = math.exp(histogram.growth_factor_log)
   local total = histogram.count
   if prev then total = total - prev.count end
   total = tonumber(total)
   local min, max, cumulative = 1/0, 0, 0
   for bucket = 0, 508 do
      local count = histogram.buckets[bucket]
      if prev then count = count - prev.buckets[bucket] end
      if count ~= 0 then
         if lo < min then min = lo end
         if hi > max then max = hi end
         cumulative = cumulative + (lo + hi) / 2 * tonumber(count)
      end
      lo, hi = hi, hi * factor
   end
   return min, cumulative / total, max
end

function snapshot(a, b)
   b = b or histogram_t()
   ffi.copy(b, a, ffi.sizeof(histogram_t))
   return b
end

function clear(histogram)
   histogram.count = 0
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
   report = report,
   summarize = summarize,
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

   assert(h.count == 4)
   assert(h:snapshot().count == 4)
   assert(h:snapshot().buckets[508] == 1)

   h:report()

   h:clear()
   assert(h.count == 0)
   assert(h.buckets[508] == 0)

   print("selftest ok")
end


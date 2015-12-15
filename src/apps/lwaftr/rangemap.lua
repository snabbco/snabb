-- Range maps -*- lua -*-
--
-- A range map is a map from uint32 to value.  It divides the space of
-- uint32 values into ranges, where every key in that range has the same
-- value.  The expectation is that you build a range map once and then
-- use it many times.  We also expect that the number of ranges ends up
-- being fairly small and will always be found in cache.  For this
-- reason, a lookup in the range map can use an optimized branchless
-- binary search.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local binary_search = require('apps.lwaftr.binary_search')

local UINT32_MAX = 0xFFFFFFFF

RangeMapBuilder = {}
RangeMap = {}

local function make_entry_type(value_type)
   return ffi.typeof([[struct {
         uint32_t key;
         $ value;
      } __attribute__((packed))]],
      value_type)
end

local function make_entries_type(entry_type)
   return ffi.typeof('$[?]', entry_type)
end

local function make_equal_fn(type)
   local size = ffi.sizeof(type)
   local cast = ffi.cast
   if tonumber(ffi.new(type)) then
      return function (a, b)
         return a == b
      end
   elseif size == 2 then
      local uint16_ptr_t = ffi.typeof('uint16_t*')
      return function (a, b)
         return cast(uint16_ptr_t, a)[0] == cast(uint16_ptr_t, b)[0]
      end
   elseif size == 4 then
      local uint32_ptr_t = ffi.typeof('uint32_t*')
      return function (a, b)
         return cast(uint32_ptr_t, a)[0] == cast(uint32_ptr_t, b)[0]
      end
   elseif size == 8 then
      local uint64_ptr_t = ffi.typeof('uint64_t*')
      return function (a, b)
         return cast(uint64_ptr_t, a)[0] == cast(uint64_ptr_t, b)[0]
      end
   else
      return function (a, b)
         return C.memcmp(a, b, size) == 0
      end
   end
end

function RangeMapBuilder.new(value_type)
   local builder = {}
   builder.value_type = value_type
   builder.entry_type = make_entry_type(builder.value_type)
   builder.type = make_entries_type(builder.entry_type)
   builder.equal_fn = make_equal_fn(builder.value_type)
   builder.entries = {}
   builder = setmetatable(builder, { __index = RangeMapBuilder })
   return builder
end

function RangeMapBuilder:add(key, value)
   local entry = ffi.new(self.entry_type)
   entry.key = key
   entry.value = value
   table.insert(self.entries, entry)
end

function RangeMapBuilder:build()
   table.sort(self.entries, function(a,b) return a.key < b.key end)

   -- The optimized binary search routines in binary_search.dasl want to
   -- search for the entry whose key is *greater* than or equal to the K
   -- we are looking for.  Therefore we partition the range into
   -- contiguous entries with the highest K having a value V, starting
   -- with UINT32_MAX and working our way down.
   local ranges = {}
   if #self.entries == 0 then error('what') end
   local range_end = self.entries[#self.entries]
   range_end.key = UINT32_MAX
   table.insert(ranges, range_end)
   for i=#self.entries,1,-1 do
      local entry = self.entries[i]
      if not self.equal_fn(entry.value, range_end.value) then
         assert(entry.key < range_end.key,
                "Key has differing values: "..entry.key)
         range_end = entry
         table.insert(ranges, range_end)
      end
   end

   local range_count = #ranges
   local packed_entries = self.type(range_count)
   for i,entry in ipairs(ranges) do
      packed_entries[range_count-i] = ranges[i]
   end

   local map = {
      value_type = self.value_type,
      entry_type = self.entry_type,
      type = self.type,
      entries = packed_entries,
      size = range_count
   }
   map.binary_search = binary_search.gen(map.size, ffi.sizeof(map.entry_type))
   map = setmetatable(map, { __index = RangeMap })
   return map
end

function RangeMap:lookup(k)
   return self.binary_search(self.entries, k)
end

function RangeMap:val_at(i)
   return self.entries[i].value
end

function selftest()
   local builder = RangeMapBuilder.new(ffi.typeof('uint8_t'))
   builder:add(0, 1)
   builder:add(1, 2)
   builder:add(100, 10)
   builder:add(101, 20)
   builder:add(200, 30)
   builder:add(300, 40)
   builder:add(301, 50)
   builder:add(302, 60)
   builder:add(350, 70)
   builder:add(370, 70)
   builder:add(400, 70)
   builder:add(401, 80)
   builder:add(UINT32_MAX-1, 99)
   builder:add(UINT32_MAX, 100)
   local map = builder:build()

   assert(map.size == 12)
   assert(map:val_at(map:lookup(0)) == 1)
   assert(map:val_at(map:lookup(1)) == 2)
   assert(map:val_at(map:lookup(2)) == 10)
   assert(map:val_at(map:lookup(99)) == 10)
   assert(map:val_at(map:lookup(100)) == 10)
   assert(map:val_at(map:lookup(101)) == 20)
   assert(map:val_at(map:lookup(102)) == 30)
   assert(map:val_at(map:lookup(199)) == 30)
   assert(map:val_at(map:lookup(200)) == 30)
   assert(map:val_at(map:lookup(201)) == 40)
   assert(map:val_at(map:lookup(300)) == 40)
   assert(map:val_at(map:lookup(301)) == 50)
   assert(map:val_at(map:lookup(302)) == 60)
   assert(map:val_at(map:lookup(303)) == 70)
   assert(map:val_at(map:lookup(349)) == 70)
   assert(map:val_at(map:lookup(350)) == 70)
   assert(map:val_at(map:lookup(399)) == 70)
   assert(map:val_at(map:lookup(400)) == 70)
   assert(map:val_at(map:lookup(401)) == 80)
   assert(map:val_at(map:lookup(402)) == 99)
   assert(map:val_at(map:lookup(UINT32_MAX-2)) == 99)
   assert(map:val_at(map:lookup(UINT32_MAX-1)) == 99)
   assert(map:val_at(map:lookup(UINT32_MAX)) == 100)

   local pmu = require('lib.pmu')
   local has_pmu_counters, err = pmu.is_available()
   if not has_pmu_counters then
      print('No PMU available: '..err)
   end

   if has_pmu_counters then pmu.setup() end

   local function measure(f, iterations)
      local set
      if has_pmu_counters then set = pmu.new_counter_set() end
      local start = C.get_time_ns()
      if has_pmu_counters then pmu.switch_to(set) end
      local res = f(iterations)
      if has_pmu_counters then pmu.switch_to(nil) end
      local stop = C.get_time_ns()
      local ns = tonumber(stop-start)
      local cycles = nil
      if has_pmu_counters then cycles = pmu.to_table(set).cycles end
      return cycles, ns, res
   end

   local function check_perf(f, iterations, max_cycles, max_ns, what)
      require('jit').flush()
      io.write(tostring(what or f)..': ')
      io.flush()
      local cycles, ns, res = measure(f, iterations)
      if cycles then
         cycles = cycles/iterations
         io.write(('%.2f cycles, '):format(cycles))
      end
      ns = ns/iterations
      io.write(('%.2f ns per iteration (result: %s)\n'):format(
            ns, tostring(res)))
      if cycles and cycles > max_cycles then
         print('WARNING: perfmark failed: exceeded maximum cycles '..max_cycles)
      end
      if ns > max_ns then
         print('WARNING: perfmark failed: exceeded maximum ns '..max_ns)
      end
      return res
   end

   local function test_lookup(iterations)
      local inc = math.floor(UINT32_MAX / iterations)
      local result = 0
      for i=0,UINT32_MAX,inc do result = map:lookup(i) end
      return result
   end

   check_perf(test_lookup, 1e8, 35, 10, 'lookup')
end

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
local binary_search = require('lib.binary_search')

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

local entry_type_cache = {}
local function get_entry_type(value_type)
   if not entry_type_cache[value_type] then
      entry_type_cache[value_type] = make_entry_type(value_type)
   end
   return entry_type_cache[value_type]
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
   builder.entry_type = get_entry_type(builder.value_type)
   builder.type = make_entries_type(builder.entry_type)
   builder.equal_fn = make_equal_fn(builder.value_type)
   builder.entries = {}
   builder = setmetatable(builder, { __index = RangeMapBuilder })
   return builder
end

function RangeMapBuilder:add_range(key_min, key_max, value)
   assert(key_min <= key_max)
   local min, max = ffi.new(self.entry_type), ffi.new(self.entry_type)
   min.key, min.value = key_min, value
   max.key, max.value = key_max, value
   table.insert(self.entries, { min=min, max=max })
end

function RangeMapBuilder:add(key, value)
   self:add_range(key, key, value)
end

function RangeMapBuilder:build(default_value)
   assert(default_value)
   table.sort(self.entries, function(a,b) return a.max.key < b.max.key end)

   -- The optimized binary search routines in binary_search.dasl want to
   -- search for the entry whose key is *greater* than or equal to the K
   -- we are looking for.  Therefore we partition the range into
   -- contiguous entries with the highest K having a value V, starting
   -- with UINT32_MAX and working our way down.
   local ranges = {}
   if #self.entries == 0 or self.entries[#self.entries].max.key < UINT32_MAX then
      table.insert(self.entries,
                   { min=self.entry_type(UINT32_MAX, default_value),
                     max=self.entry_type(UINT32_MAX, default_value) })
   end

   table.insert(ranges, self.entries[#self.entries].max)
   local range_end = self.entries[#self.entries].min
   for i=#self.entries-1,1,-1 do
      local entry = self.entries[i]
      if entry.max.key >= range_end.key then
         error("Multiple range map entries for key: "..entry.max.key)
      elseif entry.max.key + 1 ~= range_end.key then
         table.insert(ranges, self.entry_type(range_end.key - 1, default_value))
         range_end = self.entry_type(entry.max.key + 1, default_value)
      end
      if not self.equal_fn(entry.max.value, range_end.value) then
         table.insert(ranges, entry.max)
      end
      range_end = entry.min
   end
   if range_end.key > 0 then
      table.insert(ranges, self.entry_type(range_end.key - 1, default_value))
   end

   local range_count = #ranges
   local packed_entries = self.type(range_count)
   for i,entry in ipairs(ranges) do
      packed_entries[range_count-i] = entry
   end

   local map = {
      value_type = self.value_type,
      entry_type = self.entry_type,
      type = self.type,
      entries = packed_entries,
      size = range_count
   }
   map.binary_search = binary_search.gen(map.size, map.entry_type)
   map = setmetatable(map, { __index = RangeMap })
   return map
end

function RangeMap:lookup(k)
   return self.binary_search(self.entries, k)
end

function RangeMap:iterate()
   local entry = -1
   local function next_entry()
      entry = entry + 1
      if entry >= self.size then return end
      local hi, val = self.entries[entry].key, self.entries[entry].value
      local lo = 0
      if entry > 0 then lo = self.entries[entry - 1].key + 1 end
      return lo, hi, val
   end
   return next_entry
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
   builder:add(351, 70)
   builder:add(370, 70)
   builder:add(400, 70)
   builder:add(401, 80)
   builder:add(UINT32_MAX-1, 99)
   builder:add(UINT32_MAX, 100)
   local map = builder:build(0)

   -- The ranges that we expect this map to compile to.
   local ranges = {
      { 0, 1},
      { 1, 2},
      { 99, 0 },
      { 100, 10 },
      { 101, 20 },
      { 199, 0 },
      { 200, 30 },
      { 299, 0 },
      { 300, 40 },
      { 301, 50 },
      { 302, 60 },
      { 349, 0 },
      { 351, 70 },
      { 369, 0 },
      { 370, 70 },
      { 399, 0 },
      { 400, 70 },
      { 401, 80 },
      { UINT32_MAX-2, 0 },
      { UINT32_MAX-1, 99 },
      { UINT32_MAX, 100 },
   }

   assert(map.size == #ranges)
   for i, v in ipairs(ranges) do
      local key, value = unpack(v)
      assert(map.entries[i-1].key == key)
      assert(map.entries[i-1].value == value)
   end

   do
      local i = 1
      local expected_lo = 0
      for lo, hi, value in map:iterate() do
         local expected_hi, expected_value = unpack(ranges[i])
         assert(lo == expected_lo)
         assert(hi == expected_hi)
         assert(value == expected_value)
         i = i + 1
         expected_lo = hi + 1
      end
      assert(i == #ranges + 1)
      assert(expected_lo == UINT32_MAX + 1)
   end

   assert(map:lookup(0).value == 1)
   assert(map:lookup(1).value == 2)
   assert(map:lookup(2).value == 0)
   assert(map:lookup(99).value == 0)
   assert(map:lookup(100).value == 10)
   assert(map:lookup(101).value == 20)
   assert(map:lookup(102).value == 0)
   assert(map:lookup(199).value == 0)
   assert(map:lookup(200).value == 30)
   assert(map:lookup(201).value == 0)
   assert(map:lookup(300).value == 40)
   assert(map:lookup(301).value == 50)
   assert(map:lookup(302).value == 60)
   assert(map:lookup(303).value == 0)
   assert(map:lookup(349).value == 0)
   assert(map:lookup(350).value == 70)
   assert(map:lookup(351).value == 70)
   assert(map:lookup(352).value == 0)
   assert(map:lookup(369).value == 0)
   assert(map:lookup(370).value == 70)
   assert(map:lookup(371).value == 0)
   assert(map:lookup(399).value == 0)
   assert(map:lookup(400).value == 70)
   assert(map:lookup(401).value == 80)
   assert(map:lookup(402).value == 0)
   assert(map:lookup(UINT32_MAX-2).value == 0)
   assert(map:lookup(UINT32_MAX-1).value == 99)
   assert(map:lookup(UINT32_MAX).value == 100)

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
      for i=0,UINT32_MAX,inc do result = map:lookup(i).value end
      return result
   end

   check_perf(test_lookup, 1e8, 35, 10, 'lookup')
end

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")
local bit = require("bit")
local bxor, bnot = bit.bxor, bit.bnot
local tobit, lshift, rshift = bit.tobit, bit.lshift, bit.rshift
local max, floor, ceil = math.max, math.floor, math.ceil

PodHashMap = {}
LookupStreamer = {}

local HASH_MAX = 0xFFFFFFFF
local INT32_MIN = -0x80000000
local INITIAL_SIZE = 8
local MAX_OCCUPANCY_RATE = 0.9
local MIN_OCCUPANCY_RATE = 0.0

local function make_entry_type(key_type, value_type)
   return ffi.typeof([[struct {
         uint32_t hash;
         $ key;
         $ value;
      } __attribute__((packed))]],
      key_type,
      value_type)
end

-- hash := [0,HASH_MAX); scale := size/HASH_MAX
local function hash_to_index(hash, scale)
   return floor(hash*scale + 0.5)
end

local function make_equal_fn(key_type)
   local size = ffi.sizeof(key_type)
   local cast = ffi.cast
   if tonumber(ffi.new(key_type)) then
      return function (a, b)
         return a == b
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

function PodHashMap.new(key_type, value_type, hash_fn)
   local phm = {}   
   phm.entry_type = make_entry_type(key_type, value_type)
   phm.hash_fn = hash_fn
   phm.equal_fn = make_equal_fn(key_type)
   phm.size = 0
   phm.occupancy = 0
   phm.max_occupancy_rate = MAX_OCCUPANCY_RATE
   phm.min_occupancy_rate = MIN_OCCUPANCY_RATE
   phm = setmetatable(phm, { __index = PodHashMap })
   phm:resize(INITIAL_SIZE)
   return phm
end

-- FIXME: There should be a library to help allocate anonymous
-- hugepages, not this code.
local try_huge_pages = true
local huge_page_threshold = 1e6
local function calloc(t, count)
   local byte_size = ffi.sizeof(t) * count
   local mem, err
   if try_huge_pages and byte_size > huge_page_threshold then
      mem, err = S.mmap(nil, byte_size, 'read, write',
                        'private, anonymous, hugetlb')
      if not mem then
         print("hugetlb mmap failed ("..tostring(err)..'), falling back.')
         -- FIXME: Increase vm.nr_hugepages.  See
         -- core.memory.reserve_new_page().
      end
   end
   if not mem then
      mem, err = S.mmap(nil, byte_size, 'read, write',
                        'private, anonymous')
      if not mem then error("mmap failed: " .. tostring(err)) end
   end
   local ret = ffi.cast(ffi.typeof('$*', t), mem)
   ffi.gc(ret, function (ptr) S.munmap(ptr, byte_size) end)
   return ret
end

local header_t = ffi.typeof[[
struct {
   uint32_t size;
   uint32_t entry_size;
   uint32_t occupancy;
   uint32_t max_displacement;
   double max_occupancy_rate;
   double min_occupancy_rate;
}
]]

function PodHashMap:save(stream)
   stream:write_ptr(header_t(self.size, ffi.sizeof(self.entry_type),
                             self.occupancy, self.max_displacement,
                             self.max_occupancy_rate, self.min_occupancy_rate))
   stream:write_array(self.entries,
                      self.entry_type,
                      self.size + self.max_displacement + 1)
end

function load(stream, key_t, value_t, hash_fn)
   local map = PodHashMap.new(key_t, value_t, hash_fn)
   local header = stream:read_ptr(header_t)
   assert(header.entry_size == header.entry_size)

   map.size = header.size
   map.scale = map.size / HASH_MAX
   map.occupancy = header.occupancy
   map.max_displacement = header.max_displacement
   map.min_occupancy_rate = header.min_occupancy_rate
   map.max_occupancy_rate = header.max_occupancy_rate
   map.occupancy_hi = ceil(map.size * map.max_occupancy_rate)
   map.occupancy_lo = floor(map.size * map.min_occupancy_rate)
   local entry_count = map.size + map.max_displacement + 1
   map.entries = calloc(map.entry_type, entry_count)

   -- Copy the entries from disk into hugepages.
   C.memcpy(map.entries,
            stream:read_array(map.entry_type, entry_count),
            ffi.sizeof(map.entry_type) * entry_count)

   return map
end

function PodHashMap:resize(size)
   assert(size >= (self.occupancy / self.max_occupancy_rate))
   local old_entries = self.entries
   local old_size = self.size

   self.size = size
   self.scale = self.size / HASH_MAX
   self.occupancy = 0
   self.max_displacement = 0
   self.occupancy_hi = ceil(self.size * self.max_occupancy_rate)
   self.occupancy_lo = floor(self.size * self.min_occupancy_rate)
   -- Allocate double the requested number of entries to make sure there
   -- is sufficient displacement if all hashes map to the last bucket.
   self.entries = calloc(self.entry_type, size * 2)

   for i=0,self.size*2-1 do self.entries[i].hash = HASH_MAX end

   for i=0,old_size*2-1 do
      if old_entries[i].hash ~= HASH_MAX then
         self:insert(old_entries[i].hash, old_entries[i].key, old_entries[i].value)
      end
   end
end

function PodHashMap:insert(hash, key, value)
   if self.occupancy + 1 > self.occupancy_hi then
      self:resize(self.size * 2)
   end

   local entries = self.entries
   local scale = self.scale
   local start_index = hash_to_index(hash, self.scale)
   local index = start_index
   --print('adding ', hash, key, value, index)

   while entries[index].hash < hash do
      --print('displace', index, entries[index].hash)
      index = index + 1
   end

   while entries[index].hash == hash do
      --- Update currently unsupported.
      --print('update?', index)
      assert(not self.equal_fn(key, entries[index].key))
      index = index + 1
   end

   self.max_displacement = max(self.max_displacement, index - start_index)

   if entries[index].hash ~= HASH_MAX then
      --- Rob from rich!
      --print('steal', index)
      local empty = index;
      while entries[empty].hash ~= HASH_MAX do empty = empty + 1 end
      --print('end', empty)
      while empty > index do
         entries[empty] = entries[empty - 1]
         local displacement = empty - hash_to_index(entries[empty].hash, scale)
         self.max_displacement = max(self.max_displacement, displacement)
         empty = empty - 1;
      end
   end
           
   self.occupancy = self.occupancy + 1
   entries[index].hash = hash
   entries[index].key = key
   entries[index].value = value
   return index
end

function PodHashMap:add(key, value)
   local hash = self.hash_fn(key)
   assert(hash ~= HASH_MAX)
   return self:insert(hash, key, value)
end

function PodHashMap:lookup(key)
   local hash = self.hash_fn(key)
   local entries = self.entries
   local index = hash_to_index(hash, self.scale)
   local other_hash = entries[index].hash

   if hash == other_hash and self.equal_fn(key, entries[index].key) then
      -- Found!
      return index
   end

   while other_hash < hash do
      index = index + 1
      other_hash = entries[index].hash
   end

   while other_hash == hash do
      if self.equal_fn(key, entries[index].key) then
         -- Found!
         return index
      end
      -- Otherwise possibly a collision.
      index = index + 1
      other_hash = entries[index].hash
   end

   -- Not found.
   return nil
end

-- FIXME: Does NOT shrink max_displacement
function PodHashMap:remove_at(i)
   assert(not self:is_empty(i))

   local entries = self.entries
   local scale = self.scale

   self.occupancy = self.occupancy - 1
   entries[i].hash = HASH_MAX

   while true do
      local next = i + 1
      local next_hash = entries[next].hash
      if next_hash == HASH_MAX then break end
      if hash_to_index(next_hash, scale) == next then break end
      -- Give to the poor.
      entries[i] = entries[next]
      entries[next].hash = HASH_MAX
      i = next
   end

   if self.occupancy < self.size * self.occupancy_lo then
      self:resize(self.size / 2)
   end
end

function PodHashMap:is_empty(i)
   assert(i >= 0 and i < self.size*2)
   return self.entries[i].hash == HASH_MAX
end

function PodHashMap:hash_at(i)
   assert(not self:is_empty(i))
   return self.entries[i].hash
end

function PodHashMap:key_at(i)
   assert(not self:is_empty(i))
   return self.entries[i].key
end

function PodHashMap:val_at(i)
   assert(not self:is_empty(i))
   return self.entries[i].value
end

function PodHashMap:selfcheck()
   local occupancy = 0
   local max_displacement = 0

   local function fail(expected, op, found, what, where)
      if where then where = 'at '..where..': ' else where = '' end
      error(where..what..' check: expected '..expected..op..'found '..found)
   end
   local function expect_eq(expected, found, what, where)
      if expected ~= found then fail(expected, '==', found, what, where) end
   end
   local function expect_le(expected, found, what, where)
      if expected > found then fail(expected, '<=', found, what, where) end
   end

   local prev = 0
   for i = 0,self.size*2-1 do
      local entry = self.entries[i]
      local hash = entry.hash
      if hash ~= 0xffffffff then
         expect_eq(self.hash_fn(entry.key), hash, 'hash', i)
         local index = hash_to_index(hash, self.scale)
         if prev == 0xffffffff then
            expect_eq(index, i, 'undisplaced index', i)
         else
            expect_le(prev, hash, 'displaced hash', i)
         end
         occupancy = occupancy + 1
         max_displacement = max(max_displacement, i - index)
      end
      prev = hash
   end

   expect_eq(occupancy, self.occupancy, 'occupancy')
   -- Compare using <= because remove_at doesn't update max_displacement.
   expect_le(max_displacement, self.max_displacement, 'max_displacement')
end

function PodHashMap:dump()
   local function dump_one(index)
      io.write(index..':')
      local entry = self.entries[index]
      if (entry.hash == HASH_MAX) then
         io.write('\n')
      else
         local distance = index - hash_to_index(entry.hash, self.scale)
         io.write(' hash: '..entry.hash..' (distance: '..distance..')\n')
         io.write('    key: '..tostring(entry.key)..'\n')
         io.write('  value: '..tostring(entry.value)..'\n')
      end
   end
   for index=0,self.size-1 do dump_one(index) end
   for index=self.size,self.size*2-1 do
      if self.entries[index].hash == HASH_MAX then break end
      dump_one(index)
   end
end

function PodHashMap:iterate()
   local max_entry = self.entries + self.size + self.max_displacement
   local function next_entry(max_entry, entry)
      while entry < max_entry do
         entry = entry + 1
         if entry.hash ~= HASH_MAX then return entry end
      end
   end
   return next_entry, max_entry, self.entries - 1
end

function PodHashMap:make_lookup_streamer(stride)
   -- These requires are here because they rely on dynasm, which the
   -- user might not have.  In that case, since they get no benefit from
   -- streaming lookup, restrict them to the scalar lookup.
   local binary_search = require('apps.lwaftr.binary_search')
   local multi_copy = require('apps.lwaftr.multi_copy')

   local res = {
      all_entries = self.entries,
      stride = stride,
      hash_fn = self.hash_fn,
      equal_fn = self.equal_fn,
      entries_per_lookup = self.max_displacement + 1,
      scale = self.scale,
      pointers = ffi.new('void*['..stride..']'),
      entries = calloc(self.entry_type, stride),
      -- Binary search over N elements can return N if no entry was
      -- found that was greater than or equal to the key.  We would
      -- have to check the result of binary search to ensure that we
      -- are reading a value in bounds.  To avoid this, allocate one
      -- more entry.
      stream_entries = calloc(self.entry_type,
                              stride * (self.max_displacement + 1) + 1)
   }
   -- Give res.pointers sensible default values in case the first lookup
   -- doesn't fill the pointers vector.
   for i = 0, stride-1 do res.pointers[i] = self.entries end

   -- Initialize the stream_entries to HASH_MAX for sanity.
   for i = 0, stride * (self.max_displacement + 1) do
      res.stream_entries[i].hash = HASH_MAX
   end

   -- Compile multi-copy and binary-search procedures that are
   -- specialized for this table and this stride.
   local entry_size = ffi.sizeof(self.entry_type)
   res.multi_copy = multi_copy.gen(stride, res.entries_per_lookup * entry_size)
   res.binary_search = binary_search.gen(res.entries_per_lookup, self.entry_type)

   return setmetatable(res, { __index = LookupStreamer })
end

function LookupStreamer:stream()
   local stride = self.stride
   local entries = self.entries
   local pointers = self.pointers
   local stream_entries = self.stream_entries
   local entries_per_lookup = self.entries_per_lookup
   local equal_fn = self.equal_fn

   for i=0,stride-1 do
      local hash = self.hash_fn(entries[i].key)
      local index = hash_to_index(hash, self.scale)
      entries[i].hash = hash
      pointers[i] = self.all_entries + index
   end

   self.multi_copy(stream_entries, pointers)

   -- Copy results into entries.
   for i=0,stride-1 do
      local hash = entries[i].hash
      local index = i * entries_per_lookup
      local found = self.binary_search(stream_entries + index, hash)
      -- It could be that we read one beyond the ENTRIES_PER_LOOKUP
      -- entries allocated for this key; that's fine.  See note in
      -- make_lookup_streamer.
      if found.hash == hash then
         -- Direct hit?
         if equal_fn(found.key, entries[i].key) then
            entries[i].value = found.value
         else
            -- Mark this result as not found unless we prove
            -- otherwise.
            entries[i].hash = HASH_MAX

            -- Collision?
            found = found + 1
            while found.hash == hash do
               if equal_fn(found.key, entries[i].key) then
                  -- Yay!  Re-mark this result as found.
                  entries[i].hash = hash
                  entries[i].value = found.value
                  break
               end
               found = found + 1
            end
         end
      else
         -- Not found.
         entries[i].hash = HASH_MAX
      end
   end
end

function LookupStreamer:is_empty(i)
   assert(i >= 0 and i < self.stride)
   return self.entries[i].hash == HASH_MAX
end

function LookupStreamer:is_found(i)
   return not self:is_empty(i)
end

-- One of Bob Jenkins' hashes from
-- http://burtleburtle.net/bob/hash/integer.html.  Chosen to result
-- in the least badness as we adapt to int32 bitops.
function hash_i32(i32)
   i32 = tobit(i32)
   i32 = i32 + bnot(lshift(i32, 15))
   i32 = bxor(i32, (rshift(i32, 10)))
   i32 = i32 + lshift(i32, 3)
   i32 = bxor(i32, rshift(i32, 6))
   i32 = i32 + bnot(lshift(i32, 11))
   i32 = bxor(i32, rshift(i32, 16))

   -- Unset the low bit, to distinguish valid hashes from HASH_MAX.
   i32 = lshift(i32, 1)
   -- Project result to u32 range.
   return i32 - INT32_MIN
end

local murmur = require('lib.hash.murmur').MurmurHash3_x86_32:new()
local vptr = ffi.new("uint8_t [4]")
function murmur_hash_i32(i32)
   ffi.cast("int32_t*", vptr)[0] = i32
   local h = murmur:hash(vptr, 4, 0ULL).u32[0]

   -- Unset the low bit, to distinguish valid hashes from HASH_MAX.
   local i32 = lshift(i32, 1)
   -- Project result to u32 range.
   return i32 - INT32_MIN
end

function selftest()
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

   local function test_jenkins(iterations)
      local result
      for i=1,iterations do result=hash_i32(i) end
      return result
   end

   local function test_murmur(iterations)
      local result
      for i=1,iterations do result=murmur_hash_i32(i) end
      return result
   end

   check_perf(test_jenkins, 1e8, 15, 4, 'jenkins hash')
   check_perf(test_murmur, 1e8, 30, 8, 'murmur hash (32 bit)')

   -- 32-byte entries
   local rhh = PodHashMap.new(ffi.typeof('uint32_t'), ffi.typeof('int32_t[6]'),
                              hash_i32)
   local occupancy = 2e6
   rhh:resize(occupancy / 0.4 + 1)

   local function test_insertion(count)
      local v = ffi.new('int32_t[6]');
      for i = 1,count do
         for j=0,5 do v[j] = bnot(i) end
         rhh:add(i, v)
      end
   end

   local function test_lookup(count)
      local result
      for i = 1, count do
         result = rhh:lookup(i)
      end
      return result
   end

   check_perf(test_insertion, occupancy, 400, 100, 'insertion (40% occupancy)')
   print('max displacement: '..rhh.max_displacement)
   io.write('selfcheck: ')
   io.flush()
   rhh:selfcheck()
   io.write('pass\n')

   io.write('population check: ')
   io.flush()
   for i = 1, occupancy do
      local offset = rhh:lookup(i)
      assert(rhh:val_at(offset)[0] == bnot(i))
   end
   rhh:selfcheck()
   io.write('pass\n')

   io.write('iteration check: ')
   io.flush()
   local iterated = 0
   for entry in rhh:iterate() do iterated = iterated + 1 end
   assert(iterated == occupancy)
   io.write('pass\n')

   check_perf(test_lookup, occupancy, 300, 100, 'lookup (40% occupancy)')

   local stride = 1
   repeat
      local streamer = rhh:make_lookup_streamer(stride)
      local function test_lookup_streamer(count)
         local result
         for i = 1, count, stride do
            local n = math.min(stride, count-i+1)
            for j = 0, n-1 do
               streamer.entries[j].key = i + j
            end
            streamer:stream()
            result = streamer.entries[n-1].value[0]
         end
         return result
      end
      -- Note that "result" is part of the value, not an index into
      -- the table, and so we expect the results to be different from
      -- rhh:lookup().
      check_perf(test_lookup_streamer, occupancy, 1000, 100,
                 'streaming lookup, stride='..stride)
      stride = stride * 2
   until stride > 256

   check_perf(test_lookup, occupancy, 300, 100, 'lookup (40% occupancy)')

   -- A check that our equality functions work as intended.
   local numbers_equal = make_equal_fn(ffi.typeof('int'))
   local four_byte = ffi.typeof('uint32_t[1]')
   local eight_byte = ffi.typeof('uint32_t[2]')
   local twelve_byte = ffi.typeof('uint32_t[3]')
   local four_byte_equal = make_equal_fn(four_byte)
   local eight_byte_equal = make_equal_fn(eight_byte)
   local twelve_byte_equal = make_equal_fn(twelve_byte)
   assert(numbers_equal(1,1))
   assert(not numbers_equal(1,2))
   assert(four_byte_equal(ffi.new(four_byte, {1}),
                          ffi.new(four_byte, {1})))
   assert(not four_byte_equal(ffi.new(four_byte, {1}),
                              ffi.new(four_byte, {2})))
   assert(eight_byte_equal(ffi.new(eight_byte, {1,1}),
                           ffi.new(eight_byte, {1,1})))
   assert(not eight_byte_equal(ffi.new(eight_byte, {1,1}),
                               ffi.new(eight_byte, {1,2})))
   assert(twelve_byte_equal(ffi.new(twelve_byte, {1,1,1}),
                            ffi.new(twelve_byte, {1,1,1})))
   assert(not twelve_byte_equal(ffi.new(twelve_byte, {1,1,1}),
                                ffi.new(twelve_byte, {1,1,2})))
end

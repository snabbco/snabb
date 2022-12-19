module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local S = require("syscall")
local lib = require("core.lib")
local binary_search = require("lib.binary_search")
local multi_copy = require("lib.multi_copy")
local siphash = require("lib.hash.siphash")

local min, max, floor, ceil = math.min, math.max, math.floor, math.ceil

CTable = {}
LookupStreamer = {}

local HASH_MAX = 0xFFFFFFFF
local uint8_ptr_t = ffi.typeof('uint8_t*')
local uint16_ptr_t = ffi.typeof('uint16_t*')
local uint32_ptr_t = ffi.typeof('uint32_t*')
local uint64_ptr_t = ffi.typeof('uint64_t*')

local function compute_hash_fn(key_ctype, seed)
   if tonumber(ffi.new(key_ctype)) then
      return siphash.make_u64_hash({c=1, d=2, key=seed})
   else
      return siphash.make_hash({c=1, d=2, size=ffi.sizeof(key_ctype),
                                key=seed})
   end
end

local function compute_multi_hash_fn(key_ctype, width, stride, seed)
   if tonumber(ffi.new(key_ctype)) then
      -- We could fix this, but really it would be nicest to prohibit
      -- scalar keys.
      error('streaming lookup not available for scalar keys')
   end
   return siphash.make_multi_hash({c=1, d=2, size=ffi.sizeof(key_ctype),
                                   width=width, stride=stride, key=seed})
end

local entry_types = {}
local function make_entry_type(key_type, value_type)
   local cache = entry_types[key_type]
   if cache then
      cache = cache[value_type]
      if cache then return cache end
   else
      entry_types[key_type] = {}
   end
   local raw_size = ffi.sizeof(key_type) + ffi.sizeof(value_type) + 4
   local padding = 2^ceil(math.log(raw_size)/math.log(2)) - raw_size
   local ret = ffi.typeof([[struct {
         uint32_t hash;
         $ key;
         $ value;
         uint8_t padding[$];
      } __attribute__((packed))]],
      key_type,
      value_type,
      padding)
   entry_types[key_type][value_type] = ret
   return ret
end

local function make_entries_type(entry_type)
   return (ffi.typeof('$[?]', entry_type))
end

-- hash := [0,HASH_MAX); scale := size/HASH_MAX
local function hash_to_index(hash, scale)
   return (floor(hash*scale))
end

local function make_equal_fn(key_type)
   local size = ffi.sizeof(key_type)
   local cast = ffi.cast
   if tonumber(ffi.new(key_type)) then
      return function (a, b)
         return a == b
      end
   elseif size == 2 then
      return function (a, b)
         return cast(uint16_ptr_t, a)[0] == cast(uint16_ptr_t, b)[0]
      end
   elseif size == 4 then
      return function (a, b)
         return cast(uint32_ptr_t, a)[0] == cast(uint32_ptr_t, b)[0]
      end
   elseif size == 6 then
      return function (a, b)
         return (cast(uint32_ptr_t, a)[0] == cast(uint32_ptr_t, b)[0] and
                 cast(uint16_ptr_t, a)[2] == cast(uint16_ptr_t, b)[2])
      end
   elseif size == 8 then
      return function (a, b)
         return cast(uint64_ptr_t, a)[0] == cast(uint64_ptr_t, b)[0]
      end
   else
      return function (a, b)
         return C.memcmp(a, b, size) == 0
      end
   end
end

local function parse_params(params, required, optional)
   local ret = {}
   for k, _ in pairs(required) do
      if params[k] == nil then error('missing required option ' .. k) end
   end
   for k, v in pairs(params) do
      if not required[k] and optional[k] == nil then
         error('unrecognized option ' .. k)
      end
      ret[k] = v
   end
   for k, v in pairs(optional) do
      if ret[k] == nil then ret[k] = v end
   end
   return ret
end

-- FIXME: For now the value_type option is required, but in the future
-- we should allow for a nil value type to create a set instead of a
-- map.
local required_params = lib.set('key_type', 'value_type')
local optional_params = {
   hash_seed = false,
   initial_size = 8,
   max_occupancy_rate = 0.9,
   min_occupancy_rate = 0.0,
   resize_callback = false,
   -- The default value for max_displacement_limit is infinity.
   -- This is safe but uses lots of memory. An alternative
   -- known-to-be-reasonable, virtually-infinite-in-practice value is: 30.
   -- In practice, users of lib.ctable can use a lower max_displacement
   -- to limit memory usage. See CTable:resize().
   max_displacement_limit = 1/0
}

function new(params)
   local ctab = {}   
   local params = parse_params(params, required_params, optional_params)
   ctab.entry_type = make_entry_type(params.key_type, params.value_type)
   ctab.type = make_entries_type(ctab.entry_type)
   function ctab.make_hash_fn()
      return compute_hash_fn(params.key_type, ctab.hash_seed)
   end
   function ctab.make_multi_hash_fn(width)
      local stride, seed = ffi.sizeof(ctab.entry_type), ctab.hash_seed
      return compute_multi_hash_fn(params.key_type, width, stride, seed)
   end
   ctab.equal_fn = make_equal_fn(params.key_type)
   ctab.size = 0
   ctab.max_displacement = 0
   ctab.occupancy = 0
   ctab.lookup_helpers = {}
   ctab.max_occupancy_rate = params.max_occupancy_rate
   ctab.min_occupancy_rate = params.min_occupancy_rate
   ctab.resize_callback = params.resize_callback
   ctab.max_displacement_limit = params.max_displacement_limit
   ctab = setmetatable(ctab, { __index = CTable })
   ctab:reseed_hash_function(params.hash_seed)
   ctab:resize(params.initial_size)
   return ctab
end

-- FIXME: There should be a library to help allocate anonymous
-- hugepages, not this code.
local try_huge_pages = true
local huge_page_threshold = 1e6
local huge_page_size = memory.get_huge_page_size()
local function calloc(t, count)
   if count == 0 then return 0, 0 end
   local byte_size = ffi.sizeof(t) * count
   local alloc_byte_size = byte_size
   local mem, err
   if try_huge_pages and byte_size > huge_page_threshold then
      alloc_byte_size = ceil(byte_size/huge_page_size) * huge_page_size
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
   ffi.gc(ret, function (ptr) S.munmap(ptr, alloc_byte_size) end)
   return ret, byte_size
end

function CTable:reseed_hash_function(seed)
   -- The hash function's seed determines the hash value of an input,
   -- and thus the iteration order for the table.  Usually this is a
   -- feature: besides preventing hash-flood attacks, it also prevents a
   -- quadratic-time complexity when initially populating a table from
   -- entries stored in hash order, as can happen when reading in a
   -- table from a serialization.  However, when SNABB_RANDOM_SEED is
   -- set, then presumably we're trying to reproduce deterministic
   -- behavior, as with quickcheck, and in that case a random seed can
   -- make it more onerous to prove that make_table({A=B,C=D}) is equal
   -- to make_table({A=B,C=D}) as the two tables could have different
   -- iteration orders.  So, in "quickcheck mode", always seed hash
   -- tables with the same value.
   if seed then
      self.hash_seed = seed
   elseif lib.getenv("SNABB_RANDOM_SEED") then
      self.hash_seed = siphash.sip_hash_key_from_seed(
         lib.getenv("SNABB_RANDOM_SEED"))
   else
      self.hash_seed = siphash.random_sip_hash_key()
   end
   self.hash_fn = self.make_hash_fn()

   -- FIXME: Invalidate associated lookup streamers, as they need new
   -- multi_hash functions.
end

function CTable:resize(size)
   assert(size >= (self.occupancy / self.max_occupancy_rate))
   assert(size == floor(size))
   local old_entries = self.entries
   local old_size = self.size
   local old_max_displacement = self.max_displacement

   -- Theoretically, all hashes can map to the last bucket and
   -- max_displacement could become as large as the table size. To be
   -- safe, we should allocate twice as many entries as the size of
   -- the table.  In practice, max_displacement is expected to always
   -- be a small number.  We use max_displacement_limit as a cap for 
   -- this value that "should be enough for everyone".  This is not
   -- entirely safe, since an overrun can occur before the check for
   -- the cap in maybe_increase_max_displacement(). The factor 2 here
   -- reduces that risk but does not eliminate it.
   local alloc_size = math.min(size*2, size + 2 * self.max_displacement_limit)
   self.entries, self.byte_size = calloc(self.entry_type, alloc_size)
   self.size = size
   self.scale = self.size / HASH_MAX
   self.occupancy = 0
   self.max_displacement = 0
   self.lookup_helper = self:make_lookup_helper()
   self.occupancy_hi = ceil(self.size * self.max_occupancy_rate)
   self.occupancy_lo = floor(self.size * self.min_occupancy_rate)
   for i=0,alloc_size-1 do self.entries[i].hash = HASH_MAX end

   if old_size ~= 0 then self:reseed_hash_function() end

   for i=0,old_size+old_max_displacement-1 do
      if old_entries[i].hash ~= HASH_MAX then
         self:add(old_entries[i].key, old_entries[i].value)
      end
   end
   if self.resize_callback then
      self.resize_callback(self, old_size)
   end
end

function CTable:get_backing_size()
   return self.byte_size
end

local header_t = ffi.typeof[[
struct {
   uint32_t size;
   uint32_t occupancy;
   uint32_t max_displacement;
   uint8_t hash_seed[16];
   double max_occupancy_rate;
   double min_occupancy_rate;
}
]]

function load(stream, params)
   local header = stream:read_struct(nil, header_t)
   local params_copy = {}
   for k,v in pairs(params) do params_copy[k] = v end
   params_copy.initial_size = header.size
   params_copy.min_occupancy_rate = header.min_occupancy_rate
   params_copy.hash_seed = ffi.new('uint8_t[16]')
   ffi.copy(params_copy.hash_seed, header.hash_seed, 16)
   params_copy.max_occupancy_rate = header.max_occupancy_rate
   local ctab = new(params_copy)
   ctab.occupancy = header.occupancy
   ctab:maybe_increase_max_displacement(header.max_displacement)
   local entry_count = ctab.size + ctab.max_displacement

   -- Slurp the entries directly into the ctable's backing store.
   -- This ensures that the ctable is in hugepages.
   stream:read_array(ctab.entries, ctab.entry_type, entry_count)

   return ctab
end

function CTable:save(stream)
   stream:write_struct(header_t,
                       header_t(self.size, self.occupancy, self.max_displacement,
                                self.hash_seed, self.max_occupancy_rate,
                                self.min_occupancy_rate))
   stream:write_array(self.entry_type,
                      self.entries,
                      self.size + self.max_displacement)
end

function CTable:make_lookup_helper()
   local entries_per_lookup = self.max_displacement + 1
   local search = self.lookup_helpers[entries_per_lookup]
   if search == nil then
      search = binary_search.gen(entries_per_lookup, self.entry_type)
      self.lookup_helpers[entries_per_lookup] = search
   end
   return search
end

function CTable:maybe_increase_max_displacement(displacement)
   if displacement <= self.max_displacement then return end
   assert(displacement <= self.max_displacement_limit)
   self.max_displacement = displacement
   self.lookup_helper = self:make_lookup_helper()
end

function CTable:add(key, value, updates_allowed)
   if self.occupancy + 1 > self.occupancy_hi then
      -- Note that resizing will invalidate all hash keys, so we need
      -- to hash the key after resizing.
      self:resize(max(self.size * 2, 1)) -- Could be current size is 0.
   end

   local hash = self.hash_fn(key)
   assert(hash >= 0)
   assert(hash < HASH_MAX)

   local entries = self.entries
   local scale = self.scale
   -- local start_index = hash_to_index(hash, self.scale)
   local start_index = floor(hash*self.scale)
   local index = start_index

   -- Fast path.
   if entries[index].hash == HASH_MAX and updates_allowed ~= 'required' then
      self.occupancy = self.occupancy + 1
      local entry = entries + index
      entry.hash = hash
      entry.key = key
      entry.value = value
      return entry
   end

   while entries[index].hash < hash do
      index = index + 1
   end

   while entries[index].hash == hash do
      local entry = entries + index
      if self.equal_fn(key, entry.key) then
         assert(updates_allowed, "key is already present in ctable")
         entry.key = key
         entry.value = value
         return entry
      end
      index = index + 1
   end

   assert(updates_allowed ~= 'required', "key not found in ctable")

   self:maybe_increase_max_displacement(index - start_index)

   if entries[index].hash ~= HASH_MAX then
      -- In a robin hood hash, we seek to spread the wealth around among
      -- the members of the table.  An entry that can be stored exactly
      -- where hash_to_index() maps it is a most wealthy entry.  The
      -- farther from that initial position, the less wealthy.  Here we
      -- have found an entry whose hash is greater than our hash,
      -- meaning it has travelled less far, so we steal its position,
      -- displacing it by one.  We might have to displace other entries
      -- as well.
      local empty = index;
      while entries[empty].hash ~= HASH_MAX do empty = empty + 1 end
      while empty > index do
         entries[empty] = entries[empty - 1]
         local displacement = empty - hash_to_index(entries[empty].hash, scale)
         self:maybe_increase_max_displacement(displacement)
         empty = empty - 1;
      end
   end
           
   self.occupancy = self.occupancy + 1
   local entry = entries + index
   entry.hash = hash
   entry.key = key
   entry.value = value
   return entry
end

function CTable:update(key, value)
   return self:add(key, value, 'required')
end

function CTable:lookup_ptr(key)
   local hash = self.hash_fn(key)
   local entry = self.entries + hash_to_index(hash, self.scale)
   entry = self.lookup_helper(entry, hash)

   if hash == entry.hash then
      -- Peel the first iteration of the loop; collisions will be rare.
      if self.equal_fn(key, entry.key) then return entry end
      entry = entry + 1
      if entry.hash ~= hash then return nil end
      while entry.hash == hash do
         if self.equal_fn(key, entry.key) then return entry end
         -- Otherwise possibly a collision.
         entry = entry + 1
      end
      -- Not found.
      return nil
   else
      -- Not found.
      return nil
   end
end

function CTable:lookup_and_copy(key, entry)
   local entry_ptr = self:lookup_ptr(key)
   if not entry_ptr then return false end
   ffi.copy(entry, entry_ptr, ffi.sizeof(entry))
   return true
end

function CTable:remove_ptr(entry)
   local scale = self.scale
   local index = entry - self.entries
   assert(index >= 0)
   assert(index < self.size + self.max_displacement)
   assert(entry.hash ~= HASH_MAX)

   self.occupancy = self.occupancy - 1
   entry.hash = HASH_MAX

   while true do
      entry = entry + 1
      index = index + 1
      if entry.hash == HASH_MAX then break end
      if hash_to_index(entry.hash, scale) == index then break end
      -- Give to the poor.
      entry[-1] = entry[0]
      entry.hash = HASH_MAX
   end

   if self.occupancy < self.occupancy_lo then
      self:resize(max(ceil(self.size / 2), 1))
   end
end

-- FIXME: Does NOT shrink max_displacement
function CTable:remove(key, missing_allowed)
   local ptr = self:lookup_ptr(key)
   if not ptr then
      assert(missing_allowed, "key not found in ctable")
      return false
   end
   self:remove_ptr(ptr)
   return true
end

function CTable:make_lookup_streamer(width)
   assert(width > 0 and width <= 262144, "Width value out of range: "..width)
   local res = {
      all_entries = self.entries,
      width = width,
      equal_fn = self.equal_fn,
      entries_per_lookup = self.max_displacement + 1,
      scale = self.scale,
      pointers = ffi.new('void*['..width..']'),
      entries = self.type(width),
      hashes = ffi.new('uint32_t[?]', width),
      -- Binary search over N elements can return N if no entry was
      -- found that was greater than or equal to the key.  We would
      -- have to check the result of binary search to ensure that we
      -- are reading a value in bounds.  To avoid this, allocate one
      -- more entry.
      stream_entries = self.type(width * (self.max_displacement + 1) + 1)
   }
   -- Pointer to first entry key (cache to avoid cdata allocation.)
   local key_offset = 4 -- Skip past uint32_t hash.
   res.keys = ffi.cast('uint8_t*', res.entries) + key_offset
   -- Give res.pointers sensible default values in case the first lookup
   -- doesn't fill the pointers vector.
   for i = 0, width-1 do res.pointers[i] = self.entries end

   -- Initialize the stream_entries to HASH_MAX for sanity.
   for i = 0, width * (self.max_displacement + 1) do
      res.stream_entries[i].hash = HASH_MAX
   end

   -- Compile multi-copy and binary-search procedures that are
   -- specialized for this table and this width.
   local entry_size = ffi.sizeof(self.entry_type)
   res.multi_copy = multi_copy.gen(width, res.entries_per_lookup * entry_size)
   res.multi_hash = self.make_multi_hash_fn(width)
   res.binary_search = binary_search.gen(res.entries_per_lookup, self.entry_type)

   return setmetatable(res, { __index = LookupStreamer })
end

function LookupStreamer:stream()
   local width = self.width
   local entries = self.entries
   local pointers = self.pointers
   local stream_entries = self.stream_entries
   local entries_per_lookup = self.entries_per_lookup
   local equal_fn = self.equal_fn

   self.multi_hash(self.keys, self.hashes)

   for i=0,width-1 do
      local hash = self.hashes[i]
      entries[i].hash = hash
      pointers[i] = self.all_entries + hash_to_index(hash, self.scale)
   end

   self.multi_copy(stream_entries, pointers)

   -- Copy results into entries.
   for i=0,width-1 do
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
   assert(i >= 0 and i < self.width)
   return self.entries[i].hash == HASH_MAX
end

function LookupStreamer:is_found(i)
   return not self:is_empty(i)
end

function CTable:selfcheck()
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
   for i = 0,self.size+self.max_displacement-1 do
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

function CTable:dump()
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
   for index=0,self.size-1+self.max_displacement do dump_one(index) end
end

function CTable:iterate()
   local max_entry = self.entries + self.size + self.max_displacement
   local function next_entry(max_entry, entry)
      while true do
         entry = entry + 1
         if entry >= max_entry then return nil end
         if entry.hash ~= HASH_MAX then return entry end
      end
   end
   return next_entry, max_entry, self.entries - 1
end

function CTable:next_entry(offset, limit)
   if offset >= self.size + self.max_displacement then
      return 0, nil
   elseif limit == nil then
      limit = self.size + self.max_displacement
   else
      limit = min(limit, self.size + self.max_displacement)
   end
   for offset=offset, limit-1 do
      if self.entries[offset].hash ~= HASH_MAX then
         return offset, self.entries + offset
      end
   end
   return limit, nil
end

function selftest()
   print("selftest: ctable")
   local bnot = require("bit").bnot

   -- 32-byte entries
   local occupancy = 2e6
   local params = {
      key_type = ffi.typeof('uint32_t[1]'),
      value_type = ffi.typeof('int32_t[6]'),
      max_occupancy_rate = 0.4,
      initial_size = ceil(occupancy / 0.4)
   }
   local ctab = new(params)

   -- Fill with {i} -> { bnot(i), ... }.
   local k = ffi.new('uint32_t[1]');
   local v = ffi.new('int32_t[6]');
   for i = 1,occupancy do
      k[0] = i
      for j=0,5 do v[j] = bnot(i) end
      ctab:add(k, v)
   end

   for i=1,2 do
      -- The max displacement of this table will depend on the hash
      -- seed, but we know for this input that it should rather small.
      -- Assert here so that we can detect any future deviation or
      -- regression.
      assert(ctab.max_displacement < 15, ctab.max_displacement)

      ctab:selfcheck()

      for i = 1, occupancy do
         k[0] = i
         local value = ctab:lookup_ptr(k).value[0]
         assert(value == bnot(i))
      end
      ctab:selfcheck()

      -- Incrementing by 31 instead of 1 just to save test time.
      do
         local entry = ctab.entry_type()
         for i = 1, occupancy, 31 do
            k[0] = i
            assert(ctab:lookup_and_copy(k, entry))
            assert(entry.key[0] == i)
            assert(entry.value[0] == bnot(i))
            ctab:remove(entry.key)
            assert(ctab:lookup_ptr(k) == nil)
            ctab:add(entry.key, entry.value)
            assert(ctab:lookup_ptr(k).value[0] == bnot(i))
         end
      end

      local iterated = 0
      for entry in ctab:iterate() do iterated = iterated + 1 end
      assert(iterated == occupancy)

      -- Save the table out to disk, reload it, and run the same
      -- checks.
      local tmp = os.tmpname()
      local file = require("lib.stream.file")
      do
         local stream = file.open(tmp, 'wb')
         ctab:save(stream)
         stream:close()
      end
      do
         local stream = file.open(tmp, 'rb')
         ctab = load(stream, params)
         stream:close()
      end         
      os.remove(tmp)
   end

   -- OK, all looking good with the normal interfaces; let's check out
   -- streaming lookup.
   local width = 1
   repeat
      local streamer = ctab:make_lookup_streamer(width)
      for i = 1, occupancy, width do
         local n = min(width, occupancy-i+1)
         for j = 0, n-1 do
            streamer.entries[j].key[0] = i + j
         end

         streamer:stream()
         for j = 0, n-1 do
            assert(streamer:is_found(j))
            local value = streamer.entries[j].value[0]
            assert(value == bnot(i + j))
         end
      end
      width = width * 2
   until width > 256

   -- A check that our equality functions work as intended.
   local numbers_equal = make_equal_fn(ffi.typeof('int'))
   assert(numbers_equal(1,1))
   assert(not numbers_equal(1,2))

   local function check_bytes_equal(type, a, b)
      local equal_fn = make_equal_fn(type)
      local hash_fn = compute_hash_fn(type)
      assert(equal_fn(ffi.new(type, a), ffi.new(type, a)))
      assert(not equal_fn(ffi.new(type, a), ffi.new(type, b)))
      assert(hash_fn(ffi.new(type, a)) == hash_fn(ffi.new(type, a)))
      assert(hash_fn(ffi.new(type, a)) ~= hash_fn(ffi.new(type, b)))
   end
   check_bytes_equal(ffi.typeof('uint16_t[1]'), {1}, {2})         -- 2 byte
   check_bytes_equal(ffi.typeof('uint32_t[1]'), {1}, {2})         -- 4 byte
   check_bytes_equal(ffi.typeof('uint16_t[3]'), {1,1,1}, {1,1,2}) -- 6 byte
   check_bytes_equal(ffi.typeof('uint32_t[2]'), {1,1}, {1,2})     -- 8 byte
   check_bytes_equal(ffi.typeof('uint32_t[3]'), {1,1,1}, {1,1,2}) -- 12 byte

   print("selftest: ok")
end

-- This module implements a basic Bloom filter as described in
-- <http://en.wikipedia.org/wiki/Bloom_filter>.
--
-- Given the expected number of items n to be stored in the filter and
-- the maxium acceptable false-positive rate p when the filter
-- contains that number of items, the size m of the storage cell in
-- bits and the number k of hash calculations are determined by
--
--  m = -n ln(p)/ln(2)^2
--  k = m/n ln(2) = -ln(p)/ln(2)
--
-- According to
-- <http://www.eecs.harvard.edu/~kirsch/pubs/bbbf/esa06.pdf>, the k
-- independent hash functions can be replaced by two h1, h2 and the
-- "linear combinations" h[i] = h1 + i*h2 (i=1..k) without changing
-- the statistics of the filter.  Furthermore, h1 and h2 can be
-- derived from the same hash function using double hashing or seeded
-- hashing.  This implementation requires the "x64_128" variant of the
-- Murmur hash family provided by lib.hash.murmur.
--
-- Storing a sequence of bytes of length l in the filter proceeds as
-- follows.  First, the hash function is applied to the data with seed
-- value 0.
--
--  h1 = hash(data, l, 0)
--
-- In this pseudo-code, h1 represents the lower 64 bits of the actual
-- hash.  The second hash is obtained by using h1 as seed
--
--  h2 = hash(data, l, h1)
--
-- Finally, k values in the range [0, m-1] are calculated as
--
--  k_i = (h1 + i*h2) % m
--
-- In order to be able to implement the mod m operation using bitops,
-- m is rounded up to the next power of 2.  In that case, the k_i can
-- be calculated efficiently by
--
--  k_i = bit.band(h1 + i*h2, m-1)
--
-- The values k_i represent the original data.  Such a set of values
-- is called an *item*.  The actual filter consists of a data
-- structure that stores one bit for each of the m elements in the
-- filter, called a *cell*.  To store an item in a cell, the bits at
-- the positions given by the values k_i are set to one.

module(..., package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local bit = require("bit")
local murmur = require("lib.hash.murmur")

local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local filter = subClass(nil)
filter._name = "Bloom filter"
local selftest_config = { verbose = false, performance = false }

-- n = expected maximum number of objects to store
-- p = maximum false positive rate in the range 0 < p < 1
function filter:new (n, p)
   assert(n > 0 and p < 1 and p > 0, self:name()..": invalid parameters")
   local o = filter:superClass().new(self)
   local ln2 = math.log(2)
   local m = - n * math.log(p) / ln2^2
   m = 2^math.ceil(math.log(m)/ln2)  -- Round up to the next power of two
   o._m = m
   o._k = math.ceil(m/n*ln2)
   o._mod = ffi.new("uint64_t", m-1)
   o._hash1 = murmur.MurmurHash3_x64_128:new()
   o._hash2 = murmur.MurmurHash3_x64_128:new()
   return o
end

-- Return the number of hash functions for this filter.
function filter:nhashes ()
   return self._k
end

-- Return the number of bits contained in a storage cell for this
-- filter. This is guaranteed to be a power of 2.
function filter:width()
   return self._m
end

-- Create a new storage cell, consisting of an array of 64-bit
-- integers which is large enough to hold the m bits of the filter.
function filter:cell_new ()
   local nblocks = rshift(self._m, 6)
   if band(self._m, 0x3FULL) ~= 0ULL then
      nblocks = nblocks + 1
   end
   return ffi.typeof("uint64_t [$]", nblocks)()
end

-- Remove all stored items from a cell by setting all bits to zero.
function filter:cell_clear (cell)
   ffi.fill(cell, ffi.sizeof(cell))
end

-- Copy cell d to cell s (assuming that they are of equal type)
function filter:cell_copy (s, d)
   ffi.copy(d, s, ffi.sizeof(d))
end

-- Return the ratio of the number of bits which are set to one to the
-- total number of bits in the cell's bitset, which is a measure of
-- how full the storage cell is.
function filter:cell_usage (cell)
   local set = 0
   local width = self._m
   for i = 0, width-1 do
      if band(cell[rshift(i, 6)], lshift(1ULL, band(i, 0x3FULL))) ~= 0ULL then
	 set = set+1
      end
   end
   return set/width
end

-- Create a new storage item, consisting of an array of 64-bit
-- integers of size k.  We don't use Lua numbers to avoid conversions
-- in the store_value() and check_value() methods.  The item can
-- optionally be filled with the given value.
function filter:item_new (v, l)
   local item = ffi.typeof("uint64_t[$]", self._k)()
   if v and l then
      self:store_value(v, l, item, nil)
   end
   return item
end

-- Return an array that contains the item's data as Lua values.  This
-- is primarily intended for debugging or diagnostic purposes.
function filter:item_dump (item)
   dump = {}
   for i = 0, self._k-1 do
      table.insert(dump, tonumber(item[i]))
   end
   return dump
end

-- Store a value in a item and/or cell. The value is represented by a
-- pointer to a location in memory where the data is stored and its
-- size l in bytes. The argument v is, in fact, not the pointer itself
-- but a cdata object of type "uint8_t *[1]". Example usage where
-- "value" is the pointer to the actual data and sizeofvalue is its
-- size:
--
--  local vptr = ffi.new("uint8_t *[1]")
--  vptr[0] = value
--  filter:store_value(vptr, sizeofvalue, item)
--
-- This avoids the allocation of a cdata object of type "uint8_t*" for
-- the method call, removing the dependence on the sink optimizer to
-- generate code that is free of garbage.
function filter:store_value (v, l, item, cell)
   local h1 = self._hash1:hash(v[0], l, 0ULL)
   local h2 = self._hash2:hash(v[0], l, h1.u64[0])
   for i = 1, self._k do
      local index = band(h1.u64[0] + i*h2.u64[0], self._mod)
      if cell then
   	 local block = rshift(index, 6)
      	 cell[block] = bor(cell[block], lshift(1ULL, band(index, 0x3FULL)))
      end
      if item then
   	 item[i-1] = index
      end
   end
end

-- Store an item in a cell
function filter:store_item (item, cell)
   for i = 0, self._k-1 do
      local index = item[i]
      local block = rshift(index, 6)
      cell[block] = bor(cell[block], lshift(1ULL, band(index, 0x3FULL)))
   end
end

-- Check whether a value is contained in a cell and return the result
-- as a boolean.  The value is represented in the same manner as for
-- the store_value() method.
--
-- Due to the nature of a Bloom filter, a positive outcome does not
-- guarantee that the value has actually been stored in the cell
-- before (but the rate of these false positives is bounded by the
-- parameter 'p' passed to the constructor of the filter). OTOH, a
-- negative outcome guarantees that the value has not been stored in
-- the cell.
function filter:check_value (v, l, cell)
   local h1 = self._hash1:hash(v[0], l, 0ULL)
   local h2 = self._hash2:hash(v[0], l, h1.u64[0])
   for i = 1, self._k do
      local index = band(h1.u64[0] + i*h2.u64[0], self._mod)
      if band(cell[rshift(index, 6)], lshift(1ULL, band(index, 0x3FULL))) == 0ULL then
	 return false
      end
   end
   return true
end

-- Check whether a given item is contained in a cell.
function filter:check_item (item, cell)
   for i = 0, self._k-1 do
      local index = item[i]
      if band(cell[rshift(index, 6)], lshift(1ULL, band(index, 0x3FULL))) == 0ULL then
      	 return false
      end
   end
   return true
end

local function check_buckets(filter, item, expected)
   for k, i in ipairs(filter:item_dump(item)) do
      assert(i == expected[k], "wrong bucket index "..k
	     .." (expected "..expected[k]..", got "..tostring(i)..")")
   end
end

function selftest()
   local murmur = require("lib.hash.murmur")

   local f = filter:new(100, 0.001)
   assert(f:width() == 2048, "woring size of bitset, expected 2048, got "..f:width())
   assert(f:nhashes() == 15, "wrong number of hashes, expected 15, got "..f:nhashes())
   local cell, item = f:cell_new(), f:item_new()

   local data1 = ffi.new("uint8_t[9]", 'foobarbaz')
   local data2 = ffi.new("uint8_t[1]", 'a')
   local s1, s2 = ffi.sizeof(data1), ffi.sizeof(data2)
   local dptr1, dptr2 = ffi.new("uint8_t*[1]"), ffi.new("uint8_t *[1]")
   dptr1[0] = data1
   dptr2[0] = data2
   local expected_buckets = { 149, 986, 1823, 612, 1449, 238, 1075,
   			      1912, 701, 1538, 327, 1164, 2001, 790,
   			      1627 }

   f:store_value(dptr1, s1, item, nil)
   check_buckets(f, item, expected_buckets)
   f:store_value(dptr1, s1, nil, cell)
   assert(f:check_item(item, cell), "check from item failed")
   assert(f:check_value(dptr1, s1, cell), "check from value failed")
   assert(not f:check_value(dptr2, s2, cell), "non-existance check failed")
   f:cell_clear(cell)
   assert(not f:check_value(dptr1, s1, cell), "clear store failed")
   f:store_value(dptr2, s2, item)
   f:store_value(dptr1, s1, item)
   check_buckets(f, item, expected_buckets)

   data1 = ffi.new("union { uint32_t i; uint8_t b[4]; }")
   dptr1[0] = data1.b
   data2 = ffi.new("union { uint32_t i; uint8_t b[4]; }")
   dptr2[0] = data2.b
   s1, s2 = ffi.sizeof(data1), ffi.sizeof(data2)
   
   local min, max, step, samples = 50, 150, 10, 20000
   data1 = ffi.new("uint32_t [?]", max)
   data2 = ffi.new("uint32_t [?]", samples)
   for i = 0, max-1 do
      data1[i] = i
   end
   for i = 0, samples-1 do
      data2[i] = i+max
   end
   for j = min, max, step do
      f:cell_clear(cell)
      local fail = 0
      for i = 0, j-1 do
   	 dptr1[0] = ffi.cast("uint8_t *", data1 + i)
   	 f:store_value(dptr1, ffi.sizeof("uint32_t"), item, cell)
   	 assert(f:check_item(item, cell))
   	 assert(f:check_value(dptr1, s1, cell))
      end

      local fp = 0
      for i = 0, samples-1 do
   	 dptr1[0] = ffi.cast("uint8_t *", data2 + i)
   	 if f:check_value(dptr1, ffi.sizeof("uint32_t"), cell) then
   	    fp = fp+1
   	 end
      end
      if selftest_config.verbose then
   	 print(string.format("False-positive rate @%d (occupancy %02.2f%%): %.4f, %d",
   			     j, 100*f:cell_usage(cell), fp/samples, fp))
      end
      if j == 100 then
   	 assert(fp/samples <= 0.001,
   		"Maximum false-positives rate exceeded, expected 0.1%, got "..fp/samples)
      end
   end

   if selftest_config.performance then

      local function perfloop (iter, desc, call, ...)
	 jit.flush()
	 local start = ffi.C.get_time_ns()
	 for i = 1, iter do
	    call(...)
	 end
	 local stop = ffi.C.get_time_ns()
	 print(desc..": "..math.floor(iter/(tonumber(stop-start)/1e9))
	    .." iterations per second")
      end

      print("Bloom filter performance tests")
      data1 = ffi.new("uint8_t [6]", '\x01\x02\x03\x04\x05\x06')
      dptr1[0] = ffi.cast("uint8_t *", data1)
      local iter = 1e8
      f:store_value(dptr1, 6, item, cell)
      perfloop(iter, "check item", f.check_item, f, item, cell)
      perfloop(iter, "store item", f.store_item, f, item, cell)
      perfloop(iter, "store value cell/item", f.store_value, f, dptr1, 6, item, cell)
      perfloop(iter, "store value cell", f.store_value, f, dptr1, 6, nil, cell)
      perfloop(iter, "store value item", f.store_value, f, dptr1, 6, item)
      perfloop(iter, "check value", f.check_value, f, dptr1, 6, cell)
   end
end

filter.selftest = selftest

return filter

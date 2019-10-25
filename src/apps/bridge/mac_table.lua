-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
--
-- This module implements a MAC address table as part of the learning
-- bridge app (apps.bridge.learning).  It associates a MAC address
-- with the bridge port on which the last packet originating from the
-- address has been seen by the bridge.  It also stores the
-- split-horizon group to which the port belongs (if any) to resolve
-- group collisions during forwarding.
--
-- The table is implemented as a hash table based on lib.hash.murmur
-- using open addressing with linear probing and fixed-sized buckets.
--
-- A table is allocated to store a particular number of MAC addresses,
-- called its "size" or "target size".  The number of hash buckets in
-- the table is determined to be the next power of 2 which is at least
-- twice as large as the target size.
--
-- A MAC address is mapped to a bucket by calculating
--
--   index = bit.band(hash(MAC), mask)
--
-- where the mask is equal to the number of buckets minus 1.  This
-- operation runs in constant time (approximately 15 cycles if
-- maximally optimized by the compiler).  Each hash bucket contains a
-- fixed number of slots.  The slots are filled in a linear fashion
-- starting with the lowest one.  The linear search in the bucket
-- scales with the average number of occupied slots per bucket.
--
-- If an address needs to be stored in a bucket which is already full,
-- the address is dropped and an overflow condition is flagged for the
-- table, which will trigger a resizing of the table during the next
-- run of the MAC learning timeout function.
--
-- The qualitiy of the hash table has been examined with a numerical
-- simulation using randomly generated MAC addresses to fill a table
-- to its target size.  The target size is chosen to be a power of 2
-- which represents the worst case, where the number of hash buckets
-- is just twice the target size.
--
-- Size    Fill ratio      Load    Ovrflow Max     Avg     Std-dev
--       64        1.00    0.38    false   3       1.33    0.55
--      128        1.00    0.39    false   3       1.28    0.57
--      256        1.00    0.40    false   3       1.25    0.50
--      512        1.00    0.39    false   4       1.27    0.54
--     1024        1.00    0.39    false   5       1.29    0.57
--     2048        1.00    0.40    false   4       1.27    0.53
--     4096        1.00    0.39    false   4       1.27    0.53
--     8192        1.00    0.40    false   5       1.26    0.53
--    16384        1.00    0.39    false   5       1.27    0.54
--    32768        1.00    0.39    false   6       1.27    0.54
--    65536        1.00    0.39    false   6       1.27    0.54
--   131072        1.00    0.39    false   6       1.27    0.54
--   262144        1.00    0.39    false   6       1.27    0.54
--
-- The simulation stops if either the number of stored addresses is
-- equal to the target size or an overflow occured.  In this
-- simulation, the bucket size was chosen to be >= 6.  It shows that
-- up to a target size of 2^18, the table could always be completely
-- filled without hitting an overflow.  The average number of used
-- slots per bucket as well as its standard deviation are constant, as
-- is the load factor (the ration of non-empty buckets and the total
-- number of buckets).  Based on this simulation, the bucket size is
-- chosen to be 6.  The performance will only depend on the average
-- number of used slots, not the bucket size.
--
-- MAC addresses are refreshed and timed out by using two separate
-- tables, called "main" and "shadow".  When an address is learned, it
-- is always stored in both tables, but lookups occur only in the main
-- table.  After a configurable interval, the tables are rotated,
-- i.e. the shadow table becomes the main table and vice versa and all
-- entries are removed from the new shadow table.  The effect is that
-- the main table contains only the addresses learned during the
-- previous interval.
--
-- The timeout function also calls the instance method maybe_resize()
-- which checks whether the main table has suffered an overflow or the
-- target size has been reached during the last timeout interval.  In
-- that case, a new target size is calculated by exponentially
-- increasing the current target size until the number of hash buckets
-- reaches the next power of two or the target size reaches the
-- configurable maximum target size.  If the configuration variable
-- copy_on_resize is true (default), the contents of the old table is
-- transferred to the new table.
--
-- Notes on performance and implementation choices:
--
-- The insert and lookup operations require an iteration over the
-- slots of a hash bucket.  Even though the average number of
-- iterations is less than 2, the code must be written in a manner
-- that performs equally well for any number of iterations up to the
-- size of the bucket.  This kind of "branchy loop" represents one of
-- the worst cases to optimize for the JIT compiler.  Particualarly
-- so, because this loop always occurs within an outer loop in which
-- the bridge app processes incoming packets.
--
-- I was not able to find a way to write this loop in Lua without
-- causing serious performance degradation for varying (but realistic)
-- workloads.  The branches in the inner loop will cause *both* loops
-- to suffer heavily.  In addition, the branches will also require
-- non-trivial garbage-avoidance hacks, which clutter the code and add
-- to the perfomance penalty.  To side-step the problem, the loop has
-- been implemented in C to hide it from the compiler.  In this form
-- it is safe to be called from within an outer loop and it guarantees
-- stable performance with just a little variation due to the varying
-- number of used slots per buckets.  The function call overhead is
-- estimated to be around 20 cycles.
--
-- Unfortunately, this technique forces the bridge app to expose some
-- of its data structures to the MAC table (packet forwarding tables
-- and flooding port lists).
--
-- If anybody figures out how to write this thing in pure Lua without
-- hitting a performance bottleneck, please fix this kludgy code :)

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local murmur = require("lib.hash.murmur")
local logger = require("lib.logger")
local band = require("bit").band
require("apps.bridge.learning_h")

local mac_table = subClass(nil)

local default_config = {
   size = 256,
   timeout = 60,
   verbose = false,
   copy_on_resize = true,
   resize_max = 2^16,
}

local bucket_size = C.BUCKET_SIZE
-- This must match hash_table_t from learning.h
local hash_table_t = ffi.typeof([[
  struct {
    hash_table_header_t h;
    mac_entry_t buckets[?][$];
  }]], bucket_size)

local table_types = { 'main', 'shadow' }
local function alloc_tables (self, buckets)
   for i, type in ipairs(table_types) do
      self._tables[type] = nil
      self._tables[type] = hash_table_t(buckets)
      self._tables_C[i-1] = ffi.cast("hash_table_t*", self._tables[type])
   end
end

-- Round up a number to the next but one power of 2 or the next if the
-- number already is a power of 2.
local function buckets_from_size (size)
   return 2^math.ceil(math.log(size*2)/math.log(2))
end

-- This function is called once per timeout interval to time out MAC
-- addresses and possibly resize the table via the maybe_resize()
-- method if an overflow has occured or the target size has been
-- reached.
local function timeout (self)
   if self._config.verbose then
      local shadow = self._tables.shadow
      local info = self:info(shadow)
      local max, avg, std_dev = self:stats(shadow)
      local msg =
         string.format("%d of %d hash buckets in use, %d MAC entries, "
                          .."target size %d, Max/Avg/Std-dev slots per bucket:"
                          .." %d/%1.2f/%1.2f, size/bucket overflow: %s/%s",
                       info.ubuckets, info.buckets, info.entries,
                       info.size, max, avg, std_dev,
                       info.entries > info.size, self:overflow_p())
      self._logger:log(msg)
   end
   if self:maybe_resize() and not self._config.copy_on_resize then
      -- Resized tables have been cleared, no need to switch
      return
   end
   local new_shadow = self._tables.main
   self:clear(new_shadow)
   self._tables.main = self._tables.shadow
   self._tables.shadow = new_shadow
   self._tables_C[0] = ffi.cast("hash_table_t *", self._tables.main)
   self._tables_C[1] = ffi.cast("hash_table_t *", self._tables.shadow)
end

function mac_table:new (config)
   local config = config or {}
   for k, v in pairs(default_config) do
      if config[k] == nil then
         config[k] = v
      end
   end
   local o = mac_table:superClass().new(self)
   o._config = config
   local size = config.size
   assert(type(size) == 'number' and size > 0)
   size = math.min(size, config.resize_max)
   o._size = size
   o._buckets = buckets_from_size(size)
   o._mask = ffi.new("uint64_t[1]")
   o._mask[0] = o._buckets-1
   o._hash = murmur.MurmurHash3_x64_128:new()
   o._tables = {}
   -- Used to pass pointers to the main and shadow table to
   -- C.mac_table_insert()
   o._tables_C = ffi.new("hash_table_t *[2]")
   alloc_tables(o, o._buckets)
   o._logger = logger.new({ module = "mac_table" })
   timer.activate(
      timer.new("mac_table_timeout",
                function (t)
                   timeout(o)
                end,
                config.timeout*1e9,
                'repeating'))
   return o
end

-- Convert a 6-byte MAC address stored at the given location in
-- network-byte order to a 64-bit number.  The inverse is performed by
-- the iterator() method.
local function mac2u64 (mem)
   local mask
   if ffi.abi("le") then
      mask = 0xFFFFFFFFFFFFULL
   else
      mask = 0xFFFFFFFFFFFF0000ULL
   end
   return band(ffi.cast("uint64_t*", mem[0])[0], mask)
end

-- API
--
-- Insert the MAC address stored at the location pointed to by mem[0]
-- in network byte order in the main and shadow table and associtate
-- the port <port>and split-horizon group <group> with it. mem must be
-- of type uint8_t *[1].
function mac_table:insert (mem, port, group)
   local h = self._hash:hash(mem[0], 6, 0ULL)
   local index = band(h.u64[0], self._mask[0])
   C.mac_table_insert(mac2u64(mem), port, group, self._tables_C, index)
end

-- API
--
-- Look up the MAC address stored at the location pointed to by mem[0]
-- in network byte order in the main table and return the handles of
-- the port and split-horizon group associated with it or nil if the
-- address was not found in the table. mem must be of type uint8_t *[1].
function mac_table:lookup (mem)
   local h = self._hash:hash(mem[0], 6, 0ULL)
   local index = band(h.u64[0], self._mask[0])
   local bucket = ffi.cast("mac_entry_t*", self._tables_C[0].buckets[index])
   local result = C.mac_table_lookup(mac2u64(mem), bucket)
   if result.port == 0 then
      return nil, nil
   else
      return result.port, result.group
   end
end

-- API
--
-- Look up the MAC address stored at the location pointed to by mem[0]
-- in network byte order in the main table and add the packet p to one
-- of the packet forwarding tables from the array pft_C according to
-- the result of the lookup:
--
--   Match
--
--     If the egress port is the same as the ingress port or the
--     ingress port belongs to the same split-horizon group as the
--     egress port, the packet is added to the "discard" table.
--
--     Otherwise, the packet is added to the unicast forwarding table
--     with the egress port set to the result of the lookup
--
--   Miss
--
--     The packet is added to the flooding forwarding list with its
--     egress port list set to flood_pl
--
-- mem must be of type uint8_t *[1].
function mac_table:lookup_pft (mem, port, group, p, pft_C, flood_pl)
   local h = self._hash:hash(mem[0], 6, 0ULL)
   local index = band(h.u64[0], self._mask[0])
   local bucket = ffi.cast("mac_entry_t*", self._tables_C[0].buckets[index])
   C.mac_table_lookup_pft(mac2u64(mem), bucket, port, group,
                          p, pft_C, flood_pl)
end

-- API
--
-- Dynamically resize the main and shadow tables if the main table is
-- full.  This condition is met if the main table is in the overflow
-- state (i.e. at least one address could not be inserted due to a
-- full hash bucket in the past timeout interval) or the number of
-- entries exceeds the target size.
--
-- The new target size is determined by doubling the current size
-- until the associated hash table size (the number of buckets in the
-- table) is at least doubled and the new size is larger than the
-- current number of entries in the table.  However, the new target
-- size is bounded by the "resize_max" configuration variable.
--
-- The main and shadow tables are replaced with instances of the new
-- size.  If the configuration variable "copy_on_resize" is a true
-- value, the contents of the old shadow table is inserted in the new
-- tables to avoid re-learning of all active addresses.
--
-- The method returns true if the tables have been resized, false
-- otherwise.
do
   local box = ffi.new("uint8_t *[1]")

   function mac_table:maybe_resize ()
      -- Only check the main table, which will always overflow first
      local info = self:info()
      if not (self:overflow_p() or info.entries > info.size) then
         return false
      end
      local max = self._config.resize_max
      -- This allows us to traverse the old shadow table later on even
      -- after it has been replaced.
      local next, state = self:iterator(self:table('shadow'))
      local new_buckets = self._buckets
      while (new_buckets < 2*self._buckets
             or info.entries > self._size) and self._size < max do
         self._size = self._size*2
         if self._size > max then
            self._size = max
         end
         new_buckets = buckets_from_size(self._size)
      end
      if new_buckets == self._buckets then
         local msg =
            string.format("can't grow table beyond resize limit %d "
                             .."(size/bucket overflow: %s/%s)",
                          max, info.entries > info.size,
                          self:overflow_p())
         self._logger:log(msg)
         return false
      end
      local msg =
         string.format("resizing from %d to %d hash buckets, "
                          .."new target size %d "
                          .."(%d MAC entries, old target size %d"
                          ..", size/bucket overflow: %s/%s)",
                       self._buckets, new_buckets, self._size,
                       info.entries, info.size,
                       info.entries > info.size, self:overflow_p())
      self._logger:log(msg)
      self._buckets = new_buckets
      self._mask[0] = new_buckets-1
      alloc_tables(self, new_buckets)
      if self._config.copy_on_resize then
         for mac, port, group in next, state do
            box[0] = mac
            self:insert(box, port, group)
         end
      end
      return true
   end
end

-- API
--
-- Return the table of the given name or 'main' by default.  The
-- result can be used as input to all instance methods that operate on
-- either the main or shadow tables.  It must be treated as an opaque
-- object by the caller.
function mac_table:table (name)
   local name = name or 'main'
   assert(name == 'main' or name == 'shadow')
   return self._tables[name]
end

-- API
--
-- Initilize the given table or the main table by default by setting
-- all header fields and all hash buckets to zero.
function mac_table:clear (t)
   local t = t or self._tables[main]
   ffi.fill(t, ffi.sizeof(t))
end

-- API
--
-- Return the predicate whether the given table or the main table by
-- default has experienced an overflow.
function mac_table:overflow_p (t)
   local t = t or self._tables.main
   return t.h.overflow == 1
end

-- API
--
-- Return a table that contains information common to the main and
-- shadow tables as well as specific information for either the main
-- or shadow table (default main).
--
-- Generic information
--
--  size     The targeted maximum number of entries that the tables
--           should be able to hold.  The maybe_resize() method
--           performs a resize if entries > size.
--  buckets  The number of hash buckets in each table.  It is guaranteed to
--           be a power of 2.
--  mask     The hash mask used to select a bucket from the hash value of a
--           MAC address.  This value is always equal to buckets-1.
--
-- Table-specific information
--
--  ubuckets The number of hash buckets with at least one used slot
--  entries  The total number of MAC addresses stored in the table
--  load     The load-factor of the table given by ubuckets/buckets
function mac_table:info (t)
   local t = t or self._tables.main
   local info = {
      size = self._size,
      buckets = self._buckets,
      mask = tonumber(self._mask[0]),
      ubuckets = t.h.ubuckets,
      entries = t.h.entries,
      load = t.h.ubuckets/self._buckets,
   }
   return info
end

-- API
--
-- Return the maximum and average slot usage as well as the standard
-- deviation of the latter of all non-empty hash buckets in the given
-- table or the main table by default.
do
   local data = {}
   function mac_table:stats (t)
      local t = t or self._tables.main
      local max, sum, n = 0, 0, 0
      for i = 0, self._buckets-1 do
         local bucket = t.buckets[i]
         local slots = 0
         for j = 0, bucket_size-1 do
            if bucket[j].mac == 0ULL then
               break
            end
            slots = slots + 1
         end
         if slots > 0 then
            n = n + 1
            data[n] = slots
            sum = sum + slots
            max = math.max(max, slots)
         end
      end
      local avg = sum/t.h.ubuckets
      local std_dev = 0
      for i = 1, n do
         std_dev = std_dev + (avg - data[i])^2
      end
      std_dev = math.sqrt(std_dev/t.h.ubuckets)
      return max, avg, std_dev
   end
end

-- API
--
-- Return an iterator function and associated invariant state for the
-- given table or the main table by default.  The iterator function
-- returns the next MAC address as a pointer to an array of 6 unsigned
-- bytes in network byte order and the handles for the port and
-- split-horizon group of the port on which it has been learned.
--
-- The storage used for the address is reused by each call of the
-- iterator function.  The invariant state is stored in a dynamically
-- allocated table.  It has a method reset() associated with it,
-- which, resets the state to its initial value.
--
-- Example usage:
--
--  local ethernet = require("lib.protocol.ethernet")
--  for mac, port, group in mac_table:iterator() do
--    print(ethernet:ntop(mac), port, group)
--  end
--  local next, state = mac_table:iterator()
--  for mac in next, state do
--    print(ethernet:ntop(mac))
--  end
--  state:reset()
--  for mac in next, state do
--    print(ethernet:ntop(mac))
--  end
--
-- The iterator() method is not suited to be called from a
-- packet-processing loop.
do
   local mac_conv = ffi.new[[
     union {
       uint64_t u64;
       uint8_t mac[6];
       uint8_t pad[2];
     }]]
   local function next (s)
      local mac, port, group = 0ULL
      while mac == 0ULL do
         if s.index == s.buckets then
            return nil
         end
         local entry = s.t.buckets[s.index][s.slot]
         mac, port, group = entry.mac, entry.port, entry.group
         if s.slot == bucket_size-1 or mac == 0ULL then
            s.index = s.index+1
            s.slot = 0
         else
            s.slot = s.slot+1
         end
      end
      mac_conv.u64 = mac
      return mac_conv.mac, port, group
   end

   local mt = { __index = {
                   reset = function (s)
                      s.index = 0
                      s.slot = 0
              end } }

   function mac_table:iterator (t)
      local t = t or self._tables.main
      local state = setmetatable(
         { t = t,
           buckets = self._buckets,
           index = 0,
           slot = 0 }, mt)
      return next, state
   end
end

function selftest ()
   local ethernet = require("lib.protocol.ethernet")
   local mac = ffi.new[[
     union {
       uint64_t u64;
       uint8_t mac[6];
       uint8_t pad[2];
     }]]
   local box = ffi.new("uint8_t *[1]")
   box[0] = mac.mac

   local function check (s)
      local t = mac_table:new({ size = s })
      local info = t:info()
      assert(info.size == s)
      assert(info.mask == info.buckets-1)
      local macs = {}
      local n = 0
      while true do
         mac.u64 = math.random(2^48)
         t:insert(box, 1, 0)
         if not t:overflow_p() then
            assert(t:lookup(box))
            local k = ethernet:ntop(mac.mac)
            if not macs[k] then
               macs[k] = true
               n = n + 1
            end
         else
            break
         end
      end
      local i = 0
      for mac in t:iterator() do
         i = i+1
         assert(macs[ethernet:ntop(mac)])
      end
      assert(i == n)
   end

   for s = 1, 500 do
      check(s)
   end

   local t = mac_table:new()
   while not t:overflow_p() do
      mac.u64 = math.random(2^48)
      t:insert(box, 0, 0)
   end
   local info = t:info()
   local next, state = t:iterator()
   assert(t:maybe_resize())
   assert(not t:overflow_p())
   assert(t:info().entries == info.entries)
   -- Check whether the entries in the old table have been copied to
   -- the resized table.
   local macs = {}
   for mac in next, state do
      macs[ethernet:ntop(mac)] = true
   end
   for mac in t:iterator() do
      assert(macs[ethernet:ntop(mac)])
   end
end

mac_table.selftest = selftest

return mac_table

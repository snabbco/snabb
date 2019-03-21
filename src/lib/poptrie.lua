-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local debug = false

-- Poptrie, see
--   http://conferences.sigcomm.org/sigcomm/2015/pdf/papers/p57.pdf

local ffi = require("ffi")
local bit = require("bit")
local band, bor, lshift, rshift, bnot =
   bit.band, bit.bor, bit.lshift, bit.rshift, bit.bnot

local poptrie_lookup = require("lib.poptrie_lookup")

local Poptrie = {
   leaf_compression = true,
   direct_pointing = false,
   k = 6,
   s = 18,
   leaf_tag = lshift(1, 31),
   leaf_t = ffi.typeof("uint16_t"),
   vector_t = ffi.typeof("uint64_t"),
   base_t = ffi.typeof("uint32_t"),
   num_leaves = 100,
   num_nodes = 10
}
Poptrie.node_t = ffi.typeof([[struct {
   $ leafvec, vector;
   $ base0, base1;
} __attribute__((packed))]], Poptrie.vector_t, Poptrie.base_t)

local function array (t, n)
   return ffi.new(ffi.typeof("$[?]", t), n)
end

function new (init)
   local self = setmetatable({}, {__index=Poptrie})
   if init.leaves and init.nodes then
      self.leaves, self.num_leaves = init.leaves, assert(init.num_leaves)
      self.nodes, self.num_nodes = init.nodes, assert(init.num_nodes)
   elseif init.nodes or init.leaves or init.directmap then
      error("partial init")
   else
      self.leaves = array(Poptrie.leaf_t, Poptrie.num_leaves)
      self.nodes = array(Poptrie.node_t, Poptrie.num_nodes)
   end
   if init.directmap then
      self.directmap = init.directmap
      self.direct_pointing = true
   else
      if init.direct_pointing ~= nil then
         self.direct_pointing = init.direct_pointing
      end
      if init.s ~= nil then
         self.s = init.s
      end
      if self.direct_pointing then
         self.directmap = array(Poptrie.base_t, 2^self.s)
      end
   end
   self:configure_lookup()
   return self
end

local asm_cache = {}

function Poptrie:configure_lookup ()
   local config = ("leaf_compression=%s,direct_pointing=%s,s=%s")
      :format(self.leaf_compression, self.direct_pointing, self.s)
   if not asm_cache[config] then
      asm_cache[config] = {
         poptrie_lookup.generate(self, 32),
         poptrie_lookup.generate(self, 64),
         poptrie_lookup.generate(self, 128)
      }
   end
   self.asm_lookup32, self.asm_lookup64, self.asm_lookup128 =
      unpack(asm_cache[config])
end

function Poptrie:grow_nodes ()
   self.num_nodes = self.num_nodes * 2
   local new_nodes = array(Poptrie.node_t, self.num_nodes)
   ffi.copy(new_nodes, self.nodes, ffi.sizeof(self.nodes))
   self.nodes = new_nodes
end

function Poptrie:grow_leaves ()
   self.num_leaves = self.num_leaves * 2
   local new_leaves = array(Poptrie.leaf_t, self.num_leaves)
   ffi.copy(new_leaves, self.leaves, ffi.sizeof(self.leaves))
   self.leaves = new_leaves
end

-- Extract bits at offset
-- key=uint8_t[?]
function extract (key, offset, length)
   local bits, read = 0, 0
   local byte = math.floor(offset/8)
   while read < length do
      offset = math.max(offset - byte*8, 0)
      local nbits = math.min(length - read, 8 - offset)
      local x = band(rshift(key[byte], offset), lshift(1, nbits) - 1)
      bits = bor(bits, lshift(x, read))
      read = read + nbits
      byte = math.min(byte + 1, ffi.sizeof(key) - 1)
   end
   return bits
end

-- Add key/value pair to RIB (intermediary binary trie)
-- key=uint8_t[?], length=uint16_t, value=uint16_t
function Poptrie:add (key, length, value)
   assert(value)
   local function add (node, offset)
      if offset == length then
         node.value = value
      elseif extract(key, offset, 1) == 0 then
         node.left = add(node.left or {}, offset + 1)
      elseif extract(key, offset, 1) == 1 then
         node.right = add(node.right or {}, offset + 1)
      else error("invalid state") end
      return node
   end
   self.rib = add(self.rib or {}, 0)
end

-- Longest prefix match on RIB
function Poptrie:rib_lookup (key, length, root)
   local function lookup (node, offset, value)
      value = node.value or value
      if offset == length then
         return value, (node.left or node.right) and node
      elseif node.left and extract(key, offset, 1) == 0 then
         return lookup(node.left, offset + 1, value)
      elseif node.right and extract(key, offset, 1) == 1 then
         return lookup(node.right, offset + 1, value)
      else
         -- No match: return longest prefix key value, but no node.
         return value
      end
   end
   return lookup(root or self.rib, 0)
end

-- Map f over keys of length in RIB
function Poptrie:rib_map (f, length, root)
   local function map (node, offset, key, value)
      value = (node and node.value) or value
      local left, right = node and node.left, node and node.right
      if offset == length then
         f(key, value, (left or right) and node)
      else
         map(left, offset + 1, key, value)
         map(right, offset + 1, bor(key, lshift(1, offset)), value)
      end
   end
   return map(root or self.rib, 0, 0)
end

function Poptrie:clear_fib ()
   self.leaf_base, self.node_base = 0, 0
   ffi.fill(self.leaves, ffi.sizeof(self.leaves), 0)
   ffi.fill(self.nodes,  ffi.sizeof(self.nodes),  0)
end

function Poptrie:allocate_leaf ()
   while self.leaf_base >= self.num_leaves do
      self:grow_leaves()
   end
   self.leaf_base = self.leaf_base + 1
   return self.leaf_base - 1
end

function Poptrie:allocate_node ()
   if self.direct_pointing then
      -- When using direct_pointing, the node index space is split into half in
      -- favor of a bit used for disambiguation in Poptrie:build_directmap.
      assert(band(self.node_base, Poptrie.leaf_tag) == 0, "Node overflow")
   end
   while self.node_base >= self.num_nodes do
      self:grow_nodes()
   end
   self.node_base = self.node_base + 1
   return self.node_base - 1
end

function Poptrie:build_node (rib, node_index, default)
   -- Initialize node base pointers.
   do local node = self.nodes[node_index]
      -- Note: have to be careful about keeping direct references of nodes
      -- around as they can get invalidated when the backing array is grown.
      node.base0 = self.leaf_base
      node.base1 = self.node_base
   end
   -- Compute leaves and children
   local leaves, children = {}, {}
   local function collect (key, value, node)
      leaves[key], children[key] = value, node
   end
   self:rib_map(collect, Poptrie.k, rib)
   -- Allocate and initialize node.leafvec and leaves.
   local last_leaf_value = nil
   for index = 0, 2^Poptrie.k - 1 do
      if not children[index] then
         local value = leaves[index] or default or 0
         if value ~= last_leaf_value then -- always true when leaf_compression=false
            if Poptrie.leaf_compression then
               local node = self.nodes[node_index]
               node.leafvec = bor(node.leafvec, lshift(1ULL, index))
               last_leaf_value = value
            end
            local leaf_index = self:allocate_leaf()
            self.leaves[leaf_index] = value
         end
      end
   end
   -- Allocate child nodes (this has to be done before recursing into
   -- build_node() because their indices into the nodes array need to be
   -- node.base1 + index, and build() will advance the node_base.)
   local child_nodes = {}
   for index = 0, 2^Poptrie.k - 1 do
      if children[index] then
         child_nodes[index] = self:allocate_node()
      end
   end
   -- Initialize node.vector and child nodes.
   for index = 0, 2^Poptrie.k - 1 do
      if children[index] then
         local node = self.nodes[node_index]
         node.vector = bor(node.vector, lshift(1ULL, index))
         self:build_node(children[index],
                         child_nodes[index],
                         leaves[index] or default)
      end
   end
end

-- Build direct index array for RIB
function Poptrie:build_directmap (rib)
   local function build (index, value, node)
      if node then
         self.directmap[index] = self:allocate_node()
         self:build_node(node, self.directmap[index], value)
      else
         self.directmap[index] = bor(value or 0, Poptrie.leaf_tag)
      end
   end
   self:rib_map(build, self.s, rib)
end

-- Compress RIB into Poptrie
function Poptrie:build ()
   self:clear_fib()
   if self.direct_pointing then
      self:build_directmap(self.rib)
   else
      self:build_node(self.rib, self:allocate_node())
   end
end

-- http://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetNaive
local function popcnt (v) -- XXX - popcaan is 64-bit only
   local c = 0
   while v > 0 do
      c = c + band(v, 1ULL)
      v = rshift(v, 1ULL)
   end
   return c
end

-- [Algorithm 1] lookup(t = (N , L), key); the lookup procedure for the address
-- key in the tree t (when k = 6). The function extract(key, off, len) extracts
-- bits of length len, starting with the offset off, from the address key.
-- N and L represent arrays of internal nodes and leaves, respectively.
-- << denotes the shift instruction of bits. Numerical literals with the UL and
-- ULL suffixes denote 32-bit and 64-bit unsigned integers, respectively.
-- Vector and base are the variables to hold the contents of the node’s fields.
--
-- if [direct_pointing] then
--    index = extract(key, 0, t.s);
--    dindex = t.D[index].direct index;
--    if (dindex & (1UL << 31)) then
--       return dindex & ((1UL << 31) - 1);
--    end if
--    index = dindex;
--    offset = t.s;
-- else
--    index = 0;
--    offset = 0;
-- end if
-- vector = t.N [index].vector;
-- v = extract(key, offset, 6);
-- while (vector & (1ULL << v)) do
--    base = t.N [index].base1;
--    bc = popcnt(vector & ((2ULL << v) - 1));
--    index = base + bc - 1;
--    vector = t.N [index].vector;
--    offset += 6;
--    v = extract(key, offset, 6);
-- end while
-- base = t.N [index].base0;
-- if [leaf_compression] then
--    bc = popcnt(t.N [index].leafvec & ((2ULL << v) - 1));
-- else
--    bc = popcnt((∼t.N [index].vector) & ((2ULL << v) - 1));
-- end if
-- return t.L[base + bc - 1];
--
function Poptrie:lookup (key)
   local N, L, D = self.nodes, self.leaves, self.directmap
   local index, offset = 0, 0
   if self.direct_pointing then
      offset = self.s
      index = D[extract(key, 0, offset)]
      if debug then print(bin(index), band(index, Poptrie.leaf_tag - 1)) end
      if band(index, Poptrie.leaf_tag) ~= 0 then
         return band(index, Poptrie.leaf_tag - 1) -- direct leaf, strip tag
      end
   end
   local node = N[index]
   local v = extract(key, offset, Poptrie.k)
   if debug then print(index, bin(node.vector), bin(v)) end
   while band(node.vector, lshift(1ULL, v)) ~= 0 do
      local base = N[index].base1
      local bc = popcnt(band(node.vector, lshift(2ULL, v) - 1))
      index = base + bc - 1
      node = N[index]
      offset = offset + Poptrie.k
      v = extract(key, offset, Poptrie.k)
      if debug then print(index, bin(node.vector), bin(v)) end
   end
   if debug then print(node.base0, bin(node.leafvec), bin(v)) end
   local base = node.base0
   local bc
   if Poptrie.leaf_compression then
      bc = popcnt(band(node.leafvec, lshift(2ULL, v) - 1))
   else
      bc = popcnt(band(bnot(node.vector), lshift(2ULL, v) - 1))
   end
   if debug then print(base + bc - 1) end
   return L[base + bc - 1]
end

function Poptrie:lookup32 (key)
   return self.asm_lookup32(self.leaves, self.nodes, key, self.directmap)
end
function Poptrie:lookup64 (key)
   return self.asm_lookup64(self.leaves, self.nodes, key, self.directmap)
end
function Poptrie:lookup128 (key)
   return self.asm_lookup128(self.leaves, self.nodes, key, self.directmap)
end

function Poptrie:fib_info ()
   for i=0, self.node_base-1 do
      print("node:", i)
      print(self.nodes[i].base0, bin(self.nodes[i].leafvec))
      print(self.nodes[i].base1, bin(self.nodes[i].vector))
   end
   for i=0, self.leaf_base-1 do
      if self.leaves[i] > 0 then
         print("leaf:", i, self.leaves[i])
      end
   end
end

function selftest ()
   local function s (...)
      local pf = ffi.new("uint8_t[16]")
      for i, b in ipairs{...} do pf[i-1] = b end
      return pf
   end
   local function rs ()
      local bs = {}
      for i = 1, 16 do bs[i] = math.random(256) - 1 end
      return s(unpack(bs))
   end
   -- To test direct pointing: direct_pointing = true
   local t = new{}
   -- Tets building empty RIB
   t:build()
   -- Test RIB
   t:add(s(0x00), 8, 1) -- 00000000
   t:add(s(0x0F), 8, 2) -- 00001111
   t:add(s(0x07), 4, 3) --     0111
   t:add(s(0xFF), 8, 4) -- 11111111
   t:add(s(0xFF), 5, 5) --    11111
   -- 111111111111111111111111111111111111111111111111111111111111111111110000
   t:add(s(0xF0,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x0F), 72, 6)
   local v, n = t:rib_lookup(s(0x0), 1)
   assert(not v and n.left and not n.right)
   local v, n = t:rib_lookup(s(0x00), 8)
   assert(v == 1 and not n)
   local v, n = t:rib_lookup(s(0x07), 3)
   assert(not v and (n.left and n.right))
   local v, n = t:rib_lookup(s(0x0), 1, n)
   assert(v == 3 and not n)
   local v, n = t:rib_lookup(s(0xFF), 5)
   assert(v == 5 and (not n.left) and n.right)
   local v, n = t:rib_lookup(s(0x0F), 3, n)
   assert(v == 4 and not n)
   local v, n = t:rib_lookup(s(0x3F), 8)
   assert(v == 5 and not n)
   local v, n = t:rib_lookup(s(0xF0,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x0F), 72)
   assert(v == 6 and not n)
   -- Test FIB
   t:build()
   if debug then t:fib_info() end
   assert(t:lookup(s(0x00)) == 1) -- 00000000
   assert(t:lookup(s(0x03)) == 0) -- 00000011
   assert(t:lookup(s(0x07)) == 3) -- 00000111
   assert(t:lookup(s(0x0F)) == 2) -- 00001111
   assert(t:lookup(s(0x1F)) == 5) -- 00011111
   assert(t:lookup(s(0x3F)) == 5) -- 00111111
   assert(t:lookup(s(0xFF)) == 4) -- 11111111
   assert(t:lookup(s(0xF0,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x0F)) == 6)
   assert(t:lookup32(s(0x00)) == 1)
   assert(t:lookup32(s(0x03)) == 0)
   assert(t:lookup32(s(0x07)) == 3)
   assert(t:lookup32(s(0x0F)) == 2)
   assert(t:lookup32(s(0x1F)) == 5)
   assert(t:lookup32(s(0x3F)) == 5)
   assert(t:lookup32(s(0xFF)) == 4)
   assert(t:lookup64(s(0x00)) == 1)
   assert(t:lookup64(s(0x03)) == 0)
   assert(t:lookup64(s(0x07)) == 3)
   assert(t:lookup64(s(0x0F)) == 2)
   assert(t:lookup64(s(0x1F)) == 5)
   assert(t:lookup64(s(0x3F)) == 5)
   assert(t:lookup64(s(0xFF)) == 4)
   assert(t:lookup128(s(0x00)) == 1)
   assert(t:lookup128(s(0x03)) == 0)
   assert(t:lookup128(s(0x07)) == 3)
   assert(t:lookup128(s(0x0F)) == 2)
   assert(t:lookup128(s(0x1F)) == 5)
   assert(t:lookup128(s(0x3F)) == 5)
   assert(t:lookup128(s(0xFF)) == 4)
   assert(t:lookup128(s(0xF0,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x0F)) == 6)

   -- Random testing
   local function reproduce (cases, config)
      debug = true
      print("repoducing...")
      print("config:")
      lib.print_object(config)
      local t = new(config)
      for entry, case in ipairs(cases) do
         local a, l = unpack(case)
         if l <= 64 then
            print("key:", entry, bin(ffi.cast("uint64_t*", a)[0]))
            print("prefix:", entry, bin(ffi.cast("uint64_t*", a)[0], l))
         else
            print("key:", entry, bin(ffi.cast("uint64_t*", a)[0]))
            print("    ", "   ", bin(ffi.cast("uint64_t*", a)[1]))
            print("prefix:", entry, bin(ffi.cast("uint64_t*", a)[0], 64))
            print("    ", "   ", bin(ffi.cast("uint64_t*", a)[1], l-64))
         end
         t:add(case[1], case[2], entry)
      end
      t:build()
      t:fib_info()
      for _, case in ipairs(cases) do
         local a, l = unpack(case)
         print("rib:", t:rib_lookup(a))
         print("fib:", t:lookup(a))
         if l <= 32 then print("32:",  t:lookup32(a))
         elseif l <= 64 then print("64:",  t:lookup64(a))
         else print("128:",  t:lookup128(a)) end
      end
   end
   local function r_assert (condition, cases, config)
      if condition then return end
      reproduce(cases, config)
      print("selftest failed")
      main.exit(1)
   end
   local lib = require("core.lib")
   local seed = lib.getenv("SNABB_RANDOM_SEED") or 0
   for keysize = 1, 128 do
      print("keysize:", keysize)
      -- ramp up the geometry below to crank up test coverage
      for entries = 1, 3 do
         for i = 1, 10 do
            -- add {direct_pointing=true} to test direct pointing
            for _, config in ipairs{ {} } do
               math.randomseed(seed+i)
               cases = {}
               local t = new(config)
               local k = {}
               for entry = 1, entries do
                  local a, l = rs(), math.random(keysize)
                  cases[entry] = {a, l}
                  t:add(a, l, entry)
                  k[entry] = a
               end
               local v = {}
               for entry, a in ipairs(k) do
                  v[entry] = t:rib_lookup(a, keysize)
                  r_assert(v[entry] > 0, cases, config)
               end
               t:build()
               for entry, a in ipairs(k) do
                  r_assert(t:lookup(a) == v[entry], cases)
                  local l = cases[entry][2]
                  if l <= 32 then r_assert(t:lookup32(a) == v[entry], cases)
                  elseif l <= 64 then r_assert(t:lookup64(a) == v[entry], cases)
                  else r_assert(t:lookup128(a) == v[entry], cases) end
               end
            end
         end
      end
   end

   -- PMU analysis
   local pmu = require("lib.pmu")
   local function measure (description, f, iterations)
      local set = pmu.new_counter_set()
      pmu.switch_to(set)
      f(iterations)
      pmu.switch_to(nil)
      local tab = pmu.to_table(set)
      print(("%s: %.2f cycles/lookup %.2f instructions/lookup")
            :format(description,
                    tab.cycles / iterations,
                    tab.instructions / iterations))
   end
   local function time (description, f)
      local start = os.clock(); f()
      print(("%s: %.4f seconds"):format(description, os.clock() - start))
   end
   if pmu.is_available() then
      local t = new{direct_pointing=false}
      local k = {}
      local numentries = tonumber(
         lib.getenv("SNABB_POPTRIE_NUMENTRIES") or 10000
      )
      local numhit = tonumber(
         lib.getenv("SNABB_POPTRIE_NUMHIT") or 100
      )
      local keysize = tonumber(
         lib.getenv("SNABB_POPTRIE_KEYSIZE") or 32
      )
      for entry = 0, numentries - 1 do
         local a, l = rs(), math.random(keysize)
         t:add(a, l, entry)
         k[entry % numhit + 1] = a
      end
      local function build ()
         t:build()
      end
      local function lookup (iter)
         for i=1,iter do t:lookup(k[i%#k+1]) end
      end
      local function lookup32 (iter)
         for i=1,iter do t:lookup32(k[i%#k+1]) end
      end
      local function lookup64 (iter)
         for i=1,iter do t:lookup64(k[i%#k+1]) end
      end
      local function lookup128 (iter)
         for i=1,iter do t:lookup128(k[i%#k+1]) end
      end
      print(("PMU analysis (numentries=%d, numhit=%d, keysize=%d)")
         :format(numentries, numhit, keysize))
      pmu.setup()
      time("build", build)
      measure("lookup", lookup, 1e5)
      if keysize <= 32 then measure("lookup32", lookup32, 1e7) end
      if keysize <= 64 then measure("lookup64", lookup64, 1e7) end
      if keysize <= 128 then measure("lookup128", lookup128, 1e7) end
      do local rib = t.rib
         t = new{direct_pointing=true}
         t.rib = rib
      end
      time("build(direct_pointing)", build)
      measure("lookup(direct_pointing)", lookup, 1e5)
      if keysize <= 32 then measure("lookup32(direct_pointing)", lookup32, 1e7) end
      if keysize <= 64 then measure("lookup64(direct_pointing)", lookup64, 1e7) end
      if keysize <= 128 then measure("lookup128(direct_pointing)", lookup128, 1e7) end
   else
      print("No PMU available.")
   end
end

-- debugging utils
function bin (number, length)
   local digits = {"0", "1"}
   local s = ""
   local i = 0
   repeat
      local remainder = number % 2
      s = digits[tonumber(remainder+1)]..s
      number = (number - remainder) / 2
      i = i + 1
      if i % Poptrie.k == 0 then s = " "..s end
   until number == 0 or (i == length)
   return s
end

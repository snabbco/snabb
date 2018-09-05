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
   k = 6,
   leaf_t = ffi.typeof("uint16_t"),
   vector_t = ffi.typeof("uint64_t"),
   base_t = ffi.typeof("uint32_t")
}
Poptrie.node_t = ffi.typeof([[struct {
   $ leafvec, vector;
   $ base0, base1;
} __attribute__((packed))]], Poptrie.vector_t, Poptrie.base_t)

local function array (t, n)
   return ffi.new(ffi.typeof("$[?]", t), n)
end

function new (init)
   local num_default = 4
   local pt = {
      nodes = init.nodes or array(Poptrie.node_t, num_default),
      num_nodes = (init.nodes and assert(init.num_nodes)) or num_default,
      leaves = init.leaves or array(Poptrie.leaf_t, num_default),
      num_leaves = (init.leaves and assert(init.num_leaves)) or num_default
   }
   return setmetatable(pt, {__index=Poptrie})
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

-- XXX - Generalize for key=uint8_t[?]
local function extract (key, offset, length)
   return band(rshift(key+0ULL, offset), lshift(1ULL, length) - 1)
end

-- Add key/value pair to RIB (intermediary binary trie)
-- key=uint64_t, length=uint16_t, value=uint16_t
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
         return {value=value, left=node.left, right=node.right}
      elseif extract(key, offset, 1) == 0 and node.left then
         return lookup(node.left, offset + 1, value)
      elseif extract(key, offset, 1) == 1 and node.right then
         return lookup(node.right, offset + 1, value)
      else
         -- No match: return longest prefix key value, but no child nodes.
         return {value=value}
      end
   end
   return lookup(root or self.rib, 0)
end

-- Compress RIB into Poptrie
function Poptrie:build (rib, node_index, leaf_base, node_base)
   local function allocate_leaf ()
      while leaf_base >= self.num_leaves do
         self:grow_leaves()
      end
      leaf_base = leaf_base + 1
      return leaf_base - 1
   end
   local function allocate_node ()
      while node_base >= self.num_nodes do
         self:grow_nodes()
      end
      node_base = node_base + 1
      return node_base - 1
   end
   local function node ()
      return self.nodes[node_index]
   end
   -- When called without arguments, create the root node.
   rib = rib or self.rib
   leaf_base = leaf_base or 0
   node_base = node_base or 0
   node_index = node_index or allocate_node()
   -- Initialize node base pointers.
   node().base0 = leaf_base
   node().base1 = node_base
   -- Compute children
   local children = {}
   for index = 0, 2^Poptrie.k - 1 do
      children[index] = self:rib_lookup(index, Poptrie.k, rib)
   end
   -- Allocate and initialize node.leafvec and leaves.
   local last_leaf_value = nil
   for index = 0, 2^Poptrie.k - 1 do
      local child = children[index]
      if not (child.left or child.right) then
         local value = child.value or 0
         if value ~= last_leaf_value then -- always true when leaf_compression=false
            if Poptrie.leaf_compression then
               node().leafvec = bor(node().leafvec, lshift(1ULL, index))
               last_leaf_value = value
            end
            local leaf_index = allocate_leaf()
            self.leaves[leaf_index] = value
         end
      end
   end
   -- Allocate child nodes (this has to be done before recursing into build()
   -- because their indices into the nodes array need to be node.base1 + index,
   -- and build() will advance the node_base.)
   local child_nodes = {}
   for index = 0, 2^Poptrie.k - 1 do
      local child = children[index]
      if child.left or child.right then
         child_nodes[index] = allocate_node()
      end
   end
   -- Initialize node.vector and child nodes.
   for index = 0, 2^Poptrie.k - 1 do
      local child = children[index]
      if child.left or child.right then
         node().vector = bor(node().vector, lshift(1ULL, index))
         leaf_base, node_base =
            self:build(child, child_nodes[index], leaf_base, node_base)
      end
   end
   -- Return new leaf_base and node_base indices.
   return leaf_base, node_base
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
   local N, L = self.nodes, self.leaves
   local index = 0
   local node = N[index]
   local offset = 0
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

Poptrie.asm_lookup64 = poptrie_lookup.generate(Poptrie, 64)
function Poptrie:lookup64 (key)
   return Poptrie.asm_lookup64(self.leaves, self.nodes, key)
end

function selftest ()
   local t = new{}
   -- Test RIB
   t:add(0x00, 8, 1) -- 00000000
   t:add(0x0F, 8, 2) -- 00001111
   t:add(0x07, 4, 3) --     0111
   t:add(0xFF, 8, 4) -- 11111111
   t:add(0xFF, 5, 5) --    11111
   local n = t:rib_lookup(0x0, 1)
   assert(not n.value and n.left and not n.right)
   local n = t:rib_lookup(0x00, 8)
   assert(n.value == 1 and not (n.left or n.right))
   local n = t:rib_lookup(0x07, 3)
   assert(not n.value and (n.left and n.right))
   local n = t:rib_lookup(0x0, 1, n)
   assert(n.value == 3 and not (n.left or n.right))
   local n = t:rib_lookup(0xFF, 5)
   assert(n.value == 5 and (not n.left) and n.right)
   local n = t:rib_lookup(0x0F, 3, n)
   assert(n.value == 4 and not (n.left or n.right))
   local n = t:rib_lookup(0x3F, 8)
   assert(n.value == 5 and not (n.left or n.right))
   -- Test FIB
   local leaf_base, node_base = t:build()
   if debug then
      for i=0, node_base-1 do
         print("node:", i)
         print(t.nodes[i].base0, bin(t.nodes[i].leafvec))
         print(t.nodes[i].base1, bin(t.nodes[i].vector))
      end
      for i=0, leaf_base-1 do
         print("leaf:", i, t.leaves[i])
      end
   end
   assert(t:lookup(0x00) == 1) -- 00000000
   assert(t:lookup(0x03) == 0) -- 00000011
   assert(t:lookup(0x07) == 3) -- 00000111
   assert(t:lookup(0x0F) == 2) -- 00001111
   assert(t:lookup(0x1F) == 5) -- 00011111
   assert(t:lookup(0x3F) == 5) -- 00111111
   assert(t:lookup(0xFF) == 4) -- 11111111
   assert(t:lookup64(0x00) == 1)
   assert(t:lookup64(0x03) == 0)
   assert(t:lookup64(0x07) == 3)
   assert(t:lookup64(0x0F) == 2)
   assert(t:lookup64(0x1F) == 5)
   assert(t:lookup64(0x3F) == 5)
   assert(t:lookup64(0xFF) == 4)

   -- Random testing
   local function reproduce (cases)
      debug = true
      print("repoducing...")
      local t = new{}
      for entry, case in ipairs(cases) do
         print("key:", entry, bin(case[1]))
         print("prefix:", entry, bin(case[1], case[2]))
         t:add(case[1], case[2], entry)
      end
      local leaf_base, node_base = t:build()
      for i=0, node_base-1 do
         print("node:", i)
         print(t.nodes[i].base0, bin(t.nodes[i].leafvec))
         print(t.nodes[i].base1, bin(t.nodes[i].vector))
      end
      for i=0, leaf_base-1 do
         if t.leaves[i] > 0 then print("leaf:", i, t.leaves[i]) end
      end
      for _, case in ipairs(cases) do
         print("rib:", t:rib_lookup(case[1]).value)
         print("fib:", t:lookup(case[1]))
         print("64:",  t:lookup64(case[1]))
      end
   end
   local function r_assert (condition, cases)
      if condition then return end
      reproduce(cases)
      print("selftest failed")
      main.exit(1)
   end
   local lib = require("core.lib")
   local seed = lib.getenv("SNABB_RANDOM_SEED") or 0
   for keysize = 1, 64 do
      print("keysize:", keysize)
      -- ramp up the geometry below to crank up test coverage
      for entries = 1, 8 do
         for i = 1, 4 do
            math.randomseed(seed+i)
            cases = {}
            local t = new{}
            local k = {}
            for entry= 1, entries do
               local a, l = math.random(2^keysize - 1), math.random(keysize)
               cases[entry] = {a, l}
               t:add(a, l, entry)
               k[entry] = a
            end
            local v = {}
            for entry, a in ipairs(k) do
               v[entry] = t:rib_lookup(a, keysize).value
               r_assert(v[entry] > 0, cases)
            end
            t:build()
            for entry, a in ipairs(k) do
               r_assert(t:lookup(a) == v[entry], cases)
               r_assert(t:lookup64(a) == v[entry], cases)
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
   if pmu.is_available() then
      local t = new{}
      local k = {}
      local numentries = 10000
      local keysize = 64
      for entry = 1, numentries do
         local a, l = math.random(2^keysize - 1), math.random(keysize)
         t:add(a, l, entry)
         k[entry] = a
      end
      t:build()
      print("PMU analysis (numentries="..numentries..", keysize="..keysize..")")
      pmu.setup()
      measure("lookup",
              function (iter)
                 for i=1,iter do t:lookup(k[i%#k+1]) end
              end,
              1e5)
      measure("lookup64",
              function (iter)
                 for i=1,iter do t:lookup64(k[i%#k+1]) end
              end,
              1e7)
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

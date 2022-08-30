-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local murmur = require("lib.hash.murmur")
local ffi = require("ffi")
local band, bor, bnot, lshift, rshift =
   bit.band, bit.bor, bit.bnot, bit.lshift, bit.rshift
local min, max =
   math.min, math.max

local Heap = {
   line_size = 128,
   block_lines = 64,
   block_size = 64*128, -- 8KB
}

-- NB: `a' must be a power of two
local function pad (a, l) return band(-l, a-1) end
local function padded (a, l) return l + pad(a, l) end

local block_t = ffi.typeof(([[
   struct {
      uint8_t ref[%d];
      uint8_t mem[%d];
   }
]]):format(Heap.block_lines, Heap.block_size))

function Heap:new ()
   local heap = {
      _blocks = {
         [0] = ffi.new(block_t)
      },
      _free = 0, _maxfree = Heap.block_size,
      _recycle = nil, _maxrecycle = nil,
      _overflow = nil, _maxoverflow = nil
   }
   return setmetatable(heap, {__index=Heap})
end

local _block_pow = 13
assert(Heap.block_size == lshift(1,_block_pow))

function Heap:_block (o)
   local block = rshift(o, _block_pow)
   local offset = band(o, lshift(1, _block_pow)-1)
   return block, offset
end

function Heap:_bump_alloc (bytes)
   local o, new_free = self._free, self._free + bytes
   if new_free <= self._maxfree then
      self._free = new_free
      return o
   end
end

local _line_pow = 7
assert(Heap.line_size == lshift(1, _line_pow))

function Heap:_ref (o, bytes, c)
   local block, offset = self:_block(o)
   local b = self._blocks[block]
   while bytes > 0 do
      local ref = rshift(offset, _line_pow)
      b.ref[ref] = b.ref[ref] + c
      local lbytes = Heap.line_size-pad(Heap.line_size, offset)
      local rbytes = math.min(bytes, lbytes)
      offset = offset + rbytes
      bytes = bytes - rbytes
   end
end

function Heap:_has_ref (l)
   local block, offset = self:_block(l)
   local b = self._blocks[block]
   local ref = rshift(offset, _line_pow)
   return b.ref[ref] > 0
end

function Heap:_find_hole (recycle)
   local block = self:_block(recycle)
   while recycle < lshift(block+1, _block_pow) do
      if not self:_has_ref(recycle) then
         return recycle
      end
      recycle = recycle + Heap.line_size
   end
end

function Heap:_find_recycle (recycle)
   local hole
   local block = self:_block(recycle)
   while not hole and block <= #self._blocks do
      hole = self:_find_hole(recycle)
      block = block + 1
      recycle = lshift(block, _block_pow)
   end
   if hole then
      return hole, hole + Heap.line_size
   end
end

function Heap:_overflow_alloc (bytes)
   local o, new_overflow = self._overflow, self._overflow + bytes
   if new_overflow <= self._maxoverflow then
      self._overflow = new_overflow
      return o
   end
end

function Heap:_recycle_alloc (bytes)
   if bytes > Heap.line_size then
      return self:_overflow_alloc(bytes)
   end
   local o, new_recycle = self._recycle, self._recycle + bytes
   if new_recycle <= self._maxrecycle then
      self._recycle = new_recycle
      return o
   else
      local next_line = padded(Heap.line_size, self._recycle)
      self._recycle, self._maxrecycle = self:_find_recycle(next_line)
      if self._recycle then
         return self:_recycle_alloc(bytes)
      end
   end
end

function Heap:_new_block ()
   local block = #self._blocks+1
   self._blocks[block] = ffi.new(block_t)
   local o = lshift(block, _block_pow)
   return o, o + Heap.block_size
end

function Heap:_collect ()
   self._recycle, self._maxrecycle = self:_find_recycle(0)
   if self._recycle then
      self._overflow, self._maxoverflow = self:_new_block()
   end
   self._free, self._maxfree = self:_new_block()
end

function Heap:allocate (bytes)
   assert(bytes <= Heap.block_size)
   local o = (self._recycle and self:_recycle_alloc(bytes))
          or self:_bump_alloc(bytes)
   if o then
      self:_ref(o, bytes, 1)
      -- Allocated space is zeroed. We are civilized, after all.
      ffi.fill(self:ptr(o), bytes, 0)
      return o
   else
      self:_collect()
      return self:allocate(bytes)
   end
end

function Heap:free (o, bytes)
   assert(bytes <= Heap.block_size)
   self:_ref(o, bytes, -1)
end

function Heap:ptr (o)
   local block, offset = self:_block(o)
   return self._blocks[block].mem + offset
end

local function selftest_heap ()
   local h = Heap:new()
   local o1 = h:allocate(Heap.line_size/2)
   assert(h:_has_ref(0*Heap.line_size))
   local o2 = h:allocate(Heap.line_size*1)
   assert(h:_has_ref(0*Heap.line_size))
   assert(h:_has_ref(1*Heap.line_size))
   h:free(o2, Heap.line_size*1)
   assert(h:_has_ref(0*Heap.line_size))
   assert(not h:_has_ref(1*Heap.line_size))
   h:free(o1, Heap.line_size/2)
   assert(not h:_has_ref(0*Heap.line_size))
   local o1 = h:allocate(Heap.block_size)
   local o1_b, o1_o = h:_block(o1)
   assert(o1_b == 1 and o1_o == 0)
   assert(#h._blocks == 2)
   assert(h._recycle == 0)
   assert(h._maxrecycle == Heap.line_size)
   assert(h._overflow == Heap.block_size*2)
   assert(h._maxoverflow == Heap.block_size*2)
   assert(h._free == Heap.block_size*2)
   assert(h._maxfree == Heap.block_size*3)
   local o2 = h:allocate(Heap.line_size/2)
   local o3 = h:allocate(Heap.line_size)
end


List = {
   trie_width = 4,
   hash_width = 32,
   node_entries = 16
}

List.type_map = {
   decimal64 = 'double',
   boolean = 'bool',
   uint16 = 'uint16_t',
   uint32 = 'uint32_t',
   uint64 = 'uint64_t',
   string = 'uint32_t'
}

List.type_cache = {}

function List:cached_type (t)
   if not self.type_cache[t] then
      self.type_cache[t] = ffi.typeof(t)
   end
   return self.type_cache[t]
end

List.node_t = List:cached_type [[
   struct {
      uint16_t occupied, leaf;
      uint32_t children[16];
   }
]]

List.list_ts = [[
   struct {
      uint32_t prev, next;
   }
]]

List.string_t = List:cached_type [[
   struct {
      uint16_t len;
      uint8_t str[1];
   } __attribute__((packed))
]]

function List:new (keys, members)
   local self = setmetatable({}, {__index=List})
   local keys_ts = self:build_type(keys)
   local members_ts = self:build_type(members)
   self.keys = keys
   self.members = members
   self.keys_t = self:cached_type(keys_ts)
   self.leaf_t = self:cached_type(self:build_leaf_type(keys_ts, members_ts))
   self.heap = Heap:new()
   self.first, self.last = nil, nil -- empty
   self.root = self:alloc_node() -- heap obj=0 reserved for root node
   self.hashin = ffi.new(self.keys_t)
   return self
end

function List:build_type (fields)
   local t = "struct { "
   for _, spec in ipairs(fields) do
      t = t..("%s %s; "):format(
         assert(self.type_map[spec[2]], "NYI: "..spec[2]),
         spec[1]
      )
   end
   t = t.."} __attribute__((packed))"
   return t
end

function List:build_leaf_type (keys_ts, members_ts)
   return ("struct { %s list; %s keys; %s members; } __attribute__((packed))")
      :format(self.list_ts, keys_ts, members_ts)
end

local function ptrcast (t, ptr)
   return ffi.cast(ffi.typeof('$*', t), ptr)
end

function List:alloc_node ()
   local o = self.heap:allocate(ffi.sizeof(self.node_t))
   return o
end

function List:free_node (o)
   self.heap:free(o, ffi.sizeof(self.node_t))
end

function List:node (o)
   return ptrcast(self.node_t, self.heap:ptr(o))
end

function List:alloc_leaf ()
   local o = self.heap:allocate(ffi.sizeof(self.leaf_t))
   return o
end

function List:free_leaf (o)
   self.heap:free(o, ffi.sizeof(self.leaf_t))
end

function List:leaf (o)
   return ptrcast(self.leaf_t, self.heap:ptr(o))
end

function List:alloc_str (s)
   local o = self.heap:allocate(ffi.sizeof(self.string_t)+#s-1)
   local str = ptrcast(self.string_t, self.heap:ptr(o))
   ffi.copy(str.str, s, #s)
   str.len = #s
   return o
end

function List:free_str (o)
   local str = ptrcast(self.string_t, self.heap:ptr(o))
   self.heap:free(o, ffi.sizeof(self.string_t)+str.len-1)
end

function List:str (o)
   return ptrcast(self.string_t, self.heap:ptr(o))
end

function List:tostring(str)
   return ffi.string(str.str, str.len)
end

function List:copy_scalar (dst, src, fields)
   for _, spec in ipairs(fields) do
      local name, type = unpack(spec)
      if type ~= 'string' then
         dst[name] = src[name]
      end
   end
end

function List:totable (t, s, fields)
   self:copy_scalar(t, s, fields)
   for _, spec in ipairs(fields) do
      local name, type = unpack(spec)
      if type == 'string' then
         t[name] = self:tostring(self:str(s[name]))
      end
   end
end

function List:tostruct (s, t, fields)
   self:copy_scalar(s, t, fields)
   for _, spec in ipairs(fields) do
      local name, type = unpack(spec)
      if type == 'string' then
         s[name] = self:alloc_str(t[name])
      end
   end
end

local murmur32 = murmur.MurmurHash3_x86_32:new()
local function hash32 (ptr, len, seed)
   return murmur32:hash(ptr, len, seed).u32[0]
end

function List:entry_hash (e, seed)
   self:copy_scalar(self.hashin, e, self.keys)
   for _, spec in ipairs(self.keys) do
      local name, type = unpack(spec)
      if type == 'string' then
         self.hashin[name] = hash32(e[name], #e[name], seed)
      end
   end
   return hash32(self.hashin, ffi.sizeof(self.keys_t), seed)
end

-- Same as entry hash but for keys_t
function List:leaf_hash (keys, seed)
   self:copy_scalar(self.hashin, keys, self.keys)
   for _, spec in ipairs(self.keys) do
      local name, type = unpack(spec)
      if type == 'string' then
         local str = self:str(keys[name])
         self.hashin[name] = hash32(str.str, str.len, seed)
      end
   end
   return hash32(self.hashin, ffi.sizeof(self.keys_t), seed)
end

function List:new_leaf (e, prev, next)
   local o = self:alloc_leaf()
   local leaf = self:leaf(o)
   leaf.list.prev = prev or 0 --  NB: obj=0 is root node, can not be a leaf!
   leaf.list.next = next or 0
   self:tostruct(leaf.keys, e, self.keys)
   self:tostruct(leaf.members, e, self.members)
   return o
end

function List:node_occupied (node, index, newval)
   if newval == true then
      node.occupied = bor(node.occupied, lshift(1, index))
   elseif newval == false then
      node.occupied = bor(node.occupied, bnot(lshift(1, index)))
   end
   return band(1, rshift(node.occupied, index)) == 1
end

function List:node_leaf (node, index, newval)
   if newval == true then
      node.leaf = bor(node.leaf, lshift(1, index))
   elseif newval == false then
      node.leaf = bor(node.leaf, bnot(lshift(1, index)))
   end
   return band(1, rshift(node.leaf, index)) == 1
end

function List:next_hash_parameters (d, s, h)
   if d + 4 < self.hash_width then
      return d + 4, s, h
   else
      return 0, s + 1, nil
   end
end

function List:insert_leaf (o, r, d, s, h)
   r = r or self.root
   d = d or 0
   s = s or 0
   h = h or self:leaf_hash(self:leaf(o).keys, s)
   local node = self:node(r)
   local index = band(self.node_entries-1, rshift(h, d))
   if self:node_occupied(node, index) then
      -- Child slot occupied, advance hash parameters
      d, s, h = self:next_hash_parameters()
      if self:node_leaf(node, index) then
         -- Occupied by leaf, replace with node and insert
         -- both existing and new leaves into new node.
         local l = node.children[index]
         local n = self:alloc_node()
         node.children[index] = n
         self:node_leaf(node, index, false)
         self:insert_leaf(l, n, d, s, nil)
         self:insert_leaf(o, n, d, s, h)
      else
         -- Occupied by node, insert into it.
         self:insert_leaf(o, r, d, s, h)
      end
   else
      -- Not occupied, insert leaf.
      self:node_occupied(node, index, true)
      self:node_leaf(node, index, true)
      node.children[index] = o
   end
end

function List:find_leaf (k, r, d, s, h)
   r = r or self.root
   d = d or 0
   s = s or 0
   h = h or self:entry_hash(k, s)
   local node = self:node(r)
   local index = band(self.node_entries-1, rshift(h, d))
   if self:node_occupied(node, index) then
      if self:node_leaf(node, index) then
         -- Found!
         return node.children[index]
      else
         -- Continue searching in child node.
         d, s, h = self:next_hash_parameters()
         self:find_leaf(k, node.children[index], d, s, h)
      end
   else
      -- Not present!
      return nil
   end
end

function List:append_leaf (o, prev)
   local leaf = self:leaf(o)
   local pleaf = self:leaf(prev)
   leaf.list.prev = prev
   leaf.list.next = pleaf.list.next
   pleaf.list.next = o
end

function List:add_entry (e)
   local o = self:new_leaf(e)
   self:insert_leaf(o)
   if self.last then
      self:append_leaf(o, self.last)
   else
      self.last = o
   end
end

function List:find_entry (k)
   local o = self:find_leaf(k)
   if o then
      local leaf = self:leaf(o)
      local ret = {}
      self:totable(ret, leaf.keys, self.keys)
      self:totable(ret, leaf.members, self.members)
      return ret
   end
end

function selftest_list ()
   local l = List:new(
      {{'id', 'uint32'}, {'name', 'string'}},
      {{'value', 'decimal64'}, {'description', 'string'}}
   )
   print("leaf_t", ffi.sizeof(l.leaf_t))
   print("node_t", ffi.sizeof(l.node_t))
   l:add_entry{
      id=42, name="foobar",
      value=3.14, description="PI"
   }
   local root = l:node(l.root)
   print(l.root, root.occupied, root.leaf, root.children[12])
   local e1 = l:find_entry{
      id=42, name="foobar"
   }
   assert(e1)
   for k,v in pairs(e1) do
      print(k,v)
   end
end


function selftest ()
   print("Selftest: Heap")
   selftest_heap()
   print("Selftest: List")
   selftest_list()
end
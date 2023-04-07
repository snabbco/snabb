-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local typeof = require("lib.yang.ctype").typeof
local murmur = require("lib.hash.murmur")
local lib = require("core.lib")
local ffi = require("ffi")
local C = ffi.C
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

Heap.block_t = ffi.typeof(([[
   struct {
      uint8_t ref[%d];
      uint8_t mem[%d];
   } __attribute__((packed))
]]):format(Heap.block_lines, Heap.block_size))

function Heap:new ()
   local heap = {
      _blocks = {
         [0] = self.block_t()
      },
      _free = 0, _maxfree = Heap.block_size,
      _recycle = nil, _maxrecycle = nil
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
      local next_offset = lshift(ref+1, _line_pow)
      bytes = bytes - (next_offset - offset)
      offset = next_offset
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
   local free_block = self:_block(self._free)
   -- NB: scan only blocks before current free block
   while not hole and block < free_block do
      hole = self:_find_hole(recycle)
      block = block + 1
      recycle = lshift(block, _block_pow)
   end
   if hole then
      return hole, hole + Heap.line_size
   end
end

function Heap:_recycle_alloc (bytes)
   assert(bytes <= Heap.line_size)
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
   self._blocks[block] = self.block_t()
   local o = lshift(block, _block_pow)
   return o, o + Heap.block_size
end

function Heap:_collect ()
   self._free, self._maxfree = self:_new_block()
   self._recycle, self._maxrecycle = self:_find_recycle(0)
end

function Heap:allocate (bytes)
   assert(bytes <= Heap.block_size)
   local o
   if self._recycle and bytes <= Heap.line_size then
      o = self:_recycle_alloc(bytes)
   end
   if not o then
      o = self:_bump_alloc(bytes)
   end
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

Heap.header_t = ffi.typeof[[
   struct {
      uint32_t maxblock;
      double free, maxfree;
      double recycle, maxrecycle;
   } __attribute__((packed))
]]

function Heap:save (stream)
   stream:write_struct(self.header_t, self.header_t(
      #self._blocks,
      self._free, self._maxfree,
      self._recycle or -1, self._maxrecycle or -1
   ))
   for block=0, #self._blocks do
      stream:write_struct(self.block_t, self._blocks[block])
   end
end

function Heap:load (stream)
   local header = stream:read_struct(nil, self.header_t)
   local blocks = {}
   for block=0, header.maxblock do
      blocks[block] = stream:read_struct(nil, self.block_t)
   end
   local heap = {
      _blocks = blocks,
      _free = header.free, _maxfree = header.maxfree,
      _recycle = (header.recycle >= 0 and header.recycle) or nil,
      _maxrecycle = (header.maxrecycle >= 0 and header.maxrecycle) or nil
   }
   return setmetatable(heap, {__index=Heap})
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
   assert(#h._blocks == 1)
   assert(h._recycle == 0)
   assert(h._maxrecycle == Heap.line_size)
   assert(h._free == Heap.block_size*2)
   assert(h._maxfree == Heap.block_size*2)
   local o2 = h:allocate(Heap.line_size/2)
   assert(h._recycle == Heap.line_size/2)
   local o3 = h:allocate(Heap.line_size)
   assert(h._recycle == h._maxrecycle)

   -- Stress
   local h = Heap:new()
   local obj = {}
   math.randomseed(0)
   local function alloc_obj ()
      local size = math.random(10*Heap.line_size)
      local s = ffi.new("char[?]", size)
      for i=0, size-1 do
         s[i] = math.random(127)
      end
      local o = h:allocate(size)
      assert(not obj[o])
      ffi.copy(h:ptr(o), s, size)
      obj[o] = s
      return o
   end
   local function free_obj ()
      for o, s in pairs(obj) do
         if math.random(10) == 1 then
            h:free(o, ffi.sizeof(s))
            obj[o] = nil
         end
      end
   end
   local function check_obj ()
      for o, s in pairs(obj) do
         if C.memcmp(h:ptr(o), s, ffi.sizeof(s)) ~= 0 then
            return o
         end
      end
   end
   for i=1, 100000 do
      local o = alloc_obj()
      local err = check_obj()
      if err then
         error("error after allocation "..i.." ("..o..") in object "..err)
      end
      free_obj()
   end

   -- Test save
   local memstream = require("lib.stream.mem")
   local tmp = memstream.tmpfile()
   h:save(tmp)
   tmp:seek('set', 0)
   h = Heap:load(tmp)
   check_obj()
   tmp:seek('set', 0)
   Heap:new():save(tmp)
   tmp:seek('set', 0)
   local h = Heap:load(tmp)
   assert(h._free == 0)
   assert(h._recycle == nil)
end


local List = {
   trie_width = 4,
   hash_width = 32,
   node_children = 16
}

List.type_map = {
   binary = {ctype='uint32_t', kind='string'}, -- same as string
   empty = {ctype='bool', kind='empty'}, -- no representation (always true)
   enumeration = {ctype='uint32_t', kind='string'}, -- same as string 
   identityref = {ctype='uint32_t', kind='string'}, -- same as string 
   leafref = {ctype='uint32_t', kind='string'}, -- same as string 
   string = {ctype='uint32_t', kind='string'}, -- pointer into heap
   lvalue = {ctype='uint32_t', kind='lvalue'}
}

function List:type_info (type)
   return assert(self.type_map[type], "Unsupported type: "..type)
end

function List:type_kind (spec)
   if spec.ctype then return 'ctype'
   else return self:type_info(spec.type).kind end
end

function List:type_ctype (spec)
   return spec.ctype or self:type_info(spec.type).ctype
end

function validate_keys (keys)
   validate_members(keys)
   for name, key in pairs(keys) do
      assert(not key.optional, "Keys can not be optional")
   end
end

function validate_members (members)
   for name, member in pairs(members) do
      assert(type(member) == 'table' and
             (type(member.type) == 'string' or
              type(member.ctype) == 'string'),
         "Invalid field spec for "..name)
      assert(List:type_kind(member))
   end
end

List.node_t = ffi.typeof [[
   struct {
      uint16_t occupied;
      uint16_t leaf;
      uint32_t parent;
      uint32_t children[16];
   }
]]

List.list_ts = [[
   struct {
      uint32_t prev;
      uint32_t next;
   }
]]

List.string_t = ffi.typeof [[
   struct {
      uint16_t len;
      uint8_t str[1];
   } __attribute__((packed))
]]

List.optional_ts = [[
   struct {
      struct { %s } value;
      bool present;
   } %s;
]]

List.leaf_ts = [[
   struct {
      %s list;
      %s keys;
      %s members;
   }
]]

function List:_new (keys, members)
   local self = setmetatable({}, {__index=List})
   validate_keys(keys)
   validate_members(members)
   local keys_ts = self:build_type(keys)
   local members_ts = self:build_type(members)
   self.keys = keys
   self.members = members
   self.keys_t = typeof(keys_ts)
   self.leaf_t = typeof(self:build_leaf_type(keys_ts, members_ts))
   self.hashin = self.keys_t()
   return self
end

function List:new (keys, members)
   local self = self:_new(keys, members)
   self.heap = Heap:new()
   self.first, self.last = 0, 0 -- empty
   self.root = self:alloc_node() -- heap obj=0 reserved for root node
   self.length = 0
   self.lvalues = {}
   for name, member in pairs(members) do
      if member.type == 'lvalue' then
         self.lvalues[name] = {}
      end
   end
   return self
end

function List:field_order (fields)
   local order = {}
   for name in pairs(fields) do
      table.insert(order, name)
   end
   local function order_fields (x, y)
      -- 1. mandatory fields (< name)
      -- 2. optional fields (< name)
      if (not fields[x].optional) and fields[y].optional then
         return true
      elseif fields[x].optional and (not fields[y].optional) then
         return false
      else
         return x < y
      end
   end
   table.sort(order, order_fields)
   return order
end

function List:build_type (fields)
   local t = "struct { "
   for _, name in ipairs(self:field_order(fields)) do
      local spec = fields[name]
      local ct = self:type_ctype(spec)
      local et, array = ct:match("(.+)(%[%d+%])")
      local f
      if array then
         f = ("%s %s%s;"):format(et, name, array)
      else
         f = ("%s %s;"):format(ct, name)
      end
      if spec.optional then
         f = self.optional_ts:format(f, name)
      end
      t = t..f.." "
   end
   t = t.."}"
   return t
end

function List:build_leaf_type (keys_ts, members_ts)
   return self.leaf_ts:format(self.list_ts, keys_ts, members_ts)
end

function List:heap_cast (t, o)
   return ffi.cast(ffi.typeof('$*', t), self.heap:ptr(o))
end

function List:alloc_node ()
   local o = self.heap:allocate(ffi.sizeof(self.node_t))
   return o
end

function List:free_node (o)
   self.heap:free(o, ffi.sizeof(self.node_t))
end

function List:node (o)
   return self:heap_cast(self.node_t, o)
end

function List:alloc_leaf ()
   local o = self.heap:allocate(ffi.sizeof(self.leaf_t))
   return o
end

function List:free_leaf (o)
   self.heap:free(o, ffi.sizeof(self.leaf_t))
end

function List:leaf (o)
   return self:heap_cast(self.leaf_t, o)
end

function List:alloc_str (s)
   local o = self.heap:allocate(ffi.sizeof(self.string_t)+#s-1)
   local str = self:str(o)
   ffi.copy(str.str, s, #s)
   str.len = #s
   return o
end

function List:free_str (o)
   local str = self:str(o)
   self.heap:free(o, ffi.sizeof(self.string_t)+str.len-1)
end

function List:str (o)
   return self:heap_cast(self.string_t, o)
end

function List:tostring(o)
   local str = self:str(o)
   return ffi.string(str.str, str.len)
end

function List:str_equal_string (o, s)
   local str = self:str(o)
   if not str.len == #s then
      return false
   end
   return C.memcmp(str.str, s, str.len) == 0
end

function List:pack_mandatory (dst, name, kind, value)
   assert(value ~= nil, "Missing value: "..name)
   if kind == 'string' then
      dst[name] = self:alloc_str(value)
   elseif kind == 'empty' then
      dst[name] = true
   elseif kind == 'ctype' then
      dst[name] = value
   elseif kind == 'lvalue' then
      local idx = #self.lvalues[name] + 1
      self.lvalues[name][idx] = assert(value)
      dst[name] = idx
   else
      error("NYI: kind "..kind)
   end
end

function List:unpack_mandatory (dst, name, kind, value)
   if kind == 'string' then
      dst[name] = self:tostring(value)
   elseif kind == 'empty' then
      dst[name] = true
   elseif kind == 'ctype' then
      dst[name] = value
   elseif kind == 'lvalue' then
      dst[name] = assert(self.lvalues[name][value])
   else
      error("NYI: kind "..kind)
   end
end

function List:free_mandatory (name, kind, value)
   if kind == 'string' then
      self:free_str(value)
   elseif kind == 'empty' then
      -- nop
   elseif kind == 'ctype' then
      -- nop
   elseif kind == 'lvalue' then
      self.lvalues[name][value] = nil
   else
      error("NYI: kind "..kind)
   end
end

function List:pack_optional (dst, name, kind, value)
   if value ~= nil then
      self:pack_mandatory(dst[name].value, name, kind, value)
      dst[name].present = true
   else
      dst[name].present = false
   end
end

function List:unpack_optional (dst, name, kind, value)
   if value.present then
      self:unpack_mandatory(dst, name, kind, value.value[name])
   end
end

function List:free_optional (name, kind, value)
   if value.present then
      self:free_mandatory(name, kind, value.value[name])
   end
end

function List:pack_field (dst, name, spec, value)
   local kind = self:type_kind(spec)
   if spec.optional then
      self:pack_optional(dst, name, kind, value)
   else
      self:pack_mandatory(dst, name, kind, value)
   end
end

function List:unpack_field (dst, name, spec, value)
   local kind = self:type_kind(spec)
   if spec.optional then
      self:unpack_optional(dst, name, kind, value)
   else
      self:unpack_mandatory(dst, name, kind, value)
   end
end

function List:free_field (name, spec, value)
   local kind = self:type_kind(spec)
   if spec.optional then
      self:free_optional(name, kind, value)
   else
      self:free_mandatory(name, kind, value)
   end
end

function List:pack_fields (s, t, fields)
   for name, spec in pairs(fields) do
      self:pack_field(s, name, spec, t[name])
   end
end

function List:unpack_fields (t, s, fields)
   for name, spec in pairs(fields) do
      self:unpack_field(t, name, spec, s[name])
   end
end

function List:free_fields (s, fields)
   for name, spec in pairs(fields) do
      self:free_field(name, spec, s[name])
   end
end

local murmur32 = murmur.MurmurHash3_x86_32:new()
local function hash32 (ptr, len, seed)
   return murmur32:hash(ptr, len, seed).u32[0]
end

function List:entry_hash (e, seed)
   for name, spec in pairs(self.keys) do
      local kind = self:type_kind(spec)
      if kind == 'ctype' then
         self:pack_field(self.hashin, name, spec, e[name])
      elseif kind == 'string' then
         self.hashin[name] = hash32(e[name], #e[name], seed)
      elseif kind == 'empty' then
         self:pack_field(self.hashin, name, spec, e[name])
      else
         error("NYI: kind "..kind)
      end
   end
   return hash32(self.hashin, ffi.sizeof(self.keys_t), seed)
end

-- Same as entry hash but for keys_t
function List:leaf_hash (keys, seed)
   for name, spec in pairs(self.keys) do
      local kind = self:type_kind(spec)
      if kind == 'ctype' then
         self:pack_field(self.hashin, name, spec, keys[name])
      elseif kind == 'string' then
         local str = self:str(keys[name])
         self.hashin[name] = hash32(str.str, str.len, seed)
      elseif kind == 'empty' then
         self:pack_field(self.hashin, name, spec, keys[name])
      else
         error("NYI: kind "..kind)
      end
   end
   return hash32(self.hashin, ffi.sizeof(self.keys_t), seed)
end

function List:new_leaf (e, members, prev, next)
   local o = self:alloc_leaf()
   local leaf = self:leaf(o)
   leaf.list.prev = prev or 0 --  NB: obj=0 is root node, can not be a leaf!
   leaf.list.next = next or 0
   self:pack_fields(leaf.keys, e, self.keys)
   self:pack_fields(leaf.members, members or e, self.members)
   return o
end

function List:update_leaf (o, members)
   local leaf = self:leaf(o)
   self:free_fields(leaf.members, self.members)
   self:pack_fields(leaf.members, members, self.members)
end

function List:destroy_leaf (o)
   local leaf = self:leaf(o)
   self:free_fields(leaf.keys, self.keys)
   self:free_fields(leaf.members, self.members)
   self:free_leaf(o)
end

local node_index_mask = List.node_children - 1
function List:node_index (node, d, h)
   return band(node_index_mask, rshift(h, d))
end

function List:node_occupied (node, index, newval)
   if newval == true then
      node.occupied = bor(node.occupied, lshift(1, index))
   elseif newval == false then
      node.occupied = band(node.occupied, bnot(lshift(1, index)))
   end
   return band(node.occupied, lshift(1, index)) > 0
end

function List:node_leaf (node, index, newval)
   if newval == true then
      node.leaf = bor(node.leaf, lshift(1, index))
   elseif newval == false then
      node.leaf = band(node.leaf, bnot(lshift(1, index)))
   end
   return band(node.leaf, lshift(1, index)) > 0
end

function List:next_hash_parameters (d, s, h)
   if d + self.trie_width < self.hash_width then
      return d + self.trie_width, s, h
   else
      return 0, s + 1, nil
   end
end

function List:prev_hash_parameters (d, s, h)
   if d >= self.trie_width then
      return d - self.trie_width, s, h
   else
      return self.hash_width - self.trie_width, s - 1, nil
   end
end

function List:entry_keys_equal (e, o)
   local keys = self:leaf(o).keys
   local cmp = self.hashin
   ffi.fill(cmp, ffi.sizeof(cmp))
   for name, spec in pairs(self.keys) do
      local kind = self:type_kind(spec)
      if kind == 'string' then
         if self:str_equal_string(keys[name], e[name]) then
            cmp[name] = keys[name]
         end
      else
         self:pack_mandatory(cmp, name, kind, e[name])
      end
   end
   return C.memcmp(keys, cmp, ffi.sizeof(keys)) == 0
end

-- NB: finds any node matching the keys hash!
function List:find_node (k, r, d, s, h)
   r = r or self.root
   d = d or 0
   s = s or 0
   h = h or self:entry_hash(k, s)
   local node = self:node(r)
   local index = self:node_index(node, d, h)
   if self:node_occupied(node, index) and
      not self:node_leaf(node, index)
   then
      -- Continue searching in child node.
      d, s, h = self:next_hash_parameters(d, s, h)
      return self:find_node(k, node.children[index], d, s, h)
   else
      -- Found!
      return r, d, s, h
   end
end

-- NB: finds leaf with matching keys in node.
function List:find_leaf (k, n, d, s, h)
   local node = self:node(n)
   local index = self:node_index(node, d, h)
   if self:node_occupied(node, index) then
      assert(self:node_leaf(node, index))
      local o = node.children[index]
      if self:entry_keys_equal(k, o) then
         return o
      end
   end
end

-- NB: does not handle already existing identical keys!
function List:insert_leaf (o, r, d, s, h)
   h = h or self:leaf_hash(self:leaf(o).keys, s)
   local node = self:node(r)
   local index = self:node_index(node, d, h)
   if self:node_occupied(node, index) then
      assert(self:node_leaf(node, index))
      -- Occupied by leaf, replace with node and insert
      -- both existing and new leaves into new node.
      local l = node.children[index]
      local n = self:alloc_node()
      self:node(n).parent = r
      node.children[index] = n
      self:node_leaf(node, index, false)
      d, s, h = self:next_hash_parameters(d, s, h)
      self:insert_leaf(l, n, d, s, nil)
      self:insert_leaf(o, n, d, s, h)
   else
      -- Not occupied, insert leaf.
      self:node_occupied(node, index, true)
      self:node_leaf(node, index, true)
      node.children[index] = o
   end      
end

-- NB: does not handle non-existing keys!
function List:remove_child (k, r, d, s, h)
   local node = self:node(r)
   local index = self:node_index(node, d, h)
   assert(self:node_occupied(node, index))
   assert(self:node_leaf(node, index))
   -- Remove
   self:node_occupied(node, index, false)
   self:node_leaf(node, index, false)
   node.children[index] = 0
   self:remove_obsolete_nodes(k, r, d, s, h)
end

assert(ffi.abi("le"))
local t = ffi.new("union { uint32_t u[2]; double d; }")
local function msb_set (v)
   -- https://graphics.stanford.edu/~seander/bithacks.html#IntegerLogIEEE64Float
   -- "Finding integer log base 2 of an integer
   -- (aka the position of the highest bit set)"
   --
   -- We use this function to find the only bit set. :-)
   t.u[1] = 0x43300000
   t.u[0] = v
   t.d = t.d - 4503599627370496.0
   return rshift(t.u[1], 20) - 0x3FF
end

function List:remove_obsolete_nodes (k, r, d, s, h)
   if r == self.root then
      -- Node is the root, and never obsolete.
      return
   end
   local node = self:node(r)
   local d, s, h = self:prev_hash_parameters(d, s, h)
   h = h or self:entry_hash(k, s)
   local parent = self:node(node.parent)
   local parent_index = self:node_index(parent, d, h)
   if node.occupied == 0 then
      -- Node is now empty, remove from parent.
      error("unreachable")
      -- ^- This case never happens, because we only ever create
      -- new nodes with at least two leaves (the new leaf, and
      -- the displaced leaf).
      parent.children[parent_index] = 0
      self:node_occupied(parent, parent_index, false)
      self:free_node(r)
      return self:remove_obsolete_nodes(k, node.parent, d, s, h)
   elseif band(node.occupied, node.occupied-1) == 0 then
      -- Node has only one child, move to parent if it is a leaf.
      local index = msb_set(node.occupied)
      if self:node_leaf(node, index) then
         parent.children[parent_index] = node.children[index]
         self:node_leaf(parent, parent_index, true)
         self:free_node(r)
         return self:remove_obsolete_nodes(k, node.parent, d, s, h)
      end
   end
end

function List:append_leaf (o, prev)
   prev = prev or self.last
   if prev == 0 then -- empty (0 is reserved for root node)
      self.first, self.last = o, o
   else
      local leaf = self:leaf(o)
      local pleaf = self:leaf(prev)
      leaf.list.prev = prev
      leaf.list.next = pleaf.list.next
      pleaf.list.next = o
      if leaf.list.next == 0 then
         -- print("new last")
         self.last = o
      end
   end
   self.length = self.length + 1
end

function List:unlink_leaf (o)
   local leaf = self:leaf(o)
   if self.first == o then
      self.first = leaf.list.next
   end
   if self.last == o then
      self.last = leaf.list.prev
   end
   if leaf.list.prev ~= 0 then
      local prev = self:leaf(leaf.list.prev)
      prev.list.next = leaf.list.next   
   end
   if leaf.list.next ~= 0 then
      local next = self:leaf(leaf.list.next)
      next.list.prev = leaf.list.prev
   end
   self.length = self.length - 1
end

function List:leaf_entry (o)
   local leaf = self:leaf(o)
   local ret = {}
   self:unpack_fields(ret, leaf.keys, self.keys)
   self:unpack_fields(ret, leaf.members, self.members)
   return ret
end

function List:add_entry (e, update, members)
   local n, d, s, h = self:find_node(e)
   local o = self:find_leaf(e, n, d, s, h)
   if o then
      if update then
         self:update_leaf(o, members or e)
      else
         error("Attempting to add duplicate entry to list")
      end
   else
      local o = self:new_leaf(e, members)
      self:insert_leaf(o, n, d, s, h)
      self:append_leaf(o)
   end
end

function List:add_or_update_entry (e, members)
   self:add_entry(e, true, members)
end

function List:find_entry (k)
   local o = self:find_leaf(k, self:find_node(k))
   if o then
      return self:leaf_entry(o)
   end
end

function List:remove_entry (k)
   local n, d, s, h = self:find_node(k)
   local o = self:find_leaf(k, n, d, s, h)
   if o then
      self:remove_child(k, n, d, s, h)
      self:unlink_leaf(o)
      self:destroy_leaf(o)
      return true
   end
end

function List:ipairs ()
   local n = 1
   local o = self.first
   assert(type(o) == 'number')
   return function ()
      if o == 0 then
         return
      end
      local i = n
      local e = self:leaf_entry(o)
      n = n + 1
      o = self:leaf(o).list.next
      return i, e
   end
end

List.header_t = ffi.typeof[[
   struct {
      double first, last, length;
   } __attribute__((packed))
]]

function List:save (stream)
   local header = self.header_t(self.first, self.last, self.length)
   stream:write_struct(self.header_t, header)
   self.heap:save(stream)
end

function List:load (stream, keys, members, lvalues)
   local self = self:_new(keys, members)
   local h = stream:read_struct(nil, self.header_t)
   self.heap = Heap:load(stream)
   self.first = h.first
   self.last = h.last
   self.root = 0 -- heap obj=0 reserved for root node
   self.length = h.length
   self.lvalues = lvalues
   return self
end

function selftest_list ()
   local l = List:new(
      {id={ctype='uint32_t'}, name={type='string'}},
      {value={ctype='double'}, description={type='string'}}
   )
   -- print("leaf_t", ffi.sizeof(l.leaf_t))
   -- print("node_t", ffi.sizeof(l.node_t))
   l:add_entry {
      id=42, name="foobar",
      value=3.14, description="PI"
   }
   local root = l:node(l.root)
   assert(root.occupied == lshift(1, 14))
   assert(root.occupied == root.leaf)
   -- print(l.root, root.occupied, root.leaf, root.children[14])
   local e1 = l:find_entry {id=42, name="foobar"}
   assert(e1)
   assert(e1.id == 42 and e1.name == "foobar")
   assert(not l:find_entry {id=43, name="foobar"})
   assert(not l:find_entry {id=42, name="foo"})
   -- for k,v in pairs(e1) do print(k,v) end
   l:add_entry {
      id=127, name="hey",
      value=1/0, description="inf"
   }
   for i, e in l:ipairs() do
      if i == 1 then
         assert(e.id == 42)
      elseif i == 2 then
         assert(e.id == 127)
      else
         error("unexpected index: "..i)
      end
   end

   -- Test empty interator
   for _ in List:new({id={ctype='uint64_t'}}, {}):ipairs() do
      error("list is empty")
   end
   
   -- Test update
   local ok = pcall(function ()
      l:add_entry {
         id=127, name="hey",
         value=1, description="one"
      }
   end)
   assert(not ok)
   l:add_or_update_entry {
      id=127, name="hey",
      value=1, description="one"
   }
   local e_updated = l:find_entry {id=127, name="hey"}
   assert(e_updated)
   assert(e_updated.value == 1)
   assert(e_updated.description == "one")
   
   -- Test collisions
   local lc = List:new({id={ctype='uint64_t'}}, {})
   -- print("leaf_t", ffi.sizeof(lc.leaf_t))
   -- print("node_t", ffi.sizeof(lc.node_t))
   lc:add_entry {id=0ULL}
   lc:add_entry {id=4895842651ULL}
   local root = lc:node(lc.root)
   assert(root.leaf == 0)
   assert(root.occupied == lshift(1, 12))
   -- print(lc.root, root.occupied, root.leaf, root.children[12])
   local e1 = lc:find_entry {id=0ULL}
   local e2 = lc:find_entry {id=4895842651ULL}
   assert(e1)
   assert(e2)
   assert(e1.id == 0ULL)
   assert(e2.id == 4895842651ULL)
   assert(lc:remove_entry {id=0ULL})
   assert(lc:remove_entry {id=4895842651ULL})
   assert(lc.length == 0)
   assert(root.occupied == 0)

   -- Test optional
   local l = List:new(
      {id={type='string'}},
      {value={ctype='double', optional=true},
       description={type='string', optional=true}}
   )
   l:add_entry{
      id="foo",
      value=3.14,
      description="PI"
   }
   l:add_entry{
      id="foo1",
      value=42
   }
   l:add_entry{
      id="foo2",
      description="none"
   }
   l:add_entry{
      id="foo3"
   }
   assert(l:find_entry{id="foo"}.value == 3.14)
   assert(l:find_entry{id="foo"}.description == "PI")
   assert(l:find_entry{id="foo1"}.value == 42)
   assert(l:find_entry{id="foo1"}.description == nil)
   assert(l:find_entry{id="foo2"}.value == nil)
   assert(l:find_entry{id="foo2"}.description == "none")
   assert(l:find_entry{id="foo3"}.value == nil)
   assert(l:find_entry{id="foo3"}.description == nil)

   -- Test empty type
   local l = List:new(
      {id={type='string'}, e={type='empty'}},
      {value={type='empty', optional=true}}
   )
   l:add_entry {id="foo", e=true}
   l:add_entry {id="foo1", e=true, value=true}
   assert(l:find_entry{id="foo", e=true}.value == nil)
   assert(l:find_entry{id="foo1", e=true}.value == true)
   local ok, err = pcall(function () l:add_entry {id="foo2"} end)
   assert(not ok)
   assert(err:match("Missing value: e"))

   -- Test lvalues
   local l = List:new(
      {id={type='string'}},
      {value={type='lvalue'}}
   )
   l:add_entry {id="foo", value={}}
   l:add_entry {id="foo1", value={bar=true}}
   assert(#l:find_entry{id="foo"}.value == 0)
   assert(l:find_entry{id="foo1"}.value.bar == true)
   l:add_or_update_entry {id="foo1", value={bar=false}}
   l:remove_entry {id="foo"}
   assert(l.lvalues.value[1] == nil)
   assert(l.lvalues.value[2].bar == false)

   -- Test optional lvalue
   local l = List:new(
      {id={type='string'}},
      {o={type='lvalue', optional=true}}
   )
   l:add_entry {id="foo"}
   l:add_entry {id="foo1", o={bar=true}}
   assert(l:find_entry{id="foo"}.o == nil)
   assert(l:find_entry{id="foo1"}.o.bar == true)
   l:add_or_update_entry {id="foo1", o={bar=false}}
   l:remove_entry {id="foo"}
   assert(l.lvalues.o[1].bar == false)

   -- Test struct
   local ts = "struct { uint16_t x; uint16_t y; }"
   local l = List:new(
      {id={type='string'}},
      {value={ctype=ts}}
   )
   l:add_entry {id="foo", value={x=1, y=2}}
   l:add_entry {id="foo1", value={x=2, y=3}}
   assert(l:find_entry{id="foo"}.value.x == 1)
   assert(l:find_entry{id="foo"}.value.y == 2)
   assert(l:find_entry{id="foo1"}.value.x == 2)
   assert(l:find_entry{id="foo1"}.value.y == 3)
   l:add_or_update_entry {id="foo1", value={x=3,y=4}}
   assert(l:find_entry{id="foo1"}.value.x == 3)
   assert(l:find_entry{id="foo1"}.value.y == 4)
   l:add_or_update_entry {id="foo1", value=l:find_entry{id="foo"}.value}
   assert(l:find_entry{id="foo1"}.value.x == 1)
   assert(l:find_entry{id="foo1"}.value.y == 2)
   l:add_entry {id="foo2", value=typeof(ts)({x=7, y=8})}
   assert(l:find_entry{id="foo2"}.value.x == 7)
   assert(l:find_entry{id="foo2"}.value.y == 8)

   -- Test optional struct
   local l = List:new(
      {id={type='string'}},
      {value={ctype=ts, optional=true}}
   )
   l:add_entry {id="foo"}
   l:add_entry {id="foo1", value={x=2, y=3}}
   assert(l:find_entry{id="foo"}.value == nil)
   assert(l:find_entry{id="foo1"}.value.x == 2)
   assert(l:find_entry{id="foo1"}.value.y == 3)
   l:add_or_update_entry {id="foo", value={x=1,y=2}}
   assert(l:find_entry{id="foo"}.value.x == 1)
   assert(l:find_entry{id="foo"}.value.y == 2)
   l:add_or_update_entry {id="foo1", value=nil}
   assert(l:find_entry{id="foo1"}.value == nil)

   -- Test list ordering
   local l = List:new({n={ctype='uint64_t'}},{})
   l:add_entry({n=1})
   l:add_entry({n=2})
   l:add_entry({n=3})
   l:add_entry({n=4})
   l:add_entry({n=5})
   local n, count = 0, 0
   for i, e in l:ipairs() do
      assert(e.n > n, "out of order: "..i)
      n = e.n
      count = count + 1
   end
   assert(count == l.length)

   -- Test empty iterator
   local l = List:new({n={ctype='uint64_t'}},{})
   l:add_entry({n=1})
   l:remove_entry({n=1})
   for i, e in l:ipairs() do
      assert(false)
   end

   -- Test load/save
   local keys = {id={type='string'}}
   local members = {value={type='lvalue'}}
   local l = List:new(keys, members)
   l:add_entry {id="foo", value={}}
   l:add_entry {id="foo1", value={bar=true}}
   local memstream = require("lib.stream.mem")
   local tmp = memstream.tmpfile()
   l:save(tmp)
   tmp:seek('set', 0)
   local l = List:load(tmp, keys, members, l.lvalues)
   assert(#l:find_entry{id="foo"}.value == 0)
   assert(l:find_entry{id="foo1"}.value.bar == true)
end


local ListMeta = {}

function ListMeta:__len ()
   return self.list.length
end

function ListMeta:__index (k)
   return self.list:find_entry(k)
end

function ListMeta:__newindex (k, members)
   if members ~= nil then
      self.list:add_or_update_entry(k, members)
   else
      self.list:remove_entry(k)
   end
end

function ListMeta:__ipairs ()
   return self.list:ipairs()
end

ListMeta.__pairs = ListMeta.__ipairs

local function pairs_for_key (iter, key)
   return function ()
      local i, e = iter()
      if i then
         return e[key], e
      end
   end
end

local function make_mt_for_single_key (key)
   local mt = {
      __len = ListMeta.__len,
      __ipairs = ListMeta.__ipairs
   }
   function mt:__index (k)
      return ListMeta.__index(self, {[key]=k})
   end
   function mt:__newindex (k, members)
      return ListMeta.__newindex(self, {[key]=k}, members)
   end
   function mt:__pairs ()
      return pairs_for_key(ListMeta.__ipairs(self), key)
   end
   return mt
end

local list_mt_cache = {}
local function mt_for_single_key (key)
   if not list_mt_cache[key] then
      list_mt_cache[key] = make_mt_for_single_key(key)
   end
   return list_mt_cache[key]
end

local function list_meta (keys, members)
   local numkeys = 0
   local key1
   for key in pairs(keys) do
      key1 = key1 or key
      numkeys = numkeys + 1
   end
   if numkeys == 1 then
      return mt_for_single_key(key1)
   elseif numkeys > 1 then
      return ListMeta
   else
      error("List needs at least one key")
   end
end

function new (keys, members)
   local mt = list_meta(keys, members)
   return setmetatable({list=List:new(keys, members)}, mt)
end

function object (list)
   if type(list) == 'table' then
      local o = rawget(list, 'list')
      local mt = getmetatable(o)
      if mt and mt.__index == List then
         return o
      end
   end
end

function load (stream, keys, members, lvalues)
   local mt = list_meta(keys, members)
   return setmetatable({list=List:load(stream, keys, members, lvalues)}, mt)
end

local function selftest_listmeta ()
   local l1 = new(
      {id={ctype='uint32_t'}, name={type='string'}},
      {value={ctype='double'}, description={type='string'}}
   )
   l1[{id=0, name='foo'}] = {value=1.5, description="yepyep"}
   l1[{id=1, name='bar'}] = {value=3.14, description="PI"}
   local ok, err = pcall (function()
      object(l1):add_entry {
         id=0, name='foo',
         value=0, description="should fail"
      }
   end)
   assert(not ok and err:match("Attempting to add duplicate entry to list"))
   assert(#l1 == 2)
   assert(#l1 == object(l1).length)
   assert(l1[{id=0, name='foo'}].value == 1.5)
   for i, entry in ipairs(l1) do
      if i == 1 then
         assert(entry.name == 'foo')
      elseif i == 2 then
         assert(entry.name == 'bar')
      else
         error("unexpected entry: "..i)
      end
   end
   l1[{id=0, name='foo'}] = nil
   assert(l1[{id=0, name='foo'}] == nil)
   assert(object(l1):find_entry({id=1, name='bar'}).value == 3.14)
   -- Test single key meta
   local l = new({id={type='string'}}, {value={type='string'}})
   l.foo = {value="bar"}
   assert(l.foo)
   assert(l.foo.value == "bar")
   assert(#l == 1)
   l.foo = nil
   assert(l.foo == nil)
   assert(#l == 0)
   local l = new({id={ctype='double'}}, {value={type='string'}})
   l[3] = {value="bar"}
   assert(l[3])
   assert(#l == 1)
   for id, e in pairs(l) do
      assert(id == 3)
      assert(e.value == "bar")
   end
   for i, e in ipairs(l) do
      assert(i == 1)
      assert(e.id == 3)
      assert(e.value == "bar")
   end
   l[3] = nil
   assert(l[3] == nil)
   assert(#l == 0)
   -- Test object()
   assert(object(l) == rawget(l, 'list'))
   assert(object({}) == nil)
   assert(object(42) == nil)
end

function selftest_ip ()
   local yang_util = require("lib.yang.util")
   local ipv6 = require("lib.protocol.ipv6")
   local l = new(
      {ip={ctype='uint32_t'}, port={ctype='uint16_t'}},
      {b4_address={ctype='uint8_t[16]'}}
   )
   math.randomseed(0)
   for i=1, 1e5 do
      local b4 = ffi.new("uint8_t[16]")
      for j=0,15 do b4[j] = i end
      object(l):add_entry {
         ip = math.random(0xffffffff),
         port = bit.band(0xffff, i),
         b4_address = b4
      }
   end
   print("added "..#l.." entries")
   local middle = math.floor(#l/2)
   local entry
   for i, e in ipairs(l) do
      if i == middle then
         entry = e
         print("Iterated to entry #"..middle)
         assert(e.ip == l[e].ip)
         print("Looked up middle entry with ip="..yang_util.ipv4_ntop(e.ip))
         print("B4 address is: "..ipv6:ntop(e.b4_address))
         break
      end
   end
   l[entry] = nil
   print("Removed middle entry")
   assert(not l[entry])
   print("Asserted entry is no longer present")
end

function selftest ()
   print("Selftest: Heap")
   selftest_heap()
   print("Selftest: List")
   selftest_list()
   print("Selftest: ListMeta")
   selftest_listmeta()
   print("Selftest: ip bench")
   selftest_ip()
end
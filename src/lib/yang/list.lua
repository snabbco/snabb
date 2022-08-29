-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local ffi = require("ffi")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local min, max = math.min, math.max

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

function selftest ()
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
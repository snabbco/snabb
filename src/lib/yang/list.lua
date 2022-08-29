-- Use of this source code is governed by the Apache 2.0 license; see
-- COPYING.
module(..., package.seeall)

local ffi = require("ffi")

local Heap = {
   chunk_size = 32,
   bucket_size = 8,
   growth_factor = 2,
   shrink_factor = 2
}

-- NB: `a' must be a power of two
local function padding (a, l) return bit.band(-l, a-1) end
local function padded (a, l) return l + padding(a, l) end

assert(Heap.chunk_size == 32)
assert(Heap.bucket_size == 8)
local function divchunk (n) return bit.rshift(n, 5) end
local function divbucket (n) return bit.rshift(n, 3) end
local function mulchunk (n) return bit.lshift(n, 5) end
local function mulbucket (n) return bit.lshift(n, 3) end

function Heap:new (initial_size)
   local default_initial_size = mulchunk(32)
   if initial_size then
      assert(initial_size > 0)
      initial_size = padded(self.chunk_size, initial_size)
   else
      initial_size = default_initial_size
   end
   local heap = {
      size = initial_size,
      hstart = 0,
      hlen = initial_size,
      buffer = self:new_buffer(initial_size),
      dirtybits = self:new_dirtybits(initial_size)
   }
   return setmetatable(heap, {__index=Heap})
end

function Heap:new_buffer (size)
   return ffi.new("uint8_t[?]", size)
end

function Heap:nchunks (bytes)
   bytes = bytes or self.size
   return divchunk(padded(self.bucket_size, bytes))
end

function Heap:nbuckets (bytes)
   return divbucket(padded(self.bucket_size, self:nchunks(bytes)))
end

function Heap:new_dirtybits (size)
   print("new_dirtybits", self:nbuckets(size))
   return ffi.new("uint8_t[?]", self:nbuckets(size))
end

function Heap:resize (new_size)
   local new_buffer = self:new_buffer(new_size)
   ffi.copy(new_buffer, self.buffer, ffi.sizeof(self.buffer))
   local new_dirtybits = self:new_dirtybits(new_size)
   ffi.copy(new_dirtybits, self.dirtybits, ffi.sizeof(self.dirtybits))
   self.buffer, self.dirtybits = new_buffer, new_dirtybits
   self.hstart, self.hlen = self.size, new_size - self.size
   self.size = new_size
end

function Heap:grow (min_size)
   local new_size = self.size
   repeat
      new_size = new_size * self.growth_factor
   until new_size >= min_size
   self:resize(new_size)
end

function Heap:ptr (offset)
   return self.buffer + mulchunk(offset)
end

function Heap:do_dirtybits (offset, nchunks, f)
   while nchunks > 0 do
      local bucket = divbucket(offset)
      local o = padding(self.bucket_size, padding(self.bucket_size, offset))
      local n = math.min(nchunks, self.bucket_size - o)
      f(self, bucket, o, n)
      offset, nchunks = offset + o, nchunks - n
   end
end

function Heap:mark_bucket (bucket, o, n)
   local marker = bit.lshift(bit.lshift(1ULL, n) - 1, o)
   self.dirtybits[bucket] = bit.bor(self.dirtybits[bucket], marker)
end

function Heap:unmark_bucket (bucket, o, n)
   local eraser = bit.bnot(bit.lshift(bit.lshift(1ULL, n) - 1, o))
   self.dirtybits[bucket] = bit.band(self.dirtybits[bucket], eraser)
end

function Heap:mark (offset, nchunks)
   self:do_dirtybits(offset, nchunks, Heap.mark_bucket)
end

function Heap:unmark (offset, nchunks)
   self:do_dirtybits(offset, nchunks, Heap.unmark_bucket)
end

function Heap:find_hole (nchunks)
   local need = divbucket(nchunks)
   local from, to
   for bucket = 0, self:nbuckets()-1 do
      if self.dirtybits[bucket] == 0 then
         from = from or bucket
         to = bucket
      elseif from and (need <= to-from) then
         break
      else
         from, to = nil, nil
      end
   end
   if from and (need <= to-from) then
      self.hstart = mulchunk(mulbucket(from))
      self.hlen = mulchunk(mulbucket(1+to-from))
      return true
   end
end

function Heap:allocate (bytes)
   bytes = padded(self.chunk_size, bytes)
   local nchunks = divchunk(bytes)
   if bytes > self.hlen then
      if not self:find_hole(nchunks) then
         self:grow(self.size + bytes)
      end
   end
   local offset = divchunk(self.hstart)
   self:mark(offset, nchunks)
   self.hstart, self.hlen = self.hstart + bytes, self.hlen - bytes
   return offset
end

function Heap:free (offset, bytes)
   bytes = padded(self.chunk_size, bytes)
   local nchunks = divchunk(bytes)
   self:unmark(offset, nchunks)
end

function selftest ()
   local h = Heap:new()
   local s1 = "foo"
   local o1 = h:allocate(#s1)
   ffi.copy(h:ptr(o1), s1, #s1)
   print("dirtybits[0]", ("%X"):format(h.dirtybits[0]))
   local s2 = "bar"
   local o2 = h:allocate(#s2)
   ffi.copy(h:ptr(o2), s2, #s2)
   print("dirtybits[0]", ("%X"):format(h.dirtybits[0]))
   assert(ffi.string(h:ptr(o1), #s1) == s1)
   h:free(o1, #s1)
   print("dirtybits[0]", ("%X"):format(h.dirtybits[0]))
   -- h:free(o2, #s2)
   -- print("dirtybits[0]", ("%X"):format(h.dirtybits[0]))
   assert(h:find_hole(1))
   assert(h.hstart == h.chunk_size*h.bucket_size)
   assert(h.hlen == h.size-h.hstart)
   local s3 = "flute"
   local o3 = h:allocate(#s3)
   ffi.copy(h:ptr(o3), s3, #s3)
   print("dirtybits[1]", ("%X"):format(h.dirtybits[1]))
   h:free(o2, #s2)
   print("dirtybits[0]", ("%X"):format(h.dirtybits[0]))
   assert(h:find_hole(1))
   assert(h.hstart == 0)
   assert(h.hlen == h.bucket_size*h.chunk_size)
   local old_size, min_new_size = h.size, h.size*2
   h:grow(min_new_size)
   assert(h.size >= min_new_size)
   assert(h.hstart == old_size)
   assert(h.hlen == h.size-h.hstart)
end
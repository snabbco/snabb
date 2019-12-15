-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Reorder buffer, designed for use with byte streams where ranges of
-- the byte streams may arrive out of order and might even overlap, as
-- in TCP.
--
-- The actual data is "on the side" in a ring buffer; the reorder
-- information just tracks which parts of the buffer are valid.
--
-- The reorder information is tracked in such a way that it's easy to
-- read completed data directly off the front of the ring buffer without
-- having to adjust the contents of the reorder buffer.

module(..., package.seeall)

local bit = require("bit")
local ffi = require("ffi")
local lib = require("core.lib")

local max_hole_count = 4

local reorder_t = ffi.typeof([[
   struct {
      uint32_t hole_count;
      struct { uint32_t start, len; } holes[$];
   } __attribute((packed))]],
   max_hole_count)

local function to_uint32(n)
   return ffi.new('uint32_t[1]', n)[0]
end

function new()
   return reorder_t()
end

local reorder = {}
reorder.__index = reorder

-- Add COUNT bytes from the uint8_t* BYTES to the ring buffer BUF.  The
-- read end of the ring buffer is at stream position BASE, and the bytes
-- to be written start at stream position POS.  Both BASE and POS are
-- wrappable uint32_t counters.
--
-- In the event of overlap between this range and a previously recorded
-- range of data, this implementation will discard the overlapping
-- portion of the new data, preferring the old data.
function reorder:write(buf, base, pos, bytes, count)
   local offset = to_uint32(pos - base)
   assert(offset + count <= buf.size)
   
   local i = 0
   while i < self.hole_count do
      local hole_offset = to_uint32(self.holes[i].start - base)
      local hole_len = self.holes[i].len
      if offset < hole_offset then
         -- New data overlaps with old data.
         local drop = math.min(count, hole_offset - offset)
         if drop == count then return end
         offset, bytes, count = offset + drop, bytes + drop, count - drop
         -- Fall through.
      end
      if offset < hole_offset + hole_len then
         -- New data starts in this hole.
         local fill = math.min(count, hole_offset + hole_len - offset)
         buf:rewrite(offset, bytes, fill)
         if fill == hole_len then
            -- Hole completely filled; delete it and loop again with
            -- same i.
            for j=i,self.hole_count-2 do self.holes[j] = self.holes[j+1] end
            self.hole_count = self.hole_count - 1
            -- Fall through.
         elseif offset == hole_offset then
            -- Hole partially filled from start.
            self.holes[i].start = base + hole_offset + fill
            self.holes[i].len = hole_len - fill
            return
         elseif offset + fill < hole_offset + hole_len then
            -- Hole split by fill in middle.
            assert(fill == count)
            if self.hole_count == max_hole_count then
               error("fixme: do something sensible here")
            else
               for j=i+1,self.hole_count-1 do self.holes[j+1] = self.holes[j] end
               self.holes[i].len = offset - hole_offset
               self.holes[i+1].start = base + offset + count
               self.holes[i+1].len = hole_len - count - self.holes[i].len
               self.hole_count = self.hole_count + 1
               return
            end
         else
            -- Hole partially filled at end; start looking in next hole.
            self.holes[i].len = hole_len - fill
            i = i + 1
            -- Fall through.
         end
         offset, bytes, count = offset + fill, bytes + fill, count - fill
      else
         -- New data is after this hole; look at next hole.
         i = i + 1
      end
   end

   -- New data is after all the holes.
   if offset < buf:read_avail() then
      -- But it starts before the end of the data.  Drop overlapping data.
      local drop = math.min(count, buf:read_avail() - offset)
      if drop == count then return end
      offset, bytes, count = offset + drop, bytes + drop, count - drop
   end      

   -- New data is after all the holes and all of the data.  But we might
   -- need to extend a hole or open a new hole before it starts.
   if offset ~= buf:read_avail() then
      local old_size = buf:read_avail()
      local new_hole_bytes = offset - old_size
      assert(new_hole_bytes > 0)
      if i == 0 then
         -- First hole.
         self.hole_count = 1
         self.holes[0].start = base + old_size
         self.holes[0].len = new_hole_bytes
      else
         local last_hole_offset = to_uint32(self.holes[i-1].start - base)
         local last_hole_len = self.holes[i-1].len
         if last_hole_offset + last_hole_len == old_size then
            -- Reorder buffer ended with a hole.  Extend it.
            self.holes[i-1].len = self.holes[i-1].len + new_hole_bytes
         elseif self.hole_count == max_hole_count then
            error("fixme: do something sensible here")
         else
            -- Reorder buffer ended with data.  Make a new hole.
            self.hole_count = self.hole_count + 1
            self.holes[i].start = base + old_size
            self.holes[i].len = new_hole_bytes
         end
      end
      -- Leave a place for the new or extended hole.
      buf:advance_write(new_hole_bytes)
   end
      
   -- Finally, append our new data to the buffer.
   buf:write(bytes, count)
end

function reorder:has_holes()
   return self.hole_count ~= 0
end

function reorder:read_avail(buf, base)
   if self:has_holes() then
      return to_uint32(self.holes[0].start - base)
   else
      return buf:read_avail()
   end
end

reorder_t = ffi.metatype(reorder_t, reorder)

function selftest()
   print('selftest: lib.reorder')
   local window = 2^16
   local data_len = math.random(1, window)
   local data = lib.random_bytes(data_len)
   -- 3 segments.
   local offset_12 = math.random(0, data_len)
   local offset_23 = math.random(offset_12, data_len)
   
   local function make_segment(start, len)
      local ret = ffi.new('uint8_t[?]', len)
      ffi.copy(ret, data + start, len)
      return {ret, start, len}
   end
   local function permute_indices(lo, hi)
      if lo == hi then return {{hi}} end
      local ret = {}
      for _, tail in ipairs(permute_indices(lo + 1, hi)) do
         for pos = 1, #tail + 1 do
            local order = lib.deepcopy(tail)
            table.insert(order, pos, lo)
            table.insert(ret, order)
         end
      end
      return ret
   end

   local segments = { make_segment(0, offset_12),
                      make_segment(offset_12, offset_23 - offset_12),
                      make_segment(offset_23, data_len - offset_23) }
   local reorder = new()
   local buf = require('lib.buffer').new(window)

   local pos = 0
   for _, order in ipairs(permute_indices(1, #segments)) do
      for again = 1,5 do
         local advance = math.random(0, 2^32)
         buf:advance_read(advance)
         buf:advance_write(advance)
         pos = to_uint32(pos + advance)
         for _, i in ipairs(order) do
            local bytes, offset, len = unpack(segments[i])
            reorder:write(buf, pos, to_uint32(pos + offset), bytes, len)
         end
         assert(reorder.hole_count == 0)
         assert(reorder:read_avail(buf) == data_len)
         local tmp = ffi.new('uint8_t[?]', data_len)
         buf:read(tmp, data_len)
         assert(ffi.C.memcmp(data, tmp, data_len) == 0)
      end
   end

   print('selftest: ok')
end

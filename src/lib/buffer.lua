-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Ring buffer for bytes

module(...,package.seeall)

local lib = require("core.lib")
local ffi = require("ffi")
local bit = require("bit")

local band = bit.band

local buffer_t = ffi.typeof[[
struct {
  uint32_t read_idx, write_idx;
  uint32_t size;
  uint8_t buf[?];
} __attribute__((packed))
]]

local function to_uint32(n)
   return ffi.new('uint32_t[1]', n)[0]
end

function new(size)
   local ret = buffer_t(size)
   ret:init(size)
   return ret
end

local buffer = {}
buffer.__index = buffer

function buffer:init(size)
   assert(size ~= 0 and band(size, size - 1) == 0, "size not power of two")
   self.size = size
   return self
end

function buffer:reset()
   self.write_idx, self.read_idx = 0, 0
end

function buffer:is_empty()
   return self.write_idx == self.read_idx
end
function buffer:read_avail()
   return to_uint32(self.write_idx - self.read_idx)
end
function buffer:is_full()
   return self:read_avail() == self.size
end
function buffer:write_avail()
   return self.size - self:read_avail()
end

function buffer:write_pos()
   return band(self.write_idx, self.size - 1)
end
function buffer:rewrite_pos(offset)
   return band(self.read_idx + offset, self.size - 1)
end
function buffer:read_pos()
   return band(self.read_idx, self.size - 1)
end

function buffer:advance_write(count)
   self.write_idx = self.write_idx + count
end
function buffer:advance_read(count)
   self.read_idx = self.read_idx + count
end

function buffer:write(bytes, count)
   if count > self:write_avail() then error('write xrun') end
   local pos = self:write_pos()
   local count1 = math.min(self.size - pos, count)
   ffi.copy(self.buf + pos, bytes, count1)
   ffi.copy(self.buf, bytes + count1, count - count1)
   self:advance_write(count)
end

function buffer:rewrite(offset, bytes, count)
   if offset + count > self:read_avail() then error('rewrite xrun') end
   local pos = self:rewrite_pos(offset)
   local count1 = math.min(self.size - pos, count)
   ffi.copy(self.buf + pos, bytes, count1)
   ffi.copy(self.buf, bytes + count1, count - count1)
end

function buffer:read(bytes, count)
   if count > self:read_avail() then error('read xrun') end
   local pos = self:read_pos()
   local count1 = math.min(self.size - pos, count)
   ffi.copy(bytes, self.buf + pos, count1)
   ffi.copy(bytes + count1, self.buf, count - count1)
   self:advance_read(count)
end

function buffer:drop(count)
   if count > self:read_avail() then error('read xrun') end
   self:advance_read(count)
end

function buffer:peek()
   local pos = self:read_pos()
   return self.buf + pos, math.min(self:read_avail(), self.size - pos)
end

buffer_t = ffi.metatype(buffer_t, buffer)

function selftest()
   print('selftest: lib.buffer')
   local function assert_throws(f, ...)
      local success, ret = pcall(f, ...)
      assert(not success, "expected failure but got "..tostring(ret))
   end
   local function assert_avail(b, readable, writable)
      assert(b:read_avail() == readable)
      assert(b:write_avail() == writable)
   end
   local function write_str(b, str)
      local scratch = ffi.new('uint8_t[?]', #str)
      ffi.copy(scratch, str, #str)
      b:write(scratch, #str)
   end
   local function read_str(b, count)
      local scratch = ffi.new('uint8_t[?]', count)
      b:read(scratch, count)
      return ffi.string(scratch, count)
   end

   assert_throws(new, 10)
   local b = new(16)
   assert_avail(b, 0, 16)
   for i = 1,10 do
      local s = '0123456789'
      write_str(b, s)
      assert_avail(b, #s, 16-#s)
      assert(read_str(b, #s) == s)
      assert_avail(b, 0, 16)
   end

   local ptr, avail = b:peek()
   assert(avail == 0)
   write_str(b, "foo")
   local ptr, avail = b:peek()
   assert(avail > 0)

   -- Test wrap of indices.
   local s = "overflow"
   b.read_idx = to_uint32(3 - #s)
   b.write_idx = b.read_idx
   assert_avail(b, 0, 16)
   write_str(b, s)
   assert_avail(b, #s, 16-#s)
   assert(read_str(b, #s) == s)
   assert_avail(b, 0, 16)

   print('selftest: ok')
end

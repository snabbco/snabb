-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- A channel is a ring buffer used by the config leader app to send
-- updates to a follower.  Each follower has its own ring buffer and is
-- the only reader to the buffer.  The config leader is the only writer
-- to these buffers also.  The ring buffer is just bytes; putting a
-- message onto the buffer will write a header indicating the message
-- size, then the bytes of the message.  The channel ring buffer is
-- mapped into shared memory.  Access to a channel will never block or
-- cause a system call.

local ffi = require('ffi')
local S = require("syscall")
local lib = require('core.lib')
local shm = require('core.shm')

local ring_buffer_t = ffi.typeof([[struct {
   uint32_t read;
   uint32_t write;
   uint32_t size;
   uint8_t buf[?];
}]])

-- Q: Why not just use shm.map?
-- A: We need a variable-sized mapping.
local function create_ring_buffer (name, size)
   local path = shm.resolve(name)
   shm.mkdir(lib.dirname(path))
   path = shm.root..'/'..path
   local fd, err = S.open(path, "creat, rdwr, excl", '0664')
   if not fd then
      err = tostring(err or "unknown error")
      error('error creating file "'..path..'": '..err)
   end
   local len = ffi.sizeof(ring_buffer_t, size)
   assert(fd:ftruncate(len), "ring buffer: ftruncate failed")
   local mem, err = S.mmap(nil, len, "read, write", "shared", fd, 0)
   fd:close()
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   mem = ffi.cast(ffi.typeof("$*", ring_buffer_t), mem)
   ffi.gc(mem, function (ptr) S.munmap(ptr, len) end)
   mem.size = size
   return mem
end

local function open_ring_buffer (name)
   local path = shm.resolve(name)
   path = shm.root..'/'..path
   local fd, err = S.open(path, "rdwr")
   if not fd then
      err = tostring(err or "unknown error")
      error('error opening file "'..path..'": '..err)
   end
   local stat = S.fstat(fd)
   local len = stat and stat.size
   if len < ffi.sizeof(ring_buffer_t, 0) then
      error("unexpected size for ring buffer")
   end
   local mem, err = S.mmap(nil, len, "read, write", "shared", fd, 0)
   fd:close()
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   mem = ffi.cast(ffi.typeof("$*", ring_buffer_t), mem)
   ffi.gc(mem, function (ptr) S.munmap(ptr, len) end)
   if len ~= ffi.sizeof(ring_buffer_t, mem.size) then
      error("unexpected ring buffer size: "..tostring(len))
   end
   return mem
end

local function to_uint32 (num)
   local buf = ffi.new('uint32_t[1]')
   buf[0] = num
   return buf[0]
end

local function read_avail (ring)
   lib.compiler_barrier()
   return to_uint32(ring.write - ring.read)
end

local function write_avail (ring)
   return ring.size - read_avail(ring)
end

Channel = {}

-- Messages typically encode up to 3 or 4 strings like app names, link
-- names, module names, or the like.  All of that and the length headers
-- probably fits within 256 bytes per message certainly.  So make room
-- for around 4K messages, why not.
local default_buffer_size = 1024*1024
function create(name, size)
   local ret = {}
   size = size or default_buffer_size
   ret.ring_buffer = create_ring_buffer(name, size)
   return setmetatable(ret, {__index=Channel})
end

function open(name)
   local ret = {}
   ret.ring_buffer = open_ring_buffer(name)
   return setmetatable(ret, {__index=Channel})
end

-- The coordination needed between the reader and the writer is that:
--
--  1. If the reader sees a a bumped write pointer, that the data written
--     to the ring buffer will be available to the reader, i.e. the writer
--     has done whatever is needed to synchronize the data.
--
--  2. It should be possible for the reader to update the read pointer
--     without stompling other memory, notably the write pointer.
--
--  3. It should be possible for the writer to update the write pointer
--     without stompling other memory, notably the read pointer.
--
--  4. Updating a write pointer or a read pointer should eventually be
--     visible to the reader or writer, respectively.
--
-- The full memory barrier after updates to the read or write pointer
-- ensures (1).  The x86 memory model, and the memory model of C11,
-- guarantee (2) and (3).  For (4), the memory barrier on the writer
-- side ensures that updates to the read or write pointers are
-- eventually visible to other CPUs, but we also have to insert a
-- compiler barrier before reading them to prevent LuaJIT from caching
-- their value somewhere else, like in a register.  See
-- https://www.kernel.org/doc/Documentation/memory-barriers.txt for more
-- discussion on memory models, and
-- http://www.freelists.org/post/luajit/Compiler-loadstore-barrier-volatile-pointer-barriers-in-general,3
-- for more on compiler barriers in LuaJIT.
--
-- If there are multiple readers or writers, they should serialize their
-- accesses through some other mechanism.
--

-- Put some bytes onto the channel, but without updating the write
-- pointer.  Precondition: the caller has checked that COUNT bytes are
-- indeed available for writing.
function Channel:put_bytes(bytes, count, offset)
   offset = offset or 0
   local ring = self.ring_buffer
   local start = (ring.write + offset) % ring.size
   if start + count > ring.size then
      local head = ring.size - start
      ffi.copy(ring.buf + start, bytes, head)
      ffi.copy(ring.buf, bytes + head, count - head)
   else
      ffi.copy(ring.buf + start, bytes, count)
   end
end

-- Peek some bytes into the channel.  If the COUNT bytes are contiguous,
-- return a pointer into the channel.  Otherwise allocate a buffer for
-- those bytes and return that.  Precondition: the caller has checked
-- that COUNT bytes are indeed available for reading.
function Channel:peek_bytes(count, offset)
   offset = offset or 0
   local ring = self.ring_buffer
   local start = (ring.read + offset) % ring.size
   local len
   if start + count > ring.size then
      local buf = ffi.new('uint8_t[?]', count)
      local head_count = ring.size - start
      local tail_count = count - head_count
      ffi.copy(buf, ring.buf + start, head_count)
      ffi.copy(buf + head_count, ring.buf, tail_count)
      return buf
   else
      return ring.buf + start
   end
end

function Channel:put_message(bytes, count)
   local ring = self.ring_buffer
   if write_avail(ring) < count + 4 then return false end
   self:put_bytes(ffi.cast('uint8_t*', ffi.new('uint32_t[1]', count)), 4)
   self:put_bytes(bytes, count, 4)
   ring.write = ring.write + count + 4
   ffi.C.full_memory_barrier()
   return true;
end

function Channel:peek_payload_len()
   local ring = self.ring_buffer
   local avail = read_avail(ring)
   local count = 4
   if avail < count then return nil end
   local len = ffi.cast('uint32_t*', self:peek_bytes(4))[0]
   if avail < count + len then return nil end
   return len
end

function Channel:peek_message()
   local payload_len = self:peek_payload_len()
   if not payload_len then return nil, nil end
   return self:peek_bytes(payload_len, 4), payload_len
end

function Channel:discard_message(payload_len)
   local ring = self.ring_buffer
   ring.read = ring.read + payload_len + 4
   ffi.C.full_memory_barrier()
end

function selftest()
   print('selftest: apps.config.channel')
   local msg_t = ffi.typeof('struct { uint8_t a; uint8_t b; }')
   local ch = create('test/config-channel', (4+2)*16 + 1)
   local function put(i)
      return ch:put_message(ffi.new('uint8_t[2]', {i, i+16}), 2)
   end
   for _=1,4 do
      for i=1,16 do assert(put(i)) end
      assert(not put(17))
      local function assert_pop(i)
         local msg, len = ch:peek_message()
         assert(msg)
         assert(len == 2)
         assert(msg[0] == i)
         assert(msg[1] == i + 16)
         ch:discard_message(len)
      end
      assert_pop(1)
      assert(put(17))
      for i=2,17 do assert_pop(i) end
      assert(not ch:peek_message())
   end
   print('selftest: channel ok')
end

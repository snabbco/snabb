-- Channels
--
-- A channel is a way for different threads or processes to communicate.
-- Channels are backed by a ring buffer that is mapped into shared
-- memory.  Access to a channel will never block or cause a system call.
-- Readers and writers have to agree ahead of time on how to interpret
-- the messages that are written to a channel.

module(..., package.seeall)

local ffi = require('ffi')
local S = require("syscall")
local lib = require('core.lib')

root = "/var/run/snabb"

local ring_buffer_t = ffi.typeof([[struct {
   uint32_t read;
   uint32_t write;
   uint32_t size;
   uint32_t flags;
   uint8_t buf[?];
}]])

-- Make directories needed for a named object.
-- Given the name "foo/bar/baz" create /var/run/foo and /var/run/foo/bar.
local function mkdir_p (name)
   -- Create root with mode "rwxrwxrwt" (R/W for all and sticky) if it
   -- does not exist yet.
   if not S.stat(root) then
      local mask = S.umask(0)
      local status, err = S.mkdir(root, "01777")
      assert(status, ("Unable to create %s: %s"):format(
                root, tostring(err or "unspecified error")))
      S.umask(mask)
   end
   -- Create sub directories
   local dir = root
   name:gsub("([^/]+)",
             function (x) S.mkdir(dir, "rwxu")  dir = dir.."/"..x end)
end

local function create_ring_buffer (name, size)
   local tail = tostring(S.getpid())..'/channels/'..name
   local path = root..'/'..tail
   mkdir_p(tail)
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

local function open_ring_buffer (pid, name)
   local path = root..'/'..tostring(pid)..'/channels/'..name
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
local function put_bytes (ring, bytes, count)
   local new_write_avail = write_avail(ring) - count
   if new_write_avail < 0 then return new_write_avail end
   local start = ring.write % ring.size
   if start + count > ring.size then
      local head = ring.size - start
      ffi.copy(ring.buf + start, bytes, head)
      ffi.copy(ring.buf, bytes + head, count - head)
   else
      ffi.copy(ring.buf + start, bytes, count)
   end
   ring.write = ring.write + count
   ffi.C.full_memory_barrier()
   return new_write_avail
end

local function get_bytes (ring, count, buf)
   if read_avail(ring) < count then return nil end
   buf = buf or ffi.new('uint8_t[?]', count)
   local start = ring.read % ring.size
   if start + count > ring.size then
      ffi.copy(buf, ring.buf + start, ring.size - start)
      ffi.copy(buf, ring.buf, count - ring.size)
   else
      ffi.copy(buf, ring.buf + start, count)
   end
   ring.read = ring.read + count
   ffi.C.full_memory_barrier()
   return buf
end

Channel = {}

local default_buffer_size = 32
function create(name, type, size)
   local ret = {}
   size = size or default_buffer_size
   ret.ring_buffer = create_ring_buffer(name, ffi.sizeof(type) * size)
   ret.type = type
   ret.type_ptr = ffi.typeof('$*', type)
   return setmetatable(ret, {__index=Channel})
end

function open(pid, name, type)
   local ret = {}
   ret.ring_buffer = open_ring_buffer(pid, name)
   if ret.ring_buffer.size % ffi.sizeof(type) ~= 0 then
      error ("Unexpected channel size: "..ret.ring_buffer.size)
   end
   ret.type = type
   return setmetatable(ret, {__index=Channel})
end

function Channel:put(...)
   local val = self.type(...)
   return put_bytes(self.ring_buffer, val, ffi.sizeof(self.type)) >= 0
end

function Channel:pop()
   local ret = get_bytes(self.ring_buffer, ffi.sizeof(self.type))
   if ret then return ffi.cast(self.type_ptr, ret) end
end

function selftest()
   print('selftest: channel')
   local msg_t = ffi.typeof('struct { uint8_t a; uint8_t b; }')
   local ch = create('test/control', msg_t, 16)
   for i=1,16 do assert(ch:put({i, i+16})) end
   assert(not ch:put({0,0}))
   local function assert_pop(a, b)
      local msg = assert(ch:pop())
      assert(msg.a == a)
      assert(msg.b == b)
   end
   assert_pop(1, 17)
   assert(ch:put({17, 33}))
   assert(not ch:put({0,0}))
   for i=2,17 do assert_pop(i, i+16) end
   assert(not ch:pop())
   print('selftest: channel ok')
end

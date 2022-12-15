-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local sync = require("core.sync")
local shm  = require("core.shm")
local lib  = require("core.lib")
local ffi  = require("ffi")

local waitfor, compiler_barrier = lib.waitfor, lib.compiler_barrier
local band = bit.band

-- Group freelist: lock-free multi-producer multi-consumer ring buffer
-- (mpmc queue)
--
-- https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue
--
-- NB: assumes 32-bit wide loads/stores are atomic (as is the fact on x86_64)!

-- Group freelist holds up to n chunks of chunksize packets each
chunksize = 2048

-- (default_size=1024)*(chunksize=2048) == roughly two million packets
local default_size = 1024 -- must be a power of two

local CACHELINE = 64 -- XXX - make dynamic
local INT = ffi.sizeof("uint32_t")

ffi.cdef([[
struct group_freelist_chunk {
   uint32_t sequence[1], nfree;
   struct packet *list[]]..chunksize..[[];
} __attribute__((packed))]])

ffi.cdef([[
struct group_freelist {
   uint32_t enqueue_pos[1], enqueue_mask;
   uint8_t pad_enqueue_pos[]]..CACHELINE-2*INT..[[];

   uint32_t dequeue_pos[1], dequeue_mask;
   uint8_t pad_dequeue_pos[]]..CACHELINE-2*INT..[[];

   uint32_t size, state[1];

   struct group_freelist_chunk chunk[?];
} __attribute__((packed, aligned(]]..CACHELINE..[[)))]])

-- Group freelists states
local CREATE, INIT, READY = 0, 1, 2

function freelist_create (name, size)
   size = size or default_size
   assert(band(size, size-1) == 0, "size is not a power of two")

   local fl = shm.create(name, "struct group_freelist", size)
   if sync.cas(fl.state, CREATE, INIT) then
      fl.size = size
      local mask = size - 1
      fl.enqueue_mask, fl.dequeue_mask = mask, mask
      for i = 0, fl.size-1 do
         fl.chunk[i].sequence[0] = i
      end
      assert(sync.cas(fl.state, INIT, READY))
      return fl
   else
      shm.unmap(fl)
      return freelist_open(name)
   end
end

function freelist_open (name, readonly)
   local fl = shm.open(name, "struct group_freelist", 'read-only', 1)
   waitfor(function () return fl.state[0] == READY end)
   local size = fl.size
   shm.unmap(fl)
   return shm.open(name, "struct group_freelist", readonly, size)
end

function start_add (fl)
   local pos = fl.enqueue_pos[0]
   local mask = fl.enqueue_mask
   while true do
      local chunk = fl.chunk[band(pos, mask)]
      local seq = chunk.sequence[0]
      local dif = seq - pos
      if dif == 0 then
         if sync.cas(fl.enqueue_pos, pos, pos+1) then
            return chunk, pos+1
         end
      elseif dif < 0 then
         return
      else
         compiler_barrier() -- ensure fresh load of enqueue_pos
         pos = fl.enqueue_pos[0]
      end
   end
end

function start_remove (fl)
   local pos = fl.dequeue_pos[0]
   local mask = fl.dequeue_mask
   while true do
      local chunk = fl.chunk[band(pos, mask)]
      local seq = chunk.sequence[0]
      local dif = seq - (pos+1)
      if dif == 0 then
         if sync.cas(fl.dequeue_pos, pos, pos+1) then
            return chunk, pos+mask+1
         end
      elseif dif < 0 then
         return
      else
         compiler_barrier() -- ensure fresh load of dequeue_pos
         pos = fl.dequeue_pos[0]
      end
   end
end

function finish (chunk, seq)
   chunk.sequence[0] = seq
end

local function occupied_chunks (fl)
   local enqueue, dequeue = fl.enqueue_pos[0], fl.dequeue_pos[0]
   if dequeue > enqueue then
      return enqueue + fl.size - dequeue
   else
      return enqueue - dequeue
   end
end

-- Register struct group_freelist as an abstract SHM object type so that
-- the group freelist can be recognized by shm.open_frame and described
-- with tostring().
shm.register('group_freelist', {open=freelist_open})
ffi.metatype("struct group_freelist", {__tostring = function (fl)
   return ("%d/%d"):format(occupied_chunks(fl)*chunksize, fl.size*chunksize)
end})

function selftest ()
   local fl = freelist_create("test.group_freelist")
   assert(not start_remove(fl)) -- empty

   local w1, sw1 = start_add(fl)
   local w2, sw2 = start_add(fl)
   assert(not start_remove(fl)) -- empty
   finish(w2, sw2)
   assert(not start_remove(fl)) -- empty
   finish(w1, sw1)
   local r1, sr1 = start_remove(fl)
   assert(r1 == w1)
   local r2, sr2 = start_remove(fl)
   assert(r2 == w2)
   assert(not start_remove(fl)) -- empty
   finish(r1, sr1)
   finish(r2, sr2)
   assert(not start_remove(fl)) -- empty

   for i=1,fl.size do
      local w, sw = start_add(fl)
      assert(w)
      finish(w, sw)
   end
   assert(not start_add(fl)) -- full
   for i=1,fl.size do
      local r, sr = start_remove(fl)
      assert(r)
      finish(r, sr)
   end
   assert(not start_remove(fl)) -- empty

   local w = {}
   for _=1,10000 do
      for _=1,math.random(fl.size) do
         local w1, sw = start_add(fl)
         if not w1 then break end
         finish(w1, sw)
         table.insert(w, w1)
      end
      for _=1,math.random(#w) do
         local r, sr = start_remove(fl)
         assert(r == table.remove(w, 1))
         finish(r, sr)
      end
   end

   local flro = freelist_open("test.group_freelist", 'read-only')
   assert(flro.size == fl.size)
   local objsize = ffi.sizeof("struct group_freelist", fl.size)
   assert(ffi.C.memcmp(fl, flro, objsize) == 0)
end
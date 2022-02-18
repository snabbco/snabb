-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local sync = require("core.sync")
local shm  = require("core.shm")
local ffi  = require("ffi")
local band = bit.band
local min  = math.min

-- Group freelist: lock-free multi-producer multi-consumer ring buffer
-- (mpmc queue)
--
-- NB: assumes 32-bit wide loads/stores are atomic (as is the fact on x86_64)!
--
-- Logically, the group freelist is a simple ring buffer with
-- 32-bit head and tail cursors, just like core.link (and lib.interlink).
--
-- However, producers and consumers operate in parallel in two phases:
--
--  * start_add and start_remove reserve a "ticket" to produce or consume
--    the next N head or tail positions.
--
--  * finish_add and finish_remove "redeem" a ticket to advance the
--    head or tail cursors accordingly.
--
-- To avoid false sharing, cursors and copies thereof are arranged in
-- distinct cachelines:
--
--  * head_remove is the head cursor visible to consumers.
--    It is updated by finish_add, and copied into head_cache in start_remove.
--
--  * tail_remove is the tail cursor visible to consumers,
--    head_cache is a copy of head_remove intended to avoid invalidation
--    of this cacheline.
--    They are updated in start_remove.
--
--  * tail_add is the tail cursor visible to producers.
--    It is updated by finish_remove, and copied into tail_cache in start_add.
--
--  * head_add is the head cursor visible to producers,
--    tail_cache is a copy of tail_add intended to avoid invalidation
--    of this cacheline.
--    They are updated in start_add.
--
-- Let's walk through what happens in a producer between
-- start_add and finish_add (consumer behavior is symmetric):
--
--  1. We fetch the value head=head_add (this will incur a cache miss if
--     another consumer updated head_add).
--
--  2. We make sure there is enough capacity to add N packets
--     (head < tail_add):
--     fetching tail_cache might be sufficient, otherwise we have to
--     update it by fetching tail_add (this will incur a cache miss if
--     a consumer updated tail_add).
--
--  3. We attempt to CAS head_add = head -> head+N.
--     If this fails we have to start over.
--     If the CAS succeds we obtaine a ticket (head) to add N packets to
--     the freelist (and have invalidated any caches of head_add).
--
--  4. We can now add N packets to list[head..head+N] without
--     synchronizing with other producers or consumers.
--
--  5. We update head_remove, the head cursor visible to consumers,
--     redeeming our ticket.
--     We do this by repeating CAS head_remove = head -> head+N
--     until it succeeds.
--     This will fail for as long as we are waiting for another
--     producer to redeem their earlier ticket by calling finish_add
--     (we incur a cache miss any time another producer updated head_remove).
--
-- The consumer side works in just the same way, the only difference being
-- that in (4.) consumers will incur cache misses when fetching
-- list[tail..tail+N] to remove packets, naturally.
--
-- NB: this design is not crash safe! If a producer or consumer halts
-- in between start_add/start_remove and finish_add/finish_remove other
-- producers or consumers will deadlock in their attempts to
-- redeem their tickets (finish_add/finish_remove).

local SIZE = 1048576 -- 2^20, roughly one million
local MAX = SIZE - 1

local CACHELINE = 64 -- XXX - make dynamic
local INT = ffi.sizeof("uint32_t")

ffi.cdef([[
struct group_freelist {
   uint32_t head_remove[1];
   uint8_t pad_head_remove[]]..CACHELINE-1*INT..[[];

   uint32_t head_cache[1], tail_remove[1];
   uint8_t pad_tail_remove[]]..CACHELINE-2*INT..[[];

   uint32_t tail_add[1];
   uint8_t pad_tail_add[]]..CACHELINE-1*INT..[[];

   uint32_t tail_cache[1], head_add[1];
   uint8_t pad_head_add[]]..CACHELINE-2*INT..[[];

   struct packet *list[]]..SIZE..[[];
} __attribute__((packed, aligned(]]..CACHELINE..[[)))]])


function freelist_create (name)
   return shm.create(name, "struct group_freelist")
end

function freelist_open (name, readonly)
   return shm.open(name, "struct group_freelist", readonly)
end

local function mask (i)
   return band(i, MAX)
end

local function nfree (head, tail)
   return mask(head - tail)
end

local function capacity (head, tail)
   return MAX - nfree(head, tail)
end

function start_add (fl, n)
   while true do
      local head = fl.head_add[0]
      if capacity(head, fl.tail_cache[0]) < n then
         fl.tail_cache[0] = fl.tail_add[0]
         assert(capacity(head, fl.tail_cache[0]) >= n,
                "group freelist overflow")
      end
      if sync.cas(fl.head_add, head, mask(head + n)) then
         return head
      end
   end
end

function add (fl, head, i, p)
   fl.list[mask(head+i)] = p
end

local function finish_add1 (fl, head, n)
   return sync.cas(fl.head_remove, head, mask(head + n))
end
function finish_add (fl, head, n)
   while not finish_add1(fl, head, n) do end
end

function start_remove (fl, n)
   while true do
      local tail = fl.tail_remove[0]
      if nfree(fl.head_cache[0], tail) < n then
         fl.head_cache[0] = fl.head_remove[0]
      end
      local n = min(n, nfree(fl.head_cache[0], tail))
      if n == 0 or sync.cas(fl.tail_remove, tail, mask(tail + n)) then
         return tail, n
      end
   end
end

function remove (fl, tail, i)
   local p = fl.list[mask(tail+i)]
   fl.list[mask(tail+i)] = nil
   return p
end

local function finish_remove1 (fl, tail, n)
   return sync.cas(fl.tail_add, tail, mask(tail + n))
end
function finish_remove (fl, tail, n)
   while not finish_remove1(fl, tail, n) do end
end


function selftest ()
   local fl = freelist_create("test_freelist")
   assert(select(2, start_remove(fl, 1)) == 0) -- empty

   local w1 = start_add(fl, 1000)
   local w2 = start_add(fl, 3700)
   assert(select(2, start_remove(fl, 1)) == 0) -- empty
   assert(not finish_add1(fl, w2, 3700))
   assert(finish_add1(fl, w1, 1000))
   assert(finish_add1(fl, w2, 3700))
   local r1, nr1 = start_remove(fl, 2000)
   assert(r1 and nr1 == 2000)
   local r2, nr2 = start_remove(fl, 3000)
   assert(r2 and nr2 == 2700)
   assert(not finish_remove1(fl, r2, nr2))
   assert(finish_remove1(fl, r1, nr1))
   assert(finish_remove1(fl, r2, nr2))
   assert(select(2, start_remove(fl, 1)) == 0) -- empty

   local w3 = start_add(fl, 12345)
   local w4 = start_add(fl, 54321)
   assert(finish_add1(fl, w3, 12345))
   local r3, nr3 = start_remove(fl, 10000)
   assert(r3 and nr3 == 10000)
   assert(finish_add1(fl, w4, 54321))
   local r4, nr4 = start_remove(fl, 54321+2345)
   assert(r4 and nr4 == 54321+2345)
   assert(not finish_remove1(fl, r4, nr4))
   assert(finish_remove1(fl, r3, nr3))
   assert(finish_remove1(fl, r4, nr4))
   assert(select(2, start_remove(fl, 1)) == 0) -- empty

   local w5 = start_add(fl, MAX)
   assert(not pcall(start_add, fl, 1)) -- full
   assert(finish_add1(fl, w5, MAX))
   local r5, nr5 = start_remove(fl, MAX)
   assert(r5 and nr5 == MAX)
   assert(not pcall(start_add, fl, 1)) -- full
   assert(select(2, start_remove(fl, 1)) == 0) -- empty
   assert(finish_remove1(fl, r5, nr5))
   assert(select(2, start_remove(fl, 1)) == 0) -- empty
   assert(pcall(start_add, fl, 1)) -- not full
end
-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local sync = require("core.sync")
local shm  = require("core.shm")
local ffi  = require("ffi")
local band = bit.band
local min  = math.min

local SIZE = 1048576 -- 2^20, roughly one million
local MAX = SIZE - 1

local CACHELINE = 64 -- XXX - make dynamic
local INT = ffi.sizeof("uint32_t")

ffi.cdef([[
struct group_freelist {
   uint32_t h_remove[1];
   uint8_t pad_h_remove[]]..CACHELINE-1*INT..[[];

   uint32_t t_remove[1];
   uint8_t pad_t_remove[]]..CACHELINE-1*INT..[[];

   uint32_t h_add[1];
   uint8_t pad_h_add[]]..CACHELINE-1*INT..[[];

   uint32_t t_add[1];
   uint8_t pad_t_add[]]..CACHELINE-1*INT..[[];

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

function start_add (fl, n)
   while true do
      local head = fl.h_add[0]
      assert(MAX-mask(head - fl.t_add[0]) >= n, "group freelist overflow")
      if sync.cas(fl.h_add, head, mask(head + n)) then
         return head
      end
   end
end

function add (fl, head, i, p)
   fl.list[mask(head+i)] = p
end

local function finish_add1 (fl, head, n)
   return sync.cas(fl.h_remove, head, mask(head + n))
end
function finish_add (fl, head, n)
   while not finish_add1(fl, head, n) do end
end

function start_remove (fl, n)
   while true do
      local tail = fl.t_remove[0]
      local n = min(n, mask(fl.h_remove[0] - tail))
      if n == 0 or sync.cas(fl.t_remove, tail, mask(tail + n)) then
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
   return sync.cas(fl.t_add, tail, mask(tail + n))
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
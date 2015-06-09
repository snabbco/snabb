-- counter.lua - Count discrete events for diagnostic purposes
-- 
-- This module provides a thin layer for representing 64-bit counters
-- as shared memory objects.
--
-- Counters let you efficiently count discrete events (packet drops,
-- etc) and are accessible as shared memory from other processes such
-- as monitoring tools. Counters hold 64-bit unsigned integers.
-- 
-- Use counters to make troubleshooting easier. For example, if there
-- are several reasons that an app could drop a packet then you can
-- use counters to keep track of why this is actually happening.
--
-- You can access the counters using this module, or the raw core.shm
-- module, or even directly on disk. Each counter is an 8-byte ramdisk
-- file that contains the 64-bit value in native host endian.
--
-- For example, you can read a counter on the command line with od(1):
-- 
--     # od -A none -t u8 /var/run/snabb/15347/counter/a
--     43


module(..., package.seeall)

local shm = require("core.shm")
local ffi = require("ffi")
local counter_t = ffi.typeof("struct { uint64_t c; }")

function open (name)          return shm.map(name, counter_t) end
function set (counter, value) counter.c = value               end
function add (counter, value) counter.c = counter.c + value   end
function read (counter)       return counter.c                end

function selftest ()
   print("selftest: core.counter")
   local a  = open("core.counter/counter/a")
   local b  = open("core.counter/counter/b")
   local a2 = open("core.counter/counter/a")
   set(a, 42)
   set(b, 43)
   assert(read(a) == 42)
   assert(read(b) == 43)
   assert(read(a) == read(a2))
   add(a, 1)
   assert(read(a) == 43)
   assert(read(a) == read(a2))
   shm.unlink("core.counter")
   print("selftest ok")
end


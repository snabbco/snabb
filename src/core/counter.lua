-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

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

local lib = require("core.lib")
local shm = require("core.shm")
local ffi = require("ffi")
require("core.counter_h")

type = shm.register('counter', getfenv())

local counter_t = ffi.typeof("struct counter")

-- Double buffering:
-- For each counter we have a private copy to update directly and then
-- a public copy in shared memory that we periodically commit to.
--
-- This is important for a subtle performance reason: the shared
-- memory counters all have page-aligned addresses (thanks to mmap)
-- and accessing many of them can lead to expensive cache misses (due
-- to set-associative CPU cache). See snabbco/snabb#558.
local public  = {}
local private = {}
local numbers = {} -- name -> number

function create (name, initval)
   if numbers[name] then return private[numbers[name]] end
   local n = #public+1
   public[n] = shm.create(name, counter_t)
   private[n] = ffi.new(counter_t)
   numbers[name] = n
   if initval then set(private[n], initval) end
   return private[n]
end

function open (name)
   if numbers[name] then return private[numbers[name]] end
   local n = #public+1
   public[n] = shm.open(name, counter_t, 'readonly')
   private[n] = public[#public] -- use counter directly
   numbers[name] = n
   return private[n]
end

function delete (name)
   local number = numbers[name]
   if not number then error("counter not found for deletion: " .. name) end
   -- Free shm object
   shm.unmap(public[number])
   -- If we "own" the counter for writing then we unlink it too.
   if public[number] ~= private[number] then
      shm.unlink(name)
   end
   -- Free local state
   numbers[name] = false
   public[number] = false
   private[number] = false
end

-- Copy counter private counter values to public shared memory.
function commit ()
   for i = 1, #public do
      if public[i] ~= private[i] then public[i].c = private[i].c end
   end
end

function set  (counter, value) counter.c = value                         end
function add  (counter, value) counter.c = counter.c + (value or 1)      end
function read (counter)        return counter.c                          end

ffi.metatype( counter_t,
              {__tostring =
               function (counter) return lib.comma_value(counter.c) end})

function selftest ()
   print("selftest: core.counter")
   local a  = create("core.counter/counter/a")
   local b  = create("core.counter/counter/b")
   local a2 = shm.create("core.counter/counter/a", counter_t, true)
   set(a, 42)
   set(b, 43)
   assert(read(a) == 42)
   assert(read(b) == 43)
   commit()
   assert(read(a) == a2.c)
   add(a, 1)
   assert(read(a) == 43)
   commit()
   assert(read(a) == a2.c)
   shm.unlink("core.counter")
   print("selftest ok")
end


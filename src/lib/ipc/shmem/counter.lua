-- The counter subclass of lib.ipc.shmem.shmem manages a shared memory
-- mapping dedicated to counters.  It defines the name space "Counter"
-- and contains exclusively unsigned 64-bit objects.  Because all
-- objects are of the same type, the index file for this name space
-- contains only the names of the objects.  The type (uint64_t) and
-- length (8 bytes) is implied.
--
-- The procedural interface can be used to avoid method-call overhead.
-- The set of counters may also be accessed by treating the entire
-- segment as an array of doubles
--
--  local array = ffi.cast("uint64_t *", counter:base())
--  array[i] = ...
--
module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local shmem = require("lib.ipc.shmem.shmem")

local counter = subClass(shmem)
counter._name = "Counter shared memory"
counter._namespace = "Counter:1"
-- Suppress the length field in the index file
counter._fs = ''

local uint64_t = ffi.typeof("uint64_t")
function counter:register (name, value)
   return counter:superClass().register(self, name, uint64_t, value)
end

function counter:add (name, value)
   add(self:ptr(name), value)
end

-- Procedural interface

function add (counter, value)
   counter[0] = counter[0] + value
end

function get (counter)
   return counter[0]
end

function set (counter, value)
   counter[0] = value
end

return counter

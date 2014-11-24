-- counter.lua -- Counters for system-wide statistics and diagnostics
module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

require("core.counter_h")

-- This module provides a counter object for tracking system statistics.
-- Each counter has a name (string) and a value (double).
-- 
-- Counters are efficient so that you can use them on the fast path.
-- They are represented as FFI double objects and should be updatable
-- with a single atomic x86 ADD instruction.
--
-- Counters are available to external processes. The counter array is
-- stored in file-backed shared memory. A monitoring application can
-- access counters as shared memory (for realtime access) or as plain
-- files (for archiving).
--
-- *** FILE FORMAT ***
--
-- Counters are stored in two files: the index file (text) containing
-- the names of the counters and the counter file (binary) containing
-- the values.
--
-- The index file contains a series of lines. The first line is the
-- file format version number ("1.0") and the following lines are the
-- names each counter in sequence. Lines are written to the file
-- incrementally over time as new counters are defined. Here is a
-- small example index file:
--
--   1.0
--   buffer.total_buffers
--   buffer.free_buffers
--   engine.configuration
--   engine.ingress_packets
--   engine.egress_packets
--   engine.cpu_cycles{class:VhostUser}
--   engine.cpu_cycles{class:Intel10G}
--
-- The counters file contains the value of each counter as an 8-byte
-- IEEE double. The file can be treated as an array of double floats.
-- Counters appear in the order given in the index file.

local array                -- Counter values (memory-mapped FFI double[])
local max                  -- Maximum number of counters (array size)
local map = {}             -- Mapping from counter name to FFI 'double *'
local index                -- Index file where counter names are written
local next = 0             -- Next available counter index

-- Initialize the counter module.
function initialize (options)
   map = {}
   next = 0
   local stat_filename = options.filename or ("/tmp/snabb-counters.%d"):format(C.getpid())
   local index_filename = options.index_filename or stat_filename..".index"
   local NaN = 0/0
   max = options.max_counters or 10000
   array = C.counter_mmap_file(stat_filename, max * 8, NaN)
   if array == nil then
      print("Failed to create file backing for counter memory.")
      array = ffi.new("double[?]", max)
   else
      index = io.open(index_filename, 'w')
      if not index then
         print("Failed to create counter index file")
      else
         index:write("1.0\n")
         index:flush()
      end
   end
end

-- Return a counter by name. Create it if it does not already exist.
function named (name)
   if not map[name] then map[name] = new(name) end
   return map[name]
end

-- Return the index of a new counter called NAME.
function new (name)
   if not array then initialize({}) end
   local c
   if next < max then
      next = next + 1
      c = array + (next-1)
   else
      -- Fall back to normal heap memory once shared region is exhausted
      c = ffi.new("double[1]")
   end
   index:write(name,"\n")  
   index:flush()
   c[0] = 0
   return c
end

-- Add a value to a counter
function add (counter, value)
   counter[0] = counter[0] + value
end

-- Set an exact value for a counter
function set (counter, value)
   counter[0] = value
end

function selftest ()
   print("selftest: counter")
   initialize({filename = "snabb-counters.selftest"})
   for i = 1, 100000 do
      local name = "Counter"..tostring(i)
      local c = named(name)
      set(c, i)
   end
   local ifile = assert(io.open("snabb-counters.selftest.index", "r"))
   local cfile = assert(io.open("snabb-counters.selftest", "r"))
   local l = ifile:read('*l')
   -- Check version
   assert(l == '1.0')
   -- Check names
   for line in ifile:lines() do
      assert(map[line])
   end
   local stats = ffi.cast('double *', cfile:read('*a'))
   -- Check values
   for i = 0, max-1 do
      assert(stats[i] == array[i])
   end
   os.remove("snabb-counters.selftest.index")
   os.remove("snabb-counters.selftest")
   print("ok")
end


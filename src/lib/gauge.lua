-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local shm = require("core.shm")

-- SHM object type for gauges (double precision float values).

type = shm.register('gauge', getfenv())

local gauge_t = ffi.typeof("struct { double g; }")

function create (name, initval)
   local gauge = shm.create(name, gauge_t)
   set(gauge, initval or 0)
   return gauge
end

function open (name)
   return shm.open(name, gauge_t, 'readonly')
end

function set  (gauge, value) gauge.g = value end
function read (gauge) return gauge.g         end

ffi.metatype(gauge_t,
             {__tostring =
              function (gauge) return ("%f"):format(read(gauge)) end})

function selftest ()
   print('selftest: lib.gauge')
   local a = create("lib.gauge/gauge/a", 1.42)
   local a2 = open("lib.gauge/gauge/a")
   local b = create("lib.gauge/gauge/b")
   assert(read(a) == 1.42)
   assert(read(a2) == read(a))
   assert(read(b) == 0)
   assert(read(a) ~=  read(b))
   set(a, 0.1234)
   assert(read(a) == 0.1234)
   assert(read(a2) == read(a))
   shm.unmap(a)
   shm.unmap(a2)
   shm.unmap(b)
   shm.unlink("link.gauge")
   print('selftest: ok')
end

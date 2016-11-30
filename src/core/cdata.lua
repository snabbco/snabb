-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- cdata.lua - Store different kinds of Lua values in SHM objects using ctypes.
-- Semantics / conversions are as described here:
-- http://luajit.org/ext_ffi_semantics.html
--
-- Example:
--
--  local cdata = require("core.cdata")
--  local n = cdata.create("num.double", math.pi)
--  local n2 = cdata.open("num.double")
--  cdata.set(n, 2*math.pi)
--  cdata.read(n2) => 6.2831853071796
--
--  local shm = require("core.shm")
--  local frame = shm.create_frame("myframe", {pi = {cdata.double, math.pi}})

module(..., package.seeall)

local shm = require("core.shm")
local ffi = require("ffi")
local cdata = getfenv()


for _, ctype in ipairs({ 'int8_t', 'uint8_t', 'int16_t', 'uint16_t',
                         'int32_t', 'uint32_t', 'int64_t', 'uint64_t',
                         'float', 'double', 'bool' }) do
   cdata[ctype] = {}
   cdata[ctype].type = shm.register(ctype, cdata[ctype])
   cdata[ctype].create = function (name, initval)
      local cdata = shm.create(name, ctype.."[1]")
      if initval then cdata[0] = initval end
      return cdata
   end
   cdata[ctype].open = function (name)
      return shm.open(name, ctype.."[1]", 'readonly')
   end
end

function set  (cdata, value) cdata[0] = value end
function read (cdata) return cdata[0] end


function create (name, initval)
   local _, type = name:match("(.*)[.](.*)$")
   return assert(cdata[type], "Unsupported type: "..type).create(name, initval)
end

function open (name)
   local _, type = name:match("(.*)[.](.*)$")
   return assert(cdata[type], "Unsupported type: "..type).open(name)
end


function selftest ()
   local d = create("d.double")
   set(d, math.pi)
   local d2 = open("d.double")
   assert(math.pi == read(d2))
   local i64 = 10000000ULL
   local i = create("i.int64_t", i64)
   assert(read(i) == i64)
   local b = create("b.bool", true)
   assert(read(b) == true)
   set(b, false)
   assert(read(b) == false)
   local f = shm.create_frame("test", {pi = {cdata.double, math.pi}})
   local f2 = shm.open_frame("test")
   assert(read(f2.pi) == math.pi)
end

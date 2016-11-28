-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- cdata.lua - Store different kinds of Lua values in SHM objects using ctypes.
-- Semantics / conversions are as described here:
-- http://luajit.org/ext_ffi_semantics.html
--
-- Example:
--
--  local n = create("num", 'double', math.pi)
--  set(n, 2*math.pi)
--  read(n) => number

module(..., package.seeall)

local shm = require("core.shm")
local ffi = require("ffi")
local C = ffi.C
require("core.cdata_h")

type = shm.register('cdata', getfenv())

local cdata_t = ffi.typeof("struct cdata")

local ctypes = {
   int8_t  = C.I8,    uint8_t  = C.U8,
   int16_t = C.I16,   uint16_t = C.U16,
   int32_t = C.I32,   uint32_t = C.U32,
   int64_t = C.I64,   uint64_t = C.U64,
   float   = C.FLOAT, double   = C.DOUBLE,
   bool    = C.BOOL
}

local union = {
   [C.I8]    = 'i8',    [C.U8]     = 'u8',
   [C.I16]   = 'i16',   [C.U16]    = 'u16',
   [C.I32]   = 'i32',   [C.U32]    = 'u32',
   [C.I64]   = 'i64',   [C.U64]    = 'u64',
   [C.FLOAT] = 'f',     [C.DOUBLE] = 'd',
   [C.BOOL]  = 'b'
}

local function slot (type) return union[tonumber(type)] end

function create (name, type, initval)
   local type = assert(ctypes[type], "Unsupported type: "..type)
   local cdata = shm.create(name, cdata_t)
   cdata.type = type
   if initval then
      cdata[slot(type)] = initval
   end
   return cdata
end


function open (name)
   return shm.open(name, cdata_t, 'readonly')
end

function set  (cdata, value) cdata[slot(cdata.type)] = value end
function read (cdata) return cdata[slot(cdata.type)] end

function selftest ()
   local d = create("d", "double")
   set(d, math.pi)
   local d2 = open("d")
   assert(math.pi == read(d2))
   local i64 = 10000000ULL
   local i = create("i", "int64_t", i64)
   assert(read(i) == i64)
   local b = create("b", "bool", true)
   assert(read(b) == true)
   set(b, false)
   assert(read(b) == false)
end

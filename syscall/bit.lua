-- abstract different bit libraries in different lua versions

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

-- TODO add 64 bit operations here

local ffi = require "ffi"

local abi = require "syscall.abi"

local ok, bit

ok, bit = pcall(require, "bit")

if not ok then
  ok, bit = pcall(require, "bit32")

  local int32 = ffi.typeof("int32_t")

  if not ok then error("no suitable bit library found") end

  -- fixups to make compatible with luajit
  bit.tobit = function(x) return tonumber(int32(x)) end
  bit.bswap = function(x)
    return bit.bor(bit.lshift(bit.extract(x, 0, 8), 24),
                     bit.lshift(bit.extract(x, 8, 8), 16),
                     bit.lshift(bit.extract(x, 16, 8), 8),
                                bit.extract(x, 24, 8))
    end
end

-- 64 to 32 bit conversions via unions TODO use meth not object? tidy up
local mt
if abi.le then
mt = {
  __index = {
    to32 = function(u) return u.i32[1], u.i32[0] end,
  }
}
else
mt = {
  __index = {
    to32 = function(u) return u.i32[0], u.i32[1] end,
  }
}
end

mt.__new = function(tp, x)
  local n = ffi.new(tp)
  n.i64 = x or 0
  return n
end

local i6432 = ffi.metatype("union {int64_t i64; int32_t i32[2];}", mt)
local u6432 = ffi.metatype("union {uint64_t i64; uint32_t i32[2];}", mt)

bit.i6432 = function(x) return i6432(x):to32() end
bit.u6432 = function(x) return u6432(x):to32() end

-- initial 64 bit ops. TODO for luajit 2.1 these are not needed, as accepts 64 bit cdata
function bit.bor64(a, b) -- TODO support more arguments
  local aa, bb, cc = i6432(a), i6432(b), i6432()
  cc.i32[0], cc.i32[1] = bit.bor(aa.i32[0], bb.i32[0]), bit.bor(aa.i32[1], bb.i32[1])
  return cc.i64
end

function bit.band64(a, b) -- TODO support more arguments
  local aa, bb, cc = i6432(a), i6432(b), i6432()
  cc.i32[0], cc.i32[1] = bit.band(aa.i32[0], bb.i32[0]), bit.band(aa.i32[1], bb.i32[1])
  return cc.i64
end

return bit

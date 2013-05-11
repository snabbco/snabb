-- BSD types

return function(types, hh)

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ptt, addtype, lenfn, lenmt, newfn, istype = hh.ptt, hh.addtype, hh.lenfn, hh.lenmt, hh.newfn, hh.istype

local ffi = require "ffi"
local bit = require "bit"

require "syscall.ffitypes"

local h = require "syscall.helpers"

local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local c = require "syscall.constants"

local abi = require "syscall.abi"

local mt = {} -- metatables
local meth = {}

-- 32 bit dev_t, 24 bit minor, 8 bit major
mt.device = {
  __index = {
    major = function(dev) return bit.bor(bit.band(bit.rshift(dev:device(), 24), 0xff)) end,
    minor = function(dev) return bit.band(dev:device(), 0xffffff) end,
    device = function(dev) return tonumber(dev.dev) end,
  },
}

t.device = function(major, minor)
  local dev = major
  if minor then dev = bit.bor(minor, bit.lshift(major, 24)) end
  return setmetatable({dev = t.dev(dev)}, mt.device)
end

return types

end


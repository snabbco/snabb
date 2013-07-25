-- NetBSD utility functions

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(S)

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local h = require "syscall.helpers"

local ffi = require "ffi"

local octal = h.octal

-- TODO move to helpers? see notes in syscall.lua about reworking though
local function istype(tp, x)
  if ffi.istype(tp, x) then return x end
  return false
end

local util = {}

local mt = {}

-- initial implementation of network ioctls, no real attempt to make it compatible with Linux...
-- initially just implement the ones from rump netconfig, make interface later

local function sockioctl(domain, tp, io, data)
  local sock, err = S.socket(domain, tp)
  if not sock then return nil, err end
  local io, err = sock:ioctl(io, data)
  if not io then
    sock:close()
    return nil, err
  end
  local ok, err = sock:close()
  if not ok then return nil, err end
  return io
end

function util.ifcreate(name) return sockioctl("inet", "dgram", "SIOCIFCREATE", t.ifreq{name = name}) end
function util.ifdestroy(name) return sockioctl("inet", "dgram", "SIOCIFDESTROY", t.ifreq{name = name}) end
function util.ifgetflags(name)
  local io, err = sockioctl("inet", "dgram", "SIOCGIFFLAGS")
  if not io then return nil, err end
  return io.flags
end
function util.ifsetflags(name, flags)
  return sockioctl("inet", "dgram", "SIOCSIFFLAGS", {name = name, flags = c.IFF[flags]})
end
function util.ifup(name)
  local flags, err = util.ifgetflags(name)
  if not flags then return nil, err end
  return util.ifsetflags(name, c.IFF(flags, "up"))
end

return util

end

return {init = init}


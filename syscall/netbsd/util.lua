-- NetBSD utility functions

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

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
function util.ifcreate(name) -- TODO generic function that creates socket to do ioctl
  local sock, err = S.socket("inet", "dgram")
  if not sock then return nil, err end
  local ifr = t.ifreq{name = name}
  local io, err = sock:ioctl("SIOCIFCREATE", ifr)
  local ok, err = sock:close()
  if not ok then return nil, err end
  return true
end

return util

end

return {init = init}


-- BSD shared types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(c, types)

local abi = require "syscall.abi"

local t, pt, s, ctypes = types.t, types.pt, types.s, types.ctypes

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = require "syscall.helpers"

local addtype, addtype_var, addtype_fn, addraw2 = h.addtype, h.addtype_var, h.addtype_fn, h.addraw2
local ptt, reviter, mktype, istype, lenfn, lenmt, getfd, newfn
  = h.ptt, h.reviter, h.mktype, h.istype, h.lenfn, h.lenmt, h.getfd, h.newfn
local ntohl, ntohl, ntohs, htons = h.ntohl, h.ntohl, h.ntohs, h.htons

local mt = {} -- metatables

local addtypes = {
}

local addstructs = {
  flock = "struct flock",
}

for k, v in pairs(addtypes) do addtype(types, k, v) end
for k, v in pairs(addstructs) do addtype(types, k, v, lenmt) end

mt.sockaddr_un = {
  index = {
    family = function(sa) return sa.sun_family end,
    path = function(sa) return ffi.string(sa.sun_path) end,
  },
  newindex = {
    family = function(sa, v) sa.sun_family = v end,
    path = function(sa, v) ffi.copy(sa.sun_path, v) end,
  },
  __new = function(tp, path) return newfn(tp, {family = c.AF.UNIX, path = path, sun_len = s.sockaddr_un}) end,
  __len = function(sa) return 2 + #sa.path end,
}

addtype(types, "sockaddr_un", "struct sockaddr_un", mt.sockaddr_un)

function t.sa(addr, addrlen) return addr end -- non Linux is trivial, Linux has odd unix handling

return types

end

return {init = init}


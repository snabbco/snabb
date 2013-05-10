-- Linux kernel types

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

local C = ffi.C -- for inet_pton etc, TODO due to be replaced with Lua

local mt = {} -- metatables
local meth = {}

return types


-- FreeBSD fcntl
-- TODO incomplete, lots missing

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local c = require "syscall.osx.constants"

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local h = require "syscall.helpers"

local ctobool, booltoc = h.ctobool, h.booltoc

local fcntl = {
}

return fcntl

end

return {init = init}


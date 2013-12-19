-- ioctls, filling in as needed

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local s = types.s

local strflag = require("syscall.helpers").strflag
local bit = require "syscall.bit"

local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + 4294967296ULL end -- TODO see note in NetBSD
  return r
end
local lshift = bit.lshift
local rshift = bit.rshift

local ioctl = strflag {
}

return ioctl

end

return {init = init}


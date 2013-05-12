-- ioctls, filling in as needed

-- include types to get sizes
local types = require "syscall.types"
local s, t = types.s, types.t

local strflag = require("syscall.helpers").strflag

local abi = require "syscall.abi"

local ffi = require "ffi"
local ok, arch = pcall(require, "linux." .. abi.arch .. ".ioctl") -- architecture specific definitions
if not ok then arch = {} end

local bit = require "bit"

local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + t.int64(4294967296) end
  return r
end
local lshift = bit.lshift
local rshift = bit.rshift

local ioctl = strflag {
}

return ioctl


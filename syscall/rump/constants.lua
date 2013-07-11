-- these are constants for rump kernel
-- note these are internal constants, all the OS constants are NetBSD ones

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local h = require "syscall.helpers"

local octal, multiflags, charflags, swapflags, strflag, atflag, modeflags
  = h.octal, h.multiflags, h.charflags, h.swapflags, h.strflag, h.atflag, h.modeflags

local c = {}

c.ETFS = strflag {
  REG = 0,
  BLK = 1,
  CHR = 2,
  DIR = 3,
  DIR_SUBDIRS = 4,
}

return c


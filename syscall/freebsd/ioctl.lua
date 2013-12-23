-- ioctls, filling in as needed

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local s, t = types.s, types.t

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

local IOC = {
  VOID  = 0x20000000,
  OUT   = 0x40000000,
  IN    = 0x80000000,
  PARM_SHIFT  = 13,
}

IOC.PARM_MASK = lshift(1, IOC.PARM_SHIFT) - 1
IOC.INOUT = IOC.IN + IOC.OUT
IOC.DIRMASK = IOC.IN + IOC.OUT + IOC.VOID

local function ioc(dir, ch, nr, size)
  return t.ulong(bor(dir,
                 lshift(band(size, IOC.PARM_MASK), 16),
                 lshift(ch, 8),
                 nr))
end

local singletonmap = {
  int = "int1",
  char = "char1",
  uint = "uint1",
  uint64 = "uint64_1",
}

local function _IOC(dir, ch, nr, tp)
  if type(ch) == "string" then ch = ch:byte() end
  if type(tp) == "number" then return ioc(dir, ch, nr, tp) end
  local size = s[tp]
  local singleton = singletonmap[tp] ~= nil
  tp = singletonmap[tp] or tp
  return {number = ioc(dir, ch, nr, size),
          read = dir == IOC.OUT or dir == IOC.INOUT, write = dir == IOC.IN or dir == IOC.INOUT,
          type = t[tp], singleton = singleton}
end

local _IO     = function(ch, nr)     return _IOC(IOC.VOID, ch, nr, 0) end
local _IOR    = function(ch, nr, tp) return _IOC(IOC.OUT, ch, nr, tp) end
local _IOW    = function(ch, nr, tp) return _IOC(IOC.IN, ch, nr, tp) end
local _IOWR   = function(ch, nr, tp) return _IOC(IOC.INOUT, ch, nr, tp) end
local _IOWINT = function(ch, nr)     return _IOC(IOC.VOID, ch, nr, "int") end

local ioctl = strflag {
  TIOCPTMASTER = _IO('t', 28),

-- allow user defined ioctls
  _IO = _IO,
  _IOR = _IOR, 
  _IOW = _IOW,
  _IOWR = _IOWR,
  _IOWINT = _IOWINT,
}

return ioctl

end

return {init = init}


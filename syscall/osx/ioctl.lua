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

local ioctl = strflag {
  -- tty ioctls
  TIOCEXCL       =  _IO('t', 13),
  TIOCNXCL       =  _IO('t', 14),
  TIOCFLUSH      = _IOW('t', 16, "int"),
  TIOCGETA       = _IOR('t', 19, "termios"),
  TIOCSETA       = _IOW('t', 20, "termios"),
  TIOCSETAW      = _IOW('t', 21, "termios"),
  TIOCSETAF      = _IOW('t', 22, "termios"),
  TIOCGETD       = _IOR('t', 26, "int"),
  TIOCSETD       = _IOW('t', 27, "int"),
  TIOCGDRAINWAIT = _IOR('t', 86, "int"),
  TIOCSDRAINWAIT = _IOW('t', 87, "int"),
  TIOCTIMESTAMP  = _IOR('t', 89, "timeval"),
  TIOCMGDTRWAIT  = _IOR('t', 90, "int"),
  TIOCMSDTRWAIT  = _IOW('t', 91, "int"),
  TIOCDRAIN      =  _IO('t', 94),
  TIOCSIG        = _IOWINT('t', 95),
  TIOCEXT        = _IOW('t', 96, "int"),
  TIOCSCTTY      =  _IO('t', 97),
  TIOCCONS       = _IOW('t', 98, "int"),
  TIOCGSID       = _IOR('t', 99, "int"),
  TIOCSTAT       =  _IO('t', 101),
  TIOCUCNTL      = _IOW('t', 102, "int"),
  TIOCSWINSZ     = _IOW('t', 103, "winsize"),
  TIOCGWINSZ     = _IOR('t', 104, "winsize"),
  TIOCMGET       = _IOR('t', 106, "int"),
  TIOCMBIC       = _IOW('t', 107, "int"),
  TIOCMBIS       = _IOW('t', 108, "int"),
  TIOCMSET       = _IOW('t', 109, "int"),
  TIOCSTART      =  _IO('t', 110),
  TIOCSTOP       =  _IO('t', 111),
  TIOCPKT        = _IOW('t', 112, "int"),
  TIOCNOTTY      =  _IO('t', 113),
  TIOCSTI        = _IOW('t', 114, "char"),
  TIOCOUTQ       = _IOR('t', 115, "int"),
  TIOCSPGRP      = _IOW('t', 118, "int"),
  TIOCGPGRP      = _IOR('t', 119, "int"),
  TIOCCDTR       =  _IO('t', 120),
  TIOCSDTR       =  _IO('t', 121),
  TIOCCBRK       =  _IO('t', 122),
  TIOCSBRK       =  _IO('t', 123),
}

return ioctl

end

return {init = init}


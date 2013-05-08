-- ioctls, filling in as needed
-- note there are some architecture dependent values

-- include types to get sizes
local types = require "syscall.types"
local s, t = types.s, types.t

local strflag = require("syscall.helpers").strflag

local abi = require "syscall.abi"

local ffi = require "ffi"
local ok, arch = pcall(require, "syscall." .. abi.arch .. ".ioctl") -- architecture specific definitions
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

-- these can vary by architecture
local IOC = arch.IOC or {
  SIZEBITS = 14,
  DIRBITS = 2,
  NONE = 0,
  WRITE = 1,
  READ = 2,
}

IOC.READWRITE = IOC.READ + IOC.WRITE

IOC.NRBITS	= 8
IOC.TYPEBITS	= 8

IOC.NRMASK	= lshift(1, IOC.NRBITS) - 1
IOC.TYPEMASK	= lshift(1, IOC.TYPEBITS) - 1
IOC.SIZEMASK	= lshift(1, IOC.SIZEBITS) - 1
IOC.DIRMASK	= lshift(1, IOC.DIRBITS) - 1

IOC.NRSHIFT   = 0
IOC.TYPESHIFT = IOC.NRSHIFT + IOC.NRBITS
IOC.SIZESHIFT = IOC.TYPESHIFT + IOC.TYPEBITS
IOC.DIRSHIFT  = IOC.SIZESHIFT + IOC.SIZEBITS

local function _IOC(dir, tp, nr, size)
  if type(tp) == "string" then tp = tp:byte() end
  return bor(lshift(dir, IOC.DIRSHIFT), 
	 lshift(tp, IOC.TYPESHIFT), 
	 lshift(nr, IOC.NRSHIFT), 
	 lshift(size, IOC.SIZESHIFT))
end

-- used to create numbers
local _IO    = function(tp, nr)		return _IOC(IOC.NONE, tp, nr, 0) end
local _IOR   = function(tp, nr, size)	return _IOC(IOC.READ, tp, nr, size) end
local _IOW   = function(tp, nr, size)	return _IOC(IOC.WRITE, tp, nr, size) end
local _IOWR  = function(tp, nr, size)	return _IOC(IOC.READWRITE, tp, nr, size) end

-- used to decode ioctl numbers..
local _IOC_DIR  = function(nr) return band(rshift(nr, IOC.DIRSHIFT), IOC.DIRMASK) end
local _IOC_TYPE = function(nr) return band(rshift(nr, IOC.TYPESHIFT), IOC.TYPEMASK) end
local _IOC_NR   = function(nr) return band(rshift(nr, IOC.NRSHIFT), IOC.NRMASK) end
local _IOC_SIZE = function(nr) return band(rshift(nr, IOC.SIZESHIFT), IOC.SIZEMASK) end

-- ...and for the drivers/sound files...

IOC.IN		= lshift(IOC.WRITE, IOC.DIRSHIFT)
IOC.OUT		= lshift(IOC.READ, IOC.DIRSHIFT)
IOC.INOUT		= lshift(bor(IOC.WRITE, IOC.READ), IOC.DIRSHIFT)
local IOCSIZE_MASK	= lshift(IOC.SIZEMASK, IOC.SIZESHIFT)
local IOCSIZE_SHIFT	= IOC.SIZESHIFT

local ioctl = strflag {
-- termios, non standard values generally 0x54 = 'T'
  TCGETS          = 0x5401,
  TCSETS          = 0x5402,
  TCSETSW         = 0x5403,
  TCSETSF         = 0x5404,
  TCGETA          = 0x5405,
  TCSETA          = 0x5406,
  TCSETAW         = 0x5407,
  TCSETAF         = 0x5408,
  TCSBRK          = 0x5409,
  TCXONC          = 0x540A,
  TCFLSH          = 0x540B,
  TIOCEXCL        = 0x540C,
  TIOCNXCL        = 0x540D,
  TIOCSCTTY       = 0x540E,
  TIOCGPGRP       = 0x540F,
  TIOCSPGRP       = 0x5410,
  TIOCOUTQ        = 0x5411,
  TIOCSTI         = 0x5412,
  TIOCGWINSZ      = 0x5413,
  TIOCSWINSZ      = 0x5414,
  TIOCMGET        = 0x5415,
  TIOCMBIS        = 0x5416,
  TIOCMBIC        = 0x5417,
  TIOCMSET        = 0x5418,
  TIOCGSOFTCAR    = 0x5419,
  TIOCSSOFTCAR    = 0x541A,
  FIONREAD        = 0x541B,
  TIOCLINUX       = 0x541C,
  TIOCCONS        = 0x541D,
  TIOCGSERIAL     = 0x541E,
  TIOCSSERIAL     = 0x541F,
  TIOCPKT         = 0x5420,
  FIONBIO         = 0x5421,
  TIOCNOTTY       = 0x5422,
  TIOCSETD        = 0x5423,
  TIOCGETD        = 0x5424,
  TCSBRKP         = 0x5425,
  TIOCSBRK        = 0x5427,
  TIOCCBRK        = 0x5428,
  TIOCGSID        = 0x5429,
  TCGETS2         = _IOR('T', 0x2A, s.termios2),
  TCSETS2         = _IOW('T', 0x2B, s.termios2),
  TCSETSW2        = _IOW('T', 0x2C, s.termios2),
  TCSETSF2        = _IOW('T', 0x2D, s.termios2),
  TIOCGRS485      = 0x542E,
  TIOCSRS485      = 0x542F,
  TIOCGPTN        = _IOR('T', 0x30, s.uint),
  TIOCSPTLCK      = _IOW('T', 0x31, s.int),
  TIOCGDEV        = _IOR('T', 0x32, s.uint),
  TCGETX          = 0x5432,
  TCSETX          = 0x5433,
  TCSETXF         = 0x5434,
  TCSETXW         = 0x5435,
  TIOCSIG         = _IOW('T', 0x36, s.int),
  TIOCVHANGUP     = 0x5437,
  FIONCLEX        = 0x5450,
  FIOCLEX         = 0x5451,
  FIOASYNC        = 0x5452,
  TIOCSERCONFIG   = 0x5453,
  TIOCSERGWILD    = 0x5454,
  TIOCSERSWILD    = 0x5455,
  TIOCGLCKTRMIOS  = 0x5456,
  TIOCSLCKTRMIOS  = 0x5457,
  TIOCSERGSTRUCT  = 0x5458,
  TIOCSERGETLSR   = 0x5459,
  TIOCSERGETMULTI = 0x545A,
  TIOCSERSETMULTI = 0x545B,
  TIOCMIWAIT      = 0x545C,
  TIOCGICOUNT     = 0x545D,
  FIOQSIZE        = 0x5460,
-- network ioctls (from the pre-netlink tools) from linux/sockios.h
  SIOCGIFINDEX    = 0x8933,

  SIOCBRADDBR     = 0x89a0,
  SIOCBRDELBR     = 0x89a1,
  SIOCBRADDIF     = 0x89a2,
  SIOCBRDELIF     = 0x89a3,
-- event system
  EVIOCGVERSION   = _IOR('E', 0x01, s.int),
  EVIOCGID        = _IOR('E', 0x02, s.input_id),
  EVIOCGREP       = _IOR('E', 0x03, s.uint2),
  EVIOCSREP       = _IOW('E', 0x03, s.uint2),
  EVIOCGKEYCODE   = _IOR('E', 0x04, s.uint2),
  EVIOCGKEYCODE_V2 = _IOR('E', 0x04, s.input_keymap_entry),
  EVIOCSKEYCODE   = _IOW('E', 0x04, s.uint2),
  EVIOCSKEYCODE_V2 = _IOW('E', 0x04, s.input_keymap_entry),
  EVIOCGNAME = function(len) return _IOC(IOC.READ, 'E', 0x06, len) end,
  EVIOCGPHYS = function(len) return _IOC(IOC.READ, 'E', 0x07, len) end,
  EVIOCGUNIQ = function(len) return _IOC(IOC.READ, 'E', 0x08, len) end,
  EVIOCGPROP = function(len) return _IOC(IOC.READ, 'E', 0x09, len) end,
  EVIOCGKEY  = function(len) return _IOC(IOC.READ, 'E', 0x18, len) end,
  EVIOCGLED  = function(len) return _IOC(IOC.READ, 'E', 0x19, len) end,
  EVIOCGSND  = function(len) return _IOC(IOC.READ, 'E', 0x1a, len) end,
  EVIOCGSW   = function(len) return _IOC(IOC.READ, 'E', 0x1b, len) end,
  EVIOCGBIT  = function(ev, len) return _IOC(IOC.READ, 'E', 0x20 + ev, len) end,
  EVIOCGABS  = function(abs) return _IOR('E', 0x40 + abs, s.input_absinfo) end,
  EVIOCSABS  = function(abs) return _IOW('E', 0xc0 + abs, s.input_absinfo) end,
  EVIOCSFF   = _IOC(IOC.WRITE, 'E', 0x80, s.ff_effect),
  EVIOCRMFF  = _IOW('E', 0x81, s.int),
  EVIOCGEFFECTS = _IOR('E', 0x84, s.int),
  EVIOCGRAB  = _IOW('E', 0x90, s.int),
-- tun/tap
  TUNSETNOCSUM   = _IOW('T', 200, s.int),
  TUNSETDEBUG    = _IOW('T', 201, s.int),
  TUNSETIFF      = _IOW('T', 202, s.int),
  TUNSETPERSIST  = _IOW('T', 203, s.int),
  TUNSETOWNER    = _IOW('T', 204, s.int),
  TUNSETLINK     = _IOW('T', 205, s.int),
  TUNSETGROUP    = _IOW('T', 206, s.int),
  TUNGETFEATURES = _IOR('T', 207, s.uint),
  TUNSETOFFLOAD  = _IOW('T', 208, s.uint),
  TUNSETTXFILTER = _IOW('T', 209, s.uint),
  TUNGETIFF      = _IOR('T', 210, s.uint),
  TUNGETSNDBUF   = _IOR('T', 211, s.int),
  TUNSETSNDBUF   = _IOW('T', 212, s.int),
  TUNATTACHFILTER= _IOW('T', 213, s.sock_fprog),
  TUNDETACHFILTER= _IOW('T', 214, s.sock_fprog),
  TUNGETVNETHDRSZ= _IOR('T', 215, s.int),
  TUNSETVNETHDRSZ= _IOW('T', 216, s.int),
  TUNSETQUEUE    = _IOW('T', 217, s.int),
-- allow user defined ioctls
  _IO = _IO,
  _IOR = _IOR, 
  _IOW = _IOW,
  _IOWR = _IOWR
}

local override = arch.ioctl or {}
if type(override) == "function" then override = override(_IO, _IOR, _IOW, _IOWR) end
for k, v in pairs(override) do ioctl[k] = v end

-- alternate names
ioctl.TIOCINQ = ioctl.FIONREAD

-- TODO should we export more functions?
return ioctl


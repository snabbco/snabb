-- ioctls, filling in as needed
-- note there are some architecture dependent values

-- parts adapted from https://github.com/Wiladams/LJIT2RPi/blob/master/include/ioctl.lua

local ffi = require "ffi"
local bit = require "bit"
local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + 4294967296LL end
  return r
end
local lshift = bit.lshift
local rshift = bit.rshift

-- TODO would rather not include ffi, but we need sizes so split these out into a new file
require "include.headers"

--[[
 * ioctl command encoding: 32 bits total, command in lower 16 bits,
 * size of the parameter structure in the lower 14 bits of the
 * upper 16 bits.
 * Encoding the size of the parameter structure in the ioctl request
 * is useful for catching programs compiled with old versions
 * and to avoid overwriting user space outside the user buffer area.
 * The highest 2 bits are reserved for indicating the ``access mode''.
 * NOTE: This limits the max parameter size to 16kB -1 !
--]]

--[[
 * The following is for compatibility across the various Linux
 * platforms.  The generic ioctl numbering scheme doesn't really enforce
 * a type field.  De facto, however, the top 8 bits of the lower 16
 * bits are indeed used as a type field, so we might just as well make
 * this explicit here.  Please be sure to use the decoding macros
 * below from now on.
--]]

local IOC_NRBITS	= 8
local IOC_TYPEBITS	= 8

-- Let any architecture override either of the following

local IOC_SIZEBITS	= 14
local IOC_DIRBITS	= 2

local IOC_NRMASK	= lshift(1, IOC_NRBITS) - 1
local IOC_TYPEMASK	= lshift(1, IOC_TYPEBITS) - 1
local IOC_SIZEMASK	= lshift(1, IOC_SIZEBITS) - 1
local IOC_DIRMASK	= lshift(1, IOC_DIRBITS) - 1

local IOC_NRSHIFT	= 0
local IOC_TYPESHIFT	= IOC_NRSHIFT + IOC_NRBITS
local IOC_SIZESHIFT	= IOC_TYPESHIFT + IOC_TYPEBITS
local IOC_DIRSHIFT	= IOC_SIZESHIFT + IOC_SIZEBITS

-- Direction bits, which any architecture can choose to override

local IOC_NONE	= 0
local IOC_WRITE	= 1
local IOC_READ	= 2

local function _IOC(dir, tp, nr, size)
  if type(tp) == "string" then tp = tp:byte() end
  return bor(lshift(dir, IOC_DIRSHIFT), 
	 lshift(tp, IOC_TYPESHIFT), 
	 lshift(nr, IOC_NRSHIFT), 
	 lshift(size, IOC_SIZESHIFT))
end

-- used to create numbers
local _IO 	 = function(tp, nr)		return _IOC(IOC_NONE, tp, nr, 0) end
local _IOR 	 = function(tp, nr, size)	return _IOC(IOC_READ, tp, nr, ffi.sizeof(size)) end
local _IOW 	 = function(tp, nr, size)	return _IOC(IOC_WRITE, tp, nr, ffi.sizeof(size)) end
local _IOWR	 = function(tp, nr, size)	return _IOC(bor(IOC_READ, IOC_WRITE), tp, nr, ffi.sizeof(size)) end
local _IOR_BAD   = function(tp, nr, size)	return _IOC(IOC_READ, tp, nr, ffi.sizeof(size)) end
local _IOW_BAD   = function(tp, nr, size)	return _IOC(IOC_WRITE, tp, nr, ffi.sizeof(size)) end
local _IOWR_BAD  = function(tp, nr, size)	return _IOC(bor(IOC_READ, IOC_WRITE), tp, nr, ffi.sizeof(size)) end

-- used to decode ioctl numbers..
local _IOC_DIR  = function(nr)			return band(rshift(nr, IOC_DIRSHIFT), IOC_DIRMASK) end
local _IOC_TYPE = function(nr)			return band(rshift(nr, IOC_TYPESHIFT), IOC_TYPEMASK) end
local _IOC_NR   = function(nr)			return band(rshift(nr, IOC_NRSHIFT), IOC_NRMASK) end
local _IOC_SIZE = function(nr)			return band(rshift(nr, IOC_SIZESHIFT), IOC_SIZEMASK) end

-- ...and for the drivers/sound files...

local IOC_IN		= lshift(IOC_WRITE, IOC_DIRSHIFT)
local IOC_OUT		= lshift(IOC_READ, IOC_DIRSHIFT)
local IOC_INOUT		= lshift(bor(IOC_WRITE, IOC_READ), IOC_DIRSHIFT)
local IOCSIZE_MASK	= lshift(IOC_SIZEMASK, IOC_SIZESHIFT)
local IOCSIZE_SHIFT	= IOC_SIZESHIFT

local ioctl = {
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
  --TIOCINQ         FIONREAD
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
  TCGETS2         = _IOR('T', 0x2A, "struct termios2"),
  TCSETS2         = _IOW('T', 0x2B, "struct termios2"),
  TCSETSW2        = _IOW('T', 0x2C, "struct termios2"),
  TCSETSF2        = _IOW('T', 0x2D, "struct termios2"),
  TIOCGRS485      = 0x542E,
  TIOCSRS485      = 0x542F,
  TIOCGPTN        = _IOR('T', 0x30, "unsigned int"),
  TIOCSPTLCK      = _IOW('T', 0x31, "int"),
  TIOCGDEV        = _IOR('T', 0x32, "unsigned int"),
  TCGETX          = 0x5432,
  TCSETX          = 0x5433,
  TCSETXF         = 0x5434,
  TCSETXW         = 0x5435,
  TIOCSIG         = _IOW('T', 0x36, "int"),
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
-- network ioctls
  SIOCGIFINDEX    = 0x8933,

  SIOCBRADDBR     = 0x89a0,
  SIOCBRDELBR     = 0x89a1,
  SIOCBRADDIF     = 0x89a2,
  SIOCBRDELIF     = 0x89a3,
}

return ioctl


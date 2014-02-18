-- ioctls, filling in as needed
-- note there are some architecture dependent values

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local abi = require "syscall.abi"

local s, t = types.s, types.t

local strflag = require "syscall.helpers".strflag

local arch = require("syscall.linux." .. abi.arch .. ".ioctl")

local bit = require "syscall.bit"

local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + 4294967296 end -- TODO see note in NetBSD
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

local function ioc(dir, ch, nr, size)
  if type(ch) == "string" then ch = ch:byte() end
  return bor(lshift(dir, IOC.DIRSHIFT), 
	     lshift(ch, IOC.TYPESHIFT), 
	     lshift(nr, IOC.NRSHIFT), 
	     lshift(size, IOC.SIZESHIFT))
end

local singletonmap = {
  int = "int1",
  char = "char1",
  uint = "uint1",
  uint32 = "uint32_1",
  uint64 = "uint64_1",
}

local function _IOC(dir, ch, nr, tp)
  if not tp or type(tp) == "number" then return ioc(dir, ch, nr, tp or 0) end
  local size = s[tp]
  local singleton = singletonmap[tp] ~= nil
  tp = singletonmap[tp] or tp
  return {number = ioc(dir, ch, nr, size),
          read = dir == IOC.READ or dir == IOC.READWRITE, write = dir == IOC.WRITE or dir == IOC.READWRITE,
          type = t[tp], singleton = singleton}
end

-- used to create numbers
local _IO    = function(ch, nr)		return _IOC(IOC.NONE, ch, nr, 0) end
local _IOR   = function(ch, nr, tp)	return _IOC(IOC.READ, ch, nr, tp) end
local _IOW   = function(ch, nr, tp)	return _IOC(IOC.WRITE, ch, nr, tp) end
local _IOWR  = function(ch, nr, tp)	return _IOC(IOC.READWRITE, ch, nr, tp) end

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

-- VFIO driver writer decided not to use standard IOR/IOW alas
local function vfio(dir, nr, tp)
  local ch = ";"
  nr = nr + 100 -- vfio base
  dir = IOC[string.upper(dir)]
  local io = _IOC(dir, ch, nr, tp)
  if type(io) == "number" then return io end -- if just IO, not return
  io.number = ioc(IOC.NONE, ch, nr, 0) -- number encode nothing, but we want to know anyway
  return io
end

local ioctl = strflag {
-- termios, non standard values generally 0x54 = 'T'
  TCGETS          = {number = 0x5401, read = true, type = "termios"},
  TCSETS          = 0x5402,
  TCSETSW         = 0x5403,
  TCSETSF         = 0x5404,
  TCSBRK          = 0x5409, -- takes literal number
  TCXONC          = 0x540A,
  TCFLSH          = 0x540B, -- takes literal number
  TIOCEXCL        = 0x540C,
  TIOCNXCL        = 0x540D,
  TIOCSCTTY       = 0x540E,
  TIOCGPGRP       = 0x540F,
  TIOCSPGRP       = 0x5410,
  TIOCOUTQ        = 0x5411,
  TIOCSTI         = 0x5412,
  TIOCGWINSZ      = {number = 0x5413, read = true, type = "winsize"},
  TIOCSWINSZ      = {number = 0x5414, write = true, type = "winsize"},
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
  TCGETS2         = _IOR('T', 0x2A, "termios2"),
  TCSETS2         = _IOW('T', 0x2B, "termios2"),
  TCSETSW2        = _IOW('T', 0x2C, "termios2"),
  TCSETSF2        = _IOW('T', 0x2D, "termios2"),
  TIOCGPTN        = _IOR('T', 0x30, "uint"),
  TIOCSPTLCK      = _IOW('T', 0x31, "int"),
  TIOCGDEV        = _IOR('T', 0x32, "uint"),
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
-- socket ioctls from linux/sockios.h - for many of these you can use netlink instead
  FIOSETOWN       = 0x8901,
  SIOCSPGRP       = 0x8902,
  FIOGETOWN       = 0x8903,
  SIOCGPGRP       = 0x8904,
  SIOCATMARK      = 0x8905,
  SIOCGSTAMP      = 0x8906,
  SIOCGSTAMPNS    = 0x8907,

  SIOCADDRT       = 0x890B,
  SIOCDELRT       = 0x890C,
  SIOCRTMSG       = 0x890D,

  SIOCGIFINDEX    = 0x8933,

  SIOCDARP        = 0x8953,
  SIOCGARP        = 0x8954,
  SIOCSARP        = 0x8955,

  SIOCBRADDBR     = 0x89a0,
  SIOCBRDELBR     = 0x89a1,
  SIOCBRADDIF     = 0x89a2,
  SIOCBRDELIF     = 0x89a3,
-- event system
  EVIOCGVERSION   = _IOR('E', 0x01, "int"),
  EVIOCGID        = _IOR('E', 0x02, "input_id"),
  EVIOCGREP       = _IOR('E', 0x03, "uint2"),
  EVIOCSREP       = _IOW('E', 0x03, "uint2"),
  EVIOCGKEYCODE   = _IOR('E', 0x04, "uint2"),
  EVIOCGKEYCODE_V2 = _IOR('E', 0x04, "input_keymap_entry"),
  EVIOCSKEYCODE   = _IOW('E', 0x04, "uint2"),
  EVIOCSKEYCODE_V2 = _IOW('E', 0x04, "input_keymap_entry"),
  EVIOCGNAME = function(len) return _IOC(IOC.READ, 'E', 0x06, len) end,
  EVIOCGPHYS = function(len) return _IOC(IOC.READ, 'E', 0x07, len) end,
  EVIOCGUNIQ = function(len) return _IOC(IOC.READ, 'E', 0x08, len) end,
  EVIOCGPROP = function(len) return _IOC(IOC.READ, 'E', 0x09, len) end,
  EVIOCGKEY  = function(len) return _IOC(IOC.READ, 'E', 0x18, len) end,
  EVIOCGLED  = function(len) return _IOC(IOC.READ, 'E', 0x19, len) end,
  EVIOCGSND  = function(len) return _IOC(IOC.READ, 'E', 0x1a, len) end,
  EVIOCGSW   = function(len) return _IOC(IOC.READ, 'E', 0x1b, len) end,
  EVIOCGBIT  = function(ev, len) return _IOC(IOC.READ, 'E', 0x20 + ev, len) end,
  EVIOCGABS  = function(abs) return _IOR('E', 0x40 + abs, "input_absinfo") end,
  EVIOCSABS  = function(abs) return _IOW('E', 0xc0 + abs, "input_absinfo") end,
  EVIOCSFF   = _IOC(IOC.WRITE, 'E', 0x80, "ff_effect"),
  EVIOCRMFF  = _IOW('E', 0x81, "int"),
  EVIOCGEFFECTS = _IOR('E', 0x84, "int"),
  EVIOCGRAB  = _IOW('E', 0x90, "int"),
-- input devices
  UI_DEV_CREATE  = _IO ('U', 1),
  UI_DEV_DESTROY = _IO ('U', 2),
  UI_SET_EVBIT   = _IOW('U', 100, "int"),
  UI_SET_KEYBIT  = _IOW('U', 101, "int"),
-- tun/tap
  TUNSETNOCSUM   = _IOW('T', 200, "int"),
  TUNSETDEBUG    = _IOW('T', 201, "int"),
  TUNSETIFF      = _IOW('T', 202, "int"),
  TUNSETPERSIST  = _IOW('T', 203, "int"),
  TUNSETOWNER    = _IOW('T', 204, "int"),
  TUNSETLINK     = _IOW('T', 205, "int"),
  TUNSETGROUP    = _IOW('T', 206, "int"),
  TUNGETFEATURES = _IOR('T', 207, "uint"),
  TUNSETOFFLOAD  = _IOW('T', 208, "uint"),
  TUNSETTXFILTER = _IOW('T', 209, "uint"),
  TUNGETIFF      = _IOR('T', 210, "uint"),
  TUNGETSNDBUF   = _IOR('T', 211, "int"),
  TUNSETSNDBUF   = _IOW('T', 212, "int"),
  TUNATTACHFILTER= _IOW('T', 213, "sock_fprog"),
  TUNDETACHFILTER= _IOW('T', 214, "sock_fprog"),
  TUNGETVNETHDRSZ= _IOR('T', 215, "int"),
  TUNSETVNETHDRSZ= _IOW('T', 216, "int"),
  TUNSETQUEUE    = _IOW('T', 217, "int"),
-- from linux/vhost.h VHOST_VIRTIO 0xAF
  VHOST_GET_FEATURES   = _IOR(0xAF, 0x00, "uint64"),
  VHOST_SET_FEATURES   = _IOW(0xAF, 0x00, "uint64"),
  VHOST_SET_OWNER      = _IO(0xAF, 0x01),
  VHOST_RESET_OWNER    = _IO(0xAF, 0x02),
  VHOST_SET_MEM_TABLE  = _IOW(0xAF, 0x03, "vhost_memory"),
  VHOST_SET_LOG_BASE   = _IOW(0xAF, 0x04, "uint64"),
  VHOST_SET_LOG_FD     = _IOW(0xAF, 0x07, "int"),
  VHOST_SET_VRING_NUM  = _IOW(0xAF, 0x10, "vhost_vring_state"),
  VHOST_SET_VRING_ADDR = _IOW(0xAF, 0x11, "vhost_vring_addr"),
  VHOST_SET_VRING_BASE = _IOW(0xAF, 0x12, "vhost_vring_state"),
  VHOST_GET_VRING_BASE = _IOWR(0xAF, 0x12, "vhost_vring_state"),
  VHOST_SET_VRING_KICK = _IOW(0xAF, 0x20, "vhost_vring_file"),
  VHOST_SET_VRING_CALL = _IOW(0xAF, 0x21, "vhost_vring_file"),
  VHOST_SET_VRING_ERR  = _IOW(0xAF, 0x22, "vhost_vring_file"),
  VHOST_NET_SET_BACKEND= _IOW(0xAF, 0x30, "vhost_vring_file"),
-- from linux/vfio.h type is ';' base is 100
  VFIO_GET_API_VERSION = vfio('NONE', 0),
  VFIO_CHECK_EXTENSION = vfio('WRITE', 1, "uint32"),

-- allow user defined ioctls
  _IO = _IO,
  _IOR = _IOR, 
  _IOW = _IOW,
  _IOWR = _IOWR,
}

local override = arch.ioctl or {}
if type(override) == "function" then override = override(_IO, _IOR, _IOW, _IOWR) end
for k, v in pairs(override) do ioctl[k] = v end

-- allow names for types in table ioctls
for k, v in pairs(ioctl) do if type(v) == "table" and type(v.type) == "string" then v.type = t[v.type] end end

-- alternate names
ioctl.TIOCINQ = ioctl.FIONREAD

return ioctl

end

return {init = init}


-- ioctls, filling in as needed

return function(abi, types)

local s = types.s

local strflag = require("syscall.helpers").strflag
local bit = require "bit"

local band = bit.band
local function bor(...)
  local r = bit.bor(...)
  if r < 0 then r = r + 4294967296LL end -- TODO see note in Linux
  return r
end
local lshift = bit.lshift
local rshift = bit.rshift

local IOC = {
  VOID  = 0x20000000,
  OUT   = 0x40000000,
  IN    = 0x80000000,

  DIRMASK     = 0xe0000000,
  PARM_MASK   = 0x1fff,
  PARM_SHIFT  = 16,
  GROUP_SHIFT = 8,
}

IOC.INOUT = IOC.IN + IOC.OUT

local function _IOC(dir, tp, nr, size)
  if type(size) == "string" then size = s[size] end
  if type(tp) == "string" then tp = tp:byte() end
  return bor(dir,
             lshift(band(size, IOC.PARM_MASK), IOC.PARM_SHIFT),
             lshift(tp , IOC.GROUP_SHIFT),
             nr)
end

local _IO    = function(tp, nr)		return _IOC(IOC.VOID, tp, nr, 0) end
local _IOR   = function(tp, nr, size)	return _IOC(IOC.OUT, tp, nr, size) end
local _IOW   = function(tp, nr, size)	return _IOC(IOC.IN, tp, nr, size) end
local _IOWR  = function(tp, nr, size)	return _IOC(IOC.INOUT, tp, nr, size) end

--[[
#define IOCPARM_LEN(x)  (((x) >> IOCPARM_SHIFT) & IOCPARM_MASK)
#define IOCBASECMD(x)   ((x) & ~(IOCPARM_MASK << IOCPARM_SHIFT))
#define IOCGROUP(x)     (((x) >> IOCGROUP_SHIFT) & 0xff)

#define IOCPARM_MAX     NBPG    /* max size of ioctl args, mult. of NBPG */
]]

local ioctl = strflag {
  -- socket ioctls
  SIOCSHIWAT     =  _IOW('s',  0, "int"),
  SIOCGHIWAT     =  _IOR('s',  1, "int"),
  SIOCSLOWAT     =  _IOW('s',  2, "int"),
  SIOCGLOWAT     =  _IOR('s',  3, "int"),
  SIOCATMARK     =  _IOR('s',  7, "int"),
  SIOCSPGRP      =  _IOW('s',  8, "int"),
  SIOCGPGRP      =  _IOR('s',  9, "int"),
--[[
  SIOCADDRT      =  _IOW('r', 10, "ortentry"),
  SIOCDELRT      =  _IOW('r', 11, "ortentry"),
  SIOCSIFADDR    =  _IOW('i', 12, "ifreq"),
  SIOCGIFADDR    = _IOWR('i', 33, "ifreq"),
  SIOCSIFDSTADDR =  _IOW('i', 14, "ifreq"),
  SIOCGIFDSTADDR = _IOWR('i', 34, "ifreq"),
  SIOCSIFFLAGS   =  _IOW('i', 16, "ifreq"),
  SIOCGIFFLAGS   = _IOWR('i', 17, "ifreq"),
  SIOCGIFBRDADDR = _IOWR('i', 35, "ifreq"),
  SIOCSIFBRDADDR =  _IOW('i', 19, "ifreq"),
  SIOCGIFCONF    = _IOWR('i', 38, "ifconf"),
  SIOCGIFNETMASK = _IOWR('i', 37, "ifreq"),
  SIOCSIFNETMASK =  _IOW('i', 22, "ifreq"),
  SIOCGIFMETRIC  = _IOWR('i', 23, "ifreq"),
  SIOCSIFMETRIC  =  _IOW('i', 24, "ifreq"),
  SIOCDIFADDR    =  _IOW('i', 25, "ifreq"),
  SIOCAIFADDR    =  _IOW('i', 26, "ifaliasreq"),
  SIOCGIFALIAS   = _IOWR('i', 27, "ifaliasreq"),
  SIOCALIFADDR   =  _IOW('i', 28, "if_laddrreq"),
  SIOCGLIFADDR   = _IOWR('i', 29, "if_laddrreq"),
  SIOCDLIFADDR   =  _IOW('i', 30, "if_laddrreq"),
  SIOCSIFADDRPREF=  _IOW('i', 31, "if_addrprefreq"),
  SIOCGIFADDRPREF= _IOWR('i', 32, "if_addrprefreq"),
  SIOCADDMULTI   =  _IOW('i', 49, "ifreq"),
  SIOCDELMULTI   =  _IOW('i', 50, "ifreq"),
  SIOCGETVIFCNT  = _IOWR('u', 51, "sioc_vif_req"),
  SIOCGETSGCNT   = _IOWR('u', 52, "sioc_sg_req"),
  SIOCSIFMEDIA   = _IOWR('i', 53, "ifreq"),
  SIOCGIFMEDIA   = _IOWR('i', 54, "ifmediareq"),
  SIOCSIFGENERIC =  _IOW('i', 57, "ifreq"),
  SIOCGIFGENERIC = _IOWR('i', 58, "ifreq"),
  SIOCSIFPHYADDR =  _IOW('i', 70, "ifaliasreq"),
  SIOCGIFPSRCADDR= _IOWR('i', 71, "ifreq"),
  SIOCGIFPDSTADDR= _IOWR('i', 72, "ifreq"),
  SIOCDIFPHYADDR =  _IOW('i', 73, "ifreq"),
  SIOCSLIFPHYADDR=  _IOW('i', 74, "if_laddrreq"),
  SIOCGLIFPHYADDR= _IOWR('i', 75, "if_laddrreq"),
  SIOCSIFMTU     =  _IOW('i', 127, "ifreq"),
  SIOCGIFMTU     = _IOWR('i', 126, "ifreq"),
  SIOCSDRVSPEC   =  _IOW('i', 123, "ifdrv"),
  SIOCGDRVSPEC   = _IOWR('i', 123, "ifdrv"),
  SIOCIFCREATE   =  _IOW('i', 122, "ifreq"),
  SIOCIFDESTROY  =  _IOW('i', 121, "ifreq"),
  SIOCIFGCLONERS = _IOWR('i', 120, "if_clonereq"),
  SIOCGIFDLT     = _IOWR('i', 119, "ifreq"),
  SIOCGIFCAP     = _IOWR('i', 118, "ifcapreq"),
  SIOCSIFCAP     =  _IOW('i', 117, "ifcapreq"),
  SIOCSVH        = _IOWR('i', 130, "ifreq"),
  SIOCGVH        = _IOWR('i', 131, "ifreq"),
  SIOCINITIFADDR = _IOWR('i', 132, "ifaddr"),
  SIOCGIFDATA    = _IOWR('i', 133, "ifdatareq"),
  SIOCZIFDATA    = _IOWR('i', 134, "ifdatareq"),
  SIOCGLINKSTR   = _IOWR('i', 135, "ifdrv"),
  SIOCSLINKSTR   =  _IOW('i', 136, "ifdrv"),
  SIOCSETPFSYNC  =  _IOW('i', 247, "ifreq"),
  SIOCGETPFSYNC  = _IOWR('i', 248, "ifreq"),
]]
}

return ioctl

end


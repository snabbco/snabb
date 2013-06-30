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

--[[
#define IOCPARM_MASK    0x1fff          /* parameter length, at most 13 bits */
#define IOCPARM_SHIFT   16
#define IOCGROUP_SHIFT  8
#define IOCPARM_LEN(x)  (((x) >> IOCPARM_SHIFT) & IOCPARM_MASK)
#define IOCBASECMD(x)   ((x) & ~(IOCPARM_MASK << IOCPARM_SHIFT))
#define IOCGROUP(x)     (((x) >> IOCGROUP_SHIFT) & 0xff)

#define IOCPARM_MAX     NBPG    /* max size of ioctl args, mult. of NBPG */
                                /* no parameters */
#define IOC_VOID        (unsigned long)0x20000000
                                /* copy parameters out */
#define IOC_OUT         (unsigned long)0x40000000
                                /* copy parameters in */
#define IOC_IN          (unsigned long)0x80000000
                                /* copy parameters in and out */
#define IOC_INOUT       (IOC_IN|IOC_OUT)
                                /* mask for IN/OUT/VOID */
#define IOC_DIRMASK     (unsigned long)0xe0000000

#define _IOC(inout, group, num, len) \
    ((inout) | (((len) & IOCPARM_MASK) << IOCPARM_SHIFT) | \
    ((group) << IOCGROUP_SHIFT) | (num))
#define _IO(g,n)        _IOC(IOC_VOID,  (g), (n), 0)
#define _IOR(g,n,t)     _IOC(IOC_OUT,   (g), (n), sizeof(t))
#define _IOW(g,n,t)     _IOC(IOC_IN,    (g), (n), sizeof(t))
/* this should be _IORW, but stdio got there first */
#define _IOWR(g,n,t)    _IOC(IOC_INOUT, (g), (n), sizeof(t))
]]

local ioctl = strflag {
  -- socket ioctls
  SIOCSHIWAT     =  _IOW('s',  0, s.int),
  SIOCGHIWAT     =  _IOR('s',  1, s.int),
  SIOCSLOWAT     =  _IOW('s',  2, s.int),
  SIOCGLOWAT     =  _IOR('s',  3, s.int),
  SIOCATMARK     =  _IOR('s',  7, s.int),
  SIOCSPGRP      =  _IOW('s',  8, s.int),
  SIOCGPGRP      =  _IOR('s',  9, s.int),
  SIOCADDRT      =  _IOW('r', 10, s.ortentry),
  SIOCDELRT      =  _IOW('r', 11, s.ortentry),
  SIOCSIFADDR    =  _IOW('i', 12, s.ifreq),
  SIOCGIFADDR    = _IOWR('i', 33, s.ifreq),
  SIOCSIFDSTADDR =  _IOW('i', 14, s.ifreq),
  SIOCGIFDSTADDR = _IOWR('i', 34, s.ifreq),
  SIOCSIFFLAGS   =  _IOW('i', 16, s.ifreq),
  SIOCGIFFLAGS   = _IOWR('i', 17, s.ifreq),
  SIOCGIFBRDADDR = _IOWR('i', 35, s.ifreq),
  SIOCSIFBRDADDR =  _IOW('i', 19, s.ifreq),
  SIOCGIFCONF    = _IOWR('i', 38, s.ifconf),
  SIOCGIFNETMASK = _IOWR('i', 37, s.ifreq),
  SIOCSIFNETMASK =  _IOW('i', 22, s.ifreq),
  SIOCGIFMETRIC  = _IOWR('i', 23, s.ifreq),
  SIOCSIFMETRIC  =  _IOW('i', 24, s.ifreq),
  SIOCDIFADDR    =  _IOW('i', 25, s.ifreq),
  SIOCAIFADDR    =  _IOW('i', 26, s.ifaliasreq),
  SIOCGIFALIAS   = _IOWR('i', 27, s.ifaliasreq),
  SIOCALIFADDR   =  _IOW('i', 28, s.if_laddrreq),
  SIOCGLIFADDR   = _IOWR('i', 29, s.if_laddrreq),
  SIOCDLIFADDR   =  _IOW('i', 30, s.if_laddrreq),
  SIOCSIFADDRPREF=  _IOW('i', 31, s.if_addrprefreq),
  SIOCGIFADDRPREF= _IOWR('i', 32, s.if_addrprefreq),
  SIOCADDMULTI   =  _IOW('i', 49, s.ifreq),
  SIOCDELMULTI   =  _IOW('i', 50, s.ifreq),
  SIOCGETVIFCNT  = _IOWR('u', 51, s.sioc_vif_req),
  SIOCGETSGCNT   = _IOWR('u', 52, s.sioc_sg_req),
  SIOCSIFMEDIA   = _IOWR('i', 53, s.ifreq),
  SIOCGIFMEDIA   = _IOWR('i', 54, s.ifmediareq),
  SIOCSIFGENERIC =  _IOW('i', 57, s.ifreq),
  SIOCGIFGENERIC = _IOWR('i', 58, s.ifreq),
  SIOCSIFPHYADDR =  _IOW('i', 70, s.ifaliasreq),
  SIOCGIFPSRCADDR= _IOWR('i', 71, s.ifreq),
  SIOCGIFPDSTADDR= _IOWR('i', 72, s.ifreq),
  SIOCDIFPHYADDR =  _IOW('i', 73, s.ifreq),
  SIOCSLIFPHYADDR=  _IOW('i', 74, s.if_laddrreq),
  SIOCGLIFPHYADDR= _IOWR('i', 75, s.if_laddrreq),
  SIOCSIFMTU     =  _IOW('i', 127, s.ifreq),
  SIOCGIFMTU     = _IOWR('i', 126, s.ifreq),
  SIOCSDRVSPEC   =  _IOW('i', 123, s.ifdrv),
  SIOCGDRVSPEC   = _IOWR('i', 123, s.ifdrv),
  SIOCIFCREATE   =  _IOW('i', 122, s.ifreq),
  SIOCIFDESTROY  =  _IOW('i', 121, s.ifreq),
  SIOCIFGCLONERS = _IOWR('i', 120, s.if_clonereq),
  SIOCGIFDLT     = _IOWR('i', 119, s.ifreq),
  SIOCGIFCAP     = _IOWR('i', 118, s.ifcapreq),
  SIOCSIFCAP     =  _IOW('i', 117, s.ifcapreq),
  SIOCSVH        = _IOWR('i', 130, s.ifreq),
  SIOCGVH        = _IOWR('i', 131, s.ifreq),
  SIOCINITIFADDR = _IOWR('i', 132, s.ifaddr),
  SIOCGIFDATA    = _IOWR('i', 133, s.ifdatareq),
  SIOCZIFDATA    = _IOWR('i', 134, s.ifdatareq),
  SIOCGLINKSTR   = _IOWR('i', 135, s.ifdrv),
  SIOCSLINKSTR   =  _IOW('i', 136, s.ifdrv),
  SIOCSETPFSYNC  =  _IOW('i', 247, s.ifreq),
  SIOCGETPFSYNC  = _IOWR('i', 248, s.ifreq),
}

return ioctl

end


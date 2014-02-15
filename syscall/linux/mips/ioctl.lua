-- MIPS ioctl differences

local arch = {
  IOC = {
    SIZEBITS = 13,
    DIRBITS = 3,
    NONE = 1,
    WRITE = 2,
    READ = 4,
  },
  ioctl = function(_IO, _IOR, _IOW, _IORW)
    return {
      TCSETA	     = 0x5402,
      TCSETAW	     = 0x5403,
      TCSETAF	     = 0x5404,
      TCSBRK	     = 0x5405,
      TCXONC	     = 0x5406,
      TCFLSH	     = 0x5407,
      TCGETS	     = 0x540d,
      TCSETS	     = 0x540e,
      TCSETSW	     = 0x540f,
      TCSETSF	     = 0x5410,
      TIOCNOTTY	     = 0x5471,
      TIOCSCTTY	     = 0x5480,
      TIOCSSERIAL    = 0x5485,
      TCSBRKP	     = 0x5486,
      TIOCSERGWILD   = 0x5489,
      TIOCSERSWILD   = 0x548a,
      TIOCSLCKTRMIOS = 0x548c,
      TIOCSERGSTRUCT = 0x548d,
      TIOCSERGETLSR  = 0x548e,
      TIOCSERGETMULTI= 0x548f,
      TIOCSERSETMULTI= 0x5490,
      TIOCMIWAIT     = 0x5491,
      FIOCLEX	     = 0x6601,
      FIOASYNC	     = 0x667d,
      FIONBIO        = 0x667e,
      TIOCSETD	     = 0x7401,
      TIOCGSID	     = 0x7416,
      TIOCMSET	     = 0x741a,
      TIOCOUTQ	     = 0x7472,
      FIOGETOWN      = _IOR('f', 123, "int"),
      FIOSETOWN      = _IOW('f', 124, "int"),
      SIOCATMARK     = _IOR('s', 7, "int"),
      SIOCSPGRP      = _IOW('s', 8, "pid"),
      SIOCGPGRP      = _IOR('s', 9, "pid"),
      TIOCSWINSZ     = _IOW('t', 103, "winsize"),
      TIOCSPGRP	     = _IOW('t', 118, "int"),
      TIOCGPGRP	     = _IOR('t', 119, "int"),
    }
  end,
}

return arch


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
      TCFLSH	     = 0x5407,
      TCSETS	     = 0x540e,
      TCSETSW	     = 0x540f,
      TCSETSF	     = 0x5410,
      TIOCNOTTY	     = 0x5471,
      TCSBRKP	     = 0x5486,
      TIOCSERSWILD   = 0x548a,
      TIOCMIWAIT     = 0x5491,
      TIOCSETD	     = 0x7401,
      TIOCMSET	     = 0x741a,
      TIOCOUTQ	     = 0x7472,
      FIOGETOWN      = _IOR('f', 123, "int"),
      FIOSETOWN      = _IOW('f', 124, "int"),
      SIOCATMARK     = _IOR('s', 7, "int"),
      SIOCSPGRP      = _IOW('s', 8, "pid"),
      SIOCGPGRP      = _IOR('s', 9, "pid"),
      TIOCSPGRP	     = _IOW('t', 118, "int"),
    }
  end,
}

return arch


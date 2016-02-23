-- ppc ioctl differences

local arch = {
  IOC = {
    SIZEBITS  = 13,
    DIRBITS   = 3,
    NONE      = 1,
    READ      = 2,
    WRITE     = 4,
  },
  ioctl = function(_IO, _IOR, _IOW, _IORW)
    return {
      FIOCLEX	= _IO('f', 1),
      FIONCLEX	= _IO('f', 2),
      FIOQSIZE	= _IOR('f', 128, "off"),
      FIOASYNC	= _IOW('f', 125, "int"),
      TCGETS	= _IOR('t', 19, "termios"),
      TCSETS	= _IOW('t', 20, "termios"),
      TCSETSW	= _IOW('t', 21, "termios"),
      TCSETSF	= _IOW('t', 22, "termios"),
      TCSBRK	= _IO('t', 29),
      TCXONC	= _IO('t', 30),
      TCFLSH	= _IO('t', 31),
      TIOCSWINSZ = _IOW('t', 103, "winsize"),
      TIOCGWINSZ = _IOR('t', 104, "winsize"),
      TIOCOUTQ  = _IOR('t', 115, "int"),
      TIOCSPGRP	= _IOW('t', 118, "int"),
      TIOCGPGRP	= _IOR('t', 119, "int"),
      FIONBIO	= _IOW('f', 126, "int"),
      FIONREAD	= _IOR('f', 127, "int"),
    }
  end,
}

return arch


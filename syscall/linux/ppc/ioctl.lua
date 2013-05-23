-- ppc ioctl differences

return function(s)

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
      FIOQSIZE	= _IOR('f', 128, s.off),
      FIOASYNC	= _IOW('f', 125, s.int),
      TCGETS	= _IOR('t', 19, s.termios),
      TCSETS	= _IOW('t', 20, s.termios),
      TCSETSW	= _IOW('t', 21, s.termios),
      TCSETSF	= _IOW('t', 22, s.termios),
      TCGETA	= _IOR('t', 23, s.termio),
      TCSETA	= _IOW('t', 24, s.termio),
      TCSETAW	= _IOW('t', 25, s.termio),
      TCSETAF	= _IOW('t', 28, s.termio),
      TCSBRK	= _IO('t', 29),
      TCXONC	= _IO('t', 30),
      TCFLSH	= _IO('t', 31),
      TIOCSWINSZ = _IOW('t', 103, s.winsize),
      TIOCGWINSZ = _IOR('t', 104, s.winsize),
      TIOCOUTQ  = _IOR('t', 115, s.int),
      TIOCSPGRP	= _IOW('t', 118, s.int),
      TIOCGPGRP	= _IOR('t', 119, s.int),
      FIONBIO	= _IOW('f', 126, s.int),
      FIONREAD	= _IOR('f', 127, s.int),
    }
  end,
}

return arch

end


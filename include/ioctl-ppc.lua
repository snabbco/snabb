-- ppc ioctl differences

local arch = {
  IOC_SIZEBITS  = 13,
  IOC_DIRBITS   = 3,
  IOC_NONE      = 1,
  IOC_READ      = 2,
  IOC_WRITE     = 4,
  FIONCLEX	= {'_IO', 'f', 2},
  TCSETA	= {'_IOW', 't', 24, 'termio'},
  TCSETAW	= {'_IOW', 't', 25, 'termio'},
  TCSETAF	= {'_IOW', 't', 28, 'termio'},
  TIOCSWINSZ	= {'_IOW', 't', 103, 'winsize'},
  TIOCGWINSZ	= {'_IOR', 't', 104, 'winsize'},
  TIOCOUTQ      = {'_IOR', 't', 115, 'int'},
  TIOCSPGRP	= {'_IOW', 't', 118, 'int'},
  TIOCGPGRP	= {'_IOR', 't', 119, 'int'},
  FIONBIO	= {'_IOW', 'f', 126, 'int'},
  FIONREAD	= {'_IOR', 'f', 127, 'int'},
}

return arch


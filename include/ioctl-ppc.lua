-- ppc ioctl differences

local arch = {
  IOC_SIZEBITS  = 13,
  IOC_DIRBITS   = 3,
  IOC_NONE      = 1,
  IOC_READ      = 2,
  IOC_WRITE     = 4,
  TIOCSPGRP	= {'_IOW', 't', 118, 'int'},
  TIOCGPGRP	= {'_IOR', 't', 119, 'int'},
  TIOCSWINSZ	= {'_IOW', 't', 103, 'winsize'},
  TIOCGWINSZ	= {'_IOR', 't', 104, 'winsize'},
}

return arch


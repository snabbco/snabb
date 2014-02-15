-- MIPS ioctl differences

return function(s)

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
      FIOGETOWN      = _IOR('f', 123, "int"),
      FIOSETOWN      = _IOW('f', 124, "int"),
      SIOCATMARK     = _IOR('s', 7, "int"),
      SIOCSPGRP      = _IOW('s', 8, "pid"),
      SIOCGPGRP      = _IOR('s', 9, "pid"),
    }
  end,
}

return arch

end


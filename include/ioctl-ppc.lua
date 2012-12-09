-- ppc ioctl differences

local arch = {
  IOC_SIZEBITS  = 13,
  IOC_DIRBITS   = 3,
  IOC_NONE      = 1,
  IOC_READ      = 2,
  IOC_WRITE     = 4,
}

return arch


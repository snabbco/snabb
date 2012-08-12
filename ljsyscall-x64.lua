-- x86-64 specific code

local ffi = require "ffi"

local arch = {}

arch.SYS = {
  stat             = 4,
  fstat            = 5,
  lstat            = 6,
  getpid           = 39,
  clone            = 56,
  getdents         = 78,
  getcwd           = 79,
  mknod            = 133,
  ustat            = 136,
  acct             = 163,
  readahead        = 187,
  setxattr         = 188,
  lsetxattr        = 189,
  fsetxattr        = 190,
  getxattr         = 191,
  lgetxattr        = 192,
  fgetxattr        = 193,
  listxattr        = 194,
  llistxattr       = 195,
  flistxattr       = 196,
  removexattr      = 197,
  lremovexattr     = 198,
  fremovexattr     = 199,
  io_setup         = 206,
  io_destroy       = 207,
  io_getevents     = 208,
  io_submit        = 209,
  io_cancel        = 210,
  getdents64       = 217,
  clock_settime    = 227,
  clock_gettime    = 228,
  clock_getres     = 229,
  clock_nanosleep  = 230,
  mknodat          = 259,
  fstatat          = 262,
  splice           = 275,
  tee              = 276,
  sync_file_range  = 277,
  vmsplice         = 278,
  timerfd_create   = 283,
  fallocate        = 285,
  timerfd_settime  = 286,
  timerfd_gettime  = 287,
  pipe2            = 293,
  setns            = 308,
}

arch.epoll = function()
ffi.cdef[[
struct epoll_event {
  uint32_t events;      /* Epoll events */
  epoll_data_t data;    /* User data variable */
}  __attribute__ ((packed));
]]
end

return arch


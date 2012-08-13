-- x86 specific code

local ffi = require "ffi"

local arch = {}

arch.SYS = {
  mknod            = 14,
  getpid           = 20,
  acct             = 51,
  ustat            = 62,
  stat             = 106,
  fstat            = 108,
  lstat            = 107,
  clone            = 120,
  _llseek          = 140,
  getdents         = 141,
  getcwd           = 183,
  stat64           = 195,
  lstat64          = 196,
  fstat64          = 197,
  getdents64       = 220,
  readahead        = 225,
  setxattr         = 226,
  lsetxattr        = 227,
  fsetxattr        = 228,
  getxattr         = 229,
  lgetxattr        = 230,
  fgetxattr        = 231,
  listxattr        = 232,
  llistxattr       = 233,
  flistxattr       = 234,
  removexattr      = 235,
  lremovexattr     = 236,
  fremovexattr     = 237,
  io_setup         = 245,
  io_destroy       = 246,
  io_getevents     = 247,
  io_submit        = 248,
  io_cancel        = 249,
  clock_settime    = 264,
  clock_gettime    = 265,
  clock_getres     = 266,
  clock_nanosleep  = 267,
  mknodat          = 297,
  fstatat64        = 300,
  splice           = 313,
  sync_file_range  = 314,
  tee              = 315,
  vmsplice         = 316,
  timerfd_create   = 322,
  fallocate        = 324,
  timerfd_settime  = 325,
  timerfd_gettime  = 326,
  pipe2            = 331,
  setns            = 346,
}

-- x86 has a different sigaction
arch.sigaction = function()
ffi.cdef[[
struct sigaction {
  union {
    sighandler_t sa_handler;
    void (*sa_sigaction)(int, struct siginfo *, void *);
  };
  sigset_t sa_mask;
  unsigned long sa_flags;
  void (*sa_restorer)(void);
};
]]
end

return arch


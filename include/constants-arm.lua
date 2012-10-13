-- arm specific constants

local ffi = require "ffi"

assert(ffi.abi("eabi"), "only support eabi for arm")

local octal = function (s) return tonumber(s, 8) end 

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
  getdents64       = 217,
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
  io_setup         = 243,
  io_destroy       = 244,
  io_getevents     = 245,
  io_submit        = 246,
  io_cancel        = 247,
  clock_settime    = 262,
  clock_gettime    = 263,
  clock_getres     = 264,
  clock_nanosleep  = 265,
  mknodat          = 324,
  fstatat64        = 327,
  splice           = 340,
  sync_file_range  = 341,
  tee              = 342,
  vmsplice         = 343,
  timerfd_create   = 350,
  fallocate        = 352,
  timerfd_settime  = 353,
  timerfd_gettime  = 354,
  pipe2            = 359,
  setns            = 375,
}

-- TODO cleanup to return table
arch.oflags = function(S)
  S.O_DIRECTORY = octal('040000')
  S.O_NOFOLLOW  = octal('0100000')
  S.O_DIRECT    = octal('0200000')
end

return arch


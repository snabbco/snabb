-- NetBSD syscall numbers

local nr = {
  SYS = {
  syscall = 0,
  exit = 1,
  fork = 2,
  read = 3,
  write = 4,
  open = 5,
  close = 6,
  compat_50_wait4 = 7,
  compat_43_ocreat = 8,
  link = 9,
  unlink = 10,
  chdir = 12,
  fchdir = 13,
  compat_50_mknod = 14,
  chmod = 15,
  chown = 16,
  ["break"] = 17,
  compat_20_getfsstat = 18,
  compat_43_olseek = 19,
  getpid = 20,
  compat_40_mount = 21,
  unmount = 22,
  setuid = 23,
  getuid = 24,
  geteuid = 25,
  ptrace = 26,
  recvmsg = 27,
  sendmsg = 28,
  recvfrom = 29,
  accept = 30,
  getpeername = 31,
  getsockname = 32,
  access = 33,
  chflags = 34,
  fchflags = 35,
  sync = 36,
  kill = 37,
  compat_43_stat43 = 38,
  getppid = 39,
  compat_43_lstat43 = 40,


  ioctl = 54,
  }
}

return nr


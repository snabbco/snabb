-- define C functions for rump

-- TODO merge into NetBSD ones, generate

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local h = require "syscall.helpers"
local err64 = h.err64
local errpointer = h.errpointer

local ffi = require "ffi"

local cdef

if abi.types == abi.host or abi.types == "linux" then -- types same on host and rump or using Linux so no renaming
  cdef = function(s)
    s = string.gsub(s, "_netbsd_", "")
    ffi.cdef(s)
  end
else
  cdef = ffi.cdef -- use as provided
end

cdef [[
ssize_t rump___sysimpl_read(int, void *, size_t);
ssize_t rump___sysimpl_write(int, const void *, size_t);
int rump___sysimpl_open(const char *, int, _netbsd_mode_t);
int rump___sysimpl_close(int);
int rump___sysimpl_link(const char *, const char *);
int rump___sysimpl_unlink(const char *);
int rump___sysimpl_chdir(const char *);
int rump___sysimpl_fchdir(int);
int rump___sysimpl_mknod50(const char *, _netbsd_mode_t, _netbsd_dev_t);
int rump___sysimpl_chmod(const char *, _netbsd_mode_t);
int rump___sysimpl_chown(const char *, uid_t, gid_t);
pid_t rump___sysimpl_getpid(void);
int rump___sysimpl_unmount(const char *, int);
int rump___sysimpl_setuid(uid_t);
uid_t rump___sysimpl_getuid(void);
uid_t rump___sysimpl_geteuid(void);
ssize_t rump___sysimpl_recvmsg(int, struct _netbsd_msghdr *, int);
ssize_t rump___sysimpl_sendmsg(int, const struct _netbsd_msghdr *, int);
ssize_t rump___sysimpl_recvfrom(int, void *, size_t, int, struct _netbsd_sockaddr *, socklen_t *);
int rump___sysimpl_accept(int, struct _netbsd_sockaddr *, socklen_t *);
int rump___sysimpl_getpeername(int, struct _netbsd_sockaddr *, socklen_t *);
int rump___sysimpl_getsockname(int, struct _netbsd_sockaddr *, socklen_t *);
int rump___sysimpl_access(const char *, int);
int rump___sysimpl_chflags(const char *, unsigned long);
int rump___sysimpl_fchflags(int, unsigned long);
void rump___sysimpl_sync(void);
pid_t rump___sysimpl_getppid(void);
int rump___sysimpl_dup(int);
gid_t rump___sysimpl_getegid(void);
gid_t rump___sysimpl_getgid(void);
int rump___sysimpl___getlogin(char *, size_t);
int rump___sysimpl___setlogin(const char *);
int rump___sysimpl_ioctl(int, unsigned long, void *);
int rump___sysimpl_revoke(const char *);
int rump___sysimpl_symlink(const char *, const char *);
ssize_t rump___sysimpl_readlink(const char *, char *, size_t);
_netbsd_mode_t rump___sysimpl_umask(_netbsd_mode_t);
int rump___sysimpl_chroot(const char *);
int rump___sysimpl_getgroups(int, gid_t *);
int rump___sysimpl_setgroups(int, const gid_t *);
int rump___sysimpl_getpgrp(void);
int rump___sysimpl_setpgid(pid_t, pid_t);
int rump___sysimpl_dup2(int, int);
int rump___sysimpl_fcntl(int, int, ...);
int rump___sysimpl_select50(int, _netbsd_fd_set *, _netbsd_fd_set *, _netbsd_fd_set *, struct _netbsd_timeval *);
int rump___sysimpl_fsync(int);
int rump___sysimpl_connect(int, const struct _netbsd_sockaddr *, socklen_t);
int rump___sysimpl_bind(int, const struct _netbsd_sockaddr *, socklen_t);
int rump___sysimpl_setsockopt(int, int, int, const void *, socklen_t);
int rump___sysimpl_listen(int, int);
int rump___sysimpl_getsockopt(int, int, int, void *, socklen_t *);
ssize_t rump___sysimpl_readv(int, const struct iovec *, int);
ssize_t rump___sysimpl_writev(int, const struct iovec *, int);
int rump___sysimpl_fchown(int, uid_t, gid_t);
int rump___sysimpl_fchmod(int, _netbsd_mode_t);
int rump___sysimpl_setreuid(uid_t, uid_t);
int rump___sysimpl_setregid(gid_t, gid_t);
int rump___sysimpl_rename(const char *, const char *);
int rump___sysimpl_flock(int, int);
int rump___sysimpl_mkfifo(const char *, _netbsd_mode_t);
ssize_t rump___sysimpl_sendto(int, const void *, size_t, int, const struct _netbsd_sockaddr *, socklen_t);
int rump___sysimpl_shutdown(int, int);
int rump___sysimpl_socketpair(int, int, int, int *);
int rump___sysimpl_mkdir(const char *, _netbsd_mode_t);
int rump___sysimpl_rmdir(const char *);
int rump___sysimpl_utimes50(const char *, const struct _netbsd_timeval *);
int rump___sysimpl_setsid(void);
int rump___sysimpl_nfssvc(int, void *);
ssize_t rump___sysimpl_pread(int, void *, size_t, off_t);
ssize_t rump___sysimpl_pwrite(int, const void *, size_t, off_t);
int rump___sysimpl_setgid(gid_t);
int rump___sysimpl_setegid(gid_t);
int rump___sysimpl_seteuid(uid_t);
long rump___sysimpl_pathconf(const char *, int);
long rump___sysimpl_fpathconf(int, int);
int rump___sysimpl_getrlimit(int, struct _netbsd_rlimit *);
int rump___sysimpl_setrlimit(int, const struct _netbsd_rlimit *);
off_t rump___sysimpl_lseek(int, off_t, int);
int rump___sysimpl_truncate(const char *, off_t);
int rump___sysimpl_ftruncate(int, off_t);
int rump___sysimpl_futimes50(int, const struct _netbsd_timeval *);
pid_t rump___sysimpl_getpgid(pid_t);
int rump___sysimpl_reboot(int, char *);
int rump___sysimpl_poll(struct _netbsd_pollfd *, unsigned int, int);
int rump___sysimpl_fdatasync(int);
int rump___sysimpl_modctl(int, void *);
int rump___sysimpl__ksem_init(unsigned int, intptr_t *);
int rump___sysimpl__ksem_open(const char *, int, _netbsd_mode_t, unsigned int, intptr_t *);
int rump___sysimpl__ksem_unlink(const char *);
int rump___sysimpl__ksem_close(intptr_t);
int rump___sysimpl__ksem_post(intptr_t);
int rump___sysimpl__ksem_wait(intptr_t);
int rump___sysimpl__ksem_trywait(intptr_t);
int rump___sysimpl__ksem_getvalue(intptr_t, unsigned int *);
int rump___sysimpl__ksem_destroy(intptr_t);
int rump___sysimpl__ksem_timedwait(intptr_t, const struct _netbsd_timespec *);
int rump___sysimpl_lchmod(const char *, _netbsd_mode_t);
int rump___sysimpl_lchown(const char *, uid_t, gid_t);
int rump___sysimpl_lutimes50(const char *, const struct _netbsd_timeval *);
pid_t rump___sysimpl_getsid(pid_t);
ssize_t rump___sysimpl_preadv(int, const struct iovec *, int, off_t);
ssize_t rump___sysimpl_pwritev(int, const struct iovec *, int, off_t);
int rump___sysimpl___getcwd(char *, size_t);
int rump___sysimpl_fchroot(int);
int rump___sysimpl_lchflags(const char *, unsigned long);
int rump___sysimpl_issetugid(void);
int rump___sysimpl_kqueue(void);
int rump___sysimpl_kevent50(int, const struct _netbsd_kevent *, size_t, struct _netbsd_kevent *, size_t, const struct _netbsd_timespec *);
int rump___sysimpl_fsync_range(int, int, off_t, off_t);
int rump___sysimpl_getvfsstat(struct _netbsd_statvfs *, size_t, int);
int rump___sysimpl_statvfs1(const char *, struct _netbsd_statvfs *, int);
int rump___sysimpl_fstatvfs1(int, struct _netbsd_statvfs *, int);
int rump___sysimpl_extattrctl(const char *, int, const char *, int, const char *);
int rump___sysimpl_extattr_set_file(const char *, int, const char *, const void *, size_t);
ssize_t rump___sysimpl_extattr_get_file(const char *, int, const char *, void *, size_t);
int rump___sysimpl_extattr_delete_file(const char *, int, const char *);
int rump___sysimpl_extattr_set_fd(int, int, const char *, const void *, size_t);
ssize_t rump___sysimpl_extattr_get_fd(int, int, const char *, void *, size_t);
int rump___sysimpl_extattr_delete_fd(int, int, const char *);
int rump___sysimpl_extattr_set_link(const char *, int, const char *, const void *, size_t);
ssize_t rump___sysimpl_extattr_get_link(const char *, int, const char *, void *, size_t);
int rump___sysimpl_extattr_delete_link(const char *, int, const char *);
ssize_t rump___sysimpl_extattr_list_fd(int, int, void *, size_t);
ssize_t rump___sysimpl_extattr_list_file(const char *, int, void *, size_t);
ssize_t rump___sysimpl_extattr_list_link(const char *, int, void *, size_t);
int rump___sysimpl_pselect50(int, _netbsd_fd_set *, _netbsd_fd_set *, _netbsd_fd_set *, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
int rump___sysimpl_pollts50(struct _netbsd_pollfd *, unsigned int, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
int rump___sysimpl_setxattr(const char *, const char *, const void *, size_t, int);
int rump___sysimpl_lsetxattr(const char *, const char *, const void *, size_t, int);
int rump___sysimpl_fsetxattr(int, const char *, const void *, size_t, int);
int rump___sysimpl_getxattr(const char *, const char *, void *, size_t);
int rump___sysimpl_lgetxattr(const char *, const char *, void *, size_t);
int rump___sysimpl_fgetxattr(int, const char *, void *, size_t);
int rump___sysimpl_listxattr(const char *, char *, size_t);
int rump___sysimpl_llistxattr(const char *, char *, size_t);
int rump___sysimpl_flistxattr(int, char *, size_t);
int rump___sysimpl_removexattr(const char *, const char *);
int rump___sysimpl_lremovexattr(const char *, const char *);
int rump___sysimpl_fremovexattr(int, const char *);
int rump___sysimpl_stat50(const char *, struct _netbsd_stat *);
int rump___sysimpl_fstat50(int, struct _netbsd_stat *);
int rump___sysimpl_lstat50(const char *, struct _netbsd_stat *);
int rump___sysimpl_getdents30(int, char *, size_t);
int rump___sysimpl_socket30(int, int, int);
int rump___sysimpl_getfh30(const char *, void *, size_t *);
int rump___sysimpl_fhopen40(const void *, size_t, int);
int rump___sysimpl_fhstatvfs140(const void *, size_t, struct _netbsd_statvfs *, int);
int rump___sysimpl_fhstat50(const void *, size_t, struct _netbsd_stat *);
int rump___sysimpl_mount50(const char *, const char *, int, void *, size_t);
int rump___sysimpl_posix_fadvise50(int, off_t, off_t, int);
int rump___sysimpl_pipe2(int *, int);
int rump___sysimpl_dup3(int, int, int);
int rump___sysimpl_kqueue1(int);
int rump___sysimpl_paccept(int, struct _netbsd_sockaddr *, socklen_t *, const _netbsd_sigset_t *, int);
int rump___sysimpl_linkat(int, const char *, int, const char *, int);
int rump___sysimpl_renameat(int, const char *, int, const char *);
int rump___sysimpl_mkfifoat(int, const char *, _netbsd_mode_t);
int rump___sysimpl_mknodat(int, const char *, _netbsd_mode_t, _netbsd_dev_t);
int rump___sysimpl_mkdirat(int, const char *, _netbsd_mode_t);
int rump___sysimpl_faccessat(int, const char *, int, int);
int rump___sysimpl_fchmodat(int, const char *, _netbsd_mode_t, int);
int rump___sysimpl_fchownat(int, const char *, uid_t, gid_t, int);
int rump___sysimpl_fstatat(int, const char *, struct _netbsd_stat *, int);
int rump___sysimpl_utimensat(int, const char *, const struct _netbsd_timespec *, int);
int rump___sysimpl_openat(int, const char *, int, int);
int rump___sysimpl_readlinkat(int, const char *, char *, size_t);
int rump___sysimpl_symlinkat(const char *, int, const char *);
int rump___sysimpl_unlinkat(int, const char *, int);
int rump___sysimpl_futimens(int, const struct _netbsd_timespec *);
int rump___sysimpl___quotactl(const char *, struct _netbsd_quotactl_args *);
int rump___sysimpl_ktrace(const char *tracefile, int ops, int trpoints, pid_t pid);
int rump___sysimpl_fktrace(int fd, int ops, int trpoints, pid_t pid);
int rump___sysimpl_utrace(const char *, void *, size_t);
int rump___sysimpl_recvmmsg(int, struct _netbsd_mmsghdr *, unsigned int, unsigned int, struct _netbsd_timespec *);
int rump___sysimpl_sendmmsg(int, struct _netbsd_mmsghdr *, unsigned int, unsigned int);

int rump___sysimpl_gettimeofday50(struct _netbsd_timeval *, void *);
int rump___sysimpl_settimeofday50(const struct _netbsd_timeval *, const void *);
int rump___sysimpl_adjtime50(const struct _netbsd_timeval *, struct _netbsd_timeval *);
int rump___sysimpl_setitimer50(int, const struct _netbsd_itimerval *, struct _netbsd_itimerval *);
int rump___sysimpl_getitimer50(int, struct _netbsd_itimerval *);
int rump___sysimpl_clock_gettime50(_netbsd_clockid_t, struct _netbsd_timespec *);
int rump___sysimpl_clock_settime50(_netbsd_clockid_t, const struct _netbsd_timespec *);
int rump___sysimpl_clock_getres50(_netbsd_clockid_t, struct _netbsd_timespec *);
int rump___sysimpl_nanosleep50(const struct _netbsd_timespec *, struct _netbsd_timespec *);
int rump___sysimpl_timer_settime50(_netbsd_timer_t, int, const struct _netbsd_itimerspec *, struct _netbsd_itimerspec *);
int rump___sysimpl_timer_gettime50(_netbsd_timer_t, struct _netbsd_itimerspec *);
int rump___sysimpl_clock_nanosleep(_netbsd_clockid_t, int, const struct _netbsd_timespec *, struct _netbsd_timespec *);
int rump___sysimpl_timer_create(_netbsd_clockid_t, struct _netbsd_sigevent *, _netbsd_timer_t *);
int rump___sysimpl_timer_delete(_netbsd_timer_t);
int rump___sysimpl_timer_getoverrun(_netbsd_timer_t);

int rump___sysimpl_aio_cancel(int, struct aiocb *);
int rump___sysimpl_aio_error(const struct aiocb *);
int rump___sysimpl_aio_fsync(int, struct aiocb *);
int rump___sysimpl_aio_read(struct aiocb *);
int rump___sysimpl_aio_return(struct aiocb *);
int rump___sysimpl_aio_write(struct aiocb *);
int rump___sysimpl_lio_listio(int, struct aiocb *const *, int, struct sigevent *);
int rump___sysimpl_aio_suspend(const struct aiocb *const *, int, const struct timespec *);

int rump___sysimpl___sysctl(const int *, unsigned int, void *, size_t *, const void *, size_t);

int rump_sys_pipe(int *);
]]

local clist = {
  accept = "accept",
  access = "access",
  bind = "bind",
  chdir = "chdir",
  chflags = "chflags",
  chmod = "chmod",
  chown = "chown",
  chroot = "chroot",
  close = "close",
  connect = "connect",
  dup2 = "dup2",
  dup3 = "dup3",
  dup = "dup",
  extattrctl = "extattrctl",
  extattr_delete_fd = "extattr_delete_fd",
  extattr_delete_file = "extattr_delete_file",
  extattr_delete_link = "extattr_delete_link",
  extattr_get_fd = "extattr_get_fd",
  extattr_get_file = "extattr_get_file",
  extattr_get_link = "extattr_get_link",
  extattr_list_fd = "extattr_list_fd",
  extattr_list_file = "extattr_list_file",
  extattr_list_link = "extattr_list_link",
  extattr_set_fd = "extattr_set_fd",
  extattr_set_file = "extattr_set_file",
  extattr_set_link = "extattr_set_link",
  faccessat = "faccessat",
  fchdir = "fchdir",
  fchflags = "fchflags",
  fchmodat = "fchmodat",
  fchmod = "fchmod",
  fchownat = "fchownat",
  fchown = "fchown",
  fchroot = "fchroot",
  fcntl = "fcntl",
  fdatasync = "fdatasync",
  fgetxattr = "fgetxattr",
  fktrace = "fktrace",
  flistxattr = "flistxattr",
  flock = "flock",
  fpathconf = "fpathconf",
  fremovexattr = "fremovexattr",
  fsetxattr = "fsetxattr",
  fstatat = "fstatat",
  fstatvfs1 = "fstatvfs1",
  fsync_range = "fsync_range",
  fsync = "fsync",
  ftruncate = "ftruncate",
  futimens = "futimens",
  getcwd = "__getcwd",
  getegid = "getegid",
  geteuid = "geteuid",
  getgid = "getgid",
  getgroups = "getgroups",
  __getlogin = "__getlogin",
  getpeername = "getpeername",
  getpgid = "getpgid",
  getpgrp = "getpgrp",
  getpid = "getpid",
  getppid = "getppid",
  getrlimit = "getrlimit",
  getsid = "getsid",
  getsockname = "getsockname",
  getsockopt = "getsockopt",
  getuid = "getuid",
  getvfsstat = "getvfsstat",
  getxattr = "getxattr",
  ioctl = "ioctl",
  issetugid = "issetugid",
  kqueue1 = "kqueue1",
  kqueue = "kqueue",
  _ksem_close = "_ksem_close",
  _ksem_destroy = "_ksem_destroy",
  _ksem_getvalue = "_ksem_getvalue",
  _ksem_init = "_ksem_init",
  _ksem_open = "_ksem_open",
  _ksem_post = "_ksem_post",
  _ksem_timedwait = "_ksem_timedwait",
  _ksem_trywait = "_ksem_trywait",
  _ksem_unlink = "_ksem_unlink",
  _ksem_wait = "_ksem_wait",
  ktrace = "ktrace",
  lchflags = "lchflags",
  lchmod = "lchmod",
  lchown = "lchown",
  lgetxattr = "lgetxattr",
  linkat = "linkat",
  link = "link",
  listen = "listen",
  listxattr = "listxattr",
  llistxattr = "llistxattr",
  lremovexattr = "lremovexattr",
  lseek = "lseek",
  lsetxattr = "lsetxattr",
  mkdirat = "mkdirat",
  mkdir = "mkdir",
  mkfifoat = "mkfifoat",
  mkfifo = "mkfifo",
  mknodat = "mknodat",
  modctl = "modctl",
  nfssvc = "nfssvc",
  openat = "openat",
  open = "open",
  paccept = "paccept",
  pathconf = "pathconf",
  pipe2 = "pipe2",
  poll = "poll",
  pread = "pread",
  preadv = "preadv",
  pwrite = "pwrite",
  pwritev = "pwritev",
  __quotactl = "__quotactl",
  readlinkat = "readlinkat",
  readlink = "readlink",
  read = "read",
  readv = "readv",
  reboot = "reboot",
  recvfrom = "recvfrom",
  recvmsg = "recvmsg",
  removexattr = "removexattr",
  renameat = "renameat",
  rename = "rename",
  revoke = "revoke",
  rmdir = "rmdir",
  sendmsg = "sendmsg",
  sendto = "sendto",
  setegid = "setegid",
  seteuid = "seteuid",
  setgid = "setgid",
  setgroups = "setgroups",
  __setlogin = "__setlogin",
  setpgid = "setpgid",
  setregid = "setregid",
  setreuid = "setreuid",
  setrlimit = "setrlimit",
  setsid = "setsid",
  setsockopt = "setsockopt",
  setuid = "setuid",
  setxattr = "setxattr",
  shutdown = "shutdown",
  socketpair = "socketpair",
  statvfs1 = "statvfs1",
  symlinkat = "symlinkat",
  symlink = "symlink",
  sync = "sync",
  sysctl = "__sysctl",
  truncate = "truncate",
  umask = "umask",
  unlinkat = "unlinkat",
  unlink = "unlink",
  unmount = "unmount",
  utimensat = "utimensat",
  utrace = "utrace",
  write = "write",
  writev = "writev",
  recvmmsg = "recvmmsg",
  sendmmsg = "sendmmsg",
-- version calls
  fhopen = "fhopen40",
  fhstat = "fhstat50",
  fhstatvfs = "fhstatvfs140",
  fstat = "fstat50",
  futimes = "futimes50",
  getdents = "getdents30",
  getfh = "getfh30",
  kevent = "kevent50",
  lstat = "lstat50",
  lutimes = "lutimes50",
  mknod = "mknod50",
  mount = "mount50",
  posix_fadvise = "posix_fadvise50",
  pselect = "pselect50",
  select = "select50",
  socket = "socket30",
  stat = "stat50",
  utimes = "utimes50",
  pollts = "pollts50",
-- time functions
  gettimeofday = "gettimeofday50",
  settimeofday = "settimeofday50",
  adjtime = "adjtime50",
  setitimer = "setitimer50",
  getitimer = "getitimer50",
  clock_gettime = "clock_gettime50",
  clock_settime = "clock_settime50",
  clock_getres = "clock_getres50",
  nanosleep = "nanosleep50",
  timer_settime = "timer_settime50",
  timer_gettime = "timer_gettime50",
  clock_nanosleep = "clock_nanosleep",
  timer_create = "timer_create",
  timer_delete = "timer_delete",
  timer_getoverrun = "timer_getoverrun",
}

local C = {}

for k, v in pairs(clist) do C[k] = ffi.C["rump___sysimpl_" .. v] end

-- different naming convention due to return value
C.pipe = ffi.C.rump_sys_pipe

return C



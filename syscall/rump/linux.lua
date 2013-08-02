-- define C functions for rump Linux ABI

-- Note this is experimental, work in progress
-- The definitions are not all correct, need to be checked against Linux ABI.

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local function init(abi)

local ffi = require "ffi"

ffi.cdef [[
ssize_t rump___sysimpl_read(int, void *, size_t);
ssize_t rump___sysimpl_write(int, const void *, size_t);
int rump___sysimpl_open(const char *, int, mode_t);
int rump___sysimpl_close(int);
int rump___sysimpl_link(const char *, const char *);
int rump___sysimpl_unlink(const char *);
int rump___sysimpl_chdir(const char *);
int rump___sysimpl_fchdir(int);
int rump___sysimpl_mknod(const char *, mode_t, uint32_t);
int rump___sysimpl_chmod(const char *, mode_t);
int rump___sysimpl_chown(const char *, uid_t, gid_t);
pid_t rump___sysimpl_getpid(void);
int rump___sysimpl_setuid(uid_t);
uid_t rump___sysimpl_getuid(void);
uid_t rump___sysimpl_geteuid(void);
ssize_t rump___sysimpl_recvmsg(int, struct msghdr *, int);
ssize_t rump___sysimpl_sendmsg(int, const struct msghdr *, int);
ssize_t rump___sysimpl_recvfrom(int, void *, size_t, int, struct sockaddr *, socklen_t *);
int rump___sysimpl_accept(int, struct sockaddr *, socklen_t *);
int rump___sysimpl_getpeername(int, struct sockaddr *, socklen_t *);
int rump___sysimpl_getsockname(int, struct sockaddr *, socklen_t *);
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
int rump___sysimpl_ioctl(int, unsigned long, ...);
int rump___sysimpl_revoke(const char *);
int rump___sysimpl_symlink(const char *, const char *);
ssize_t rump___sysimpl_readlink(const char *, char *, size_t);
mode_t rump___sysimpl_umask(mode_t);
int rump___sysimpl_chroot(const char *);
int rump___sysimpl_getgroups(int, gid_t *);
int rump___sysimpl_setgroups(int, const gid_t *);
int rump___sysimpl_getpgrp(void);
int rump___sysimpl_setpgid(pid_t, pid_t);
int rump___sysimpl_dup2(int, int);
int rump___sysimpl_fcntl(int, int, ...);
int rump___sysimpl_select50(int, fd_set *, fd_set *, fd_set *, struct timeval *);
int rump___sysimpl_fsync(int);
int rump___sysimpl_connect(int, const struct sockaddr *, socklen_t);
int rump___sysimpl_bind(int, const struct sockaddr *, socklen_t);
int rump___sysimpl_setsockopt(int, int, int, const void *, socklen_t);
int rump___sysimpl_listen(int, int);
int rump___sysimpl_getsockopt(int, int, int, void *, socklen_t *);
ssize_t rump___sysimpl_readv(int, const struct iovec *, int);
ssize_t rump___sysimpl_writev(int, const struct iovec *, int);
int rump___sysimpl_fchown(int, uid_t, gid_t);
int rump___sysimpl_fchmod(int, mode_t);
int rump___sysimpl_setreuid(uid_t, uid_t);
int rump___sysimpl_setregid(gid_t, gid_t);
int rump___sysimpl_rename(const char *, const char *);
int rump___sysimpl_flock(int, int);
int rump___sysimpl_mkfifo(const char *, mode_t);
ssize_t rump___sysimpl_sendto(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
int rump___sysimpl_shutdown(int, int);
int rump___sysimpl_socketpair(int, int, int, int *);
int rump___sysimpl_mkdir(const char *, mode_t);
int rump___sysimpl_rmdir(const char *);
int rump___sysimpl_setsid(void);
ssize_t rump___sysimpl_pread(int, void *, size_t, off_t);
ssize_t rump___sysimpl_pwrite(int, const void *, size_t, off_t);
int rump___sysimpl_setgid(gid_t);
int rump___sysimpl_setegid(gid_t);
int rump___sysimpl_seteuid(uid_t);
int rump___sysimpl_getrlimit(int, struct rlimit *);
int rump___sysimpl_setrlimit(int, const struct rlimit *);
off_t rump___sysimpl_lseek(int, off_t, int);
int rump___sysimpl_truncate(const char *, off_t);
int rump___sysimpl_ftruncate(int, off_t);
int rump___sysimpl___sysctl(const int *, unsigned int, void *, size_t *, const void *, size_t);
pid_t rump___sysimpl_getpgid(pid_t);
int rump___sysimpl_reboot(int, char *);
int rump___sysimpl_poll(struct pollfd *, unsigned int, int);
int rump___sysimpl_fdatasync(int);
int rump___sysimpl_modctl(int, void *);
int rump___sysimpl_lchmod(const char *, mode_t);
int rump___sysimpl_lchown(const char *, uid_t, gid_t);
pid_t rump___sysimpl_getsid(pid_t);
ssize_t rump___sysimpl_preadv(int, const struct iovec *, int, off_t);
ssize_t rump___sysimpl_pwritev(int, const struct iovec *, int, off_t);
int rump___sysimpl_fsync_range(int, int, off_t, off_t);
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
int rump___sysimpl_stat(const char *, struct stat *);
int rump___sysimpl_fstat(int, struct stat *);
int rump___sysimpl_lstat(const char *, struct stat *);
int rump___sysimpl_socket(int, int, int);
int rump___sysimpl_posix_fadvise(int, off_t, off_t, int);
int rump___sysimpl_pipe2(int *, int);
int rump___sysimpl_dup3(int, int, int);
int rump___sysimpl_paccept(int, struct sockaddr *, socklen_t *, const sigset_t *, int);
int rump___sysimpl_linkat(int, const char *, int, const char *, int);
int rump___sysimpl_renameat(int, const char *, int, const char *);
int rump___sysimpl_mkfifoat(int, const char *, mode_t);
int rump___sysimpl_mknodat(int, const char *, mode_t, uint32_t);
int rump___sysimpl_mkdirat(int, const char *, mode_t);
int rump___sysimpl_faccessat(int, const char *, int, int);
int rump___sysimpl_fchmodat(int, const char *, mode_t, int);
int rump___sysimpl_fchownat(int, const char *, uid_t, gid_t, int);
int rump___sysimpl_fexecve(int, char *const *, char *const *);
int rump___sysimpl_fstatat(int, const char *, struct stat *, int);
int rump___sysimpl_utimensat(int, const char *, const struct timespec *, int);
int rump___sysimpl_openat(int, const char *, int, ...);
int rump___sysimpl_readlinkat(int, const char *, char *, size_t);
int rump___sysimpl_symlinkat(const char *, int, const char *);
int rump___sysimpl_unlinkat(int, const char *, int);
int rump___sysimpl_futimens(int, const struct timespec *);
int rump___sysimpl_pipe(int *);
]]

local C = {
  accept = ffi.C.rump___sysimpl_accept,
  access = ffi.C.rump___sysimpl_access,
  bind = ffi.C.rump___sysimpl_bind,
  chdir = ffi.C.rump___sysimpl_chdir,
  chflags = ffi.C.rump___sysimpl_chflags,
  chmod = ffi.C.rump___sysimpl_chmod,
  chown = ffi.C.rump___sysimpl_chown,
  chroot = ffi.C.rump___sysimpl_chroot,
  close = ffi.C.rump___sysimpl_close,
  connect = ffi.C.rump___sysimpl_connect,
  dup2 = ffi.C.rump___sysimpl_dup2,
  dup3 = ffi.C.rump___sysimpl_dup3,
  dup = ffi.C.rump___sysimpl_dup,
  faccessat = ffi.C.rump___sysimpl_faccessat,
  fchdir = ffi.C.rump___sysimpl_fchdir,
  fchflags = ffi.C.rump___sysimpl_fchflags,
  fchmodat = ffi.C.rump___sysimpl_fchmodat,
  fchmod = ffi.C.rump___sysimpl_fchmod,
  fchownat = ffi.C.rump___sysimpl_fchownat,
  fchown = ffi.C.rump___sysimpl_fchown,
  fcntl = ffi.C.rump___sysimpl_fcntl,
  fdatasync = ffi.C.rump___sysimpl_fdatasync,
  fexecve = ffi.C.rump___sysimpl_fexecve,
  fgetxattr = ffi.C.rump___sysimpl_fgetxattr,
  flistxattr = ffi.C.rump___sysimpl_flistxattr,
  flock = ffi.C.rump___sysimpl_flock,
  fremovexattr = ffi.C.rump___sysimpl_fremovexattr,
  fsetxattr = ffi.C.rump___sysimpl_fsetxattr,
  fsync_range = ffi.C.rump___sysimpl_fsync_range,
  fsync = ffi.C.rump___sysimpl_fsync,
  ftruncate = ffi.C.rump___sysimpl_ftruncate,
  futimens = ffi.C.rump___sysimpl_futimens,
  getegid = ffi.C.rump___sysimpl_getegid,
  geteuid = ffi.C.rump___sysimpl_geteuid,
  getgid = ffi.C.rump___sysimpl_getgid,
  getgroups = ffi.C.rump___sysimpl_getgroups,
  __getlogin = ffi.C.rump___sysimpl___getlogin,
  getpeername = ffi.C.rump___sysimpl_getpeername,
  getpgid = ffi.C.rump___sysimpl_getpgid,
  getpgrp = ffi.C.rump___sysimpl_getpgrp,
  getpid = ffi.C.rump___sysimpl_getpid,
  getppid = ffi.C.rump___sysimpl_getppid,
  getrlimit = ffi.C.rump___sysimpl_getrlimit,
  getsid = ffi.C.rump___sysimpl_getsid,
  getsockname = ffi.C.rump___sysimpl_getsockname,
  getsockopt = ffi.C.rump___sysimpl_getsockopt,
  getuid = ffi.C.rump___sysimpl_getuid,
  getxattr = ffi.C.rump___sysimpl_getxattr,
  ioctl = ffi.C.rump___sysimpl_ioctl,
  lchmod = ffi.C.rump___sysimpl_lchmod,
  lchown = ffi.C.rump___sysimpl_lchown,
  lgetxattr = ffi.C.rump___sysimpl_lgetxattr,
  linkat = ffi.C.rump___sysimpl_linkat,
  link = ffi.C.rump___sysimpl_link,
  listen = ffi.C.rump___sysimpl_listen,
  listxattr = ffi.C.rump___sysimpl_listxattr,
  llistxattr = ffi.C.rump___sysimpl_llistxattr,
  lremovexattr = ffi.C.rump___sysimpl_lremovexattr,
  lseek = ffi.C.rump___sysimpl_lseek,
  lsetxattr = ffi.C.rump___sysimpl_lsetxattr,
  mkdirat = ffi.C.rump___sysimpl_mkdirat,
  mkdir = ffi.C.rump___sysimpl_mkdir,
  mkfifoat = ffi.C.rump___sysimpl_mkfifoat,
  mkfifo = ffi.C.rump___sysimpl_mkfifo,
  mknod = ffi.C.rump___sysimpl_mknod,
  mknodat = ffi.C.rump___sysimpl_mknodat,
  modctl = ffi.C.rump___sysimpl_modctl,
  openat = ffi.C.rump___sysimpl_openat,
  open = ffi.C.rump___sysimpl_open,
  paccept = ffi.C.rump___sysimpl_paccept,
  pipe2 = ffi.C.rump___sysimpl_pipe2,
  poll = ffi.C.rump___sysimpl_poll,
  pread = ffi.C.rump___sysimpl_pread,
  preadv = ffi.C.rump___sysimpl_preadv,
  pwrite = ffi.C.rump___sysimpl_pwrite,
  pwritev = ffi.C.rump___sysimpl_pwritev,
  readlinkat = ffi.C.rump___sysimpl_readlinkat,
  readlink = ffi.C.rump___sysimpl_readlink,
  read = ffi.C.rump___sysimpl_read,
  readv = ffi.C.rump___sysimpl_readv,
  reboot = ffi.C.rump___sysimpl_reboot,
  recvfrom = ffi.C.rump___sysimpl_recvfrom,
  recvmsg = ffi.C.rump___sysimpl_recvmsg,
  removexattr = ffi.C.rump___sysimpl_removexattr,
  renameat = ffi.C.rump___sysimpl_renameat,
  rename = ffi.C.rump___sysimpl_rename,
  revoke = ffi.C.rump___sysimpl_revoke,
  rmdir = ffi.C.rump___sysimpl_rmdir,
  select = ffi.C.rump___sysimpl_select50,
  sendmsg = ffi.C.rump___sysimpl_sendmsg,
  sendto = ffi.C.rump___sysimpl_sendto,
  setegid = ffi.C.rump___sysimpl_setegid,
  seteuid = ffi.C.rump___sysimpl_seteuid,
  setgid = ffi.C.rump___sysimpl_setgid,
  setgroups = ffi.C.rump___sysimpl_setgroups,
  __setlogin = ffi.C.rump___sysimpl___setlogin,
  setpgid = ffi.C.rump___sysimpl_setpgid,
  setregid = ffi.C.rump___sysimpl_setregid,
  setreuid = ffi.C.rump___sysimpl_setreuid,
  setrlimit = ffi.C.rump___sysimpl_setrlimit,
  setsid = ffi.C.rump___sysimpl_setsid,
  setsockopt = ffi.C.rump___sysimpl_setsockopt,
  setuid = ffi.C.rump___sysimpl_setuid,
  setxattr = ffi.C.rump___sysimpl_setxattr,
  shutdown = ffi.C.rump___sysimpl_shutdown,
  socketpair = ffi.C.rump___sysimpl_socketpair,
  symlinkat = ffi.C.rump___sysimpl_symlinkat,
  symlink = ffi.C.rump___sysimpl_symlink,
  sync = ffi.C.rump___sysimpl_sync,
  __sysctl = ffi.C.rump___sysimpl___sysctl,
  truncate = ffi.C.rump___sysimpl_truncate,
  umask = ffi.C.rump___sysimpl_umask,
  unlinkat = ffi.C.rump___sysimpl_unlinkat,
  unlink = ffi.C.rump___sysimpl_unlink,
  utimensat = ffi.C.rump___sysimpl_utimensat,
  write = ffi.C.rump___sysimpl_write,
  writev = ffi.C.rump___sysimpl_writev,
}

-- TODO this mostly works, but not for eg mmap where should return a pointer -1...
local function nosys()
  ffi.errno(38) -- Linux ENOSYS
  return -1
end

setmetatable(C, {__index = function() return nosys end})

return C

end

return {init = init}


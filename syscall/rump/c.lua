-- define C functions for rump

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local function init(abi)

local ffi = require "ffi"

local cdef

if abi.host == abi.os then -- types same on host and rump so no renaming
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
int rump___sysimpl_mknod(const char *, _netbsd_mode_t, uint32_t);
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
int rump___sysimpl_ioctl(int, unsigned long, ...);
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
int rump___sysimpl___sysctl(const int *, unsigned int, void *, size_t *, const void *, size_t);
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
int rump___sysimpl_kevent(int, const struct _netbsd_kevent *, size_t, struct _netbsd_kevent *, size_t, const struct _netbsd_timespec *);
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
int rump___sysimpl_pollts(struct _netbsd_pollfd *, unsigned int, const struct _netbsd_timespec *, const _netbsd_sigset_t *);
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
int rump___sysimpl_mknodat(int, const char *, _netbsd_mode_t, uint32_t);
int rump___sysimpl_mkdirat(int, const char *, _netbsd_mode_t);
int rump___sysimpl_faccessat(int, const char *, int, int);
int rump___sysimpl_fchmodat(int, const char *, _netbsd_mode_t, int);
int rump___sysimpl_fchownat(int, const char *, uid_t, gid_t, int);
int rump___sysimpl_fexecve(int, char *const *, char *const *);
int rump___sysimpl_fstatat(int, const char *, struct _netbsd_stat *, int);
int rump___sysimpl_utimensat(int, const char *, const struct _netbsd_timespec *, int);
int rump___sysimpl_openat(int, const char *, int, ...);
int rump___sysimpl_readlinkat(int, const char *, char *, size_t);
int rump___sysimpl_symlinkat(const char *, int, const char *);
int rump___sysimpl_unlinkat(int, const char *, int);
int rump___sysimpl_futimens(int, const struct _netbsd_timespec *);
int rump___sysimpl___quotactl(const char *, struct _netbsd_quotactl_args *);
int rump___sysimpl_pipe(int *);
]]

local rump = abi.modules.rump

local C = {
  accept = rump.rump___sysimpl_accept,
  access = rump.rump___sysimpl_access,
  bind = rump.rump___sysimpl_bind,
  chdir = rump.rump___sysimpl_chdir,
  chflags = rump.rump___sysimpl_chflags,
  chmod = rump.rump___sysimpl_chmod,
  chown = rump.rump___sysimpl_chown,
  chroot = rump.rump___sysimpl_chroot,
  close = rump.rump___sysimpl_close,
  connect = rump.rump___sysimpl_connect,
  dup2 = rump.rump___sysimpl_dup2,
  dup3 = rump.rump___sysimpl_dup3,
  dup = rump.rump___sysimpl_dup,
  extattrctl = rump.rump___sysimpl_extattrctl,
  extattr_delete_fd = rump.rump___sysimpl_extattr_delete_fd,
  extattr_delete_file = rump.rump___sysimpl_extattr_delete_file,
  extattr_delete_link = rump.rump___sysimpl_extattr_delete_link,
  extattr_get_fd = rump.rump___sysimpl_extattr_get_fd,
  extattr_get_file = rump.rump___sysimpl_extattr_get_file,
  extattr_get_link = rump.rump___sysimpl_extattr_get_link,
  extattr_list_fd = rump.rump___sysimpl_extattr_list_fd,
  extattr_list_file = rump.rump___sysimpl_extattr_list_file,
  extattr_list_link = rump.rump___sysimpl_extattr_list_link,
  extattr_set_fd = rump.rump___sysimpl_extattr_set_fd,
  extattr_set_file = rump.rump___sysimpl_extattr_set_file,
  extattr_set_link = rump.rump___sysimpl_extattr_set_link,
  faccessat = rump.rump___sysimpl_faccessat,
  fchdir = rump.rump___sysimpl_fchdir,
  fchflags = rump.rump___sysimpl_fchflags,
  fchmodat = rump.rump___sysimpl_fchmodat,
  fchmod = rump.rump___sysimpl_fchmod,
  fchownat = rump.rump___sysimpl_fchownat,
  fchown = rump.rump___sysimpl_fchown,
  fchroot = rump.rump___sysimpl_fchroot,
  fcntl = rump.rump___sysimpl_fcntl,
  fdatasync = rump.rump___sysimpl_fdatasync,
  fexecve = rump.rump___sysimpl_fexecve,
  fgetxattr = rump.rump___sysimpl_fgetxattr,
  fhopen = rump.rump___sysimpl_fhopen40,
  fhstat = rump.rump___sysimpl_fhstat50,
  fhstatvfs = rump.rump___sysimpl_fhstatvfs140,
  flistxattr = rump.rump___sysimpl_flistxattr,
  flock = rump.rump___sysimpl_flock,
  fpathconf = rump.rump___sysimpl_fpathconf,
  fremovexattr = rump.rump___sysimpl_fremovexattr,
  fsetxattr = rump.rump___sysimpl_fsetxattr,
  fstat = rump.rump___sysimpl_fstat50,
  fstatat = rump.rump___sysimpl_fstatat,
  fstatvfs1 = rump.rump___sysimpl_fstatvfs1,
  fsync_range = rump.rump___sysimpl_fsync_range,
  fsync = rump.rump___sysimpl_fsync,
  ftruncate = rump.rump___sysimpl_ftruncate,
  futimens = rump.rump___sysimpl_futimens,
  futimes = rump.rump___sysimpl_futimes50,
  getcwd = rump.rump___sysimpl___getcwd,
  getdents = rump.rump___sysimpl_getdents30,
  getegid = rump.rump___sysimpl_getegid,
  geteuid = rump.rump___sysimpl_geteuid,
  getfh = rump.rump___sysimpl_getfh30,
  getgid = rump.rump___sysimpl_getgid,
  getgroups = rump.rump___sysimpl_getgroups,
  __getlogin = rump.rump___sysimpl___getlogin,
  getpeername = rump.rump___sysimpl_getpeername,
  getpgid = rump.rump___sysimpl_getpgid,
  getpgrp = rump.rump___sysimpl_getpgrp,
  getpid = rump.rump___sysimpl_getpid,
  getppid = rump.rump___sysimpl_getppid,
  getrlimit = rump.rump___sysimpl_getrlimit,
  getsid = rump.rump___sysimpl_getsid,
  getsockname = rump.rump___sysimpl_getsockname,
  getsockopt = rump.rump___sysimpl_getsockopt,
  getuid = rump.rump___sysimpl_getuid,
  getvfsstat = rump.rump___sysimpl_getvfsstat,
  getxattr = rump.rump___sysimpl_getxattr,
  ioctl = rump.rump___sysimpl_ioctl,
  issetugid = rump.rump___sysimpl_issetugid,
  kevent = rump.rump___sysimpl_kevent,
  kqueue1 = rump.rump___sysimpl_kqueue1,
  kqueue = rump.rump___sysimpl_kqueue,
  _ksem_close = rump.rump___sysimpl__ksem_close,
  _ksem_destroy = rump.rump___sysimpl__ksem_destroy,
  _ksem_getvalue = rump.rump___sysimpl__ksem_getvalue,
  _ksem_init = rump.rump___sysimpl__ksem_init,
  _ksem_open = rump.rump___sysimpl__ksem_open,
  _ksem_post = rump.rump___sysimpl__ksem_post,
--  _ksem_timedwait = rump.rump___sysimpl__ksem_timedwait,
  _ksem_trywait = rump.rump___sysimpl__ksem_trywait,
  _ksem_unlink = rump.rump___sysimpl__ksem_unlink,
  _ksem_wait = rump.rump___sysimpl__ksem_wait,
  lchflags = rump.rump___sysimpl_lchflags,
  lchmod = rump.rump___sysimpl_lchmod,
  lchown = rump.rump___sysimpl_lchown,
  lgetxattr = rump.rump___sysimpl_lgetxattr,
  linkat = rump.rump___sysimpl_linkat,
  link = rump.rump___sysimpl_link,
  listen = rump.rump___sysimpl_listen,
  listxattr = rump.rump___sysimpl_listxattr,
  llistxattr = rump.rump___sysimpl_llistxattr,
  lremovexattr = rump.rump___sysimpl_lremovexattr,
  lseek = rump.rump___sysimpl_lseek,
  lsetxattr = rump.rump___sysimpl_lsetxattr,
  lstat = rump.rump___sysimpl_lstat50,
  lutimes = rump.rump___sysimpl_lutimes50,
  mkdirat = rump.rump___sysimpl_mkdirat,
  mkdir = rump.rump___sysimpl_mkdir,
  mkfifoat = rump.rump___sysimpl_mkfifoat,
  mkfifo = rump.rump___sysimpl_mkfifo,
  mknod = rump.rump___sysimpl_mknod,
  mknodat = rump.rump___sysimpl_mknodat,
  modctl = rump.rump___sysimpl_modctl,
  mount = rump.rump___sysimpl_mount50,
  nfssvc = rump.rump___sysimpl_nfssvc,
  openat = rump.rump___sysimpl_openat,
  open = rump.rump___sysimpl_open,
  paccept = rump.rump___sysimpl_paccept,
  pathconf = rump.rump___sysimpl_pathconf,
  pipe2 = rump.rump___sysimpl_pipe2,
  poll = rump.rump___sysimpl_poll,
  pollts = rump.rump___sysimpl_pollts,
  posix_fadvise = rump.rump___sysimpl_posix_fadvise50,
  pread = rump.rump___sysimpl_pread,
  preadv = rump.rump___sysimpl_preadv,
  pselect = rump.rump___sysimpl_pselect50,
  pwrite = rump.rump___sysimpl_pwrite,
  pwritev = rump.rump___sysimpl_pwritev,
  __quotactl = rump.rump___sysimpl___quotactl,
  readlinkat = rump.rump___sysimpl_readlinkat,
  readlink = rump.rump___sysimpl_readlink,
  read = rump.rump___sysimpl_read,
  readv = rump.rump___sysimpl_readv,
  reboot = rump.rump___sysimpl_reboot,
  recvfrom = rump.rump___sysimpl_recvfrom,
  recvmsg = rump.rump___sysimpl_recvmsg,
  removexattr = rump.rump___sysimpl_removexattr,
  renameat = rump.rump___sysimpl_renameat,
  rename = rump.rump___sysimpl_rename,
  revoke = rump.rump___sysimpl_revoke,
  rmdir = rump.rump___sysimpl_rmdir,
  select = rump.rump___sysimpl_select50,
  sendmsg = rump.rump___sysimpl_sendmsg,
  sendto = rump.rump___sysimpl_sendto,
  setegid = rump.rump___sysimpl_setegid,
  seteuid = rump.rump___sysimpl_seteuid,
  setgid = rump.rump___sysimpl_setgid,
  setgroups = rump.rump___sysimpl_setgroups,
  __setlogin = rump.rump___sysimpl___setlogin,
  setpgid = rump.rump___sysimpl_setpgid,
  setregid = rump.rump___sysimpl_setregid,
  setreuid = rump.rump___sysimpl_setreuid,
  setrlimit = rump.rump___sysimpl_setrlimit,
  setsid = rump.rump___sysimpl_setsid,
  setsockopt = rump.rump___sysimpl_setsockopt,
  setuid = rump.rump___sysimpl_setuid,
  setxattr = rump.rump___sysimpl_setxattr,
  shutdown = rump.rump___sysimpl_shutdown,
  socket = rump.rump___sysimpl_socket30,
  socketpair = rump.rump___sysimpl_socketpair,
  stat = rump.rump___sysimpl_stat50,
  statvfs1 = rump.rump___sysimpl_statvfs1,
  symlinkat = rump.rump___sysimpl_symlinkat,
  symlink = rump.rump___sysimpl_symlink,
  sync = rump.rump___sysimpl_sync,
  __sysctl = rump.rump___sysimpl___sysctl,
  truncate = rump.rump___sysimpl_truncate,
  umask = rump.rump___sysimpl_umask,
  unlinkat = rump.rump___sysimpl_unlinkat,
  unlink = rump.rump___sysimpl_unlink,
  unmount = rump.rump___sysimpl_unmount,
  utimensat = rump.rump___sysimpl_utimensat,
  utimes = rump.rump___sysimpl_utimes50,
  write = rump.rump___sysimpl_write,
  writev = rump.rump___sysimpl_writev,
}

-- TODO this mostly works, but not for eg mmap where should return a pointer -1...
local function nosys()
  ffi.errno(78) -- NetBSD ENOSYS
  return -1
end

setmetatable(C, {__index = function() return nosys end})

return C

end

return {init = init}


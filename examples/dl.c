/* dlopen/dlsym implementation for staticly linking - under development */

#include <dlfcn.h>
#include <string.h>
#include <stdio.h>

#include <sys/types.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <dirent.h>
#include <sys/uio.h>
#include <sys/file.h>
#include <sys/socket.h>

/* these are not defined in headers, prototype does not matter here as LuaJIT knows it */
int __getcwd();
int __getlogin();
int __setlogin();
int __quotactl();

/*
ls ljsyscall/obj/{include,syscall,test}.* | sed 's@ljsyscall/obj/@extern const char *luaJIT_BC_@g' | sed 's/\.o$/[];/g' | sed 's/\./_/g'
*/

//extern const char *luaJIT_BC_include_ffi-reflect_reflect[];
extern const char *luaJIT_BC_include_luaunit_luaunit[];
extern const char *luaJIT_BC_include_strict_strict[];
extern const char *luaJIT_BC_syscall_abi[];
extern const char *luaJIT_BC_syscall_compat[];
extern const char *luaJIT_BC_syscall_features[];
extern const char *luaJIT_BC_syscall_ffifunctions[];
extern const char *luaJIT_BC_syscall_ffitypes[];
extern const char *luaJIT_BC_syscall_helpers[];
extern const char *luaJIT_BC_syscall_init[];
extern const char *luaJIT_BC_syscall_libc[];
extern const char *luaJIT_BC_syscall_linux_arm_constants[];
extern const char *luaJIT_BC_syscall_linux_arm_ffitypes[];
extern const char *luaJIT_BC_syscall_linux_arm_ioctl[];
extern const char *luaJIT_BC_syscall_linux_cgroup[];
extern const char *luaJIT_BC_syscall_linux_c[];
extern const char *luaJIT_BC_syscall_linux_compat[];
extern const char *luaJIT_BC_syscall_linux_constants[];
extern const char *luaJIT_BC_syscall_linux_errors[];
extern const char *luaJIT_BC_syscall_linux_fcntl[];
extern const char *luaJIT_BC_syscall_linux_ffifunctions[];
extern const char *luaJIT_BC_syscall_linux_ffitypes[];
extern const char *luaJIT_BC_syscall_linux_ioctl[];
extern const char *luaJIT_BC_syscall_linux_mips_constants[];
extern const char *luaJIT_BC_syscall_linux_mips_ffitypes[];
extern const char *luaJIT_BC_syscall_linux_mips_ioctl[];
extern const char *luaJIT_BC_syscall_linux_netfilter[];
extern const char *luaJIT_BC_syscall_linux_nl[];
extern const char *luaJIT_BC_syscall_linux_ppc_constants[];
extern const char *luaJIT_BC_syscall_linux_ppc_ffitypes[];
extern const char *luaJIT_BC_syscall_linux_ppc_ioctl[];
extern const char *luaJIT_BC_syscall_linux_sockopt[];
extern const char *luaJIT_BC_syscall_linux_syscalls[];
extern const char *luaJIT_BC_syscall_linux_types[];
extern const char *luaJIT_BC_syscall_linux_util[];
extern const char *luaJIT_BC_syscall_linux_x64_constants[];
extern const char *luaJIT_BC_syscall_linux_x64_ffitypes[];
extern const char *luaJIT_BC_syscall_linux_x64_ioctl[];
extern const char *luaJIT_BC_syscall_linux_x86_constants[];
extern const char *luaJIT_BC_syscall_linux_x86_ffitypes[];
extern const char *luaJIT_BC_syscall_linux_x86_ioctl[];
extern const char *luaJIT_BC_syscall_methods[];
extern const char *luaJIT_BC_syscall_netbsd_c[];
extern const char *luaJIT_BC_syscall_netbsd_constants[];
extern const char *luaJIT_BC_syscall_netbsd_errors[];
extern const char *luaJIT_BC_syscall_netbsd_fcntl[];
extern const char *luaJIT_BC_syscall_netbsd_ffifunctions[];
extern const char *luaJIT_BC_syscall_netbsd_ffitypes[];
extern const char *luaJIT_BC_syscall_netbsd_ioctl[];
extern const char *luaJIT_BC_syscall_netbsd_syscalls[];
extern const char *luaJIT_BC_syscall_netbsd_types[];
extern const char *luaJIT_BC_syscall_netbsd_util[];
extern const char *luaJIT_BC_syscall[];
extern const char *luaJIT_BC_syscall_osx_c[];
extern const char *luaJIT_BC_syscall_osx_constants[];
extern const char *luaJIT_BC_syscall_osx_errors[];
extern const char *luaJIT_BC_syscall_osx_fcntl[];
extern const char *luaJIT_BC_syscall_osx_ffifunctions[];
extern const char *luaJIT_BC_syscall_osx_ffitypes[];
extern const char *luaJIT_BC_syscall_osx_ioctl[];
extern const char *luaJIT_BC_syscall_osx_syscalls[];
extern const char *luaJIT_BC_syscall_osx_types[];
extern const char *luaJIT_BC_syscall_osx_util[];
extern const char *luaJIT_BC_syscall_rump_abi[];
extern const char *luaJIT_BC_syscall_rump_c[];
extern const char *luaJIT_BC_syscall_rump_constants[];
extern const char *luaJIT_BC_syscall_rump_ffirump[];
extern const char *luaJIT_BC_syscall_rump_init[];
extern const char *luaJIT_BC_syscall_rump_linux[];
extern const char *luaJIT_BC_syscall_shared_ffitypes[];
extern const char *luaJIT_BC_syscall_shared_types[];
extern const char *luaJIT_BC_syscall_syscalls[];
extern const char *luaJIT_BC_syscall_types[];
extern const char *luaJIT_BC_syscall_util[];
extern const char *luaJIT_BC_test_linux[];
extern const char *luaJIT_BC_test_netbsd[];
extern const char *luaJIT_BC_test_rump[];
extern const char *luaJIT_BC_test_test[];

static char dlfcn_error[] = "Service unavailable";

void *dlopen(const char *filename, int flag) {
  if (filename)
    return NULL;

  return (void *)1;
}

char *dlerror(void) {
  return dlfcn_error;
}

/*
ls ljsyscall/obj/{include,syscall,test}.* | sed 's@ljsyscall/obj/@@g' | sed 's/\.o$//g' | sed 's/\./_/g' | sed 's/\(.*\)/  if (strcmp(symbol, "luaJIT_BC_\1") == 0) return luaJIT_BC_\1;/g'
*/

void *dlsym(void *handle, const char *symbol) {
  if (! handle)
    return NULL;
  /* replace with hash table, or Lua table */

  //if (strcmp(symbol, "luaJIT_BC_include_ffi-reflect_reflect") == 0) return luaJIT_BC_include_ffi-reflect_reflect;
  if (strcmp(symbol, "luaJIT_BC_include_luaunit_luaunit") == 0) return luaJIT_BC_include_luaunit_luaunit;
  if (strcmp(symbol, "luaJIT_BC_include_strict_strict") == 0) return luaJIT_BC_include_strict_strict;
  if (strcmp(symbol, "luaJIT_BC_syscall_abi") == 0) return luaJIT_BC_syscall_abi;
  if (strcmp(symbol, "luaJIT_BC_syscall_compat") == 0) return luaJIT_BC_syscall_compat;
  if (strcmp(symbol, "luaJIT_BC_syscall_features") == 0) return luaJIT_BC_syscall_features;
  if (strcmp(symbol, "luaJIT_BC_syscall_ffifunctions") == 0) return luaJIT_BC_syscall_ffifunctions;
  if (strcmp(symbol, "luaJIT_BC_syscall_ffitypes") == 0) return luaJIT_BC_syscall_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_helpers") == 0) return luaJIT_BC_syscall_helpers;
  if (strcmp(symbol, "luaJIT_BC_syscall_init") == 0) return luaJIT_BC_syscall_init;
  if (strcmp(symbol, "luaJIT_BC_syscall_libc") == 0) return luaJIT_BC_syscall_libc;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_arm_constants") == 0) return luaJIT_BC_syscall_linux_arm_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_arm_ffitypes") == 0) return luaJIT_BC_syscall_linux_arm_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_arm_ioctl") == 0) return luaJIT_BC_syscall_linux_arm_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_cgroup") == 0) return luaJIT_BC_syscall_linux_cgroup;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_c") == 0) return luaJIT_BC_syscall_linux_c;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_compat") == 0) return luaJIT_BC_syscall_linux_compat;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_constants") == 0) return luaJIT_BC_syscall_linux_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_errors") == 0) return luaJIT_BC_syscall_linux_errors;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_fcntl") == 0) return luaJIT_BC_syscall_linux_fcntl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_ffifunctions") == 0) return luaJIT_BC_syscall_linux_ffifunctions;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_ffitypes") == 0) return luaJIT_BC_syscall_linux_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_ioctl") == 0) return luaJIT_BC_syscall_linux_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_mips_constants") == 0) return luaJIT_BC_syscall_linux_mips_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_mips_ffitypes") == 0) return luaJIT_BC_syscall_linux_mips_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_mips_ioctl") == 0) return luaJIT_BC_syscall_linux_mips_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_netfilter") == 0) return luaJIT_BC_syscall_linux_netfilter;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_nl") == 0) return luaJIT_BC_syscall_linux_nl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_ppc_constants") == 0) return luaJIT_BC_syscall_linux_ppc_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_ppc_ffitypes") == 0) return luaJIT_BC_syscall_linux_ppc_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_ppc_ioctl") == 0) return luaJIT_BC_syscall_linux_ppc_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_sockopt") == 0) return luaJIT_BC_syscall_linux_sockopt;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_syscalls") == 0) return luaJIT_BC_syscall_linux_syscalls;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_types") == 0) return luaJIT_BC_syscall_linux_types;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_util") == 0) return luaJIT_BC_syscall_linux_util;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_x64_constants") == 0) return luaJIT_BC_syscall_linux_x64_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_x64_ffitypes") == 0) return luaJIT_BC_syscall_linux_x64_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_x64_ioctl") == 0) return luaJIT_BC_syscall_linux_x64_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_x86_constants") == 0) return luaJIT_BC_syscall_linux_x86_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_x86_ffitypes") == 0) return luaJIT_BC_syscall_linux_x86_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_linux_x86_ioctl") == 0) return luaJIT_BC_syscall_linux_x86_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_methods") == 0) return luaJIT_BC_syscall_methods;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_c") == 0) return luaJIT_BC_syscall_netbsd_c;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_constants") == 0) return luaJIT_BC_syscall_netbsd_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_errors") == 0) return luaJIT_BC_syscall_netbsd_errors;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_fcntl") == 0) return luaJIT_BC_syscall_netbsd_fcntl;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_ffifunctions") == 0) return luaJIT_BC_syscall_netbsd_ffifunctions;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_ffitypes") == 0) return luaJIT_BC_syscall_netbsd_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_ioctl") == 0) return luaJIT_BC_syscall_netbsd_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_syscalls") == 0) return luaJIT_BC_syscall_netbsd_syscalls;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_types") == 0) return luaJIT_BC_syscall_netbsd_types;
  if (strcmp(symbol, "luaJIT_BC_syscall_netbsd_util") == 0) return luaJIT_BC_syscall_netbsd_util;
  if (strcmp(symbol, "luaJIT_BC_syscall") == 0) return luaJIT_BC_syscall;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_c") == 0) return luaJIT_BC_syscall_osx_c;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_constants") == 0) return luaJIT_BC_syscall_osx_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_errors") == 0) return luaJIT_BC_syscall_osx_errors;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_fcntl") == 0) return luaJIT_BC_syscall_osx_fcntl;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_ffifunctions") == 0) return luaJIT_BC_syscall_osx_ffifunctions;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_ffitypes") == 0) return luaJIT_BC_syscall_osx_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_ioctl") == 0) return luaJIT_BC_syscall_osx_ioctl;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_syscalls") == 0) return luaJIT_BC_syscall_osx_syscalls;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_types") == 0) return luaJIT_BC_syscall_osx_types;
  if (strcmp(symbol, "luaJIT_BC_syscall_osx_util") == 0) return luaJIT_BC_syscall_osx_util;
  if (strcmp(symbol, "luaJIT_BC_syscall_rump_abi") == 0) return luaJIT_BC_syscall_rump_abi;
  if (strcmp(symbol, "luaJIT_BC_syscall_rump_c") == 0) return luaJIT_BC_syscall_rump_c;
  if (strcmp(symbol, "luaJIT_BC_syscall_rump_constants") == 0) return luaJIT_BC_syscall_rump_constants;
  if (strcmp(symbol, "luaJIT_BC_syscall_rump_ffirump") == 0) return luaJIT_BC_syscall_rump_ffirump;
  if (strcmp(symbol, "luaJIT_BC_syscall_rump_init") == 0) return luaJIT_BC_syscall_rump_init;
  if (strcmp(symbol, "luaJIT_BC_syscall_rump_linux") == 0) return luaJIT_BC_syscall_rump_linux;
  if (strcmp(symbol, "luaJIT_BC_syscall_shared_ffitypes") == 0) return luaJIT_BC_syscall_shared_ffitypes;
  if (strcmp(symbol, "luaJIT_BC_syscall_shared_types") == 0) return luaJIT_BC_syscall_shared_types;
  if (strcmp(symbol, "luaJIT_BC_syscall_syscalls") == 0) return luaJIT_BC_syscall_syscalls;
  if (strcmp(symbol, "luaJIT_BC_syscall_types") == 0) return luaJIT_BC_syscall_types;
  if (strcmp(symbol, "luaJIT_BC_syscall_util") == 0) return luaJIT_BC_syscall_util;
  if (strcmp(symbol, "luaJIT_BC_test_linux") == 0) return luaJIT_BC_test_linux;
  if (strcmp(symbol, "luaJIT_BC_test_netbsd") == 0) return luaJIT_BC_test_netbsd;
  if (strcmp(symbol, "luaJIT_BC_test_rump") == 0) return luaJIT_BC_test_rump;
  if (strcmp(symbol, "luaJIT_BC_test_test") == 0) return luaJIT_BC_test_test;

  /* syscalls from rump */
/*
cat syscall/rump/c.lua | grep 'ffi.C.rump___sysimpl_' | grep -v - '--' | sed 's/.*rump___sysimpl_//g' | sed 's/,//g' | sed 's/\(.*\)/  if (strcmp(symbol, "\1") == 0) return \1;/g'
*/
  if (strcmp(symbol, "accept") == 0) return accept;
  if (strcmp(symbol, "access") == 0) return access;
  if (strcmp(symbol, "bind") == 0) return bind;
  if (strcmp(symbol, "chdir") == 0) return chdir;
  if (strcmp(symbol, "chflags") == 0) return chflags;
  if (strcmp(symbol, "chmod") == 0) return chmod;
  if (strcmp(symbol, "chown") == 0) return chown;
  if (strcmp(symbol, "chroot") == 0) return chroot;
  if (strcmp(symbol, "close") == 0) return close;
  if (strcmp(symbol, "connect") == 0) return connect;
  if (strcmp(symbol, "dup2") == 0) return dup2;
  if (strcmp(symbol, "dup3") == 0) return dup3;
  if (strcmp(symbol, "dup") == 0) return dup;
  if (strcmp(symbol, "extattrctl") == 0) return extattrctl;
  if (strcmp(symbol, "extattr_delete_fd") == 0) return extattr_delete_fd;
  if (strcmp(symbol, "extattr_delete_file") == 0) return extattr_delete_file;
  if (strcmp(symbol, "extattr_delete_link") == 0) return extattr_delete_link;
  if (strcmp(symbol, "extattr_get_fd") == 0) return extattr_get_fd;
  if (strcmp(symbol, "extattr_get_file") == 0) return extattr_get_file;
  if (strcmp(symbol, "extattr_get_link") == 0) return extattr_get_link;
  if (strcmp(symbol, "extattr_list_fd") == 0) return extattr_list_fd;
  if (strcmp(symbol, "extattr_list_file") == 0) return extattr_list_file;
  if (strcmp(symbol, "extattr_list_link") == 0) return extattr_list_link;
  if (strcmp(symbol, "extattr_set_fd") == 0) return extattr_set_fd;
  if (strcmp(symbol, "extattr_set_file") == 0) return extattr_set_file;
  if (strcmp(symbol, "extattr_set_link") == 0) return extattr_set_link;
  if (strcmp(symbol, "faccessat") == 0) return faccessat;
  if (strcmp(symbol, "fchdir") == 0) return fchdir;
  if (strcmp(symbol, "fchflags") == 0) return fchflags;
  if (strcmp(symbol, "fchmodat") == 0) return fchmodat;
  if (strcmp(symbol, "fchmod") == 0) return fchmod;
  if (strcmp(symbol, "fchownat") == 0) return fchownat;
  if (strcmp(symbol, "fchown") == 0) return fchown;
  if (strcmp(symbol, "fchroot") == 0) return fchroot;
  if (strcmp(symbol, "fcntl") == 0) return fcntl;
  if (strcmp(symbol, "fdatasync") == 0) return fdatasync;
  if (strcmp(symbol, "fgetxattr") == 0) return fgetxattr;
  if (strcmp(symbol, "fhopen40") == 0) return fhopen40;
  if (strcmp(symbol, "fhstat50") == 0) return fhstat50;
  if (strcmp(symbol, "fhstatvfs140") == 0) return fhstatvfs140;
  if (strcmp(symbol, "flistxattr") == 0) return flistxattr;
  if (strcmp(symbol, "flock") == 0) return flock;
  if (strcmp(symbol, "fpathconf") == 0) return fpathconf;
  if (strcmp(symbol, "fremovexattr") == 0) return fremovexattr;
  if (strcmp(symbol, "fsetxattr") == 0) return fsetxattr;
  if (strcmp(symbol, "fstat50") == 0) return fstat50;
  if (strcmp(symbol, "fstatat") == 0) return fstatat;
  if (strcmp(symbol, "fstatvfs1") == 0) return fstatvfs1;
  if (strcmp(symbol, "fsync_range") == 0) return fsync_range;
  if (strcmp(symbol, "fsync") == 0) return fsync;
  if (strcmp(symbol, "ftruncate") == 0) return ftruncate;
  if (strcmp(symbol, "futimens") == 0) return futimens;
  if (strcmp(symbol, "futimes50") == 0) return futimes50;
  if (strcmp(symbol, "__getcwd") == 0) return __getcwd;
  if (strcmp(symbol, "getdents30") == 0) return getdents30;
  if (strcmp(symbol, "getegid") == 0) return getegid;
  if (strcmp(symbol, "geteuid") == 0) return geteuid;
  if (strcmp(symbol, "getfh30") == 0) return getfh30;
  if (strcmp(symbol, "getgid") == 0) return getgid;
  if (strcmp(symbol, "getgroups") == 0) return getgroups;
  if (strcmp(symbol, "__getlogin") == 0) return __getlogin;
  if (strcmp(symbol, "getpeername") == 0) return getpeername;
  if (strcmp(symbol, "getpgid") == 0) return getpgid;
  if (strcmp(symbol, "getpgrp") == 0) return getpgrp;
  if (strcmp(symbol, "getpid") == 0) return getpid;
  if (strcmp(symbol, "getppid") == 0) return getppid;
  if (strcmp(symbol, "getrlimit") == 0) return getrlimit;
  if (strcmp(symbol, "getsid") == 0) return getsid;
  if (strcmp(symbol, "getsockname") == 0) return getsockname;
  if (strcmp(symbol, "getsockopt") == 0) return getsockopt;
  if (strcmp(symbol, "getuid") == 0) return getuid;
  if (strcmp(symbol, "getvfsstat") == 0) return getvfsstat;
  if (strcmp(symbol, "getxattr") == 0) return getxattr;
  if (strcmp(symbol, "ioctl") == 0) return ioctl;
  if (strcmp(symbol, "issetugid") == 0) return issetugid;
  if (strcmp(symbol, "kevent") == 0) return kevent;
  if (strcmp(symbol, "kqueue1") == 0) return kqueue1;
  if (strcmp(symbol, "kqueue") == 0) return kqueue;
  if (strcmp(symbol, "_ksem_close") == 0) return _ksem_close;
  if (strcmp(symbol, "_ksem_destroy") == 0) return _ksem_destroy;
  if (strcmp(symbol, "_ksem_getvalue") == 0) return _ksem_getvalue;
  if (strcmp(symbol, "_ksem_init") == 0) return _ksem_init;
  if (strcmp(symbol, "_ksem_open") == 0) return _ksem_open;
  if (strcmp(symbol, "_ksem_post") == 0) return _ksem_post;
  if (strcmp(symbol, "_ksem_trywait") == 0) return _ksem_trywait;
  if (strcmp(symbol, "_ksem_unlink") == 0) return _ksem_unlink;
  if (strcmp(symbol, "_ksem_wait") == 0) return _ksem_wait;
  if (strcmp(symbol, "lchflags") == 0) return lchflags;
  if (strcmp(symbol, "lchmod") == 0) return lchmod;
  if (strcmp(symbol, "lchown") == 0) return lchown;
  if (strcmp(symbol, "lgetxattr") == 0) return lgetxattr;
  if (strcmp(symbol, "linkat") == 0) return linkat;
  if (strcmp(symbol, "link") == 0) return link;
  if (strcmp(symbol, "listen") == 0) return listen;
  if (strcmp(symbol, "listxattr") == 0) return listxattr;
  if (strcmp(symbol, "llistxattr") == 0) return llistxattr;
  if (strcmp(symbol, "lremovexattr") == 0) return lremovexattr;
  if (strcmp(symbol, "lseek") == 0) return lseek;
  if (strcmp(symbol, "lsetxattr") == 0) return lsetxattr;
  if (strcmp(symbol, "lstat50") == 0) return lstat50;
  if (strcmp(symbol, "lutimes50") == 0) return lutimes50;
  if (strcmp(symbol, "mkdirat") == 0) return mkdirat;
  if (strcmp(symbol, "mkdir") == 0) return mkdir;
  if (strcmp(symbol, "mkfifoat") == 0) return mkfifoat;
  if (strcmp(symbol, "mkfifo") == 0) return mkfifo;
  if (strcmp(symbol, "mknod") == 0) return mknod;
  if (strcmp(symbol, "mknodat") == 0) return mknodat;
  if (strcmp(symbol, "modctl") == 0) return modctl;
  if (strcmp(symbol, "mount50") == 0) return mount50;
  if (strcmp(symbol, "nfssvc") == 0) return nfssvc;
  if (strcmp(symbol, "openat") == 0) return openat;
  if (strcmp(symbol, "open") == 0) return open;
  if (strcmp(symbol, "paccept") == 0) return paccept;
  if (strcmp(symbol, "pathconf") == 0) return pathconf;
  if (strcmp(symbol, "pipe2") == 0) return pipe2;
  if (strcmp(symbol, "poll") == 0) return poll;
  if (strcmp(symbol, "pollts") == 0) return pollts;
  if (strcmp(symbol, "posix_fadvise50") == 0) return posix_fadvise50;
  if (strcmp(symbol, "pread") == 0) return pread;
  if (strcmp(symbol, "preadv") == 0) return preadv;
  if (strcmp(symbol, "pselect50") == 0) return pselect50;
  if (strcmp(symbol, "pwrite") == 0) return pwrite;
  if (strcmp(symbol, "pwritev") == 0) return pwritev;
  if (strcmp(symbol, "__quotactl") == 0) return __quotactl;
  if (strcmp(symbol, "readlinkat") == 0) return readlinkat;
  if (strcmp(symbol, "readlink") == 0) return readlink;
  if (strcmp(symbol, "read") == 0) return read;
  if (strcmp(symbol, "readv") == 0) return readv;
  if (strcmp(symbol, "reboot") == 0) return reboot;
  if (strcmp(symbol, "recvfrom") == 0) return recvfrom;
  if (strcmp(symbol, "recvmsg") == 0) return recvmsg;
  if (strcmp(symbol, "removexattr") == 0) return removexattr;
  if (strcmp(symbol, "renameat") == 0) return renameat;
  if (strcmp(symbol, "rename") == 0) return rename;
  if (strcmp(symbol, "revoke") == 0) return revoke;
  if (strcmp(symbol, "rmdir") == 0) return rmdir;
  if (strcmp(symbol, "select50") == 0) return select50;
  if (strcmp(symbol, "sendmsg") == 0) return sendmsg;
  if (strcmp(symbol, "sendto") == 0) return sendto;
  if (strcmp(symbol, "setegid") == 0) return setegid;
  if (strcmp(symbol, "seteuid") == 0) return seteuid;
  if (strcmp(symbol, "setgid") == 0) return setgid;
  if (strcmp(symbol, "setgroups") == 0) return setgroups;
  if (strcmp(symbol, "__setlogin") == 0) return __setlogin;
  if (strcmp(symbol, "setpgid") == 0) return setpgid;
  if (strcmp(symbol, "setregid") == 0) return setregid;
  if (strcmp(symbol, "setreuid") == 0) return setreuid;
  if (strcmp(symbol, "setrlimit") == 0) return setrlimit;
  if (strcmp(symbol, "setsid") == 0) return setsid;
  if (strcmp(symbol, "setsockopt") == 0) return setsockopt;
  if (strcmp(symbol, "setuid") == 0) return setuid;
  if (strcmp(symbol, "setxattr") == 0) return setxattr;
  if (strcmp(symbol, "shutdown") == 0) return shutdown;
  if (strcmp(symbol, "socket30") == 0) return socket30;
  if (strcmp(symbol, "socketpair") == 0) return socketpair;
  if (strcmp(symbol, "stat50") == 0) return stat50;
  if (strcmp(symbol, "statvfs1") == 0) return statvfs1;
  if (strcmp(symbol, "symlinkat") == 0) return symlinkat;
  if (strcmp(symbol, "symlink") == 0) return symlink;
  if (strcmp(symbol, "sync") == 0) return sync;
  if (strcmp(symbol, "__sysctl") == 0) return __sysctl;
  if (strcmp(symbol, "truncate") == 0) return truncate;
  if (strcmp(symbol, "umask") == 0) return umask;
  if (strcmp(symbol, "unlinkat") == 0) return unlinkat;
  if (strcmp(symbol, "unlink") == 0) return unlink;
  if (strcmp(symbol, "unmount") == 0) return unmount;
  if (strcmp(symbol, "utimensat") == 0) return utimensat;
  if (strcmp(symbol, "utimes50") == 0) return utimes50;
  if (strcmp(symbol, "write") == 0) return write;
  if (strcmp(symbol, "writev") == 0) return writev;

  /* compat syscalls fixup */
  if (strcmp(symbol, "__mount50") == 0) return mount;
  if (strcmp(symbol, "__stat50") == 0) return stat;
  if (strcmp(symbol, "__fstat50") == 0) return fstat;
  if (strcmp(symbol, "__lstat50") == 0) return lstat;
  if (strcmp(symbol, "__getdents30") == 0) return getdents;

  fprintf(stderr, "failed to find %s\n", symbol);

  return NULL;
}

int dlclose(void *handle) {
  return 0;
}


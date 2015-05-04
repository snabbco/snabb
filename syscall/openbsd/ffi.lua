-- This are the types for OpenBSD

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local ffi = require "ffi"

require "syscall.ffitypes"

local version = require "syscall.openbsd.version".version

local defs = {}

local function append(str) defs[#defs + 1] = str end

append [[
typedef int32_t       clockid_t;
typedef uint32_t      fflags_t;
typedef uint64_t      fsblkcnt_t;
typedef uint64_t      fsfilcnt_t;
typedef int32_t       id_t;
typedef long          key_t;
typedef int32_t       lwpid_t;
typedef uint32_t      mode_t;
typedef int           accmode_t;
typedef int           nl_item;
typedef uint32_t      nlink_t;
typedef int64_t       rlim_t;
typedef uint8_t       sa_family_t;
typedef long          suseconds_t;
typedef unsigned int  useconds_t;
typedef int           cpuwhich_t;
typedef int           cpulevel_t;
typedef int           cpusetid_t;
typedef uint32_t      dev_t;
typedef uint32_t      fixpt_t;
typedef	unsigned int  nfds_t;
typedef int64_t       daddr_t;
typedef int32_t       timer_t;
]]
if version <= 201311 then append [[
typedef uint32_t      ino_t;
typedef int32_t       time_t;
typedef int32_t       clock_t;
]] else append [[
typedef uint64_t      ino_t;
typedef int64_t       time_t;
typedef int64_t       clock_t;
]] end
append [[
typedef unsigned int  tcflag_t;
typedef unsigned int  speed_t;
typedef char *        caddr_t;

/* can be changed, TODO also should be long */
typedef uint32_t __fd_mask;
typedef struct fd_set {
  __fd_mask fds_bits[32];
} fd_set;
typedef struct __sigset {
  uint32_t sig[1]; // note renamed to match Linux
} sigset_t;
// typedef unsigned int sigset_t; /* this is correct TODO fix */
struct cmsghdr {
  socklen_t cmsg_len;
  int cmsg_level;
  int cmsg_type;
  char cmsg_data[?];
};
struct msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  int msg_iovlen;
  void *msg_control;
  socklen_t msg_controllen;
  int msg_flags;
};
struct timespec {
  time_t tv_sec;
  long   tv_nsec;
};
struct timeval {
  time_t tv_sec;
  suseconds_t tv_usec;
};
struct itimerspec {
  struct timespec it_interval;
  struct timespec it_value;
};
struct itimerval {
  struct timeval it_interval;
  struct timeval it_value;
};
struct sockaddr {
  uint8_t       sa_len;
  sa_family_t   sa_family;
  char          sa_data[14];
};
struct sockaddr_storage {
  uint8_t       ss_len;
  sa_family_t   ss_family;
  unsigned char __ss_pad1[6];
  uint64_t      __ss_pad2;
  unsigned char __ss_pad3[240];
};
struct sockaddr_in {
  uint8_t         sin_len;
  sa_family_t     sin_family;
  in_port_t       sin_port;
  struct in_addr  sin_addr;
  int8_t          sin_zero[8];
};
struct sockaddr_in6 {
  uint8_t         sin6_len;
  sa_family_t     sin6_family;
  in_port_t       sin6_port;
  uint32_t        sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t        sin6_scope_id;
};
struct sockaddr_un {
  uint8_t         sun_len;
  sa_family_t     sun_family;
  char            sun_path[104];
};
struct pollfd {
  int fd;
  short events;
  short revents;
};
]]
if version <= 201311 then append [[
struct stat {
  dev_t     st_dev;
  ino_t     st_ino;
  mode_t    st_mode;
  nlink_t   st_nlink;
  uid_t     st_uid;
  gid_t     st_gid;
  dev_t     st_rdev;
  int32_t   st_lspare0;
  struct  timespec st_atim;
  struct  timespec st_mtim;
  struct  timespec st_ctim;
  off_t     st_size;
  int64_t   st_blocks;
  uint32_t  st_blksize;
  uint32_t  st_flags;
  uint32_t  st_gen;
  int32_t   st_lspare1;
  struct  timespec __st_birthtim;
  int64_t   st_qspare[2];
};
]] else append [[
struct stat {
  mode_t    st_mode;
  dev_t     st_dev;
  ino_t     st_ino;
  nlink_t   st_nlink;
  uid_t     st_uid;
  gid_t     st_gid;
  dev_t     st_rdev;
  struct  timespec st_atim;
  struct  timespec st_mtim;
  struct  timespec st_ctim;
  off_t     st_size;
  int64_t   st_blocks;
  uint32_t  st_blksize;
  uint32_t  st_flags;
  uint32_t  st_gen;
  struct  timespec __st_birthtim;
};
]] end append [[
struct rusage {
  struct timeval ru_utime;
  struct timeval ru_stime;
  long    ru_maxrss;
  long    ru_ixrss;
  long    ru_idrss;
  long    ru_isrss;
  long    ru_minflt;
  long    ru_majflt;
  long    ru_nswap;
  long    ru_inblock;
  long    ru_oublock;
  long    ru_msgsnd;
  long    ru_msgrcv;
  long    ru_nsignals;
  long    ru_nvcsw;
  long    ru_nivcsw;
};
struct flock {
  off_t   l_start;
  off_t   l_len;
  pid_t   l_pid;
  short   l_type;
  short   l_whence;
};
struct termios {
  tcflag_t        c_iflag;
  tcflag_t        c_oflag;
  tcflag_t        c_cflag;
  tcflag_t        c_lflag;
  cc_t            c_cc[20];
  speed_t         c_ispeed;
  speed_t         c_ospeed;
};
]]
if version <= 201311 then append [[
struct dirent {
  uint32_t d_fileno;
  uint16_t d_reclen;
  uint8_t  d_type;
  uint8_t  d_namlen;
  char     d_name[255 + 1];
};
struct kevent {
  unsigned int    ident;
  short           filter;
  unsigned short  flags;
  unsigned int    fflags;
  int             data;
  void            *udata;
};
]] else append [[
struct dirent {
  uint64_t d_fileno;
  int64_t  d_off;
  uint16_t d_reclen;
  uint8_t  d_type;
  uint8_t  d_namlen;
  char     __d_padding[4];
  char     d_name[255 + 1];
};
struct kevent {
  intptr_t	  ident;
  short           filter;
  unsigned short  flags;
  unsigned int    fflags;
  int64_t         data;
  void            *udata;
};
]] end
append [[
union sigval {
  int     sival_int;
  void    *sival_ptr;
};
static const int SI_MAXSZ = 128;
static const int SI_PAD = ((SI_MAXSZ / sizeof (int)) - 3);
typedef struct {
  int     si_signo;
  int     si_code;
  int     si_errno;
  union {
    int     _pad[SI_PAD];
      struct {
        pid_t   _pid;
        union {
          struct {
            uid_t   _uid;
            union sigval    _value;
          } _kill;
          struct {
            clock_t _utime;
            int     _status;
            clock_t _stime;
          } _cld;
        } _pdata;
      } _proc;
      struct {
        caddr_t _addr;
        int     _trapno;
      } _fault;
   } _data;
} siginfo_t;
struct  sigaction {
  union {
    void    (*__sa_handler)(int);
    void    (*__sa_sigaction)(int, siginfo_t *, void *);
  } __sigaction_u;
  sigset_t sa_mask;
  int     sa_flags;
};
]]

-- functions
append [[
int reboot(int howto);
int ioctl(int d, unsigned long request, void *arg);

/* not syscalls, but using for now */
int grantpt(int fildes);
int unlockpt(int fildes);
char *ptsname(int fildes);
]]

if version >= 201405 then
append [[
int getdents(int fd, void *buf, size_t nbytes);
]]
end

local s = table.concat(defs, "")

ffi.cdef(s)

require "syscall.bsd.ffi"


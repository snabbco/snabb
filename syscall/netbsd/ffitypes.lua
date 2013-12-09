-- This is types for NetBSD and rump kernel, which are the same bar names.

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local defs = {}

local function append(str) defs[#defs + 1] = str end

-- these are the same, could just define as uint
if abi.abi64 then
append [[
typedef unsigned int _netbsd_clock_t;
]]
else
append [[
typedef unsigned long _netbsd_clock_t;
]]
end

-- register_t varies by arch
local register_t = {
  x86 = "int",
  x64 = "long int",
  mips = "int32_t",
  mips64 = "int64_t",
  sparc = "unsigned long int",
  sparc64 = "unsigned long int",
  ia64 = "long int",
  alpha = "long int",
  ppc = "long int",
  ppc64 = "long int",
  arm = "int",
  sh3 = "int",
  m68k = "int",
  hppa = "int",
  vax = "int",
}

append("typedef " .. register_t[abi.arch] .. " _netbsd_register_t;")

append [[
typedef uint32_t _netbsd_mode_t;
typedef uint8_t _netbsd_sa_family_t;
typedef uint64_t _netbsd_dev_t;
typedef uint32_t _netbsd_nlink_t;
typedef uint64_t _netbsd_ino_t;
typedef int64_t _netbsd_time_t;
typedef int64_t _netbsd_daddr_t;
typedef uint64_t _netbsd_blkcnt_t;
typedef uint64_t _netbsd_fsblkcnt_t;
typedef uint64_t _netbsd_fsfilcnt_t;
typedef uint32_t _netbsd_blksize_t;
typedef int _netbsd_clockid_t;
typedef int _netbsd_timer_t;
typedef int _netbsd_suseconds_t;
typedef unsigned int _netbsd_nfds_t;

/* these are not used in Linux so not renamed */
typedef unsigned int useconds_t;
typedef int32_t lwpid_t;

typedef struct { int32_t __fsid_val[2]; } _netbsd_fsid_t;

typedef uint32_t _netbsd_fd_mask;
typedef struct {
  _netbsd_fd_mask fds_bits[8]; /* kernel can cope with more */
} _netbsd_fd_set;
struct _netbsd_msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  int msg_iovlen;
  void *msg_control;
  socklen_t msg_controllen;
  int msg_flags;
};
struct _netbsd_cmsghdr {
  size_t cmsg_len;
  int cmsg_level;
  int cmsg_type;
  unsigned char cmsg_data[?];
};
struct _netbsd_timespec {
  _netbsd_time_t tv_sec;
  long   tv_nsec;
};
struct _netbsd_timeval {
  _netbsd_time_t tv_sec;
  _netbsd_suseconds_t tv_usec;
};
typedef struct {
  uint32_t      val[4]; // note renamed to match Linux
} _netbsd_sigset_t;
struct _netbsd_sockaddr {
  uint8_t       sa_len;
  _netbsd_sa_family_t   sa_family;
  char          sa_data[14];
};
struct _netbsd_sockaddr_storage {
  uint8_t       ss_len;
  _netbsd_sa_family_t   ss_family;
  char          __ss_pad1[6];
  int64_t       __ss_align;
  char          __ss_pad2[128 - 2 - 8 - 6];
};
struct _netbsd_sockaddr_in {
  uint8_t         sin_len;
  _netbsd_sa_family_t     sin_family;
  in_port_t       sin_port;
  struct in_addr  sin_addr;
  int8_t          sin_zero[8];
};
struct _netbsd_sockaddr_in6 {
  uint8_t         sin6_len;
  _netbsd_sa_family_t     sin6_family;
  in_port_t       sin6_port;
  uint32_t        sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t        sin6_scope_id;
};
struct _netbsd_sockaddr_un {
  uint8_t         sun_len;
  _netbsd_sa_family_t     sun_family;
  char            sun_path[104];
};
struct _netbsd_stat {
  _netbsd_dev_t     st_dev;
  _netbsd_mode_t    st_mode;
  _netbsd_ino_t     st_ino;
  _netbsd_nlink_t   st_nlink;
  uid_t     st_uid;
  gid_t     st_gid;
  _netbsd_dev_t     st_rdev;
  struct    _netbsd_timespec st_atimespec;
  struct    _netbsd_timespec st_mtimespec;
  struct    _netbsd_timespec st_ctimespec;
  struct    _netbsd_timespec st_birthtimespec;
  off_t     st_size;
  _netbsd_blkcnt_t  st_blocks;
  _netbsd_blksize_t st_blksize;
  uint32_t  st_flags;
  uint32_t  st_gen;
  uint32_t  st_spare[2];
};
typedef union _netbsd_sigval {
  int     sival_int;
  void    *sival_ptr;
} _netbsd_sigval_t;
struct _netbsd_kevent {
  uintptr_t ident;
  uint32_t  filter;
  uint32_t  flags;
  uint32_t  fflags;
  int64_t   data;
  intptr_t  udata;
};
struct _netbsd_kfilter_mapping {
  char     *name;
  size_t   len;
  uint32_t filter;
};
]]

if abi.abi64 then
append [[
struct _ksiginfo {
  int     _signo;
  int     _code;
  int     _errno;
  int     _pad; /* only on LP64 */
  union {
    struct {
      pid_t   _pid;
      uid_t   _uid;
      _netbsd_sigval_t        _value;
    } _rt;
    struct {
      pid_t   _pid;
      uid_t   _uid;
      int     _status;
      _netbsd_clock_t _utime;
      _netbsd_clock_t _stime;
    } _child;
    struct {
      void   *_addr;
      int     _trap;
    } _fault;
    struct {
      long    _band;
      int     _fd;
    } _poll;
  } _reason;
};
]]
else
append [[
struct _ksiginfo {
  int     _signo;
  int     _code;
  int     _errno;
  union {
    struct {
      pid_t   _pid;
      uid_t   _uid;
      _netbsd_sigval_t        _value;
    } _rt;
    struct {
      pid_t   _pid;
      uid_t   _uid;
      int     _status;
      _netbsd_clock_t _utime;
      _netbsd_clock_t _stime;
    } _child;
    struct {
      void   *_addr;
      int     _trap;
    } _fault;
    struct {
      long    _band;
      int     _fd;
    } _poll;
  } _reason;
};
]]
end

append [[
typedef union _netbsd_siginfo {
  char    si_pad[128];    /* Total size; for future expansion */
  struct _ksiginfo _info;
} _netbsd_siginfo_t;
struct _netbsd_sigaction {
  union {
    void (*_sa_handler)(int);
    void (*_sa_sigaction)(int, _netbsd_siginfo_t *, void *);
  } _sa_u;
  _netbsd_sigset_t sa_mask;
  int sa_flags;
};
struct _netbsd_ufs_args {
  char *fspec;
};
struct _netbsd_tmpfs_args {
  int ta_version;
  _netbsd_ino_t ta_nodes_max;
  off_t ta_size_max;
  uid_t ta_root_uid;
  gid_t ta_root_gid;
  _netbsd_mode_t ta_root_mode;
};
struct _netbsd_ptyfs_args {
  int version;
  gid_t gid;
  _netbsd_mode_t mode;
  int flags;
};
struct _netbsd_procfs_args {
  int version;
  int flags;
};
struct _netbsd_dirent {
  _netbsd_ino_t d_fileno;
  uint16_t d_reclen;
  uint16_t d_namlen;
  uint8_t  d_type;
  char     d_name[512];
};
struct _netbsd_ifreq {
  char ifr_name[16];
  union {
    struct  _netbsd_sockaddr ifru_addr;
    struct  _netbsd_sockaddr ifru_dstaddr;
    struct  _netbsd_sockaddr ifru_broadaddr;
    struct  _netbsd_sockaddr_storage ifru_space;
    short   ifru_flags;
    int     ifru_metric;
    int     ifru_mtu;
    int     ifru_dlt;
    unsigned int   ifru_value;
    void *  ifru_data;
    struct {
      uint32_t        b_buflen;
      void            *b_buf;
    } ifru_b;
  } ifr_ifru;
};
struct _netbsd_ifaliasreq {
  char    ifra_name[16];
  struct  _netbsd_sockaddr ifra_addr;
  struct  _netbsd_sockaddr ifra_dstaddr;
  struct  _netbsd_sockaddr ifra_mask;
};
struct _netbsd_pollfd {
  int fd;
  short int events;
  short int revents;
};
struct _netbsd_flock {
  off_t   l_start;
  off_t   l_len;
  pid_t   l_pid;
  short   l_type;
  short   l_whence;
};
struct _netbsd_termios {
        tcflag_t        c_iflag;        /* input flags */
        tcflag_t        c_oflag;        /* output flags */
        tcflag_t        c_cflag;        /* control flags */
        tcflag_t        c_lflag;        /* local flags */
        cc_t            c_cc[20];       /* control chars */
        int             c_ispeed;       /* input speed */
        int             c_ospeed;       /* output speed */
};
/* compat issues */
struct _netbsd_compat_60_ptmget {
  int     cfd;
  int     sfd;
  char    cn[16];
  char    sn[16];
};
struct _netbsd_ptmget {
  int     cfd;
  int     sfd;
  char    cn[1024];
  char    sn[1024];
};
struct _netbsd_statvfs {
  unsigned long   f_flag;
  unsigned long   f_bsize;
  unsigned long   f_frsize;
  unsigned long   f_iosize;
  _netbsd_fsblkcnt_t      f_blocks;
  _netbsd_fsblkcnt_t      f_bfree;
  _netbsd_fsblkcnt_t      f_bavail;
  _netbsd_fsblkcnt_t      f_bresvd;
  _netbsd_fsfilcnt_t      f_files;
  _netbsd_fsfilcnt_t      f_ffree;
  _netbsd_fsfilcnt_t      f_favail;
  _netbsd_fsfilcnt_t      f_fresvd;
  uint64_t        f_syncreads;
  uint64_t        f_syncwrites;
  uint64_t        f_asyncreads;
  uint64_t        f_asyncwrites;
  _netbsd_fsid_t          f_fsidx;
  unsigned long   f_fsid;
  unsigned long   f_namemax;
  uid_t           f_owner;
  uint32_t        f_spare[4];
  char    f_fstypename[32];
  char    f_mntonname[1024];
  char    f_mntfromname[1024];
};
struct _netbsd_rusage {
  struct _netbsd_timeval ru_utime;
  struct _netbsd_timeval ru_stime;
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
]]

if abi.le then
append [[
struct _netbsd_ktr_header {
  int     ktr_len;
  short   ktr_type;
  short   ktr_version;
  pid_t   ktr_pid;
  char    ktr_comm[17];
  union {
    struct {
      struct {
        int32_t tv_sec;
        long tv_usec;
      } _tv;
      const void *_buf;
    } _v0;
    struct {
      struct {
        int32_t tv_sec;
        long tv_nsec;
      } _ts;
      lwpid_t _lid;
    } _v1;
    struct {
      struct _netbsd_timespec _ts;
      lwpid_t _lid;
    } _v2;
  } _v;
};
]]
else
append [[
struct _netbsd_ktr_header {
  int     ktr_len;
  short   ktr_version;
  short   ktr_type;
  pid_t   ktr_pid;
  char    ktr_comm[17];
  union {
    struct {
      struct {
        int32_t tv_sec;
        long tv_usec;
      } _tv;
      const void *_buf;
    } _v0;
    struct {
      struct {
        int32_t tv_sec;
        long tv_nsec;
      } _ts;
      lwpid_t _lid;
    } _v1;
    struct {
      struct _netbsd_timespec _ts;
      lwpid_t _lid;
    } _v2;
  } _v;
};
]]
end

append [[
struct ktr_syscall {
  int     ktr_code;
  int     ktr_argsize;
};
struct ktr_sysret {
  short   ktr_code;
  short   ktr_eosys;
  int     ktr_error;
  _netbsd_register_t ktr_retval;
  _netbsd_register_t ktr_retval_1;
};
struct ktr_genio {
  int     ktr_fd;
  int     ktr_rw; /* enum uoi_rw, changed to constant */
};
struct ktr_psig {
  int     signo;
  sig_t   action;
  _netbsd_sigset_t mask;
  int     code;
};
struct ktr_csw {
  int     out;
  int     user;
};
struct ktr_user {
  char    ktr_id[20];
};
struct ktr_saupcall {
  int ktr_type;
  int ktr_nevent;
  int ktr_nint;
  void *ktr_sas;
  void *ktr_ap;
};
struct ktr_execfd {
  int   ktr_fd;
  unsigned int ktr_dtype;
};
]]

local s = table.concat(defs, "")

if abi.host == "netbsd" then
  s = string.gsub(s, "_netbsd_", "") -- remove netbsd types
end

local ffi = require "ffi"
ffi.cdef(s)


-- This is types for NetBSD and rump kernel, which are the same bar names.

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(abi)

require "syscall.ffitypes"

local ffi = require "ffi"

local cdef

if abi.rump and abi.host ~= "netbsd" then
  cdef = ffi.cdef
else
  cdef = function(s)
    s = string.gsub(s, "_netbsd_", "") -- remove netbsd types
    ffi.cdef(s)
  end
end

-- these are the same, could just define as uint
if abi.abi64 then
cdef [[
typedef unsigned int _netbsd_clock_t;
]]
else
cdef [[
typedef unsigned long _netbsd_clock_t;
]]
end

cdef [[
typedef uint32_t _netbsd_mode_t;
typedef uint8_t _netbsd_sa_family_t;
typedef uint64_t _netbsd_dev_t;
typedef uint32_t _netbsd_nlink_t;
typedef uint64_t _netbsd_ino_t;
typedef int64_t _netbsd_time_t;
typedef int64_t _netbsd_daddr_t;
typedef uint64_t _netbsd_blkcnt_t;
typedef uint32_t _netbsd_blksize_t;
typedef int _netbsd_clockid_t;
typedef int _netbsd_timer_t;
typedef int _netbsd_suseconds_t;
typedef unsigned int useconds_t;

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
]]

if abi.abi64 then
cdef [[
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
cdef [[
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

cdef [[
typedef union _netbsd_siginfo {
  char    si_pad[128];    /* Total size; for future expansion */
  struct _ksiginfo _info;
} _netbsd_siginfo_t;
struct _netbsd_sigaction {
  union {
    void (*sa_handler)(int);
    void (*sa_sigaction)(int, _netbsd_siginfo_t *, void *);
  } sa_handler; // renamed as in Linux definition
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
]]

end

return {init = init}


-- This is types for NetBSD and rump kernel, which are the same bar names.

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local ffi = require "ffi"

require "syscall.ffitypes"

local helpers = require "syscall.helpers"

local version = require "syscall.netbsd.version".version

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
typedef uint32_t _netbsd_id_t;
typedef unsigned int _netbsd_tcflag_t;
typedef unsigned int _netbsd_speed_t;
typedef int32_t _netbsd_lwpid_t;
typedef uint32_t _netbsd_fixpt_t;

typedef unsigned short u_short;
typedef unsigned char u_char;
typedef uint64_t u_quad_t;

/* these are not used in Linux so not renamed */
typedef unsigned int useconds_t;
typedef int32_t lwpid_t;

typedef struct { int32_t __fsid_val[2]; } _netbsd_fsid_t;

typedef uint32_t _netbsd_fd_mask;
typedef struct {
  _netbsd_fd_mask fds_bits[8]; /* kernel can cope with more */
} _netbsd_fd_set;
struct _netbsd_cmsghdr {
  size_t cmsg_len;
  int cmsg_level;
  int cmsg_type;
  char cmsg_data[?];
};
struct _netbsd_msghdr {
  void *msg_name;
  socklen_t msg_namelen;
  struct iovec *msg_iov;
  int msg_iovlen;
  void *msg_control;
  socklen_t msg_controllen;
  int msg_flags;
};
struct _netbsd_mmsghdr {
  struct _netbsd_msghdr msg_hdr;
  unsigned int msg_len;
};
struct _netbsd_timespec {
  _netbsd_time_t tv_sec;
  long   tv_nsec;
};
struct _netbsd_timeval {
  _netbsd_time_t tv_sec;
  _netbsd_suseconds_t tv_usec;
};
struct _netbsd_itimerspec {
  struct _netbsd_timespec it_interval;
  struct _netbsd_timespec it_value;
};
struct _netbsd_itimerval {
  struct _netbsd_timeval it_interval;
  struct _netbsd_timeval it_value;
};
typedef struct {
  uint32_t      sig[4]; // note renamed to match Linux
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
struct  _netbsd_sigevent {
  int     sigev_notify;
  int     sigev_signo;
  union _netbsd_sigval    sigev_value;
  void    (*sigev_notify_function)(union _netbsd_sigval);
  void /* pthread_attr_t */       *sigev_notify_attributes;
};
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
  _netbsd_tcflag_t        c_iflag;
  _netbsd_tcflag_t        c_oflag;
  _netbsd_tcflag_t        c_cflag;
  _netbsd_tcflag_t        c_lflag;
  cc_t            c_cc[20];
  int             c_ispeed;
  int             c_ospeed;
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
struct _netbsd_ktr_syscall {
  int     ktr_code;
  int     ktr_argsize;
};
struct _netbsd_ktr_sysret {
  short   ktr_code;
  short   ktr_eosys;
  int     ktr_error;
  _netbsd_register_t ktr_retval;
  _netbsd_register_t ktr_retval_1;
};
struct _netbsd_ktr_genio {
  int     ktr_fd;
  int     ktr_rw; /* enum uoi_rw, changed to constant */
};
struct _netbsd_ktr_psig {
  int     signo;
  sig_t   action;
  _netbsd_sigset_t mask;
  int     code;
};
struct _netbsd_ktr_csw {
  int     out;
  int     user;
};
struct _netbsd_ktr_user {
  char    ktr_id[20];
};
struct _netbsd_ktr_saupcall {
  int ktr_type;
  int ktr_nevent;
  int ktr_nint;
  void *ktr_sas;
  void *ktr_ap;
};
struct _netbsd_ktr_execfd {
  int   ktr_fd;
  unsigned int ktr_dtype;
};
struct _netbsd_ifdrv {
  char          ifd_name[16];
  unsigned long ifd_cmd;
  size_t        ifd_len;
  void         *ifd_data;
};
struct _netbsd_ifbreq {
  char     ifbr_ifsname[16];
  uint32_t ifbr_ifsflags;
  uint8_t  ifbr_state;
  uint8_t  ifbr_priority;
  uint8_t  ifbr_path_cost;
  uint8_t  ifbr_portno;
};
struct _netbsd_in6_addrlifetime {
  _netbsd_time_t ia6t_expire;
  _netbsd_time_t ia6t_preferred;
  uint32_t ia6t_vltime;
  uint32_t ia6t_pltime;
};
struct _netbsd_in6_ifstat {
  u_quad_t ifs6_in_receive;
  u_quad_t ifs6_in_hdrerr;
  u_quad_t ifs6_in_toobig;
  u_quad_t ifs6_in_noroute;
  u_quad_t ifs6_in_addrerr;
  u_quad_t ifs6_in_protounknown;
  u_quad_t ifs6_in_truncated;
  u_quad_t ifs6_in_discard;
  u_quad_t ifs6_in_deliver;
  u_quad_t ifs6_out_forward;
  u_quad_t ifs6_out_request;
  u_quad_t ifs6_out_discard;
  u_quad_t ifs6_out_fragok;
  u_quad_t ifs6_out_fragfail;
  u_quad_t ifs6_out_fragcreat;
  u_quad_t ifs6_reass_reqd;
  u_quad_t ifs6_reass_ok;
  u_quad_t ifs6_reass_fail;
  u_quad_t ifs6_in_mcast;
  u_quad_t ifs6_out_mcast;
};
struct _netbsd_icmp6_ifstat {
  u_quad_t ifs6_in_msg;
  u_quad_t ifs6_in_error;
  u_quad_t ifs6_in_dstunreach;
  u_quad_t ifs6_in_adminprohib;
  u_quad_t ifs6_in_timeexceed;
  u_quad_t ifs6_in_paramprob;
  u_quad_t ifs6_in_pkttoobig;
  u_quad_t ifs6_in_echo;
  u_quad_t ifs6_in_echoreply;
  u_quad_t ifs6_in_routersolicit;
  u_quad_t ifs6_in_routeradvert;
  u_quad_t ifs6_in_neighborsolicit;
  u_quad_t ifs6_in_neighboradvert;
  u_quad_t ifs6_in_redirect;
  u_quad_t ifs6_in_mldquery;
  u_quad_t ifs6_in_mldreport;
  u_quad_t ifs6_in_mlddone;
  u_quad_t ifs6_out_msg;
  u_quad_t ifs6_out_error;
  u_quad_t ifs6_out_dstunreach;
  u_quad_t ifs6_out_adminprohib;
  u_quad_t ifs6_out_timeexceed;
  u_quad_t ifs6_out_paramprob;
  u_quad_t ifs6_out_pkttoobig;
  u_quad_t ifs6_out_echo;
  u_quad_t ifs6_out_echoreply;
  u_quad_t ifs6_out_routersolicit;
  u_quad_t ifs6_out_routeradvert;
  u_quad_t ifs6_out_neighborsolicit;
  u_quad_t ifs6_out_neighboradvert;
  u_quad_t ifs6_out_redirect;
  u_quad_t ifs6_out_mldquery;
  u_quad_t ifs6_out_mldreport;
  u_quad_t ifs6_out_mlddone;
};
struct _netbsd_in6_ifreq {
  char ifr_name[16];
  union {
    struct _netbsd_sockaddr_in6 ifru_addr;
    struct _netbsd_sockaddr_in6 ifru_dstaddr;
    short  ifru_flags;
    int    ifru_flags6;
    int    ifru_metric;
    void * ifru_data;
    struct _netbsd_in6_addrlifetime ifru_lifetime;
    struct _netbsd_in6_ifstat ifru_stat;
    struct _netbsd_icmp6_ifstat ifru_icmp6stat;
  } ifr_ifru;
};
struct _netbsd_in6_aliasreq {
  char    ifra_name[16];
  struct  _netbsd_sockaddr_in6 ifra_addr;
  struct  _netbsd_sockaddr_in6 ifra_dstaddr;
  struct  _netbsd_sockaddr_in6 ifra_prefixmask;
  int     ifra_flags;
  struct  _netbsd_in6_addrlifetime ifra_lifetime;
};
struct _netbsd_rt_metrics {
  uint64_t rmx_locks;
  uint64_t rmx_mtu;
  uint64_t rmx_hopcount;
  uint64_t rmx_recvpipe;
  uint64_t rmx_sendpipe;
  uint64_t rmx_ssthresh;
  uint64_t rmx_rtt;
  uint64_t rmx_rttvar;
  _netbsd_time_t  rmx_expire;
  _netbsd_time_t  rmx_pksent;
};
struct _netbsd_rt_msghdr {
  u_short rtm_msglen __attribute__ ((aligned (8)));
  u_char  rtm_version;
  u_char  rtm_type;
  u_short rtm_index;
  int     rtm_flags;
  int     rtm_addrs;
  pid_t   rtm_pid;
  int     rtm_seq;
  int     rtm_errno;
  int     rtm_use;
  int     rtm_inits;
  struct  _netbsd_rt_metrics rtm_rmx __attribute__ ((aligned (8)));
};
struct _netbsd_clockinfo {
  int     hz;
  int     tick;
  int     tickadj;
  int     stathz;
  int     profhz;
};
struct _netbsd_loadavg {
  _netbsd_fixpt_t ldavg[3];
  long    fscale;
};
struct _netbsd_vmtotal
{
  int16_t t_rq;
  int16_t t_dw;
  int16_t t_pw;
  int16_t t_sl;
  int16_t _reserved1;
  int32_t t_vm;
  int32_t t_avm;
  int32_t t_rm;
  int32_t t_arm;
  int32_t t_vmshr;
  int32_t t_avmshr;
  int32_t t_rmshr;
  int32_t t_armshr;
  int32_t t_free;
};
struct _netbsd_ctlname {
  const char *ctl_name;
  int     ctl_type;
};
/* volatile may be an issue... */
struct _netbsd_aiocb {
  off_t aio_offset;
  volatile void *aio_buf;
  size_t aio_nbytes;
  int aio_fildes;
  int aio_lio_opcode;
  int aio_reqprio;
  struct _netbsd_sigevent aio_sigevent;
  /* Internal kernel variables */
  int _state;
  int _errno;
  ssize_t _retval;
};
]]

local s = table.concat(defs, "")

-- TODO broken, makes this module not a proper function, see #120
-- although this will not ever actually happen...
if abi.host == "netbsd" then
  s = string.gsub(s, "_netbsd_", "") -- remove netbsd types
end

ffi.cdef(s)


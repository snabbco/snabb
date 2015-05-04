-- ffi definitions of OSX types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local ffi = require "ffi"

require "syscall.ffitypes"

-- for version detection - not implemented yet
ffi.cdef [[
int sysctl(const int *name, unsigned int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
]]

local defs = {}

local function append(str) defs[#defs + 1] = str end

append [[
typedef uint16_t mode_t;
typedef uint8_t sa_family_t;
typedef uint32_t dev_t;
typedef int64_t blkcnt_t;
typedef int32_t blksize_t;
typedef int32_t suseconds_t;
typedef uint16_t nlink_t;
typedef uint64_t ino_t; // at least on recent desktop; TODO define as ino64_t
typedef long time_t;
typedef int32_t daddr_t;
typedef unsigned long clock_t;
typedef unsigned int nfds_t;
typedef uint32_t id_t; // check as not true in freebsd
typedef unsigned long tcflag_t;
typedef unsigned long speed_t;
typedef	int kern_return_t;

typedef unsigned int natural_t;
typedef natural_t mach_port_name_t;
typedef mach_port_name_t *mach_port_name_array_t;
typedef mach_port_name_t mach_port_t;

typedef mach_port_t task_t;
typedef mach_port_t task_name_t;
typedef mach_port_t thread_t;
typedef mach_port_t thread_act_t;
typedef mach_port_t ipc_space_t;
typedef mach_port_t host_t;
typedef mach_port_t host_priv_t;
typedef mach_port_t host_security_t;
typedef mach_port_t processor_t;
typedef mach_port_t processor_set_t;
typedef mach_port_t processor_set_control_t;
typedef mach_port_t semaphore_t;
typedef mach_port_t lock_set_t;
typedef mach_port_t ledger_t;
typedef mach_port_t alarm_t;
typedef mach_port_t clock_serv_t;
typedef mach_port_t clock_ctrl_t;

typedef int alarm_type_t;
typedef int sleep_type_t;
typedef int clock_id_t;
typedef int clock_flavor_t;
typedef int *clock_attr_t;
typedef int clock_res_t;

/* osx has different clock functions so clockid undefined, but so POSIX headers work, define it
   similarly with timer_t */
typedef int clockid_t;
typedef int timer_t;

/* actually not a struct at all in osx, just a uint32_t but for compatibility fudge it */
/* TODO this should work, but really need to move all sigset_t handling out of common types */
typedef struct {
  uint32_t      sig[1];
} sigset_t;

typedef struct fd_set {
  int32_t fds_bits[32];
} fd_set;
struct pollfd
{
  int     fd;
  short   events;
  short   revents;
};
struct cmsghdr {
  size_t cmsg_len;
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
  char          __ss_pad1[6];
  int64_t       __ss_align;
  char          __ss_pad2[128 - 2 - 8 - 6];
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
struct stat {
  dev_t           st_dev;
  mode_t          st_mode;
  nlink_t         st_nlink;
  ino_t           st_ino;
  uid_t           st_uid;
  gid_t           st_gid;
  dev_t           st_rdev;
  struct timespec st_atimespec;
  struct timespec st_mtimespec;
  struct timespec st_ctimespec;
  struct timespec st_birthtimespec;
  off_t           st_size;
  blkcnt_t        st_blocks;
  blksize_t       st_blksize;
  uint32_t        st_flags;
  uint32_t        st_gen;
  int32_t         st_lspare;
  int64_t         st_qspare[2];
};
union sigval {
  int     sival_int;
  void    *sival_ptr;
};
typedef struct __siginfo {
  int     si_signo;
  int     si_errno;
  int     si_code;
  pid_t   si_pid;
  uid_t   si_uid;
  int     si_status;
  void    *si_addr;
  union sigval si_value;
  long    si_band;
  unsigned long   __pad[7];
} siginfo_t;
union __sigaction_u {
  void    (*__sa_handler)(int);
  void    (*__sa_sigaction)(int, struct __siginfo *, void *);
};
struct sigaction {
  union __sigaction_u __sigaction_u;
  sigset_t sa_mask;
  int sa_flags;
};
struct sigevent {
  int sigev_notify;
  int sigev_signo;
  union sigval    sigev_value;
  void            (*sigev_notify_function)(union sigval);
  void            *sigev_notify_attributes; /* pthread_attr_t */
};
struct dirent {
  uint64_t  d_ino;
  uint64_t  d_seekoff;
  uint16_t  d_reclen;
  uint16_t  d_namlen;
  uint8_t   d_type;
  char      d_name[1024];
};
struct legacy_dirent {
  uint32_t d_ino;
  uint16_t d_reclen;
  uint8_t  d_type;
  uint8_t  d_namlen;
  char d_name[256];
};
struct flock {
  off_t  l_start;
  off_t  l_len;
  pid_t  l_pid;
  short  l_type;
  short  l_whence;
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
struct kevent {
  uintptr_t       ident;
  int16_t         filter;
  uint16_t        flags;
  uint32_t        fflags;
  intptr_t        data;
  void            *udata;
};
struct aiocb {
  int aio_fildes;
  off_t           aio_offset;
  volatile void   *aio_buf;
  size_t          aio_nbytes;
  int aio_reqprio;
  struct sigevent aio_sigevent;
  int aio_lio_opcode;
};
struct mach_timebase_info {
  uint32_t	numer;
  uint32_t	denom;
};
typedef struct mach_timebase_info	*mach_timebase_info_t;
typedef struct mach_timebase_info	mach_timebase_info_data_t;
struct mach_timespec {
  unsigned int tv_sec;
  clock_res_t  tv_nsec;
};
typedef struct mach_timespec mach_timespec_t;
]]

append [[
int ioctl(int d, unsigned long request, void *arg);
int mount(const char *type, const char *dir, int flags, void *data);

int stat64(const char *path, struct stat *sb);
int lstat64(const char *path, struct stat *sb);
int fstat64(int fd, struct stat *sb);

int _getdirentries(int fd, char *buf, int nbytes, long *basep);
int _sigaction(int signum, const struct sigaction *act, struct sigaction *oldact);

/* mach_absolute_time uses rtdsc, so careful if move CPU */
uint64_t mach_absolute_time(void);
kern_return_t mach_timebase_info(mach_timebase_info_t info);
kern_return_t mach_wait_until(uint64_t deadline);

extern mach_port_t mach_task_self_;
mach_port_t mach_host_self(void);
kern_return_t mach_port_deallocate(ipc_space_t task, mach_port_name_t name);

kern_return_t host_get_clock_service(host_t host, clock_id_t clock_id, clock_serv_t *clock_serv);
kern_return_t clock_get_time(clock_serv_t clock_serv, mach_timespec_t *cur_time);
]]

ffi.cdef(table.concat(defs, ""))

require "syscall.bsd.ffi"



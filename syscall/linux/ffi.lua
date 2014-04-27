-- ffi definitions of Linux types

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local ffi = require "ffi"

require "syscall.ffitypes"

local arch = require("syscall.linux." .. abi.arch .. ".ffi") -- architecture specific definitions

local defs = {}

local function append(str) defs[#defs + 1] = str end

append [[
typedef uint32_t mode_t;
typedef unsigned short int sa_family_t;
typedef uint64_t rlim64_t;
typedef unsigned long nlink_t;
typedef unsigned long ino_t;
typedef long time_t;
typedef int32_t daddr_t;
typedef long blkcnt_t;
typedef long blksize_t;
typedef int32_t clockid_t;
typedef long clock_t;
typedef uint32_t off32_t; /* only used for eg mmap2 on Linux */
typedef uint32_t le32; /* this is little endian - not really using it yet */
typedef uint32_t id_t;
typedef unsigned int tcflag_t;
typedef unsigned int speed_t;
typedef int timer_t;

/* despite glibc, Linux uses 32 bit dev_t */
typedef uint32_t dev_t;

typedef unsigned long aio_context_t;
typedef unsigned long nfds_t;

// should be a word, but we use 32 bits as bitops are signed 32 bit in LuaJIT at the moment
typedef int32_t fd_mask;

// again should be a long, and we have wrapped in a struct
// TODO ok to wrap Lua types but not syscall? https://github.com/justincormack/ljsyscall/issues/36
// TODO is this size right? check
struct cpu_set_t {
  int32_t val[1024 / (8 * sizeof (int32_t))];
};

typedef int mqd_t;
typedef int idtype_t; /* defined as enum */

struct timespec {
  time_t tv_sec;
  long   tv_nsec;
};

// misc
typedef void (*sighandler_t) (int);

// structs
struct timeval {
  long    tv_sec;         /* seconds */
  long    tv_usec;        /* microseconds */
};
struct itimerspec {
  struct timespec it_interval;
  struct timespec it_value;
};
struct itimerval {
  struct timeval it_interval;
  struct timeval it_value;
};
//static const int UTSNAME_LENGTH = 65;
struct utsname {
  char sysname[65];
  char nodename[65];
  char release[65];
  char version[65];
  char machine[65];
  char domainname[65];
};
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
typedef struct { /* based on Linux FD_SETSIZE = 1024, the kernel can do more, so can increase */
  fd_mask fds_bits[1024 / (sizeof (fd_mask) * 8)];
} fd_set;
struct ucred {
  pid_t pid;
  uid_t uid;
  gid_t gid;
};
struct rlimit64 {
  rlim64_t rlim_cur;
  rlim64_t rlim_max;
};
struct sysinfo {
  long uptime;
  unsigned long loads[3];
  unsigned long totalram;
  unsigned long freeram;
  unsigned long sharedram;
  unsigned long bufferram;
  unsigned long totalswap;
  unsigned long freeswap;
  unsigned short procs;
  unsigned short pad;
  unsigned long totalhigh;
  unsigned long freehigh;
  unsigned int mem_unit;
  char _f[20-2*sizeof(long)-sizeof(int)]; /* TODO ugh, remove calculation */
};
struct timex {
  unsigned int modes;
  long int offset;
  long int freq;
  long int maxerror;
  long int esterror;
  int status;
  long int constant;
  long int precision;
  long int tolerance;
  struct timeval time;
  long int tick;

  long int ppsfreq;
  long int jitter;
  int shift;
  long int stabil;
  long int jitcnt;
  long int calcnt;
  long int errcnt;
  long int stbcnt;

  int tai;

  int  :32; int  :32; int  :32; int  :32;
  int  :32; int  :32; int  :32; int  :32;
  int  :32; int  :32; int  :32;
};
typedef union sigval {
  int sival_int;
  void *sival_ptr;
} sigval_t;
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
  size_t msg_iovlen;
  void *msg_control;
  size_t msg_controllen;
  int msg_flags;
};
struct mmsghdr {
  struct msghdr msg_hdr;
  unsigned int msg_len;
};
struct sockaddr {
  sa_family_t sa_family;
  char sa_data[14];
};
struct sockaddr_storage {
  sa_family_t ss_family;
  unsigned long int __ss_align;
  char __ss_padding[128 - 2 * sizeof(unsigned long int)]; /* total length 128 TODO no calculations */
};
struct sockaddr_in {
  sa_family_t    sin_family;
  in_port_t      sin_port;
  struct in_addr sin_addr;
  unsigned char  sin_zero[8];
};
struct sockaddr_in6 {
  sa_family_t    sin6_family;
  in_port_t sin6_port;
  uint32_t sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t sin6_scope_id;
};
struct sockaddr_un {
  sa_family_t sun_family;
  char        sun_path[108];
};
struct sockaddr_nl {
  sa_family_t     nl_family;
  unsigned short  nl_pad;
  uint32_t        nl_pid;
  uint32_t        nl_groups;
};
struct sockaddr_ll {
  unsigned short  sll_family;
  unsigned short  sll_protocol; /* __be16 */
  int             sll_ifindex;
  unsigned short  sll_hatype;
  unsigned char   sll_pkttype;
  unsigned char   sll_halen;
  unsigned char   sll_addr[8];
};
struct nlmsghdr {
  uint32_t           nlmsg_len;
  uint16_t           nlmsg_type;
  uint16_t           nlmsg_flags;
  uint32_t           nlmsg_seq;
  uint32_t           nlmsg_pid;
};
struct rtgenmsg {
  unsigned char rtgen_family;
};
struct ifinfomsg {
  unsigned char   ifi_family;
  unsigned char   __ifi_pad;
  unsigned short  ifi_type;
  int             ifi_index;
  unsigned        ifi_flags;
  unsigned        ifi_change;
};
struct rtattr {
  unsigned short  rta_len;
  unsigned short  rta_type;
};
struct nlmsgerr {
  int             error;
  struct nlmsghdr msg;
};
struct rtmsg {
  unsigned char rtm_family;
  unsigned char rtm_dst_len;
  unsigned char rtm_src_len;
  unsigned char rtm_tos;
  unsigned char rtm_table;
  unsigned char rtm_protocol;
  unsigned char rtm_scope;
  unsigned char rtm_type;
  unsigned int  rtm_flags;
};

static const int IFNAMSIZ = 16;

struct ifmap {
  unsigned long mem_start;
  unsigned long mem_end;
  unsigned short base_addr; 
  unsigned char irq;
  unsigned char dma;
  unsigned char port;
};
struct rtnl_link_stats {
  uint32_t rx_packets;
  uint32_t tx_packets;
  uint32_t rx_bytes;
  uint32_t tx_bytes;
  uint32_t rx_errors;
  uint32_t tx_errors;
  uint32_t rx_dropped;
  uint32_t tx_dropped;
  uint32_t multicast;
  uint32_t collisions;
  uint32_t rx_length_errors;
  uint32_t rx_over_errors;
  uint32_t rx_crc_errors;
  uint32_t rx_frame_errors;
  uint32_t rx_fifo_errors;
  uint32_t rx_missed_errors;
  uint32_t tx_aborted_errors;
  uint32_t tx_carrier_errors;
  uint32_t tx_fifo_errors;
  uint32_t tx_heartbeat_errors;
  uint32_t tx_window_errors;
  uint32_t rx_compressed;
  uint32_t tx_compressed;
};
struct ndmsg {
  uint8_t  ndm_family;
  uint8_t  ndm_pad1;
  uint16_t ndm_pad2;
  int32_t  ndm_ifindex;
  uint16_t ndm_state;
  uint8_t  ndm_flags;
  uint8_t  ndm_type;
};
struct nda_cacheinfo {
  uint32_t ndm_confirmed;
  uint32_t ndm_used;
  uint32_t ndm_updated;
  uint32_t ndm_refcnt;
};
struct ndt_stats {
  uint64_t ndts_allocs;
  uint64_t ndts_destroys;
  uint64_t ndts_hash_grows;
  uint64_t ndts_res_failed;
  uint64_t ndts_lookups;
  uint64_t ndts_hits;
  uint64_t ndts_rcv_probes_mcast;
  uint64_t ndts_rcv_probes_ucast;
  uint64_t ndts_periodic_gc_runs;
  uint64_t ndts_forced_gc_runs;
};
struct ndtmsg {
  uint8_t  ndtm_family;
  uint8_t  ndtm_pad1;
  uint16_t ndtm_pad2;
};
struct ndt_config {
  uint16_t ndtc_key_len;
  uint16_t ndtc_entry_size;
  uint32_t ndtc_entries;
  uint32_t ndtc_last_flush;
  uint32_t ndtc_last_rand;
  uint32_t ndtc_hash_rnd;
  uint32_t ndtc_hash_mask;
  uint32_t ndtc_hash_chain_gc;
  uint32_t ndtc_proxy_qlen;
};
typedef struct { 
  unsigned int clock_rate;
  unsigned int clock_type;
  unsigned short loopback;
} sync_serial_settings;
typedef struct { 
  unsigned int clock_rate;
  unsigned int clock_type;
  unsigned short loopback;
  unsigned int slot_map;
} te1_settings;
typedef struct {
  unsigned short encoding;
  unsigned short parity;
} raw_hdlc_proto;
typedef struct {
  unsigned int t391;
  unsigned int t392;
  unsigned int n391;
  unsigned int n392;
  unsigned int n393;
  unsigned short lmi;
  unsigned short dce;
} fr_proto;
typedef struct {
  unsigned int dlci;
} fr_proto_pvc;
typedef struct {
  unsigned int dlci;
  char master[IFNAMSIZ];
} fr_proto_pvc_info;
typedef struct {
  unsigned int interval;
  unsigned int timeout;
} cisco_proto;
struct if_settings {
  unsigned int type;
  unsigned int size;
  union {
    raw_hdlc_proto          *raw_hdlc;
    cisco_proto             *cisco;
    fr_proto                *fr;
    fr_proto_pvc            *fr_pvc;
    fr_proto_pvc_info       *fr_pvc_info;

    sync_serial_settings    *sync;
    te1_settings            *te1;
  } ifs_ifsu;
};
struct ifreq {
  union {
    char ifrn_name[IFNAMSIZ];
  } ifr_ifrn;
  union {
    struct  sockaddr ifru_addr;
    struct  sockaddr ifru_dstaddr;
    struct  sockaddr ifru_broadaddr;
    struct  sockaddr ifru_netmask;
    struct  sockaddr ifru_hwaddr;
    short   ifru_flags;
    int     ifru_ivalue;
    int     ifru_mtu;
    struct  ifmap ifru_map;
    char    ifru_slave[IFNAMSIZ];
    char    ifru_newname[IFNAMSIZ];
    void *  ifru_data;
    struct  if_settings ifru_settings;
  } ifr_ifru;
};
struct ifaddrmsg {
  uint8_t  ifa_family;
  uint8_t  ifa_prefixlen;
  uint8_t  ifa_flags;
  uint8_t  ifa_scope;
  uint32_t ifa_index;
};
struct ifa_cacheinfo {
  uint32_t ifa_prefered;
  uint32_t ifa_valid;
  uint32_t cstamp;
  uint32_t tstamp;
};
struct rta_cacheinfo {
  uint32_t rta_clntref;
  uint32_t rta_lastuse;
  uint32_t rta_expires;
  uint32_t rta_error;
  uint32_t rta_used;
  uint32_t rta_id;
  uint32_t rta_ts;
  uint32_t rta_tsage;
};
struct fdb_entry {
  uint8_t mac_addr[6];
  uint8_t port_no;
  uint8_t is_local;
  uint32_t ageing_timer_value;
  uint8_t port_hi;
  uint8_t pad0;
  uint16_t unused;
};
struct inotify_event {
  int wd;
  uint32_t mask;
  uint32_t cookie;
  uint32_t len;
  char name[?];
};
struct linux_dirent64 {
  uint64_t        d_ino;
  int64_t         d_off;
  unsigned short  d_reclen;
  unsigned char   d_type;
  char            d_name[0];
};
struct flock64 {
  short int l_type;
  short int l_whence;
  off_t l_start;
  off_t l_len;
  pid_t l_pid;
};
typedef union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
} epoll_data_t;
struct signalfd_siginfo {
  uint32_t ssi_signo;
  int32_t ssi_errno;
  int32_t ssi_code;
  uint32_t ssi_pid;
  uint32_t ssi_uid;
  int32_t ssi_fd;
  uint32_t ssi_tid;
  uint32_t ssi_band;
  uint32_t ssi_overrun;
  uint32_t ssi_trapno;
  int32_t ssi_status;
  int32_t ssi_int;
  uint64_t ssi_ptr;
  uint64_t ssi_utime;
  uint64_t ssi_stime;
  uint64_t ssi_addr;
  uint8_t __pad[48];
};
struct io_event {
  uint64_t           data;
  uint64_t           obj;
  int64_t            res;
  int64_t            res2;
};
struct seccomp_data {
  int nr;
  uint32_t arch;
  uint64_t instruction_pointer;
  uint64_t args[6];
};
struct sock_filter {
  uint16_t   code;
  uint8_t    jt;
  uint8_t    jf;
  uint32_t   k;
};
struct sock_fprog {
  unsigned short len;
  struct sock_filter *filter;
};
struct mq_attr {
  long mq_flags, mq_maxmsg, mq_msgsize, mq_curmsgs, __unused[4];
};
struct termios2 {
    tcflag_t c_iflag;
    tcflag_t c_oflag;
    tcflag_t c_cflag;
    tcflag_t c_lflag;
    cc_t c_line;
    cc_t c_cc[19];
    speed_t c_ispeed;
    speed_t c_ospeed;
};
struct input_event {
    struct timeval time;
    uint16_t type;
    uint16_t code;
    int32_t value;
};
struct input_id {
    uint16_t bustype;
    uint16_t vendor;
    uint16_t product;
    uint16_t version;
};
struct input_absinfo {
    int32_t value;
    int32_t minimum;
    int32_t maximum;
    int32_t fuzz;
    int32_t flat;
    int32_t resolution;
};
struct input_keymap_entry {
    uint8_t  flags;
    uint8_t  len;
    uint16_t index;
    uint32_t keycode;
    uint8_t  scancode[32];
};
struct ff_replay {
    uint16_t length;
    uint16_t delay;
};
struct ff_trigger {
    uint16_t button;
    uint16_t interval;
};
struct ff_envelope {
    uint16_t attack_length;
    uint16_t attack_level;
    uint16_t fade_length;
    uint16_t fade_level;
};
struct ff_constant_effect {
    int16_t level;
    struct ff_envelope envelope;
};
struct ff_ramp_effect {
    int16_t start_level;
    int16_t end_level;
    struct ff_envelope envelope;
};
struct ff_condition_effect {
    uint16_t right_saturation;
    uint16_t left_saturation;
    int16_t right_coeff;
    int16_t left_coeff;
    uint16_t deadband;
    int16_t center;
};
struct ff_periodic_effect {
    uint16_t waveform;
    uint16_t period;
    int16_t magnitude;
    int16_t offset;
    uint16_t phase;
    struct ff_envelope envelope;
    uint32_t custom_len;
    int16_t *custom_data;
};
struct ff_rumble_effect {
    uint16_t strong_magnitude;
    uint16_t weak_magnitude;
};
struct ff_effect {
    uint16_t type;
    int16_t id;
    uint16_t direction;
    struct ff_trigger trigger;
    struct ff_replay replay;
    union {
        struct ff_constant_effect constant;
        struct ff_ramp_effect ramp;
        struct ff_periodic_effect periodic;
        struct ff_condition_effect condition[2];
        struct ff_rumble_effect rumble;
    } u;
};
typedef struct {
  int     val[2];
} kernel_fsid_t;
/* we define the underlying structs not the pointer typedefs for capabilities */
struct user_cap_header {
  uint32_t version;
  int pid;
};
struct user_cap_data {
  uint32_t effective;
  uint32_t permitted;
  uint32_t inheritable;
};
/* this are overall capabilities structs to put metatables on */
struct cap {
  uint32_t cap[2];
};
struct capabilities {
  uint32_t version;
  int pid;
  struct cap effective;
  struct cap permitted;
  struct cap inheritable;
};
struct xt_get_revision {
  char name[29];
  uint8_t revision;
};
struct vfs_cap_data {
  le32 magic_etc;
  struct {
    le32 permitted;    /* Little endian */
    le32 inheritable;  /* Little endian */
  } data[2];
};
typedef struct {
  void *ss_sp;
  int ss_flags;
  size_t ss_size;
} stack_t;
struct sched_param {
  int sched_priority;
  /* unused after here */
  int sched_ss_low_priority;
  struct timespec sched_ss_repl_period;
  struct timespec sched_ss_init_budget;
  int sched_ss_max_repl;
};
struct tun_filter {
  uint16_t flags;
  uint16_t count;
  uint8_t addr[0][6];
};
struct tun_pi {
  uint16_t flags;
  uint16_t proto; /* __be16 */
};
struct vhost_vring_state {
  unsigned int index;
  unsigned int num;
};
struct vhost_vring_file {
  unsigned int index;
  int fd;
};
struct vhost_vring_addr {
  unsigned int index;
  unsigned int flags;
  uint64_t desc_user_addr;
  uint64_t used_user_addr;
  uint64_t avail_user_addr;
  uint64_t log_guest_addr;
};
struct vhost_memory_region {
  uint64_t guest_phys_addr;
  uint64_t memory_size;
  uint64_t userspace_addr;
  uint64_t flags_padding;
};
struct vhost_memory {
  uint32_t nregions;
  uint32_t padding;
  struct vhost_memory_region regions[0];
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
]]

append(arch.nsig or [[
static const int _NSIG = 64;
]]
)

append(arch.sigset or [[
// again, should be a long
static const int _NSIG_BPW = 32;
typedef struct {
  int32_t sig[_NSIG / _NSIG_BPW];
} sigset_t;
]]
)

-- both Glibc and Musl have larger termios at least for some architectures; I believe this is correct for kernel
append(arch.termios or [[
struct termios {
  tcflag_t c_iflag;
  tcflag_t c_oflag;
  tcflag_t c_cflag;
  tcflag_t c_lflag;
  cc_t c_line;
  cc_t c_cc[19];
};
]]
)

-- Linux struct siginfo padding depends on architecture
if abi.abi64 then
append [[
static const int SI_MAX_SIZE = 128;
static const int SI_PAD_SIZE = (SI_MAX_SIZE / sizeof (int)) - 4;
]]
else
append [[
static const int SI_MAX_SIZE = 128;
static const int SI_PAD_SIZE = (SI_MAX_SIZE / sizeof (int)) - 3;
]]
end

append(arch.siginfo or [[
typedef struct siginfo {
  int si_signo;
  int si_errno;
  int si_code;

  union {
    int _pad[SI_PAD_SIZE];

    struct {
      pid_t si_pid;
      uid_t si_uid;
    } kill;

    struct {
      int si_tid;
      int si_overrun;
      sigval_t si_sigval;
    } timer;

    struct {
      pid_t si_pid;
      uid_t si_uid;
      sigval_t si_sigval;
    } rt;

    struct {
      pid_t si_pid;
      uid_t si_uid;
      int si_status;
      clock_t si_utime;
      clock_t si_stime;
    } sigchld;

    struct {
      void *si_addr;
    } sigfault;

    struct {
      long int si_band;
       int si_fd;
    } sigpoll;
  } _sifields;
} siginfo_t;
]]
)

-- this is the type used by the rt_sigaction syscall NB have renamed the fields to sa_
append(arch.sigaction or [[
struct k_sigaction {
  void (*sa_handler)(int);
  unsigned long sa_flags;
  void (*sa_restorer)(void);
  unsigned sa_mask[2];
};
]]
)

-- these could vary be arch but do not yet
append [[
static const int sigev_preamble_size = sizeof(int) * 2 + sizeof(sigval_t);
static const int sigev_max_size = 64;
static const int sigev_pad_size = (sigev_max_size - sigev_preamble_size) / sizeof(int);
typedef struct sigevent {
  sigval_t sigev_value;
  int sigev_signo;
  int sigev_notify;
  union {
    int _pad[sigev_pad_size];
    int _tid;
    struct {
      void (*_function)(sigval_t);
      void *_attribute;
    } _sigev_thread;
  } _sigev_un;
} sigevent_t;
]]

append(arch.ucontext) -- there is no default for ucontext and related types as very machine specific

if arch.statfs then append(arch.statfs)
else
-- Linux struct statfs/statfs64 depends on 64/32 bit
if abi.abi64 then
append [[
typedef long statfs_word;
]]
else
append [[
typedef uint32_t statfs_word;
]]
end

append [[
struct statfs64 {
  statfs_word f_type;
  statfs_word f_bsize;
  uint64_t f_blocks;
  uint64_t f_bfree;
  uint64_t f_bavail;
  uint64_t f_files;
  uint64_t f_ffree;
  kernel_fsid_t f_fsid;
  statfs_word f_namelen;
  statfs_word f_frsize;
  statfs_word f_flags;
  statfs_word f_spare[4];
};
]]
end

append(arch.stat)

-- epoll packed on x86_64 only (so same as x86)
append(arch.epoll or [[
struct epoll_event {
  uint32_t events;
  epoll_data_t data;
};
]]
)

-- endian dependent
if abi.le then
append [[
struct iocb {
  uint64_t   aio_data;
  uint32_t   aio_key, aio_reserved1;
  uint16_t   aio_lio_opcode;
  int16_t    aio_reqprio;
  uint32_t   aio_fildes;
  uint64_t   aio_buf;
  uint64_t   aio_nbytes;
  int64_t    aio_offset;
  uint64_t   aio_reserved2;
  uint32_t   aio_flags;
  uint32_t   aio_resfd;
};
]]
else
append [[
struct iocb {
  uint64_t   aio_data;
  uint32_t   aio_reserved1, aio_key;
  uint16_t   aio_lio_opcode;
  int16_t    aio_reqprio;
  uint32_t   aio_fildes;
  uint64_t   aio_buf;
  uint64_t   aio_nbytes;
  int64_t    aio_offset;
  uint64_t   aio_reserved2;
  uint32_t   aio_flags;
  uint32_t   aio_resfd;
};
]]
end

-- functions, minimal for Linux as mainly use syscall
append [[
long syscall(int number, ...);

int gettimeofday(struct timeval *tv, void *tz);
int clock_gettime(clockid_t clk_id, struct timespec *tp);
]]

ffi.cdef(table.concat(defs, ""))


-- MIPS specific definitions

-- sigset_t size is set from _NSIG here

return {
  nsig = [[
static const int _NSIG = 128;
]],
  ucontext = [[
typedef struct sigaltstack {
  void *ss_sp;
  size_t ss_size;
  int ss_flags;
} stack_t;
typedef struct {
  unsigned __mc1[2];
  unsigned long long __mc2[65];
  unsigned __mc3[5];
  unsigned long long __mc4[2];
  unsigned __mc5[6];
} mcontext_t;
typedef struct __ucontext {
  unsigned long uc_flags;
  struct __ucontext *uc_link;
  stack_t uc_stack;
  mcontext_t uc_mcontext;
  sigset_t uc_sigmask;
  unsigned long uc_regspace[128];
} ucontext_t;
]],
sigaction = [[
struct k_sigaction {
  unsigned int    sa_flags;
  void (*sa_handler)(int);
  sigset_t        sa_mask;
};
]],
siginfo = [[
/* note renamed members of struct to match other architectures */
typedef struct siginfo {
  int si_signo;
  int si_code;
  int si_errno;
  int __pad0[SI_MAX_SIZE / sizeof(int) - SI_PAD_SIZE - 3];

  union {
    int _pad[SI_PAD_SIZE];

    struct {
      pid_t si_pid;
      uid_t si_uid;
    } kill;

    struct {
      timer_t si_tid;
      int si_overrun;
      char _pad[sizeof(uid_t) - sizeof(int)];
      sigval_t si_sigval;
      int _sys_private;
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
      pid_t si_pid;
      clock_t si_utime;
      int si_status;
      clock_t si_stime;
    } irix_sigchld;

    struct {
      void *si_addr;
      short si_addr_lsb;
    } sigfault;

    struct {
      long si_band;
      int si_fd;
    } sigpoll;

    struct {
      void *si_call_addr;
      int si_syscall;
      unsigned int si_arch;
    } sigsys;
  } _sifields;
} siginfo_t;
]],
  -- note this is struct stat64
  stat = [[
struct stat {
  unsigned long   st_dev;
  unsigned long   __st_pad0[3];
  unsigned long long      st_ino;
  mode_t          st_mode;
  nlink_t         st_nlink;
  uid_t           st_uid;
  gid_t           st_gid;
  unsigned long   st_rdev;
  unsigned long   __st_pad1[3];
  long long       st_size;
  time_t          st_atime;
  unsigned long   st_atime_nsec;
  time_t          st_mtime;
  unsigned long   st_mtime_nsec;
  time_t          st_ctime;
  unsigned long   st_ctime_nsec;
  unsigned long   st_blksize;
  unsigned long   __st_pad2;
  long long       st_blocks;
  long __st_padding4[14];
};
]],
  statfs = [[
struct statfs64 {
  uint32_t   f_type;
  uint32_t   f_bsize;
  uint32_t   f_frsize;
  uint32_t   __pad;
  uint64_t   f_blocks;
  uint64_t   f_bfree;
  uint64_t   f_files;
  uint64_t   f_ffree;
  uint64_t   f_bavail;
  kernel_fsid_t f_fsid;
  uint32_t   f_namelen;
  uint32_t   f_flags;
  uint32_t   f_spare[5];
};
]],
  nsig = [[
static const int _NSIG = 128;
]],
  termios = [[
struct termios {
  tcflag_t c_iflag;
  tcflag_t c_oflag;
  tcflag_t c_cflag;
  tcflag_t c_lflag;
  cc_t c_line;
  cc_t c_cc[23];
};
]],
}


-- MIPS specific definitions

-- TODO sigset_t probably needs to be here as _NSIG = 128 on MIPS

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
}


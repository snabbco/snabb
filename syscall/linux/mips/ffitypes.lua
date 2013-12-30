-- MIPS specific definitions

-- TODO sigset_t probably needs to be here as _NSIG = 128 on MIPS

return {
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
  -- note this is struct stat64
  stat = [[
struct stat {
  unsigned long long st_dev;
  unsigned long long st_ino;
  unsigned int    st_mode;
  unsigned int    st_nlink;
  unsigned int    st_uid;
  unsigned int    st_gid;
  unsigned long long st_rdev;
  unsigned long long __pad1;
  long long       st_size;
  int             st_blksize;
  int             __pad2;
  long long       st_blocks;
  int             st_atime;
  unsigned int    st_atime_nsec;
  int             st_mtime;
  unsigned int    st_mtime_nsec;
  int             st_ctime;
  unsigned int    st_ctime_nsec;
  unsigned int    __unused4;
  unsigned int    __unused5;
};
]],
}

--[[ -- this is what Musl uses, I think it is the n32 stat?

struct stat {
  dev_t st_dev;
  long __st_padding1[2];
  ino_t st_ino;
  mode_t st_mode;
  nlink_t st_nlink;
  uid_t st_uid;
  gid_t st_gid;
  dev_t st_rdev;
  long __st_padding2[2];
  off_t st_size;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  blksize_t st_blksize;
  long __st_padding3;
  blkcnt_t st_blocks;
  long __st_padding4[14];
};
]]



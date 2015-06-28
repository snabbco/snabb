-- arm64 specific definitions

return {
  ucontext = [[
typedef unsigned long greg_t;
typedef unsigned long gregset_t[34];
typedef struct {
  long double vregs[32];
  unsigned int fpsr;
  unsigned int fpcr;
} fpregset_t;
typedef struct sigcontext
{
  unsigned long fault_address;
  unsigned long regs[31];
  unsigned long sp, pc, pstate;
  long double __reserved[256];
} mcontext_t;
typedef struct __ucontext {
  unsigned long uc_flags;
  struct ucontext *uc_link;
  stack_t uc_stack;
  sigset_t uc_sigmask;
  mcontext_t uc_mcontext;
} ucontext_t;
]],
  stat = [[
struct stat {
  dev_t st_dev;
  ino_t st_ino;
  mode_t st_mode;
  nlink_t st_nlink;
  uid_t st_uid;
  gid_t st_gid;
  dev_t st_rdev;
  unsigned long __pad;
  off_t st_size;
  blksize_t st_blksize;
  int __pad2;
  blkcnt_t st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  unsigned __unused[2];
};
]],
  statfs = [[
struct statfs64 {
  unsigned long f_type, f_bsize;
  fsblkcnt_t f_blocks, f_bfree, f_bavail;
  fsfilcnt_t f_files, f_ffree;
  fsid_t f_fsid;
  unsigned long f_namelen, f_frsize, f_flags, f_spare[4];
};
]],
}


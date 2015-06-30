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
  unsigned long   st_dev;
  unsigned long   st_ino;
  unsigned int    st_mode;
  unsigned int    st_nlink;
  unsigned int    st_uid;
  unsigned int    st_gid;
  unsigned long   st_rdev;
  unsigned long   __pad1;
  long            st_size;
  int             st_blksize;
  int             __pad2;
  long            st_blocks;
  long            st_atime;
  unsigned long   st_atime_nsec;
  long            st_mtime;
  unsigned long   st_mtime_nsec;
  long            st_ctime;
  unsigned long   st_ctime_nsec;
  unsigned int    __unused4;
  unsigned int    __unused5;
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


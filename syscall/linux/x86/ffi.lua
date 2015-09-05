-- x86 specific definitions

return {
  ucontext = [[
typedef int greg_t, gregset_t[19];
typedef struct _fpstate {
  unsigned long cw, sw, tag, ipoff, cssel, dataoff, datasel;
  struct {
    unsigned short significand[4], exponent;
  } _st[8];
  unsigned long status;
} *fpregset_t;
typedef struct {
  gregset_t gregs;
  fpregset_t fpregs;
  unsigned long oldmask, cr2;
} mcontext_t;
typedef struct __ucontext {
  unsigned long uc_flags;
  struct __ucontext *uc_link;
  stack_t uc_stack;
  mcontext_t uc_mcontext;
  sigset_t uc_sigmask;
  unsigned long __fpregs_mem[28];
} ucontext_t;
]],
  stat = [[
struct stat {
  unsigned long long      st_dev;
  unsigned char   __pad0[4];
  unsigned long   __st_ino;
  unsigned int    st_mode;
  unsigned int    st_nlink;
  unsigned long   st_uid;
  unsigned long   st_gid;
  unsigned long long      st_rdev;
  unsigned char   __pad3[4];
  long long       st_size;
  unsigned long   st_blksize;
  unsigned long long      st_blocks;
  unsigned long   st_atime;
  unsigned long   st_atime_nsec;
  unsigned long   st_mtime;
  unsigned int    st_mtime_nsec;
  unsigned long   st_ctime;
  unsigned long   st_ctime_nsec;
  unsigned long long      st_ino;
};
]],
  statfs = [[
typedef long statfs_word;
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
} __attribute__((packed,aligned(4)));
]],
}


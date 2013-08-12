-- x64 specific definitions

return {
  epoll = [[
struct epoll_event {
  uint32_t events;
  epoll_data_t data;
}  __attribute__ ((packed));
]],
  statfs64 = [[
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
  ucontext = [[
typedef long long greg_t, gregset_t[23];
typedef struct _fpstate {
  unsigned short cwd, swd, ftw, fop;
  unsigned long long rip, rdp;
  unsigned mxcsr, mxcr_mask;
  struct {
    unsigned short significand[4], exponent, padding[3];
  } _st[8];
  struct {
    unsigned element[4];
  } _xmm[16];
  unsigned padding[24];
} *fpregset_t;
typedef struct {
  gregset_t gregs;
  fpregset_t fpregs;
  unsigned long long __reserved1[8];
} mcontext_t;
typedef struct __ucontext {
  unsigned long uc_flags;
  struct __ucontext *uc_link;
  stack_t uc_stack;
  mcontext_t uc_mcontext;
  sigset_t uc_sigmask;
  unsigned long __fpregs_mem[64];
} ucontext_t;
]],
  stat = [[
struct stat {
  unsigned long   st_dev;
  unsigned long   st_ino;
  unsigned long   st_nlink;
  unsigned int    st_mode;
  unsigned int    st_uid;
  unsigned int    st_gid;
  unsigned int    __pad0;
  unsigned long   st_rdev;
  long            st_size;
  long            st_blksize;
  long            st_blocks;
  unsigned long   st_atime;
  unsigned long   st_atime_nsec;
  unsigned long   st_mtime;
  unsigned long   st_mtime_nsec;
  unsigned long   st_ctime;
  unsigned long   st_ctime_nsec;
  long            __unused[3];
};
]],
}



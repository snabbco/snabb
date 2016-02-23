-- ppc specific definitions

return {
  termios = [[
struct termios {
  tcflag_t c_iflag;
  tcflag_t c_oflag;
  tcflag_t c_cflag;
  tcflag_t c_lflag;
  cc_t c_cc[19];
  cc_t c_line;
  speed_t c_ispeed;
  speed_t c_ospeed;
};
]],
  ucontext = [[
typedef unsigned long greg_t, gregset_t[48];
typedef struct {
  double fpregs[32];
  double fpscr;
  unsigned _pad[2];
} fpregset_t;
typedef struct {
  unsigned vrregs[32][4];
  unsigned vrsave;
  unsigned _pad[2];
  unsigned vscr;
} vrregset_t;
typedef struct {
  gregset_t gregs;
  fpregset_t fpregs;
  vrregset_t vrregs __attribute__((__aligned__(16)));
} mcontext_t;
typedef struct ucontext {
  unsigned long int uc_flags;
  struct ucontext *uc_link;
  stack_t uc_stack;
  int uc_pad[7];
  union uc_regs_ptr {
    struct pt_regs *regs;
    mcontext_t *uc_regs;
  } uc_mcontext;
  sigset_t    uc_sigmask;
  char uc_reg_space[sizeof(mcontext_t) + 12];  /* last for extensibility */
} ucontext_t;
]],
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


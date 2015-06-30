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
  sigset_t uc_sigmask;
  mcontext_t uc_mcontext;
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


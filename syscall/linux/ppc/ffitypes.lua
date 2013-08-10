-- ppc specific definitions

return {
  termio = [[
static const int NCC = 10;
struct termio {
  unsigned short c_iflag;
  unsigned short c_oflag;
  unsigned short c_cflag;
  unsigned short c_lflag;
  unsigned char c_line;
  unsigned char c_cc[NCC];
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
}


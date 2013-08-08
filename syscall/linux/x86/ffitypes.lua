-- x86 specific definitions

local ffi = require "ffi"

local arch = {}

arch.ucontext = function()
return [[
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
]]
end

return arch


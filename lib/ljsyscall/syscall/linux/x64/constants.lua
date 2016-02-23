-- x64 specific constants

local arch = {}

arch.REG = {
  R8         = 0,
  R9         = 1,
  R10        = 2,
  R11        = 3,
  R12        = 4,
  R13        = 5,
  R14        = 6,
  R15        = 7,
  RDI        = 8,
  RSI        = 9,
  RBP        = 10,
  RBX        = 11,
  RDX        = 12,
  RAX        = 13,
  RCX        = 14,
  RSP        = 15,
  RIP        = 16,
  EFL        = 17,
  CSGSFS     = 18,
  ERR        = 19,
  TRAPNO     = 20,
  OLDMASK    = 21,
  CR2        = 22,
}

return arch



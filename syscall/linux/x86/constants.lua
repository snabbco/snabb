-- x86 specific code

local arch = {}

-- x86 register names
arch.REG = {
  GS         = 0,
  FS         = 1,
  ES         = 2,
  DS         = 3,
  EDI        = 4,
  ESI        = 5,
  EBP        = 6,
  ESP        = 7,
  EBX        = 8,
  EDX        = 9,
  ECX        = 10,
  EAX        = 11,
  TRAPNO     = 12,
  ERR        = 13,
  EIP        = 14,
  CS         = 15,
  EFL        = 16,
  UESP       = 17,
  SS         = 18,
}

return arch


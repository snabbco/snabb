-- x86 specific definitions

local ffi = require "ffi"

local arch = {}

arch.sigaction = function()
ffi.cdef[[
struct sigaction {
  union {
    sighandler_t sa_handler;
    void (*sa_sigaction)(int, struct siginfo *, void *);
  };
  sigset_t sa_mask;
  unsigned long sa_flags;
  void (*sa_restorer)(void);
};
]]
end

return arch


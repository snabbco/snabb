-- example of a complex signal handler, in this case produce a Lua backtrace on sigpipe

local S = require "syscall"
local t = S.t
local c = S.c
local ffi = require "ffi"
 
local ip
if ffi.arch == "x86" then ip = c.REG.EIP
elseif ffi.arch == "x64" then ip = c.REG.RIP
else error "unsupported architecture" end

local backtrace = function() error("sigpipe") end
 
local f = t.sa_sigaction(function(s, info, ucontext)
  ucontext.uc_mcontext.gregs[ip] = ffi.cast("intptr_t", ffi.cast("void (*)(void)", backtrace)) -- set instruction pointer to g
end)
assert(S.sigaction("pipe", {sigaction = f}))
 
-- example code to get interesting stack trace
function bb(x)
  assert(S.kill(S.getpid(), "pipe"))
  return x + 1
end
 
function aa(x)
  local c = 2 * bb(x + 1)
  print("not here")
  return c
end
 
aa(2)


-- choose correct syscalls for OS

local abi = require "syscall.abi"

local S = require(abi.os .. ".syscalls")

-- creat is not actually a syscall always, just define
function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end

function S.nice(inc)
  local prio = S.getpriority("process", 0) -- this cannot fail with these args.
  local ok, err = S.setpriority("process", 0, prio + inc)
  if not ok then return nil, err end
  return S.getpriority("process", 0)
end

-- TODO setpgrp and similar - see the man page

return S


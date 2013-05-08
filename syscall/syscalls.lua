-- choose correct syscalls for OS

local abi = require "syscall.abi"

local S = require(abi.os .. ".syscalls")

-- creat is not actually a syscall always, just define
function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end

return S


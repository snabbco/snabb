local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local abi = require "syscall.abi"

local nr = require("syscall.linux." .. abi.arch .. ".nr")

if nr.SYS.socketcall then nr.socketcalls = {
  SOCKET      = 1,
  BIND        = 2,
  CONNECT     = 3,
  LISTEN      = 4,
  ACCEPT      = 5,
  GETSOCKNAME = 6,
  GETPEERNAME = 7,
  SOCKETPAIR  = 8,
  SEND        = 9,
  RECV        = 10,
  SENDTO      = 11,
  RECVFROM    = 12,
  SHUTDOWN    = 13,
  SETSOCKOPT  = 14,
  GETSOCKOPT  = 15,
  SENDMSG     = 16,
  RECVMSG     = 17,
  ACCEPT4     = 18,
  RECVMMSG    = 19,
  SENDMMSG    = 20,
}
end

return nr


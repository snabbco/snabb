-- BSD specific syscalls

return function(S, hh)

local c = require "syscall.constants"
local C = require "syscall.c"
local types = require "syscall.types"
local abi = require "syscall.abi"

local istype, mktype, getfd = hh.istype, hh.mktype, hh.getfd
local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

function S.accept(sockfd, flags, addr, addrlen) -- TODO add support for signal mask that paccept has
  addr = addr or t.sockaddr_storage()
  addrlen = addrlen or t.socklen1(addrlen or #addr)
  local ret
  if not flags
    then ret = C.accept(getfd(sockfd), addr, addrlen)
    else ret = C.paccept(getfd(sockfd), addr, addrlen, nil, c.SOCK[flags])
  end
  if ret == -1 then return nil, t.error() end
  return {fd = t.fd(ret), addr = t.sa(addr, addrlen[0])}
end

function S.exit(status) C.exit(c.EXIT[status]) end
function S.mkfifo(pathname, mode) return retbool(C.mkfifo(pathname, c.S_I[mode])) end

return S

end


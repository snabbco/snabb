-- OSX specific syscalls

return function(S, hh, abi, c, C, types, ioctl)

local istype, mktype, getfd = hh.istype, hh.mktype, hh.getfd
local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

function S.mkfifo(pathname, mode) return retbool(C.mkfifo(pathname, c.S_I[mode])) end

return S

end


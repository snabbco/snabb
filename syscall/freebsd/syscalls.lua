-- FreeBSD specific syscalls

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local version = require "syscall.freebsd.version".version

return function(S, hh, c, C, types)

local ret64, retnum, retfd, retbool, retptr = hh.ret64, hh.retnum, hh.retfd, hh.retbool, hh.retptr

local ffi = require "ffi"
local errno = ffi.errno

local h = require "syscall.helpers"

local istype, mktype, getfd = h.istype, h.mktype, h.getfd

local t, pt, s = types.t, types.pt, types.s

function S.reboot(howto) return C.reboot(c.RB[howto]) end

if C.bindat then
  function S.bindat(dirfd, sockfd, addr, addrlen)
    local saddr = pt.sockaddr(addr)
    return retbool(C.bindat(c.AT_FDCWD[dirfd], getfd(sockfd), saddr, addrlen or #addr))
  end
end
if C.connectat then
  function S.connectat(dirfd, sockfd, addr, addrlen)
    local saddr = pt.sockaddr(addr)
    return retbool(C.connectat(c.AT_FDCWD[dirfd], getfd(sockfd), saddr, addrlen or #addr))
  end
end

function S.pdfork(flags, fdp) -- changed order as rarely supply fdp
  fdp = fdp or t.int1()
  local pid, err = C.pdfork(fdp, c.PD[flags])
  if pid == -1 then return nil, t.error(err or errno()) end
  if pid == 0 then return 0 end -- the child does not get an fd
  return pid, nil, t.fd(fdp[0])
end
function S.pdgetpid(fd, pidp)
  pidp = pidp or t.int1()
  local ok, err = C.pdgetpid(getfd(fd), pidp)
  if ok == -1 then return nil, t.error(err or errno()) end
  return pidp[0]
end
function S.pdkill(fd, sig) return retbool(C.pdkill(getfd(fd), c.SIG[sig])) end
-- pdwait4 not implemented in FreeBSD yet

if C.cap_enter and version >= 10 then -- do not support on FreeBSD 9, only partial implementation
  function S.cap_enter() return retbool(C.cap_enter()) end
end
if C.cap_getmode and version >= 10 then
  function S.cap_getmode(modep)
    modep = modep or t.uint1()
    local ok, err = C.cap_getmode(modep)
    if ok == -1 then return nil, t.error(err or errno()) end
    return modep[0]
  end
  function S.cap_sandboxed()
    local modep = S.cap_getmode()
    if not modep then return false end
    return modep ~= 0
  end
end

-- pty functions
local function isptmaster(fd) return fd:ioctl("TIOCPTMASTER") end
S.grantpt = isptmaster
S.unlockpt = isptmaster

local SPECNAMELEN = 63

function S.ptsname(fd)
  local ok, err = isptmaster(fd)
  if not ok then return nil, err end
  local buf = t.buffer(SPECNAMELEN)
  local fgn = t.fiodgname_arg{buf = buf, len = SPECNAMELEN}
  local ok, err = fd:ioctl("FIODGNAME", fgn)
  if not ok then return nil, err end
  return "/dev/" .. ffi.string(buf)
end

return S

end


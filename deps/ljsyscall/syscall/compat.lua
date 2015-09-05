-- Compatibility wrappers to add more commonality between different systems, plus define common functions from man(3)

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S) 

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local ffi = require "ffi"

local h = require "syscall.helpers"

local istype, mktype, getfd = h.istype, h.mktype, h.getfd

if not S.creat then
  function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end
end

function S.nice(inc)
  local prio = S.getpriority("process", 0) -- this cannot fail with these args.
  local ok, err = S.setpriority("process", 0, prio + inc)
  if not ok then return nil, err end
  return S.getpriority("process", 0)
end

-- deprecated in NetBSD and not in some archs for Linux, implement with recvfrom/sendto
function S.recv(fd, buf, count, flags) return S.recvfrom(fd, buf, count, flags, nil, nil) end
function S.send(fd, buf, count, flags) return S.sendto(fd, buf, count, flags, nil, nil) end

-- not a syscall in many systems, defined in terms of sigaction
local sigret = {}
for k, v in pairs(c.SIGACT) do if k ~= "ERR" then sigret[v] = k end end

if S.sigaction then
  function S.signal(signum, handler) -- defined in terms of sigaction, see portability notes in Linux man page
    local oldact = t.sigaction()
    local ok, err = S.sigaction(signum, handler, oldact)
    if not ok then return nil, err end
    local num = tonumber(t.intptr(oldact.handler))
    local ret = sigret[num]
    if ret then return ret end -- return eg "IGN", "DFL" not a function pointer
    return oldact.handler
  end
end

if not S.pause and S.sigsuspend then -- NetBSD and OSX deprecate pause
  function S.pause() return S.sigsuspend(t.sigset()) end
end

if not S.alarm and S.setitimer then -- usually implemented via itimer, although Linux provides alarm as syscall
  function S.alarm(sec)
    local oldit, err = S.setitimer(c.ITIMER.REAL, {0, sec})
    if not oldit then return nil, err end -- alarm not supposed to return errors but hey
    return oldit.value.sec
  end
end

-- non standard names
if not S.umount then S.umount = S.unmount end
if not S.unmount then S.unmount = S.umount end

if S.getdirentries and not S.getdents then -- eg OSX has extra arg
  function S.getdents(fd, buf, len)
    return S.getdirentries(fd, buf, len, nil)
  end
end

-- TODO we should allow utimbuf and also table of times really; this is the very old 1s precision version, NB Linux has syscall
if not S.utime then
  function S.utime(path, actime, modtime)
    local tv
    modtime = modtime or actime
    if actime and modtime then tv = {actime, modtime} end
    return S.utimes(path, tv)
  end
end

-- not a syscall in Linux
if S.utimensat and not S.futimens then
  function S.futimens(fd, times)
    return S.utimensat(fd, nil, times, 0)
  end
end

-- some linux arhcitectures eg ARM do not have a time syscall
if not S.time then
  function S.time(t)
    local tv = S.gettimeofday()
    if t then t[0] = tv.sec end
    return tv.sec
  end
end

-- the utimes, futimes, lutimes are legacy, but OSX/FreeBSD do not support the nanosecond versions
-- we support the legacy versions but do not fake the more precise ones
S.futimes = S.futimes or S.futimens
if S.utimensat and not S.lutimes then
  function S.lutimes(filename, times)
    return S.utimensat("FDCWD", filename, times, "SYMLINK_NOFOLLOW")
  end
end
if S.utimensat and not S.utimes then
  function S.utimes(filename, times)
    return S.utimensat("FDCWD", filename, times, 0)
  end
end

if not S.wait then
  function S.wait(status) return S.waitpid(-1, 0, status) end
end

S.wait3 = function(options, rusage, status) return S.wait4(-1, options, rusage, status) end

if not S.waitpid and S.wait4 then
  S.waitpid = function(pid, options, status) return S.wait4(pid, options, false, status) end
end

if S.wait4 and not S.wait then
  S.wait = function(status) return S.wait4(-1, 0, false, status) end
end

if not S.nanosleep then
  function S.nanosleep(req, rem)
    S.select({}, req)
    if rem then rem.sec, rem.nsec = 0, 0 end -- cannot tell how much time left, could be interrupted by a signal.
    return true
  end
end

-- common libc function
if not S.sleep and S.nanosleep then
  function S.sleep(sec)
    local ok, err, rem = S.nanosleep(sec)
    if not ok then return nil, err end
    if rem then return tonumber(rem.tv_sec) end
    return 0
  end
end

return S

end

return {init = init}


-- Compatibility wrappers to add more commonality between different systems, plus define common functions from man(3)

local function init(S)

local types, c = S.types, S.c
local t, pt, s = types.t, types.pt, types.s

function S.creat(pathname, mode) return S.open(pathname, "CREAT,WRONLY,TRUNC", mode) end

function S.nice(inc)
  local prio = S.getpriority("process", 0) -- this cannot fail with these args.
  local ok, err = S.setpriority("process", 0, prio + inc)
  if not ok then return nil, err end
  return S.getpriority("process", 0)
end

-- deprecated in NetBSD, implement with recvfrom
function S.recv(fd, buf, count, flags) return S.recvfrom(fd, buf, count or #buf, c.MSG[flags], nil, nil) end

-- not a syscall in many systems, defined in terms of sigaction
function S.signal(signum, handler) -- defined in terms of sigaction
  local oldact = t.sigaction()
  local ok, err = S.sigaction(signum, handler, oldact)
  if not ok then return nil, err end
  return oldact.sa_handler
end

if not S.pause then -- NetBSD and OSX deprecate pause
  function S.pause() return S.sigsuspend(t.sigset()) end
end

-- old rlimit functions in Linux are 32 bit only so now defined using prlimit
if S.prlimit and not S.getrlimit then
  function S.getrlimit(resource)
    return S.prlimit(0, resource)
  end

  function S.setrlimit(resource, rlim)
    local ret, err = S.prlimit(0, resource, rlim)
    if not ret then return nil, err end
    return true
  end
end

if not S.umount then S.umount = S.unmount end
if not S.unmount then S.unmount = S.umount end

-- the utimes, futimes, lutimes are legacy, but OSX does not support the nanosecond versions; we support both

-- TODO we should allow utimbuf and also table of times really
if not S.utime then
  function S.utime(path, actime, modtime)
    local ts
    modtime = modtime or actime
    if actime and modtime then ts = {actime, modtime} end
    return S.utimensat(nil, path, ts)
  end
end

-- TODO setpgrp and similar - see the man page

return S

end

return {init = init}


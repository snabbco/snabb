-- Linux specific compatibility code, as Linux has odd issues

local function init(S)

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

-- old rlimit functions in Linux are 32 bit only so now defined using prlimit
function S.getrlimit(resource)
  return S.prlimit(0, resource)
end

function S.setrlimit(resource, rlim)
  local ret, err = S.prlimit(0, resource, rlim)
  if not ret then return nil, err end
  return true
end

function S.gethostname()
  local u, err = S.uname()
  if not u then return nil, err end
  return u.nodename
end

function S.getdomainname()
  local u, err = S.uname()
  if not u then return nil, err end
  return u.domainname
end

function S.killpg(pgrp, sig) return S.kill(-pgrp, sig) end

-- helper function to read inotify structs as table from inotify fd, TODO could be in util
function S.inotify_read(fd, buffer, len)
  len = len or 1024
  buffer = buffer or t.buffer(len)
  local ret, err = S.read(fd, buffer, len)
  if not ret then return nil, err end
  return t.inotify_events(buffer, ret)
end

-- in Linux mkfifo is not a syscall, emulate
function S.mkfifo(path, mode) return S.mknod(path, bit.bor(c.MODE[mode], c.S_I.FIFO)) end
function S.mkfifoat(fd, path, mode) return S.mknodat(fd, path, bit.bor(c.MODE[mode], c.S_I.FIFO), 0) end

-- in Linux shm_open and shm_unlink are not syscalls
local shm = "/dev/shm"

function S.shm_open(pathname, flags, mode)
  if pathname:sub(1, 1) ~= "/" then pathname = "/" .. pathname end
  pathname = shm .. pathname
  return S.open(pathname, c.O(flags, "nofollow", "cloexec", "nonblock"), mode)
end

function S.shm_unlink(pathname)
  if pathname:sub(1, 1) ~= "/" then pathname = "/" .. pathname end
  pathname = shm .. pathname
  return S.unlink(pathname)
end

-- TODO setpgrp and similar - see the man page

return S

end

return {init = init}


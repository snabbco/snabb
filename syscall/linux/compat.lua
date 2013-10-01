-- Linux specific compatibility code, as Linux has odd issues

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

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

-- in Linux pathconf can just return constants

-- TODO these could go into constants, although maybe better to get from here, and some are slightly bogus eg PAGE_SIZE
local PAGE_SIZE = 4096
local NAME_MAX = 255
local PATH_MAX = 4096 -- TODO this is in constants, inconsistently
local PIPE_BUF = 4096
local FILESIZEBITS = 64
local SYMLINK_MAX = 255
local _POSIX_LINK_MAX = 8
local _POSIX_MAX_CANON = 255
local _POSIX_MAX_INPUT = 255

local pathconf_values = {
  [c.PC.LINK_MAX] = _POSIX_LINK_MAX,
  [c.PC.MAX_CANON] = _POSIX_MAX_CANON,
  [c.PC.MAX_INPUT] = _POSIX_MAX_INPUT,
  [c.PC.NAME_MAX] = NAME_MAX,
  [c.PC.PATH_MAX] = PATH_MAX,
  [c.PC.PIPE_BUF] = PIPE_BUF,
  [c.PC.CHOWN_RESTRICTED] = 1,
  [c.PC.NO_TRUNC] = 1,
  [c.PC.VDISABLE] = 0,
  [c.PC.SYNC_IO] = 1,
  [c.PC.ASYNC_IO] = -1,
  [c.PC.PRIO_IO] = -1,
  [c.PC.SOCK_MAXBUF] = -1,
  [c.PC.FILESIZEBITS] = FILESIZEBITS,
  [c.PC.REC_INCR_XFER_SIZE] = PAGE_SIZE,
  [c.PC.REC_MAX_XFER_SIZE] = PAGE_SIZE,
  [c.PC.REC_MIN_XFER_SIZE] = PAGE_SIZE,
  [c.PC.REC_XFER_ALIGN] = PAGE_SIZE,
  [c.PC.ALLOC_SIZE_MIN] = PAGE_SIZE,
  [c.PC.SYMLINK_MAX] = SYMLINK_MAX,
  [c.PC["2_SYMLINKS"]] = 1,
}

function S.pathconf(_, name) return pathconf_values[c.PC[name]] end
function S.fpathconf(_, name) return pathconf_values[c.PC[name]] end

return S

end

return {init = init}


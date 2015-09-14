-- generic utils not specific to any OS

-- these are generally equivalent to things that are in man(1) or man(3)
-- these can be made more modular as number increases

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S)

local h = require "syscall.helpers"
local htonl = h.htonl

local ffi = require "ffi"
local bit = require "syscall.bit"

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local mt, meth = {}, {}

local util = require("syscall." .. abi.os .. ".util").init(S)

mt.dir = {
  __tostring = function(t)
    if #t == 0 then return "" end
    table.sort(t)
    return table.concat(t, "\n") .. "\n"
    end
}

function util.dirtable(name, nodots) -- return table of directory entries, remove . and .. if nodots true
  local d = {}
  local size = 4096
  local buf = t.buffer(size)
  local iter, err = util.ls(name, buf, size)
  if not iter then return nil, err end
  for f in iter do
    if not (nodots and (f == "." or f == "..")) then d[#d + 1] = f end
  end
  return setmetatable(d, mt.dir)
end

-- this returns an iterator over multiple calls to getdents TODO add nodots?
-- note how errors work, getdents will throw as called multiple times, but normally should not fail if open succeeds
-- getdents can fail eg on nfs though.
function util.ls(name, buf, size)
  size = size or 4096
  buf = buf or t.buffer(size)
  if not name then name = "." end
  local fd, err = S.open(name, "directory, rdonly")
  if err then return nil, err end
  local di
  return function()
    local d, first
    repeat
      if not di then
        local err
        di, err = fd:getdents(buf, size)
        if not di then
          fd:close()
          error(err)
        end
        first = true
      end
      d = di()
      if not d then di = nil end
      if not d and first then return nil end
    until d
    return d.name, d
  end
end

-- recursive rm TODO use ls iterator, which also returns type
local function rmhelper(file, prefix)
  local name
  if prefix then name = prefix .. "/" .. file else name = file end
  local st, err = S.lstat(name)
  if not st then return nil, err end
  if st.isdir then
    local files, err = util.dirtable(name, true)
    if not files then return nil, err end
    for _, f in pairs(files) do
      local ok, err = rmhelper(f, name)
      if not ok then return nil, err end
    end
    local ok, err = S.rmdir(name)
    if not ok then return nil, err end
  else
    local ok, err = S.unlink(name)
    if not ok then return nil, err end
  end
  return true
end

function util.rm(...)
  for _, f in ipairs{...} do
    local ok, err = rmhelper(f)
    if not ok then return nil, err end
  end
  return true
end

-- TODO warning broken
function util.cp(source, dest, mode) -- TODO make much more functional, less broken, esp fix mode! and size issue!!
  local contents, err = util.readfile(source)
  if not contents then return nil, err end
  local ok, err = util.writefile(dest, contents, mode)
  if not ok then return nil, err end
  return true
end

function util.touch(file)
  local fd, err = S.open(file, "wronly,creat,noctty,nonblock", "0666")
  if not fd then return nil, err end
  local fd2, err = S.dup(fd)
  if not fd2 then
    fd2:close()
    return nil, err
  end
  fd:close()
  local ok, err = S.futimes(fd2)
  fd2:close()
  if not ok then return nil, err end
  return true
end

function util.createfile(file) -- touch without timestamp adjustment
  local fd, err = S.open(file, "wronly,creat,noctty,nonblock", "0666")
  if not fd then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return true
end

function util.mapfile(name) -- generally better to use, but no good for sysfs etc
  local fd, err = S.open(name, "rdonly")
  if not fd then return nil, err end
  local st, err = S.fstat(fd)
  if not st then return nil, err end
  local size = st.size
  local m, err = S.mmap(nil, size, "read", "shared", fd, 0)
  if not m then return nil, err end
  local str = ffi.string(m, size)
  local ok, err = S.munmap(m, size)
  if not ok then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return str
end

-- TODO fix short reads, but mainly used for sysfs, proc
function util.readfile(name, buffer, length)
  local fd, err = S.open(name, "rdonly")
  if not fd then return nil, err end
  local r, err = S.read(fd, buffer, length or 4096)
  if not r then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return r
end

-- write string to named file; silently ignore short writes TODO fix
function util.writefile(name, str, mode, flags)
  local fd, err
  if mode then fd, err = S.creat(name, mode) else fd, err = S.open(name, flags or "wronly") end
  if not fd then return nil, err end
  local n, err = S.write(fd, str)
  if not n then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return true
end

mt.ps = {
  __tostring = function(ps)
    local s = {}
    for i = 1, #ps do
      s[#s + 1] = tostring(ps[i])
    end
    return table.concat(s, '\n')
  end
}

-- note that Linux and NetBSD have /proc but FreeBSD does not usually have it mounted, although it is an option
function util.ps()
  local ls, err = util.dirtable("/proc")
  if not ls then return nil, err end
  local ps = {}
  for i = 1, #ls do
    if not string.match(ls[i], '[^%d]') then
      local p = util.proc(tonumber(ls[i]))
      if p then ps[#ps + 1] = p end
    end
  end
  table.sort(ps, function(a, b) return a.pid < b.pid end)
  return setmetatable(ps, mt.ps)
end

mt.proc = {
  __index = function(p, k)
    local name = p.dir .. k
    local st, err = S.lstat(name)
    if not st then return nil, err end
    if st.isreg then
      local fd, err = S.open(p.dir .. k, "rdonly")
      if not fd then return nil, err end
      local ret, err = S.read(fd) -- read defaults to 4k, sufficient?
      if not ret then return nil, err end
      S.close(fd)
      return ret -- TODO many could usefully do with some parsing
    end
    if st.islnk then
      local ret, err = S.readlink(name)
      if not ret then return nil, err end
      return ret
    end
    -- TODO directories
  end,
  __tostring = function(p) -- TODO decide what to print
    local c = p.cmdline
    if c then
      if #c == 0 then
        local comm = p.comm
        if comm and #comm > 0 then
          c = '[' .. comm:sub(1, -2) .. ']'
        end
      end
      return p.pid .. '  ' .. c
    end
  end
}

function util.proc(pid)
  if not pid then pid = S.getpid() end
  return setmetatable({pid = pid, dir = "/proc/" .. pid .. "/"}, mt.proc)
end

-- receive cmsg, extended helper on recvmsg, fairly incomplete at present
function util.recvcmsg(fd, msg, flags)
  if not msg then
    local buf1 = t.buffer(1) -- assume user wants to receive single byte to get cmsg
    local io = t.iovecs{{buf1, 1}}
    local bufsize = 1024 -- sane default, build your own structure otherwise
    local buf = t.buffer(bufsize)
    msg = t.msghdr{iov = io, msg_control = buf, msg_controllen = bufsize}
  end
  local count, err = S.recvmsg(fd, msg, flags)
  if not count then return nil, err end
  local ret = {count = count, iovec = msg.msg_iov} -- thats the basic return value, and the iovec
  for mc, cmsg in msg:cmsgs() do
    local pid, uid, gid = cmsg:credentials()
    if pid then
      ret.pid = pid
      ret.uid = uid
      ret.gid = gid
    end
    local fd_array = {}
    for fd in cmsg:fds() do
      fd_array[#fd_array + 1] = fd
    end
    ret.fd = fd_array
  end
  return ret
end

function util.sendfds(fd, ...)
  local buf1 = t.buffer(1) -- need to send one byte
  local io = t.iovecs{{buf1, 1}}
  local cmsg = t.cmsghdr("socket", "rights", {...})
  local msg = t.msghdr{iov = io, control = cmsg}
  return S.sendmsg(fd, msg, 0)
end

-- generic inet name to ip, also with netmask support
-- TODO convert to a type? either way should not really be in util, probably helpers
-- better as a type that returns inet, mask
function util.inet_name(src, netmask)
  local addr
  if not netmask then
    local a, b = src:find("/", 1, true)
    if a then
      netmask = tonumber(src:sub(b + 1))
      src = src:sub(1, a - 1)
    end
  end
  if src:find(":", 1, true) then -- ipv6
    addr = t.in6_addr(src)
    if not addr then return nil end
    if not netmask then netmask = 128 end
  else
    addr = t.in_addr(src)
    if not addr then return nil end
    if not netmask then netmask = 32 end
  end
  return addr, netmask
end

local function lastslash(name)
  local ls
  local i = 0
  while true do 
    i = string.find(name, "/", i + 1)
    if not i then return ls end
    ls = i
  end
end

local function deltrailslash(name)
  while name:sub(#name) == "/" do
    name = string.sub(name, 1, #name - 1)
  end
  return name
end

function util.basename(name)
  if name == "" then return "." end
  name = deltrailslash(name)
  if name == "" then return "/" end -- was / or // etc
  local ls = lastslash(name)
  if not ls then return name end
  return string.sub(name, ls + 1)
end

function util.dirname(name)
  if name == "" then return "." end
  name = deltrailslash(name)
  if name == "" then return "/" end -- was / or // etc
  local ls = lastslash(name)
  if not ls then return "." end
  name = string.sub(name, 1, ls - 1)
  name = deltrailslash(name)
  if name == "" then return "/" end -- was / or // etc
  return name
end

return util

end

return {init = init}


-- misc utils

-- aim is to move a lot of stuff that is not strictly syscalls out of main code to modularise better
-- most code here is man(1) or man(3) or misc helpers for common tasks.

-- TODO rework so that items can be methods on fd again, for eventfd, timerfd, signalfd and tty

local S = require "syscall"

local abi = S.abi
local types = S.types
local c = S.c

local h = require "syscall.helpers"

local ffi = require "ffi"

local octal = h.octal

-- TODO move to helpers? see notes in syscall.lua about reworking though
local function istype(tp, x)
  if ffi.istype(tp, x) then return x end
  return false
end

local util = {}

local t, pt, s = types.t, types.pt, types.s

local mt = {}

function util.dirfile(name, nodots) -- return the directory entries in a file, remove . and .. if nodots true
  local fd, d, ok, err
  fd, err = S.open(name, "directory, rdonly")
  if err then return nil, err end
  d, err = S.getdents(fd)
  if err then return nil, err end
  if nodots then
    d["."] = nil
    d[".."] = nil
  end
  ok, err = fd:close()
  if not ok then return nil, err end
  return d
end

mt.ls = {
  __tostring = function(t)
    table.sort(t)
    return table.concat(t, "\n")
    end
}

function util.ls(name, nodots) -- return just the list, no other data, cwd if no directory specified
  if not name then name = S.getcwd() end
  local ds, err = util.dirfile(name, nodots)
  if not ds then return nil, err end
  local l = {}
  for k, _ in pairs(ds) do l[#l + 1] = k end
  return setmetatable(l, mt.ls)
end

-- recursive rm
local function rmhelper(file, prefix)
  local name
  if prefix then name = prefix .. "/" .. file else name = file end
  local st, err = S.lstat(name)
  if not st then return nil, err end
  if st.isdir then
    local files, err = util.dirfile(name, true)
    if not files then return nil, err end
    for f, _ in pairs(files) do
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

function util.cp(source, dest, mode) -- TODO make much more functional, less broken
  local contents, err = util.mapfile(source)
  if not contents then return nil, err end
  local ok, err = util.writefile(dest, contents, mode)
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

function util.ps()
  local ls, err = util.ls("/proc")
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

-- bridge functions. in error cases use gc to close file.
local function bridge_ioctl(io, name)
  local s, err = S.socket(c.AF.LOCAL, c.SOCK.STREAM, 0)
  if not s then return nil, err end
  local ret, err = S.ioctl(s, io, name)
  if not ret then return nil, err end
  local ok, err = s:close()
  if not ok then return nil, err end
  return true
end

function util.bridge_add(name) return bridge_ioctl("SIOCBRADDBR", name) end
function util.bridge_del(name) return bridge_ioctl("SIOCBRDELBR", name) end

local function bridge_if_ioctl(io, bridge, dev)
  local err, s, ifr, len, ret, ok
  s, err = S.socket(c.AF.LOCAL, c.SOCK.STREAM, 0)
  if not s then return nil, err end
  if type(dev) == "string" then
    dev, err = if_nametoindex(dev, s)
    if not dev then return nil, err end
  end
  ifr = t.ifreq()
  len = #bridge + 1
  if len > IFNAMSIZ then len = IFNAMSIZ end
  ffi.copy(ifr.ifr_ifrn.ifrn_name, bridge, len) -- note not using the short forms as no metatable defined yet...
  ifr.ifr_ifru.ifru_ivalue = dev
  ret, err = S.ioctl(s, io, ifr);
  if not ret then return nil, err end
  ok, err = s:close()
  if not ok then return nil, err end
  return true
end

function util.bridge_add_interface(bridge, dev) return bridge_if_ioctl(c.SIOC.BRADDIF, bridge, dev) end
function util.bridge_add_interface(bridge, dev) return bridge_if_ioctl(c.SIOC.BRDELIF, bridge, dev) end

-- should probably have constant for "/sys/class/net"

local function brinfo(d) -- can be used as subpart of general interface info
  local bd = "/sys/class/net/" .. d .. "/" .. c.SYSFS_BRIDGE_ATTR
  if not S.stat(bd) then return nil end
  local bridge = {}
  local fs = util.dirfile(bd, true)
  if not fs then return nil end
  for f, _ in pairs(fs) do
    local s = util.readfile(bd .. "/" .. f)
    if s then
      s = s:sub(1, #s - 1) -- remove newline at end
      if f == "group_addr" or f == "root_id" or f == "bridge_id" then -- string values
        bridge[f] = s
      elseif f == "stp_state" then -- bool
        bridge[f] = s == 1
      else
        bridge[f] = tonumber(s) -- not quite correct, most are timevals TODO
      end
    end
  end

  local brif, err = util.ls("/sys/class/net/" .. d .. "/" .. c.SYSFS_BRIDGE_PORT_SUBDIR, true)
  if not brif then return nil end

  local fdb = "/sys/class/net/" .. d .. "/" .. c.SYSFS_BRIDGE_FDB
  if not S.stat(fdb) then return nil end
  local sl = 2048
  local buffer = t.buffer(sl)
  local fd = S.open(fdb, "rdonly")
  if not fd then return nil end
  local brforward = {}

  repeat
    local n = S.read(fd, buffer, sl)
    if not n then return nil end

    local fdbs = pt.fdb_entry(buffer)

    for i = 1, math.floor(n / s.fdb_entry) do
      local fdb = fdbs[i - 1]
      local mac = t.macaddr()
      ffi.copy(mac, fdb.mac_addr, IFHWADDRLEN)

      -- TODO ageing_timer_value is not an int, time, float
      brforward[#brforward + 1] = {
        mac_addr = mac, port_no = tonumber(fdb.port_no),
        is_local = fdb.is_local ~= 0,
        ageing_timer_value = tonumber(fdb.ageing_timer_value)
      }
    end

  until n == 0
  if not fd:close() then return nil end

  return {bridge = bridge, brif = brif, brforward = brforward}
end

function util.bridge_list()
  local dir, err = util.dirfile("/sys/class/net", true)
  if not dir then return nil, err end
  local b = {}
  for d, _ in pairs(dir) do
    b[d] = brinfo(d)
  end
  return b
end

function util.touch(file)
  local fd, err = S.open(file, "wronly,creat,noctty,nonblock", octal("666"))
  if not fd then return nil, err end
  local fd2, err = S.dup(fd)
  if not fd2 then
    fd2:close()
    return nil, err
  end
  fd:close()
  local ok, err = S.futimens(fd2, "now")
  fd2:close()
  if not ok then return nil, err end
  return true
end

local function div(a, b) return math.floor(tonumber(a) / tonumber(b)) end -- would be nicer if replaced with shifts, as only powers of 2

-- receive cmsg, extended helper on recvmsg, fairly incomplete at present
function util.recvcmsg(fd, msg, flags)
  if not msg then
    local buf1 = t.buffer(1) -- assume user wants to receive single byte to get cmsg
    local io = t.iovecs{{buf1, 1}}
    local bufsize = 1024 -- sane default, build your own structure otherwise
    local buf = t.buffer(bufsize)
    msg = t.msghdr{msg_iov = io.iov, msg_iovlen = #io, msg_control = buf, msg_controllen = bufsize}
  end
  local count, err = S.recvmsg(fd, msg, flags)
  if not count then return nil, err end
  local ret = {count = count, iovec = msg.msg_iov} -- thats the basic return value, and the iovec
  for mc, cmsg in msg:cmsgs() do
    if cmsg.cmsg_level == c.SOL.SOCKET then
      if cmsg.cmsg_type == c.SCM.CREDENTIALS then
        local cred = pt.ucred(cmsg + 1) -- cmsg_data
        ret.pid = cred.pid
        ret.uid = cred.uid
        ret.gid = cred.gid
      elseif cmsg.cmsg_type == c.SCM.RIGHTS then
        local fda = pt.int(cmsg + 1) -- cmsg_data
        local fdc = div(cmsg:datalen(), s.int)
        ret.fd = {}
        for i = 1, fdc do ret.fd[i] = t.fd(fda[i - 1]) end
      end -- TODO add other SOL.SOCKET messages
    end -- TODO add other processing for different types
  end
  return ret
end

-- helper functions

function util.sendcred(fd, pid, uid, gid) -- only needed for root to send (incorrect!) credentials
  if not pid then pid = C.getpid() end
  if not uid then uid = C.getuid() end
  if not gid then gid = C.getgid() end
  local ucred = t.ucred()
  ucred.pid = pid
  ucred.uid = uid
  ucred.gid = gid
  local buf1 = t.buffer(1) -- need to send one byte
  local io = t.iovecs{{buf1, 1}}

  local cmsg = t.cmsghdr(c.SOL.SOCKET, c.SCM.CREDENTIALS, ucred)

  local msg = t.msghdr() -- assume socket connected and so does not need address
  msg.msg_iov = io.iov
  msg.msg_iovlen = #io
  msg.msg_control = cmsg
  msg.msg_controllen = #cmsg

  return S.sendmsg(fd, msg, 0)
end

function util.sendfds(fd, ...)
  local buf1 = t.buffer(1) -- need to send one byte
  local io = t.iovecs{{buf1, 1}}
  local fds = {}
  for i, v in ipairs{...} do fds[i] = v:getfd() end
  local fa = t.ints(#fds, fds)
  local fasize = ffi.sizeof(fa)

  local cmsg = t.cmsghdr(c.SOL.SOCKET, c.SCM.RIGHTS, fa, fasize)

  local msg = t.msghdr() -- assume socket connected and so does not need address
  msg.msg_iov = io.iov
  msg.msg_iovlen = #io
  msg.msg_control = cmsg
  msg.msg_controllen = #cmsg

  return S.sendmsg(fd, msg, 0)
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

-- TODO could add umount method.
mt.mount = {
  __tostring = function(m) return m.source .. " on " .. m.target .. " type " .. m.type .. " (" .. m.flags .. ")" end,
}

mt.mounts = {
  __tostring = function(ms)
  local rs = ""
  for i = 1, #ms do
    rs = rs .. tostring(ms[i]) .. '\n'
  end
  return rs
end
}

function util.mounts(file)
  local mf, err = util.readfile(file or "/proc/mounts")
  if not mf then return nil, err end
  local mounts = {}
  for line in mf:gmatch("[^\r\n]+") do
    local l = {}
    local parts = {"source", "target", "type", "flags", "freq", "passno"}
    local p = 1
    for word in line:gmatch("%S+") do
      l[parts[p]] = word
      p = p + 1
    end
    mounts[#mounts + 1] = setmetatable(l, mt.mount)
  end
  -- TODO some of the options you get in /proc/mounts are file system specific and should be moved to l.data
  -- idea is you can round-trip this data
  -- a lot of the fs specific options are key=value so easier to recognise
  return setmetatable(mounts, mt.mounts)
end

local function if_nametoindex(name, s) -- internal version when already have socket for ioctl (although not used anywhere)
  local ifr = t.ifreq()
  local len = #name + 1
  if len > IFNAMSIZ then len = IFNAMSIZ end
  ffi.copy(ifr.ifr_ifrn.ifrn_name, name, len)
  local ret, err = S.ioctl(s, "SIOCGIFINDEX", ifr)
  if not ret then return nil, err end
  return ifr.ifr_ifru.ifru_ivalue
end

function util.if_nametoindex(name) -- standard function in some libc versions
  local s, err = S.socket(c.AF.LOCAL, c.SOCK.STREAM, 0)
  if not s then return nil, err end
  local i, err = if_nametoindex(name, s)
  if not i then return nil, err end
  local ok, err = S.close(s)
  if not ok then return nil, err end
  return i
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

-- note will give short reads, but mainly used for sysfs, proc
function util.readfile(name, buffer, length)
  local fd, err = S.open(name, "rdonly")
  if not fd then return nil, err end
  local r, err = S.read(fd, buffer, length or 4096)
  if not r then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return r
end

function util.writefile(name, str, mode) -- write string to named file; silently ignore short writes
  local fd, err
  if mode then fd, err = S.creat(name, mode) else fd, err = S.open(name, "wronly") end
  if not fd then return nil, err end
  local n, err = S.write(fd, str)
  if not n then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return true
end

-- termios
-- TODO note disadvantage of having in a different file is that cannot apply methods to a normal fd
-- hence open_pts. Need to work out how to make this extensible more effectively. Same issue for adding nonblock() still in syscall
function util.tcgetattr(fd)
  local tio = t.termios()
  local ok, err = S.ioctl(fd, "TCGETS", tio)
  if not ok then return nil, err end
  return tio
end

function util.isatty(fd)
  local tc = util.tcgetattr(fd)
  if tc then return true else return false end
end

local tcsets = {
  [0] = "TCSETS",  -- now
  [1] = "TCSETSW", -- drain
  [2] = "TCSETSF", -- flush. Note these are in fact consecutive ioctl numbers
}

function util.tcsetattr(fd, optional_actions, tio)
  local inc = c.TCSA[optional_actions]
  return S.ioctl(fd, tcsets[inc], tio)
end

function util.tcsendbreak(fd, duration)
  return S.ioctl(fd, "TCSBRK", pt.void(duration)) -- duration in seconds if not zero
end

function util.tcdrain(fd)
  return S.ioctl(fd, "TCSBRK", pt.void(1))
end

function util.tcflush(fd, queue_selector)
  return S.ioctl(fd, "TCFLSH", pt.void(c.TCFLUSH[queue_selector]))
end

function util.tcflow(fd, action)
  return S.ioctl(fd, "TCXONC", pt.void(c.TCFLOW[action]))
end

function util.tcgetsid(fd)
  local sid = t.int1()
  local ok, err = S.ioctl(fd, "TIOCGSID", sid)
  if not ok then return nil, err end
  return sid[0]
end

function util.posix_openpt(flags)
  local fd, err = S.open("/dev/ptmx", flags)
  if not fd then return nil, err end
  return setmetatable({fd = fd}, mt.openpt)
end

function util.grantpt(fd) -- I don't think we need to do anything here (eg Musl libc does not)
  return true
end

function util.unlockpt(fd)
  local unlock = t.int1()
  local ok, err = S.ioctl(fd, "TIOCSPTLCK", unlock)
  if not ok then return nil, err end
  return true
end

function util.ptsname(fd)
  local pts = t.int1()
  local ret, err = S.ioctl(fd, "TIOCGPTN", pts)
  if not ret then return nil, err end
  return "/dev/pts/" .. tostring(pts[0])
end

function util.open_pts(name, flags)
  local fd, err = S.open(name, flags)
  if not fd then return nil, err end
  return setmetatable({fd = fd}, mt.openpt)
end

local openptindex = {
  getfd = function(t) return t.fd:getfd() end,
  tcgetattr = util.tcgetattr,
  isatty = util.isatty,
  tcsetattr = util.tcsetattr,
  tcsendbreak = util.tcsendbreak,
  tcdrain = util.tcdrain,
  tcflush = util.tcflush,
  tcflow = util.tcflow,
  tcgetsid = util.tcgetsid,
  grantpt = util.grantpt,
  unlockpt = util.unlockpt,
  ptsname = util.ptsname,
}

mt.openpt = {
  __index = function(t, k)
    if openptindex[k] then return openptindex[k] end
    return function(pty, ...) return t.fd[k](t.fd, ...) end
  end
}

-- eventfd read and write helpers, as in glibc but Lua friendly. Note returns 0 for EAGAIN, as 0 never returned directly
-- returns Lua number - if you need all 64 bits, pass your own value in and use that for the exact result
function util.eventfd_read(fd, value)
  if not value then value = t.uint64_1() end
  local ret, err = S.read(fd, value, 8)
  if err and err.AGAIN then
    value[0] = 0
    return 0
  end
  if not ret then return nil, err end
  return tonumber(value[0])
end
function util.eventfd_write(fd, value)
  if not value then value = 1 end
  if type(value) == "number" then value = t.uint64_1(value) end
  local ret, err = S.write(fd, value, 8)
  if not ret then return nil, err end
  return true
end

function util.signalfd_read(fd, ss)
  ss = istype(t.siginfos, ss) or t.siginfos(ss or 8)
  local ret, err = S.read(fd, ss.sfd, ss.bytes)
  if ret == 0 or (err and err.AGAIN) then return {} end
  if not ret then return nil, err end
  ss.count = ret / s.signalfd_siginfo -- may not be full length
  return ss
end

function util.timerfd_read(fd, buffer)
  if not buffer then buffer = t.uint64_1() end
  local ret, err = S.read(fd, buffer, 8)
  if not ret and err.AGAIN then return 0 end -- will never actually return 0
  if not ret then return nil, err end
  return tonumber(buffer[0])
end

local auditarch_le = {
  x86 = "I386",
  x64 = "X86_64",
  arm = "ARM",
  mips = "MIPSEL",
}

local auditarch_be = {
  ppc = "PPC",
  arm = "ARMEB",
  mips = "MIPS",
}

function util.auditarch()
  if abi.le then return c.AUDIT_ARCH[auditarch_le[abi.arch]] else return c.AUDIT_ARCH[auditarch_be[abi.arch]] end
end

-- file system capabilities
local seccap = "security.capability"

function util.capget(f)
  local attr, err
  if type(f) == "string" then attr, err = S.getxattr(f, seccap) else attr, err = f:getxattr(seccap) end
  if not attr then return nil, err end
  local vfs = pt.vfs_cap_data(attr)
  local magic_etc = h.convle32(vfs.magic_etc)
  local version = bit.band(c.VFS_CAP.REVISION_MASK, magic_etc)
  -- TODO if you need support for version 1 filesystem caps add here, fairly simple
  assert(version == c.VFS_CAP.REVISION_2, "FIXME: Currently only support version 2 filesystem capabilities")
  local cap = t.capabilities()
  cap.permitted.cap[0], cap.permitted.cap[1] = h.convle32(vfs.data[0].permitted), h.convle32(vfs.data[1].permitted)
  cap.inheritable.cap[0], cap.inheritable.cap[1] = h.convle32(vfs.data[0].inheritable), h.convle32(vfs.data[1].inheritable)
  if bit.band(magic_etc, c.VFS_CAP_FLAGS.EFFECTIVE) ~= 0 then
    cap.effective.cap[0] = bit.bor(cap.permitted.cap[0], cap.inheritable.cap[0])
    cap.effective.cap[1] = bit.bor(cap.permitted.cap[1], cap.inheritable.cap[1])
  end
  return cap
end

function util.capset(f, cap, flags)
  cap = istype(t.capabilities, cap) or t.capabilities(cap)
  local vfsflags = 0
  -- is this the correct way to do this? TODO check
  for k, _ in pairs(c.CAP) do if cap.effective[k] then vfsflags = c.VFS_CAP_FLAGS.EFFECTIVE end end
  local vfs = t.vfs_cap_data()
  vfs.magic_etc = h.convle32(c.VFS_CAP.REVISION_2 + vfsflags)
  vfs.data[0].permitted, vfs.data[1].permitted = h.convle32(cap.permitted.cap[0]), h.convle32(cap.permitted.cap[1])
  vfs.data[0].inheritable, vfs.data[1].inheritable = h.convle32(cap.inheritable.cap[0]), h.convle32(cap.inheritable.cap[1])
  if type(f) == "string" then return S.setxattr(f, seccap, vfs, flags) else return f:getxattr(seccap, vfs, flags) end
end

return util


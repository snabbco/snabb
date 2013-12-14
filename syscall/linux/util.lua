-- misc utils

-- aim is to move a lot of stuff that is not strictly syscalls out of main code to modularise better
-- most code here is man(1) or man(3) or misc helpers for common tasks.

-- TODO rework so that items can be methods on fd again, for eventfd, timerfd, signalfd and tty

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(S)

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local h = require "syscall.helpers"

local ffi = require "ffi"

local bit = require "syscall.bit"

local octal = h.octal

-- TODO move to helpers? see notes in syscall.lua about reworking though
local function istype(tp, x)
  if ffi.istype(tp, x) then return x end
  return false
end

local util = {}

local mt = {}

local function if_nametoindex(name, s)
  local ifr = t.ifreq{name = name}
  local ret, err = S.ioctl(s, "SIOCGIFINDEX", ifr)
  if not ret then return nil, err end
  return ifr.ivalue
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

-- bridge functions.
local function bridge_ioctl(io, name)
  local s, err = S.socket(c.AF.LOCAL, c.SOCK.STREAM, 0)
  if not s then return nil, err end
  local ret, err = S.ioctl(s, io, name)
  if not ret then
    s:close()
    return nil, err
  end
  local ok, err = s:close()
  if not ok then return nil, err end
  return ret
end

function util.bridge_add(name) return bridge_ioctl("SIOCBRADDBR", name) end
function util.bridge_del(name) return bridge_ioctl("SIOCBRDELBR", name) end

local function bridge_if_ioctl(io, name, dev)
  local err, s, ifr, len, ret, ok
  s, err = S.socket(c.AF.LOCAL, c.SOCK.STREAM, 0)
  if not s then return nil, err end
  if type(dev) == "string" then
    dev, err = if_nametoindex(dev, s)
    if not dev then return nil, err end
  end
  ifr = t.ifreq{name = name, ivalue = dev}
  ret, err = S.ioctl(s, io, ifr);
  if not ret then
    s:close()
    return nil, err
  end
  ok, err = s:close()
  if not ok then return nil, err end
  return ret
end

function util.bridge_add_interface(bridge, dev) return bridge_if_ioctl(c.SIOC.BRADDIF, bridge, dev) end
function util.bridge_add_interface(bridge, dev) return bridge_if_ioctl(c.SIOC.BRDELIF, bridge, dev) end

local function brinfo(d) -- can be used as subpart of general interface info
  local bd = "/sys/class/net/" .. d .. "/" .. c.SYSFS_BRIDGE_ATTR
  if not S.stat(bd) then return nil end
  local bridge = {}
  for fn, f in util.ls(bd) do
    local s = util.readfile(bd .. "/" .. fn)
    if s then
      s = s:sub(1, #s - 1) -- remove newline at end
      if fn == "group_addr" or fn == "root_id" or fn == "bridge_id" then -- string values
        bridge[fn] = s
      elseif f == "stp_state" then -- bool
        bridge[fn] = s == 1
      elseif fn ~= "." and fn ~=".." then
        bridge[fn] = tonumber(s) -- not quite correct, most are timevals TODO
      end
    end
  end

  local brif, err = util.dirtable("/sys/class/net/" .. d .. "/" .. c.SYSFS_BRIDGE_PORT_SUBDIR, true)
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

    for i = 1, bit.rshift(n, 4) do -- fdb_entry is 16 bytes
      local fdb = fdbs[i - 1]
      local mac = t.macaddr()
      ffi.copy(mac, fdb.mac_addr, s.macaddr)

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
  local b = {}
  for d in util.ls("/sys/class/net") do
    if d ~= "." and d ~= ".." then b[d] = brinfo(d) end
  end
  return b
end

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

-- will work on netbsd with Linux compat, but should use getvfsstat()
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

-- table based mount, more cross OS compatible
function util.mount(tab)
  local source = tab.source or "none" -- standard default
  local target = tab.target or tab.dir -- netbsd compatible
  local filesystemtype = tab.type
  local mountflags = tab.flags
  local data = tab.data
  return S.mount(source, target, filesystemtype, mountflags, data)
end

function util.sendcred(fd, pid, uid, gid)
  if not pid then pid = S.getpid() end
  if not uid then uid = S.getuid() end
  if not gid then gid = S.getgid() end
  local ucred = t.ucred{pid = pid, uid = uid, gid = gid}
  local buf1 = t.buffer(1) -- need to send one byte
  local io = t.iovecs{{buf1, 1}}
  local cmsg = t.cmsghdr("socket", "credentials", ucred)
  local msg = t.msghdr{iov = io, control = cmsg}
  return S.sendmsg(fd, msg, 0)
end

return util

end

return {init = init}


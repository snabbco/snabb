-- misc utils

-- aim is to move a lot of stuff that is not strictly syscalls out of main code to modularise better

local ffi = require "ffi"
local S = require "syscall"

local util = {}

local t, pt, s, c = S.t, S.pt, S.s, S.c

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
  local ds = util.dirfile(name, nodots)
  local l = {}
  for k, _ in pairs(ds) do l[#l + 1] = k end
  return setmetatable(l, mt.ls)
end

-- recursive rm
local function rmhelper(file, prefix)
  local name
  if prefix then name = prefix .. "/" .. file else name = file end
  local st, err = S.stat(name)
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
      local p = S.proc(tonumber(ls[i]))
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
    local s = S.readfile(bd .. "/" .. f)
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

    for i = 1, n / s.fdb_entry do
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

return util


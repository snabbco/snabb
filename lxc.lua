-- Work in progress - not complete or tested yet

-- script to run init.lua in a container for testing

-- creates a container and runs init in it, innit.

-- pushes an interface into the container, but only with local routing, not bridged or mac-vlan'd for now

-- run as root

local oldassert = assert
local function assert(c, s)
  return oldassert(c, tostring(s))
end

local S = require "syscall"
local nl = require "syscall.nl"
local util = require "syscall.util"

local root = arg[1] or "root"

local init = util.mapfile("init.lua")
local luajit = util.mapfile("luajit/luajit")
local libc = util.mapfile("luajit/libc.so")
local libgcc = util.mapfile("luajit/libgcc_s.so")

if S.stat(root) then
  assert(util.rm(root))
end
assert(S.mkdir(root, "rwxu"))

assert(S.mkdir(root .. "/dev", "rwxu"))
assert(S.mkdir(root .. "/dev/pts", "rwxu"))
assert(S.mkdir(root .. "/sbin", "rwxu"))
assert(S.mkdir(root .. "/proc", "rwxu"))
assert(S.mkdir(root .. "/bin", "rwxu"))
assert(S.mkdir(root .. "/root", "rwxu"))
assert(S.mkdir(root .. "/tmp", "rwxu"))
assert(S.mkdir(root .. "/etc", "rwxu"))
assert(S.mkdir(root .. "/sys", "rwxu"))
assert(S.mkdir(root .. "/lib", "rwxu"))
assert(S.mkdir(root .. "/lib/syscall", "rwxu"))
assert(S.mkdir(root .. "/lib/syscall/x64", "rwxu"))

-- should just read rockspec!
assert(util.cp("init.lua", root .. "/sbin/init", "rwxu"))
assert(util.cp("luajit/luajit", root .. "/bin/luajit", "rwxu"))
assert(util.cp("luajit/libc.so", root .. "/lib/libc.so", "rwxu"))
assert(util.cp("luajit/libgcc_s.so", root .. "/lib/libgcc_s.so", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall.lua", root .. "/lib/syscall.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/headers.lua", root .. "/lib/syscall/headers.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/types.lua", root .. "/lib/syscall/types.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/constants.lua", root .. "/lib/syscall/constants.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/helpers.lua", root .. "/lib/syscall/helpers.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/ioctl.lua", root .. "/lib/syscall/ioctl.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/nl.lua", root .. "/lib/syscall/nl.lua", "rwxu"))
assert(util.cp("/usr/local/share/lua/5.1/syscall/x64/constants.lua", root .. "/lib/syscall/x64/constants.lua", "rwxu"))

assert(S.symlink("/lib/libc.so", root .. "/lib/ld-musl-x86_64.so.1"))

assert(S.chdir(root))

-- should use random names. Also should gc the veth to cleanup. For now just delete it on entry as this is a demo.
nl.dellink(0, "ifname", "veth0")
assert(nl.create_interface{name = "veth0", type = "veth", peer = {name = "veth1"}})
local i = nl.interfaces()
assert(i.veth0:up())
assert(i.veth0:address("10.3.0.1/24"))

local p = assert(S.clone("newnet,newipc,newns,newpid,newuts"))

if p ~=0 then -- parent
  local i = nl.interfaces()
  assert(i.veth1:move_ns(p))

  assert(S.waitpid(-1, "clone"))
else -- child

  -- wait for interface to appear
  local sock = assert(nl.socket("route", {groups = "link"}))
  local i = nl.interfaces()
  if not i.veth1 then
    local m = assert(nl.read(sock))
    assert(m.veth1)
  end
  sock:close()
  i:refresh()
  -- rename it to eth0
  i.veth1:rename("eth0")

  -- set up file system
  -- use chroot for now, change to pivot_root later
  assert(S.chroot("."))

--[[
-- something like this for pivot_root
      fork_assert(S.mount(tmpfile3, tmpfile3, "none", "bind")) -- to make sure on different mount point
      fork_assert(S.mount(tmpfile3, tmpfile3, nil, "private"))
      fork_assert(S.chdir(tmpfile3))
      fork_assert(S.mkdir("old"))
      fork_assert(S.pivot_root(".", "old"))
      fork_assert(S.chdir("/"))
]]

  local chardevices = {
    null = {1, 3},
    zero = {1, 5},
    random = {1, 8},
    urandom = {1, 9},
  }

  for k, v in pairs(chardevices) do 
    assert(S.mknod("/dev/" .. k, "fchr,rusr,wusr", S.t.device(v[1], v[2])))
  end

  -- call init
  assert(S.execve("/sbin/init", {"init"}, {}))
  S.exit("failure")
end

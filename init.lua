#!/bin/luajit

-- basic init process
-- note we do not catch all errors as we cannot do much about them

-- note that stdin, stderr should be attached to /dev/console

package.path = "/lib/?.lua;?"

local S = require "syscall"
local nl = require "syscall.nl"

local function fatal(s)
  print(s)
  os.exit()
end

function try(f, ...)
  local ok, err = f(...) -- could use pcall
  if ok then return ok end
  print("init: error at line " .. debug.getinfo(2, "l").currentline .. ": " .. tostring(err))
end

if not S then fatal("cannot find syscall library") end

-- mounts

try(S.mount, "sysfs", "/sys", "sysfs", "rw,nosuid,nodev,noexec,relatime")
try(S.mount, "proc", "/proc", "proc", "rw,nosuid,nodev,noexec,relatime")
try(S.mount, "devpts", "/dev/pts", "devpts", "rw,nosuid,noexec,relatime")

-- interfaces

local i = nl.interfaces()
local lo, eth0 = i.lo, i.eth0

lo:up()

eth0:up()

eth0:address("10.3.0.2/24")

-- hostname

S.sethostname("lua")

-- print something
local i = nl.interfaces()
print(i)

-- run processes


-- reap zombies

while true do
  local w, err = S.waitpid(-1, "all")
  if not w and err.ECHILD then break end -- no more children
end

-- childless

print("last child exited")

S.pause() -- for testing, normally exit



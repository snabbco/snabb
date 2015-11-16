#!/usr/bin/env luajit
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

--LISP controller mock-up program for testing.

local function assert(v, ...)
   if v then return v, ... end
   error(tostring((...)), 2)
end

local ffi = require("ffi")
local S   = require("syscall")

local CONTROL_SOCK = "/var/tmp/ctrl.socket"

S.signal('pipe', 'ign') --I 💔 Linux

::retry::
sock = sock or assert(S.socket("unix", "stream, nonblock"))
local sa = S.t.sockaddr_un(CONTROL_SOCK)
local ok, err = sock:connect(sa)
if not ok then
   if err.CONNREFUSED or err.AGAIN then
      S.sleep(1)
      print'retrying...'
      goto retry
   end
   assert(nil, err)
end
print'connected'

while true do
   if assert(S.select({writefds = {sock}}, 0)).count == 1 then

      local f = assert(io.open'lisp.fib')
      local data = assert(f:read'*a')
      f:close()

      print'sending...'
      if not S.write(sock, data, #data) then
         print'write error'
         sock:close()
         sock = nil
         goto retry
      end
   end
   S.sleep(1)
end

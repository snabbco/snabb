#!/usr/bin/env luajit

--LISP controller mock-up program for testing.

local ffi = require("ffi")
local S   = require("syscall")

CONTROL_SOCK = "/var/tmp/ctrl.socket"
CONTROL_DATA = [[
[17185] 00:00:00:00:aa:01 fd80:2::2
[17185] 00:00:00:00:aa:02 fd80:1::2
]]

local sock = assert(S.socket("unix", "stream, nonblock"))
local sa = S.t.sockaddr_un(CONTROL_SOCK)

::retry::
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

while assert(S.select({writefds = {sock}}, 0)).count == 1 do
	print'sending...'
	assert(S.write(sock, CONTROL_DATA, #CONTROL_DATA))
	S.sleep(1)
end


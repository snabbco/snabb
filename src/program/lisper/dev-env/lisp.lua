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

local CONTROL_SOCK = "/var/tmp/lisp-ipc-map-cache"
local PUNT_SOCK    = "/var/tmp/lispers.net-itr"

S.signal('pipe', 'ign') --I 💔 Linux

::retry::
sock = sock or assert(S.socket("unix", "dgram, nonblock"))
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
		local s = f:read'*a'
		f:close()
		local t = {}
		for s in s:gmatch'(.-)[\r?\n][\r?\n]' do
			table.insert(t, s)
		end

		print'sending...'
		for i,s in ipairs(t) do
			if not S.write(sock, s, #s) then
				print'write error'
				sock:close()
				sock = nil
				goto retry
			end
		end
	end
	S.sleep(1)
end

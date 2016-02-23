-- detect freebsd version

local abi = require "syscall.abi"

-- if not on FreeBSD just return most recent
if abi.os ~= "freebsd" then return {version = 10} end

local ffi = require "ffi"

require "syscall.ffitypes"

ffi.cdef [[
int sysctl(const int *name, unsigned int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
]]

local sc = ffi.new("int[2]", 1, 24) -- kern.osreldate
local osrevision = ffi.new("int[1]")
local lenp = ffi.new("unsigned long[1]", ffi.sizeof("int"))
local res = ffi.C.sysctl(sc, 2, osrevision, lenp, nil, 0)
if res == -1 then error("cannot identify FreeBSD version") end

local version = math.floor(osrevision[0] / 100000) -- major version ie 9, 10

return {version = version}


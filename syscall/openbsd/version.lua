-- detect openbsd version

local abi = require "syscall.abi"

-- if not on OpenBSD just return most recent
if abi.os ~= "openbsd" then return {version = 201405} end

local ffi = require "ffi"

require "syscall.ffitypes"

ffi.cdef [[
int sysctl(const int *name, unsigned int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
]]

-- TODO we could probably support some earlier versions easily

-- 201211 = 5.2
-- 201305 = 5.3
-- 201311 = 5.4
-- 201405 = 5.5

local sc = ffi.new("int[2]", 1, 3) -- kern.osrev
local osrevision = ffi.new("int[1]")
local lenp = ffi.new("unsigned long[1]", ffi.sizeof("int"))
local ok, res = ffi.C.sysctl(sc, 2, osrevision, lenp, nil, 0)
if not ok or res == -1 then error "cannot determinate openbsd version" end

local version = osrevision[0]

-- 5.4 to 5.5 is the main recent large ABI change, but older ones so far untested...
if version < 201311 then version = 201311 end
if version < 201311 or version > 201405 then error "unsupported openbsd version" end

return {version = version}


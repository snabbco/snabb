-- detect netbsd version

local abi = require "syscall.abi"

local ffi = require "ffi"

require "syscall.ffitypes"

local version, major, minor

-- NetBSD ABI version
-- TODO if running rump on NetBSD the version detection is a bit flaky if the host and rump differ
-- normally this is ok if you init netbsd first and have compat installed for rump, or do not use both...
ffi.cdef[[
int sysctl(const int *, unsigned int, void *, size_t *, const void *, size_t);
int __sysctl(const int *, unsigned int, void *, size_t *, const void *, size_t);
int rump_getversion(void);
]]
local sc = ffi.new("int[2]", 1, 3) -- kern.osrev
local osrevision = ffi.new("int[1]")
local lenp = ffi.new("unsigned long[1]", ffi.sizeof("int"))
local ok, res
if abi.host == "netbsd" then
  ok, res = pcall(ffi.C.sysctl, sc, 2, osrevision, lenp, nil, 0)
end
if not ok or res == -1 then ok, res = pcall(ffi.C.rump_getversion) end
if not ok or res == -1 then 
  version = 7
else
  local major = math.floor(osrevision[0] / 100000000)
  local minor = math.floor(osrevision[0] / 1000000) - major * 100
  version = major
  if minor == 99 then version = version + 1 end
end

return {version = version, major = major, minor = minor}


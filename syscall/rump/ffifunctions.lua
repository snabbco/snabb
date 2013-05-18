-- rump kernel ffi functions

local abi = require "syscall.abi"

local ffi = require "ffi"
local cdef

if ffi.os == "netbsd" then
  require "syscall.ffitypes" -- with rump on NetBSD the types are the same
  cdef = function(s)
    s = string.gsub(s, "_netbsd_", "") -- no netbsd types
    ffi.cdef(s)
  end
else
-- TODO this will be in rump.ffitypes or may call modified version of real thing
ffi.cdef[[
typedef uint32_t _netbsd_mode_t;
typedef unsigned int _netbsd_size_t;
typedef int _netbsd_ssize_t;
]]
  cdef = ffi.cdef -- use as provided
end

cdef [[
int rump___sysimpl_mkdir(const char *pathname, _netbsd_mode_t mode);
int rump___sysimpl_mount50(const char *type, const char *dir, int flags, void *data, _netbsd_size_t data_len);
int rump___sysimpl_open(const char *pathname, int flags, _netbsd_mode_t mode);
_netbsd_ssize_t rump___sysimpl_read(int fd, void *buf, _netbsd_size_t count);
int rump___sysimpl_close(int fd);
int rump___sysimpl_reboot(int howto, char *bootstr);
]]


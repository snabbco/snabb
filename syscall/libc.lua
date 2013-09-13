-- things that are libc only, not syscalls
-- this file will not be included if not running with libc eg for rump

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(S)

local c = S.c
local types = S.types
local t, s, pt = types.t, types.s, types.pt

local ffi = require "ffi"

local h = require "syscall.helpers"

local zeropointer = pt.void(0)

local function retbool(ret)
  if ret == -1 then return nil, t.error() end
  return true
end

-- if getcwd not defined, fall back to libc implementation (currently osx) TODO use underlying syscall
if not S.getcwd then
ffi.cdef [[
char *getcwd(char *buf, size_t size);
]]
  function S.getcwd(buf, size)
    size = size or c.PATH_MAX
    buf = buf or t.buffer(size)
    local ret = ffi.C.getcwd(buf, size)
    if ret == zeropointer then return nil, t.error() end
    return ffi.string(buf)
  end
end

-- in NetBSD, OSX exit defined in libc
if not S.exit then
ffi.cdef[[
void exit(int status);
]]
  function S.exit(status) ffi.C.exit(c.EXIT[status]) end
end

--[[ -- need more types defined
int uname(struct utsname *buf);
time_t time(time_t *t);
]]

--[[
int gethostname(char *name, size_t namelen);
int sethostname(const char *name, size_t len);
int getdomainname(char *name, size_t namelen);
int setdomainname(const char *name, size_t len);
--]]

-- environment
ffi.cdef [[
// environment
extern char **environ;

int setenv(const char *name, const char *value, int overwrite);
int unsetenv(const char *name);
int clearenv(void);
char *getenv(const char *name);
]]

function S.environ() -- return whole environment as table
  local environ = ffi.C.environ
  if not environ then return nil end
  local r = {}
  local i = 0
  while environ[i] ~= zeropointer do
    local e = ffi.string(environ[i])
    local eq = e:find('=')
    if eq then
      r[e:sub(1, eq - 1)] = e:sub(eq + 1)
    end
    i = i + 1
  end
  return r
end

function S.getenv(name)
  return S.environ()[name]
end
function S.unsetenv(name) return retbool(ffi.C.unsetenv(name)) end
function S.setenv(name, value, overwrite)
  overwrite = h.booltoc(overwrite) -- allows nil as false/0
  return retbool(ffi.C.setenv(name, value, overwrite))
end
function S.clearenv() return retbool(ffi.C.clearenv()) end

return S

end

return {init = init}


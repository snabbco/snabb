-- NetBSD fcntl

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

local function init(types)

local c = require "syscall.netbsd.constants"

local ffi = require "ffi"

local t, pt, s = types.t, types.pt, types.s

local h = require "syscall.helpers"

local ctobool, booltoc = h.ctobool, h.booltoc

-- TODO this should just be __new
local function getflock(arg)
  arg = arg or t.flock()
  if not ffi.istype(t.flock, arg) then
    for _, v in pairs {"type", "whence", "start", "len", "pid"} do -- allow use of short names
      if arg[v] then
        arg["l_" .. v] = arg[v] -- TODO cleanup this to use table?
        arg[v] = nil
      end
    end
    arg.l_type = c.FCNTL_LOCK[arg.l_type]
    arg.l_whence = c.SEEK[arg.l_whence]
    arg = t.flock(arg)
  end
  return arg
end

local fcntl = {
  commands = {
    [c.F.SETFL] = function(arg) return c.O[arg] end,
    [c.F.SETFD] = function(arg) return c.FD[arg] end,
    [c.F.GETLK] = getflock,
    [c.F.SETLK] = getflock,
    [c.F.SETLKW] = getflock,
    [c.F.SETNOSIGPIPE] = function(arg) return booltoc(arg) end,
  },
  ret = {
    [c.F.DUPFD] = function(ret) return t.fd(ret) end,
    [c.F.DUPFD_CLOEXEC] = function(ret) return t.fd(ret) end,
    [c.F.GETFD] = function(ret) return tonumber(ret) end,
    [c.F.GETFL] = function(ret) return tonumber(ret) end,
    [c.F.GETOWN] = function(ret) return tonumber(ret) end,
    [c.F.GETLK] = function(ret, arg) return arg end,
    [c.F.MAXFD] = function(ret) return tonumber(ret) end,
    [c.F.GETNOSIGPIPE] = function(ret) return ctobool(ret) end,
  }
}

return fcntl

end

return {init = init}


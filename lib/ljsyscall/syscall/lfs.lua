-- this is intended to be compatible with luafilesystem https://github.com/keplerproject/luafilesystem

-- currently does not implement locks

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string

-- TODO allow use eg with rump kernel, needs an initialisation option
-- maybe return a table with a metatable that allows init or uses default if no init?
local S = require "syscall"

-- TODO not implemented
-- lfs.lock_dir
-- lfs.lock
-- unlock

local function lfswrap(f)
  return function(...)
    local ret, err = f(...)
    if not ret then return nil, tostring(err) end
    return ret
  end
end

local lfs = {}

lfs._VERSION = "ljsyscall lfs 1"

local attributes = {
  dev = "dev",
  ino = "ino",
  mode = "typename", -- not sure why lfs insists on calling this mode
  nlink = "nlink",
  uid = "uid",
  gid = "gid",
  rdev = "rdev",
  access = "access",
  modification = "modification",
  change = "change",
  size = "size",
  blocks = "blocks",
  blksize = "blksize",
}

local function attr(st, aname)
  if aname then
    aname = attributes[aname]
    return st[aname]
  end
  local ret = {}
  for k, v in pairs(attributes) do ret[k] = st[v] end
  return ret
end

function lfs.attributes(filepath, aname)
  local st, err = S.stat(filepath)
  if not st then return nil, tostring(err) end
  return attr(st, aname)
end
function lfs.symlinkattributes(filepath, aname)
  local st, err = S.lstat(filepath)
  if not st then return nil, tostring(err) end
  return attr(st, aname)
end

lfs.chdir = lfswrap(S.chdir)
lfs.currentdir = lfswrap(S.getcwd)
lfs.rmdir = lfswrap(S.rmdir)
lfs.touch = lfswrap(S.utime)

function lfs.mkdir(path)
  local ret, err = S.mkdir(path, "0777")
  if not ret then return nil, tostring(err) end
  return ret
end

local function dir_close(dir)
  dir.fd:close()
  dir.fd = nil
end

local function dir_next(dir)
  if not dir.fd then error "dir ended" end
  local d
  repeat
    if not dir.di then
      local err
      dir.di, err = dir.fd:getdents(dir.buf, dir.size)
      if not dir.di then
        dir_close(dir)
        error(tostring(err)) -- not sure how we are suppose to handle errors
      end
      dir.first = true
    end
    d = dir.di()
    if not d then
      dir.di = nil
      if dir.first then
        dir_close(dir)
        return nil
      end
    end
    dir.first = false
  until d
  return d.name
end

function lfs.dir(path)
  local size = 4096
  local buf = S.t.buffer(size)
  local fd, err = S.open(path, "directory, rdonly")
  if err then return nil, tostring(err) end
  return dir_next, {size = size, buf = buf, fd = fd, next = dir_next, close = dir_close}
end

local flink, fsymlink = lfswrap(S.link), lfswrap(S.symlink)

function lfs.link(old, new, symlink)
  if symlink then
    return fsymlink(old, new)
  else
    return flink(old, new)
  end
end

function lfs.setmode(file, mode) return true, "binary" end

return lfs


-- generic utils not specific to any OS

-- these are generally equivalent to things that are in man(1) or man(3)
-- these can be made more modular as number increases

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math, bit

local function init(S)

local ffi = require "ffi"

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local mt, meth = {}, {}

local util = require("syscall." .. abi.os .. ".util").init(S)

mt.dir = {
  __tostring = function(t)
    if #t == 0 then return "" end
    table.sort(t)
    return table.concat(t, "\n") .. "\n"
    end
}

function util.dirtable(name, nodots) -- return table of directory entries, remove . and .. if nodots true
  local d = {}
  local size = 4096
  local buf = t.buffer(size)
  for f in util.ls(name, buf, size) do
    if not (nodots and (f == "." or f == "..")) then d[#d + 1] = f end
  end
  return setmetatable(d, mt.dir)
end

-- this returns an iterator over multiple calls to getdents TODO add nodots?
-- note how errors work, getdents will throw as called multiple times, but normally should not fail if open succeeds
-- getdents can fail eg on nfs though.
function util.ls(name, buf, size)
  size = size or 4096
  buf = buf or t.buffer(size)
  if not name then name = "." end
  local fd, err = S.open(name, "directory, rdonly")
  if err then return nil, err end
  local di
  return function()
    local d, first
    repeat
      if not di then
        local err
        di, err = fd:getdents(buf, size)
        if not di then
          fd:close()
          error(err)
        end
        first = true
      end
      d = di()
      if not d then di = nil end
      if not d and first then return nil end
    until d
    return d.name, d
  end
end

function util.touch(file)
  local fd, err = S.open(file, "wronly,creat,noctty,nonblock", "0666")
  if not fd then return nil, err end
  local fd2, err = S.dup(fd)
  if not fd2 then
    fd2:close()
    return nil, err
  end
  fd:close()
  local ok, err = S.futimes(fd2)
  fd2:close()
  if not ok then return nil, err end
  return true
end

function util.createfile(file) -- touch without timestamp adjustment
  local fd, err = S.open(file, "wronly,creat,noctty,nonblock", "0666")
  if not fd then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return true
end

function util.mapfile(name) -- generally better to use, but no good for sysfs etc
  local fd, err = S.open(name, "rdonly")
  if not fd then return nil, err end
  local st, err = S.fstat(fd)
  if not st then return nil, err end
  local size = st.size
  local m, err = S.mmap(nil, size, "read", "shared", fd, 0)
  if not m then return nil, err end
  local str = ffi.string(m, size)
  local ok, err = S.munmap(m, size)
  if not ok then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return str
end

-- TODO fix short reads, but mainly used for sysfs, proc
function util.readfile(name, buffer, length)
  local fd, err = S.open(name, "rdonly")
  if not fd then return nil, err end
  local r, err = S.read(fd, buffer, length or 4096)
  if not r then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return r
end

-- write string to named file; silently ignore short writes TODO fix
function util.writefile(name, str, mode, flags)
  local fd, err
  if mode then fd, err = S.creat(name, mode) else fd, err = S.open(name, flags or "wronly") end
  if not fd then return nil, err end
  local n, err = S.write(fd, str)
  if not n then return nil, err end
  local ok, err = fd:close()
  if not ok then return nil, err end
  return true
end

return util

end

return {init = init}


-- generic utils not specific to any OS

-- these are generally equivalent to things that are in man(1) or man(3)
-- these can be made more modular as number increases

local function init(S)

local abi, types, c = S.abi, S.types, S.c
local t, pt, s = types.t, types.pt, types.s

local mt, meth = {}, {}

local util = {}

if abi.os == "linux" then util = require "syscall.linux.util".init(S) end -- no other OSs have specific util code yet

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
  local ok, err = S.futimens(fd2, "now")
  fd2:close()
  if not ok then return nil, err end
  return true
end

return util

end

return {init = init}


-- misc utils

-- aim is to move a lot of stuff that is not strictly syscalls out of main code to modularise better

local ffi = require "ffi"
local S = require "syscall"

local util = {}

local t, pt, s, c = S.t, S.pt, S.s, S.c

-- recursive rm
local function rmhelper(file, prefix)
  local name
  if prefix then name = prefix .. "/" .. file else name = file end
  local st, err = S.stat(name)
  if not st then return nil, err end
  if st.isdir then
    local files, err = S.dirfile(name, true)
    if not files then return nil, err end
    for f, _ in pairs(files) do
      local ok, err = rmhelper(f, name)
      if not ok then return nil, err end
    end
    local ok, err = S.rmdir(name)
    if not ok then return nil, err end
  else
    local ok, err = S.unlink(name)
    if not ok then return nil, err end
  end
  return true
end

function util.rm(...)
  for _, f in ipairs{...} do
    local ok, err = rmhelper(f)
    if not ok then return nil, err end
  end
  return true
end


return util


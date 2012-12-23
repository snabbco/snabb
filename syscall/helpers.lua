-- misc helper functions that we use across the board

local h = {}

function h.octal(s) return tonumber(s, 8) end 

function h.split(delimiter, text)
  if delimiter == "" then return {text} end
  if #text == 0 then return {} end
  local list = {}
  local pos = 1
  while true do
    local first, last = text:find(delimiter, pos)
    if first then
      list[#list + 1] = text:sub(pos, first - 1)
      pos = last + 1
    else
      list[#list + 1] = text:sub(pos)
      break
    end
  end
  return list
end

function h.trim(s) -- TODO should replace underscore with space
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local split, trim = h.split, h.trim

-- for single valued flags only
function h.flag(t, str)
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local val = rawget(t, str)
  if val then return val end
  local s = trim(str):upper()
  if #s == 0 then return 0 end
  local val = rawget(t, s)
  if not val then return nil end
  rawset(t, str, val) -- this memoizes for future use
  return val
end

h.stringflag = {__index = h.flag, __call = function(t, a) return t[a] end}

-- take a bunch of flags in a string and return a number
local function flags(t, str) -- allows multiple comma sep flags that are ORed TODO allow | as well
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local val = rawget(t, str)
  if val then return val end
  local f = 0
  local a = split(",", str)
  for i, v in ipairs(a) do
    local s = trim(v):upper()
    local val = rawget(t, s)
    if not val then return nil end
    f = bit.bor(f, val)
  end
  rawset(t, str, f)
  return f
end

h.multiflags = {__index = flags, __call = function(t, a) return t[a] end}

-- single char flags, eg used for access which allows "rwx"
local function chflags(t, s)
  if not s then return 0 end
  if type(s) ~= "string" then return s end
  s = trim(s:upper())
  local flag = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    flag = bit.bor(flag, rawget(t, c))
  end
  return flag
end

h.charflags = {__index = chflags, __call = function(t, a) return t[a] end}

return h


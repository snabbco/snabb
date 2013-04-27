-- misc helper functions that we use across the board

local ffi = require "ffi"

local h = {}

-- endian conversion
-- TODO add tests eg for signs.
if ffi.abi("be") then -- nothing to do
  function h.htonl(b) return b end
  function h.htons(b) return b end
  function h.convle32(b) return bit.bswap(b) end -- used by file system capabilities, always stored as le
else
  function h.htonl(b) return bit.bswap(b) end
  function h.htons(b) return bit.rshift(bit.bswap(b), 16) end
  function h.convle32(b) return b end -- used by file system capabilities, always stored as le
end
h.ntohl = h.htonl -- reverse is the same
h.ntohs = h.htons -- reverse is the same

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

-- the old version now used only in one place TODO remove
function h.flag(t, str)
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  if rawget(t, "__cache") then
    local val = t.__cache[str]
    if val then return val end
  end
  local s = trim(str):upper()
  if #s == 0 then return 0 end
  local val = rawget(t, s)
  if not val then return nil end
  if not t.__cache then t.__cache = {} end
  t.__cache[str] = val -- memoize for future use
  return val
end

-- for single valued flags
function h.strflag(tab)
  local function flag(cache, str)
    if not str then return 0 end
    if type(str) ~= "string" then return str end
    if #str == 0 then return 0 end
    local s = trim(str):upper()
    if #s == 0 then return 0 end
    local val = rawget(tab, s)
    if not val then return nil end
    cache[str] = val
    return val
  end
  return setmetatable(tab, {__index = setmetatable({}, {__index = flag}), __call = function(t, a) return t[a] end})
end

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

-- for swap flags, which can have number
local function swapflags(t, str) -- allows multiple comma sep flags that are ORed TODO allow | as well
  if not str then return 0 end
  if type(str) ~= "string" then return str end
  if #str == 0 then return 0 end
  local val = rawget(t, str)
  if val then return val end
  local f = 0
  local a = split(",", str)
  for i, v in ipairs(a) do
    local s = trim(v):upper()
    if tonumber(s) then
      local val = tonumber(s)
      f = bit.bor(f, rawget(t, "PREFER"), bit.lshift(bit.band(rawget(t, "PRIO_MASK"), val), rawget(t, "PRIO_SHIFT")))
    else
      local val = rawget(t, s)
      if not val then return nil end
      f = bit.bor(f, val)
    end
  end
  rawset(t, str, f)
  return f
end

h.swapflags = {__index = swapflags, __call = function(t, a) return t[a] end}

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

h.divmod = function(a, b)
  return math.floor(a / b), a % b
end

h.booltoc = setmetatable({
  [0] = 0,
  [1] = 1,
  [false] = 0,
  [true] = 1,
}, {__call = function(tb, arg) return tb[arg or 0] end}) -- allow nil as false

return h


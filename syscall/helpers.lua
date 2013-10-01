-- misc helper functions that we use across the board

local require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, print, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local abi = require "syscall.abi"

local ffi = require "ffi"

local bit = require "bit"

local h = {}

local voidp = ffi.typeof("void *")

local function ptvoid(x)
  return ffi.cast(voidp, x)
end

-- constants
h.uint64_max = ffi.cast("uint64_t", 0) - 1
h.uerr64 = h.uint64_max
h.err64 = ffi.cast("int64_t", -1)
if abi.abi64 then h.errpointer = ptvoid(h.err64) else h.errpointer = ptvoid(0xffffffff) end

-- endian conversion
-- TODO add tests eg for signs.
if abi.be then -- nothing to do
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
local octal = h.octal

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

-- for AT_FDCWD
function h.atflag(tab)
  local function flag(cache, str)
    if not str then return tab.FDCWD end
    if type(str) == "number" then return str end
    if type(str) ~= "string" then return str:getfd() end
    if #str == 0 then return 0 end
    local s = trim(str):upper()
    if #s == 0 then return 0 end
    local val = rawget(tab, s)
    if not val then error("invalid flag " .. s) end
    cache[str] = val
    return val
  end
  return setmetatable(tab, {__index = setmetatable({}, {__index = flag}), __call = function(t, a) return t[a] end})
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
-- allows multiple comma sep flags that are ORed
function h.multiflags(tab)
  local function flag(cache, str)
    if not str then return 0 end
    if type(str) ~= "string" then return str end
    if #str == 0 then return 0 end
    local f = 0
    local a = split(",", str)
    if #a == 1 and str == str:upper() then return nil end -- this is to allow testing for presense, while catching errors
    for i, v in ipairs(a) do
      local s = trim(v):upper()
      if #s == 0 then error("empty flag") end
      local val = rawget(tab, s)
      if not val then error("invalid flag " .. s) end
      f = bit.bor(f, val)
    end
    cache[str] = f
    return f
  end
  return setmetatable(tab, {
    __index = setmetatable({}, {__index = flag}),
    -- this allows easily adding a flag TODO some mechanism to remove eg using ~ would be nice here or elsewhere
    __call = function(t, ...)
      local a = 0
      for _, v in ipairs{...} do
        a = bit.bor(a, t[v])
      end
      return a
    end,
  })
end

-- like multiflags but also allow octal values in string
function h.modeflags(tab)
  local function flag(cache, str)
    if not str then return 0 end
    if type(str) ~= "string" then return str end
    if #str == 0 then return 0 end
    local f = 0
    local a = split(",", str)
    if #a == 1 and str == str:upper() and str:sub(1,1) ~= "0" then return nil end -- this is to allow testing for presense, while catching errors
    for i, v in ipairs(a) do
      local s = trim(v):upper()
      if #s == 0 then error("empty flag") end
      local val
      if s:sub(1, 1) == "0" then
        val = octal(s)
      else
        val = rawget(tab, s)
        if not val then error("invalid flag " .. s) end
      end
      f = bit.bor(f, val)
    end
    cache[str] = f
    return f
  end
  return setmetatable(tab, {__index = setmetatable({}, {__index = flag}), __call = function(t, a) return t[a] end})
end

function h.swapflags(tab)
  local function flag(cache, str)
    if not str then return 0 end
    if type(str) ~= "string" then return str end
    if #str == 0 then return 0 end
    local f = 0
    local a = split(",", str)
    if #a == 1 and str == str:upper() then return nil end -- this is to allow testing for presense, while catching errors
    for i, v in ipairs(a) do
      local s = trim(v):upper()
      if #s == 0 then error("empty flag") end
      if tonumber(s) then
        local val = tonumber(s)
        f = bit.bor(f, rawget(tab, "PREFER"), bit.lshift(bit.band(rawget(tab, "PRIO_MASK"), val), rawget(tab, "PRIO_SHIFT")))
      else
        local val = rawget(tab, s)
        if not val then error("invalid flag " .. s) end
        f = bit.bor(f, val)
      end
    end
    cache[str] = f
    return f
  end
  return setmetatable(tab, {__index = setmetatable({}, {__index = flag}), __call = function(t, a) return t[a] end})
end

-- single char flags, eg used for access which allows "rwx"
function h.charflags(tab)
  local function flag(cache, str)
    if not str then return 0 end
    if type(str) ~= "string" then return str end
    str = trim(str:upper())
    local flag = 0
    for i = 1, #str do
      local c = str:sub(i, i)
      local val = rawget(tab, c)
      if not val then error("invalid flag " .. c) end
      flag = bit.bor(flag, val)
    end
    cache[str] = flag
    return flag
  end
  return setmetatable(tab, {__index = setmetatable({}, {__index = flag}), __call = function(t, a) return t[a] end})
end

h.divmod = function(a, b)
  return math.floor(a / b), a % b
end

h.booltoc = setmetatable({
  [0] = 0,
  [1] = 1,
  [false] = 0,
  [true] = 1,
}, {__call = function(tb, arg) return tb[arg or 0] end}) -- allow nil as false

function h.ctobool(i) return tonumber(i) ~= 0 end

local function align(len, a) return bit.band(tonumber(len) + a - 1, bit.bnot(a - 1)) end
h.align = align

local buffer = ffi.typeof("char[?]")
-- Give an alignment and a list of values, returns a buffer to fit them, it's length, and what the offsets would be
function h.align_types(alignment, in_vals)
  local len = 0
  local offsets = { }
  for i, tp in ipairs(in_vals) do
    local item_alignment = align(ffi.sizeof(tp), alignment)
    offsets [ i ] = len
    len = len + item_alignment
  end
  return buffer(len), len, offsets
end

return h


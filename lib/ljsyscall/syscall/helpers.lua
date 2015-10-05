-- misc helper functions that we use across the board

local require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math = 
require, error, assert, tonumber, tostring,
setmetatable, pairs, ipairs, unpack, rawget, rawset,
pcall, type, table, string, math

local debug, collectgarbage = require "debug", collectgarbage

local abi = require "syscall.abi"

local ffi = require "ffi"
local bit = require "syscall.bit"

local h = {}

-- generic assert helper, mainly for tests
function h.assert(cond, err, ...)
  if not cond then
    error(tostring(err or "unspecified error")) -- annoyingly, assert does not call tostring!
  end
  collectgarbage("collect") -- force gc, to test for bugs
  if type(cond) == "function" then return cond, err, ... end
  if cond == true then return ... end
  return cond, ...
end

local voidp = ffi.typeof("void *")

local function ptvoid(x)
  return ffi.cast(voidp, x)
end

local function ptt(tp)
  local ptp = ffi.typeof(tp .. " *")
  return function(x) return ffi.cast(ptp, x) end
end
h.ptt = ptt

-- constants
h.uint64_max = ffi.cast("uint64_t", 0) - ffi.cast("uint64_t", 1)
h.err64 = ffi.cast("int64_t", -1)
if abi.abi64 then h.errpointer = ptvoid(h.err64) else h.errpointer = ptvoid(0xffffffff) end
h.uint32_max = ffi.cast("uint32_t", 0xffffffff)
h.int32_max = 0x7fffffff
if abi.abi64 then h.longmax = bit.rshift64(h.err64, 1) else h.longmax = h.int32_max end

-- generic iterator that counts down so needs no closure to hold state
function h.reviter(array, i)
  i = i - 1
  if i >= 0 then return i, array[i] end
end

function h.mktype(tp, x) if ffi.istype(tp, x) then return x else return tp(x) end end
function h.istype(tp, x) if ffi.istype(tp, x) then return x else return false end end

local function lenfn(tp) return ffi.sizeof(tp) end
h.lenfn = lenfn
h.lenmt = {__len = lenfn}

local tint = ffi.typeof("int")
local function getfd(fd)
  if type(fd) == "number" or ffi.istype(tint, fd) then return fd end
  return fd:getfd()
end
h.getfd = getfd

-- generic function for __new
function h.newfn(tp, tab)
  local obj = ffi.new(tp)
  if not tab then return obj end
  -- these are split out so __newindex is called, not just initialisers luajit understands
  for k, v in pairs(tab) do if type(k) == "string" then obj[k] = v end end -- set string indexes
  return obj
end

-- generic function for __tostring
local function simpleprint(pt, x)
  local out = {}
  for _, v in ipairs(pt) do out[#out + 1] = v .. " = " .. tostring(x[v]) end
  return "{ " .. table.concat(out, ", ") .. " }"
end

-- type initialisation helpers
function h.addtype(types, name, tp, mt)
  if abi.rumpfn then tp = abi.rumpfn(tp) end
  if mt then
    if mt.index and not mt.__index then -- generic index method
      local index = mt.index
      mt.index = nil
      mt.__index = function(tp, k) if index[k] then return index[k](tp) else error("invalid index " .. k) end end
    end
    if mt.newindex and not mt.__newindex then -- generic newindex method
      local newindex = mt.newindex
      mt.newindex = nil
      mt.__newindex = function(tp, k, v) if newindex[k] then newindex[k](tp, v) else error("invalid index " .. k) end end
    end
    if not mt.__len then mt.__len = lenfn end -- default length function is just sizeof
    if not mt.__tostring and mt.print then mt.__tostring = function(x) return simpleprint(mt.print, x) end end
    types.t[name] = ffi.metatype(tp, mt)
  else
    types.t[name] = ffi.typeof(tp)
  end
  types.ctypes[tp] = types.t[name]
  types.pt[name] = ptt(tp)
  types.s[name] = ffi.sizeof(types.t[name])
end

-- for variables length types, ie those with arrays
function h.addtype_var(types, name, tp, mt)
  if abi.rumpfn then tp = abi.rumpfn(tp) end
  if not mt.__len then mt.__len = lenfn end -- default length function is just sizeof, gives instance size for var lngth
  types.t[name] = ffi.metatype(tp, mt)
  types.pt[name] = ptt(tp)
end

function h.addtype_fn(types, name, tp)
  if abi.rumpfn then tp = abi.rumpfn(tp) end
  types.t[name] = ffi.typeof(tp)
  types.s[name] = ffi.sizeof(types.t[name])
end

function h.addraw2(types, name, tp)
  if abi.rumpfn then tp = abi.rumpfn(tp) end
  types.t[name] = ffi.typeof(tp .. "[2]")
end

function h.addtype1(types, name, tp)
  types.t[name] = ffi.typeof(tp .. "[1]")
  types.s[name] = ffi.sizeof(types.t[name])
end

function h.addtype2(types, name, tp)
  types.t[name] = ffi.typeof(tp .. "[2]")
  types.s[name] = ffi.sizeof(types.t[name])
end

function h.addptrtype(types, name, tp)
  local ptr = ffi.typeof(tp)
  types.t[name] = function(v) return ffi.cast(ptr, v) end
  types.s[name] = ffi.sizeof(ptr)
end

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
    if type(str) ~= "string" then return getfd(str) end
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
    for _, v in ipairs(a) do
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
    __call = function(tab, x, ...) -- this allows easily adding or removing a flag
      local a = tab[x]
      for _, v in ipairs{...} do
        if type(v) == "string" and v:find("~") then -- allow negation eg c.IFF(old, "~UP")
          local sa = split(",", v)
          for _, vv in ipairs(sa) do
            local s = trim(vv):upper()
            if #s == 0 then error("empty flag") end
            local negate = false
            if s:sub(1, 1) == "~" then
              negate = true
              s = trim(s:sub(2))
              if #s == 0 then error("empty flag") end
            end
            local val = rawget(tab, s)
            if not val then error("invalid flag " .. s) end
            if negate then a = bit.band(a, bit.bnot(val)) else a = bit.bor(a, val) end
          end
        else
          a = bit.bor(a, tab[v])
        end
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

return h


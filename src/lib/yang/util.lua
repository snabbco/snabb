-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local lib = require("core.lib")
local ffi = require("ffi")
local ipv4 = require("lib.protocol.ipv4")

ffi.cdef([[
unsigned long long strtoull (const char *nptr, const char **endptr, int base);
]])

function tointeger(str, what, min, max)
   if not what then what = 'integer' end
   local str = assert(str, 'missing value for '..what)
   local start = 1
   local is_negative
   local base = 10
   if str:match('^-') then start, is_negative = 2, true
   elseif str:match('^+') then start = 2 end
   if str:match('^0x', start) then base, start = 16, start + 2
   elseif str:match('^0', start) then base = 8 end
   str = str:lower()
   if start > str:len() then
      error('invalid numeric value for '..what..': '..str)
   end
   -- FIXME: check that res did not overflow the 64-bit number
   local res = ffi.C.strtoull(str:sub(start), nil, base)
   if is_negative then
      res = -1LL*ffi.cast("int64_t", res)
      if res > 0 then
         error('invalid numeric value for '..what..': '..str)
      end
      if min and not (min <= 0 and min <= res) then
         error('invalid numeric value for '..what..': '..str)
      end
   else
      -- Only compare min and res if both are positive, otherwise if min
      -- is a negative int64_t then the comparison will treat it as a
      -- large uint64_t.
      if min and not (min <= 0 or min <= res) then
         error('invalid numeric value for '..what..': '..str)
      end
   end
   if max and res > max then
      error('invalid numeric value for '..what..': '..str)
   end
   -- Only return Lua numbers for values within int32 + uint32 range.
   -- The 0 <= res check is needed because res might be a uint64, in
   -- which case comparing to a negative Lua number will cast that Lua
   -- number to a uint64 :-((
   if (0 <= res or -0x8000000 <= res) and res <= 0xffffffff then
      return tonumber(res)
   end
   return res
end

local array_mt = {}

function ffi_array(ptr, elt_t, count)
   local t = ffi.typeof(elt_t)
   local initial_size = count or ffi.sizeof(ptr)/ffi.sizeof(t)
   local self = {
      t = t,
      ptr = ptr,
      size = initial_size,
      fill = initial_size
   }
   return setmetatable(self, array_mt)
end

function array_mt:__len()
   return self.fill
end
function array_mt:__index(idx)
   assert(1 <= idx and idx <= self.fill)
   return self.ptr[idx-1]
end
function array_mt:__newindex(idx, val)
   if val then
      if idx > self.size then
         -- grow
         local old = self.ptr
         self.size = self.size * 2
         self.ptr = ffi.new(ffi.typeof("$[?]", self.t), self.size)
         ffi.copy(self.ptr, old, ffi.sizeof(old))
      end
      assert(1 <= idx and idx <= self.fill+1)
      self.fill = math.max(idx, self.fill)
      self.ptr[idx-1] = val
   else
      assert(1 <= idx and idx <= self.fill)
      ffi.copy(self.ptr+idx-1, self.ptr+idx,
         (self.fill-idx)*ffi.sizeof(self.t))
      self.fill = self.fill-1
   end
end
function array_mt:__pairs()
   local idx = 0
   return function()
      idx = idx + 1
      if idx <= self.fill then
         return idx, self.ptr[idx-1]
      end
   end
end
array_mt.__ipairs = array_mt.__pairs

-- The yang modules represent IPv4 addresses as host-endian uint32
-- values in Lua.  See https://github.com/snabbco/snabb/issues/1063.
function ipv4_pton(str)
   return lib.ntohl(ffi.cast('uint32_t*', assert(ipv4:pton(str)))[0])
end

function ipv4_ntop(addr)
   return ipv4:ntop(ffi.new('uint32_t[1]', lib.htonl(addr)))
end

ffi.cdef [[
void* malloc (size_t);
void free (void*);
]]

function memoize(f, max_occupancy)
   local cache = {}
   local occupancy = 0
   local argc = 0
   max_occupancy = max_occupancy or 10
   return function(...)
      local args = {...}
      if #args == argc then
         local walk = cache
         for i=1,#args do
            if walk == nil then break end
            walk = walk[args[i]]
         end
         if walk ~= nil then return unpack(walk) end
      else
         cache, occupancy, argc = {}, 0, #args
      end
      local ret = {f(...)}
      if occupancy >= max_occupancy then
         cache = {}
         occupancy = 0
      end
      local walk = cache
      for i=1,#args-1 do
         if not walk[args[i]] then walk[args[i]] = {} end
         walk = walk[args[i]]
      end
      walk[args[#args]] = ret
      occupancy = occupancy + 1
      return unpack(ret)
   end
end

function timezone ()
   local now = os.time()
   local utctime = os.date("!*t", now)
   local localtime = os.date("*t", now)
   -- Synchronize daylight-saving flags.
   utctime.isdst = localtime.isdst
   local timediff = os.difftime(os.time(localtime), os.time(utctime))
   if timediff ~= 0 then
      local sign = timediff > 0 and "+" or "-"
      local time = os.date("!*t", math.abs(timediff))
      return sign..("%.2d:%.2d"):format(time.hour, time.min)
   end
end

function format_date_as_iso_8601 (time)
   local ret = {}
   time = time or os.time()
   local utctime = os.date("!*t", time)
   table.insert(ret, ("%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ"):format(
      utctime.year, utctime.month, utctime.day, utctime.hour, utctime.min, utctime.sec))
   table.insert(ret, timezone() or "")
   return table.concat(ret, "")
end

-- XXX: ISO 8601 can be more complex. We asumme date is the format returned
-- by 'format_date_as_iso8601'.
function parse_date_as_iso_8601 (date)
   assert(type(date) == 'string')
   local gmtdate = "(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)"
   local year, month, day, hour, min, sec = assert(date:match(gmtdate))
   local ret = {year=year, month=month, day=day, hour=hour, min=min, sec=sec}
   if date:match("Z$") then
      return ret
   else
      local tz_sign, tz_hour, tz_min = date:match("([+-]?)(%d%d):(%d%d)$")
      ret.tz_sign = tz_sign
      ret.tz_hour = tz_hour
      ret.tz_min = tz_min
      return ret
   end
end

function selftest()
   print('selftest: lib.yang.util')
   assert(tointeger('0') == 0)
   assert(tointeger('-0') == 0)
   assert(tointeger('10') == 10)
   assert(tostring(tointeger('10')) == '10')
   assert(tointeger('-10') == -10)
   assert(tointeger('010') == 8)
   assert(tointeger('-010') == -8)
   assert(tointeger('0xffffffff') == 0xffffffff)
   assert(tointeger('0xffffffffffffffff') == 0xffffffffffffffffULL)
   assert(tointeger('0x7fffffffffffffff') == 0x7fffffffffffffffULL)
   assert(tointeger('0xffffffffffffffff') == 0xffffffffffffffffULL)
   assert(tointeger('-0x7fffffffffffffff') == -0x7fffffffffffffffLL)
   assert(tointeger('-0x8000000000000000') == -0x8000000000000000LL)
   assert(ipv4_pton('255.0.0.1') == 255 * 2^24 + 1)
   assert(ipv4_ntop(ipv4_pton('255.0.0.1')) == '255.0.0.1')
   -- ffi_array
   local a = ffi_array(ffi.new("double[3]"), "double")
   assert(#a == 3)
   for i in ipairs(a) do
      a[i] = i
   end
   assert(a[3] == 3)
   a[4] = 4
   assert(a[4] == 4)
   assert(#a == 4)
   a[2] = nil
   assert(#a == 3)
   assert(a[3] == 4)
   print('selftest: ok')
end

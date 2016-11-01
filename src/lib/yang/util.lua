-- Use of this source code is governed by the Apache 2.0 license; see COPYING.
module(..., package.seeall)

local ffi = require("ffi")

-- Parse inet:mac-address using ethernet:pton
-- Parse inet:ipv4-address using ipv4:pton
-- Parse inet:ipv6-address using ipv6:pton

-- Parse inet:ipv4-prefix?
-- Parse inet:ipv6-prefix?

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
   local function check(test)
      return assert(test, 'invalid numeric value for '..what..': '..str)
   end
   check(start <= str:len())
   -- FIXME: check that res did not overflow the 64-bit number
   local res = ffi.C.strtoull(str:sub(start), nil, base)
   if is_negative then
      res = ffi.new('int64_t[1]', -1*res)[0]
      check(res <= 0)
      if min then check(min <= 0 and min <= res) end
   else
      -- Only compare min and res if both are positive, otherwise if min
      -- is a negative int64_t then the comparison will treat it as a
      -- large uint64_t.
      if min then check(min <= 0 or min <= res) end
   end
   if max then check(res <= max) end
   -- Only return Lua numbers for values within int32 + uint32 range.
   if -0x8000000 <= res and res <= 0xffffffff then return tonumber(res) end
   return res
end

function selftest()
   assert(tointeger('0') == 0)
   assert(tointeger('-0') == 0)
   assert(tointeger('10') == 10)
   assert(tointeger('-10') == -10)
   assert(tointeger('010') == 8)
   assert(tointeger('-010') == -8)
   assert(tointeger('0xffffffff') == 0xffffffff)
   assert(tointeger('0xffffffffffffffff') == 0xffffffffffffffffULL)
   assert(tointeger('0x7fffffffffffffff') == 0x7fffffffffffffffULL)
   assert(tointeger('0xffffffffffffffff') == 0xffffffffffffffffULL)
   assert(tointeger('-0x7fffffffffffffff') == -0x7fffffffffffffffLL)
   assert(tointeger('-0x8000000000000000') == -0x8000000000000000LL)
end

module(...,package.seeall)

local ffi = require("ffi")

ffi.cdef[[
typedef long time_t;
typedef long suseconds_t;
struct timeval {
  time_t      tv_sec;     /* seconds */
  suseconds_t tv_usec;    /* microseconds */
};
int gettimeofday(struct timeval *tv, struct timezone *tz);
]]

-- now() returns the current time.  The first time it is called, the
-- return value will be zero.  This is to preserve precision, regardless
-- of what the current epoch is.
local zero_sec, zero_usec
function now()
   local tv = ffi.new("struct timeval")
   assert(ffi.C.gettimeofday(tv, nil) == 0)
   if not zero_sec then
      zero_sec = tv.tv_sec
      zero_usec = tv.tv_usec
   end
   local secs = tonumber(tv.tv_sec - zero_sec)
   secs = secs + tonumber(tv.tv_usec - zero_usec) * 1e-6
   return secs
end

function gmtime()
   local tv = ffi.new("struct timeval")
   assert(ffi.C.gettimeofday(tv, nil) == 0)
   local secs = tonumber(tv.tv_sec)
   secs = secs + tonumber(tv.tv_usec) * 1e-6
   return secs
end

function set(...)
   local ret = {}
   for k, v in pairs({...}) do ret[v] = true end
   return ret
end

function concat(a, b)
   local ret = {}
   for _, v in ipairs(a) do table.insert(ret, v) end
   for _, v in ipairs(b) do table.insert(ret, v) end
   return ret
end

function dup(table)
   local ret = {}
   for k, v in pairs(table) do ret[k] = v end
   return ret
end

function equals(expected, actual)
   if type(expected) ~= type(actual) then return false end
   if type(expected) == 'table' then
      for k, v in pairs(expected) do
         if not equals(v, actual[k]) then return false end
      end
      for k, _ in pairs(actual) do
         if expected[k] == nil then return false end
      end
      return true
   else
      return expected == actual
   end
end

function pp(expr, indent, suffix)
   indent = indent or ''
   suffix = suffix or ''
   if type(expr) == 'number' then
      print(indent..expr..suffix)
   elseif type(expr) == 'string' then
      print(indent..'"'..expr..'"'..suffix)
   elseif type(expr) == 'boolean' then
      print(indent..(expr and 'true' or 'false')..suffix)
   elseif type(expr) == 'table' then
      if #expr == 1 then
         print(indent..'{ "'..expr[1]..'" }'..suffix)
      else
         print(indent..'{ "'..expr[1]..'",')
         indent = indent..'  '
         for i=2,#expr-1 do pp(expr[i], indent, ',') end
         pp(expr[#expr], indent, ' }'..suffix)
      end
   else
      error("unsupported type "..type(expr))
   end
   return expr
end

function assert_equals(expected, actual)
   if not equals(expected, actual) then
      pp(expected)
      pp(actual)
      error('not equal')
   end
end

-- Construct uint32 from octets a, b, c, d; a is most significant.
function uint32(a, b, c, d)
   return a * 2^24 + b * 2^16 + c * 2^8 + d
end

-- Construct uint16 from octets a, b; a is most significant.
function uint16(a, b)
   return a * 2^8 + b
end

function ipv4_to_int(addr)
   assert(addr[1] == 'ipv4', "Not an IPV4 address")
   return uint32(addr[2], addr[3], addr[4], addr[5])
end

function ipv6_as_4x32(addr)
   local function c(i, j) return addr[i] * 2^16 + addr[j] end
   return { c(2,3), c(4,5), c(6,7), c(8,9) }
end

function selftest ()
   print("selftest: pf.utils")
   local tab = { 1, 2, 3 }
   assert(tab ~= dup(tab))
   assert_equals(tab, dup(tab))
   assert_equals({ 1, 2, 3, 1, 2, 3 }, concat(tab, tab))
   assert_equals(set(3, 2, 1), set(1, 2, 3))
   if not zero_sec then assert_equals(now(), 0) end
   assert(now() > 0)
   assert_equals(ipv4_to_int({'ipv4', 255, 0, 0, 0}), 0xff000000)
   local gu1 = gmtime()
   local gu2 = gmtime()
   assert(gu1, gu2)
   print("OK")
end

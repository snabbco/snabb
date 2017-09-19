module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C

local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

IP4 = {}
ip4_t = ffi.typeof("uint32_t")

function IP4.parse_cidr (str)
   local _,_,ip,len = string.find(str, "([^%/]+)%/(%d+)")
   ip = assert(IP4.parse(ip))
   len = assert(tonumber(len), str)
   assert(0 <= len and len <= 32, str)
   return ip, len
end

function IP4.parse (str)
   local _,_,a,b,c,d = string.find(str, "^(%d+).(%d+).(%d+).(%d+)$")
   assert(a, "Invalid IP " .. str)
   a,b,c,d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
   assert(a <= 255 and b <= 255 and c <= 255 and d <= 255, "Invalid IP " .. str)
   return tonumber(ffi.cast("uint32_t", a * 2^24 + b * 2^16 + c * 2^8 + d))
end
function IP4.tostring (ip)
   return string.format("%d.%d.%d.%d",
   band(rshift(ip, 24), 255),
   band(rshift(ip, 16), 255),
   band(rshift(ip, 8), 255),
   band(ip, 255)
   )
end
function IP4.eq (ipa, ipb)
   return ipa == ipb
end
function IP4.get_bit (ip, offset)
   assert(offset >= 0)
   assert(offset < 32)
   return tonumber(bit.band(bit.rshift(ip, 31-offset), 1))
end
IP4.masked = (function()
   local arr = ffi.new("int32_t[?]", 33)
   for i=1,33 do
      arr[i] = bit.bnot(2^(32-i)-1)
   end
   return function(ip, length)
      return ffi.cast("uint32_t", bit.band(ip, arr[length]))
   end
end)()

function IP4.commonlength (ip1, ip2)
   local v = bit.bxor(ip1, ip2)
   for i = 0, 31 do
      if IP4.get_bit(v, i) == 1 then
         return i
      end
   end
   return 32
end

function selftest_get_bit ()
   print("selftest_get_bit()")
   local ip = IP4.parse("192.0.0.3")
   local g = IP4.get_bit
   assert(g(ip, 0) == 1)
   assert(g(ip, 1) == 1)
   assert(g(ip, 2) == 0)
   assert(g(ip, 3) == 0)
   assert(g(ip, 23) == 0)
   assert(g(ip, 29) == 0)
   assert(g(ip, 30) == 1)
   assert(g(ip, 31) == 1)
   ip = IP4.parse("0.0.0.1")
   assert(g(ip,0) == 0)
   assert(g(ip,31) == 1)
end
function selftest_masked ()
   local p = IP4.parse
   local m = IP4.masked
   print("selftest_masked()")
   assert(m(p("216.0.0.0"),8) == m(p("216.1.1.1"), 8))
   assert(m(p("216.0.0.0"),9) == m(p("216.1.1.1"), 9))
   assert(m(p("216.0.0.0"),16) ~= m(p("216.1.1.1"), 16))
   assert(m(p("216.0.0.0"),16) == m(p("216.1.1.1"), 8))
   assert(m(p("216.1.1.1"),32) == m(p("216.1.1.1"), 32))
   assert(m(p("216.0.0.0"),32) ~= m(p("216.1.1.1"), 32))
   assert(m(p("0.0.0.0"),0) == m(p("216.1.1.1"), 0))
end
function selftest_commonlength ()
   print("selftest_commonlength()")
   local p = IP4.parse
   local c = IP4.commonlength
   assert(32 == c(p("255.0.0.0"), p("255.0.0.0")))
   assert(31 == c(p("255.0.0.0"), p("255.0.0.1")))
   assert(30 == c(p("255.0.0.0"), p("255.0.0.2")))
   assert(30 == c(p("255.0.0.0"), p("255.0.0.3")))
   assert(8  == c(p("255.0.0.0"), p("255.128.0.3")))
   assert(0  == c(p("0.0.0.0"), p("255.128.0.3")))
   assert(32 == c(p("0.0.0.0"), p("0.0.0.0")))
end
function selftest_parse ()
   print("selftest_parse()")
   assert(IP4.tostring(IP4.parse("255.255.255.255")) == "255.255.255.255")
   assert(IP4.tostring(IP4.parse("0.0.0.0")) == "0.0.0.0")
   assert(IP4.tostring(IP4.parse("1.1.1.1")) == "1.1.1.1")
   assert(IP4.tostring(IP4.parse("255.255.1.1")) == "255.255.1.1")
   assert(IP4.parse("1.1.1.1") == 2^24+2^16+2^8+1)
   assert(IP4.parse("1.1.1.255") == 2^24+2^16+2^8+255)
   assert(IP4.parse("255.1.1.255") == 255*2^24+2^16+2^8+255)
   local a = IP4.parse("1.2.3.4")
   local b = IP4.parse("2.2.2.2")
   a = b
   assert(IP4.tostring(a) == "2.2.2.2")
end

function IP4.selftest ()
   selftest_parse()
   selftest_masked()
   selftest_get_bit()
   selftest_commonlength()
   local pmu = require("lib.pmu")
   local gbit = IP4.get_bit
   pmu.profile(function()
      local c = 0
      for i = 0,1000000 do
         c = c + IP4.commonlength(i,i)
      end
   end)
end

return IP4

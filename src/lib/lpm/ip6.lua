module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local htons = lib.htons
local ntohs = lib.ntohs

IP6 = {}
ip6_t = ffi.typeof([[
union {
   uint64_t u64[2];
   uint16_t u16[8];
   uint8_t u8[16];
}
]])

local function colons (str)
   local i = 0
   for _ in string.gmatch(str, ":") do i = i + 1 end
   return i
end
function IP6.parse (str)
   local ipbytes = ffi.new(ip6_t)
   assert(string.find(str, ":::") == nil)
   local replace = string.rep(":0", 8 - colons(str)) .. ":"
   str = string.gsub(str, ":$", ":0")
   str = string.gsub(str, "^:", "0:")
   str = string.gsub(str, "::", replace)
   local blk = "(%x?%x?%x?%x?)"
   local chunks = {
      str:match("^" .. string.rep(blk .. ":", 7) .. blk .. "$")
   }
   assert(chunks[1] ~= nil, "Invalid IPv6 Address: " .. str)
   for i,v in pairs(chunks) do
      local n = tonumber(v, 16)
      assert(n >= 0 and n < 2^16, "Invalid IPv6 Address: " .. str)
      ipbytes.u16[i-1] = htons(n)
   end
   return ipbytes
end
function IP6.tostring (ip)
   local tab = {}
   for i = 1,8 do
      tab[i] = string.format("%x", ntohs(ip.u16[i-1]))
   end
   local str = table.concat(tab, ":")
   for i = 7,1,-1 do
      local r = string.rep("0:", i) .. "0"
      local s
      s = string.gsub(str, "^" .. r, "::")
      if s ~= str then return s end
      s = string.gsub(str, ":" .. r .. "$", "::")
      if s ~= str then return s end
   end
   return str
end
function IP6.eq (ipa, ipb)
   return ipa.u64[0] == ipb.u64[0] and ipa.u64[1] == ipb.u64[1]
end

function IP6.get_bit (ip, offset)
   assert(offset > 0)
   assert(offset < 129)
   local bits = bit.rshift(offset-1, 3)
   return bit.band(bit.rshift(ip.u8[bits], 7-bit.band(offset-1, 7)), 1)
end

ffi.metatype(ip6_t, {
   __index = IP6,
   __tostring = IP6.tostring,
   __eq = IP6.eq
})

function selftest ()
   local ip
   assert(colons("::") == 2)
   assert(colons(":0:") == 2)
   assert(colons("0:0:0") == 2)

   -- Ensure tostring() works as a function
   assert(IP6.tostring(IP6.parse("::")) == "::")
   assert(IP6.tostring(IP6.parse("0::")) == "::")
   assert(IP6.tostring(IP6.parse("0::0")) == "::")
   assert(pcall(IP6.parse, "") == false)
   assert(pcall(IP6.parse, "abg::") == false)
   assert(pcall(IP6.parse, "12345::") == false)
   assert(pcall(IP6.parse, "1245:::") == false)
   assert(pcall(IP6.parse, "1:2:3:4:5:6:7:8:9") == false)
   assert(pcall(IP6.parse, "1:2:3:4:5:6:7") == false)

   -- Ensure tostring() works as a method
   assert((IP6.parse("0::0")):tostring() == "::")

   -- Ensure tostring() works
   assert(tostring(IP6.parse("::")) == "::")
   assert(IP6.parse("::") == IP6.parse("::"))

   assert(IP6.parse("::1:2:3:4:5").u16[0] == 0)
   assert(IP6.parse("::1:2:3:4:5").u16[1] == 0)
   assert(IP6.parse("::1:2:3:4:5").u16[2] == 0)
   assert(IP6.parse("::1:2:3:4:5").u16[3] == htons(1))
   assert(IP6.parse("::1:2:3:4:5").u16[4] == htons(2))
   assert(IP6.parse("::1:2:3:4:5").u16[5] == htons(3))
   assert(IP6.parse("::1:2:3:4:5").u16[6] == htons(4))
   assert(IP6.parse("::1:2:3:4:5").u16[7] == htons(5))
   assert(IP6.parse("ffee::"):tostring() == "ffee::")
   assert((IP6.parse("::1")):get_bit(128) == 1)
   assert((IP6.parse("::1")):get_bit(127) == 0)
   assert((IP6.parse("8001::1")):get_bit(1) == 1)
   assert((IP6.parse("8000::1")):get_bit(2) == 0)
   assert((IP6.parse("8000::1")):get_bit(2) == 0)
   assert((IP6.parse("8001::1")):get_bit(15) == 0)
   assert((IP6.parse("8001::1")):get_bit(16) == 1)
   assert((IP6.parse("70::"):tostring() == "70::"))
   assert((IP6.parse("070::"):tostring() == "70::"))
end

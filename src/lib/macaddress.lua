--- MAC address handling object.
-- depends on LuaJIT's 64-bit capabilities,
-- both for numbers and bit.* library
local bit = require "bit"
local ffi = require "ffi"

local mac_t = ffi.typeof('union { int64_t bits; uint8_t bytes[6];}')
local mac_mt = {}
mac_mt.__index = mac_mt

function mac_mt:new (m)
   if ffi.istype(mac_t, m) then
      return m
   end
   local macobj = mac_t()
   if type(m) == 'string' then
      local i = 0;
      for b in m:gmatch('%x%x') do
         if i == 6 then
            -- avoid out of bound array index
            return nil, "malformed MAC address: " .. m
         end
         macobj.bytes[i] = tonumber(b, 16)
         i = i + 1
      end
      if i < 6 then
         return nil, "malformed MAC address: " .. m
      end
   else
      macobj.bits = m
   end
   return macobj
end
function mac_mt:from_bytes(b)
	local macobj = mac_t()
	ffi.copy(macobj.bytes, b, 6)
	return macobj
end

function mac_mt:__tostring ()
   return string.format('%02X:%02X:%02X:%02X:%02X:%02X',
      self.bytes[0], self.bytes[1], self.bytes[2],
      self.bytes[3], self.bytes[4], self.bytes[5])
end

function mac_mt.__eq (a, b)
   return a.bits == b.bits
end

function mac_mt:subbits (i,j)
   local b = bit.rshift(self.bits, i)
   local mask = bit.bnot(bit.lshift(0xffffffffffffLL, j-i))
   return tonumber(bit.band(b, mask))
end

mac_t = ffi.metatype(mac_t, mac_mt)

return mac_mt

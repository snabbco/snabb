require("class")
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")

-- From net/ethernet.h
-- All fields user network byte order
local ether_header_t = ffi.typeof[[
struct {
   uint8_t  ether_dhost[6];
   uint8_t  ether_shost[6];
   uint16_t ether_type;
} __attribute__((packed))
]]

local mac_addr_t = ffi.typeof("uint8_t[6]")
local ether_header_ptr_t = ffi.typeof("$ *", ether_header_t)

local ethernet = subClass(header)

-- Class variables
ethernet._name = "ethernet"
ethernet._header_type = ether_header_t
ethernet._ulp = { 
   class_map = { [0x86dd] = "lib.protocol.ipv6" },
   method    = 'type' }

-- Class methods

function ethernet:_init_new(src, dst, type)
   local header = ether_header_t()
   ffi.copy(header.ether_dhost, dst, 6)
   ffi.copy(header.ether_shost, src, 6)
   header.ether_type = C.htons(type)
   self._header = header
end

-- Convert printable address to numeric
function ethernet:pton(p)
   local result = mac_addr_t()
   local i = 0
   for v in p:split(":") do
      if string.match(v:lower(), '^[0-9a-f][0-9a-f]$') then
	 result[i] = tonumber("0x"..v)
      else
	 error("invalid mac address "..p)
      end
      i = i+1
   end
   assert(i == 6, "invalid mac address "..p)
   return result
end

function ethernet:ntop(n)
   local p = {}
   for i = 0, 5, 1 do
      table.insert(p, string.format("%02x", n[i]))
   end
   return table.concat(p, ":")
end

-- Instance methods

function ethernet:swap()
   local tmp = ffi.new("uint8_t[6]")
   local h = self._header
   ffi.copy(tmp, h.ether_dhost, 6)
   ffi.copy(h.ether_dhost, h.ether_shost,6)
   ffi.copy(h.ether_shost, tmp, 6)
end

function ethernet:src(a)
   local h = self._header
   if a ~= nil then
      ffi.copy(h.ether_shost, a, 6)
   end
   return h.ether_shost
end

function ethernet:dst(a)
   local h = self._header
   if a ~= nil then
      ffi.copy(h.ether_dhost, a, 6)
   end
   return h.ether_dhost
end

function ethernet:swap()
   local tmp = ffi.new("uint8_t[6]")
   local h = self._header
   ffi.copy(tmp, h.ether_dhost, 6)
   ffi.copy(h.ether_dhost, h.ether_shost,6)
   ffi.copy(h.ether_shost, tmp, 6)
end

function ethernet:type(t)
   local h = self._header
   if t ~= nil then
      h.ether_type = C.htons(t)
   end
   return(C.ntohs(h.ether_type))
end

return ethernet

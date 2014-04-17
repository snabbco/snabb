local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")

-- XXX IPv4 and IPv6 use the same ICMP header format but distinct
-- number spaces for type and code.  This class needs to be subclassed
-- accordingly.

local icmp_t = ffi.typeof[[
      struct {
	 uint8_t type;
	 uint8_t code;
	 int16_t checksum;
      } __attribute__((packed))
]]

local icmp = subClass(header)

-- Class variables
icmp._name = "icmp"
icmp._header_type = icmp_t
icmp._header_ptr_type = ffi.typeof("$*", icmp_t)
icmp._ulp = { 
   class_map = { [135] = "lib.protocol.icmp.nd.ns",
		 [136] = "lib.protocol.icmp.nd.na" },
   method    = "type" }

-- Class methods

function icmp:_init_new (type, code)
   local header = icmp_t()
   self._header = header
   header.type = type
   header.code = code
end

-- Instance methods

function icmp:type (type)
   if type ~= nil then
      self._header.type = type
   else
      return self._header.type
   end
end

function icmp:code (code)
   if code ~= nil then
      self._header.code = code
   else
      return self._header.code
   end
end

function icmp:checksum (payload, length, ipv6)
   local h = self._header
   local csum = 0
   if ipv6 then
      -- Checksum IPv6 pseudo-header
      local ph = ipv6:pseudo_header(length + self:sizeof(), 58)
      csum = lib.update_csum(ph, ffi.sizeof(ph), csum)
   end
   -- Add ICMP header
   h.checksum = 0
   csum = lib.update_csum(h, self:sizeof(), csum)
   -- Add ICMP payload
   csum = lib.update_csum(payload, length, csum)
   h.checksum = C.htons(lib.finish_csum(csum))
end

return icmp

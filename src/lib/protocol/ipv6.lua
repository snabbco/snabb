require("class")
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")

local ipv6hdr_t = ffi.typeof[[
      struct {
	 uint32_t flow_id; // version, tc, flow_id
	 uint16_t payload_length;
	 uint8_t  next_header;
	 uint8_t hop_limit;
	 char src_ip[16];
	 char dst_ip[16];
      } __attribute__((packed))
]]

local ipv6hdr_pseudo_t = ffi.typeof[[
      struct {
	 char src_ip[16];
	 char dst_ip[16];
	 uint16_t ulp_zero;
	 uint16_t ulp_length;
	 uint8_t  zero[3];
	 uint8_t  next_header;
      } __attribute__((packed))
]]

local ipv6_addr_t = ffi.typeof("uint16_t[8]")

local ipv6 = subClass(header)

-- Class variables
ipv6._name = "ipv6"
ipv6._header_type = ipv6hdr_t
ipv6._ulp = {
   class_map = { [47] = "lib.protocol.gre",
		 [58] = "lib.protocol.icmp.header",
	      },
   method    = 'next_header' }

-- Class methods

function ipv6:_init_new(class, flow_label, next_header, hop_limit, src, dst)
   local header = ipv6hdr_t()
   header.flow_id = C.htonl(0x60000000)
   ffi.copy(header.src_ip, src, 16)
   ffi.copy(header.dst_ip, dst, 16)
   self._header = header
   self:next_header(next_header)
   self:hop_limit(hop_limit)
end

function ipv6:pton(p)
   local result = ipv6_addr_t()
   local i = 0
   for v in p:split(":") do
      if string.match(v:lower(), '^[0-9a-f]?[0-9a-f]?[0-9a-f]?[0-9a-f]$') then
	 result[i] = C.htons(tonumber("0x"..v))
      else
	 error("invalid ipv6 address "..p.." "..v)
      end
      i = i+1
   end
   assert(i == 8, "invalid ipv6 address "..p.." "..i)
   return result
end

function ipv6:ntop(n)
   local p = {}
   for i = 0, 7, 1 do
      table.insert(p, string.format("%x", C.ntohs(n[i])))
   end
   return table.concat(p, ":")
end

-- Instance methods

function ipv6:src(ip)
   if ip ~= nil then
      ffi.copy(self._header.src_ip, ip, 16)
   end
   return self._header.src_ip
end

function ipv6:src_eq(ip)
   return C.memcmp(ip, self._header.src_ip, 16) == 0
end

function ipv6:dst(ip)
   if ip ~= nil then
      ffi.copy(self._header.dst_ip, ip, 16)
   end
   return self._header.dst_ip
end

function ipv6:dst_eq(ip)
   return C.memcmp(ip, self._header.dst_ip, 16) == 0
end

function ipv6:payload_length(length)
   if length ~= nil then
      self._header.payload_length = C.htons(length)
   end
   return(C.ntohs(self._header.payload_length))
end

function ipv6:hop_limit(limit)
   if limit ~= nil then
      self._header.hop_limit = limit
   end
   return(self._header.hop_limit)
end

function ipv6:next_header(nh)
   if nh ~= nil then
      self._header.next_header = nh
   end
   return(self._header.next_header)
end

-- Return a pseudo header for checksum calculation in a upper-layer
-- protocol (e.g. icmp).  Note that the payload length and next-header
-- values in the pseudo-header refer to the effective upper-layer
-- protocol.  They differ from the respective values of the ipv6
-- header if extension headers are present.
function ipv6:pseudo_header(plen, nh)
   local ph = ipv6hdr_pseudo_t()
   local h = self._header
   ffi.copy(ph, h.src_ip, 32)  -- Copy source and destination
   ph.ulp_length = C.htons(plen)
   ph.next_header = nh
   return(ph)
end

return ipv6

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local header = require("lib.protocol.header")

local ipv6hdr_t = ffi.typeof[[
      struct {
	 uint32_t v_tc_fl; // version, tc, flow_label
	 uint16_t payload_length;
	 uint8_t  next_header;
	 uint8_t hop_limit;
	 uint8_t src_ip[16];
	 uint8_t dst_ip[16];
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
ipv6._header_ptr_type = ffi.typeof("$*", ipv6hdr_t)
ipv6._ulp = {
   class_map = { [47] = "lib.protocol.gre",
		 [58] = "lib.protocol.icmp.header",
	      },
   method    = 'next_header' }

-- Class methods

function ipv6:new (config)
   local o = ipv6:superClass().new(self)
   local header = o._header
   header.v_tc_fl = C.htonl(0x60000000)
   ffi.copy(header.src_ip, config.src, 16)
   ffi.copy(header.dst_ip, config.dst, 16)
   o:traffic_class(config.traffic_class)
   o:flow_label(config.flow_label)
   o:next_header(config.next_header)
   o:hop_limit(config.hop_limit)
   return o
end

-- XXX should probably use inet_pton(3)
function ipv6:pton (p)
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

-- XXX should probably use inet_ntop(3)
function ipv6:ntop (n)
   local p = {}
   local n = ffi.cast("uint8_t *", n)
   for i = 0, 14, 2 do
      table.insert(p, string.format("%02x%02x", n[i], n[i+1]))
   end
   return table.concat(p, ":")
end

-- Instance methods

function ipv6:traffic_class (tc)
   return lib.bitfield(32, self._header, 'v_tc_fl', 4, 8, tc)
end

function ipv6:flow_label (fl)
   return lib.bitfield(32, self._header, 'v_tc_fl', 12, 20, fl)
end

function ipv6:payload_length (length)
   if length ~= nil then
      self._header.payload_length = C.htons(length)
   else
      return(C.ntohs(self._header.payload_length))
   end
end

function ipv6:next_header (nh)
   if nh ~= nil then
      self._header.next_header = nh
   else
      return(self._header.next_header)
   end
end

function ipv6:hop_limit (limit)
   if limit ~= nil then
      self._header.hop_limit = limit
   else
      return(self._header.hop_limit)
   end
end

function ipv6:src (ip)
   if ip ~= nil then
      ffi.copy(self._header.src_ip, ip, 16)
   else
      return self._header.src_ip
   end
end

function ipv6:src_eq (ip)
   return C.memcmp(ip, self._header.src_ip, 16) == 0
end

function ipv6:dst (ip)
   if ip ~= nil then
      ffi.copy(self._header.dst_ip, ip, 16)
   else
      return self._header.dst_ip
   end
end

function ipv6:dst_eq (ip)
   return C.memcmp(ip, self._header.dst_ip, 16) == 0
end

-- Return a pseudo header for checksum calculation in a upper-layer
-- protocol (e.g. icmp).  Note that the payload length and next-header
-- values in the pseudo-header refer to the effective upper-layer
-- protocol.  They differ from the respective values of the ipv6
-- header if extension headers are present.
function ipv6:pseudo_header (plen, nh)
   local ph = ipv6hdr_pseudo_t()
   local h = self._header
   ffi.copy(ph, h.src_ip, 32)  -- Copy source and destination
   ph.ulp_length = C.htons(plen)
   ph.next_header = nh
   return(ph)
end

return ipv6

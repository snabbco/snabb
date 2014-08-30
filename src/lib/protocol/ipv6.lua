module(..., package.seeall)
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
   class_map = {
       [6] = "lib.protocol.tcp",
      [17] = "lib.protocol.udp",
      [47] = "lib.protocol.gre",
      [58] = "lib.protocol.icmp.header",
   },
   method    = 'next_header' }

-- Class methods

function ipv6:new (config)
   local o = ipv6:superClass().new(self)
   if not o._recycled then
      o._ph = ipv6hdr_pseudo_t()
   end
   o:version(6)
   o:traffic_class(config.traffic_class)
   o:flow_label(config.flow_label)
   o:next_header(config.next_header)
   o:hop_limit(config.hop_limit)
   o:src(config.src)
   o:dst(config.dst)
   return o
end

function ipv6:new_from_mem(mem, size)
   local o = ipv6:superClass().new_from_mem(self, mem, size)
   if not o._recycled then
      o._ph = ipv6hdr_pseudo_t()
   end
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

-- Construct the solicited-node multicast address from the given
-- unicast address by appending the last 24 bits to ff02::1:ff00:0/104
function ipv6:solicited_node_mcast (n)
   local n = ffi.cast("uint8_t *", n)
   local result = self:pton("ff02:0:0:0:0:1:ff00:0")
   ffi.copy(ffi.cast("uint8_t *", result)+13, n+13, 3)
   return result
end

-- Instance methods

function ipv6:version (v)
   return lib.bitfield(32, self:header(), 'v_tc_fl', 0, 4, v)
end

function ipv6:traffic_class (tc)
   return lib.bitfield(32, self:header(), 'v_tc_fl', 4, 8, tc)
end

function ipv6:dscp (dscp)
   return lib.bitfield(32, self:header(), 'v_tc_fl', 4, 6, dscp)
end

function ipv6:ecn (ecn)
   return lib.bitfield(32, self:header(), 'v_tc_fl', 10, 2, ecn)
end

function ipv6:flow_label (fl)
   return lib.bitfield(32, self:header(), 'v_tc_fl', 12, 20, fl)
end

function ipv6:payload_length (length)
   if length ~= nil then
      self:header().payload_length = C.htons(length)
   else
      return(C.ntohs(self:header().payload_length))
   end
end

function ipv6:next_header (nh)
   if nh ~= nil then
      self:header().next_header = nh
   else
      return(self:header().next_header)
   end
end

function ipv6:hop_limit (limit)
   if limit ~= nil then
      self:header().hop_limit = limit
   else
      return(self:header().hop_limit)
   end
end

function ipv6:src (ip)
   if ip ~= nil then
      ffi.copy(self:header().src_ip, ip, 16)
   else
      return self:header().src_ip
   end
end

function ipv6:src_eq (ip)
   return C.memcmp(ip, self:header().src_ip, 16) == 0
end

function ipv6:dst (ip)
   if ip ~= nil then
      ffi.copy(self:header().dst_ip, ip, 16)
   else
      return self:header().dst_ip
   end
end

function ipv6:dst_eq (ip)
   return C.memcmp(ip, self:header().dst_ip, 16) == 0
end

-- Return a pseudo header for checksum calculation in a upper-layer
-- protocol (e.g. icmp).  Note that the payload length and next-header
-- values in the pseudo-header refer to the effective upper-layer
-- protocol.  They differ from the respective values of the ipv6
-- header if extension headers are present.
function ipv6:pseudo_header (plen, nh)
   local ph = self._ph
   ffi.fill(ph, ffi.sizeof(ph))
   local h = self:header()
   ffi.copy(ph, h.src_ip, 32)  -- Copy source and destination
   ph.ulp_length = C.htons(plen)
   ph.next_header = nh
   return(ph)
end

return ipv6

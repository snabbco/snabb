-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local header = require("lib.protocol.header")
local ipsum = require("lib.checksum").ipsum
local htons, ntohs, htonl, ntohl =
   lib.htons, lib.ntohs, lib.htonl, lib.ntohl

-- TODO: generalize
local AF_INET = 2
local INET_ADDRSTRLEN = 16

local ipv4hdr_pseudo_t = ffi.typeof[[
      struct {
      uint8_t  src_ip[4];
      uint8_t  dst_ip[4];
      uint8_t  ulp_zero;
      uint8_t  ulp_protocol;
      uint16_t ulp_length;
      } __attribute__((packed))
]]

local ipv4_addr_t = ffi.typeof("uint8_t[4]")
local ipv4_addr_t_size = ffi.sizeof(ipv4_addr_t)
local ipv4 = subClass(header)

-- Class variables
ipv4._name = "ipv4"
ipv4._ulp = {
   class_map = {
       [6] = "lib.protocol.tcp",
      [17] = "lib.protocol.udp",
      [47] = "lib.protocol.gre",
      [58] = "lib.protocol.icmp.header",
      [1] = "lib.protocol.icmp.header",
   },
   method    = 'protocol' }
ipv4:init(
   {
      [1] = ffi.typeof[[
	    struct {
	       uint16_t ihl_v_tos; // ihl:4, version:4, tos(dscp:6 + ecn:2)
	       uint16_t total_length;
	       uint16_t id;
	       uint16_t frag_off; // flags:3, fragmen_offset:13
	       uint8_t  ttl;
	       uint8_t  protocol;
	       uint16_t checksum;
	       uint8_t  src_ip[4];
	       uint8_t  dst_ip[4];
	    } __attribute__((packed))
      ]],
   })

-- Class methods

function ipv4:new (config)
   local o = ipv4:superClass().new(self)
   if not o._recycled then
      o._ph = ipv4hdr_pseudo_t()
   end
   o:header().ihl_v_tos = htons(0x4000) -- v4
   o:ihl(o:sizeof() / 4)
   o:dscp(config.dscp or 0)
   o:ecn(config.ecn or 0)
   o:total_length(o:sizeof()) -- default to header only
   o:id(config.id or 0)
   o:flags(config.flags or 0)
   o:frag_off(config.frag_off or 0)
   o:ttl(config.ttl or 0)
   o:protocol(config.protocol or 0xff)
   o:src(config.src)
   o:dst(config.dst)
   o:checksum()
   return o
end

function ipv4:new_from_mem(mem, size)
   local o = ipv4:superClass().new_from_mem(self, mem, size)
   if not o._recycled then
      o._ph = ipv4hdr_pseudo_t()
   end
   return o
end

function ipv4:pton (p)
   local in_addr  = ffi.new("uint8_t[4]")
   local result = C.inet_pton(AF_INET, p, in_addr)
   if result ~= 1 then
      return false, "malformed IPv4 address: " .. p
   end
   return in_addr
end

function ipv4:ntop (n)
   local p = ffi.new("char[?]", INET_ADDRSTRLEN)
   local c_str = C.inet_ntop(AF_INET, n, p, INET_ADDRSTRLEN)
   return ffi.string(c_str)
end

function ipv4:pton_cidr (p)
   local prefix, length = p:match("([^/]*)/([0-9]*)")
   return
      ipv4:pton(prefix),
      assert(tonumber(length), "Invalid length "..length)
end

-- Instance methods

function ipv4:version (v)
   return lib.bitfield(16, self:header(), 'ihl_v_tos', 0, 4, v)
end

function ipv4:ihl (ihl)
   return lib.bitfield(16, self:header(), 'ihl_v_tos', 4, 4, ihl)
end

function ipv4:dscp (dscp)
   return lib.bitfield(16, self:header(), 'ihl_v_tos', 8, 6, dscp)
end

function ipv4:ecn (ecn)
   return lib.bitfield(16, self:header(), 'ihl_v_tos', 14, 2, ecn)
end

function ipv4:total_length (length)
   if length ~= nil then
      self:header().total_length = htons(length)
   else
      return(ntohs(self:header().total_length))
   end
end

function ipv4:id (id)
   if id ~= nil then
      self:header().id = htons(id)
   else
      return(ntohs(self:header().id))
   end
end

function ipv4:flags (flags)
   return lib.bitfield(16, self:header(), 'frag_off', 0, 3, flags)
end

function ipv4:frag_off (frag_off)
   return lib.bitfield(16, self:header(), 'frag_off', 3, 13, frag_off)
end

function ipv4:ttl (ttl)
   if ttl ~= nil then
      self:header().ttl = ttl
   else
      return self:header().ttl
   end
end

function ipv4:protocol (protocol)
   if protocol ~= nil then
      self:header().protocol = protocol
   else
      return self:header().protocol
   end
end

function ipv4:checksum ()
   self:header().checksum = 0
   self:header().checksum = htons(ipsum(ffi.cast("uint8_t *", self:header()),
                                        self:sizeof(), 0))
   return ntohs(self:header().checksum)
end

function ipv4:src (ip)
   if ip ~= nil then
      ffi.copy(self:header().src_ip, ip, ipv4_addr_t_size)
   else
      return self:header().src_ip
   end
end

function ipv4:src_eq (ip)
   return C.memcmp(ip, self:header().src_ip, ipv4_addr_t_size) == 0
end

function ipv4:dst (ip)
   if ip ~= nil then
      ffi.copy(self:header().dst_ip, ip, ipv4_addr_t_size)
   else
      return self:header().dst_ip
   end
end

function ipv4:dst_eq (ip)
   return C.memcmp(ip, self:header().dst_ip, ipv4_addr_t_size) == 0
end

-- override the default equality method
function ipv4:eq (other)
   --compare significant fields
   return (self:ihl() == other:ihl()) and
         (self:id() == other:id()) and
         (self:protocol() == other:protocol()) and
         self:src_eq(other:src()) and self:dst_eq(other:dst())
end

-- Return a pseudo header for checksum calculation in a upper-layer
-- protocol (e.g. icmp).  Note that the payload length and next-header
-- values in the pseudo-header refer to the effective upper-layer
-- protocol.  They differ from the respective values of the ipv6
-- header if extension headers are present.
function ipv4:pseudo_header (ulplen, proto)
   local ph = self._ph
   ffi.fill(ph, ffi.sizeof(ph))
   local h = self:header()
   ffi.copy(ph, h.src_ip, 2*ipv4_addr_t_size)  -- Copy source and destination
   ph.ulp_length = htons(ulplen)
   ph.ulp_protocol = proto
   return(ph)
end

local function test_ipv4_checksum ()
   local IP_BASE      = 14
   local IP_HDR_SIZE  = 20

   local p = packet.from_string(lib.hexundump([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 34 59 1a 40 00 40 06 b0 8e c0 a8 14 a9 6b 15
      f0 b4 de 0b 01 bb e7 db 57 bc 91 cd 18 32 80 10
      05 9f 00 00 00 00 01 01 08 0a 06 0c 5c bd fa 4a
      e1 65
   ]], 66))

   local ip_hdr = ipv4:new_from_mem(p.data + IP_BASE, IP_HDR_SIZE)
   assert(ip_hdr)
   local csum = ip_hdr:checksum()
   assert(csum == 0xb08e, "Wrong IPv4 checksum")
end

function selftest()
   local ipv4_address = "192.168.1.1"
   assert(ipv4_address == ipv4:ntop(ipv4:pton(ipv4_address)),
      'ipv4 text to binary conversion failed.')

   test_ipv4_checksum()

   local ipv4hdr = ipv4:new({})
   assert(C.ntohs(ipv4hdr:header().ihl_v_tos) == 0x4500,
      'ipv4 header field ihl_v_tos not initialized correctly.')
end

ipv4.selftest = selftest

return ipv4

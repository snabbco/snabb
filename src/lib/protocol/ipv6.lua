-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local header = require("lib.protocol.header")
local htons, ntohs = lib.htons, lib.ntohs

local AF_INET6 = 10
local INET6_ADDRSTRLEN = 48

local defaults = {
   traffic_class = 0,
   flow_label = 0,
   next_header = 59, -- no next header
   hop_limit = 64,
}

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
ipv6._ulp = {
   class_map = {
       [6] = "lib.protocol.tcp",
      [17] = "lib.protocol.udp",
      [47] = "lib.protocol.gre",
      [58] = "lib.protocol.icmp.header",
      [115] = "lib.protocol.keyed_ipv6_tunnel",
   },
   method    = 'next_header' }
header.init(ipv6,
            {
               [1] = ffi.typeof[[
                     struct {
                        uint32_t v_tc_fl; // version, tc, flow_label
                        uint16_t payload_length;
                        uint8_t  next_header;
                        uint8_t hop_limit;
                        uint8_t src_ip[16];
                        uint8_t dst_ip[16];
                     } __attribute__((packed))
               ]]
            })

-- Class methods

function ipv6:new (config)
   local o = ipv6:superClass().new(self)
   if not o._recycled then
      o._ph = ipv6hdr_pseudo_t()
   end
   o:version(6)
   o:traffic_class(config.traffic_class or defaults.traffic_class)
   o:flow_label(config.flow_label or defaults.flow_label)
   o:next_header(config.next_header or defaults.next_header)
   o:hop_limit(config.hop_limit or defaults.hop_limit)
   o:src(config.src)
   o:dst(config.dst)
   return o
end

function ipv6:new_from_mem(mem, size)
   local o = ipv6:superClass().new_from_mem(self, mem, size)
   if o == nil then
      return nil
   end
   if not o._recycled then
      o._ph = ipv6hdr_pseudo_t()
   end
   return o
end

function ipv6:pton (p)
   local in_addr  = ffi.new("uint8_t[16]")
   local result = C.inet_pton(AF_INET6, p, in_addr)
   if result ~= 1 then
      return false, "malformed IPv6 address: " .. p
   end
   return in_addr
end

function ipv6:ntop (n)
   local p = ffi.new("char[?]", INET6_ADDRSTRLEN)
   local c_str = C.inet_ntop(AF_INET6, n, p, INET6_ADDRSTRLEN)
   return ffi.string(c_str)
end

function ipv6:pton_cidr (p)
   local prefix, length = p:match("([^/]*)/([0-9]*)")
   return
      ipv6:pton(prefix),
      assert(tonumber(length), "Invalid length "..length)
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
      self:header().payload_length = htons(length)
   else
      return(ntohs(self:header().payload_length))
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
   ph.ulp_length = htons(plen)
   ph.next_header = nh
   return(ph)
end

function selftest()
   local ipv6_address = "2001:620:0:c101::2"
   assert(ipv6_address == ipv6:ntop(ipv6:pton(ipv6_address)),
      'ipv6 text to binary conversion failed.')
end

ipv6.selftest = selftest

return ipv6

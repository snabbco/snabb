module(..., package.seeall)

local util = require("apps.wall.util")
local lib  = require("core.lib")
local bit  = require("bit")
local ffi  = require("ffi")

local rd16, rd32 = util.rd16, util.rd32
local ipv4_addr_cmp, ipv6_addr_cmp = util.ipv4_addr_cmp, util.ipv6_addr_cmp
local tobit, lshift, rshift = bit.tobit, bit.lshift, bit.rshift
local band, bxor, bnot = bit.band, bit.bxor, bit.bnot

-- Constants: Ethernet
ETH_TYPE_IPv4        = lib.htons(0x0800)
ETH_TYPE_IPv6        = lib.htons(0x86DD)
ETH_TYPE_VLAN        = lib.htons(0x8100)
ETH_TYPE_OFFSET      = 12
ETH_HEADER_SIZE      = 14

-- Constants: IPv4
IPv4_VER_IHL_OFFSET  = 0
IPv4_DSCP_ECN_OFFSET = 1
IPv4_LEN_OFFSET      = 2
IPv4_FRAG_ID_OFFSET  = 4
IPv4_FLAGS_OFFSET    = 6
IPv4_TTL_OFFSET      = 8
IPv4_PROTO_OFFSET    = 9
IPv4_CHECKSUM_OFFSET = 10
IPv4_SRC_ADDR_OFFSET = 12
IPv4_DST_ADDR_OFFSET = 16

IPv4_PROTO_TCP       = 6   -- uint8_t
IPv4_PROTO_UDP       = 17  -- uint8_t

-- Constants: IPv6
IPv6_MIN_HEADER_SIZE = 40
IPv6_PLOADLEN_OFFSET = 4
IPv6_NEXTHDR_OFFSET  = 6
IPv6_HOPLIMIT_OFFSET = 7
IPv6_SRC_ADDR_OFFSET = 8
IPv6_DST_ADDR_OFFSET = 24

IPv6_NEXTHDR_HOPBYHOP= 0
IPv6_NEXTHDR_TCP     = 6
IPv6_NEXTHDR_UDP     = 17
IPv6_NEXTHDR_ROUTING = 43
IPv6_NEXTHDR_FRAGMENT= 44
IPv6_NEXTHDR_ESP     = 50
IPv6_NEXTHDR_AH      = 51
IPv6_NEXTHDR_ICMPv6  = 58
IPv6_NEXTHDR_NONE    = 59
IPv6_NEXTHDR_DSTOPTS = 60

-- Constants: TCP
TCP_HEADER_SIZE      = 20
TCP_SRC_PORT_OFFSET  = 0
TCP_DST_PORT_OFFSET  = 2

-- Constants: UDP
UDP_HEADER_SIZE      = 8
UDP_SRC_PORT_OFFSET  = 0
UDP_DST_PORT_OFFSET  = 2


ffi.cdef [[
   struct swall_flow_key_ipv4 {
      uint16_t vlan_id;
      uint8_t  __pad;
      uint8_t  ip_proto;
      uint8_t  lo_addr[4];
      uint8_t  hi_addr[4];
      uint16_t lo_port;
      uint16_t hi_port;
   } __attribute__((packed));

   struct swall_flow_key_ipv6 {
      uint16_t vlan_id;
      uint8_t  __pad;
      uint8_t  ip_proto;
      uint8_t  lo_addr[16];
      uint8_t  hi_addr[16];
      uint16_t lo_port;
      uint16_t hi_port;
   } __attribute__((packed));
]]

local function hash32(i32)
   i32 = tobit(i32)
   i32 = i32 + bnot(lshift(i32, 15))
   i32 = bxor(i32, (rshift(i32, 10)))
   i32 = i32 + lshift(i32, 3)
   i32 = bxor(i32, rshift(i32, 6))
   i32 = i32 + bnot(lshift(i32, 11))
   i32 = bxor(i32, rshift(i32, 16))
   return i32
end

local uint32_ptr_t = ffi.typeof("uint32_t*")
local function make_cdata_hash_function(sizeof)
   assert(sizeof >= 4)
   assert(sizeof % 4 == 0)

   local rounds = (sizeof / 4) - 1
   return function (cdata)
      cdata = ffi.cast(uint32_ptr_t, cdata)
      local h = hash32(cdata[0])
      for i = 1, rounds do
         h = hash32(bxor(h, hash32(cdata[i])))
      end
      return h
   end
end


local flow_key_ipv4 = ffi.metatype("struct swall_flow_key_ipv4", {
   __index = {
      hash = make_cdata_hash_function(ffi.sizeof("struct swall_flow_key_ipv4")),
      eth_type = function (self) return ETH_TYPE_IPv4 end,
   }
})

local flow_key_ipv6 = ffi.metatype("struct swall_flow_key_ipv6", {
   __index = {
      hash = make_cdata_hash_function(ffi.sizeof("struct swall_flow_key_ipv6")),
      eth_type = function (self) return ETH_TYPE_IPv6 end,
   }
})

-- Helper functions

--
-- Obtain the Internet Header Length (IHL) of an IPv4 packet, and return
-- its value converted to bytes.
--
local function ihl(p, offset)
   local ver_and_ihl = p.data[offset]
   return band(ver_and_ihl, 0x0F) * 4
end

--
-- Traverse an IPv6 header which has the following layout:
--
--     0         8        16
--     | NextHdr | HdrLen | ...
--
--  where "NextHdr" is the type code of the next header, and "HdrLen" is the
--  length of the header in 8-octet units, sans the first 8 octets.
--
local function ipv6_nexthdr_type_len_skip (p)
   return p[0], p + 8 + (p[1] * 8)
end

local ipv6_walk_header_funcs = {
   [IPv6_NEXTHDR_HOPBYHOP] = ipv6_nexthdr_type_len_skip,
   [IPv6_NEXTHDR_ROUTING]  = ipv6_nexthdr_type_len_skip,
   [IPv6_NEXTHDR_DSTOPTS]  = ipv6_nexthdr_type_len_skip,
   [IPv6_NEXTHDR_FRAGMENT] = function (p)
      return p[0], p + 8
   end,
   [IPv6_NEXTHDR_AH] = function (p)
      -- Size specified in 4-octet units (plus two octets).
      return p[0], p + 2 + (p[1] * 4)
   end,
}

--
-- Traverses all the IPv6 headers (using the "next header" fields) until an
-- upper-level protocol header (e.g. TCP, UDP) is found. The returned value
-- is the type of the upper level protocol code and pointer to the beginning
-- of the upper level protocol header data.
--
local function ipv6_walk_headers (p, offset)
   local ptr = p.data + offset
   local nexthdr = ptr[IPv6_NEXTHDR_OFFSET]
   while ipv6_walk_header_funcs[nexthdr] do
      local new_nexthdr, new_ptr = ipv6_walk_header_funcs[nexthdr](ptr)
      if new_ptr > p.data + p.length then
         break
      end
      nexthdr, ptr = new_nexthdr, new_ptr
   end
   return nexthdr, ptr
end


Scanner = subClass()
Scanner._name = "SnabbWall base packet Scanner"

function Scanner:extract_packet_info(p)
   local eth_type  = rd16(p.data + ETH_TYPE_OFFSET)
   local ip_offset = ETH_HEADER_SIZE
   local vlan_id   = 0

   while eth_type == ETH_TYPE_VLAN do
      vlan_id   = rd16(p.data + ip_offset)
      eth_type  = rd16(p.data + ip_offset + 2)
      ip_offset = ip_offset + 4
   end

   local key, src_addr, src_port, dst_addr, dst_port, ip_proto
   if eth_type == ETH_TYPE_IPv4 then
      key = flow_key_ipv4()
      src_addr = p.data + ip_offset + IPv4_SRC_ADDR_OFFSET
      dst_addr = p.data + ip_offset + IPv4_DST_ADDR_OFFSET
      if ipv4_addr_cmp(src_addr, dst_addr) <= 0 then
         ffi.copy(key.lo_addr, src_addr, 4)
         ffi.copy(key.hi_addr, dst_addr, 4)
      else
         ffi.copy(key.lo_addr, dst_addr, 4)
         ffi.copy(key.hi_addr, src_addr, 4)
      end

      ip_proto = p.data[ip_offset + IPv4_PROTO_OFFSET]
      local ip_payload_offset = ip_offset + ihl(p, ip_offset)
      if ip_proto == IPv4_PROTO_TCP then
         src_port = rd16(p.data + ip_payload_offset + TCP_SRC_PORT_OFFSET)
         dst_port = rd16(p.data + ip_payload_offset + TCP_DST_PORT_OFFSET)
      elseif ip_proto == IPv4_PROTO_UDP then
         src_port = rd16(p.data + ip_payload_offset + UDP_SRC_PORT_OFFSET)
         dst_port = rd16(p.data + ip_payload_offset + UDP_DST_PORT_OFFSET)
      end
   elseif eth_type == ETH_TYPE_IPv6 then
      key = flow_key_ipv6()
      src_addr = p.data + ip_offset + IPv6_SRC_ADDR_OFFSET
      dst_addr = p.data + ip_offset + IPv6_DST_ADDR_OFFSET
      if ipv6_addr_cmp(src_addr, dst_addr) <= 0 then
         ffi.copy(key.lo_addr, src_addr, 16)
         ffi.copy(key.hi_addr, dst_addr, 16)
      else
         ffi.copy(key.lo_addr, dst_addr, 16)
         ffi.copy(key.hi_addr, src_addr, 16)
      end

      local proto_header_ptr
      ip_proto, proto_header_ptr = ipv6_walk_headers (p, ip_offset)
      if ip_proto == IPv6_NEXTHDR_TCP then
         src_port = rd16(proto_header_ptr + TCP_SRC_PORT_OFFSET)
         dst_port = rd16(proto_header_ptr + TCP_DST_PORT_OFFSET)
      elseif ip_proto == IPv6_NEXTHDR_UDP then
         src_port = rd16(proto_header_ptr + UDP_SRC_PORT_OFFSET)
         dst_port = rd16(proto_header_ptr + UDP_DST_PORT_OFFSET)
      end
   else
      return nil
   end

   key.vlan_id = vlan_id
   key.ip_proto = ip_proto

   if src_port and dst_port then
      if src_port < dst_port then
         key.lo_port, key.hi_port = src_port, dst_port
      else
         key.lo_port, key.hi_port = dst_port, src_port
      end
   end

   return key, ip_offset, src_addr, src_port, dst_addr, dst_port
end

function Scanner:get_flow(p)
   error("method must be overriden in a subclass")
end

function Scanner:scan_packet(p, time)
   error("method must be overriden in a subclass")
end

function Scanner:protocol_name(protocol)
   return tostring(protocol)
end

function selftest()
   local ipv6 = require("lib.protocol.ipv6")
   local ipv4 = require("lib.protocol.ipv4")

   do -- Test comparison of IPv6 addresses
      assert(ipv6_addr_cmp(ipv6:pton("2001:fd::1"),
                           ipv6:pton("2001:fd::2")) <= 0)

      local a = ipv6:pton("2001:fd48::01")
      local b = ipv6:pton("2001:fd48::02")  -- Last byte differs
      local c = ipv6:pton("2002:fd48::01")  -- Second byte differs
      local d = ipv6:pton("2102:fd48::01")  -- First byte differs

      assert(ipv6_addr_cmp(a, a) == 0)
      assert(ipv6_addr_cmp(b, b) == 0)
      assert(ipv6_addr_cmp(c, c) == 0)
      assert(ipv6_addr_cmp(d, d) == 0)

      assert(ipv6_addr_cmp(a, b) < 0)
      assert(ipv6_addr_cmp(a, c) < 0)
      assert(ipv6_addr_cmp(a, d) < 0)

      assert(ipv6_addr_cmp(b, a) > 0)
      assert(ipv6_addr_cmp(b, c) < 0)
      assert(ipv6_addr_cmp(b, d) < 0)

      assert(ipv6_addr_cmp(c, a) > 0)
      assert(ipv6_addr_cmp(c, b) > 0)
      assert(ipv6_addr_cmp(c, d) < 0)
   end

   do -- Test hashing of IPv4 flow keys
      local function make_ipv4_key()
         local key = flow_key_ipv4()
         key.vlan_id = 10
         key.ip_proto = IPv4_PROTO_UDP
         ffi.copy(key.lo_addr, ipv4:pton("10.0.0.1"), 4)
         ffi.copy(key.hi_addr, ipv4:pton("10.0.0.2"), 4)
         key.lo_port = 8080
         key.hi_port = 1010
         return key
      end
      local k = make_ipv4_key()
      assert(k:hash() == make_ipv4_key():hash())
      -- Changing any value makes the hash vary
      k.lo_port = 2020
      assert(k:hash() ~= make_ipv4_key():hash())
   end

   do -- Test hashing of IPv6 flow keys
      local function make_ipv6_key()
         local key = flow_key_ipv6()
         key.vlan_id = 42
         key.ip_proto = IPv6_NEXTHDR_TCP
         ffi.copy(key.lo_addr, ipv6:pton("2001:fd::1"), 16)
         ffi.copy(key.hi_addr, ipv6:pton("2001:fd::2"), 16)
         key.lo_port = 4040
         key.hi_port = 3030
         return key
      end
      local k = make_ipv6_key()
      assert(k:hash() == make_ipv6_key():hash())
      -- Changing any value makes the hash vary
      k.lo_port = IPv6_NEXTHDR_UDP
      assert(k:hash() ~= make_ipv6_key():hash())
   end

   do -- Test Scanner:extract_packet_info()
      local s = Scanner:new()

      local datagram = require("lib.protocol.datagram")
      local ethernet = require("lib.protocol.ethernet")
      local dg = datagram:new()
      dg:push(ipv6:new({ src = ipv6:pton("2001:fd::1"),
                         dst = ipv6:pton("2001:fd::2"),
                         next_header = IPv6_NEXTHDR_NONE }))
      dg:push(ethernet:new({ src = ethernet:pton("02:00:00:00:00:01"),
                             dst = ethernet:pton("02:00:00:00:00:02"),
                             type = lib.ntohs(ETH_TYPE_IPv6) }))

      local key, ip_offset, src_addr, src_port, dst_addr, dst_port =
            s:extract_packet_info(dg:packet())
      assert(key.vlan_id == 0)
      assert(key.ip_proto == IPv6_NEXTHDR_NONE)
      assert(ipv6_addr_cmp(key.lo_addr, ipv6:pton("2001:fd::1")) == 0)
      assert(ipv6_addr_cmp(key.hi_addr, ipv6:pton("2001:fd::2")) == 0)
      assert(key.lo_port == 0)
      assert(key.hi_port == 0)
   end
end

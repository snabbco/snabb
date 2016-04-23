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
      uint32_t lo_addr;
      uint32_t hi_addr;
      uint16_t lo_port;
      uint16_t hi_port;
   } __attribute__((packed));

   struct swall_flow_key_ipv6 {
      uint16_t vlan_id;
      uint8_t  __pad;
      uint8_t  ip_proto;
      uint64_t lo_addr;
      uint64_t hi_addr;
      uint16_t lo_port;
      uint16_t hi_port;
   } __attribute__((packed));
]]

local INT32_MIN = -0x80000000
local function hash32(i32)
   i32 = tobit(i32)
   i32 = i32 + bnot(lshift(i32, 15))
   i32 = bxor(i32, (rshift(i32, 10)))
   i32 = i32 + lshift(i32, 3)
   i32 = bxor(i32, rshift(i32, 6))
   i32 = i32 + bnot(lshift(i32, 11))
   i32 = bxor(i32, rshift(i32, 16))

   -- Unset the low bit, to distinguish valid hashes from HASH_MAX.
   i32 = lshift(i32, 1)
   -- Project result to u32 range.
   return i32 - INT32_MIN
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
         h = hash32(cdata[i])
      end
      return h
   end
end

local uint8_ptr_t = ffi.typeof("uint8_t*")

local flow_key_ipv4_size = ffi.sizeof("struct swall_flow_key_ipv4")
assert(flow_key_ipv4_size % 4 == 0)

local flow_key_ipv4_lo_addr_offset =
   ffi.offsetof("struct swall_flow_key_ipv4", "lo_addr")
local flow_key_ipv4_hi_addr_offset =
   ffi.offsetof("struct swall_flow_key_ipv4", "hi_addr")

local flow_key_ipv4 = ffi.metatype("struct swall_flow_key_ipv4", {
   __index = {
      hash = make_cdata_hash_function(flow_key_ipv4_size),
      eth_type = function (self) return ETH_TYPE_IPv4 end,
      lo_addr_ptr = function (self)
         return ffi.cast(uint8_ptr_t, self) + flow_key_ipv4_lo_addr_offset
      end,
      hi_addr_ptr = function (self)
         return ffi.cast(uint8_ptr_t, self) + flow_key_ipv4_hi_addr_offset
      end,
   }
})

local flow_key_ipv6_size = ffi.sizeof("struct swall_flow_key_ipv6")
assert(flow_key_ipv6_size % 4 == 0)

local flow_key_ipv6_lo_addr_offset =
   ffi.offsetof("struct swall_flow_key_ipv6", "lo_addr")
local flow_key_ipv6_hi_addr_offset =
   ffi.offsetof("struct swall_flow_key_ipv6", "hi_addr")

local flow_key_ipv6 = ffi.metatype("struct swall_flow_key_ipv6", {
   __index = {
      hash = make_cdata_hash_function(flow_key_ipv6_size),
      eth_type = function (self) return ETH_TYPE_IPv6 end,
      lo_addr_ptr = function (self)
         return ffi.cast(uint8_ptr_t, self) + flow_key_ipv6_lo_addr_offset
      end,
      hi_addr_ptr = function (self)
         return ffi.cast(uint8_ptr_t, self) + flow_key_ipv6_hi_addr_offset
      end,
   }
})

-- Helper functions

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
local function ipv6_walk_headers (p)
   local ptr = p.data
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
      src_addr = rd32(p.data + ip_offset + IPv4_SRC_ADDR_OFFSET)
      dst_addr = rd32(p.data + ip_offset + IPv4_DST_ADDR_OFFSET)
      if src_addr < dst_addr then
         key.lo_addr, key.hi_addr = src_addr, dst_addr
      else
         key.lo_addr, key.hi_addr = dst_addr, src_addr
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
         ffi.copy(key:lo_addr_ptr(), src_addr, 16)
         ffi.copy(key:hi_addr_ptr(), dst_addr, 16)
      else
         ffi.copy(key:lo_addr_ptr(), dst_addr, 16)
         ffi.copy(key:hi_addr_ptr(), src_addr, 16)
      end

      local proto_header_ptr
      ip_proto, proto_header_ptr = ipv6_walk_headers (p)
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

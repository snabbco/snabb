module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local ffi = require("ffi")
local lib = require("core.lib")
local lwtypes = require("apps.lwaftr.lwtypes")

local cast = ffi.cast
local bitfield = lib.bitfield
local ethernet_header_ptr_type = lwtypes.ethernet_header_ptr_type
local ipv6_header_ptr_type = lwtypes.ipv6_header_ptr_type
local htons = lib.htons

-- Transitional header handling library.
-- Over the longer term, something more lib.protocol-like has some nice advantages.

-- All addresses should be in network byte order, as should eth_type and vlan_tag.
-- payload lengths should be in host byte order.
-- next_hdr_type and dscp_and_ecn are <= 1 byte, so byte order is irrelevant.

function write_eth_header(dst_ptr, ether_src, ether_dst, eth_type)
   local eth_hdr = cast(ethernet_header_ptr_type, dst_ptr)
   eth_hdr.ether_shost = ether_src
   eth_hdr.ether_dhost = ether_dst
   eth_hdr.ether_type = eth_type
end

function write_ipv6_header(dst_ptr, ipv6_src, ipv6_dst, dscp_and_ecn, next_hdr_type, payload_length)
   local ipv6_hdr = cast(ipv6_header_ptr_type, dst_ptr)
   ffi.fill(ipv6_hdr, ffi.sizeof(ipv6_hdr), 0)
   bitfield(32, ipv6_hdr, 'v_tc_fl', 0, 4, 6)            -- IPv6 Version
   bitfield(32, ipv6_hdr, 'v_tc_fl', 4, 8, dscp_and_ecn) -- Traffic class
   ipv6_hdr.payload_length = htons(payload_length)
   ipv6_hdr.next_header = next_hdr_type
   ipv6_hdr.hop_limit = constants.default_ttl
   ipv6_hdr.src_ip = ipv6_src
   ipv6_hdr.dst_ip = ipv6_dst
end

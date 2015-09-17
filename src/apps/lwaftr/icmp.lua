module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local bit = require("bit")
local ffi = require("ffi")
local math = require("math")

local band, bnot = bit.band, bit.bnot
local C = ffi.C

local function calculate_payload_size(dst_pkt, initial_pkt, max_size, config)
   local original_bytes_to_skip = constants.ethernet_header_size
   if config.extra_payload_offset then
      original_bytes_to_skip = original_bytes_to_skip + config.extra_payload_offset
   end
   local payload_size = initial_pkt.length - original_bytes_to_skip
   local non_payload_bytes = dst_pkt.length + constants.icmp_base_size
   local full_pkt_size = payload_size + non_payload_bytes
   if full_pkt_size > max_size then
      full_pkt_size = max_size
      payload_size = full_pkt_size - non_payload_bytes
   end
   return payload_size, original_bytes_to_skip, non_payload_bytes
end

-- Write ICMP data to the end of a packet
-- Config must contain code and type
-- Config may contain a 'next_hop_mtu' setting.

local dgram = datagram:new()

local function write_icmp(dst_pkt, initial_pkt, max_size, base_checksum, config)
   local payload_size, original_bytes_to_skip, non_payload_bytes =
      calculate_payload_size(dst_pkt, initial_pkt, max_size, config)
   local off = dst_pkt.length
   dst_pkt.data[off] = config.type
   dst_pkt.data[off + 1] = config.code
   ffi.cast("uint16_t*", dst_pkt.data + off + 2)[0] = 0 -- checksum
   ffi.cast("uint32_t*", dst_pkt.data + off + 4)[0] = 0 -- Reserved
   if config.next_hop_mtu then
      ffi.cast("uint16_t*", dst_pkt.data + off + 6)[0] = C.htons(config.next_hop_mtu)
   end
   local dest = dst_pkt.data + non_payload_bytes
   C.memmove(dest, initial_pkt.data + original_bytes_to_skip, payload_size)

   local icmp_bytes = constants.icmp_base_size + payload_size
   local icmp_start = dst_pkt.data + dst_pkt.length
   local csum = checksum.ipsum(icmp_start, icmp_bytes, base_checksum)
   ffi.cast("uint16_t*", dst_pkt.data + off + 2)[0] = C.htons(csum)

   dst_pkt.length = dst_pkt.length + icmp_bytes
end

-- initial_pkt is the one to embed (a subset of) in the ICMP payload
function new_icmpv4_packet(from_eth, to_eth, from_ip, to_ip, initial_pkt, config)
   local new_pkt = packet.allocate()
   local dgram = dgram:reuse(new_pkt)
   local ipv4_header = ipv4:new({ttl = constants.default_ttl,
                                 protocol = constants.proto_icmp,
                                 src = from_ip, dst = to_ip})
   ipv4_header:version(4) -- It was being set to 0, which is bogus...

   local ethernet_header = ethernet:new({src = from_eth,
                                         dst = to_eth,
                                         type = constants.ethertype_ipv4})
   dgram:push(ipv4_header)
   dgram:push(ethernet_header)
   ethernet_header:free()
   ipv4_header:free()

   -- Generate RFC 1812 ICMPv4 packets, which carry as much payload as they can,
   -- rather than RFC 792 packets, which only carry the original IPv4 header + 8 octets
   write_icmp(new_pkt, initial_pkt, constants.max_icmpv4_packet_size, 0, config)

   -- Fix up the IPv4 total length and checksum
   local new_ipv4_len = new_pkt.length - constants.ethernet_header_size
   local ip_tl_p = new_pkt.data + constants.ethernet_header_size + constants.o_ipv4_total_length
   ffi.cast("uint16_t*", ip_tl_p)[0] = C.ntohs(new_ipv4_len)
   local ip_checksum_p = new_pkt.data + constants.ethernet_header_size + constants.o_ipv4_checksum
   ffi.cast("uint16_t*", ip_checksum_p)[0] = 0 -- zero out the checksum before recomputing
   local csum = checksum.ipsum(new_pkt.data + constants.ethernet_header_size, new_ipv4_len, 0)
   ffi.cast("uint16_t*", ip_checksum_p)[0] = C.htons(csum)

   return new_pkt
end

function new_icmpv6_packet(from_eth, to_eth, from_ip, to_ip, initial_pkt, config)
   local new_pkt = packet.allocate()
   local dgram = dgram:reuse(new_pkt)
   local ipv6_header = ipv6:new({hop_limit = constants.default_ttl,
                                 next_header = constants.proto_icmpv6,
                                 src = from_ip, dst = to_ip})
   local ethernet_header = ethernet:new({src = from_eth,
                                         dst = to_eth,
                                         type = constants.ethertype_ipv6})
   dgram:push(ipv6_header)
   dgram:push(ethernet_header)
   ethernet_header:free()
   ipv6_header:free()

   local max_size = constants.max_icmpv6_packet_size
   local ph_len = calculate_payload_size(new_pkt, initial_pkt, max_size, config) + constants.icmp_base_size
   local ph = ipv6_header:pseudo_header(ph_len, constants.proto_icmpv6)
   local ph_csum = checksum.ipsum(ffi.cast("uint8_t *", ph), ffi.sizeof(ph), 0)
   local ph_csum = band(bnot(ph_csum), 0xffff)
   write_icmp(new_pkt, initial_pkt, max_size, ph_csum, config)

   local new_ipv6_len = new_pkt.length - (constants.ipv6_fixed_header_size + constants.ethernet_header_size)
   local ip_pl_p = new_pkt.data + constants.ethernet_header_size + constants.o_ipv6_payload_len
   ffi.cast("uint16_t*", ip_pl_p)[0] = C.ntohs(new_ipv6_len)

   return new_pkt
end

module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local ffi = require("ffi")
local C = ffi.C

-- Write ICMP data to the end of a packet

-- Config must contain code, type, payload_p and payload_len
-- payload_p is a pointer to the beginning of a payload
-- payload_len is the number of bytes to use from it

-- Config may contain a next_hop_mtu.

function write_icmp(pkt, config, base_checksum)
   local bytes_needed = constants.icmp_base_size + config.payload_len
   assert(bytes_needed + pkt.length <= tonumber(C.PACKET_PAYLOAD_SIZE),
          "Refusing to write ICMP that would overflow a packet")
   assert(config.type)
   assert(config.code)
   assert(config.payload_p)
   assert(config.payload_len)

   local off = pkt.length
   local icmp_bytes = constants.icmp_base_size + config.payload_len
   pkt.data[off] = config.type
   pkt.data[off + 1] = config.code
   ffi.cast("uint16_t*", pkt.data + off + 2)[0] = 0 -- checksum
   ffi.cast("uint32_t*", pkt.data + off + 4)[0] = 0 -- Reserved
   if config.next_hop_mtu then
      ffi.cast("uint16_t*", pkt.data + off +  6)[0] = C.htons(config.next_hop_mtu)
   end
   for i=0,config.payload_len -1 do -- TODO: optimize this?
      pkt.data[off + 8 + i] = ffi.cast("uint8_t*", config.payload_p + i)[0]
   end

   local icmp_start = ffi.cast("uint8_t*", pkt.data + pkt.length)
   local csum = checksum.ipsum(icmp_start, icmp_bytes, base_checksum or 0)
   ffi.cast("uint16_t*", pkt.data + off + 2)[0] = C.htons(csum)

   pkt.length = pkt.length + icmp_bytes
end

function new_icmpv4_packet(from_eth, to_eth, from_ip, to_ip, config)
   local new_pkt = packet.allocate()
   local dgram = datagram:new(new_pkt) -- TODO: recycle this
   local ipv4_header = ipv4:new({ttl = constants.default_ttl,
                                 protocol = constants.proto_icmp,
                                 src = from_ip, dst = to_ip})
   ipv4_header:version(4) -- It was being set to 0, which is bogus...
   ipv4_header:total_length(ipv4_header:total_length() + constants.icmpv4_total_size)

   local ethernet_header = ethernet:new({src = from_eth,
                                         dst = to_eth,
                                         type = constants.ethertype_ipv4})
   dgram:push(ipv4_header)
   dgram:push(ethernet_header)
   ethernet_header:free()
   ipv4_header:free()
   dgram:free()
   write_icmp(new_pkt, config)

   local ip_checksum_p = new_pkt.data + constants.ethernet_header_size + constants.ipv4_checksum
   ffi.cast("uint16_t*", ip_checksum_p)[0] = 0 -- zero out the checksum before recomputing
   local csum = checksum.ipsum(new_pkt.data + constants.ethernet_header_size, ipv4_header:total_length(), 0)
   ffi.cast("uint16_t*", ip_checksum_p)[0] = C.htons(csum)
   return new_pkt
end

function new_icmpv6_packet(from_eth, to_eth, from_ip, to_ip, config)
   local new_pkt = packet.allocate()
   local dgram = datagram:new(new_pkt) -- TODO: recycle this
   local ipv6_payload_len = config.payload_len + constants.icmp_base_size
   local ipv6_header = ipv6:new({hop_limit = constants.default_ttl,
                                 next_header = constants.proto_icmpv6,
                                 src = from_ip, dst = to_ip})
   ipv6_header:payload_length(ipv6_payload_len)
   local ph = ipv6_header:pseudo_header(ipv6_payload_len, constants.proto_icmpv6)
   local ph_csum = checksum.ipsum(ffi.cast("uint8_t *", ph), ffi.sizeof(ph), 0)
   local ph_csum = bit.band(0xffff, bit.bnot(ph_csum))
   local ethernet_header = ethernet:new({src = from_eth,
                                         dst = to_eth,
                                         type = constants.ethertype_ipv6})
   dgram:push(ipv6_header)
   dgram:push(ethernet_header)
   ethernet_header:free()
   ipv6_header:free()
   dgram:free()
   write_icmp(new_pkt, config, ph_csum)
   return new_pkt
end

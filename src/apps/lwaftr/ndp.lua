module(..., package.seeall)

-- NDP address resolution.
-- Given a remote IPv6 address, try to find out its MAC address.
-- If resolution succeeds:
-- All packets coming through the 'south' interface (ie, via the network card)
-- are silently forwarded.
-- Note that the network card can drop packets; if it does, they will not get
-- to this app.
-- All packets coming through the 'north' interface (the lwaftr) will have
-- their Ethernet headers rewritten.

-- Expected configuration:
-- lwaftr <-> ipv6 fragmentation app <-> lw_eth_resolve <-> vlan tag handler
-- That is, neither fragmentation nor vlan tagging are within the scope of this app.

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

local checksum = require("lib.checksum")
local ffi = require("ffi")

local C = ffi.C
local rd16, wr16, wr32, ipv6_equals = lwutil.rd16, lwutil.wr16, lwutil.wr32, lwutil.ipv6_equals

local option_source_link_layer_address = 1
local option_target_link_layer_address = 2
local eth_ipv6_size = constants.ethernet_header_size + constants.ipv6_fixed_header_size
local o_icmp_target_offset = 8
local o_icmp_first_option = 24

-- Cache constants
local ipv6_pseudoheader_size = constants.ipv6_pseudoheader_size
local ethernet_header_size = constants.ethernet_header_size
local o_ipv6_src_addr =  constants.o_ipv6_src_addr
local o_ipv6_dst_addr =  constants.o_ipv6_dst_addr
local o_ipv6_payload_len = constants.o_ipv6_payload_len
local o_ipv6_next_header = constants.o_ipv6_next_header
local o_ipv6_hop_limit = constants.o_ipv6_hop_limit
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local proto_icmpv6 = constants.proto_icmpv6
local icmpv6_na = constants.icmpv6_na
local icmpv6_ns = constants.icmpv6_ns
local n_ethertype_ipv6 = constants.n_ethertype_ipv6
local ethertype_ipv6 = constants.ethertype_ipv6

-- Special addresses
ipv6_all_nodes_local_segment_addr = ipv6:pton("ff02::1")
ipv6_unspecified_addr = ipv6:pton("0::0") -- aka ::/128
-- Really just the first 13 bytes of the following...
ipv6_solicited_multicast = ipv6:pton("ff02:0000:0000:0000:0000:0001:ff00:00")


-- Pseudo-header:
-- 32 bytes src and dst addresses
-- 4 bytes content length, network byte order
--   (2 0 bytes and then 2 possibly-0 content length bytes in practice)
-- three zero bytes, then the next_header byte
local _scratch_pseudoheader = ffi.new('uint8_t[?]', ipv6_pseudoheader_size)
local function checksum_pseudoheader_from_header(ipv6_fixed_header)
   local ph_size = ipv6_pseudoheader_size
   ffi.fill(_scratch_pseudoheader, ph_size)
   ffi.copy(_scratch_pseudoheader, ipv6_fixed_header + o_ipv6_src_addr, 32)
   ffi.copy(_scratch_pseudoheader + 34, ipv6_fixed_header + o_ipv6_payload_len, 2)
   ffi.copy(_scratch_pseudoheader + 39, ipv6_fixed_header + o_ipv6_next_header, 1)
   return checksum.ipsum(_scratch_pseudoheader, ph_size, 0)
end

local function eth_next_is_ipv6(pkt)
   return rd16(pkt.data + o_ethernet_ethertype) == n_ethertype_ipv6
end

local function ipv6_next_is_icmp6(pkt)
   local offset = ethernet_header_size + o_ipv6_next_header
   return pkt.data[offset] == proto_icmpv6
end

local function icmpv6_type_is_na(pkt)
   return pkt.data[eth_ipv6_size] == icmpv6_na
end

local function icmpv6_type_is_ns(pkt)
   return pkt.data[eth_ipv6_size] == icmpv6_ns
end

-- The relevant byte is:
-- [ R S O 0 0 0 0 0 0 ], where S = solicited
-- Format:
-- 1 byte type, 1 byte code, 2 bytes checksum
-- RSO + 29 reserved bits.
-- Then target address (16 bytes) and possibly options.
local function is_solicited_na(pkt)
   local o_rso_bits = 4
   local offset = eth_ipv6_size + o_rso_bits
   local sol_bit = 0x40
   return bit.band(sol_bit, pkt.data[offset]) == sol_bit
end


--[[ All NDP messages are >= 8 bytes. Router solicitation is the shortest:
      0                   1                   2                   3
      0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     |     Type      |     Code      |          Checksum             |
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     |                            Reserved                           |
     +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
     |   Options ...
     +-+-+-+-+-+-+-+-+-+-+-+-
--]]
function is_ndp(pkt)
   local min_ndp_len = eth_ipv6_size + 8
   if pkt.length >= min_ndp_len and
      eth_next_is_ipv6(pkt) and
      ipv6_next_is_icmp6(pkt)
   then
      local icmp_type = pkt.data[eth_ipv6_size]
      return (icmp_type >= 133 and icmp_type <= 137)
   end
   return false
end

-- TODO: tune this for speed
-- Note that this must be run after any vlan tags have been stripped out
-- and after any reassembly has been done, and no extra IPv6 headers
-- must be present
--- TODO: could this reasonably use pflang?
function is_solicited_neighbor_advertisement(pkt)
   return is_ndp(pkt) and
          icmpv6_type_is_na(pkt) and
          is_solicited_na(pkt)
end

local function is_neighbor_solicitation(pkt)
   return is_ndp(pkt) and icmpv6_type_is_ns(pkt)
end

-- Check whether NS target address matches IPv6 address.
function is_neighbor_solicitation_for_addr(pkt, ipv6_addr)
   if not is_neighbor_solicitation(pkt) then return false end
   local target_offset = eth_ipv6_size + o_icmp_target_offset
   local target_ipv6 = pkt.data + target_offset
   return ipv6_equals(target_ipv6, ipv6_addr)
end

local function to_ether_addr(pkt, offset)
   local ether_src = ffi.new("uint8_t[?]", 6)
   ffi.copy(ether_src, pkt.data + offset, 6)
   return ether_src
end

-- The option format is, for ethernet networks:
-- 1 byte option type, 1 byte option length (in chunks of 8 bytes)
-- 6 bytes MAC address
function get_dst_ethernet(pkt, target_ipv6_addrs)
   if pkt == nil or target_ipv6_addrs == nil then return false end
   local na_addr_offset = eth_ipv6_size + o_icmp_target_offset
   for i=1,#target_ipv6_addrs do
      if ipv6_equals(target_ipv6_addrs[i], pkt.data + na_addr_offset) then
         local na_option_offset = eth_ipv6_size + o_icmp_first_option
         if pkt.data[na_option_offset] == option_target_link_layer_address then
            return to_ether_addr(pkt, na_option_offset + 2)
         end
         -- When responding to unicast solicitations, the option can be omitted
         -- since the sender of the solicitation has the correct link-layer
         -- address (See 4.4. Neighbor Advertisement Message Format)
         if pkt.length == na_option_offset then
            return to_ether_addr(pkt, 6)
         end
      end
   end
   return false
end

local function write_ndp(pkt, local_eth, target_addr, i_type, flags, option_type)
   local i_code = 0
   pkt.data[0] = i_type
   pkt.data[1] = i_code
   wr16(pkt.data + 2, 0) -- initial 0 checksum
   wr32(pkt.data + 4, 0) -- 29-32 reserved bits, depending on type
   pkt.data[4] = flags
   ffi.copy(pkt.data + 8, target_addr, 16)

   -- The link layer address SHOULD or MUST be set, so set it
   pkt.data[o_icmp_first_option] = option_type
   pkt.data[25] = 1 -- this option is one 8-octet chunk long
   ffi.copy(pkt.data + 26, local_eth, 6)
   pkt.length = 32
end

-- This only does solicited neighbor advertisements
local function write_sna(pkt, local_eth, is_router, soliciting_pkt, base_checksum)
   local target_addr = soliciting_pkt.data + eth_ipv6_size + 8
   local i_type = icmpv6_na -- RFC 4861 neighbor advertisement
   local flags = 0x40 -- solicited
   -- don't support the override flag for now; TODO?
   if is_router then flags = flags + 0x80 end
   local option_type = option_target_link_layer_address
   write_ndp(pkt, local_eth, target_addr, i_type, flags, option_type)
end

-- This does not allow setting any options in the packet.
-- Target address must be in the format that results from pton.
local function write_ns(pkt, local_eth, target_addr)
   local i_type = icmpv6_ns -- RFC 4861 neighbor solicitation
   local option_type = option_source_link_layer_address
   write_ndp(pkt, local_eth, target_addr, i_type, 0, option_type)
end


function form_ns(local_eth, local_ipv6, dst_ipv6)
   local ns_pkt = packet.allocate()
   local ethernet_broadcast = ethernet:pton("ff:ff:ff:ff:ff:ff")
   local hop_limit = 255 -- as per RFC 4861

   write_ns(ns_pkt, local_eth, dst_ipv6)
   local dgram = datagram:new(ns_pkt)
   local i = ipv6:new({ hop_limit = hop_limit, 
                        next_header = proto_icmpv6,
                        src = local_ipv6, dst = dst_ipv6 })
   i:payload_length(dgram:packet().length)
   
   local ph = i:pseudo_header(dgram:packet().length, proto_icmpv6)
   local ph_len = ipv6_pseudoheader_size
   local base_checksum = checksum.ipsum(ffi.cast("uint8_t*", ph), ph_len, 0)
   local csum = checksum.ipsum(dgram:packet().data, dgram:packet().length, bit.bnot(base_checksum))
   wr16(dgram:packet().data + 2, C.htons(csum))
   
   dgram:push(i)
   dgram:push(ethernet:new({ src = local_eth, dst = ethernet_broadcast,
                             type = ethertype_ipv6 }))
   ns_pkt = dgram:packet()
   dgram:free()
   return ns_pkt
end

--[[ IPv6 Destination Address
                     For solicited advertisements, the Source Address of
                     an invoking Neighbor Solicitation or, if the
                     solicitation s Source Address is the unspecified
                     address, the all-nodes multicast address.
--]]
-- TODO: verify that the all nodes *local segment* rather than *node local*
-- IPv6 multicast address is the right one.
local function form_sna(local_eth, local_ipv6, is_router, soliciting_pkt)
   if not soliciting_pkt then return nil end
   local na_pkt = packet.allocate()
   -- The destination of the reply is the source of the original packet
   local dst_eth = soliciting_pkt.data + 6
   local hop_limit = 255 -- as per RFC 4861

   write_sna(na_pkt, local_eth, is_router, soliciting_pkt)
   local dgram = datagram:new(na_pkt)
   local src_addr_offset = ethernet_header_size + o_ipv6_src_addr
   local invoking_src_addr = soliciting_pkt.data + src_addr_offset
   local dst_ipv6
   if ipv6_equals(invoking_src_addr, ipv6_unspecified_addr) then
      dst_ipv6 = ipv6_all_nodes_local_segment_addr
   else
      dst_ipv6 = invoking_src_addr
   end
   local i = ipv6:new({ hop_limit = hop_limit,
                        next_header = proto_icmpv6,
                        src = local_ipv6, dst = dst_ipv6 })
   i:payload_length(dgram:packet().length)
   
   local ph = i:pseudo_header(dgram:packet().length, proto_icmpv6)
   local ph_len = ipv6_pseudoheader_size
   local base_checksum = checksum.ipsum(ffi.cast("uint8_t*", ph), ph_len, 0)
   local csum = checksum.ipsum(dgram:packet().data, dgram:packet().length,
                               bit.bnot(base_checksum))
   wr16(dgram:packet().data + 2, C.htons(csum))
   
   dgram:push(i)
   dgram:push(ethernet:new({ src = local_eth, dst = dst_eth,
                             type = ethertype_ipv6 }))
   na_pkt = dgram:packet()
   dgram:free()
   return na_pkt
end

local function verify_icmp_checksum(pkt)
   local offset = ethernet_header_size + o_ipv6_payload_len
   local icmp_length = C.ntohs(rd16(pkt.data + offset))
   local ph_csum = checksum_pseudoheader_from_header(
      pkt.data + ethernet_header_size)
   local a = checksum.ipsum(pkt.data + eth_ipv6_size, icmp_length, bit.bnot(
      ph_csum))
   return a == 0
end

-- IPv6 multicast addresses start with FF.
local function is_address_multicast(ipv6_addr)
   return ipv6_addr[0] == 0xff
end

local function target_address_is_multicast(pkt)
   return is_address_multicast(pkt.data + eth_ipv6_size + 8)
end

-- Each 1 added to length represents an 8 octet chunk.
local function option_lengths_are_nonzero(pkt)
   local start = eth_ipv6_size + o_icmp_first_option
   while start < pkt.length do
      local cur_option_length = pkt.data[start + 1]
      if cur_option_length == 0 then return false end
      start = start + 8 * cur_option_length
   end
   return true
end

-- Solicited multicast addresses have their first 13 bytes
-- set to ff02::1:ff00:0/104, aka
-- ff02:0000:0000:0000:0000:0001:ff[UV:WXYZ]
local function ip_dst_is_solicited_node_multicast_address(pkt)
   local dst_addr = pkt.data + ethernet_header_size + o_ipv6_dst_addr
   return C.memcmp(dst_addr, ipv6_solicited_multicast, 13) == 0
end

local function has_src_link_layer_address_option(pkt)
   local start = eth_ipv6_size + o_icmp_first_option
   while start < pkt.length do
      local cur_option_length = pkt.data[start + 1]
      local cur_option_type = pkt.data[start]
      if cur_option_type == option_source_link_layer_address then return true end
      start = start + 8 * cur_option_length
   end
   return false
end

--[[ RFC 4861
   A node MUST silently discard any received Neighbor Solicitation
   messages that do not satisfy all of the following validity checks:

      - The IP Hop Limit field has a value of 255, i.e., the packet
        could not possibly have been forwarded by a router.
      - ICMP length (derived from the IP length) is 24 or more octets.
      - ICMP Checksum is valid.
      - ICMP Code is 0.
      - Target Address is not a multicast address.
      - All included options have a length that is greater than zero.
      - If the IP source address is the unspecified address, the IP
        destination address is a solicited-node multicast address.
      - If the IP source address is the unspecified address, there is no
        source link-layer address option in the message.
--]]
-- Note that any vlan/etc tags have been stripped off already by another app
local function is_valid_ns(pkt)
   -- Verify that there are no extra IPv6 headers via is_ndp
   if not is_ndp(pkt) then return false end

   local ehs = ethernet_header_size
   local ip_hop_offset = ehs + o_ipv6_hop_limit
   if pkt.data[ip_hop_offset] ~= 255 then return false end

   local iplen_offset = ehs + o_ipv6_payload_len
   local icmp_length = C.ntohs(rd16(pkt.data + iplen_offset))
   if icmp_length < 24 then return false end
   if not verify_icmp_checksum(pkt) then return false end
   local icmp_code_offset = eth_ipv6_size + 1
   if pkt.data[icmp_code_offset] ~= 0 then return false end

   if target_address_is_multicast(pkt) then return false end
   if not option_lengths_are_nonzero(pkt) then return false end
   local src_addr = pkt.data + ehs + o_ipv6_src_addr
   if ipv6_equals(ipv6_unspecified_addr, src_addr) then
      if ip_dst_is_solicited_node_multicast_address(pkt) then return false end
      if has_src_link_layer_address_option(pkt) then return false end
   end
   return true -- all checks passed
end

--[[Sending this from the main local IPv6 address is ok. The RFC says:

      Source Address
                     An address assigned to the interface from which the
                     advertisement is sent.
--]]
function form_nsolicitation_reply(local_eth, local_ipv6, ns_pkt)
   if not local_eth or not local_ipv6 then return nil end
   if not is_valid_ns(ns_pkt) then return nil end
   return form_sna(local_eth, local_ipv6, true, ns_pkt)
end

local function test_ndp_without_target_link()
   local lib = require("core.lib")
   -- Neighbor Advertisement packet.
   local na_pkt = lib.hexundump([[
      02:aa:aa:aa:aa:aa 90:e2:ba:a9:89:2d 86 dd 60 00 
      00 00 00 18 3a ff fe 80 00 00 00 00 00 00 92 e2 
      ba ff fe a9 89 2d fc 00 00 00 00 00 00 00 00 00 
      00 00 00 00 01 00 88 00 92 36 40 00 00 00 fe 80 
      00 00 00 00 00 00 92 e2 ba ff fe a9 89 2d
   ]], 78)
   local dst_eth = get_dst_ethernet(packet.from_string(na_pkt),
      {ipv6:pton("fe80::92e2:baff:fea9:892d")})
   assert(ethernet:ntop(dst_eth) == "90:e2:ba:a9:89:2d")
end

function selftest()
   print("selftest: ndp")

   local lmac = ethernet:pton("01:02:03:04:05:06")
   local lip = ipv6:pton("1:2:3:4:5:6:7:8")
   local rip = ipv6:pton("9:a:b:c:d:e:f:0")
   local nsp = form_ns(lmac, lip, rip)
   assert(is_ndp(nsp))
   assert(is_solicited_neighbor_advertisement(nsp) == false)
   lwutil.set_dst_ethernet(nsp, lmac) -- Not a meaningful thing to do, just a test
   
   local sol_na = form_nsolicitation_reply(lmac, lip, nsp)
   local dst_eth = get_dst_ethernet(sol_na, {rip})
   assert(ethernet:ntop(dst_eth) == "01:02:03:04:05:06")
   assert(sol_na, "an na packet should have been formed")
   assert(is_ndp(sol_na), "sol_na must be ndp!")
   assert(is_solicited_neighbor_advertisement(sol_na), "sol_na must be sna!")

   test_ndp_without_target_link()

   print("selftest: ok")
end

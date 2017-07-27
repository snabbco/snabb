-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- NDP address resolution (RFC 4861)

-- Given a remote IPv6 address, try to find out its MAC address.
-- If resolution succeeds:
-- All packets coming through the 'south' interface (ie, via the network card)
-- are silently forwarded (unless dropped by the network card).
-- All packets coming through the 'north' interface (the lwaftr) will have
-- their Ethernet headers rewritten.

module(..., package.seeall)

local bit      = require("bit")
local ffi      = require("ffi")
local packet   = require("core.packet")
local link     = require("core.link")
local lib      = require("core.lib")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6     = require("lib.protocol.ipv6")

local constants = require("apps.lwaftr.constants")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")

local C = ffi.C
local htons, ntohs = lib.htons, lib.ntohs
local htonl, ntohl = lib.htonl, lib.ntohl
local receive, transmit = link.receive, link.transmit
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
local o_ipv6_hop_limit = constants.o_ipv6_hop_limit
local o_ethernet_ethertype = constants.o_ethernet_ethertype
local proto_icmpv6 = constants.proto_icmpv6
local icmpv6_na = constants.icmpv6_na
local icmpv6_ns = constants.icmpv6_ns
local n_ethertype_ipv6 = constants.n_ethertype_ipv6
local ethertype_ipv6 = constants.ethertype_ipv6

-- Special addresses
local ipv6_all_nodes_local_segment_addr = ipv6:pton("ff02::1")
local ipv6_unspecified_addr = ipv6:pton("0::0") -- aka ::/128
-- Really just the first 13 bytes of the following...
local ipv6_solicited_multicast = ipv6:pton("ff02:0000:0000:0000:0000:0001:ff00:00")


local ether_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  dhost[6];
   uint8_t  shost[6];
   uint16_t type;
} __attribute__((packed))
]]
local ipv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t v_tc_fl; // version, tc, flow_label
   uint16_t payload_length;
   uint8_t  next_header;
   uint8_t  hop_limit;
   uint8_t  src_ip[16];
   uint8_t  dst_ip[16];
} __attribute__((packed))
]]
local icmpv6_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  type;
   uint8_t  code;
   uint16_t checksum;
} __attribute__((packed))
]]
local na_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t rso_and_reserved;    /* Bit 31: Router; Bit 30: Solicited;
                                    Bit 29: Override; Bits 28-0: Reserved. */
   uint8_t  target_ip[16];
   uint8_t  options[0];
} __attribute__((packed))
]]
local ns_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint32_t reserved;            /* Bits 31-0: Reserved.  */
   uint8_t  target_ip[16];
   uint8_t  options[0];
} __attribute__((packed))
]]
local option_header_t = ffi.typeof [[
/* All values in network byte order.  */
struct {
   uint8_t  type;
   uint8_t  length;
} __attribute__((packed))
]]
local ether_option_header_t = ffi.typeof ([[
/* All values in network byte order.  */
struct {
   $ header;
   uint8_t  addr[6];
} __attribute__((packed))
]], option_header_t)

local ndp_header_t = ffi.typeof([[
struct {
   $ ether;
   $ ipv6;
   $ icmpv6;
   uint8_t body[0];
} __attribute__((packed))]], ether_header_t, ipv6_header_t, icmpv6_header_t)
local ndp_header_len = ffi.sizeof(ndp_header_t)

local function ptr_to(t) return ffi.typeof('$*', t) end
local ndp_header_ptr_t = ptr_to(ndp_header_t)
local na_header_ptr_t = ptr_to(na_header_t)
local ns_header_ptr_t = ptr_to(ns_header_t)
local option_header_ptr_t = ptr_to(option_header_t)
local ether_option_header_ptr_t = ptr_to(ether_option_header_t)

local ether_type_ipv6 = 0x86DD

local na_router_bit = 31
local na_solicited_bit = 30
local na_override_bit = 29

local ipv6_pseudoheader_t = ffi.typeof [[
struct {
   char src_ip[16];
   char dst_ip[16];
   uint32_t ulp_length;
   uint32_t next_header;
} __attribute__((packed))
]]
local function checksum_pseudoheader_from_header(ipv6_fixed_header)
   local ph = ipv6_pseudoheader_t()
   ph.src_ip = ipv6_fixed_header.src_ip
   ph.dst_ip = ipv6_fixed_header.dst_ip
   ph.ulp_length = htonl(ntohs(ipv6_fixed_header.payload_length))
   ph.next_header = htonl(ipv6_fixed_header.next_header)
   return checksum.ipsum(ffi.cast('char*', ph),
                         ffi.sizeof(ipv6_pseudoheader_t), 0)
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


local function is_ndp(pkt)
   if pkt.length < ndp_header_len then return false end
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   if ntohs(h.ether.type) ~= ether_type_ipv6 then return false end
   if h.ipv6.next_header ~= proto_icmpv6 then return false end
   return h.icmpv6.type >= 133 and h.icmpv6.type <= 137
end

-- Check whether NS target address matches IPv6 address.
local function is_neighbor_solicitation_for_addr(pkt, ipv6_addr)
   local target_offset = eth_ipv6_size + o_icmp_target_offset
   local target_ipv6 = pkt.data + target_offset
   return ipv6_equals(target_ipv6, ipv6_addr)
end

local function to_ether_addr(pkt, offset)
   local ether_src = ffi.new("uint8_t[?]", 6)
   ffi.copy(ether_src, pkt.data + offset, 6)
   return ether_src
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


local function form_ns(local_eth, local_ipv6, dst_ipv6)
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
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   local ph_csum = checksum_pseudoheader_from_header(h.ipv6)
   local icmp_length = ntohs(h.ipv6.payload_length)
   local a = checksum.ipsum(ffi.cast('char*', h.icmpv6), icmp_length,
                            bit.bnot(ph_csum))
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
local function form_nsolicitation_reply(local_eth, local_ipv6, ns_pkt)
   if not local_eth or not local_ipv6 then return nil end
   if not is_valid_ns(ns_pkt) then return nil end
   return form_sna(local_eth, local_ipv6, true, ns_pkt)
end

local function random_locally_administered_unicast_mac_address()
   local mac = lib.random_bytes(6)
   -- Bit 0 is 0, indicating unicast.  Bit 1 is 1, indicating locally
   -- administered.
   mac[0] = bit.lshift(mac[0], 2) + 2
   return mac
end

NDP = {}
local ndp_config_params = {
   -- Source MAC address will default to a random address.
   self_mac = { default=false },
   -- Source IP is required though.
   self_ip  = { required=true },
   -- The next-hop MAC address can be statically configured.
   next_mac = { default=false },
   -- But if the next-hop MAC isn't configured, NDP will figure it out.
   next_ip  = { default=false }
}

function NDP:new(conf)
   local o = lib.parse(conf, ndp_config_params)
   if not o.self_mac then
      o.self_mac = random_locally_administered_unicast_mac_address()
   end
   if not o.next_mac then
      assert(o.next_ip, 'NDP needs next-hop IPv6 address to learn next-hop MAC')
      o.ns_pkt = form_ns(o.self_mac, o.self_ip, o.next_ip)
      self.ns_interval = 3 -- Send a new NS every three seconds.
   end
   return setmetatable(o, {__index=NDP})
end

function NDP:maybe_send_ns_request (output)
   if self.next_mac then return end
   self.next_ns_time = self.next_ns_time or engine.now()
   if self.next_ns_time <= engine.now() then
      print(("NDP: Resolving '%s'"):format(ipv6:ntop(self.next_ip)))
      self:send_ns(output)
      self.next_ns_time = engine.now() + self.ns_interval
   end
end

function NDP:send_ns (output)
   transmit(output, packet.clone(self.ns_pkt))
end

function NDP:resolve_next_hop(next_mac)
   print(("NDP: '%s' resolved (%s)"):format(ipv6:ntop(self.next_ip),
                                            ethernet:ntop(next_mac)))
   self.next_mac = next_mac
end

local function copy_mac(src)
   local dst = ffi.new('uint8_t[6]')
   ffi.copy(dst, src, 6)
   return dst
end

function NDP:handle_ndp (pkt)
   local h = ffi.cast(ndp_header_ptr_t, pkt.data)
   if h.icmpv6.type == icmpv6_na then
      -- Only process advertisements when we are looking for a
      -- next-hop MAC.
      if self.next_mac then return end
      -- Drop packets that are too short.
      if pkt.length < ndp_header_len + ffi.sizeof(na_header_t) then return end
      local na = ffi.cast(na_header_ptr_t, h.body)
      local solicited = bit.lshift(1, na_solicited_bit)
      local rso_bits = ntohl(na.rso_and_reserved)
      -- Reject unsolicited advertisements.
      if bit.band(solicited, rso_bits) ~= solicited then return end
      -- We only are looking for the MAC of our next-hop; no others.
      if not ipv6_equals(na.target_ip, self.next_ip) then return end
      -- First try to get the MAC from the options.
      local offset = na.options - pkt.data
      while offset < pkt.length do
         local option = ffi.cast(option_header_ptr_t, pkt.data + offset)
         if option.length == 0 then return end
         if offset + option.length*8 > pkt.length then return end
         offset = offset + option.length*8
         if option.type == option_target_link_layer_address then
            if option.length ~= 1 then return end
            local ether = ffi.cast(ether_option_header_ptr_t, option)
            self:resolve_next_hop(copy_mac(ether.addr))
            return
         end
      end
      -- Otherwise, when responding to unicast solicitations, the
      -- option can be omitted since the sender of the solicitation
      -- has the correct link-layer address.  See 4.4. Neighbor
      -- Advertisement Message Format.
      self:resolve_next_hop(copy_mac(h.ether.shost))
   elseif h.icmpv6.type == icmpv6_ns then
      if is_neighbor_solicitation_for_addr(pkt, self.self_ip) then
         local snap = form_nsolicitation_reply(self.self_mac, self.self_ip, pkt)
         if snap then 
            link.transmit(self.output.south, snap)
         end
      end
   else
      -- Unhandled NDP packet; silently drop.
      return
   end
end

function NDP:push()
   local isouth, osouth = self.input.south, self.output.south
   local inorth, onorth = self.input.north, self.output.north

   -- TODO: do unsolicited neighbor advertisement on start and on
   -- configuration reloads?
   -- This would be an optimization, not a correctness issue
   self:maybe_send_ns_request(osouth)

   for _ = 1, link.nreadable(isouth) do
      local p = receive(isouth)
      if is_ndp(p) then
         self:handle_ndp(p)
         packet.free(p)
      else
         transmit(onorth, p)
      end
   end

   for _ = 1, link.nreadable(inorth) do
      local p = receive(inorth)
      if not self.next_mac then
         -- drop all southbound packets until the next hop's ethernet address is known
         packet.free(p)
      else
         ffi.copy(p.data, self.next_mac, 6)
         ffi.copy(p.data + 6, self.self_mac, 6)
         transmit(osouth, p)
      end
   end
end

function selftest()
   print("selftest: ndp")

   local config = require("core.config")
   local sink = require("apps.basic.basic_apps").Sink
   local c = config.new()
   config.app(c, "nd1", NDP, { self_ip  = ipv6:pton("2001:DB8::1"),
                               next_ip  = ipv6:pton("2001:DB8::2") })
   config.app(c, "nd2", NDP, { self_ip  = ipv6:pton("2001:DB8::2"),
                               next_ip  = ipv6:pton("2001:DB8::1") })
   config.app(c, "sink1", sink)
   config.app(c, "sink2", sink)
   config.link(c, "nd1.south -> nd2.south")
   config.link(c, "nd2.south -> nd1.south")
   config.link(c, "sink1.tx -> nd1.north")
   config.link(c, "nd1.north -> sink1.rx")
   config.link(c, "sink2.tx -> nd2.north")
   config.link(c, "nd2.north -> sink2.rx")
   engine.configure(c)
   engine.main({ duration = 0.1 })

   local function mac_eq(a, b) return C.memcmp(a, b, 6) == 0 end
   local nd1, nd2 = engine.app_table.nd1, engine.app_table.nd2
   assert(mac_eq(nd1.next_mac, nd2.self_mac))
   assert(mac_eq(nd2.next_mac, nd1.self_mac))

   print("selftest: ok")
end

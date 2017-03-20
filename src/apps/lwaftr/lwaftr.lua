module(..., package.seeall)

local bt = require("apps.lwaftr.binding_table")
local constants = require("apps.lwaftr.constants")
local icmp = require("apps.lwaftr.icmp")
local lwcounter = require("apps.lwaftr.lwcounter")
local lwdebug = require("apps.lwaftr.lwdebug")
local lwheader = require("apps.lwaftr.lwheader")
local lwutil = require("apps.lwaftr.lwutil")

local checksum = require("lib.checksum")
local ethernet = require("lib.protocol.ethernet")
local counter = require("core.counter")
local packet = require("core.packet")
local lib = require("core.lib")
local link = require("core.link")
local engine = require("core.app")
local bit = require("bit")

local band, bnot = bit.band, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local receive, transmit = link.receive, link.transmit
local rd16, wr16, rd32, ipv6_equals = lwutil.rd16, lwutil.wr16, lwutil.rd32, lwutil.ipv6_equals
local is_ipv4, is_ipv6 = lwutil.is_ipv4, lwutil.is_ipv6
local htons, ntohs, ntohl = lib.htons, lib.ntohs, lib.ntohl
local write_eth_header, write_ipv6_header = lwheader.write_eth_header, lwheader.write_ipv6_header
local is_ipv4_fragment, is_ipv6_fragment = lwutil.is_ipv4_fragment, lwutil.is_ipv6_fragment

-- Note whether an IPv4 packet is actually coming from the internet, or from
-- a b4 and hairpinned to be re-encapsulated in another IPv6 packet.
local PKT_FROM_INET = 1
local PKT_HAIRPINNED = 2

local debug = lib.getenv("LWAFTR_DEBUG")

-- Local bindings for constants that are used in the hot path of the
-- data plane.  Not having them here is a 1-2% performance penalty.
local ethernet_header_size = constants.ethernet_header_size
local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local n_ethertype_ipv6 = constants.n_ethertype_ipv6

local function get_ethernet_payload(pkt)
   return pkt.data + ethernet_header_size
end
local function get_ethernet_payload_length(pkt)
   return pkt.length - ethernet_header_size
end

local o_ipv4_checksum = constants.o_ipv4_checksum
local o_ipv4_dscp_and_ecn = constants.o_ipv4_dscp_and_ecn
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr
local o_ipv4_flags = constants.o_ipv4_flags
local o_ipv4_proto = constants.o_ipv4_proto
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local o_ipv4_total_length = constants.o_ipv4_total_length
local o_ipv4_ttl = constants.o_ipv4_ttl

local function get_ipv4_header_length(ptr)
   local ver_and_ihl = ptr[0]
   return lshift(band(ver_and_ihl, 0xf), 2)
end
local function get_ipv4_total_length(ptr)
   return ntohs(rd16(ptr + o_ipv4_total_length))
end
local function get_ipv4_src_address_ptr(ptr)
   return ptr + o_ipv4_src_addr
end
local function get_ipv4_dst_address_ptr(ptr)
   return ptr + o_ipv4_dst_addr
end
local function get_ipv4_src_address(ptr)
   return ntohl(rd32(get_ipv4_src_address_ptr(ptr)))
end
local function get_ipv4_dst_address(ptr)
   return ntohl(rd32(get_ipv4_dst_address_ptr(ptr)))
end
local function get_ipv4_proto(ptr)
   return ptr[o_ipv4_proto]
end
local function get_ipv4_flags(ptr)
   return ptr[o_ipv4_flags]
end
local function get_ipv4_dscp_and_ecn(ptr)
   return ptr[o_ipv4_dscp_and_ecn]
end
local function get_ipv4_payload(ptr)
   return ptr + get_ipv4_header_length(ptr)
end
local function get_ipv4_payload_src_port(ptr)
   -- Assumes that the packet is TCP or UDP.
   return ntohs(rd16(get_ipv4_payload(ptr)))
end
local function get_ipv4_payload_dst_port(ptr)
   -- Assumes that the packet is TCP or UDP.
   return ntohs(rd16(get_ipv4_payload(ptr) + 2))
end

local ipv6_fixed_header_size = constants.ipv6_fixed_header_size
local o_ipv6_dst_addr = constants.o_ipv6_dst_addr
local o_ipv6_next_header = constants.o_ipv6_next_header
local o_ipv6_src_addr = constants.o_ipv6_src_addr

local function get_ipv6_src_address(ptr)
   return ptr + o_ipv6_src_addr
end
local function get_ipv6_dst_address(ptr)
   return ptr + o_ipv6_dst_addr
end
local function get_ipv6_next_header(ptr)
   return ptr[o_ipv6_next_header]
end
local function get_ipv6_payload(ptr)
   -- FIXME: Deal with multiple IPv6 headers?
   return ptr + ipv6_fixed_header_size
end

local proto_icmp = constants.proto_icmp
local proto_icmpv6 = constants.proto_icmpv6
local proto_ipv4 = constants.proto_ipv4

local function get_icmp_type(ptr)
   return ptr[0]
end
local function get_icmp_code(ptr)
   return ptr[1]
end
local function get_icmpv4_echo_identifier(ptr)
   return ntohs(rd16(ptr + constants.o_icmpv4_echo_identifier))
end
local function get_icmp_mtu(ptr)
   local next_hop_mtu_offset = 6
   return ntohs(rd16(ptr + next_hop_mtu_offset))
end
local function get_icmp_payload(ptr)
   return ptr + constants.icmp_base_size
end

-- This function converts between IPv4-as-host-uint32 and IPv4 as
-- uint8_t[4].  It's a stopgap measure; really the rest of the code
-- should be converted to use IPv4-as-host-uint32.
local function convert_ipv4(addr)
   local str = require('lib.yang.util').ipv4_ntop(addr)
   return require('lib.protocol.ipv4'):pton(str)
end

local function drop(pkt)
   packet.free(pkt)
end

local function drop_ipv4(lwstate, pkt, pkt_src_link)
   if pkt_src_link == PKT_FROM_INET then
      counter.add(lwstate.counters["drop-all-ipv4-iface-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-all-ipv4-iface-packets"])
   elseif pkt_src_link == PKT_HAIRPINNED then
      -- B4s emit packets with no IPv6 extension headers.
      local orig_packet_len = pkt.length + ipv6_fixed_header_size
      counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], orig_packet_len)
      counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
   else
      assert(false, "Programming error, bad pkt_src_link: " .. pkt_src_link)
   end
   return drop(pkt)
end

local function init_transmit_icmpv6_reply (rate_limiting)
   local num_packets = 0
   local last_time
   return function (lwstate, pkt)
      local now = tonumber(engine.now())
      last_time = last_time or now
      -- Reset if elapsed time reached.
      if now - last_time >= rate_limiting.period then
         last_time = now
         num_packets = 0
      end
      -- Send packet if limit not reached.
      if num_packets < rate_limiting.packets then
         num_packets = num_packets + 1
         counter.add(lwstate.counters["out-icmpv6-bytes"], pkt.length)
         counter.add(lwstate.counters["out-icmpv6-packets"])
         counter.add(lwstate.counters["out-ipv6-bytes"], pkt.length)
         counter.add(lwstate.counters["out-ipv6-packets"])
         return transmit(lwstate.o6, pkt)
      else
         counter.add(lwstate.counters["drop-over-rate-limit-icmpv6-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-over-rate-limit-icmpv6-packets"])
         return drop(pkt)
      end
   end
end

local function ipv4_in_binding_table (lwstate, ip)
   return lwstate.binding_table:is_managed_ipv4_address(ip)
end

local function init_transmit_icmpv4_reply (rate_limiting)
   local num_packets = 0
   local last_time
   return function (lwstate, pkt, orig_pkt, orig_pkt_link)
      local now = tonumber(engine.now())
      last_time = last_time or now
      -- Reset if elapsed time reached.
      if now - last_time >= rate_limiting.period then
         last_time = now
         num_packets = 0
      end
      -- Origin packet is always dropped.
      if orig_pkt_link then
         drop_ipv4(lwstate, orig_pkt, orig_pkt_link)
      else
         drop(orig_pkt)
      end
      -- Send packet if limit not reached.
      if num_packets < rate_limiting.packets then
         num_packets = num_packets + 1
         counter.add(lwstate.counters["out-icmpv4-bytes"], pkt.length)
         counter.add(lwstate.counters["out-icmpv4-packets"])
         -- Only locally generated error packets are handled here.  We transmit
         -- them right away, instead of calling transmit_ipv4, because they are
         -- never hairpinned and should not be counted by the "out-ipv4" counter.
         -- However, they should be tunneled if the error is to be sent to a host
         -- behind a B4, whether or not hairpinning is enabled; this is not hairpinning.
         -- ... and the tunneling should happen via the 'hairpinning' queue, to make
         -- sure counters are handled appropriately, despite this not being hairpinning.
         -- This avoids having phantom incoming IPv4 packets.
         local ipv4_header = get_ethernet_payload(pkt)
         local dst_ip = get_ipv4_dst_address(ipv4_header)
         if ipv4_in_binding_table(lwstate, dst_ip) then
            return transmit(lwstate.input.hairpin_in, pkt)
         else
            counter.add(lwstate.counters["out-ipv4-bytes"], pkt.length)
            counter.add(lwstate.counters["out-ipv4-packets"])
            return transmit(lwstate.o4, pkt)
         end
      else
         return drop(pkt)
      end
   end
end

LwAftr = { yang_schema = 'snabb-softwire-v1' }

function LwAftr:new(conf)
   if conf.debug then debug = true end
   local o = setmetatable({}, {__index=LwAftr})
   conf = conf.softwire_config
   o.conf = conf

   o.binding_table = bt.load(conf.binding_table)
   o.inet_lookup_queue = bt.BTLookupQueue.new(o.binding_table)
   o.hairpin_lookup_queue = bt.BTLookupQueue.new(o.binding_table)

   if not conf.internal_interface.next_hop.mac then
      conf.internal_interface.next_hop.mac = ethernet:pton('00:00:00:00:00:00')
   end
   if not conf.external_interface.next_hop.mac then
      conf.external_interface.next_hop.mac = ethernet:pton('00:00:00:00:00:00')
   end

   o.counters = lwcounter.init_counters()

   o.transmit_icmpv6_reply = init_transmit_icmpv6_reply(
      conf.internal_interface.error_rate_limiting)
   o.transmit_icmpv4_reply = init_transmit_icmpv4_reply(
      conf.external_interface.error_rate_limiting)
   if debug then lwdebug.pp(conf) end
   return o
end

-- The following two methods are called by apps.config.follower in
-- reaction to binding table changes, via
-- apps/config/support/snabb-softwire-v1.lua.
function LwAftr:add_softwire_entry(entry_blob)
   self.binding_table:add_softwire_entry(entry_blob)
end
function LwAftr:remove_softwire_entry(entry_key_blob)
   self.binding_table:remove_softwire_entry(entry_key_blob)
end

local function decrement_ttl(pkt)
   local ipv4_header = get_ethernet_payload(pkt)
   local chksum = bnot(ntohs(rd16(ipv4_header + o_ipv4_checksum)))
   local old_ttl = ipv4_header[o_ipv4_ttl]
   if old_ttl == 0 then return 0 end
   local new_ttl = band(old_ttl - 1, 0xff)
   ipv4_header[o_ipv4_ttl] = new_ttl
   -- Now fix up the checksum.  o_ipv4_ttl is the first byte in the
   -- 16-bit big-endian word, so the difference to the overall sum is
   -- multiplied by 0xff.
   chksum = chksum + lshift(new_ttl - old_ttl, 8)
   -- Now do the one's complement 16-bit addition of the 16-bit words of
   -- the checksum, which necessarily is a 32-bit value.  Two carry
   -- iterations will suffice.
   chksum = band(chksum, 0xffff) + rshift(chksum, 16)
   chksum = band(chksum, 0xffff) + rshift(chksum, 16)
   wr16(ipv4_header + o_ipv4_checksum, htons(bnot(chksum)))
   return new_ttl
end

-- Hairpinned packets need to be handled quite carefully. We've decided they:
-- * should increment hairpin-ipv4-bytes and hairpin-ipv4-packets
-- * should increment [in|out]-ipv6-[bytes|packets]
-- * should NOT increment  [in|out]-ipv4-[bytes|packets]
-- The latter is because decapsulating and re-encapsulating them via IPv4
-- packets is an internal implementation detail that DOES NOT go out over
-- physical wires.
-- Not incrementing out-ipv4-bytes and out-ipv4-packets is straightforward.
-- Not incrementing in-ipv4-[bytes|packets] is harder. The easy way would be
-- to add extra flags and conditionals, but it's expected that a high enough
-- percentage of traffic might be hairpinned that this could be problematic,
-- (and a nightmare as soon as we add any kind of parallelism)
-- so instead we speculatively decrement the counters here.
-- It is assumed that any packet we transmit to lwstate.input.v4 will not
-- be dropped before the in-ipv4-[bytes|packets] counters are incremented;
-- I *think* this approach bypasses using the physical NIC but am not
-- absolutely certain.
local function transmit_ipv4(lwstate, pkt)
   local ipv4_header = get_ethernet_payload(pkt)
   local dst_ip = get_ipv4_dst_address(ipv4_header)
   if (lwstate.conf.internal_interface.hairpinning and
       ipv4_in_binding_table(lwstate, dst_ip)) then
      -- The destination address is managed by the lwAFTR, so we need to
      -- hairpin this packet.  Enqueue on the IPv4 interface, as if it
      -- came from the internet.
      counter.add(lwstate.counters["hairpin-ipv4-bytes"], pkt.length)
      counter.add(lwstate.counters["hairpin-ipv4-packets"])
      return transmit(lwstate.input.hairpin_in, pkt)
   else
      counter.add(lwstate.counters["out-ipv4-bytes"], pkt.length)
      counter.add(lwstate.counters["out-ipv4-packets"])
      return transmit(lwstate.o4, pkt)
   end
end

-- ICMPv4 type 3 code 1, as per RFC 7596.
-- The target IPv4 address + port is not in the table.
local function drop_ipv4_packet_to_unreachable_host(lwstate, pkt, pkt_src_link)
   counter.add(lwstate.counters["drop-no-dest-softwire-ipv4-bytes"], pkt.length)
   counter.add(lwstate.counters["drop-no-dest-softwire-ipv4-packets"])

   if not lwstate.conf.external_interface.generate_icmp_errors then
      -- ICMP error messages off by policy; silently drop.
      -- Not counting bytes because we do not even generate the packets.
      counter.add(lwstate.counters["drop-out-by-policy-icmpv4-packets"])
      return drop_ipv4(lwstate, pkt, pkt_src_link)
   end

   if get_ipv4_proto(get_ethernet_payload(pkt)) == proto_icmp then
      -- RFC 7596 section 8.1 requires us to silently drop incoming
      -- ICMPv4 messages that don't match the binding table.
      counter.add(lwstate.counters["drop-in-by-rfc7596-icmpv4-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-in-by-rfc7596-icmpv4-packets"])
      return drop_ipv4(lwstate, pkt, pkt_src_link)
   end

   local ipv4_header = get_ethernet_payload(pkt)
   local to_ip = get_ipv4_src_address_ptr(ipv4_header)
   local icmp_config = {
      type = constants.icmpv4_dst_unreachable,
      code = constants.icmpv4_host_unreachable,
   }
   local icmp_dis = icmp.new_icmpv4_packet(
      lwstate.conf.external_interface.mac,
      lwstate.conf.external_interface.next_hop.mac,
      convert_ipv4(lwstate.conf.external_interface.ip),
      to_ip, pkt, icmp_config)

   return lwstate:transmit_icmpv4_reply(icmp_dis, pkt, pkt_src_link)
end

-- ICMPv6 type 1 code 5, as per RFC 7596.
-- The source (ipv6, ipv4, port) tuple is not in the table.
local function drop_ipv6_packet_from_bad_softwire(lwstate, pkt, br_addr)
   if not lwstate.conf.internal_interface.generate_icmp_errors then
      -- ICMP error messages off by policy; silently drop.
      -- Not counting bytes because we do not even generate the packets.
      counter.add(lwstate.counters["drop-out-by-policy-icmpv6-packets"])
      return drop(pkt)
   end

   local ipv6_header = get_ethernet_payload(pkt)
   local orig_src_addr_icmp_dst = get_ipv6_src_address(ipv6_header)
   -- If br_addr is specified, use that as the source addr. Otherwise, send it
   -- back from the IPv6 address it was sent to.
   local icmpv6_src_addr = br_addr or get_ipv6_dst_address(ipv6_header)
   local icmp_config = {type = constants.icmpv6_dst_unreachable,
                        code = constants.icmpv6_failed_ingress_egress_policy,
                       }
   local b4fail_icmp = icmp.new_icmpv6_packet(
      lwstate.conf.internal_interface.mac,
      lwstate.conf.internal_interface.next_hop.mac,
      icmpv6_src_addr, orig_src_addr_icmp_dst, pkt, icmp_config)
   drop(pkt)
   lwstate:transmit_icmpv6_reply(b4fail_icmp)
end

local function encapsulating_packet_with_df_flag_would_exceed_mtu(lwstate, pkt)
   local payload_length = get_ethernet_payload_length(pkt)
   local mtu = lwstate.conf.internal_interface.mtu
   if payload_length + ipv6_fixed_header_size <= mtu then
      -- Packet will not exceed MTU.
      return false
   end
   -- The result would exceed the IPv6 MTU; signal an error via ICMPv4 if
   -- the IPv4 fragment has the DF flag.
   return band(get_ipv4_flags(get_ethernet_payload(pkt)), 0x40) == 0x40
end

local function cannot_fragment_df_packet_error(lwstate, pkt)
   -- According to RFC 791, the original packet must be discarded.
   -- Return a packet with ICMP(3, 4) and the appropriate MTU
   -- as per https://tools.ietf.org/html/rfc2473#section-7.2
   if debug then lwdebug.print_pkt(pkt) end
   -- The ICMP packet should be set back to the packet's source.
   local dst_ip = get_ipv4_src_address_ptr(get_ethernet_payload(pkt))
   local mtu = lwstate.conf.internal_interface.mtu
   local icmp_config = {
      type = constants.icmpv4_dst_unreachable,
      code = constants.icmpv4_datagram_too_big_df,
      extra_payload_offset = 0,
      next_hop_mtu = mtu - constants.ipv6_fixed_header_size,
   }
   return icmp.new_icmpv4_packet(
      lwstate.conf.external_interface.mac,
      lwstate.conf.external_interface.next_hop.mac,
      convert_ipv4(lwstate.conf.external_interface.ip),
      dst_ip, pkt, icmp_config)
end

local function encapsulate_and_transmit(lwstate, pkt, ipv6_dst, ipv6_src, pkt_src_link)
   -- Do not encapsulate packets that now have a ttl of zero or wrapped around
   local ttl = decrement_ttl(pkt)
   if ttl == 0 then
      counter.add(lwstate.counters["drop-ttl-zero-ipv4-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-ttl-zero-ipv4-packets"])
      if not lwstate.conf.external_interface.generate_icmp_errors then
         -- Not counting bytes because we do not even generate the packets.
         counter.add(lwstate.counters["drop-out-by-policy-icmpv4-packets"])
         return drop_ipv4(lwstate, pkt, pkt_src_link)
      end
      local ipv4_header = get_ethernet_payload(pkt)
      local dst_ip = get_ipv4_src_address_ptr(ipv4_header)
      local icmp_config = {type = constants.icmpv4_time_exceeded,
                           code = constants.icmpv4_ttl_exceeded_in_transit,
                           }
      local reply = icmp.new_icmpv4_packet(
         lwstate.conf.external_interface.mac,
         lwstate.conf.external_interface.next_hop.mac,
         convert_ipv4(lwstate.conf.external_interface.ip),
         dst_ip, pkt, icmp_config)

      return lwstate:transmit_icmpv4_reply(reply, pkt, pkt_src_link)
   end

   if debug then print("ipv6", ipv6_src, ipv6_dst) end

   local next_hdr_type = proto_ipv4
   local ether_src = lwstate.conf.internal_interface.mac
   local ether_dst = lwstate.conf.internal_interface.next_hop.mac

   if encapsulating_packet_with_df_flag_would_exceed_mtu(lwstate, pkt) then
      counter.add(lwstate.counters["drop-over-mtu-but-dont-fragment-ipv4-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-over-mtu-but-dont-fragment-ipv4-packets"])
      if not lwstate.conf.external_interface.generate_icmp_errors then
         -- Not counting bytes because we do not even generate the packets.
         counter.add(lwstate.counters["drop-out-by-policy-icmpv4-packets"])
         return drop_ipv4(lwstate, pkt, pkt_src_link)
      end
      local reply = cannot_fragment_df_packet_error(lwstate, pkt)
      return lwstate:transmit_icmpv4_reply(reply, pkt, pkt_src_link)
   end

   local payload_length = get_ethernet_payload_length(pkt)
   local l3_header = get_ethernet_payload(pkt)
   local dscp_and_ecn = get_ipv4_dscp_and_ecn(l3_header)
   -- Note that this may invalidate any pointer into pkt.data.  Be warned!
   pkt = packet.shiftright(pkt, ipv6_fixed_header_size)
   -- Fetch possibly-moved L3 header location.
   l3_header = get_ethernet_payload(pkt)
   write_eth_header(pkt.data, ether_src, ether_dst, n_ethertype_ipv6)
   write_ipv6_header(l3_header, ipv6_src, ipv6_dst,
                     dscp_and_ecn, next_hdr_type, payload_length)

   if debug then
      print("encapsulated packet:")
      lwdebug.print_pkt(pkt)
   end

   counter.add(lwstate.counters["out-ipv6-bytes"], pkt.length)
   counter.add(lwstate.counters["out-ipv6-packets"])
   return transmit(lwstate.o6, pkt)
end

local function select_lookup_queue(lwstate, src_link)
   if src_link == PKT_FROM_INET then
      return lwstate.inet_lookup_queue
   elseif src_link == PKT_HAIRPINNED then
      return lwstate.hairpin_lookup_queue
   end
   assert(false, "Programming error, bad link: " .. link)
end

local function enqueue_lookup(lwstate, pkt, ipv4, port, flush, lq)
   if lq:enqueue_lookup(pkt, ipv4, port) then
      -- Flush the queue right away if enough packets are queued up already.
      flush(lwstate)
   end
end

local function flush_hairpin(lwstate)
   local lq = lwstate.hairpin_lookup_queue
   lq:process_queue()
   for n = 0, lq.length - 1 do
      local pkt, ipv6_dst, ipv6_src = lq:get_lookup(n)
      if ipv6_dst then
         encapsulate_and_transmit(lwstate, pkt, ipv6_dst, ipv6_src, PKT_HAIRPINNED)
      else
         -- Lookup failed. This can happen even with hairpinned packets, if
         -- the binding table changes between destination lookups.
         -- Count the original IPv6 packet as dropped, not the hairpinned one.
         if debug then print("lookup failed") end
         drop_ipv4_packet_to_unreachable_host(lwstate, pkt, PKT_HAIRPINNED)
      end
   end
   lq:reset_queue()
end

local function flush_encapsulation(lwstate)
   local lq = lwstate.inet_lookup_queue
   lq:process_queue()
   for n = 0, lq.length - 1 do
      local pkt, ipv6_dst, ipv6_src = lq:get_lookup(n)
      if ipv6_dst then
         encapsulate_and_transmit(lwstate, pkt, ipv6_dst, ipv6_src, PKT_FROM_INET)
      else
         -- Lookup failed.
         if debug then print("lookup failed") end
         drop_ipv4_packet_to_unreachable_host(lwstate, pkt, PKT_FROM_INET)
      end
   end
   lq:reset_queue()
end

local function enqueue_encapsulation(lwstate, pkt, ipv4, port, pkt_src_link)
   local lq = select_lookup_queue(lwstate, pkt_src_link)
   local flush = lq == lwstate.inet_lookup_queue and flush_encapsulation or flush_hairpin
   enqueue_lookup(lwstate, pkt, ipv4, port, flush, lq)
end

local function icmpv4_incoming(lwstate, pkt, pkt_src_link)
   local ipv4_header = get_ethernet_payload(pkt)
   local ipv4_header_size = get_ipv4_header_length(ipv4_header)
   local icmp_header = get_ipv4_payload(ipv4_header)
   local icmp_type = get_icmp_type(icmp_header)

   -- RFC 7596 is silent on whether to validate echo request/reply checksums.
   -- ICMP checksums SHOULD be validated according to RFC 5508.
   -- Choose to verify the echo reply/request ones too.
   -- Note: the lwaftr SHOULD NOT validate the transport checksum of the embedded packet.
   -- Were it to nonetheless do so, RFC 4884 extension headers MUST NOT
   -- be taken into account when validating the checksum
   local icmp_bytes = get_ipv4_total_length(ipv4_header) - ipv4_header_size
   if checksum.ipsum(icmp_header, icmp_bytes, 0) ~= 0 then
      -- Silently drop the packet, as per RFC 5508
      counter.add(lwstate.counters["drop-bad-checksum-icmpv4-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-bad-checksum-icmpv4-packets"])
      return drop_ipv4(lwstate, pkt, pkt_src_link)
   end

   local ipv4_dst = get_ipv4_dst_address(ipv4_header)
   local port

   -- checksum was ok
   if icmp_type == constants.icmpv4_echo_request then
      -- For an incoming ping from the IPv4 internet, assume port == 0
      -- for the purposes of looking up a softwire in the binding table.
      -- This will allow ping to a B4 on an IPv4 without port sharing.
      -- It also has the nice property of causing a drop if the IPv4 has
      -- any reserved ports.
      --
      -- RFC 7596 section 8.1 seems to suggest that we should use the
      -- echo identifier for this purpose, but that only makes sense for
      -- echo requests originating from a B4, to identify the softwire
      -- of the source.  It can't identify a destination softwire.  This
      -- makes sense because you can't really "ping" a port-restricted
      -- IPv4 address.
      port = 0
   elseif icmp_type == constants.icmpv4_echo_reply then
      -- A reply to a ping that originally issued from a subscriber on
      -- the B4 side; the B4 set the port in the echo identifier, as per
      -- RFC 7596, section 8.1, so use that to look up the destination
      -- softwire.
      port = get_icmpv4_echo_identifier(icmp_header)
   else
      -- As per REQ-3, use the ip address embedded in the ICMP payload,
      -- assuming that the payload is shaped like TCP or UDP with the
      -- ports first.
      local embedded_ipv4_header = get_icmp_payload(icmp_header)
      port = get_ipv4_payload_src_port(embedded_ipv4_header)
   end

   return enqueue_encapsulation(lwstate, pkt, ipv4_dst, port, pkt_src_link)
end

-- The incoming packet is a complete one with ethernet headers.
-- FIXME: Verify that the total_length declared in the packet is correct.
local function from_inet(lwstate, pkt, pkt_src_link)
   -- Check incoming ICMP -first-, because it has different binding table lookup logic
   -- than other protocols.
   local ipv4_header = get_ethernet_payload(pkt)
   if get_ipv4_proto(ipv4_header) == proto_icmp then
      if not lwstate.conf.external_interface.allow_incoming_icmp then
         counter.add(lwstate.counters["drop-in-by-policy-icmpv4-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-in-by-policy-icmpv4-packets"])
         return drop_ipv4(lwstate, pkt, pkt_src_link)
      else
         return icmpv4_incoming(lwstate, pkt, pkt_src_link)
      end
   end

   -- If fragmentation support is enabled, the lwAFTR never receives fragments.
   -- If it does, fragment support is disabled and it should drop them.
   if is_ipv4_fragment(pkt) then
      counter.add(lwstate.counters["drop-ipv4-frag-disabled"])
      return drop_ipv4(lwstate, pkt, pkt_src_link)
   end
   -- It's not incoming ICMP.  Assume we can find ports in the IPv4
   -- payload, as in TCP and UDP.  We could check strictly for TCP/UDP,
   -- but that would filter out similarly-shaped protocols like SCTP, so
   -- we optimistically assume that the incoming traffic has the right
   -- shape.
   local dst_ip = get_ipv4_dst_address(ipv4_header)
   local dst_port = get_ipv4_payload_dst_port(ipv4_header)

   return enqueue_encapsulation(lwstate, pkt, dst_ip, dst_port, pkt_src_link)
end

local function tunnel_unreachable(lwstate, pkt, code, next_hop_mtu)
   local ipv6_header = get_ethernet_payload(pkt)
   local icmp_header = get_ipv6_payload(ipv6_header)
   local embedded_ipv6_header = get_icmp_payload(icmp_header)
   local embedded_ipv4_header = get_ipv6_payload(embedded_ipv6_header)

   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = code,
                        extra_payload_offset = embedded_ipv4_header - ipv6_header,
                        next_hop_mtu = next_hop_mtu
                        }
   local dst_ip = get_ipv4_src_address_ptr(embedded_ipv4_header)
   local icmp_reply = icmp.new_icmpv4_packet(
      lwstate.conf.external_interface.mac,
      lwstate.conf.external_interface.next_hop.mac,
      convert_ipv4(lwstate.conf.external_interface.ip),
      dst_ip, pkt, icmp_config)
   return icmp_reply
end

-- FIXME: Verify that the softwire is in the the binding table.
local function icmpv6_incoming(lwstate, pkt)
   local ipv6_header = get_ethernet_payload(pkt)
   local icmp_header = get_ipv6_payload(ipv6_header)
   local icmp_type = get_icmp_type(icmp_header)
   local icmp_code = get_icmp_code(icmp_header)
   if icmp_type == constants.icmpv6_packet_too_big then
      if icmp_code ~= constants.icmpv6_code_packet_too_big then
         -- Invalid code.
         counter.add(lwstate.counters["drop-too-big-type-but-not-code-icmpv6-bytes"],
            pkt.length)
         counter.add(lwstate.counters["drop-too-big-type-but-not-code-icmpv6-packets"])
         counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
         return drop(pkt)
      end
      local mtu = get_icmp_mtu(icmp_header) - constants.ipv6_fixed_header_size
      local reply = tunnel_unreachable(lwstate, pkt,
                                       constants.icmpv4_datagram_too_big_df,
                                       mtu)
      return lwstate:transmit_icmpv4_reply(reply, pkt)
   -- Take advantage of having already checked for 'packet too big' (2), and
   -- unreachable node/hop limit exceeded/paramater problem being 1, 3, 4 respectively
   elseif icmp_type <= constants.icmpv6_parameter_problem then
      -- If the time limit was exceeded, require it was a hop limit code
      if icmp_type == constants.icmpv6_time_limit_exceeded then
         if icmp_code ~= constants.icmpv6_hop_limit_exceeded then
            counter.add(lwstate.counters[
               "drop-over-time-but-not-hop-limit-icmpv6-bytes"], pkt.length)
            counter.add(
               lwstate.counters["drop-over-time-but-not-hop-limit-icmpv6-packets"])
            counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
            counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
            return drop(pkt)
         end
      end
      -- Accept all unreachable or parameter problem codes
      local reply = tunnel_unreachable(lwstate, pkt,
                                       constants.icmpv4_host_unreachable)
      return lwstate:transmit_icmpv4_reply(reply, pkt)
   else
      -- No other types of ICMPv6, including echo request/reply, are
      -- handled.
      counter.add(lwstate.counters["drop-unknown-protocol-icmpv6-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-unknown-protocol-icmpv6-packets"])
      counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
      return drop(pkt)
   end
end

local function flush_decapsulation(lwstate)
   local lq = lwstate.inet_lookup_queue
   lq:process_queue()
   for n = 0, lq.length - 1 do
      local pkt, b4_addr, br_addr = lq:get_lookup(n)

      local ipv6_header = get_ethernet_payload(pkt)
      if (b4_addr
          and ipv6_equals(get_ipv6_src_address(ipv6_header), b4_addr)
          and ipv6_equals(get_ipv6_dst_address(ipv6_header), br_addr)) then
         -- Source softwire is valid; decapsulate and forward.
         -- Note that this may invalidate any pointer into pkt.data.  Be warned!
         pkt = packet.shiftleft(pkt, ipv6_fixed_header_size)
         write_eth_header(
            pkt.data,
            lwstate.conf.external_interface.mac,
            lwstate.conf.external_interface.next_hop.mac,
            n_ethertype_ipv4)
         transmit_ipv4(lwstate, pkt)
      else
         counter.add(lwstate.counters["drop-no-source-softwire-ipv6-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-no-source-softwire-ipv6-packets"])
         counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
         drop_ipv6_packet_from_bad_softwire(lwstate, pkt, br_addr)
      end
   end
   lq:reset_queue()
end

local function enqueue_decapsulation(lwstate, pkt, ipv4, port)
   enqueue_lookup(lwstate, pkt, ipv4, port, flush_decapsulation, lwstate.inet_lookup_queue)
end

-- FIXME: Verify that the packet length is big enough?
local function from_b4(lwstate, pkt)
   -- If fragmentation support is enabled, the lwAFTR never receives fragments.
   -- If it does, fragment support is disabled and it should drop them.
   if is_ipv6_fragment(pkt) then
      counter.add(lwstate.counters["drop-ipv6-frag-disabled"])
      counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
      counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
      return drop(pkt)
   end
   local ipv6_header = get_ethernet_payload(pkt)
   local proto = get_ipv6_next_header(ipv6_header)

   if proto ~= proto_ipv4 then
      if proto == proto_icmpv6 then
         if not lwstate.conf.internal_interface.allow_incoming_icmp then
            counter.add(lwstate.counters["drop-in-by-policy-icmpv6-bytes"], pkt.length)
            counter.add(lwstate.counters["drop-in-by-policy-icmpv6-packets"])
            counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
            counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
            return drop(pkt)
         else
            return icmpv6_incoming(lwstate, pkt)
         end
      else
         -- Drop packet with unknown protocol.
         counter.add(lwstate.counters["drop-unknown-protocol-ipv6-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-unknown-protocol-ipv6-packets"])
         counter.add(lwstate.counters["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(lwstate.counters["drop-all-ipv6-iface-packets"])
         return drop(pkt)
      end
   end

   local tunneled_ipv4_header = get_ipv6_payload(ipv6_header)
   local port
   if get_ipv4_proto(tunneled_ipv4_header) == proto_icmp then
      local icmp_header = get_ipv4_payload(tunneled_ipv4_header)
      local icmp_type = get_icmp_type(icmp_header)
      if icmp_type == constants.icmpv4_echo_request then
         -- A ping going out from the B4 to the internet; the B4 will
         -- encode a port in its range into the echo identifier, as per
         -- RFC 7596 section 8.
         port = get_icmpv4_echo_identifier(icmp_header)
      elseif icmp_type == constants.icmpv4_echo_reply then
         -- A reply to a ping, coming from the B4.  Only B4s whose
         -- softwire is associated with port 0 are pingable.  See
         -- icmpv4_incoming for more discussion.
         port = 0
      else
         -- Otherwise it's an error in response to a non-ICMP packet,
         -- routed to the B4 via the ports in IPv4 payload.  Extract
         -- these ports from the embedded packet fragment in the ICMP
         -- payload.
         local embedded_ipv4_header = get_icmp_payload(icmp_header)
         port = get_ipv4_payload_src_port(embedded_ipv4_header)
      end
   else
      -- It's not ICMP.  Assume we can find ports in the IPv4 payload,
      -- as in TCP and UDP.  We could check strictly for TCP/UDP, but
      -- that would filter out similarly-shaped protocols like SCTP, so
      -- we optimistically assume that the incoming traffic has the
      -- right shape.
      port = get_ipv4_payload_src_port(tunneled_ipv4_header)
   end

   local ipv4 = get_ipv4_src_address(tunneled_ipv4_header)
   return enqueue_decapsulation(lwstate, pkt, ipv4, port)
end

function LwAftr:push ()
   local i4, i6, ih = self.input.v4, self.input.v6, self.input.hairpin_in
   local o4, o6 = self.output.v4, self.output.v6
   self.o4, self.o6 = o4, o6

   for _ = 1, link.nreadable(i6) do
      -- Decapsulate incoming IPv6 packets from the B4 interface and
      -- push them out the V4 link, unless they need hairpinning, in
      -- which case enqueue them on the hairpinning incoming link.
      -- Drop anything that's not IPv6.
      local pkt = receive(i6)
      if is_ipv6(pkt) then
         counter.add(self.counters["in-ipv6-bytes"], pkt.length)
         counter.add(self.counters["in-ipv6-packets"])
         from_b4(self, pkt)
      else
         counter.add(self.counters["drop-misplaced-not-ipv6-bytes"], pkt.length)
         counter.add(self.counters["drop-misplaced-not-ipv6-packets"])
         counter.add(self.counters["drop-all-ipv6-iface-bytes"], pkt.length)
         counter.add(self.counters["drop-all-ipv6-iface-packets"])
         drop(pkt)
      end
   end
   flush_decapsulation(self)

   for _ = 1, link.nreadable(i4) do
      -- Encapsulate incoming IPv4 packets, excluding hairpinned
      -- packets.  Drop anything that's not IPv4.
      local pkt = receive(i4)
      if is_ipv4(pkt) then
         counter.add(self.counters["in-ipv4-bytes"], pkt.length)
         counter.add(self.counters["in-ipv4-packets"])
         from_inet(self, pkt, PKT_FROM_INET)
      else
         counter.add(self.counters["drop-misplaced-not-ipv4-bytes"], pkt.length)
         counter.add(self.counters["drop-misplaced-not-ipv4-packets"])
         -- It's guaranteed to not be hairpinned.
         counter.add(self.counters["drop-all-ipv4-iface-bytes"], pkt.length)
         counter.add(self.counters["drop-all-ipv4-iface-packets"])
         drop(pkt)
      end
   end
   flush_encapsulation(self)

   for _ = 1, link.nreadable(ih) do
      -- Encapsulate hairpinned packet.
      local pkt = receive(ih)
      -- To reach this link, it has to have come through the lwaftr, so it
      -- is certainly IPv4. It was already counted, no more counter updates.
      from_inet(self, pkt, PKT_HAIRPINNED)
   end
   flush_hairpin(self)
end

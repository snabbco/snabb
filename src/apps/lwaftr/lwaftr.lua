module(..., package.seeall)

local bt = require("apps.lwaftr.binding_table")
local constants = require("apps.lwaftr.constants")
local dump = require('apps.lwaftr.dump')
local icmp = require("apps.lwaftr.icmp")
local lwconf = require("apps.lwaftr.conf")
local lwdebug = require("apps.lwaftr.lwdebug")
local lwheader = require("apps.lwaftr.lwheader")
local lwutil = require("apps.lwaftr.lwutil")

local S = require("syscall")
local timer = require("core.timer")
local checksum = require("lib.checksum")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local ipv4 = require("lib.protocol.ipv4")
local packet = require("core.packet")
local lib = require("core.lib")
local bit = require("bit")
local ffi = require("ffi")

local band, bor, bnot = bit.band, bit.bor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local cast, fstring = ffi.cast, ffi.string
local receive, transmit = link.receive, link.transmit
local rd16, rd32, get_ihl_from_offset = lwutil.rd16, lwutil.rd32, lwutil.get_ihl_from_offset
local htons, htonl = lwutil.htons, lwutil.htonl
local ntohs, ntohl = htons, htonl
local keys = lwutil.keys
local write_eth_header, write_ipv6_header = lwheader.write_eth_header, lwheader.write_ipv6_header 

local debug = false

-- Local bindings for constants that are used in the hot path of the
-- data plane.  Not having them here is a 1-2% performance penalty.
local ipv6_fixed_header_size = constants.ipv6_fixed_header_size
local n_ethertype_ipv4 = constants.n_ethertype_ipv4
local n_ethertype_ipv6 = constants.n_ethertype_ipv6
local o_ipv4_checksum = constants.o_ipv4_checksum
local o_ipv4_dscp_and_ecn = constants.o_ipv4_dscp_and_ecn
local o_ipv4_dst_addr = constants.o_ipv4_dst_addr
local o_ipv4_flags = constants.o_ipv4_flags
local o_ipv4_identification = constants.o_ipv4_identification
local o_ipv4_proto = constants.o_ipv4_proto
local o_ipv4_src_addr = constants.o_ipv4_src_addr
local o_ipv4_total_length = constants.o_ipv4_total_length
local o_ipv4_ttl = constants.o_ipv4_ttl
local o_ipv4_ver_and_ihl = constants.o_ipv4_ver_and_ihl
local o_ipv6_dst_addr = constants.o_ipv6_dst_addr
local o_ipv6_next_header = constants.o_ipv6_next_header
local o_ipv6_src_addr = constants.o_ipv6_src_addr
local proto_icmp = constants.proto_icmp
local proto_icmpv6 = constants.proto_icmpv6
local proto_ipv4 = constants.proto_ipv4

local transmit_icmpv6_with_rate_limit

local function init_transmit_icmpv6_with_rate_limit(lwstate)
   assert(lwstate.icmpv6_rate_limiter_n_seconds > 0,
      "Incorrect icmpv6_rate_limiter_n_seconds value, must be > 0")
   assert(lwstate.icmpv6_rate_limiter_n_packets >= 0,
      "Incorrect icmpv6_rate_limiter_n_packets value, must be >= 0")
   local icmpv6_rate_limiter_n_seconds = lwstate.icmpv6_rate_limiter_n_seconds
   local icmpv6_rate_limiter_n_packets = lwstate.icmpv6_rate_limiter_n_packets
   local counter = 0
   local last_time
   return function (o, pkt)
      local cur_now = tonumber(engine.now())
      last_time = last_time or cur_now
      -- Reset if elapsed time reached.
      if cur_now - last_time >= icmpv6_rate_limiter_n_seconds then
         last_time = cur_now
         counter = 0
      end
      -- Send packet if limit not reached.
      if counter < icmpv6_rate_limiter_n_packets then
         counter = counter + 1
         return transmit(o, pkt)
      else
         packet.free(pkt)
      end
   end
end

local function on_signal(sig, f)
   local fd = S.signalfd(sig, "nonblock") -- handle signal via fd
   local buf = S.types.t.siginfos(8)
   S.sigprocmask("block", sig)            -- block traditional handler
   timer.activate(timer.new(sig, function ()
      local events, err = S.util.signalfd_read(fd, buf)
      if events and #events > 0 then
         print(("[snabb-lwaftr: %s caught]"):format(sig:upper()))
         f()
      end
  end, 1e4, 'repeating'))
end

LwAftr = {}

function LwAftr:new(conf)
   if type(conf) == 'string' then
      conf = lwconf.load_lwaftr_config(conf)
   end
   if conf.debug then debug = true end
   local o = setmetatable({}, {__index=LwAftr})
   o.conf = conf

   -- FIXME: Access these from the conf instead of splatting them onto
   -- the lwaftr app, if there is no performance impact.
   o.aftr_ipv4_ip = conf.aftr_ipv4_ip
   o.aftr_ipv6_ip = conf.aftr_ipv6_ip
   o.aftr_mac_b4_side = conf.aftr_mac_b4_side
   o.aftr_mac_inet_side = conf.aftr_mac_inet_side
   o.b4_mac = conf.b4_mac
   o.hairpinning = conf.hairpinning
   o.icmpv6_rate_limiter_n_packets = conf.icmpv6_rate_limiter_n_packets
   o.icmpv6_rate_limiter_n_seconds = conf.icmpv6_rate_limiter_n_seconds
   o.inet_mac = conf.inet_mac
   o.ipv4_mtu = conf.ipv4_mtu
   o.ipv6_mtu = conf.ipv6_mtu
   o.policy_icmpv4_incoming = conf.policy_icmpv4_incoming
   o.policy_icmpv4_outgoing = conf.policy_icmpv4_outgoing
   o.policy_icmpv6_incoming = conf.policy_icmpv6_incoming
   o.policy_icmpv6_outgoing = conf.policy_icmpv6_outgoing

   o.binding_table = bt.load(o.conf.binding_table)

   o.l2_size = constants.ethernet_header_size
   o.o_ethernet_ethertype = constants.o_ethernet_ethertype
   transmit_icmpv6_with_rate_limit = init_transmit_icmpv6_with_rate_limit(o)
   on_signal("hup", function()
      print('Reloading binding table.')
      o.binding_table = bt.load(o.conf.binding_table)
   end)
   on_signal("usr1", function()
      dump.dump_configuration(o)
      dump.dump_binding_table(o)
   end)
   if debug then lwdebug.pp(conf) end
   return o
end

local function fixup_checksum(pkt, csum_offset, fixup_val)
   assert(math.abs(fixup_val) <= 0xffff, "Invalid fixup")
   local csum = bnot(ntohs(rd16(pkt.data + csum_offset)))
   if debug then print("old csum", string.format("%x", csum)) end
   csum = csum + fixup_val
   -- TODO/FIXME: *test* this code
   -- Manually unrolled loop; max 2 iterations, extra iterations
   -- don't hurt, bitops are fast and ifs are slow.
   local overflow = rshift(csum, 16)
   csum = band(csum, 0xffff) + overflow
   local overflow = rshift(csum, 16)
   csum = band(csum, 0xffff) + overflow
   csum = bnot(csum)

   if debug then print("new csum", string.format("%x", csum)) end
   pkt.data[csum_offset] = rshift(csum, 8)
   pkt.data[csum_offset + 1] = band(csum, 0xff)
end

local function decrement_ttl(lwstate, pkt)
   local ttl_offset = lwstate.l2_size + o_ipv4_ttl
   pkt.data[ttl_offset] = pkt.data[ttl_offset] - 1
   local ttl = pkt.data[ttl_offset]
   local csum_offset = lwstate.l2_size + o_ipv4_checksum
   -- ttl_offset is even, so multiply the ttl change by 0x100.
   fixup_checksum(pkt, csum_offset, -0x100)
   return ttl
end

local function get_lwAFTR_ipv6(lwstate, binding_entry)
   local lwaftr_ipv6 = binding_entry[4]
   if not lwaftr_ipv6 then lwaftr_ipv6 = lwstate.aftr_ipv6_ip end
   return lwaftr_ipv6
end

local function binding_lookup_ipv4(lwstate, ipv4_ip, port)
   if debug then
      print(lwdebug.format_ipv4(ipv4_ip), 'port: ', port, string.format("%x", port))
      lwdebug.pp(lwstate.binding_table)
   end
   local host_endian_ipv4 = ntohl(ipv4_ip)
   local val = lwstate.binding_table:lookup(host_endian_ipv4, port)
   if val then
      return val.b4_ipv6, lwstate.binding_table:get_br_address(val.br)
   end
   if debug then
      print("Nothing found for ipv4:port", lwdebug.format_ipv4(ipv4_ip),
      string.format("%i (0x%x)", port, port))
   end
end

-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt
-- Return the destination IPv6 address, *and the source IPv6 address*
local function binding_lookup_dst_ipv4_from_pkt(lwstate, pkt, pre_ipv4_bytes)
   local dst_ip_start = pre_ipv4_bytes + o_ipv4_dst_addr
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = rd32(pkt.data + dst_ip_start)
   local dst_port_start = pre_ipv4_bytes + get_ihl_from_offset(pkt, pre_ipv4_bytes) + 2
   local port = ntohs(rd16(pkt.data + dst_port_start))
   return binding_lookup_ipv4(lwstate, ip, port)
end

local function binding_lookup_src_ipv4_from_pkt(lwstate, pkt, pre_ipv4_bytes)
   local src_ip_start = pre_ipv4_bytes + o_ipv4_src_addr
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = rd32(pkt.data + src_ip_start)
   local src_port_start = pre_ipv4_bytes + get_ihl_from_offset(pkt, pre_ipv4_bytes)
   local port = ntohs(rd16(pkt.data + src_port_start))
   return binding_lookup_ipv4(lwstate, ip, port)
end

-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt
-- Return true if the destination ipv4 address is within our managed set of addresses
local function ipv4_dst_in_binding_table(lwstate, pkt, pre_ipv4_bytes)
   local dst_ip_start = pre_ipv4_bytes + 16
   local host_endian_ipv4 = htonl(rd32(pkt.data + dst_ip_start))
   return lwstate.binding_table:is_managed_ipv4_address(host_endian_ipv4)
end

local uint64_ptr_t = ffi.typeof('uint64_t*')
local function ipv6_equals(a, b)
   local a, b = ffi.cast(uint64_ptr_t, a), ffi.cast(uint64_ptr_t, b)
   return a[0] == b[0] and a[1] == b[1]
end

local function in_binding_table(lwstate, ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port)
   local b4, br = binding_lookup_ipv4(lwstate, ipv4_src_ip, ipv4_src_port)
   return b4 and ipv6_equals(b4, ipv6_src_ip) and ipv6_equals(br, ipv6_dst_ip)
end

-- ICMPv4 type 3 code 1, as per RFC 7596.
-- The target IPv4 address + port is not in the table.
local function icmp_after_discard(lwstate, pkt, to_ip)
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_host_unreachable,
                        }
   local icmp_dis = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                           lwstate.aftr_ipv4_ip, to_ip, pkt,
                                           lwstate.l2_size, icmp_config)
   return transmit(lwstate.o4, icmp_dis)
end

-- ICMPv6 type 1 code 5, as per RFC 7596.
-- The source (ipv6, ipv4, port) tuple is not in the table.
local function icmp_b4_lookup_failed(lwstate, pkt, to_ip)
   local icmp_config = {type = constants.icmpv6_dst_unreachable,
                        code = constants.icmpv6_failed_ingress_egress_policy,
                       }
   local b4fail_icmp = icmp.new_icmpv6_packet(lwstate.aftr_mac_b4_side, lwstate.b4_mac,
                                              lwstate.aftr_ipv6_ip, to_ip, pkt,
                                              lwstate.l2_size, icmp_config)
   transmit_icmpv6_with_rate_limit(lwstate.o6, b4fail_icmp)
end

local function encapsulating_packet_with_df_flag_would_exceed_mtu(lwstate, pkt)
   local encapsulated_len = pkt.length + ipv6_fixed_header_size
   if encapsulated_len - lwstate.l2_size <= lwstate.ipv6_mtu then
      -- Packet will not exceed MTU.
      return false
   end

   -- The result would exceed the IPv6 MTU; signal an error via ICMPv4 if
   -- the IPv4 fragment has the DF flag.
   local flags = pkt.data[lwstate.l2_size + o_ipv4_flags]
   return band(flags, 0x40) == 0x40
end

local function cannot_fragment_df_packet_error(lwstate, pkt)
   -- According to RFC 791, the original packet must be discarded.
   -- Return a packet with ICMP(3, 4) and the appropriate MTU
   -- as per https://tools.ietf.org/html/rfc2473#section-7.2
   if debug then lwdebug.print_pkt(pkt) end
   -- The source address of the packet is where the ICMP packet should be sent
   local o_src = lwstate.l2_size + constants.o_ipv4_src_addr
   local dst_ip = pkt.data + o_src
   local icmp_config = {
      type = constants.icmpv4_dst_unreachable,
      code = constants.icmpv4_datagram_too_big_df,
      extra_payload_offset = 0,
      next_hop_mtu = lwstate.ipv6_mtu - constants.ipv6_fixed_header_size,
   }
   return icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                 lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                 lwstate.l2_size, icmp_config)
end

-- Given a packet containing IPv4 and Ethernet, encapsulate the IPv4 portion.
local function ipv6_encapsulate(lwstate, pkt, next_hdr_type, ipv6_src, ipv6_dst,
                                 ether_src, ether_dst)
   -- TODO: decrement the IPv4 ttl as this is part of forwarding
   -- TODO: do not encapsulate if ttl was already 0; send icmp
   if debug then print("ipv6", ipv6_src, ipv6_dst) end

   if encapsulating_packet_with_df_flag_would_exceed_mtu(lwstate, pkt) then
      local icmp_pkt = cannot_fragment_df_packet_error(lwstate, pkt)
      packet.free(pkt)
      return transmit(lwstate.o4, icmp_pkt)
   end

   -- As if it were Ethernet decapsulated.
   local offset = lwstate.l2_size
   local payload_length = pkt.length - offset
   local dscp_and_ecn = pkt.data[offset + o_ipv4_dscp_and_ecn]
   -- Make room at the beginning for IPv6 header.
   packet.shiftright(pkt, ipv6_fixed_header_size)
   -- Modify Ethernet header.
   local eth_type = n_ethertype_ipv6
   write_eth_header(pkt.data, ether_src, ether_dst, eth_type)

   -- Modify IPv6 header.
   write_ipv6_header(pkt.data + lwstate.l2_size, ipv6_src, ipv6_dst,
                     dscp_and_ecn, next_hdr_type, payload_length)

   if debug then
      print("encapsulated packet:")
      lwdebug.print_pkt(pkt)
   end
   return transmit(lwstate.o6, pkt)
end

local function icmpv4_incoming(lwstate, pkt)
   local ipv4_header_size = get_ihl_from_offset(pkt, lwstate.l2_size)
   local icmp_base = lwstate.l2_size + ipv4_header_size
   local ip_base = icmp_base + constants.icmp_base_size
   local icmp_type_offset = icmp_base -- it's the zeroeth byte of the ICMP header
   local icmp_type = pkt.data[icmp_type_offset]
   local source_port, ipv4_dst

   -- RFC 7596 is silent on whether to validate echo request/reply checksums.
   -- ICMP checksums SHOULD be validated according to RFC 5508.
   -- Choose to verify the echo reply/request ones too.
   -- Note: the lwaftr SHOULD NOT validate the transport checksum of the embedded packet.
   -- Were it to nonetheless do so, RFC 4884 extension headers MUST NOT
   -- be taken into account when validating the checksum
   local o_tl = lwstate.l2_size + o_ipv4_total_length
   local icmp_bytes = ntohs(rd16(pkt.data + o_tl)) - ipv4_header_size
   if checksum.ipsum(pkt.data + icmp_base, icmp_bytes, 0) ~= 0 then
      packet.free(pkt)
      return -- Silently drop the packet, as per RFC 5508
   end

   -- checksum was ok
   if icmp_type == constants.icmpv4_echo_reply or icmp_type == constants.icmpv4_echo_request then
      source_port = ntohs(rd16(pkt.data + icmp_base + constants.o_icmpv4_echo_identifier))
      -- Use the outermost IP header for the destination; it's not repeated in the payload
      ipv4_dst = rd32(pkt.data + lwstate.l2_size + constants.o_ipv4_dst_addr)
   else
      -- source port is the zeroeth byte of an encapsulated tcp or udp packet
      -- TODO: explicitly check for tcp/udp?
      -- As per REQ-3, use the ip address embedded in the ICMP payload
      -- The Internet Header Length is the low 4 bits, in 32-bit words; convert it to bytes
      local embedded_ipv4_header_size = bit.band(pkt.data[ip_base + o_ipv4_ver_and_ihl], 0xf) * 4
      local o_sp = ip_base + embedded_ipv4_header_size
      source_port = ntohs(rd16(pkt.data + o_sp))
      local o_ip = ip_base + o_ipv4_src_addr
      ipv4_dst = rd32(pkt.data + o_ip)
   end
   -- IPs are stored in network byte order in the binding table
   local ipv6_dst, ipv6_src = binding_lookup_ipv4(lwstate, ipv4_dst, source_port)
   if not ipv6_dst then
      -- No match found in the binding table; the packet MUST be discarded
      packet.free(pkt)
      return
   end
   -- Otherwise, the packet MUST be forwarded
   local next_hdr = proto_ipv4
   return ipv6_encapsulate(lwstate, pkt, next_hdr, ipv6_src, ipv6_dst,
                           lwstate.aftr_mac_b4_side, lwstate.b4_mac)
end


-- The incoming packet is a complete one with ethernet headers.
local function from_inet(lwstate, pkt)
   -- Check incoming ICMP -first-, because it has different binding table lookup logic
   -- than other protocols.
   local proto_offset = lwstate.l2_size + o_ipv4_proto
   local proto = pkt.data[proto_offset]
   if proto == proto_icmp then
      if lwstate.policy_icmpv4_incoming == lwconf.policies['DROP'] then
         packet.free(pkt)
         return
      else
         return icmpv4_incoming(lwstate, pkt)
      end
   end

   -- It's not incoming ICMP; back to regular processing
   local ipv6_dst, ipv6_src = binding_lookup_dst_ipv4_from_pkt(lwstate, pkt, lwstate.l2_size)
   if not ipv6_dst then
      if debug then print("lookup failed") end
      if lwstate.policy_icmpv4_outgoing == lwconf.policies['DROP'] then
         packet.free(pkt)
         return -- lookup failed
      else
         local src_ip_start = lwstate.l2_size + o_ipv4_src_addr
         local to_ip = pkt.data + src_ip_start
         return icmp_after_discard(lwstate, pkt, to_ip)-- ICMPv4 type 3 code 1 (dst/host unreachable)
      end
   end

   local ether_src = lwstate.aftr_mac_b4_side
   local ether_dst = lwstate.b4_mac -- FIXME: this should probaby use NDP

   -- Do not encapsulate packets that now have a ttl of zero or wrapped around
   local ttl = decrement_ttl(lwstate, pkt)
   if ttl == 0 or ttl == 255 then
      if lwstate.policy_icmpv4_outgoing == lwconf.policies['DROP'] then
         return
      end
      local o_src = lwstate.l2_size + constants.o_ipv4_src_addr
      local dst_ip = pkt.data + o_src
      local icmp_config = {type = constants.icmpv4_time_exceeded,
                           code = constants.icmpv4_ttl_exceeded_in_transit,
                           }
      local ttl0_icmp =  icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                                lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                                lwstate.l2_size, icmp_config)
      return transmit(lwstate.o4, ttl0_icmp)
   end

   local next_hdr = proto_ipv4
   return ipv6_encapsulate(lwstate, pkt, next_hdr, ipv6_src, ipv6_dst,
                           ether_src, ether_dst)
end

local function tunnel_packet_too_big(lwstate, pkt)
   local ipv6_hs = constants.ipv6_fixed_header_size
   local eth_hs = lwstate.l2_size
   local icmp_hs = constants.icmp_base_size
   local orig_packet_offset = eth_hs + ipv6_hs + icmp_hs + ipv6_hs

   local next_hop_mtu_offset = 6
   local o_mtu = eth_hs + ipv6_hs + next_hop_mtu_offset
   local specified_mtu = ntohs(rd16(pkt.data + o_mtu))
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_datagram_too_big_df,
                        extra_payload_offset = orig_packet_offset - eth_hs,
                        next_hop_mtu = specified_mtu - constants.ipv6_fixed_header_size,
                        }
   local o_src = orig_packet_offset + constants.o_ipv4_src_addr
   local dst_ip = pkt.data + o_src
   local icmp_reply = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                             lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                             lwstate.l2_size, icmp_config)
   return icmp_reply
end

-- This is highly redundant code, but it avoids conditionals
local function tunnel_generic_unreachable(lwstate, pkt)
   local ipv6_hs = constants.ipv6_fixed_header_size
   local eth_hs = lwstate.l2_size
   local icmp_hs = constants.icmp_base_size
   local orig_packet_offset = eth_hs + ipv6_hs + icmp_hs + ipv6_hs
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_host_unreachable,
                        extra_payload_offset = orig_packet_offset - eth_hs,
                        }
   local o_src = orig_packet_offset + constants.o_ipv4_src_addr
   local dst_ip = pkt.data + o_src
   local icmp_reply = icmp.new_icmpv4_packet(lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                                             lwstate.aftr_ipv4_ip, dst_ip, pkt,
                                             lwstate.l2_size, icmp_config)
   return icmp_reply
end

local function icmpv6_incoming(lwstate, pkt)
   local icmpv6_offset = lwstate.l2_size + constants.ipv6_fixed_header_size
   local icmp_type = pkt.data[icmpv6_offset]
   local icmp_code = pkt.data[icmpv6_offset + 1]
   local icmpv4_reply
   if icmp_type == constants.icmpv6_packet_too_big then
      if icmp_code ~= constants.icmpv6_code_packet_too_big then
         return -- Invalid code
      end
      icmpv4_reply = tunnel_packet_too_big(lwstate, pkt)

   -- Take advantage of having already checked for 'packet too big' (2), and
   -- unreachable node/hop limit exceeded/paramater problem being 1, 3, 4 respectively
   elseif icmp_type <= constants.icmpv6_parameter_problem then
      -- If the time limit was exceeded, require it was a hop limit code
      if icmp_type == constants.icmpv6_time_limit_exceeded then
         if icmp_code ~= constants.icmpv6_hop_limit_exceeded then
            return
         end
      end
      -- Accept all unreachable or parameter problem codes
      icmpv4_reply = tunnel_generic_unreachable(lwstate, pkt)
   else -- No other types of ICMPv6, including echo request/reply, are handled
      return
   end

   -- There's an ICMPv4 packet. If it's in response to a packet from the external
   -- network, send it there. If hairpinning is/was enabled, it could be from a
   -- b4; if it was from a b4, encapsulate the generated IPv4 message and send it.
   -- This is the most plausible reading of RFC 2473, although not unambigous.
   local first_ipv4_header_bytes = get_ihl_from_offset(icmpv4_reply, lwstate.l2_size)
   local pre_embed_ipv4_bytes = lwstate.l2_size + first_ipv4_header_bytes + constants.icmp_base_size
   local ipv6_dst = binding_lookup_src_ipv4_from_pkt(lwstate, icmpv4_reply, pre_embed_ipv4_bytes)
   if ipv6_dst and lwstate.hairpinning then
      if debug then print("Hairpinning ICMPv4 mapped from ICMPv6") end
      -- Hairpinning was implicitly allowed now or in the recent past if the
      -- binding table lookup succeeded. Nonetheless, require that it be
      -- currently true to encapsulate and hairpin the outgoing packet.
      -- If it's false, send it out through the normal internet interface,
      -- like notifications to any non-bound host.
      return icmpv4_incoming(lwstate, icmpv4_reply) -- to B4
   else
      return transmit(lwstate.o4, icmpv4_reply)
   end
end

local function get_ipv6_src_ip(lwstate, pkt)
   local ipv6_src = lwstate.l2_size + o_ipv6_src_addr
   return fstring(pkt.data + ipv6_src, 16)
end

local function get_ipv6_dst_ip(lwstate, pkt)
   local ipv6_dst = lwstate.l2_size + o_ipv6_dst_addr
   return fstring(pkt.data + ipv6_dst, 16)
end

local function from_b4(lwstate, pkt)
   local proto_offset = lwstate.l2_size + o_ipv6_next_header
   local proto = pkt.data[proto_offset]
   if proto == proto_icmpv6 then
      if lwstate.policy_icmpv6_incoming == lwconf.policies['DROP'] then
         packet.free(pkt)
         return
      else
         return icmpv6_incoming(lwstate, pkt)
      end
   end

   -- check src ipv4, ipv6, and port against the binding table
   local ipv6_src_ip_offset = lwstate.l2_size + o_ipv6_src_addr
   local ipv6_dst_ip_offset = lwstate.l2_size + o_ipv6_dst_addr
   -- FIXME: deal with multiple IPv6 headers?
   local eth_and_ipv6 = lwstate.l2_size + ipv6_fixed_header_size
   local ipv4_src_ip_offset = eth_and_ipv6 + o_ipv4_src_addr
   -- FIXME: as above + non-tcp/non-udp payloads
   local ipv4_src_port_offset = eth_and_ipv6 + get_ihl_from_offset(pkt, eth_and_ipv6)
   local ipv6_src_ip = pkt.data + ipv6_src_ip_offset
   local ipv6_dst_ip = pkt.data + ipv6_dst_ip_offset
   local ipv4_src_ip = rd32(pkt.data + ipv4_src_ip_offset)
   local ipv4_src_port = ntohs(rd16(pkt.data + ipv4_src_port_offset))

   if in_binding_table(lwstate, ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port) then
      -- Is it worth optimizing this to change src_eth, src_ipv6, ttl, checksum,
      -- rather than decapsulating + re-encapsulating? It would be faster, but more code.
      local offset = lwstate.l2_size + ipv6_fixed_header_size
      if debug then
         print("lwstate.hairpinning is", lwstate.hairpinning)
         print("binding_lookup...", binding_lookup_dst_ipv4_from_pkt(lwstate, pkt, offset))
      end
      if lwstate.hairpinning and ipv4_dst_in_binding_table(lwstate, pkt, offset) then
         -- Remove IPv6 header.
         packet.shiftleft(pkt, ipv6_fixed_header_size)
         write_eth_header(pkt.data, lwstate.b4_mac, lwstate.aftr_mac_b4_side,
                          n_ethertype_ipv4)
         -- TODO:  refactor so this doesn't actually seem to be from the internet?
         return from_inet(lwstate, pkt)
      else
         -- Remove IPv6 header.
         packet.shiftleft(pkt, ipv6_fixed_header_size)
         write_eth_header(pkt.data, lwstate.aftr_mac_inet_side, lwstate.inet_mac,
                          n_ethertype_ipv4)
         return transmit(lwstate.o4, pkt)
      end
   elseif lwstate.policy_icmpv6_outgoing == lwconf.policies['ALLOW'] then
      icmp_b4_lookup_failed(lwstate, pkt, ipv6_src_ip)
      packet.free(pkt)
   else
      packet.free(pkt)
      return
   end
end

-- Modify the given packet in-place, and forward it, drop it, or reply with
-- an ICMP or ICMPv6 packet as per the internet draft and configuration policy.

-- Check each input device. Handle transmission through the system in the following
-- loops; handle unusual cases (ie, ICMP going through the same interface as it
-- was received from) where they occur.
function LwAftr:push ()
   local i4, i6 = self.input.v4, self.input.v6
   local o4, o6 = self.output.v4, self.output.v6
   self.o4, self.o6 = o4, o6

   -- If we are really slammed and can't keep up, packets are going to
   -- drop one way or another.  The nwritable() check is just to prevent
   -- us from burning the CPU on packets that we're pretty sure would be
   -- dropped anyway, so that when we're in an overload situation things
   -- don't get worse as the traffic goes up.  It's not a fool-proof
   -- check that we in fact will be able to successfully handle the
   -- packet, given that the packet might require fragmentation,
   -- hairpinning, or ICMP error messages, all of which might result in
   -- transmission of packets on the "other" interface or multiple
   -- packets on the "right" interface.

   for _=1,math.min(link.nreadable(i4), link.nwritable(o6)) do
      local pkt = receive(i4)
      if debug then print("got a pkt") end
      -- Keep the ethertype in network byte order
      local ethertype = rd16(pkt.data + self.o_ethernet_ethertype)

      if ethertype == n_ethertype_ipv4 then -- Incoming packet from the internet
         from_inet(self, pkt)
      else
         packet.free(pkt)
      end -- Silently drop all other types coming from the internet interface
   end

   for _=1,math.min(link.nreadable(i6), link.nwritable(o4)) do
      local pkt = receive(i6)
      if debug then print("got a pkt") end
      local ethertype = rd16(pkt.data + self.o_ethernet_ethertype)
      if ethertype == n_ethertype_ipv6 then
         -- decapsulate iff the source was a b4, and forward/hairpin/ICMPv6 as needed
         from_b4(self, pkt)
      else
         packet.free(pkt)
      end -- FIXME: silently drop other types; is this the right thing to do?
   end
end

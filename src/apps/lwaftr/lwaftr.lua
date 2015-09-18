module(..., package.seeall)

local constants = require("apps.lwaftr.constants")
local fragment = require("apps.lwaftr.fragment")
local icmp = require("apps.lwaftr.icmp")
local lwconf = require("apps.lwaftr.conf")
local lwdebug = require("apps.lwaftr.lwdebug")

local checksum = require("lib.checksum")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local packet = require("core.packet")
local bit = require("bit")
local ffi = require("ffi")

local band, bnot, rshift = bit.band, bit.bnot, bit.rshift
local C = ffi.C

local debug = false
local empty = {}

LwAftr = {}

function LwAftr:new(conf)
   if debug then lwdebug.pp(conf) end
   local o = {}
   for k,v in pairs(conf) do
      o[k] = v
   end
   o.dgram = datagram:new()
   o.fragment_cache = {}
   o.scratch_ipv4 = ffi.new("uint8_t[4]")
   return setmetatable(o, {__index=LwAftr})
end

local function fixup_checksum(pkt, csum_offset, fixup_val)
   assert(math.abs(fixup_val) <= 0xffff, "Invalid fixup")
   local csum = bnot(C.ntohs(ffi.cast("uint16_t*", pkt.data + csum_offset)[0]))
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

local function decrement_ttl(pkt)
   local ttl_offset = constants.ethernet_header_size + constants.o_ipv4_ttl
   pkt.data[ttl_offset] = pkt.data[ttl_offset] - 1
   local ttl = pkt.data[ttl_offset]
   local csum_offset = constants.ethernet_header_size + constants.o_ipv4_checksum
   -- ttl_offset is even, so multiply the ttl change by 0x100.
   fixup_checksum(pkt, csum_offset, -0x100)
   return ttl
end

local function get_ihl(pkt)
   -- It's byte 0 of an IPv4 header
   local ver_and_ihl = pkt.data[constants.ethernet_header_size]
   return bit.band(ver_and_ihl, 0xf) * 4
end

local function get_ihl_from_offset(pkt, offset)
   local ver_and_ihl = pkt.data[offset]
   return bit.band(ver_and_ihl, 0xf) * 4
end

function LwAftr:_get_lwAFTR_ipv6(binding_entry)
   local lwaftr_ipv6 = binding_entry[5]
   if not lwaftr_ipv6 then lwaftr_ipv6 = self.aftr_ipv6_ip end
   return lwaftr_ipv6
end

-- TODO: make this O(1), and seriously optimize it for cache lines
function LwAftr:binding_lookup_ipv4(ipv4_ip, port)
   if debug then
      print(lwdebug.format_ipv4(ipv4_ip), 'port: ', port, string.format("%x", port))
      lwdebug.pp(self.binding_table)
   end
   for i=1,#self.binding_table do
      local bind = self.binding_table[i]
      if debug then print("CHECK", string.format("%x, %x", bind[2], ipv4_ip)) end
      if bind[2] == ipv4_ip then
         if port >= bind[3] and port <= bind[4] then
            local lwaftr_ipv6 = self:_get_lwAFTR_ipv6(bind)
            return bind[1], lwaftr_ipv6
         end
      end
   end
   if debug then
      print("Nothing found for ipv4:port", lwdebug.format_ipv4(ipv4_ip),
      string.format("%i (0x%x)", port, port))
   end
end

-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt
-- Return the destination IPv6 address, *and the source IPv6 address*
function LwAftr:binding_lookup_ipv4_from_pkt(pkt, pre_ipv4_bytes)
   local dst_ip_start = pre_ipv4_bytes + 16
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = ffi.cast("uint32_t*", pkt.data + dst_ip_start)[0]
   -- TODO: don't assume the length of the IPv4 header; check IHL
   local dst_port_start = pre_ipv4_bytes + get_ihl_from_offset(pkt, pre_ipv4_bytes) + 2
   local port = C.ntohs(ffi.cast("uint16_t*", pkt.data + dst_port_start)[0])
   return self:binding_lookup_ipv4(ip, port)
end

-- Todo: make this O(1)
function LwAftr:in_binding_table(ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port)
   for _, bind in ipairs(self.binding_table) do
      if debug then
         print("CHECKB4", string.format("%x, %x", bind[2], ipv4_src_ip), ipv4_src_port)
      end
      if bind[2] == ipv4_src_ip then
         if ipv4_src_port >= bind[3] and ipv4_src_port <= bind[4] then
            if debug then
               print("ipv6bind")
               lwdebug.print_ipv6(bind[1])
               lwdebug.print_ipv6(ipv6_src_ip)
            end
            if C.memcmp(bind[1], ipv6_src_ip, 16) == 0 then
               local expected_dst = self:_get_lwAFTR_ipv6(bind)
               if debug then
                  print("DST_MEMCMP", expected_dst, ipv6_dst_ip)
                  lwdebug.print_ipv6(expected_dst)
                  lwdebug.print_ipv6(ipv6_dst_ip)
               end
               if C.memcmp(expected_dst, ipv6_dst_ip, 16) == 0 then
                  return true
               end
            end
         end
      end
   end
   return false
end

-- ICMPv4 type 3 code 1, as per the internet draft.
-- That is: "Destination unreachable: destination host unreachable"
-- The target IPv4 address + port is not in the table.
function LwAftr:_icmp_after_discard(pkt, to_ip)
   local icmp_config = {type = constants.icmpv4_dst_unreachable,
                        code = constants.icmpv4_host_unreachable,
                        }
   local icmp_dis = icmp.new_icmpv4_packet(self.aftr_mac_inet_side, self.inet_mac,
                                           self.aftr_ipv4_ip, to_ip, pkt, icmp_config)
   return icmp_dis, empty
end

-- ICMPv6 type 1 code 5, as per the internet draft.
-- 'Destination unreachable: source address failed ingress/egress policy'
-- The source (ipv6, ipv4, port) tuple is not in the table.
function LwAftr:_icmp_b4_lookup_failed(pkt, to_ip)
   -- https://tools.ietf.org/html/rfc7596 calls for "As much of invoking packet                 |
   -- as possible without the ICMPv6 packet
   -- exceeding the minimum IPv6 MTU".
   -- Does this mean 1280 or the path-specific one?
   local headers_len = constants.ethernet_header_size + constants.ipv6_fixed_header_size + constants.icmp_base_size
   local plen = pkt.length - constants.ethernet_header_size
   if plen + headers_len >= constants.min_ipv6_mtu then
      plen = constants.min_ipv6_mtu - headers_len
   end
   local icmp_config = {type = constants.icmpv6_dst_unreachable,
                        code = constants.icmpv6_failed_ingress_egress_policy,
                       }
   local b4fail_icmp = icmp.new_icmpv6_packet(self.aftr_mac_b4_side, self.b4_mac, self.aftr_ipv6_ip,
                                              to_ip, pkt, icmp_config)
   return empty, b4fail_icmp
end

-- Given a packet containing IPv4 and Ethernet, encapsulate the IPv4 portion.
function LwAftr:ipv6_encapsulate(pkt, next_hdr_type, ipv6_src, ipv6_dst,
                                 ether_src, ether_dst)
   -- TODO: decrement the IPv4 ttl as this is part of forwarding
   -- TODO: do not encapsulate if ttl was already 0; send icmp
   if debug then print("ipv6", ipv6_src, ipv6_dst) end
   local dgram = self.dgram:reuse(pkt, ethernet)
   self:_decapsulate(dgram, constants.ethernet_header_size)
   if debug then
      print("Original packet, minus ethernet:")
      lwdebug.print_pkt(pkt)
   end
   local payload_len = pkt.length
   self:_add_ipv6_header(dgram, {next_header = next_hdr_type,
                                 hop_limit = constants.default_ttl,
                                 src = ipv6_src,
                                 dst = ipv6_dst})
   -- The API makes setting the payload length awkward; set it manually
   -- Todo: less awkward way to write 16 bits of a number into cdata
   pkt.data[4] = rshift(payload_len, 8)
   pkt.data[5] = band(payload_len, 0xff)
   self:_add_ethernet_header(dgram, {src = ether_src,
                                     dst = ether_dst,
                                     type = constants.ethertype_ipv6})
   if pkt.length <= self.ipv6_mtu then
      if debug then
         print("encapsulated packet:")
         lwdebug.print_pkt(pkt)
      end
      return empty, pkt
   end

   -- Otherwise, fragment if possible
   local unfrag_header_size = constants.ethernet_header_size + constants.ipv6_fixed_header_size
   local flags = pkt.data[unfrag_header_size + constants.o_ipv4_flags]
   if band(flags, 0x40) == 0x40 then -- The Don't Fragment bit is set
      -- According to RFC 791, the original packet must be discarded.
      -- Return a packet with ICMP(3, 4) and the appropriate MTU
      -- as per https://tools.ietf.org/html/rfc2473#section-7.2
      if debug then lwdebug.print_pkt(pkt) end
      local icmp_config = {type = constants.icmpv4_dst_unreachable,
                           code = constants.icmpv4_datagram_too_big_df,
                           extra_payload_offset = constants.ipv6_fixed_header_size,
                           next_hop_mtu = self.ipv6_mtu - constants.ipv6_fixed_header_size
                           }
      local icmp_pkt = icmp.new_icmpv4_packet(self.aftr_mac_inet_side, self.inet_mac,
                                              self.aftr_ipv4_ip, self.scratch_ipv4, pkt, icmp_config)
      packet.free(pkt)
      return icmp_pkt, empty
   end

   -- DF wasn't set; fragment the large packet
   local pkts = fragment.fragment_ipv6(pkt, unfrag_header_size, self.ipv6_mtu)
   if debug and pkts then
      print("Encapsulated packet into fragments")
      for idx,fpkt in ipairs(pkts) do
         print(string.format("    Fragment %i", idx))
         lwdebug.print_pkt(fpkt)
      end
   end
   return empty, pkts
end

-- Return a packet without ethernet or IPv6 headers.
-- TODO: this does not decrement TTL; is this correct?
function LwAftr:_decapsulate(dgram, length)
   -- FIXME: don't hardcode the values like this
   local length = length or constants.ethernet_header_size + constants.ipv6_fixed_header_size
   dgram:pop_raw(length)
end

function LwAftr:_add_ipv6_header(dgram, ipv6_params)
   local ipv6_hdr = ipv6:new(ipv6_params)
   dgram:push(ipv6_hdr)
   ipv6_hdr:free()
end

function LwAftr:_add_ethernet_header(dgram, eth_params)
   local eth_hdr = ethernet:new(eth_params)
   dgram:push(eth_hdr)
   eth_hdr:free()
end

function LwAftr:_icmpv4_incoming(pkt)
   local ipv4_header_size = get_ihl(pkt)
   local icmp_base = constants.ethernet_header_size + ipv4_header_size
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
   local o_tl = constants.ethernet_header_size + constants.o_ipv4_total_length
   local icmp_bytes = C.ntohs(ffi.cast("uint16_t*", pkt.data + o_tl)[0]) - ipv4_header_size
   if checksum.ipsum(pkt.data + icmp_base, icmp_bytes, 0) ~= 0 then
      packet.free(pkt)
      return empty, empty -- Silently drop the packet, as per RFC 5508
   end

   -- checksum was ok
   if icmp_type == constants.icmpv4_echo_reply or icmp_type == constants.icmpv4_echo_request then
      source_port = C.ntohs(ffi.cast("uint16_t*", pkt.data + icmp_base + constants.o_icmpv4_echo_identifier)[0])
      -- Use the outermost IP header for the destination; it's not repeated in the payload
      ipv4_dst = ffi.cast("uint32_t*", pkt.data + constants.ethernet_header_size + constants.o_ipv4_dst_addr)[0]
   else
      -- source port is the zeroeth byte of an encapsulated tcp or udp packet
      -- TODO: explicitly check for tcp/udp?
      -- As per REQ-3, use the ip address embedded in the ICMP payload
      -- The Internet Header Length is the low 4 bits, in 32-bit words; convert it to bytes
      local embedded_ipv4_header_size = bit.band(pkt.data[ip_base + constants.o_ipv4_ver_and_ihl], 0xf) * 4
      local o_sp = ip_base + embedded_ipv4_header_size
      source_port = C.ntohs(ffi.cast("uint16_t*", pkt.data + o_sp)[0])
      local o_ip = ip_base + constants.o_ipv4_src_addr
      ipv4_dst = ffi.cast("uint32_t*", pkt.data + o_ip)[0]
   end
   -- IPs are stored in network byte order in the binding table
   local ipv6_dst, ipv6_src = self:binding_lookup_ipv4(ipv4_dst, source_port)
   if not ipv6_dst then
      -- No match found in the binding table; the packet MUST be discarded
      packet.free(pkt)
      return empty, empty
   end
   -- Otherwise, the packet MUST be forwarded
   local next_hdr = constants.proto_ipv4
   return self:ipv6_encapsulate(pkt, next_hdr, ipv6_src, ipv6_dst,
                                self.aftr_mac_b4_side, self.b4_mac)
end

-- TODO: correctly handle fragmented IPv4 packets
-- TODO: correctly deal with IPv6 packets that need to be fragmented
-- The incoming packet is a complete one with ethernet headers.
function LwAftr:_encapsulate_ipv4(pkt)
   -- Check incoming ICMP -first-, because it has different binding table lookup logic
   -- than other protocols.
   local proto_offset = constants.ethernet_header_size + constants.o_ipv4_proto
   local proto = pkt.data[proto_offset]
   if proto == constants.proto_icmp then
      if self.policy_icmpv4_incoming == lwconf.policies['DROP'] then
         packet.free(pkt)
         return empty, empty
      else
         return self:_icmpv4_incoming(pkt)
      end
   end

   -- It's not incoming ICMP; back to regular processing
   local ipv6_dst, ipv6_src = self:binding_lookup_ipv4_from_pkt(pkt, constants.ethernet_header_size)
   if not ipv6_dst then
      if debug then print("lookup failed") end
      if self.policy_icmpv4_outgoing == lwconf.policies['DROP'] then
         packet.free(pkt)
         return empty, empty -- lookup failed
      else
         local src_ip_start = constants.ethernet_header_size + constants.o_ipv4_src_addr
         --local to_ip = ffi.cast("uint32_t*", pkt.data + src_ip_start)[0]
         local to_ip = pkt.data + src_ip_start
         return self:_icmp_after_discard(pkt, to_ip)-- ICMPv4 type 3 code 1 (dst/host unreachable)
      end
   end

   local ether_src = self.aftr_mac_b4_side 
   local ether_dst = self.b4_mac -- FIXME: this should probaby use NDP

   -- Do not encapsulate packets that now have a ttl of zero or wrapped around
   local ttl = decrement_ttl(pkt)
   if ttl == 0 or ttl == 255 then
      if self.policy_icmpv4_outgoing == lwconf.policies['DROP'] then
         return empty, empty
      end
      local icmp_config = {type = constants.icmpv4_time_exceeded,
                           code = constants.icmpv4_ttl_exceeded_in_transit,
                           }
      local ttl0_icmp =  icmp.new_icmpv4_packet(self.aftr_mac_inet_side, self.inet_mac,
                                                self.aftr_ipv4_ip, self.scratch_ipv4, pkt, icmp_config)
      return ttl0_icmp, empty
   end
 
   local next_hdr = constants.proto_ipv4
   return self:ipv6_encapsulate(pkt, next_hdr, ipv6_src, ipv6_dst,
                                ether_src, ether_dst)
end

-- TODO: rewrite this to either also have the source and dest IPs in the table,
-- or rewrite the fragment reassembler to check rather than assuming
-- all the fragments it is passed are the same in this regard
function LwAftr:_cache_fragment(frag)
  local frag_id = fragment.get_ipv6_frag_id(frag)
  if not self.fragment_cache[frag_id] then
     self.fragment_cache[frag_id] = {}
  end
  table.insert(self.fragment_cache[frag_id], frag)
  return self.fragment_cache[frag_id]
end

-- TODO: rewrite this to use parse
function LwAftr:from_b4(pkt)
   -- TODO: only send ICMP on failure for packets that plausibly would be bound?
   if fragment.is_ipv6_fragment(pkt) then
      local frags = self:_cache_fragment(pkt)
      local frag_status, maybe_pkt = fragment.reassemble_ipv6(frags)
      -- TODO: finish clearing out the fragment cache?
      if frag_status ~= fragment.REASSEMBLY_OK then
         if maybe_pkt == nil then maybe_pkt = empty end
         return empty, maybe_pkt -- empty or an ICMPv6 packet
      else
         -- The spec mandates that reassembly must occur before decapsulation
         pkt = maybe_pkt -- do the rest of the processing on the reassembled packet
      end
   end

   -- check src ipv4, ipv6, and port against the binding table
   local ipv6_src_ip_offset = constants.ethernet_header_size + constants.o_ipv6_src_addr
   local ipv6_dst_ip_offset = constants.ethernet_header_size + constants.o_ipv6_dst_addr
   -- FIXME: deal with multiple IPv6 headers?
   local eth_and_ipv6 = constants.ethernet_header_size + constants.ipv6_fixed_header_size
   local ipv4_src_ip_offset = eth_and_ipv6 + constants.o_ipv4_src_addr
   -- FIXME: as above + non-tcp/non-udp payloads
   local ipv4_src_port_offset = eth_and_ipv6 + get_ihl_from_offset(pkt, eth_and_ipv6)
   local ipv6_src_ip = pkt.data + ipv6_src_ip_offset
   local ipv6_dst_ip = pkt.data + ipv6_dst_ip_offset
   local ipv4_src_ip = ffi.cast("uint32_t*", pkt.data + ipv4_src_ip_offset)[0]
   local ipv4_src_port = C.ntohs(ffi.cast("uint16_t*", pkt.data + ipv4_src_port_offset)[0])

   if self:in_binding_table(ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port) then
      -- Is it worth optimizing this to change src_eth, src_ipv6, ttl, checksum,
      -- rather than decapsulating + re-encapsulating? It would be faster, but more code.
      local dgram = self.dgram:reuse(pkt)
      self:_decapsulate(dgram)
      if debug then
         print("self.hairpinning is", self.hairpinning)
         print("binding_lookup...", self:binding_lookup_ipv4_from_pkt(pkt, 0))
      end
      if self.hairpinning and self:binding_lookup_ipv4_from_pkt(pkt, 0) then
         -- FIXME: shifting the packet ethernet_header_size right would suffice here
         -- The ethernet data is thrown away by _encapsulate_ipv4 anyhow.
         self:_add_ethernet_header(dgram, {src = self.b4_mac,
                                           dst = self.aftr_mac_b4_side,
                                           type = constants.ethertype_ipv4})
         return self:_encapsulate_ipv4(pkt)
      else
         local dgram = self.dgram:reuse(pkt, ipv4)
         self:_add_ethernet_header(dgram, {src = self.aftr_mac_inet_side,
                                           dst = self.inet_mac,
                                           type = constants.ethertype_ipv4})
         return pkt, empty
      end
   elseif self.policy_icmpv6_outgoing == lwconf.policies['ALLOW'] then
      local _, icmp_pkt = self:_icmp_b4_lookup_failed(pkt, ipv6_src_ip)
      packet.free(pkt)
      return empty, icmp_pkt
   else
      packet.free(pkt)
      return empty, empty
   end
end

local function transmit_pkts(pkts, link, o)
   if type(pkts) == "table" then
      for i = 1, #pkts do
         link.transmit(o, pkts[i])
      end
   else -- Just one packet
      link.transmit(o, pkts)
   end
end

-- Modify the given packet in-place, and forward it, drop it, or reply with
-- an ICMP or ICMPv6 packet as per the internet draft and configuration policy.
-- TODO: handle ICMPv6 as per RFC 2473
-- TODO: revisit this and check on performance idioms

-- Check each input device. Handle transmission through the system in the following
-- loops; handle unusual cases (ie, ICMP going through the same interface as it
-- was received from) where they occur.
-- TODO: handle fragmentation elsewhere too?
function LwAftr:push ()
   local i4, o4 = self.input.v4, self.output.v4
   local i6, o6 = self.input.v6, self.output.v6
   while not link.empty(i4) and not link.full(o4) and not link.full(o6) do
      local pkt = link.receive(i4)
      if debug then print("got a pkt") end
      -- Keep the ethertype in network byte order
      local ethertype = ffi.cast('uint16_t*', pkt.data + constants.o_ethernet_ethertype)[0]

      if ethertype == constants.n_ethertype_ipv4 then -- Incoming packet from the internet
         ffi.copy(self.scratch_ipv4, pkt.data + constants.ethernet_header_size + constants.o_ipv4_src_addr, 4)
         local v4_pkts, v6_pkts = self:_encapsulate_ipv4(pkt)
         transmit_pkts(v4_pkts, link, o4)
         transmit_pkts(v6_pkts, link, o6)
      end -- Silently drop all other types coming from the internet interface
   end

   while not link.empty(i6) and not link.full(o4) and not link.full(o6) do
      local pkt = link.receive(i6)
      if debug then print("got a pkt") end
      local ethertype = ffi.cast('uint16_t*', pkt.data + constants.o_ethernet_ethertype)[0]
      local out_pkt = nil
      if ethertype == constants.n_ethertype_ipv6 then
         -- decapsulate iff the source was a b4, and forward/hairpin/ICMPv6 as needed
         local v4_pkts, v6_pkts = self:from_b4(pkt)
         transmit_pkts(v4_pkts, link, o4)
         transmit_pkts(v6_pkts, link, o6)
      end -- FIXME: silently drop other types; is this the right thing to do?
   end
end

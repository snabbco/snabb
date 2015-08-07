module(..., package.seeall)

local lwconf = require("apps.lwaftr.conf")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ffi = require("ffi")
local icmp = require("lib.protocol.icmp.header")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local packet = require("core.packet")

local C = ffi.C

LwAftr = {}

local function pp(t) for k,v in pairs(t) do print(k,v) end end

local function print_ipv6(addr)
   chunks = {}
   for i = 0,7 do
      table.insert(chunks, string.format("%x%x", addr[2*i], addr[2*i+1]))
   end
   print(table.concat(chunks, ':'))
end

-- http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
local proto_icmp = 1
local proto_tcp = 6
local proto_icmpv6 = 58

-- http://www.iana.org/assignments/ieee-802-numbers/ieee-802-numbers.xhtml
local ethertype_ipv4 = 0x0800
local ethertype_ipv6 = 0x86DD

local ethernet_header_size = 14 -- TODO: deal with 802.1Q tags?
local ipv6_header_size = 40
local ipv4_header_size = 20
local debug = true

function LwAftr:new(conf)
   pp(conf)
   return setmetatable(conf, {__index=LwAftr})
end

local function print_pkt(pkt)
   local fbytes = {}
   for i=0,pkt.length - 1 do
      table.insert(fbytes, string.format("0x%x", pkt.data[i]))
   end
   print(string.format("Len: %i: ", pkt.length) .. table.concat(fbytes, " "))
end

local function format_ipv4(uint32)
   return string.format("%i.%i.%i.%i",
      bit.rshift(bit.band(uint32, 0xff000000), 24),
      bit.rshift(bit.band(uint32, 0xff0000), 16),
      bit.rshift(bit.band(uint32, 0xff00), 8),
      bit.band(uint32, 0xff))
end

function LwAftr:_get_lwAFTR_ipv6(binding_entry)
   local lwaftr_ipv6 = binding_entry[5]
   if not lwaftr_ipv6 then lwaftr_ipv6 = self.aftr_ipv6_ip end
   return lwaftr_ipv6
end

-- TODO: make this O(1), and seriously optimize it for cache lines
function LwAftr:binding_lookup_ipv4(ipv4_ip, port)
   print(ipv4_ip, 'port: ', port)
   pp(self.binding_table)
   for _, bind in ipairs(self.binding_table) do
      if debug then print("CHECK", string.format("%x, %x", bind[2], ipv4_ip)) end
      if bind[2] == ipv4_ip then
         if port >= bind[3] and port <= bind[4] then
            local lwaftr_ipv6 = self:_get_lwAFTR_ipv6(bind)
            return bind[1], lwaftr_ipv6
         end
      end
   end
   print("Nothing found for ipv4:port", format_ipv4(ipv4_ip),
      string.format("%i (0x%x)", port, port))
end

-- https://www.ietf.org/id/draft-farrer-softwire-br-multiendpoints-01.txt
-- Return the destination IPv6 address, *and the source IPv6 address*
function LwAftr:binding_lookup_ipv4_from_pkt(pkt, pre_ipv4_bytes)
   local dst_ip_start = pre_ipv4_bytes + 16
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = ffi.cast("uint32_t*", pkt.data + dst_ip_start)[0]
   -- TODO: don't assume the length of the IPv4 header; check IHL
   local ipv4_header_len = 20
   local dst_port_start = pre_ipv4_bytes + ipv4_header_len + 2
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
            print("ipv6bind")
            print_ipv6(bind[1])
            print_ipv6(ipv6_src_ip)
            if C.memcmp(bind[1], ipv6_src_ip, 16) == 0 then
               local expected_dst = self:_get_lwAFTR_ipv6(bind)
               print("DST_MEMCMP", expected_dst, ipv6_dst_ip)
               print_ipv6(expected_dst)
               print_ipv6(ipv6_dst_ip)
               if C.memcmp(expected_dst, ipv6_dst_ip, 16) == 0 then
                  return true
               end
            end
         end
      end
   end
   return false
end

local function fixup_tcp_checksum(pkt, csum_offset, fixup_val)
   local csum = C.ntohs(ffi.cast("uint16_t*", pkt.data + csum_offset)[0])
   print("old csum", string.format("%x", csum))
   csum = csum + fixup_val
   -- TODO/FIXME: *test* the following loop
   while csum > 0xffff do -- process the carry nibbles
      local carry = bit.rshift(csum, 16)
      csum = bit.band(csum, 0xffff) + carry
   end
   print("new csum", string.format("%x", csum))
   pkt.data[csum_offset] = bit.rshift(bit.band(csum, 0xff00), 8)
   pkt.data[csum_offset + 1] = bit.band(csum, 0xff)
end

-- ICMPv4 type 3 code 1, as per the internet draft.
-- That is: "Destination unreachable: destination host unreachable"
-- The target IPv4 address + port is not in the table.
function LwAftr:_icmp_after_discard(to_ip)
   local new_pkt = packet.new_packet() -- TODO: recycle
   local dgram = datagram:new(new_pkt) -- TODO: recycle this
   print("gothere1")
   local icmp_header = icmp:new(3, 1) -- TODO: make symbolic
   print(self.aftr_ipv4_ip, to_ip)
   local ipv4_header = ipv4:new({ttl = 255, protocol = proto_icmp,
                                 src = self.aftr_ipv4_ip, dst = to_ip})
   print("got here 2")
   local ethernet_header = ethernet:new({src = self.aftr_mac_inet_side,
                                        dst = self.inet_mac,
                                        type = ethertype_ipv4})
   dgram:push(icmp_header)
   dgram:push(ipv4_header)
   dgram:push(ethernet_header)
   return new_pkt
end

-- ICMPv6 type 1 code 5, as per the internet draft.
-- 'Destination unreachable: source address failed ingress/egress policy'
-- The source (ipv6, ipv4, port) tuple is not in the table.
function LwAftr:_icmp_b4_lookup_failed(to_ip)
   local new_pkt = packet.new_packet() -- TODO: recycle
   local dgram = datagram:new(new_pkt) -- TODO: recycle this
   local icmp_header = icmp:new(1, 5) -- TODO: make symbolic, FIXME make ICMPv6
   local ipv6_header = ipv6:new({ttl = 255, next_header = proto_icmpv6,
                                 src = self.aftr_ipv6_ip, dst = to_ip})
   local ethernet_header = ethernet:new({src = self.aftr_mac_b4_side,
                                        dst = self.b4_mac,
                                        type = ethertype_ipv6})
   dgram:push(icmp_header)
   dgram:push(ipv6_header)
   dgram:push(ethernet_header)
   return new_pkt
end

function LwAftr:_add_inet_ethernet(pkt)
   local dgram = datagram:new(pkt, ipv4) -- TODO: recycle this
   local ethernet_header = ethernet:new({src = self.aftr_mac_inet_side,
                                         dst = self.inet_mac,
                                         type = ethertype_ipv4})
   dgram:push(ethernet_header)
   return pkt
end

-- Given a packet containing IPv4 and Ethernet, encapsulate the IPv4 portion.
function LwAftr:ipv6_encapsulate(pkt, next_hdr_type, ipv6_src, ipv6_dst,
                                 ether_src, ether_dst)
   -- TODO: decrement the IPv4 ttl as this is part of forwarding
   -- TODO: do not encapsulate if ttl was already 0; send icmp
   local dgram = datagram:new(pkt, ethernet) -- TODO: recycle this
   dgram:pop_raw(ethernet_header_size)
   print("ipv6", ipv6_src, ipv6_dst)
   local payload_len = pkt.length
   if debug then
      print("Original packet, minus ethernet:")
      print_pkt(pkt)
   end

   local ipv6_hdr = ipv6:new({next_header = next_hdr_type,
                              hop_limit = 255,
                              src = ipv6_src,
                              dst = ipv6_dst}) 
   pp(ipv6_hdr)

   local eth_hdr = ethernet:new({src = ether_src,
                                 dst = ether_dst,
                                 type = ethertype_ipv6})
   dgram:push(ipv6_hdr)
   -- The API makes setting the payload length awkward; set it manually
   -- Todo: less awkward way to write 16 bits of a number into cdata
   pkt.data[4] = bit.rshift(bit.band(payload_len, 0xff00), 8)
   pkt.data[5] = bit.band(payload_len, 0xff)
   dgram:push(eth_hdr)
   if debug then
      print("encapsulated packet:")
      print_pkt(pkt)
   end
   return pkt
end

-- TODO: correctly handle fragmented IPv4 packets
-- TODO: correctly deal with IPv6 packets that need to be fragmented
-- The incoming packet is a complete one with ethernet headers.
function LwAftr:_encapsulate_ipv4(pkt)
   local ipv6_dst, ipv6_src = self:binding_lookup_ipv4_from_pkt(pkt, ethernet_header_size)
   if not ipv6_dst then
      if debug then print("lookup failed") end
      if self.ipv4_lookup_failed_policy == lwconf.policies['DROP'] then
         return nil -- lookup failed
      elseif self.ipv4_lookup_failed_policy == lwconf.policies['DISCARD_PLUS_ICMP'] then
         local src_ip_start = ethernet_header_size + 12
         --local to_ip = ffi.cast("uint32_t*", pkt.data + src_ip_start)[0]
         local to_ip = pkt.data + src_ip_start
         return self:_icmp_after_discard(to_ip)-- ICMPv4 type 3 code 1
      else
         error("LwAftr: unknown policy" .. self.ipv4_lookup_failed_policy)
      end
   end

   local ether_src = self.aftr_mac_b4_side 
   local ether_dst = self.b4_mac -- FIXME: this should probaby use NDP

   local ttl_offset = ethernet_header_size + 8
   local ttl = pkt.data[ttl_offset]
   print('ttl', ttl, pkt.data[ttl_offset])
   -- Do not encapsulate packets that already had a ttl of zero
   if ttl == 0 then return nil end
 
   local proto_offset = ethernet_header_size + 9
   local proto = pkt.data[proto_offset]

   if proto == proto_icmp and self.icmp_policy == conf.policies['DROP'] then return nil end

   pkt.data[ttl_offset] = ttl - 1
   if proto == proto_tcp then
      local csum_offset = ethernet_header_size + 10
      -- ttl_offset is even, so multiply the ttl change by 0x100.
      -- It's added, because the checksum is is ones-complement.
      fixup_tcp_checksum(pkt, csum_offset, 0x100)
   end
   local next_hdr = 4 -- IPv4

   return self:ipv6_encapsulate(pkt, next_hdr, ipv6_src, ipv6_dst,
                                ether_src, ether_dst)
end

-- Return a packet without ethernet or IPv6 headers.
-- TODO: this does not decrement TTL; is this correct?
function LwAftr:decapsulate(pkt)
   local dgram = datagram:new(pkt) -- TODO: recycle this
   -- FIXME: don't hardcode the values like this
   dgram:pop_raw(ethernet_header_size + ipv6_header_size)
   return pkt
end


-- TODO: rewrite this to use parse
function LwAftr:from_b4(pkt)
   -- check src ipv4, ipv6, and port against the binding table
   local ipv6_src_ip_offset = ethernet_header_size + 8
   local ipv6_dst_ip_offset = ethernet_header_size + 24
   -- FIXME: deal with multiple IPv6 headers
   local ipv4_src_ip_offset = ethernet_header_size + ipv6_header_size + 12
   -- FIXME: as above + varlen ipv4 + non-tcp/non-udp payloads
   local ipv4_src_port_offset = ethernet_header_size + ipv6_header_size +
                                ipv4_header_size
   local ipv6_src_ip = pkt.data + ipv6_src_ip_offset
   local ipv6_dst_ip = pkt.data + ipv6_dst_ip_offset
   local ipv4_src_ip = ffi.cast("uint32_t*", pkt.data + ipv4_src_ip_offset)[0]
   local ipv4_src_port = C.ntohs(ffi.cast("uint16_t*", pkt.data + ipv4_src_port_offset)[0])
   if self:in_binding_table(ipv6_src_ip, ipv6_dst_ip, ipv4_src_ip, ipv4_src_port) then
      -- Is it worth optimizing this to change src_eth, src_ipv6, ttl, checksum,
      -- rather than decapsulating + re-encapsulating? It would be faster, but more code.
      self:decapsulate(pkt)
      print("self.hairpinning is", self.hairpinning)
      print("binding_lookup...", self:binding_lookup_ipv4_from_pkt(pkt, 0))
      if self.hairpinning and self:binding_lookup_ipv4_from_pkt(pkt, 0) then
         -- FIXME: shifting the packet ethernet_header_size right would suffice here
         -- The ethernet data is thrown away by _encapsulate_ipv4 anyhow.
         local dgram = datagram:new(pkt) -- TODO: recycle this
         local ethernet_header = ethernet:new({src = self.b4_mac,
                                               dst = self.aftr_mac_b4_side,
                                               type = ethertype_ipv4})
         dgram:push(ethernet_header)
         return self:_encapsulate_ipv4(pkt)
      else
         return self:_add_inet_ethernet(pkt)
      end
   elseif self.from_b4_lookup_failed_policy == lwconf.policies['DISCARD_PLUS_ICMPv6'] then
      return self:_icmp_b4_lookup_failed(ipv6_src_ip)
   else
      return nil
   end
end

-- Modify the given packet in-place, and forward it, drop it, or reply with
-- an ICMP or ICMPv6 packet as per the internet draft and configuration policy.
-- TODO: handle ICMPv6 as per RFC 2473
-- TODO: revisit this and check on performance idioms
function LwAftr:push ()
   local i, o = self.input.input, self.output.output
   while not link.empty(i) and not link.full(o) do
      local pkt = link.receive(i)
      if debug then print("got a pkt") end
      local ethertype_offset = 12
      local ethertype = C.ntohs(ffi.cast('uint16_t*', pkt.data + ethertype_offset)[0])
      local out_pkt = nil

      if ethertype == ethertype_ipv4 then -- Incoming packet from the internet
         out_pkt = self:_encapsulate_ipv4(pkt)
      elseif ethertype == ethertype_ipv6 then
         -- decapsulate iff the source was a b4, and forward/hairpin
         out_pkt = self:from_b4(pkt)
      end -- FIXME: silently drop other types; is this the right thing to do?
      --if debug then print("encapsulated") end
      if out_pkt then
         link.transmit(o, out_pkt)
         if debug then print("tx'd") end
      else 
         if debug then print ("Nothing transmitted") end
      end
   end
end

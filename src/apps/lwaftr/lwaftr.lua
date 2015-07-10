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

-- http://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml
local proto_icmp = 1
local proto_tcp = 6

-- http://www.iana.org/assignments/ieee-802-numbers/ieee-802-numbers.xhtml
local ethertype_ipv4 = 0x0800
local ethertype_ipv6 = 0x86DD

local ethernet_header_size = 14 -- TODO: deal with 802.1Q tags?
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

function LwAftr:binding_lookup_ipv4(ipv4_ip, port)
   print(ipv4_ip, 'port: ', port)
   pp(self.binding_table)
   for _, bind in ipairs(self.binding_table) do
      if debug then print("CHECK", string.format("%x, %x", bind[2], ipv4_ip)) end
      if bind[2] == ipv4_ip then
         if port >= bind[3] and port <= bind[4] then
            return bind[1]
         end
      end
   end
end

function LwAftr:binding_lookup_ipv4_from_pkt(pkt)
   local dst_ip_start = ethernet_header_size + 16
   -- Note: ip is kept in network byte order, regardless of host byte order
   local ip = ffi.cast("uint32_t*", pkt.data + dst_ip_start)[0]
   -- TODO: don't assume the length of the IPv4 header; check IHL
   local ipv4_header_len = 20
   local dst_port_start = ipv4_header_len + 2
   local port = C.ntohs(ffi.cast("uint16_t*", pkt.data + dst_port_start)[0])
   return self:binding_lookup_ipv4(ip, port)
end

local function fixup_tcp_checksum(pkt, csum_offset, fixup_val)
   local csum = C.ntohs(ffi.cast("uint16_t*", pkt.data + csum_offset)[0])
   print("old csum", string.format("%x", csum))
   csum = csum + fixup_val
   -- TODO: *test* the following loop
   while csum > 0xffff do -- process the carry nibbles
      local carry = bit.rshift(csum, 16)
      csum = bit.band(csum, 0xffff) + carry
   end
   print("new csum", string.format("%x", csum))
   pkt.data[csum_offset] = bit.rshift(bit.band(csum, 0xff00), 8)
   pkt.data[csum_offset + 1] = bit.band(csum, 0xff)
end

-- ICMPv4 type 3 code 1, as per the internet draft.
-- The target IPv4 address + port is not in the table.
function LwAftr:_icmp_after_discard(to_ip)
   local new_pkt = packet.new() -- TODO: recycle
   local dgram = datagram:new(new_pkt) -- TODO: recycle this
   local icmp_header = icmp:new(3, 1) -- TODO: make symbolic
   local ipv4_header = ipv4:new({ttl = 255, protocol = proto_icmp,
                                 src = self.aftr_ipv4_ip, dst = to_ip})
   local ethernet_header = ethernet:new({src = self.aftr_mac_inet_side,
                                        dst = self.inet_mac,
                                        ethertype_ipv4})
   dgram:push(icmp_header)
   dgram:push(ipv4_header)
   dgram:push(ethernet_header)
   return new_pkt
end

-- Given a payload, encapsulate it.
-- A plausible payload is a packet with IPv4 and TCP headers, but no ethernet.
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
function LwAftr:_encapsulate_ipv4(pkt)
   local ipv6_dst = self:binding_lookup_ipv4_from_pkt(pkt)
   if not ipv6_dst then
      if debug then print("lookup failed") end
      if self.ipv4_lookup_failed_policy == lwconf.DROP_POLICY then
         return nil -- lookup failed
      elseif self.ipv4_lookup_failed_policy == lwconf.DISCARD_PLUS_ICMP_POLICY then
         local src_ip_start = ethernet_header_size + 12
         local to_ip = ffi.cast("uint32_t*", pkt.data + src_ip_start)[0]
         return LwAftr:_icmp_after_discard(to_ip)-- ICMPv4 type 3 code 1
      else
         error("LwAftr: unknown policy" .. self.ipv4_lookup_failed_policy)
      end
   end
   local ipv6_src = self.aftr_ipv6_ip

   local ether_src = self.aftr_mac_b4_side 
   local ether_dst = self.b4_mac -- FIXME: this should probaby use NDP

   local ttl_offset = ethernet_header_size + 8
   local ttl = pkt.data[ttl_offset]
   print('ttl', ttl, pkt.data[ttl_offset])
   -- Do not encapsulate packets that already had a ttl of zero
   if ttl == 0 then return nil end
 
   local proto_offset = ethernet_header_size + 9
   local proto = pkt.data[proto_offset]

   if proto == proto_icmp and self.icmp_policy == conf.DROP_POLICY then return nil end

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

-- Modify the given packet
-- TODO: modifiable policy
function LwAftr:ipv6_or_drop(pkt)
   local ethertype_offset = 12
   local ethertype = C.ntohs(ffi.cast('uint16_t*', pkt.data + ethertype_offset)[0])

   if ethertype == ethertype_ipv4 then
      return self:_encapsulate_ipv4(pkt)
   elseif ethertype == ethertype_ipv6 then
      -- TODO: handle ICMPv6 as per RFC 2473
      -- TODO: decapsulate if the source was a b4, and forward/hairpin
   else -- silently drop other types: TODO: is this the right thing to do?
      return nil
   end
end

-- TODO: revisit this and check on performance idioms
function LwAftr:push ()
   local i, o = self.input.input, self.output.output
   local pkt = link.receive(i)
   if debug then print("got a pkt") end
   local encap_pkt = self:ipv6_or_drop(pkt)
   if debug then print("encapsulated") end
   if encap_pkt then link.transmit(o, encap_pkt) end
   if debug then print("tx'd") end
end

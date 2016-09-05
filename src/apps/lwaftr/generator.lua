module(..., package.seeall)

-- This module implements two clases: `from_inet` and `from_b4`.
--
-- `from_inet` class emulates IPv4 traffic coming from the internet to then
-- lwAFTR. It requires at least a starting IPv4 address and a PSID length
-- value. On each iteration, destination port is incremented, so packets can
-- match a different softwire belonging to a different PSID. Once all the port
-- sets have been iterated, IPv4 address is increased by one unit and
-- destination port comes -- back to its original value.
--
-- `from_b4` class emulates IPv4-in-IPv6 traffic coming from the b4 to the
-- lwAFTR. It requires several parameters: starting IPv4 address, starting B4
-- address, IPv6 lwAFTR address and PSID length value. It works similarly to
-- `from_inet`.

local ipsum = require("lib.checksum").ipsum
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local lib = require("core.lib")
local link = require("core.link")
local lwtypes = require("apps.lwaftr.lwtypes")
local packet = require("core.packet")

local ffi = require("ffi")
local C = ffi.C

local cast = ffi.cast
local bitfield = lib.bitfield

local DEFAULT_TTL = 255
local VLAN_TPID = C.htons(0x8100)

local ethernet_header_ptr_type = lwtypes.ethernet_header_ptr_type
local ethernet_vlan_header_ptr_type = lwtypes.ethernet_vlan_header_ptr_type
local ipv4_header_ptr_type = lwtypes.ipv4_header_ptr_type
local ipv6_header_ptr_type = lwtypes.ipv6_header_ptr_type
local udp_header_ptr_type = lwtypes.udp_header_ptr_type

local ipv4_header_size = lwtypes.ipv4_header_size
local ipv6_header_size = lwtypes.ipv6_header_size
local udp_header_size = lwtypes.udp_header_size

local IPV4_DSCP_AND_ECN_OFFSET = 1
local PROTO_IPV4 = C.htons(0x0800)
local PROTO_IPV4_ENCAPSULATION = 0x4
local PROTO_IPV6 = C.htons(0x86DD)
local PROTO_UDP = 17

from_inet = {}

function from_inet:new(conf)
   if not conf.shift then conf.shift = 16 - conf.psid_len end
   assert(conf.psid_len + conf.shift == 16)
   local psid_len, shift = conf.psid_len, conf.shift
   local start_inet = ipv4:pton(conf.start_inet)
   local start_port = 2^shift
   if conf.max_packets then
      conf.max_packets_per_iter = conf.max_packets
   end
   local o = {
      dst_ip = start_inet,
      dst_port = start_port,
      inc_port = 2^shift,
      max_packets_per_iter = conf.max_packets_per_iter or 10,
      iter_count = 1, -- Iteration counter. Reset when overpasses max_packet_per_iter.
      num_ips = conf.num_ips or 10,
      ip_count = 1,   -- IPv4 counter. Reset when overpasses num_ips.
      max_packets = conf.max_packets,
      packet_size = conf.packet_size or 550,
      psid_count = 1,
      psid_max = 2^psid_len,
      start_inet = start_inet,
      start_port = start_port,
      tx_packets = 0,
      src_mac = conf.src_mac,
      dst_mac = conf.dst_mac,
      vlan_tag = conf.vlan_tag and C.htons(conf.vlan_tag),
   }
   o = setmetatable(o, { __index = from_inet })
   o.master_pkt = o:master_packet()
   return o
end

function from_inet:master_packet()
   return ipv4_packet({
      src_mac = self.src_mac,
      dst_mac = self.dst_mac,
      src_ip = ipv4:pton("10.10.10.1"),
      dst_ip = self.dst_ip,
      src_port = C.htons(12345),
      dst_port = C.htons(self.dst_port),
      packet_size = self.packet_size,
      vlan_tag = self.vlan_tag,
   })
end

function ipv4_packet(params)
   local p = packet.allocate()

   local ether_hdr = cast(ethernet_header_ptr_type, p.data)
   local ethernet_header_size
   if params.vlan_tag then
      ether_hdr = cast(ethernet_vlan_header_ptr_type, p.data)
      ether_hdr.vlan.tpid = VLAN_TPID
      ether_hdr.vlan.tag = params.vlan_tag
      ethernet_header_size = lwtypes.ethernet_vlan_header_size
   else
      ether_hdr = cast(ethernet_header_ptr_type, p.data)
      ethernet_header_size = lwtypes.ethernet_header_size
   end
   ether_hdr.ether_dhost = params.dst_mac
   ether_hdr.ether_shost = params.src_mac
   ether_hdr.ether_type = PROTO_IPV4

   local ipv4_hdr = cast(ipv4_header_ptr_type, p.data + ethernet_header_size)
   ipv4_hdr.src_ip = params.src_ip
   ipv4_hdr.ttl = 15
   ipv4_hdr.ihl_v_tos = C.htons(0x4500)
   ipv4_hdr.id = 0
   ipv4_hdr.frag_off = 0
   ipv4_hdr.total_length = C.htons(params.packet_size - ethernet_header_size)
   ipv4_hdr.dst_ip = params.dst_ip
   ipv4_hdr.protocol = PROTO_UDP

   local udp_hdr = cast(udp_header_ptr_type, p.data + (ethernet_header_size +
      ipv4_header_size))
   udp_hdr.src_port = params.src_port
   udp_hdr.dst_port = params.dst_port
   udp_hdr.len = C.htons(params.packet_size - (ethernet_header_size + ipv4_header_size))
   udp_hdr.checksum = 0

   p.length = params.packet_size

   return p
end

function from_inet:pull()
   local o = assert(self.output.output)

   for i=1,engine.pull_npackets do
      if self.max_packets then
         if self.tx_packets == self.max_packets then break end
         self.tx_packets = self.tx_packets + 1
      end
      link.transmit(o, self:new_packet())
   end
end

function from_inet:new_packet()
   local p = self.master_pkt

   local ethernet_header_size
   if self.vlan_tag then
      ethernet_header_size = lwtypes.ethernet_vlan_header_size
   else
      ethernet_header_size = lwtypes.ethernet_header_size
   end

   -- Change destination IPv4
   local ipv4_hdr = cast(ipv4_header_ptr_type, p.data + ethernet_header_size)
   ipv4_hdr.dst_ip = self.dst_ip
   ipv4_hdr.checksum =  0
   ipv4_hdr.checksum = C.htons(ipsum(p.data + ethernet_header_size,
      ipv4_header_size, 0))

   -- Change destination port
   local udp_hdr = cast(udp_header_ptr_type, p.data + (ethernet_header_size + ipv4_header_size))
   udp_hdr.dst_port = C.htons(self.dst_port)

   self:next_softwire()

   return packet.clone(p)
end

function from_inet:next_softwire()
   self.dst_port = self.dst_port + self.inc_port
   self.psid_count = self.psid_count + 1
   -- Next IPv4 public address.
   if self.psid_count == self.psid_max then
      self.psid_count = 1
      self.dst_port = self.start_port
      self.dst_ip = inc_ipv4(self.dst_ip)
   end
   self.iter_count = self.iter_count + 1
   -- Iteration completed. Full restart.
   if self.iter_count > self.max_packets_per_iter
         or self.ip_count > self.num_ips then
      self.psid_count = 1
      self.dst_port = self.start_port
      self.dst_ip = self.start_inet
   end
end

function inc_ipv4(ipv4)
   for i=3,0,-1 do
      if ipv4[i] == 255 then
         ipv4[i] = 0
      else
         ipv4[i] = ipv4[i] + 1
         break
      end
   end
   return ipv4
end


from_b4 = {}

function from_b4:new(conf)
   if not conf.shift then conf.shift = 16 - conf.psid_len end
   assert(conf.psid_len + conf.shift == 16)
   local psid_len, shift = conf.psid_len, conf.shift
   local start_inet = ipv4:pton(conf.start_inet)
   local start_b4 = ipv6:pton(conf.start_b4)
   local start_port = 2^shift
   local packet_size = conf.packet_size or 550
   packet_size = packet_size - ipv6_header_size
   if conf.max_packets then
      conf.max_packets_per_iter = conf.max_packets
   end
   local o = {
      br = ipv6:pton(conf.br),
      inc_port = 2^shift,
      ip_count = 1,
      iter_count = 1,
      max_packets_per_iter = conf.max_packets_per_iter or 10,
      max_packets = conf.max_packets,
      num_ips = conf.num_ips or 10,
      packet_size = packet_size,
      psid_count = 1,
      psid_max = 2^psid_len,
      src_ipv4 = start_inet,
      src_ipv6 = start_b4,
      src_portv4 = start_port,
      start_b4 = start_b4,
      start_inet = start_inet,
      start_port = start_port,
      tx_packets = 0,
      src_mac = conf.src_mac,
      dst_mac = conf.dst_mac,
      vlan_tag = conf.vlan_tag and C.htons(conf.vlan_tag),
   }
   o = setmetatable(o, { __index = from_b4 })
   o.master_pkt = o:master_packet()
   return o
end

function from_b4:master_packet()
   local ipv4_pkt = ipv4_packet({
      src_mac = self.src_mac,
      dst_mac = self.dst_mac,
      src_ip = self.src_ipv4,
      dst_ip = ipv4:pton("10.10.10.1"),
      src_port = C.htons(self.src_portv4),
      dst_port = C.htons(12345),
      packet_size = self.packet_size,
      vlan_tag = self.vlan_tag,
   })
   return ipv6_encapsulate(ipv4_pkt, {
      src_mac = self.src_mac,
      dst_mac = self.dst_mac,
      src_ip = self.start_b4,
      dst_ip = self.br,
      vlan_tag = self.vlan_tag,
   })
end

function ipv6_encapsulate(ipv4_pkt, params)
   local p = assert(ipv4_pkt)

   -- IPv4 packet is tagged
   local ethernet_header_size 
   if params.vlan_tag then
      ethernet_header_size = lwtypes.ethernet_vlan_header_size
   else
      ethernet_header_size = lwtypes.ethernet_header_size
   end

   local payload_length = p.length - ethernet_header_size
   local dscp_and_ecn = p.data[ethernet_header_size + IPV4_DSCP_AND_ECN_OFFSET]
   packet.shiftright(p, ipv6_header_size)

   -- IPv6 packet is tagged
   if params.vlan_tag then
      eth_hdr = cast(ethernet_vlan_header_ptr_type, p.data)
      eth_hdr.vlan.tag = params.vlan_tag
      ethernet_header_size = lwtypes.ethernet_vlan_header_size
   else
      eth_hdr = cast(ethernet_header_ptr_type, p.data)
      ethernet_header_size = lwtypes.ethernet_header_size
   end
   eth_hdr.ether_dhost = params.dst_mac
   eth_hdr.ether_shost = params.src_mac
   eth_hdr.ether_type = PROTO_IPV6

   local ipv6_hdr = cast(ipv6_header_ptr_type, p.data + ethernet_header_size)
   bitfield(32, ipv6_hdr, 'v_tc_fl', 0, 4, 6) -- IPv6 Version
   bitfield(32, ipv6_hdr, 'v_tc_fl', 4, 8, dscp_and_ecn) -- Traffic class
   ipv6_hdr.payload_length = C.htons(payload_length)
   ipv6_hdr.next_header = PROTO_IPV4_ENCAPSULATION
   ipv6_hdr.hop_limit = DEFAULT_TTL
   ipv6_hdr.src_ip = params.src_ip
   ipv6_hdr.dst_ip = params.dst_ip

   local total_length = p.length -- + (ethernet_header_size + ipv6_header_size)
   p.length = total_length

   return p, total_length
end

function from_b4:pull()
   local o = assert(self.output.output)

   for i=1,engine.pull_npackets do
      if self.max_packets then
         if self.tx_packets == self.max_packets then break end
         self.tx_packets = self.tx_packets + 1
      end
      link.transmit(o, self:new_packet())
   end
end

function from_b4:new_packet()
   local ipv6 = self.master_pkt

   -- IPv6 packet is tagged
   local ethernet_header_size
   if self.vlan_tag then
      ethernet_header_size = lwtypes.ethernet_vlan_header_size
   else
      ethernet_header_size = lwtypes.ethernet_header_size
   end

   -- Set IPv6 source address
   local ipv6_hdr = cast(ipv6_header_ptr_type, ipv6.data + ethernet_header_size)
   ipv6_hdr.src_ip = self.src_ipv6
   -- Set tunneled IPv4 source address
   local ipv6_payload = ethernet_header_size + ipv6_header_size
   ipv4_hdr = cast(ipv4_header_ptr_type, ipv6.data + ipv6_payload)
   ipv4_hdr.src_ip = self.src_ipv4
   ipv4_hdr.checksum =  0
   ipv4_hdr.checksum = C.htons(ipsum(ipv6.data + ipv6_payload,
      ipv4_header_size, 0))
   -- Set tunneled IPv4 source port
   udp_hdr = cast(udp_header_ptr_type, ipv6.data + (ipv6_payload + ipv4_header_size))
   udp_hdr.src_port = C.htons(self.src_portv4)

   self:next_softwire()

   return packet.clone(ipv6)
end

function from_b4:next_softwire()
   self.src_portv4 = self.src_portv4 + self.inc_port
   self.src_ipv6 = inc_ipv6(self.src_ipv6)
   self.psid_count = self.psid_count + 1
   -- Next public IPv4 adress.
   if self.psid_count == self.psid_max then
      self.psid_count = 1
      self.src_portv4 = self.start_port
      self.src_ipv4 = inc_ipv4(self.src_ipv4)
   end
   self.iter_count = self.iter_count + 1
   -- Iteration completed. Full restart.
   if self.iter_count > self.max_packets_per_iter
         or self.ip_count > self.num_ips then
      self.psid_count = 1
      self.src_portv4 = self.start_port
      self.src_ipv4 = self.start_inet
      self.src_ipv6 = self.start_b4
   end
end

function inc_ipv6(ipv6)
   for i=15,0,-1 do
      if ipv6[i] == 255 then
         ipv6[i] = 0
      else
         ipv6[i] = ipv6[i] + 1
         break
      end
   end
   return ipv6
end

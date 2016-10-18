module(...,package.seeall)

local lib = require("core.lib")
local app = require("core.app")
local packet = require("core.packet")
local link = require("core.link")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")
local ipsum = require("lib.checksum").ipsum

local ffi = require("ffi")
local C = ffi.C
local cast = ffi.cast
local copy = ffi.copy

local PROTO_IPV4_ENCAPSULATION = 0x4
local PROTO_VLAN = C.htons(0x8100)
local PROTO_IPV4 = C.htons(0x0800)
local PROTO_IPV6 = C.htons(0x86DD)

local DEFAULT_TTL = 255
local MAGIC = 0xaffeface

local ether_header_t = ffi.typeof[[
struct {
   uint8_t  ether_dhost[6];
   uint8_t  ether_shost[6];
   uint16_t ether_type;
} __attribute__((packed))
]]
local ether_header_ptr_type = ffi.typeof("$*", ether_header_t)
local ethernet_header_size = ffi.sizeof(ether_header_t)
local OFFSET_ETHERTYPE = 12

local ether_vlan_header_type = ffi.typeof([[
struct {
   uint16_t tag;
   uint16_t ether_type;
}
]])
ether_vlan_header_ptr_type = ffi.typeof("$*", ether_vlan_header_type)
ether_vlan_header_size = ffi.sizeof(ether_vlan_header_type)
local OFFSET_ETHERTYPE_VLAN = OFFSET_ETHERTYPE + ether_vlan_header_size

local ipv4hdr_t = ffi.typeof[[
struct {
   uint16_t ihl_v_tos; // ihl:4, version:4, tos(dscp:6 + ecn:2)
   uint16_t total_length;
   uint16_t id;
   uint16_t frag_off; // flags:3, fragmen_offset:13
   uint8_t  ttl;
   uint8_t  protocol;
   uint16_t checksum;
   uint8_t  src_ip[4];
   uint8_t  dst_ip[4];
} __attribute__((packed))
]]
local ipv4_header_ptr_type = ffi.typeof("$*", ipv4hdr_t)

local ipv6_ptr_type = ffi.typeof([[
struct {
   uint32_t v_tc_fl; // version, tc, flow_label
   uint16_t payload_length;
   uint8_t  next_header;
   uint8_t  hop_limit;
   uint8_t  src_ip[16];
   uint8_t  dst_ip[16];
} __attribute__((packed))
]])
local ipv6_header_ptr_type = ffi.typeof("$*", ipv6_ptr_type)
local ipv6_header_size = ffi.sizeof(ipv6_ptr_type)

local udp_header_t = ffi.typeof[[
struct {
   uint16_t    src_port;
   uint16_t    dst_port;
   uint16_t    len;
   uint16_t    checksum;
} __attribute__((packed))
]]
local udp_header_ptr_type = ffi.typeof("$*", udp_header_t)
local udp_header_size = ffi.sizeof(udp_header_ptr_type)

local payload_t = ffi.typeof[[
struct {
   uint32_t    magic;
   uint32_t    number;
} __attribute__((packed))
]]
local payload_ptr_type = ffi.typeof("$*", payload_t)
local payload_size = ffi.sizeof(payload_t)

local uint16_ptr_t = ffi.typeof("uint16_t*")
local uint32_ptr_t = ffi.typeof("uint32_t*")

local n_cache_src_ipv6 = ipv6:pton("::")

local function rd32(offset)
   return cast(uint32_ptr_t, offset)[0]
end

local function wr32(offset, val)
   cast(uint32_ptr_t, offset)[0] = val
end

local function inc_ipv6(ipv6)
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

Lwaftrgen = {
   config = {
      sizes = {required=true},
      dst_mac = {required=true},
      src_mac = {required=true},
      rate = {required=true},
      vlan = {},
      b4_ipv6 = {},
      b4_ipv4 = {},
      public_ipv4 = {},
      aftr_ipv6 = {},
      ipv6_only = {},
      ipv4_only = {},
      b4_port = {},
      protocol = {},
      count = {},
      single_pass = {}
   }
}

local receive, transmit = link.receive, link.transmit

function Lwaftrgen:new(conf)
   local dst_mac = ethernet:pton(conf.dst_mac)
   local src_mac = ethernet:pton(conf.src_mac)
   local vlan = conf.vlan
   local b4_ipv6 = conf.b4_ipv6 and ipv6:pton(conf.b4_ipv6)
   local b4_ipv4 = conf.b4_ipv4 and ipv4:pton(conf.b4_ipv4)
   local public_ipv4 = conf.public_ipv4 and ipv4:pton(conf.public_ipv4)
   local aftr_ipv6 = conf.aftr_ipv6 and ipv6:pton(conf.aftr_ipv6)

   local ipv4_pkt = packet.allocate()
   local eth_hdr = cast(ether_header_ptr_type, ipv4_pkt.data)
   eth_hdr.ether_dhost, eth_hdr.ether_shost = dst_mac, src_mac

   local ipv4_hdr, udp_offset
   if vlan then
      udp_offset = 38
      eth_hdr.ether_type = PROTO_VLAN
      local vlan_hdr = cast(ether_vlan_header_ptr_type, ipv4_pkt.data + ethernet_header_size)
      vlan_hdr.ether_type = PROTO_IPV4
      vlan_hdr.tag = C.htons(vlan)
      ipv4_hdr = cast(ipv4_header_ptr_type, ipv4_pkt.data + ethernet_header_size + ether_vlan_header_size)
   else
      udp_offset = 34
      eth_hdr.ether_type = PROTO_IPV4
      ipv4_hdr = cast(ipv4_header_ptr_type, ipv4_pkt.data + ethernet_header_size)
   end

   ipv4_hdr.src_ip = public_ipv4
   ipv4_hdr.dst_ip = b4_ipv4
   ipv4_hdr.ttl = 15
   ipv4_hdr.ihl_v_tos = C.htons(0x4500) -- v4
   ipv4_hdr.id = 0
   ipv4_hdr.frag_off = 0

   local ipv4_udp_hdr, ipv4_payload

   ipv4_hdr.protocol = 17  -- UDP(17)
   ipv4_udp_hdr = cast(udp_header_ptr_type, ipv4_pkt.data + udp_offset)
   ipv4_udp_hdr.src_port = C.htons(12345)
   ipv4_udp_hdr.checksum = 0
   ipv4_payload = cast(payload_ptr_type, ipv4_pkt.data + udp_offset + udp_header_size)
   ipv4_payload.magic = MAGIC
   ipv4_payload.number = 0

   -- IPv4 in IPv6 packet
   copy(n_cache_src_ipv6, b4_ipv6, 16)
   local ipv6_pkt = packet.allocate()
   local eth_hdr = cast(ether_header_ptr_type, ipv6_pkt.data)
   eth_hdr.ether_dhost, eth_hdr.ether_shost = dst_mac, src_mac


   local ipv6_hdr, ipv6_ipv4_hdr
   if vlan then
      eth_hdr.ether_type = PROTO_VLAN
      local vlan_hdr = cast(ether_vlan_header_ptr_type, ipv6_pkt.data + ethernet_header_size)
      vlan_hdr.ether_type = PROTO_IPV6
      vlan_hdr.tag = C.htons(vlan)
      ipv6_hdr = cast(ipv6_header_ptr_type, ipv6_pkt.data + ethernet_header_size + ether_vlan_header_size)
      ipv6_ipv4_hdr = cast(ipv4_header_ptr_type, ipv6_pkt.data + ethernet_header_size + ether_vlan_header_size + ipv6_header_size)
   else
      eth_hdr.ether_type = PROTO_IPV6
      ipv6_hdr = cast(ipv6_header_ptr_type, ipv6_pkt.data + ethernet_header_size)
      ipv6_ipv4_hdr = cast(ipv4_header_ptr_type, ipv6_pkt.data + ethernet_header_size + ipv6_header_size)
   end

   lib.bitfield(32, ipv6_hdr, 'v_tc_fl', 0, 4, 6) -- IPv6 Version
   lib.bitfield(32, ipv6_hdr, 'v_tc_fl', 4, 8, 1) -- Traffic class
   ipv6_hdr.next_header = PROTO_IPV4_ENCAPSULATION
   ipv6_hdr.hop_limit = DEFAULT_TTL
   ipv6_hdr.dst_ip = aftr_ipv6

   ipv6_ipv4_hdr.dst_ip = public_ipv4
   ipv6_ipv4_hdr.ttl = 15
   ipv6_ipv4_hdr.ihl_v_tos = C.htons(0x4500) -- v4
   ipv6_ipv4_hdr.id = 0
   ipv6_ipv4_hdr.frag_off = 0

   local ipv6_ipv4_udp_hdr, ipv6_payload

   local total_packet_count = 0
   for _,size in ipairs(conf.sizes) do
      -- count for IPv4 and IPv6 packets (40 bytes IPv6 encap header)
      if conf.ipv4_only or conf.ipv6_only then 
         total_packet_count = total_packet_count + 1
      else
         total_packet_count = total_packet_count + 2
      end
   end

   ipv6_ipv4_hdr.protocol = 17  -- UDP(17)
   ipv6_ipv4_udp_hdr = cast(udp_header_ptr_type, ipv6_pkt.data + udp_offset + ipv6_header_size)
   ipv6_ipv4_udp_hdr.dst_port = C.htons(12345)
   ipv6_ipv4_udp_hdr.checksum = 0
   ipv6_payload = cast(payload_ptr_type, ipv6_pkt.data + udp_offset + ipv6_header_size + udp_header_size)
   ipv6_payload.magic = MAGIC
   ipv6_payload.number = 0

   local o = {
      b4_ipv6 = b4_ipv6,
      b4_ipv4 = b4_ipv4,
      b4_port = conf.b4_port,
      current_port = conf.b4_port,
      b4_ipv4_offset = 0,
      ipv6_address = n_cache_src_ipv6,
      count = conf.count,
      single_pass = conf.single_pass,
      current_count = 0,
      ipv4_pkt = ipv4_pkt,
      ipv4_hdr = ipv4_hdr,
      ipv4_payload = ipv4_payload,
      ipv6_hdr = ipv6_hdr,
      ipv6_pkt = ipv6_pkt,
      ipv6_payload = ipv6_payload,
      ipv6_ipv4_hdr = ipv6_ipv4_hdr,
      ipv4_udp_hdr = ipv4_udp_hdr,
      ipv6_ipv4_udp_hdr = ipv6_ipv4_udp_hdr,
      ipv4_only = conf.ipv4_only,
      ipv6_only = conf.ipv6_only,
      vlan = vlan,
      udp_offset = udp_offset,
      protocol = conf.protocol,
      rate = conf.rate,
      sizes = conf.sizes,
      total_packet_count = total_packet_count,
      bucket_content = conf.rate * 1e6,
      ipv4_packets = 0, ipv4_bytes = 0,
      ipv6_packets = 0, ipv6_bytes = 0,
      ipv4_packet_number = 0, ipv6_packet_number = 0,
      last_rx_ipv4_packet_number = 0, last_rx_ipv6_packet_number = 0,
      lost_packets = 0
   }
   return setmetatable(o, {__index=Lwaftrgen})
end

function Lwaftrgen:pull ()

   local output = self.output.output
   local input = self.input.input
   local ipv6_packets = self.ipv6_packets
   local ipv6_bytes = self.ipv6_bytes
   local ipv4_packets = self.ipv4_packets
   local ipv4_bytes = self.ipv4_bytes
   local lost_packets = self.lost_packets
   local udp_offset = self.udp_offset
   local o_ethertype = self.vlan and OFFSET_ETHERTYPE_VLAN or OFFSET_ETHERTYPE

   if self.current == 0 then
      main.exit(0)
   end

   -- count and trash incoming packets
   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if cast(uint16_ptr_t, pkt.data + o_ethertype)[0] == PROTO_IPV6 then
         ipv6_bytes = ipv6_bytes + pkt.length
         ipv6_packets = ipv6_packets + 1
         local payload = cast(payload_ptr_type, pkt.data + udp_offset + ipv6_header_size + udp_header_size)
         if payload.magic == MAGIC then
            if self.last_rx_ipv6_packet_number > 0 then
               lost_packets = lost_packets + payload.number - self.last_rx_ipv6_packet_number - 1  
            end
            self.last_rx_ipv6_packet_number = payload.number
         end
      else
         ipv4_bytes = ipv4_bytes + pkt.length
         ipv4_packets = ipv4_packets + 1
         local payload = cast(payload_ptr_type, pkt.data + udp_offset + udp_header_size)
         if payload.magic == MAGIC then
            if self.last_rx_ipv4_packet_number > 0 then
               lost_packets = lost_packets + payload.number - self.last_rx_ipv4_packet_number - 1  
            end
            self.last_rx_ipv4_packet_number = payload.number
         end
      end
      packet.free(pkt)
   end

   local cur_now = tonumber(app.now())
   self.period_start = self.period_start or cur_now
   local elapsed = cur_now - self.period_start
   if elapsed > 1 then
      local ipv6_packet_rate = ipv6_packets / elapsed / 1e6
      local ipv4_packet_rate = ipv4_packets / elapsed / 1e6
      local ipv6_octet_rate = ipv6_bytes * 8 / 1e9 / elapsed
      local ipv4_octet_rate = ipv4_bytes * 8 / 1e9 / elapsed
      local lost_rate = math.abs(lost_packets / (ipv6_octet_rate + ipv4_octet_rate) / 10000)
      print(string.format('v6+v4: %.3f+%.3f = %.6f MPPS, %.3f+%.3f = %.6f Gbps, lost %.3f%%',
      ipv6_packet_rate, ipv4_packet_rate, ipv6_packet_rate + ipv4_packet_rate,
      ipv6_octet_rate, ipv4_octet_rate, ipv6_octet_rate + ipv4_octet_rate, lost_rate))
      self.period_start = cur_now
      self.ipv6_bytes, self.ipv6_packets = 0, 0
      self.ipv4_bytes, self.ipv4_packets = 0, 0
      self.lost_packets = 0
   else
      self.ipv4_bytes, self.ipv4_packets = ipv4_bytes, ipv4_packets
      self.ipv6_bytes, self.ipv6_packets = ipv6_bytes, ipv6_packets
      self.lost_packets = lost_packets
   end

   local ipv4_hdr = self.ipv4_hdr
   local ipv6_hdr = self.ipv6_hdr
   local ipv6_ipv4_hdr = self.ipv6_ipv4_hdr
   local ipv4_udp_hdr = self.ipv4_udp_hdr
   local ipv6_ipv4_udp_hdr = self.ipv6_ipv4_udp_hdr

   local cur_now = tonumber(app.now())
   local last_time = self.last_time or cur_now
   self.bucket_content = self.bucket_content + self.rate * 1e6 * (cur_now - last_time)
   self.last_time = cur_now

   local limit = engine.pull_npackets
   while limit > self.total_packet_count and
      self.total_packet_count <= self.bucket_content do
      limit = limit - 1
      self.bucket_content = self.bucket_content - self.total_packet_count

      ipv4_hdr.dst_ip = self.b4_ipv4
      ipv6_ipv4_hdr.src_ip = self.b4_ipv4
      ipv6_hdr.src_ip = self.b4_ipv6
      local ipdst = C.ntohl(rd32(ipv4_hdr.dst_ip))
      ipdst = C.htonl(ipdst + self.b4_ipv4_offset)
      wr32(ipv4_hdr.dst_ip, ipdst)
      wr32(ipv6_ipv4_hdr.src_ip, ipdst)

      ipv4_udp_hdr.dst_port = C.htons(self.current_port)
      ipv6_ipv4_udp_hdr.src_port = C.htons(self.current_port)

      for _,size in ipairs(self.sizes) do

         if not self.ipv6_only then
            ipv4_hdr.total_length = C.htons(size)
            if self.vlan then
               ipv4_udp_hdr.len = C.htons(size - 28 + 4)
               self.ipv4_pkt.length = size + ethernet_header_size + 4
            else
               ipv4_udp_hdr.len = C.htons(size - 28)
               self.ipv4_pkt.length = size + ethernet_header_size
            end
            ipv4_hdr.checksum =  0
            ipv4_hdr.checksum = C.htons(ipsum(self.ipv4_pkt.data + ethernet_header_size, 20, 0))
            self.ipv4_payload.number = self.ipv4_packet_number;
            self.ipv4_packet_number = self.ipv4_packet_number + 1
            local ipv4_pkt = packet.clone(self.ipv4_pkt)
            transmit(output, ipv4_pkt)
         end

         if not self.ipv4_only then
            ipv6_hdr.payload_length = C.htons(size)
            ipv6_ipv4_hdr.total_length = C.htons(size)
            if self.vlan then
               ipv6_ipv4_udp_hdr.len = C.htons(size - 28 + 4)
               self.ipv6_pkt.length = size + 54 + 4
            else
               ipv6_ipv4_udp_hdr.len = C.htons(size - 28)
               self.ipv6_pkt.length = size + 54
            end
            self.ipv6_payload.number = self.ipv6_packet_number;
            self.ipv6_packet_number = self.ipv6_packet_number + 1
            local ipv6_pkt = packet.clone(self.ipv6_pkt)
            transmit(output, ipv6_pkt)
         end

       end 

       self.b4_ipv6 = inc_ipv6(self.b4_ipv6)
       self.current_port = self.current_port + self.b4_port
       if self.current_port > 65535 then
         self.current_port = self.b4_port
         self.b4_ipv4_offset = self.b4_ipv4_offset + 1
       end

       self.current_count = self.current_count + 1
       if self.current_count >= self.count then
         if self.single_pass then
           print(string.format("generated %d packets", self.current_count))
           -- make sure we won't generate more packets in the same breath, then exit
           self.current = 0
           self.bucket_content = 0 
         end
         self.current_count = 0
         self.current_port = self.b4_port
         self.b4_ipv4_offset = 0
         copy(self.b4_ipv6, self.ipv6_address, 16)
       end
     end
end


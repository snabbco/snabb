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
local cast = ffi.cast
local htons, ntohs = lib.htons, lib.ntohs
local htonl, ntohl = lib.htonl, lib.ntohl

local PROTO_IPV4_ENCAPSULATION = 0x4
local PROTO_IPV4 = htons(0x0800)
local PROTO_IPV6 = htons(0x86DD)

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
local ether_header_size = ffi.sizeof(ether_header_t)
local ether_min_frame_size = 64

-- The ethernet CRC field is not included in the packet as seen by
-- Snabb, but it is part of the frame and therefore a contributor to the
-- frame size.
local ether_crc_size = 4

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
local ipv4_header_size = ffi.sizeof(ipv4hdr_t)
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

local function inc_ipv4(ipv4)
   ipv4 = cast("uint32_t*", ipv4)
   ipv4[0] = htonl(ntohl(ipv4[0]) + 1)
end

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local receive, transmit = link.receive, link.transmit

B4Gen = {
   config = {
      sizes = {required=true},
      rate = {required=true},
      count = {default=1},
      single_pass = {default=false},
      b4_ipv6 = {required=true},
      aftr_ipv6 = {required=true},
      b4_ipv4 = {required=true},
      b4_port = {required=true},
      public_ipv4 = {required=true},
      frame_overhead = {default=0}
   }
}

function B4Gen:new(conf)
   local b4_ipv6 = ipv6:pton(conf.b4_ipv6)
   local b4_ipv4 = ipv4:pton(conf.b4_ipv4)
   local public_ipv4 = ipv4:pton(conf.public_ipv4)
   local aftr_ipv6 = ipv6:pton(conf.aftr_ipv6)

   -- Template IPv4 in IPv6 packet
   local pkt = packet.allocate()
   ffi.fill(pkt.data, packet.max_payload)
   local function h(ptr_type, offset, size)
      return cast(ptr_type, pkt.data + offset), offset + size
   end
   local eth_hdr,  ipv6_offset    = h(ether_header_ptr_type, 0,           ether_header_size)
   local ipv6_hdr, ipv4_offset    = h(ipv6_header_ptr_type,  ipv6_offset, ipv6_header_size)
   local ipv4_hdr, udp_offset     = h(ipv4_header_ptr_type,  ipv4_offset, ipv4_header_size)
   local udp_hdr,  payload_offset = h(udp_header_ptr_type,   udp_offset,  udp_header_size)
   local payload,  min_length     = h(payload_ptr_type,      payload_offset, payload_size)

   -- The offset in returned packets where we expect to find the payload.
   local rx_payload_offset = payload_offset - ipv6_header_size

   eth_hdr.ether_type = PROTO_IPV6

   lib.bitfield(32, ipv6_hdr, 'v_tc_fl', 0, 4, 6) -- IPv6 Version
   lib.bitfield(32, ipv6_hdr, 'v_tc_fl', 4, 8, 1) -- Traffic class
   ipv6_hdr.next_header = PROTO_IPV4_ENCAPSULATION
   ipv6_hdr.hop_limit = DEFAULT_TTL
   ipv6_hdr.src_ip = b4_ipv6
   ipv6_hdr.dst_ip = aftr_ipv6

   ipv4_hdr.src_ip = b4_ipv4
   ipv4_hdr.dst_ip = public_ipv4
   ipv4_hdr.ttl = 15
   ipv4_hdr.ihl_v_tos = htons(0x4500) -- v4
   ipv4_hdr.id = 0
   ipv4_hdr.frag_off = 0
   ipv4_hdr.protocol = 17  -- UDP

   udp_hdr.src_port = htons(conf.b4_port)
   udp_hdr.dst_port = htons(12345)
   udp_hdr.checksum = 0

   payload.magic = MAGIC
   payload.number = 0

   -- The sizes are frame sizes, including the 4-byte ethernet CRC
   -- that we don't see in Snabb.
   local sizes = {}
   for _,size in ipairs(conf.sizes) do
      assert(size >= ether_min_frame_size)
      table.insert(sizes, size - ether_crc_size - conf.frame_overhead)
   end

   local o = {
      b4_ipv6 = b4_ipv6,
      b4_ipv4 = b4_ipv4,
      b4_port = conf.b4_port,
      softwire_idx = 0,
      softwire_count = conf.count,
      single_pass = conf.single_pass,
      template_pkt = pkt,
      ipv6_hdr = ipv6_hdr,
      ipv4_hdr = ipv4_hdr,
      udp_hdr = udp_hdr,
      payload = payload,
      rx_payload_offset = rx_payload_offset,
      rate = conf.rate,
      sizes = sizes,
      bucket_content = conf.rate * 1e6,
      rx_packets = 0, rx_bytes = 0,
      tx_packet_number = 0, rx_packet_number = 0,
      lost_packets = 0
   }
   return setmetatable(o, {__index=B4Gen})
end

function B4Gen:done() return self.stopping end

function B4Gen:pull ()

   if self.stopping then return end

   local output = self.output.output
   local input = self.input.input
   local rx_packets = self.rx_packets
   local rx_bytes = self.rx_bytes
   local lost_packets = self.lost_packets
   local rx_payload_offset = self.rx_payload_offset

   -- Count and trash incoming packets.
   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if cast(ether_header_ptr_type, pkt.data).ether_type == PROTO_IPV4 then
         rx_bytes = rx_bytes + pkt.length
         rx_packets = rx_packets + 1
         local payload = cast(payload_ptr_type, pkt.data + rx_payload_offset)
         if payload.magic == MAGIC then
            if self.last_rx_packet_number and self.last_rx_packet_number > 0 then
               lost_packets = lost_packets + payload.number - self.last_rx_packet_number - 1
            end
            self.last_rx_packet_number = payload.number
         end
      end
      packet.free(pkt)
   end

   local cur_now = tonumber(app.now())
   self.period_start = self.period_start or cur_now
   local elapsed = cur_now - self.period_start
   if elapsed > 1 then
      printf('v4 rx: %.6f MPPS, %.6f Gbps, lost %.3f%%',
             rx_packets / elapsed / 1e6,
             rx_bytes * 8 / 1e9 / elapsed,
             lost_packets / (rx_packets + lost_packets) * 100)
      self.period_start = cur_now
      rx_packets, rx_bytes, lost_packets = 0, 0, 0
   end
   self.rx_packets = rx_packets
   self.rx_bytes = rx_bytes
   self.lost_packets = lost_packets

   local ipv6_hdr = self.ipv6_hdr
   local ipv4_hdr = self.ipv4_hdr
   local udp_hdr = self.udp_hdr
   local payload = self.payload

   local cur_now = tonumber(app.now())
   local last_time = self.last_time or cur_now
   self.bucket_content = self.bucket_content + self.rate * 1e6 * (cur_now - last_time)
   self.last_time = cur_now

   for _=1, math.min(engine.pull_npackets, self.bucket_content) do
      if #self.sizes > self.bucket_content then break end
      self.bucket_content = self.bucket_content - #self.sizes

      for _,size in ipairs(self.sizes) do
         local ipv4_len = size - ether_header_size
         local udp_len = ipv4_len - ipv4_header_size
         -- Expectation from callers is to make packets that are SIZE
         -- bytes big, *plus* the IPv6 header.
         ipv6_hdr.payload_length = htons(ipv4_len)
         ipv4_hdr.total_length = htons(ipv4_len)
         ipv4_hdr.checksum =  0
         ipv4_hdr.checksum = htons(ipsum(cast("char*", ipv4_hdr), ipv4_header_size, 0))
         udp_hdr.len = htons(udp_len)
         self.template_pkt.length = size + ipv6_header_size
         payload.number = self.tx_packet_number;
         self.tx_packet_number = self.tx_packet_number + 1
         transmit(output, packet.clone(self.template_pkt))
      end

      -- Next softwire.
      inc_ipv6(ipv6_hdr.src_ip)
      local next_port = ntohs(udp_hdr.src_port) + self.b4_port
      if next_port >= 2^16 then
         inc_ipv4(ipv4_hdr.src_ip)
         next_port = self.b4_port
      end
      udp_hdr.src_port = htons(next_port)

      self.softwire_idx = self.softwire_idx + 1
      if self.softwire_idx >= self.softwire_count then
         if self.single_pass then
            printf("generated %d packets for each of %d softwires",
                   #self.sizes, self.softwire_count)
            self.stopping = true
            break
         end

         -- Reset to initial softwire.
         self.softwire_idx = 0
         ipv6_hdr.src_ip = self.b4_ipv6
         ipv4_hdr.src_ip = self.b4_ipv4
         udp_hdr.src_port = htons(self.b4_port)
      end
   end
end

InetGen = {
   config = {
      sizes = {required=true},
      rate = {required=true},
      b4_ipv4 = {required=true},
      public_ipv4 = {required=true},
      b4_port = {required=true},
      count = {},
      single_pass = {},
      frame_overhead = {default=0}
   }
}

function InetGen:new(conf)
   local b4_ipv4 = ipv4:pton(conf.b4_ipv4)
   local public_ipv4 = ipv4:pton(conf.public_ipv4)

   -- Template IPv4 packet
   local pkt = packet.allocate()
   ffi.fill(pkt.data, packet.max_payload)
   local function h(ptr_type, offset, size)
      return cast(ptr_type, pkt.data + offset), offset + size
   end
   local eth_hdr,  ipv4_offset    = h(ether_header_ptr_type, 0,           ether_header_size)
   local ipv4_hdr, udp_offset     = h(ipv4_header_ptr_type,  ipv4_offset, ipv4_header_size)
   local udp_hdr,  payload_offset = h(udp_header_ptr_type,   udp_offset,  udp_header_size)
   local payload,  min_length     = h(payload_ptr_type,      payload_offset, payload_size)

   -- The offset in returned packets where we expect to find the payload.
   local rx_payload_offset = payload_offset + ipv6_header_size

   eth_hdr.ether_type = PROTO_IPV4

   ipv4_hdr.src_ip = public_ipv4
   ipv4_hdr.dst_ip = b4_ipv4
   ipv4_hdr.ttl = 15
   ipv4_hdr.ihl_v_tos = htons(0x4500) -- v4
   ipv4_hdr.id = 0
   ipv4_hdr.frag_off = 0
   ipv4_hdr.protocol = 17  -- UDP

   udp_hdr.src_port = htons(12345)
   udp_hdr.dst_port = htons(conf.b4_port)
   udp_hdr.checksum = 0

   payload.magic = MAGIC
   payload.number = 0

   -- The sizes are frame sizes, including the 4-byte ethernet CRC
   -- that we don't see in Snabb.
   local sizes = {}
   for _,size in ipairs(conf.sizes) do
      assert(size >= ether_min_frame_size)
      table.insert(sizes, size - ether_crc_size - conf.frame_overhead)
   end

   local o = {
      b4_ipv4 = b4_ipv4,
      b4_port = conf.b4_port,
      softwire_idx = 0,
      softwire_count = conf.count,
      single_pass = conf.single_pass,
      template_pkt = pkt,
      ipv4_hdr = ipv4_hdr,
      udp_hdr = udp_hdr,
      payload = payload,
      rx_payload_offset = rx_payload_offset,
      rate = conf.rate,
      sizes = sizes,
      bucket_content = conf.rate * 1e6,
      rx_packets = 0, rx_bytes = 0,
      tx_packet_number = 0, rx_packet_number = 0,
      lost_packets = 0
   }
   return setmetatable(o, {__index=InetGen})
end

function InetGen:done() return self.stopping end

function InetGen:pull ()

   if self.stopping then return end

   local output = self.output.output
   local input = self.input.input
   local rx_packets = self.rx_packets
   local rx_bytes = self.rx_bytes
   local lost_packets = self.lost_packets
   local rx_payload_offset = self.rx_payload_offset

   -- Count and trash incoming packets.
   for _=1,link.nreadable(input) do
      local pkt = receive(input)
      if cast(ether_header_ptr_type, pkt.data).ether_type == PROTO_IPV6 then
         rx_bytes = rx_bytes + pkt.length
         rx_packets = rx_packets + 1
         local payload = cast(payload_ptr_type, pkt.data + rx_payload_offset)
         if payload.magic == MAGIC then
            if self.last_rx_packet_number and self.last_rx_packet_number > 0 then
               lost_packets = lost_packets + payload.number - self.last_rx_packet_number - 1
            end
            self.last_rx_packet_number = payload.number
         end
      end
      packet.free(pkt)
   end

   local cur_now = tonumber(app.now())
   self.period_start = self.period_start or cur_now
   local elapsed = cur_now - self.period_start
   if elapsed > 1 then
      printf('v6 rx: %.6f MPPS, %.6f Gbps, lost %.3f%%',
             rx_packets / elapsed / 1e6,
             rx_bytes * 8 / 1e9 / elapsed,
             lost_packets / (rx_packets + lost_packets) * 100)
      self.period_start = cur_now
      rx_packets, rx_bytes, lost_packets = 0, 0, 0
   end
   self.rx_packets = rx_packets
   self.rx_bytes = rx_bytes
   self.lost_packets = lost_packets

   local ipv4_hdr = self.ipv4_hdr
   local udp_hdr = self.udp_hdr
   local payload = self.payload

   local cur_now = tonumber(app.now())
   local last_time = self.last_time or cur_now
   self.bucket_content = self.bucket_content + self.rate * 1e6 * (cur_now - last_time)
   self.last_time = cur_now

   for _=1, math.min(engine.pull_npackets, self.bucket_content) do
      if #self.sizes > self.bucket_content then break end
      self.bucket_content = self.bucket_content - #self.sizes

      for _,size in ipairs(self.sizes) do
         local ipv4_len = size - ether_header_size
         local udp_len = ipv4_len - ipv4_header_size
         ipv4_hdr.total_length = htons(ipv4_len)
         ipv4_hdr.checksum =  0
         ipv4_hdr.checksum = htons(ipsum(cast("char*", ipv4_hdr), ipv4_header_size, 0))
         udp_hdr.len = htons(udp_len)
         self.template_pkt.length = size
         payload.number = self.tx_packet_number;
         self.tx_packet_number = self.tx_packet_number + 1
         transmit(output, packet.clone(self.template_pkt))
      end

      -- Next softwire.
      local next_port = ntohs(udp_hdr.dst_port) + self.b4_port
      if next_port >= 2^16 then
         inc_ipv4(ipv4_hdr.dst_ip)
         next_port = self.b4_port
      end
      udp_hdr.dst_port = htons(next_port)

      self.softwire_idx = self.softwire_idx + 1
      if self.softwire_idx >= self.softwire_count then
         if self.single_pass then
            printf("generated %d packets for each of %d softwires",
                   #self.sizes, self.softwire_count)
            self.stopping = true
            break
         end

         -- Reset to initial softwire.
         self.softwire_idx = 0
         ipv4_hdr.dst_ip = self.b4_ipv4
         udp_hdr.dst_port = htons(self.b4_port)
      end
   end
end

Interleave = {}

function Interleave:new()
   return setmetatable({}, {__index=Interleave})
end

function Interleave:push ()
   local continue = true
   while continue do
      continue = false
      for _, inport in ipairs(self.input) do
         if not link.empty(inport) then
            transmit(self.output.output, receive(inport))
            continue = true
         end
      end
   end
end

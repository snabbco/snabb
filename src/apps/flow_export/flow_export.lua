-- This module implements the flow exporter app, which records
-- network traffic information and exports it in Netflow v9 format
-- (RFC 3954) or IPFIX format (RFC 3917 and others).

module(..., package.seeall)

local ffi    = require("ffi")
local ipfix  = require("apps.flow_export.ipfix")
local lib    = require("core.lib")
local link   = require("core.link")
local packet = require("core.packet")
local ctable = require("lib.ctable")
local ether  = require("lib.protocol.ethernet")
local ipv4   = require("lib.protocol.ipv4")
local ipv6   = require("lib.protocol.ipv6")
local tcp    = require("lib.protocol.tcp")
local C      = ffi.C

local htonl, htons, timeout = lib.htonl, lib.htons, lib.timeout

local ETHER_PROTO_IPV4 = 0x0800
local ETHER_PROTO_IPV6 = 0x86dd

local IP_PROTO_TCP  = 6
local IP_PROTO_UDP  = 17
local IP_PROTO_SCTP = 132

local TCP_CONTROL_BITS_OFFSET = 11

-- see https://www.iana.org/assignments/ipfix/ipfix.xhtml for
-- information on the IEs for the flow key and record
ffi.cdef[[
   struct flow_key {
      uint8_t is_ipv6;
      uint8_t src_ip[16];
      uint8_t dst_ip[16];
      uint16_t src_port;
      uint16_t dst_port;
      uint8_t protocol;
   };

   struct flow_record {
      struct flow_key key;
      /* 152, flowStartMilliseconds */
      uint64_t start_time;
      /* 153, flowEndMilliseconds */
      uint64_t end_time;
      /* 2, packetDeltaCount */
      uint64_t pkt_count;
      /* 1, octetDeltaCount */
      uint64_t octet_count;
      /* 5, ipClassOfService */
      uint8_t tos;
      /* 6, tcpControlBits */
      uint16_t tcp_control;
      /* 10, ingressInterface */
      uint32_t ingress;
      /* 14, egressInterface */
      uint32_t egress;
      /* 129, bgpPrevAdjacentAsNumber */
      uint32_t src_peer_as;
      /* 128, bgpNextAdjacentAsNumber */
      uint32_t dst_peer_as;
   };
]]

FlowExporter = {}

-- TODO: should be configurable
--       these numbers are placeholders for more realistic ones
--       (and timeouts should perhaps be more fine-grained)
local cache_size = 20000
local idle_timeout = 120
local active_timeout = 300
local export_interval = 60
local template_interval = 60

-- produce a timestamp in milliseconds
local function get_timestamp()
   return C.get_time_ns() / 1000000ULL
end

function FlowExporter:new(config)
   local params = {
      key_type = ffi.typeof("struct flow_key"),
      value_type = ffi.typeof("struct flow_record"),
      max_occupancy_rate = 0.4,
      initial_size = math.ceil(cache_size / 0.4),
   }
   local o = { flows = ctable.new(params),
               export_timer = nil,
               template_timer = nil,
               boot_time = get_timestamp(),
               exporter_mac = assert(config.exporter_mac),
               exporter_ip = assert(config.exporter_ip),
               collector_ip = assert(config.collector_ip),
               collector_port = assert(config.collector_port),
               -- TODO: use ARP to avoid needing this
               collector_mac = assert(config.collector_mac),
               observation_domain = config.observation_domain or 256,
               -- TODO: make this configurable
               mtu_to_collector = 1500 }

   return setmetatable(o, { __index = self })
end

-- allocate a single flow key that we will re-use
-- (for performance reasons)
local flow_key = ffi.new("struct flow_key")

function FlowExporter:process_packet(pkt)
   -- TODO: using the header libraries for now, but can rewrite this
   --       code if it turns out to be too slow
   local eth_header  = ether:new_from_mem(pkt.data, pkt.length)
   local eth_size    = eth_header:sizeof()
   local eth_type    = eth_header:type()
   local ip_header

   if eth_type == ETHER_PROTO_IPV4 then
      ip_header = ipv4:new_from_mem(pkt.data + eth_size, pkt.length - eth_size)
      flow_key.is_ipv6  = false
      flow_key.protocol = ip_header:protocol()
      ffi.copy(flow_key.src_ip, ip_header:src(), 4)
      ffi.copy(flow_key.dst_ip, ip_header:dst(), 4)
   elseif eth_type == ETHER_PROTO_IPV6 then
      ip_header = ipv6:new_from_mem(pkt.data + eth_size, pkt.length - eth_size)
      flow_key.is_ipv6  = true
      flow_key.protocol = ip_header:next_header()
      flow_key.src_ip   = ip_header:src()
      flow_key.dst_ip   = ip_header:dst()
   else
      -- ignore non-IP packets
      packet.free(pkt)
      return
   end

   local ip_size = ip_header:sizeof()

   -- TCP, UDP, SCTP all have the ports in the same header location
   if (flow_key.protocol == IP_PROTO_TCP
       or flow_key.protocol == IP_PROTO_UDP
       or flow_key.protocol == IP_PROTO_SCTP) then
      flow_key.src_port =
         ffi.cast("uint16_t*", pkt.data + eth_size + ip_size)[0]
      flow_key.dst_port =
         ffi.cast("uint16_t*", pkt.data + eth_size + ip_size + 2)[0]
   end

   local lookup_result = self.flows:lookup_ptr(flow_key)
   local flow_record

   if lookup_result == nil then
      flow_record             = ffi.new("struct flow_record")
      flow_record.key         = flow_key
      flow_record.start_time  = get_timestamp()
      flow_record.end_time    = flow_record.start_time
      flow_record.pkt_count   = 1ULL
      flow_record.octet_count = pkt.length

      if eth_type == ETHER_PROTO_IPV4 then
         -- simpler than combining ip_header:dscp() & ip_header:ecn()
         flow_record.tos   = ffi.cast("uint8_t*", pkt.data + eth_size + 1)[0]
      elseif eth_type == ETHER_PROTO_IPV6 then
         flow_record.tos   = ip_header:traffic_class()
      end

      if flow_key.protocol == IP_PROTO_TCP then
         local ptr = pkt.data + eth_size + ip_size + TCP_CONTROL_BITS_OFFSET
         flow_record.tcp_control = ffi.cast("uint16_t*", ptr)[0]
      end

      self.flows:add(flow_key, flow_record)
   else
      flow_record = lookup_result.value

      -- otherwise just update the counters and timestamps
      flow_record.end_time    = get_timestamp()
      flow_record.pkt_count   = flow_record.pkt_count + 1ULL
      flow_record.octet_count = flow_record.octet_count + pkt.length
   end
end

-- Walk through flow cache to see if flow records need to be expired.
-- Collect expired records and export them to the collector.
function FlowExporter:expire_records()
   local now = get_timestamp()
   local keys_to_remove = {}
   local timeout_records = {}
   local to_export = {}

   -- TODO: Walking the table here is done in serial with flow record
   --       updates, but in the future this should be done concurrently
   --       in a separate process. i.e., locking required here
   for entry in self.flows:iterate() do
      local record = entry.value

      if now - record.end_time > idle_timeout then
         table.insert(keys_to_remove, entry.key)
         table.insert(to_export, record)
      elseif now - record.end_time > active_timeout then
         table.insert(timeout_records, record)
         table.insert(to_export, record)
      end
   end

   ipfix.export_records(self, to_export)

   -- TODO: Due to the key optimization above this doesn't work, fix
   --       it by changing the flow key representation
   --for _, key in ipairs(keys_to_remove) do
   --   self.flows:remove(key)
   --end

   for _, record in ipairs(timeout_records) do
      -- TODO: what should timers reset to?
      record.start_time = now
      record.end_time = now
      record.pkt_count = 0
      record.octet_count = 0
   end
end

function FlowExporter:push()
   local input  = assert(self.input.input)

   while not link.empty(input) do
      local pkt = link.receive(input)
      self:process_packet(pkt)
   end

   if self.template_timer then
      if self.template_timer() then
         ipfix.send_template_record(self)
         self.template_timer = timeout(template_interval)
      end
   else
      ipfix.send_template_record(self)
      self.template_timer = timeout(template_interval)
   end

   if self.export_timer then
      if self.export_timer() then
         self:expire_records()
         self.export_timer = timeout(export_interval)
      end
   else
      self.export_timer = timeout(export_interval)
   end
end

function selftest()
   local datagram = require("lib.protocol.datagram")

   local nf = FlowExporter:new()
   local eth = ether:new({ src = ether:pton("00:11:22:33:44:55"),
                           dst = ether:pton("55:44:33:22:11:00"),
                           type = ETHER_PROTO_IPV4 })
   local ip = ipv4:new({ src = ipv4:pton("192.168.1.1"),
                         dst = ipv4:pton("192.168.1.25"),
                         protocol = IP_PROTO_TCP,
                         ttl = 64 })
   local tcp = tcp:new({ src_port = 9999,
                         dst_port = 80 })
   local dg = datagram:new()

   dg:push(tcp)
   dg:push(ip)
   dg:push(eth)

   local pkt = dg:packet()

   nf:process_packet(pkt)

   local key = ffi.new("struct flow_key")
   key.is_ipv6  = false
   ffi.copy(key.src_ip, ipv4:pton("192.168.1.1"), 4)
   ffi.copy(key.dst_ip, ipv4:pton("192.168.1.25"), 4)
   key.protocol = IP_PROTO_TCP
   key.src_port = htons(9999)
   key.dst_port = htons(80)

   local result = nf.flows:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.pkt_count == 1)

   nf:process_packet(pkt)
   assert(result.value.pkt_count == 2)
end

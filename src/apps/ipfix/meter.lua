-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local ffi    = require("ffi")
local cache  = require("apps.ipfix.cache")
local util   = require("apps.ipfix.util")
local consts = require("apps.lwaftr.constants")
local lib    = require("core.lib")
local link   = require("core.link")
local packet = require("core.packet")
local ctable = require("lib.ctable")
local C      = ffi.C

local htonl, htons, ntohl, ntohs  = lib.htonl, lib.htons, lib.ntohl, lib.ntohs
local get_timestamp = util.get_timestamp

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local IP_PROTO_TCP  = 6
local IP_PROTO_UDP  = 17
local IP_PROTO_SCTP = 132

local TCP_CONTROL_BITS_OFFSET = 11

-- These constants are taken from the lwaftr constants module, which
-- is maybe a bad dependency but sharing code is good
-- TODO: move constants somewhere else? lib?
local ethertype_ipv4         = consts.ethertype_ipv4
local ethertype_ipv6         = consts.ethertype_ipv6
local n_ethertype_ipv4       = consts.n_ethertype_ipv4
local n_ethertype_ipv6       = consts.n_ethertype_ipv6
local ethernet_header_size   = consts.ethernet_header_size
local ipv6_fixed_header_size = consts.ipv6_fixed_header_size
local o_ethernet_dst_addr    = consts.o_ethernet_dst_addr
local o_ethernet_src_addr    = consts.o_ethernet_src_addr
local o_ethernet_ethertype   = consts.o_ethernet_ethertype
local o_ipv4_total_length    = consts.o_ipv4_total_length
local o_ipv4_ver_and_ihl     = consts.o_ipv4_ver_and_ihl
local o_ipv4_proto           = consts.o_ipv4_proto
local o_ipv4_src_addr        = consts.o_ipv4_src_addr
local o_ipv4_dst_addr        = consts.o_ipv4_dst_addr
local o_ipv6_payload_len     = consts.o_ipv6_payload_len
local o_ipv6_next_header     = consts.o_ipv6_next_header
local o_ipv6_src_addr        = consts.o_ipv6_src_addr
local o_ipv6_dst_addr        = consts.o_ipv6_dst_addr

-- TODO: should be configurable
--       these numbers are placeholders for more realistic ones
--       (and timeouts should perhaps be more fine-grained)
local export_interval = 60

FlowMeter = {}

function FlowMeter:new(config)
   local o = { flows = assert(config.cache),
               export_timer = nil,
               idle_timeout = config.idle_timeout or 300,
               active_timeout = config.active_timeout or 120,
               -- used for debugging mainly
               boot_time = get_timestamp() }

   -- convert from secs to ms (internal timestamp granularity is ms)
   o.idle_timeout   = o.idle_timeout * 1000
   o.active_timeout = o.active_timeout * 1000

   return setmetatable(o, { __index = self })
end

local function get_ethernet_n_ethertype(ptr)
   return ffi.cast("uint16_t*", ptr + o_ethernet_ethertype)[0]
end

local function get_ipv4_ihl(ptr)
   return bit.band((ptr + o_ipv4_ver_and_ihl)[0], 0x0f)
end

local function get_ipv4_protocol(ptr)
   return (ptr + o_ipv4_proto)[0]
end

local function get_ipv6_next_header(ptr)
   return (ptr + o_ipv6_next_header)[0]
end

local function get_ipv4_src_addr_ptr(ptr)
   return ptr + o_ipv4_src_addr
end

local function get_ipv4_dst_addr_ptr(ptr)
   return ptr + o_ipv4_dst_addr
end

local function get_ipv6_src_addr_ptr(ptr)
   return ptr + o_ipv6_src_addr
end

local function get_ipv6_dst_addr_ptr(ptr)
   return ptr + o_ipv6_dst_addr
end

local function get_ipv6_traffic_class(ptr)
   local high = bit.band(ptr[0], 0x0f)
   local low  = bit.rshift(bit.band(ptr[1], 0xf0), 4)
   return bit.band(high, low)
end

function FlowMeter:process_flow(flows, flow_key, flow_record, l4_header)
   -- TCP, UDP, SCTP all have the ports in the same header location
   if (flow_key.protocol == IP_PROTO_TCP
       or flow_key.protocol == IP_PROTO_UDP
       or flow_key.protocol == IP_PROTO_SCTP) then
      -- FIXME: Use host endianness.
      flow_key.src_port = ffi.cast("uint16_t*", l4_header)[0]
      flow_key.dst_port = ffi.cast("uint16_t*", l4_header)[1]
   else
      flow_key.src_port = 0
      flow_key.dst_port = 0
   end

   local lookup_result = flows.table:lookup_ptr(flow_key)

   if lookup_result == nil then
      flow_record.start_time  = flow_record.end_time
      flow_record.pkt_count   = 1ULL
      if flow_key.protocol == IP_PROTO_TCP then
         local ptr = l4_header + TCP_CONTROL_BITS_OFFSET
         flow_record.tcp_control = ffi.cast("uint16_t*", ptr)[0]
      else
         flow_record.tcp_control = 0
      end

      flows.table:add(flow_key, flow_record)
   else
      local timestamp, bytes = flow_record.end_time, flow_record.octet_count
      local flow_record = lookup_result.value

      -- otherwise just update the counters and timestamps
      flow_record.end_time    = timestamp
      flow_record.pkt_count   = flow_record.pkt_count + 1ULL
      flow_record.octet_count = flow_record.octet_count + bytes
   end
end

function FlowMeter:process_ipv6_packet(pkt, timestamp)
   local l2_header = pkt.data
   -- We could warn here.
   if get_ethernet_n_ethertype(l2_header) ~= n_ethertype_ipv6 then return end

   local flows = self.flows.v6
   local flow_key = flows.preallocated_key
   local flow_record = flows.preallocated_value
   local l3_header = l2_header + ethernet_header_size
   flow_key.protocol = get_ipv6_next_header(l3_header)
   ffi.copy(flow_key.src_ip, get_ipv6_src_addr_ptr(l3_header), 16)
   ffi.copy(flow_key.dst_ip, get_ipv6_dst_addr_ptr(l3_header), 16)

   flow_record.end_time = timestamp
   -- Measure bytes starting with the IP header.
   flow_record.octet_count = pkt.length - ethernet_header_size
   flow_record.tos = get_ipv6_traffic_class(l3_header)

   -- TODO: handle chained headers
   local l4_header = l3_header + ipv6_fixed_header_size

   FlowMeter:process_flow(flows, flow_key, flow_record, l4_header)
end

function FlowMeter:process_ipv4_packet(pkt, timestamp)
   local l2_header = pkt.data
   -- We could warn here.
   if get_ethernet_n_ethertype(l2_header) ~= n_ethertype_ipv4 then return end

   local flows = self.flows.v4
   local flow_key = flows.preallocated_key
   local flow_record = flows.preallocated_value
   local l3_header = l2_header + ethernet_header_size
   flow_key.protocol = get_ipv4_protocol(l3_header)
   ffi.copy(flow_key.src_ip, get_ipv4_src_addr_ptr(l3_header), 4)
   ffi.copy(flow_key.dst_ip, get_ipv4_dst_addr_ptr(l3_header), 4)

   flow_record.end_time = timestamp
   -- Measure bytes starting with the IP header.
   flow_record.octet_count = pkt.length - ethernet_header_size
   -- Simpler than combining ip_header:dscp() and ip_header:ecn().
   flow_record.tos = l3_header[1]

   local ihl = get_ipv4_ihl(l3_header)
   local l4_header = l3_header + ihl * 4

   FlowMeter:process_flow(flows, flow_key, flow_record, l4_header)
end

-- print debugging messages for flow expiration
function FlowMeter:debug_expire(entry, timestamp, msg)
   local ipv4 = require("lib.protocol.ipv4")
   local ipv6 = require("lib.protocol.ipv4")

   if debug then
      local key = entry.key
      local src_ip, dst_ip

      if key.is_ipv6 == 1 then
         local ptr = ffi.cast("uint8_t*", key) + ffi.offsetof(key, "src_ip_1")
         src_ip = ipv6:ntop(ptr)
         local ptr = ffi.cast("uint8_t*", key) + ffi.offsetof(key, "dst_ip_1")
         dst_ip = ipv6:ntop(ptr)
      else
         local ptr = ffi.cast("uint8_t*", key) + ffi.offsetof(key, "src_ip_1")
         src_ip = ipv4:ntop(ptr)
         local ptr = ffi.cast("uint8_t*", key) + ffi.offsetof(key, "dst_ip_1")
         dst_ip = ipv4:ntop(ptr)
      end

      local time_delta
      if msg == "idle" then
         time_delta = tonumber(entry.value.end_time - self.boot_time) / 1000
      else
         time_delta = tonumber(entry.value.start_time - self.boot_time) / 1000
      end

      util.fe_debug("exp [%s, %ds] %s (%d) -> %s (%d) P:%d",
                    msg,
                    time_delta,
                    src_ip,
                    htons(key.src_port),
                    dst_ip,
                    htons(key.dst_port),
                    key.protocol)
   end
end

-- Walk through flow cache to see if flow records need to be expired.
-- Collect expired records and export them to the collector.
function FlowMeter:expire_records()
   for _,proto in ipairs({'v4', 'v6'}) do
      local timestamp = get_timestamp()
      local keys_to_remove = {}
      local timeout_records = {}
      local to_export = {}
      local flows = self.flows[proto]
      for entry in flows:iterate() do
         local record = entry.value

         if timestamp - record.end_time > self.idle_timeout then
            self:debug_expire(entry, timestamp, "idle")
            table.insert(keys_to_remove, entry.key)
            flows:expire_record(entry.key, record, false)
         elseif timestamp - record.start_time > self.active_timeout then
            self:debug_expire(entry, timestamp, "active")
            table.insert(timeout_records, record)
            flows:expire_record(entry.key, record, true)
         end
      end

      -- remove idle timed out flows
      for _, key in ipairs(keys_to_remove) do
         flows:remove(key)
      end

      for _, record in ipairs(timeout_records) do
         -- TODO: what should timers reset to?
         record.start_time = timestamp
         record.end_time = timestamp
         record.pkt_count = 0
         record.octet_count = 0
      end
   end
end

function FlowMeter:push()
   local v4, v6 = self.input.v4, self.input.v6
   local timestamp = get_timestamp()

   if v4 then
      for i=1,link.nreadable(v4) do
        local pkt = link.receive(v4)
        self:process_ipv4_packet(pkt, timestamp)
        packet.free(pkt)
     end
   end

   if v6 then
      for i=1,link.nreadable(v6) do
         local pkt = link.receive(v6)
         self:process_ipv6_packet(pkt, timestamp)
         packet.free(pkt)
      end
   end

   self:expire_records()
end

function selftest()
   local ether    = require("lib.protocol.ethernet")
   local ipv4     = require("lib.protocol.ipv4")
   local ipv6     = require("lib.protocol.ipv6")
   local udp      = require("lib.protocol.udp")
   local datagram = require("lib.protocol.datagram")

   local flows = cache.FlowCache:new({})
   local nf    = FlowMeter:new({ cache = flows })

   -- test helper that processes a packet with some given fields
   local function test_packet(is_ipv6, src_ip, dst_ip, src_port, dst_port)
      local proto
      if is_ipv6 then
         proto = ethertype_ipv6
      else
         proto = ethertype_ipv4
      end

      local eth = ether:new({ src = ether:pton("00:11:22:33:44:55"),
                              dst = ether:pton("55:44:33:22:11:00"),
                              type = proto })
      local ip

      if is_ipv6 then
         ip = ipv6:new({ src = ipv6:pton(src_ip),
                         dst = ipv6:pton(dst_ip),
                         next_header = IP_PROTO_UDP,
                         ttl = 64 })
      else
         ip = ipv4:new({ src = ipv4:pton(src_ip),
                         dst = ipv4:pton(dst_ip),
                         protocol = IP_PROTO_UDP,
                         ttl = 64 })
      end
      local udp = udp:new({ src_port = src_port,
                            dst_port = dst_port })
      local dg = datagram:new()

      dg:push(udp)
      dg:push(ip)
      dg:push(eth)

      local pkt = dg:packet()
      if is_ipv6 then
         nf:process_ipv6_packet(pkt, 0) -- dummy timestamp
      else
         nf:process_ipv4_packet(pkt, 0) -- dummy timestamp
      end
      packet.free(pkt)
   end

   -- populate with some known flows
   test_packet(false, "192.168.1.1", "192.168.1.25", 9999, 80)
   test_packet(false, "192.168.1.25", "192.168.1.1", 3653, 23552)
   test_packet(false, "192.168.1.25", "8.8.8.8", 58342, 53)
   test_packet(false, "8.8.8.8", "192.168.1.25", 53, 58342)
   test_packet(true, "2001:4860:4860::8888", "2001:db8::ff00:42:8329", 53, 57777)
   assert(flows.v4.table.occupancy == 4,
          string.format("wrong number of v4 flows: %d", flows.v4.table.occupancy))
   assert(flows.v6.table.occupancy == 1,
          string.format("wrong number of v6 flows: %d", flows.v6.table.occupancy))

   -- do some packets with random data to test that it doesn't interfere
   for i=1, 100 do
      test_packet(false,
                  string.format("192.168.1.%d", math.random(2, 254)),
                  "192.168.1.25",
                  math.random(10000, 65535),
                  math.random(1, 79))
   end

   local key = flows.v4.preallocated_key
   key.src_ip = ipv4:pton("192.168.1.1")
   key.dst_ip = ipv4:pton("192.168.1.25")
   key.protocol = IP_PROTO_UDP
   key.src_port = htons(9999)
   key.dst_port = htons(80)

   local result = flows.v4.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.pkt_count == 1)

   -- make sure the count is incremented on the same flow
   test_packet(false, "192.168.1.1", "192.168.1.25", 9999, 80)
   assert(result.value.pkt_count == 2,
          string.format("wrong count: %d", tonumber(result.value.pkt_count)))

   -- check the IPv6 key too
   local key = flows.v6.preallocated_key
   key.src_ip = ipv6:pton("2001:4860:4860::8888")
   key.dst_ip = ipv6:pton("2001:db8::ff00:42:8329")
   key.protocol = IP_PROTO_UDP
   key.src_port = htons(53)
   key.dst_port = htons(57777)

   local result = flows.v6.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.pkt_count == 1)

   -- sanity check
   flows.v4.table:selfcheck()
   flows.v6.table:selfcheck()

   print("selftest ok")
end

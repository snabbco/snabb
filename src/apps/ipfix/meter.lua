-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local ffi    = require("ffi")
local util   = require("apps.ipfix.util")
local lib    = require("core.lib")
local link   = require("core.link")
local packet = require("core.packet")
local ctable = require("lib.ctable")
local ether  = require("lib.protocol.ethernet")
local ipv4   = require("lib.protocol.ipv4")
local ipv6   = require("lib.protocol.ipv6")
local tcp    = require("lib.protocol.tcp")
local C      = ffi.C

local htonl, htons  = lib.htonl, lib.htons
local get_timestamp = util.get_timestamp

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local ETHER_PROTO_IPV4 = 0x0800
local ETHER_PROTO_IPV6 = 0x86dd

local IP_PROTO_TCP  = 6
local IP_PROTO_UDP  = 17
local IP_PROTO_SCTP = 132

local TCP_CONTROL_BITS_OFFSET = 11

FlowMeter = {}

function FlowMeter:new(config)
   local o = { flows = assert(config.cache) }

   return setmetatable(o, { __index = self })
end

function FlowMeter:process_packet(pkt)
   -- TODO: using the header libraries for now, but can rewrite this
   --       code if it turns out to be too slow
   local flow_key   = ffi.new("struct flow_key")
   local eth_header = ether:new_from_mem(pkt.data, pkt.length)
   local eth_size   = eth_header:sizeof()
   local eth_type   = eth_header:type()
   local ip_header

   if eth_type == ETHER_PROTO_IPV4 then
      ip_header = ipv4:new_from_mem(pkt.data + eth_size, pkt.length - eth_size)
      flow_key.is_ipv6  = false
      flow_key.protocol = ip_header:protocol()

      local ptr = ffi.cast("uint8_t*", flow_key) + ffi.offsetof(flow_key, "src_ipv4")
      ffi.copy(ptr, ip_header:src(), 4)
      ffi.copy(ptr + 4, ip_header:dst(), 4)
   elseif eth_type == ETHER_PROTO_IPV6 then
      ip_header = ipv6:new_from_mem(pkt.data + eth_size, pkt.length - eth_size)
      flow_key.is_ipv6  = true
      flow_key.protocol = ip_header:next_header()

      local ptr = ffi.cast("uint8_t*", flow_key) + ffi.offsetof(flow_key, "src_ipv6_1")
      ffi.copy(ptr, ip_header:src(), 16)
      ffi.copy(ptr + 16, ip_header:dst(), 16)
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

   local lookup_result = self.flows:lookup(flow_key)
   local flow_record

   if lookup_result == nil then
      flow_record             = ffi.new("struct flow_record")
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

   packet.free(pkt)
end

function FlowMeter:push()
   local input = assert(self.input.input)

   while not link.empty(input) do
      local pkt = link.receive(input)
      self:process_packet(pkt)
   end
end

function selftest()
   local datagram = require("lib.protocol.datagram")
   local cache    = require("apps.ipfix.cache")

   local flows = cache.FlowCache:new({})
   local nf    = FlowMeter:new({ cache = flows })

   -- test helper that processes a packet with some given fields
   local function test_packet(is_ipv6, src_ip, dst_ip, src_port, dst_port)
      local proto
      if is_ipv6 then
         proto = ETHER_PROTO_IPV6
      else
         proto = ETHER_PROTO_IPV4
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
      local udp = tcp:new({ src_port = src_port,
                            dst_port = dst_port })
      local dg = datagram:new()

      dg:push(udp)
      dg:push(ip)
      dg:push(eth)

      local pkt = dg:packet()
      nf:process_packet(pkt)
   end

   -- populate with some known flows
   test_packet(false, "192.168.1.1", "192.168.1.25", 9999, 80)
   test_packet(false, "192.168.1.25", "192.168.1.1", 3653, 23552)
   test_packet(false, "192.168.1.25", "8.8.8.8", 58342, 53)
   test_packet(false, "8.8.8.8", "192.168.1.25", 53, 58342)
   test_packet(true, "2001:4860:4860::8888", "2001:db8::ff00:42:8329", 53, 57777)
   assert(flows.table.occupancy == 5, "wrong number of flows")

   -- do some packets with random data to test that it doesn't interfere
   for i=1, 100 do
      test_packet(false,
                  string.format("192.168.1.%d", math.random(2, 254)),
                  "192.168.1.25",
                  math.random(10000, 65535),
                  math.random(1, 79))
   end

   local key = ffi.new("struct flow_key")
   key.is_ipv6 = false
   local ptr = ffi.cast("uint8_t*", key) + ffi.offsetof(key, "src_ipv4")
   ffi.copy(ptr, ipv4:pton("192.168.1.1"), 4)
   ffi.copy(ptr + 4, ipv4:pton("192.168.1.25"), 4)
   key.protocol = IP_PROTO_UDP
   key.src_port = htons(9999)
   key.dst_port = htons(80)

   local result = flows:lookup(key)
   assert(result, "key not found")
   assert(result.value.pkt_count == 1)

   -- make sure the count is incremented on the same flow
   test_packet(false, "192.168.1.1", "192.168.1.25", 9999, 80)
   assert(result.value.pkt_count == 2)

   -- check the IPv6 key too
   key = ffi.new("struct flow_key")
   key.is_ipv6 = true
   local ptr = ffi.cast("uint8_t*", key) + ffi.offsetof(key, "src_ipv6_1")
   ffi.copy(ptr, ipv6:pton("2001:4860:4860::8888"), 16)
   ffi.copy(ptr + 16, ipv6:pton("2001:db8::ff00:42:8329"), 16)
   key.protocol = IP_PROTO_UDP
   key.src_port = htons(53)
   key.dst_port = htons(57777)

   local result = flows:lookup(key)
   assert(result, "key not found")
   assert(result.value.pkt_count == 1)

   -- sanity check
   flows.table:selfcheck()

   print("selftest ok")
end

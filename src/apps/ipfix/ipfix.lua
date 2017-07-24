-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local pf     = require("pf")
local util   = require("apps.ipfix.util")
local template = require("apps.ipfix.template")
local lib    = require("core.lib")
local link   = require("core.link")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ether  = require("lib.protocol.ethernet")
local ipv4   = require("lib.protocol.ipv4")
local ipv6   = require("lib.protocol.ipv6")
local udp    = require("lib.protocol.udp")
local ctable = require("lib.ctable")
local C      = ffi.C

local ntohs  = lib.ntohs
local htonl, htons = lib.htonl, lib.htons
local function htonq(v) return bit.bswap(v + 0ULL) end

local get_timestamp = util.get_timestamp

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local IP_PROTO_UDP  = 17

-- TODO: should be configurable
--       these numbers are placeholders for more realistic ones
--       (and timeouts should perhaps be more fine-grained)
local export_interval = 60

-- Types.

local netflow_v9_packet_header_t = ffi.typeof([[
   struct {
      /* Network byte order.  */
      uint16_t version; /* 09 */
      uint16_t record_count;
      uint32_t uptime; /* seconds */
      uint32_t timestamp;
      uint32_t sequence_number;
      uint32_t observation_domain;
   } __attribute__((packed))
]])
local ipfix_packet_header_t = ffi.typeof([[
   struct {
      /* Network byte order.  */
      uint16_t version; /* 10 */
      uint16_t byte_length;
      uint32_t timestamp; /* seconds */
      uint32_t sequence_number;
      uint32_t observation_domain;
   } __attribute__((packed))
]])
-- RFC 7011 §3.3.2
local set_header_t = ffi.typeof([[
   struct {
      /* Network byte order.  */
      uint16_t id;
      uint16_t length;
   } __attribute__((packed))
]])
-- RFC 7011 §3.4.1.
local template_header_t = ffi.typeof([[
   struct {
      /* Network byte order.  */
      $ set_header;
      uint16_t template_id;
      uint16_t field_count;
   } __attribute__((packed))
]], set_header_t)

local function ptr_to(ctype) return ffi.typeof('$*', ctype) end

local set_header_ptr_t = ptr_to(set_header_t)
local template_header_ptr_t = ptr_to(template_header_t)

local V9_TEMPLATE_ID  = 0
local V10_TEMPLATE_ID = 2

-- RFC5153 recommends a 10-minute template refresh configurable from
-- 1 minute to 1 day (https://tools.ietf.org/html/rfc5153#section-6.2)
local template_interval = 600

-- Pad length to multiple of 4.
local max_padding = 3
local function padded_length(len)
   return bit.band(len + max_padding, bit.bnot(max_padding))
end

-- Sadly, for NetFlow v9, the header needs to know the number of
-- records in a message.  So before flushing out a message, an
-- FlowSet will append the record count, and then the exporter
-- needs to slurp this data off before adding the NetFlow/IPFIX
-- header.
local uint16_ptr_t = ffi.typeof('uint16_t*')
local function add_record_count(pkt, count)
   pkt.length = pkt.length + 2
   ffi.cast(uint16_ptr_t, pkt.data + pkt.length)[-1] = count
end
local function remove_record_count(pkt, count)
   local count = ffi.cast(uint16_ptr_t, pkt.data + pkt.length)[-1]
   pkt.length = pkt.length - 2
   return count
end

FlowSet = {}

function FlowSet:new (template, mtu, version, cache_size, idle_timeout, active_timeout)
   local o = {template=template, idle_timeout=idle_timeout, active_timeout=active_timeout}
   local template_ids = {[9]=V9_TEMPLATE_ID, [10]=V10_TEMPLATE_ID}
   o.template_id = assert(template_ids[version], 'bad version: '..version)

   -- Accumulate outgoing records in a packet.  Although it would be
   -- possible to be more efficient, packing all outgoing records into
   -- a central record accumulator for all types of data and template
   -- records, the old NetFlow v9 standard doesn't support mixing
   -- different types of records in the same export packet.
   o.record_buffer = packet.allocate()
   o.record_count = 0
   -- Max number of records + padding that fit in packet, with set header.
   local avail = padded_length(mtu - ffi.sizeof(set_header_t) - max_padding)
   o.max_record_count = math.floor(avail / o.template.data_len)

   -- TODO: Compute the default cache value based on expected flow
   -- amounts?
   o.cache_size = cache_size or 20000
   -- how much of the cache to traverse when iterating
   o.stride = math.ceil(o.cache_size / 1000)

   local params = {
      key_type = template.key_t,
      value_type = template.value_t,
      max_occupancy_rate = 0.4,
      initial_size = math.ceil(o.cache_size / 0.4),
   }

   o.match = o.template.match
   o.incoming = link.new_anonymous()
   o.table = ctable.new(params)
   o.scratch_entry = o.table.entry_type()

   return setmetatable(o, { __index = self })
end

function FlowSet:record_flows(timestamp)
   local entry = self.scratch_entry
   for i=1,link.nreadable(self.incoming) do
      local pkt = link.receive(self.incoming)
      self.template.extract(pkt, timestamp, entry)
      packet.free(pkt)
      local lookup_result = self.table:lookup_ptr(entry.key)
      if lookup_result == nil then
         self.table:add(entry.key, entry.value)
      else
         self.template.accumulate(lookup_result, entry)
      end
   end
end

function FlowSet:iterate()
   -- use the underlying ctable's iterator, but restrict the max stride
   -- for each use of the iterator
   local next_entry = self.next_entry or self.table:iterate()
   local last_entry = self.last_entry or self.table.entries - 1
   local max_entry  = last_entry + self.stride
   local table_max  =
      self.table.entries + self.table.size + self.table.max_displacement

   if table_max < max_entry then
      max_entry = table_max
      self.last_entry = nil
   else
      self.last_entry = max_entry
   end

   return next_entry, max_entry, last_entry
end

function FlowSet:remove(key)
   self.table:remove(key)
end

function FlowSet:append_template_record(pkt)
   -- Write the header and then the template record contents for each
   -- template.
   local header = ffi.cast(template_header_ptr_t, pkt.data + pkt.length)
   local header_size = ffi.sizeof(template_header_t)
   pkt.length = pkt.length + header_size
   header.set_header.id = htons(self.template_id)
   header.set_header.length = htons(header_size + self.template.buffer_len)
   header.template_id = htons(self.template.id)
   header.field_count = htons(self.template.field_count)
   return packet.append(pkt, self.template.buffer, self.template.buffer_len)
end

-- Given a flow exporter & an array of ctable entries, construct flow
-- record packet(s) and transmit them
function FlowSet:add_data_record(record, out)
   local pkt = self.record_buffer
   local record_len = self.template.data_len
   ptr = pkt.data + pkt.length
   ffi.copy(ptr, record, record_len)
   self.template.swap_fn(ffi.cast(self.template.record_ptr_t, ptr))
   pkt.length = pkt.length + record_len

   self.record_count = self.record_count + 1
   if self.record_count == self.max_record_count then
      self:flush_data_records(out)
   end
end

function FlowSet:flush_data_records(out)
   if self.record_count == 0 then return end

   -- Pop off the now-full record buffer and replace it with a fresh one.
   local pkt, record_count = self.record_buffer, self.record_count
   self.record_buffer, self.record_count = packet.allocate(), 0

   -- Pad payload to 4-byte alignment.
   ffi.fill(pkt.data + pkt.length, padded_length(pkt.length) - pkt.length, 0)
   pkt.length = padded_length(pkt.length)

   -- Prepend set header.
   pkt = packet.shiftright(pkt, ffi.sizeof(set_header_t))
   local set_header = ffi.cast(set_header_ptr_t, pkt.data)
   set_header.id = htons(self.template.id)
   set_header.length = htons(pkt.length)

   -- Add record count and push.
   add_record_count(pkt, record_count)
   link.transmit(out, pkt)
end

-- print debugging messages for flow expiration
function FlowSet:debug_expire(entry, timestamp, msg)
   if debug then
      local key = entry.key
      local src_ip, dst_ip

      if key.is_ipv6 == 1 then
         src_ip = ipv6:ntop(key.sourceIPv6Address)
         dst_ip = ipv6:ntop(key.destinationIPv6Address)
      else
         src_ip = ipv4:ntop(key.sourceIPv4Address)
         dst_ip = ipv4:ntop(key.destinationIPv4Address)
      end

      local time_delta
      if msg == "idle" then
         time_delta = tonumber(entry.value.flowEndMilliseconds - self.boot_time) / 1000
      else
         time_delta = tonumber(entry.value.flowStartMilliseconds - self.boot_time) / 1000
      end

      util.fe_debug("exp [%s, %ds] %s (%d) -> %s (%d) P:%d",
                    msg,
                    time_delta,
                    src_ip,
                    key.sourceTransportPort,
                    dst_ip,
                    key.destinationTransportPort,
                    key.protocolIdentifier)
   end
end

-- Walk through flow set to see if flow records need to be expired.
-- Collect expired records and export them to the collector.
function FlowSet:expire_records(out)
   local timestamp = get_timestamp()
   -- FIXME: remove these table allocations
   local keys_to_remove = {}
   for entry in self:iterate() do
      if timestamp - entry.value.flowEndMilliseconds > self.idle_timeout then
         self:debug_expire(entry, timestamp, "idle")
         table.insert(keys_to_remove, entry.key)
         -- Relying on key and value being contiguous.
         self:add_data_record(entry.key, out)
      elseif timestamp - entry.value.flowStartMilliseconds > self.active_timeout then
         self:debug_expire(entry, timestamp, "active")
         -- TODO: what should timers reset to?
         entry.value.flowStartMilliseconds = timestamp
         entry.value.flowEndMilliseconds = timestamp
         entry.value.packetDeltaCount = 0
         entry.value.octetDeltaCount = 0
         self:add_data_record(entry.key, out)
      end
   end

   self:flush_data_records(out)

   -- FIXME: Remove flows as we go.
   for _, key in ipairs(keys_to_remove) do
      self.table:remove(key)
   end
end

IPFIX = {}

function IPFIX:new(config)
   local o = { export_timer = nil,
               idle_timeout = config.idle_timeout or 300,
               active_timeout = config.active_timeout or 120,
               -- sequence number to use for flow packets
               sequence_number = 1,
               boot_time = util.get_timestamp(),
               next_template_refresh = 0,
               -- version of IPFIX/Netflow (9 or 10)
               version = assert(config.ipfix_version),
               -- RFC7011 specifies that if the PMTU is unknown, a maximum
               -- of 512 octets should be used for UDP transmission
               -- (https://tools.ietf.org/html/rfc7011#section-10.3.3)
               mtu = config.mtu or 512,
               observation_domain = config.observation_domain or 256,
               exporter_mac = assert(config.exporter_mac),
               exporter_ip = assert(config.exporter_ip),
               exporter_port = math.random(49152, 65535),
               -- TODO: use ARP to avoid needing this
               collector_mac = assert(config.collector_mac),
               collector_ip = assert(config.collector_ip),
               collector_port = assert(config.collector_port) }

   -- Convert from secs to ms (internal timestamp granularity is ms).
   o.idle_timeout   = o.idle_timeout * 1000
   o.active_timeout = o.active_timeout * 1000

   if o.version == 9 then
      o.header_t = netflow_v9_packet_header_t
   elseif o.version == 10 then
      o.header_t = ipfix_packet_header_t
   else
      error('unsupported ipfix version: '..o.version)
   end
   o.header_ptr_t = ptr_to(o.header_t)
   o.header_size = ffi.sizeof(o.header_t)

   -- FIXME: Assuming we export to IPv4 address.
   local l3_header_len = 20
   local l4_header_len = 8
   local ipfix_header_len = o.header_size
   local total_header_len = l4_header_len + l3_header_len + ipfix_header_len
   local payload_mtu = o.mtu - total_header_len
   o.ipv4_flows = FlowSet:new(template.v4, payload_mtu, o.version, config.cache_size, o.idle_timeout, o.active_timeout)
   o.ipv6_flows = FlowSet:new(template.v6, payload_mtu, o.version, config.cache_size, o.idle_timeout, o.active_timeout)

   self.outgoing_messages = link.new_anonymous()

   return setmetatable(o, { __index = self })
end

function IPFIX:send_template_records(out)
   local pkt = packet.allocate()
   pkt = self.ipv4_flows:append_template_record(pkt)
   pkt = self.ipv6_flows:append_template_record(pkt)
   add_record_count(pkt, 2)
   link.transmit(out, pkt)
end

function IPFIX:add_ipfix_header(pkt, count)
   pkt = packet.shiftright(pkt, self.header_size)
   local header = ffi.cast(self.header_ptr_t, pkt.data)

   header.version = htons(self.version)
   if self.version == 9 then
      header.count = htons(count)
      header.uptime = htonl(tonumber(get_timestamp() - self.boot_time))
   elseif self.version == 10 then
      header.byte_length = htons(pkt.length)
   end
   header.timestamp = htonl(math.floor(C.get_unix_time()))
   header.sequence_number = htonl(self.sequence_number)
   header.observation_domain = htonl(self.observation_domain)

   self.sequence_number = self.sequence_number + 1

   return pkt
end

function IPFIX:add_transport_headers (pkt)
   -- TODO: support IPv6, also obtain the MAC of the dst via ARP
   --       and use the correct src MAC (this is ok for use on the
   --       loopback device for now).
   local eth_h = ether:new({ src = ether:pton(self.exporter_mac),
                             dst = ether:pton(self.collector_mac),
                             type = 0x0800 })
   local ip_h  = ipv4:new({ src = ipv4:pton(self.exporter_ip),
                            dst = ipv4:pton(self.collector_ip),
                            protocol = 17,
                            ttl = 64,
                            flags = 0x02 })
   local udp_h = udp:new({ src_port = self.exporter_port,
                           dst_port = self.collector_port })

   udp_h:length(udp_h:sizeof() + pkt.length)
   udp_h:checksum(pkt.data, pkt.length, ip_h)
   ip_h:total_length(ip_h:sizeof() + udp_h:sizeof() + pkt.length)
   ip_h:checksum()

   local dgram = datagram:new(pkt)
   dgram:push(udp_h)
   dgram:push(ip_h)
   dgram:push(eth_h)
   return dgram:packet()
end

function IPFIX:push()
   local input = self.input.input
   local timestamp = get_timestamp()
   assert(self.output.output, "missing output link")
   local outgoing = self.outgoing_messages

   if self.next_template_refresh < engine.now() then
      self.next_template_refresh = engine.now() + template_interval
      self:send_template_records(outgoing)
   end

   for i=1,link.nreadable(input) do
      local pkt = link.receive(input)
      if self.ipv4_flows.match(pkt.data, pkt.length) then
         link.transmit(self.ipv4_flows.incoming, pkt)
      elseif self.ipv6_flows.match(pkt.data, pkt.length) then
         link.transmit(self.ipv6_flows.incoming, pkt)
      else
         -- Drop packet.
         packet.free(pkt)
      end
   end

   self.ipv4_flows:record_flows(timestamp)
   self.ipv6_flows:record_flows(timestamp)

   self.ipv4_flows:expire_records(outgoing)
   self.ipv6_flows:expire_records(outgoing)

   for i=1,link.nreadable(outgoing) do
      local pkt = link.receive(outgoing)
      pkt = self:add_ipfix_header(pkt, remove_record_count(pkt))
      pkt = self:add_transport_headers(pkt)
      link.transmit(self.output.output, pkt)
   end
end

function selftest()
   print('selftest: apps.ipfix.ipfix')
   local consts = require("apps.lwaftr.constants")
   local ethertype_ipv4 = consts.ethertype_ipv4
   local ethertype_ipv6 = consts.ethertype_ipv6
   local ipfix = IPFIX:new({ ipfix_version = 10,
                             exporter_mac = "00:11:22:33:44:55",
                             exporter_ip = "192.168.1.2",
                             collector_mac = "55:44:33:22:11:00",
                             collector_ip = "192.168.1.1",
                             collector_port = 4739 })

   -- Mock input and output.
   ipfix.input = { input = link.new_anonymous() }
   ipfix.output = { output = link.new_anonymous() }

   -- Test helper that supplies a packet with some given fields.
   local function test(src_ip, dst_ip, src_port, dst_port)
      local is_ipv6 = not not src_ip:match(':')
      local proto = is_ipv6 and ethertype_ipv6 or ethertype_ipv4
      local eth = ether:new({ src = ether:pton("00:11:22:33:44:55"),
                              dst = ether:pton("55:44:33:22:11:00"),
                              type = proto })
      local ip

      if is_ipv6 then
         ip = ipv6:new({ src = ipv6:pton(src_ip), dst = ipv6:pton(dst_ip),
                         next_header = IP_PROTO_UDP, ttl = 64 })
      else
         ip = ipv4:new({ src = ipv4:pton(src_ip), dst = ipv4:pton(dst_ip),
                         protocol = IP_PROTO_UDP, ttl = 64 })
      end
      local udp = udp:new({ src_port = src_port, dst_port = dst_port })
      local dg = datagram:new()

      dg:push(udp)
      dg:push(ip)
      dg:push(eth)

      link.transmit(ipfix.input.input, dg:packet())
      ipfix:push()
   end

   -- Populate with some known flows.
   test("192.168.1.1", "192.168.1.25", 9999, 80)
   test("192.168.1.25", "192.168.1.1", 3653, 23552)
   test("192.168.1.25", "8.8.8.8", 58342, 53)
   test("8.8.8.8", "192.168.1.25", 53, 58342)
   test("2001:4860:4860::8888", "2001:db8::ff00:42:8329", 53, 57777)
   assert(ipfix.ipv4_flows.table.occupancy == 4,
          string.format("wrong number of v4 flows: %d", ipfix.ipv4_flows.table.occupancy))
   assert(ipfix.ipv6_flows.table.occupancy == 1,
          string.format("wrong number of v6 flows: %d", ipfix.ipv6_flows.table.occupancy))

   -- do some packets with random data to test that it doesn't interfere
   for i=1, 100 do
      test(string.format("192.168.1.%d", math.random(2, 254)),
           "192.168.1.25",
           math.random(10000, 65535),
           math.random(1, 79))
   end

   local key = ipfix.ipv4_flows.scratch_entry.key
   key.sourceIPv4Address = ipv4:pton("192.168.1.1")
   key.destinationIPv4Address = ipv4:pton("192.168.1.25")
   key.protocolIdentifier = IP_PROTO_UDP
   key.sourceTransportPort = 9999
   key.destinationTransportPort = 80

   local result = ipfix.ipv4_flows.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.packetDeltaCount == 1)

   -- make sure the count is incremented on the same flow
   test("192.168.1.1", "192.168.1.25", 9999, 80)
   assert(result.value.packetDeltaCount == 2,
          string.format("wrong count: %d", tonumber(result.value.packetDeltaCount)))

   -- check the IPv6 key too
   local key = ipfix.ipv6_flows.scratch_entry.key
   key.sourceIPv6Address = ipv6:pton("2001:4860:4860::8888")
   key.destinationIPv6Address = ipv6:pton("2001:db8::ff00:42:8329")
   key.protocolIdentifier = IP_PROTO_UDP
   key.sourceTransportPort = 53
   key.destinationTransportPort = 57777

   local result = ipfix.ipv6_flows.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.packetDeltaCount == 1)

   -- sanity check
   ipfix.ipv4_flows.table:selfcheck()
   ipfix.ipv6_flows.table:selfcheck()

   local key = ipfix.ipv4_flows.scratch_entry.key
   key.sourceIPv4Address = ipv4:pton("192.168.2.1")
   key.destinationIPv4Address = ipv4:pton("192.168.2.25")
   key.protocolIdentifier = 17
   key.sourceTransportPort = 9999
   key.destinationTransportPort = 80

   local value = ipfix.ipv4_flows.scratch_entry.value
   value.flowStartMilliseconds = get_timestamp() - 500e3
   value.flowEndMilliseconds = value.flowStartMilliseconds + 30
   value.packetDeltaCount = 5
   value.octetDeltaCount = 15

   -- Add value that should be immediately expired
   ipfix.ipv4_flows.table:add(key, value)

   -- Template message; no data yet.
   assert(link.nreadable(ipfix.output.output) == 1)
   -- Cause expiry.  By default we do 1/1000th of the table per push,
   -- so this should be good.
   for i=1,2000 do ipfix:push() end
   -- Template message and data message.
   assert(link.nreadable(ipfix.output.output) == 2)

   local filter = require("pf").compile_filter([[
      udp and dst port 4739 and src net 192.168.1.2 and
      dst net 192.168.1.1]])

   for i=1,link.nreadable(ipfix.output.output) do
      local p = link.receive(ipfix.output.output)
      assert(filter(p.data, p.length), "pf filter failed")
      packet.free(p)
   end
   ipfix.output = {}

   print("selftest ok")
end

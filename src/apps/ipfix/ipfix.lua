-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This module implements an IPFIX exporter, recording flows on its
-- input link and exporting IPFIX messages on its output.

module(..., package.seeall)

local bit      = require("bit")
local ffi      = require("ffi")
local template = require("apps.ipfix.template")
local metadata = require("apps.ipfix.packet_metadata")
local lib      = require("core.lib")
local link     = require("core.link")
local packet   = require("core.packet")
local shm      = require("core.shm")
local counter  = require("core.counter")
local datagram = require("lib.protocol.datagram")
local ether    = require("lib.protocol.ethernet")
local ipv4     = require("lib.protocol.ipv4")
local ipv6     = require("lib.protocol.ipv6")
local udp      = require("lib.protocol.udp")
local ctable   = require("lib.ctable")
local C        = ffi.C

local htonl, htons = lib.htonl, lib.htons
local metadata_add = metadata.add

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local IP_PROTO_UDP  = 17

-- RFC 3954 §5.1.
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
-- RFC 7011 §3.1.
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
-- RFC 7011 §3.3.2.
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

-- This result is a double, which can store precise integers up to
-- 2^51 or so.  For milliseconds this corresponds to the year 77300 or
-- so, assuming an epoch of 1970.  If we went to microseconds, it
-- would be good until 2041.
local function to_milliseconds(secs)
   return math.floor(secs * 1e3 + 0.5)
end

-- Pad a length value to multiple of 4.
local max_padding = 3
local function padded_length(len)
   return bit.band(len + max_padding, bit.bnot(max_padding))
end

-- The real work in the IPFIX app is performed by FlowSet objects,
-- which record and export flows.  However an IPv4 FlowSet won't know
-- what to do with IPv6 packets, so the IPFIX app can have multiple
-- FlowSets.  When a packet comes in, the IPFIX app will determine
-- which FlowSet it corresponds to, and then add the packet to the
-- FlowSet's incoming work queue.  This incoming work queue is a
-- normal Snabb link.  Likewise when the FlowSet exports flow records,
-- it will send flow-expiry messages out its outgoing link, which need
-- to be encapsulated by the IPFIX app.  We use internal links for
-- that purpose as well.
local internal_link_counters = {}
local function new_internal_link(name_prefix)
   local count, name = internal_link_counters[name_prefix], name_prefix
   if count then
      count = count + 1
      name = name..' '..tostring(count)
   end
   internal_link_counters[name_prefix] = count or 1
   return name, link.new(name)
end

FlowSet = {}

function FlowSet:new (template, args)
   assert(args.active_timeout > args.scan_time,
          string.format("Template #%d: active timeout (%d) "
                           .."must be larger than scan time (%d)",
                        template.id, args.active_timeout,
                        args.scan_time))
   assert(args.idle_timeout > args.scan_time,
          string.format("Template #%d: idle timeout (%d) "
                           .."must be larger than scan time (%d)",
                        template.id, args.idle_timeout,
                        args.scan_time))
   local o = { template = template,
               flush_timer = (args.flush_timeout > 0 and
                                 lib.throttle(args.flush_timeout))
                  or function () return true end,
               idle_timeout = assert(args.idle_timeout),
               active_timeout = assert(args.active_timeout),
               scan_time = args.scan_time,
               parent = assert(args.parent) }

   if     args.version == 9  then o.template_id = V9_TEMPLATE_ID
   elseif args.version == 10 then o.template_id = V10_TEMPLATE_ID
   else error('bad version: '..args.version) end

   -- Accumulate outgoing records in a packet.  Instead of this
   -- per-FlowSet accumulator, it would be possible to instead pack
   -- all outgoing records into a central record accumulator for all
   -- types of data and template records.  This would pack more
   -- efficiently, but sadly the old NetFlow v9 standard doesn't
   -- support mixing different types of records in the same export
   -- packet.
   o.record_buffer, o.record_count = packet.allocate(), 0

   -- Max number of records + padding that fit in packet, with set header.
   local mtu = assert(args.mtu)
   local avail = padded_length(mtu - ffi.sizeof(set_header_t) - max_padding)
   o.max_record_count = math.floor(avail / template.data_len)

   local params = {
      key_type = template.key_t,
      value_type = template.value_t,
      max_occupancy_rate = 0.4,
      resize_callback = function(table, old_size)
         template.logger:log("resize flow cache "..old_size..
                                " -> "..table.size)
         require('jit').flush()
         o.table_tb:rate(math.ceil(table.size / o.scan_time))
      end
   }
   if args.cache_size then
      params.initial_size = math.ceil(args.cache_size / 0.4)
   end
   o.table_tb = lib.token_bucket_new()
   o.table = ctable.new(params)
   o.table_tstamp = C.get_unix_time()
   o.table_scan_time = 0
   o.scratch_entry = o.table.entry_type()
   o.expiry_cursor = 0

   o.match = template.match
   o.incoming_link_name, o.incoming = new_internal_link('IPFIX incoming')

   o.shm = shm.create_frame("templates/"..template.id,
                            {  packets_in = { counter },
                               flow_export_packets = { counter },
                               exported_flows = { counter },
                               table_size = { counter, o.table.size },
                               table_byte_size = { counter, o.table.byte_size },
                               table_occupancy = { counter, o.table.occupancy },
                               table_max_displacement = { counter, o.table.max_displacement },
                               table_scan_time = { counter, 0 } })
   return setmetatable(o, { __index = self })
end

function FlowSet:record_flows(timestamp)
   local entry = self.scratch_entry
   timestamp = to_milliseconds(timestamp)
   for i=1,link.nreadable(self.incoming) do
      local pkt = link.receive(self.incoming)
      counter.add(self.shm.packets_in)
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
   counter.add(self.shm.exported_flows)

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

   -- Add headers provided by the IPFIX object that created us
   pkt = self.parent:add_ipfix_header(pkt, record_count)
   pkt = self.parent:add_transport_headers(pkt)
   link.transmit(out, pkt)
   counter.add(self.shm.flow_export_packets)
end

-- Print debugging messages for a flow.
function FlowSet:debug_flow(entry, msg)
   if debug then
      local out = string.format("%s | %s %s\n", os.date("%F %H:%M:%S"),
                                msg, self.template.tostring(entry))
      io.stderr:write(out)
      io.stderr:flush()
   end
end

-- Walk through flow set to see if flow records need to be expired.
-- Collect expired records and export them to the collector.
function FlowSet:expire_records(out, now)
   local cursor = self.expiry_cursor
   now_ms = to_milliseconds(now)
   local active = to_milliseconds(self.active_timeout)
   local idle = to_milliseconds(self.idle_timeout)
   for i = 1, self.table_tb:take_all() do
      local entry
      cursor, entry = self.table:next_entry(cursor, cursor + 1)
      if entry then
         if now_ms - tonumber(entry.value.flowEndMilliseconds) > idle then
            self:debug_flow(entry, "expire idle")
            -- Relying on key and value being contiguous.
            self:add_data_record(entry.key, out)
            self.table:remove_ptr(entry)
         elseif now_ms - tonumber(entry.value.flowStartMilliseconds) > active then
            self:debug_flow(entry, "expire active")
            self:add_data_record(entry.key, out)
            -- TODO: what should timers reset to?
            entry.value.flowStartMilliseconds = now_ms
            entry.value.flowEndMilliseconds = now_ms
            entry.value.packetDeltaCount = 0
            entry.value.octetDeltaCount = 0
            cursor = cursor + 1
         else
            -- Flow still live.
            cursor = cursor + 1
         end
      else
         -- Empty slot or end of table
         if cursor == 0 then
            self.table_scan_time = now - self.table_tstamp
            self.table_tstamp = now
         end
      end
   end
   self.expiry_cursor = cursor

   if self.flush_timer() then self:flush_data_records(out) end
end

function FlowSet:sync_stats()
   counter.set(self.shm.table_size, self.table.size)
   counter.set(self.shm.table_byte_size, self.table.byte_size)
   counter.set(self.shm.table_occupancy, self.table.occupancy)
   counter.set(self.shm.table_max_displacement, self.table.max_displacement)
   counter.set(self.shm.table_scan_time, self.table_scan_time)
end

IPFIX = {}
local ipfix_config_params = {
   idle_timeout = { default = 300 },
   active_timeout = { default = 120 },
   flush_timeout = { default = 10 },
   cache_size = { default = 20000 },
   scan_time = { default = 10 },
   -- RFC 5153 §6.2 recommends a 10-minute template refresh
   -- configurable from 1 minute to 1 day.
   template_refresh_interval = { default = 600 },
   -- Valid values: 9 or 10.
   ipfix_version = { default = 10 },
   -- RFC 7011 §10.3.3 specifies that if the PMTU is unknown, a
   -- maximum of 512 octets should be used for UDP transmission.
   mtu = { default = 512 },
   observation_domain = { default = 256 },
   exporter_ip = { required = true },
   exporter_eth_src = { default = '00:00:00:00:00:00' },
   exporter_eth_dst = { default = '00:00:00:00:00:00' },
   collector_ip = { required = true },
   collector_port = { required = true },
   templates = { default = { template.v4, template.v6 } }
}

function IPFIX:new(config)
   config = lib.parse(config, ipfix_config_params)
   local o = { boot_time = engine.now(),
               template_refresh_interval = config.template_refresh_interval,
               next_template_refresh = -1,
               version = config.ipfix_version,
               observation_domain = config.observation_domain }
   o.shm = {
      -- Total number of packets received
      received_packets = { counter },
      -- Packets not matched by any flow set
      ignored_packets = { counter },
      -- Number of template packets sent
      template_packets = { counter },
      -- Non-wrapping sequence number (see add_ipfix_header() for a
      -- brief description of the semantics for IPFIX and Netflowv9)
      sequence_number = { counter, 1 },
      version = { counter, o.version },
      observation_domain = { counter, o.observation_domain },
   }

   if o.version == 9 then
      o.header_t = netflow_v9_packet_header_t
   elseif o.version == 10 then
      o.header_t = ipfix_packet_header_t
   else
      error('unsupported ipfix version: '..o.version)
   end
   o.header_ptr_t = ptr_to(o.header_t)
   o.header_size = ffi.sizeof(o.header_t)

   -- Prepare transport headers to prepend to each export packet
   -- TODO: Support IPv6.
   local eth_h = ether:new({ src = ether:pton(config.exporter_eth_src),
                             dst = ether:pton(config.exporter_eth_dst),
                             type = 0x0800 })
   local ip_h  = ipv4:new({ src = ipv4:pton(config.exporter_ip),
                            dst = ipv4:pton(config.collector_ip),
                            protocol = 17,
                            ttl = 64,
                            flags = 0x02 })
   local udp_h = udp:new({ src_port = math.random(49152, 65535),
                           dst_port = config.collector_port })
   local transport_headers = datagram:new(packet.allocate())
   transport_headers:push(udp_h)
   transport_headers:push(ip_h)
   transport_headers:push(eth_h)
   -- We need to update the IP and UDP headers after adding a payload.
   -- The following re-locates ip_h and udp_h to point to the headers
   -- in the template packet.
   transport_headers:new(transport_headers:packet(), ether) -- Reset the parse stack
   transport_headers:parse_n(3)
   _, ip_h, udp_h = unpack(transport_headers:stack())
   o.transport_headers = {
      ip_h = ip_h,
      udp_h = udp_h,
      pkt = transport_headers:packet()
   }

   -- FIXME: Assuming we export to IPv4 address.
   local l3_header_len = 20
   local l4_header_len = 8
   local ipfix_header_len = o.header_size
   local total_header_len = l4_header_len + l3_header_len + ipfix_header_len
   local flow_set_args = { mtu = config.mtu - total_header_len,
                           version = config.ipfix_version,
                           cache_size = config.cache_size,
                           idle_timeout = config.idle_timeout,
                           active_timeout = config.active_timeout,
                           scan_time = config.scan_time,
                           flush_timeout = config.flush_timeout,
                           parent = o }

   o.flow_sets = {}
   for _, template in ipairs(config.templates) do
      table.insert(o.flow_sets, FlowSet:new(template, flow_set_args))
   end

   o.stats_timer = lib.throttle(5)
   return setmetatable(o, { __index = self })
end

function IPFIX:send_template_records(out)
   local pkt = packet.allocate()
   for _, flow_set in ipairs(self.flow_sets) do
      pkt = flow_set:append_template_record(pkt)
   end
   local record_count
   if self.version == 9 then
      record_count = #self.flow_sets
   else
      -- For IPFIX, template records are not accounted for in the
      -- sequence number of the header
      record_count = 0
   end
   pkt = self:add_ipfix_header(pkt, record_count)
   pkt = self:add_transport_headers(pkt)
   counter.add(self.shm.template_packets)
   link.transmit(out, pkt)
end

function IPFIX:add_ipfix_header(pkt, count)
   pkt = packet.shiftright(pkt, self.header_size)
   local header = ffi.cast(self.header_ptr_t, pkt.data)

   header.version = htons(self.version)
   header.sequence_number = htonl(tonumber(counter.read(self.shm.sequence_number)))
   if self.version == 9 then
      -- record_count counts the number of all records in this packet
      -- (template and data)
      header.record_count = htons(count)
      -- sequence_number counts the number of exported packets
      conter.add(self.shm.sequence_number)
      header.uptime = htonl(to_milliseconds(engine.now() - self.boot_time))
   elseif self.version == 10 then
      -- sequence_number counts the cumulative number of data records
      -- (i.e. excluding template and option records)
      counter.add(self.shm.sequence_number, count)
      header.byte_length = htons(pkt.length)
   end
   header.timestamp = htonl(math.floor(C.get_unix_time()))
   header.observation_domain = htonl(self.observation_domain)

   return pkt
end

function IPFIX:add_transport_headers (pkt)
   local headers = self.transport_headers
   local ip_h, udp_h = headers.ip_h, headers.udp_h
   udp_h:length(udp_h:sizeof() + pkt.length)
   udp_h:checksum(pkt.data, pkt.length, ip_h)
   ip_h:total_length(ip_h:sizeof() + udp_h:sizeof() + pkt.length)
   ip_h:checksum()
   return packet.prepend(pkt, headers.pkt.data, headers.pkt.length)
end

function IPFIX:push()
   local input = self.input.input
   -- FIXME: Use engine.now() for monotonic time.  Have to check that
   -- engine.now() gives values relative to the UNIX epoch though.
   local timestamp = ffi.C.get_unix_time()
   assert(self.output.output, "missing output link")
   local output = self.output.output

   if self.next_template_refresh < engine.now() then
      self.next_template_refresh = engine.now() + self.template_refresh_interval
      self:send_template_records(output)
   end

   local flow_sets = self.flow_sets
   local nreadable = link.nreadable(input)
   counter.add(self.shm.received_packets, nreadable)
   for _,set in ipairs(flow_sets) do
      for _ = 1, nreadable do
         local p = link.receive(input)
         local md = metadata_add(p)
         if set.match(md.filter_start, md.filter_length) then
            link.transmit(set.incoming, p)
         else
            link.transmit(input, p)
         end
      end
      nreadable = link.nreadable(input)
   end

   counter.add(self.shm.ignored_packets, nreadable)
   for _ = 1, nreadable do
      packet.free(link.receive(input))
   end

   for _,set in ipairs(flow_sets) do set:record_flows(timestamp) end
   for _,set in ipairs(flow_sets) do set:expire_records(output, timestamp) end

   if self.stats_timer() then
      for _,set in ipairs(flow_sets) do
         set:sync_stats()
      end
   end
end

function selftest()
   print('selftest: apps.ipfix.ipfix')
   local consts = require("apps.lwaftr.constants")
   local ethertype_ipv4 = consts.ethertype_ipv4
   local ethertype_ipv6 = consts.ethertype_ipv6
   local ipfix = IPFIX:new({ exporter_ip = "192.168.1.2",
                             collector_ip = "192.168.1.1",
                             collector_port = 4739,
                             flush_timeout = 0 })

   -- Mock input and output.
   local input_name, input = new_internal_link('ipfix selftest input')
   local output_name, output = new_internal_link('ipfix selftest output')
   ipfix.input, ipfix.output = { input = input }, { output = output }
   local ipv4_flows, ipv6_flows = unpack(ipfix.flow_sets)

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

      link.transmit(input, dg:packet())
      ipfix:push()
   end

   -- Populate with some known flows.
   test("192.168.1.1", "192.168.1.25", 9999, 80)
   test("192.168.1.25", "192.168.1.1", 3653, 23552)
   test("192.168.1.25", "8.8.8.8", 58342, 53)
   test("8.8.8.8", "192.168.1.25", 53, 58342)
   test("2001:4860:4860::8888", "2001:db8::ff00:42:8329", 53, 57777)
   assert(ipv4_flows.table.occupancy == 4,
          string.format("wrong number of v4 flows: %d", ipv4_flows.table.occupancy))
   assert(ipv6_flows.table.occupancy == 1,
          string.format("wrong number of v6 flows: %d", ipv6_flows.table.occupancy))

   -- do some packets with random data to test that it doesn't interfere
   for i=1, 10000 do
      test(string.format("192.168.1.%d", math.random(2, 254)),
           "192.168.1.25",
           math.random(10000, 65535),
           math.random(1, 79))
   end

   local key = ipv4_flows.scratch_entry.key
   key.sourceIPv4Address = ipv4:pton("192.168.1.1")
   key.destinationIPv4Address = ipv4:pton("192.168.1.25")
   key.protocolIdentifier = IP_PROTO_UDP
   key.sourceTransportPort = 9999
   key.destinationTransportPort = 80

   local result = ipv4_flows.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.packetDeltaCount == 1)

   -- make sure the count is incremented on the same flow
   test("192.168.1.1", "192.168.1.25", 9999, 80)
   assert(result.value.packetDeltaCount == 2,
          string.format("wrong count: %d", tonumber(result.value.packetDeltaCount)))

   -- check the IPv6 key too
   local key = ipv6_flows.scratch_entry.key
   key.sourceIPv6Address = ipv6:pton("2001:4860:4860::8888")
   key.destinationIPv6Address = ipv6:pton("2001:db8::ff00:42:8329")
   key.protocolIdentifier = IP_PROTO_UDP
   key.sourceTransportPort = 53
   key.destinationTransportPort = 57777

   local result = ipv6_flows.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.packetDeltaCount == 1)

   -- sanity check
   ipv4_flows.table:selfcheck()
   ipv6_flows.table:selfcheck()

   local key = ipv4_flows.scratch_entry.key
   key.sourceIPv4Address = ipv4:pton("192.168.2.1")
   key.destinationIPv4Address = ipv4:pton("192.168.2.25")
   key.protocolIdentifier = 17
   key.sourceTransportPort = 9999
   key.destinationTransportPort = 80

   local value = ipv4_flows.scratch_entry.value
   value.flowStartMilliseconds = to_milliseconds(C.get_unix_time() - 500)
   value.flowEndMilliseconds = value.flowStartMilliseconds + 30
   value.packetDeltaCount = 5
   value.octetDeltaCount = 15

   -- Add value that should be immediately expired
   ipv4_flows.table:add(key, value)

   -- Template message; no data yet.
   assert(link.nreadable(output) == 1)
   -- Cause expiry.  By default we do 1e-5th of the table per push,
   -- so this should be good.
   for i=1,2e5 do ipfix:push() end
   -- Template message and data message.
   assert(link.nreadable(output) == 2)

   local filter = require("pf").compile_filter([[
      udp and dst port 4739 and src net 192.168.1.2 and
      dst net 192.168.1.1]])

   for i=1,link.nreadable(output) do
      local p = link.receive(output)
      assert(filter(p.data, p.length), "pf filter failed")
      packet.free(p)
   end

   link.free(input, input_name)
   link.free(output, output_name)

   print("selftest ok")
end

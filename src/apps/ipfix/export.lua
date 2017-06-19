-- This module implements functions for exporting flow information as
-- IPFIX or Netflow V9 packets to a flow collector.
--
-- See RFC 3954 (https://tools.ietf.org/html/rfc3954)

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local util   = require("apps.ipfix.util")
local lib    = require("core.lib")
local link   = require("core.link")
local dg     = require("lib.protocol.datagram")
local ether  = require("lib.protocol.ethernet")
local ipv4   = require("lib.protocol.ipv4")
local ipv6   = require("lib.protocol.ipv6")
local udp    = require("lib.protocol.udp")
local C      = ffi.C

local htonl, htons  = lib.htonl, lib.htons
local get_timestamp = util.get_timestamp

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

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

local function string_parser(str)
   local idx = 1
   local quote = ('"'):byte()
   local ret = {}
   function ret.consume_upto(char)
      local start_idx = idx
      local byte = char:byte()
      while str:byte(idx) ~= byte do
         if str:byte(idx) == quote then
            idx = idx + 1
            while str:byte(idx) ~= quote do idx = idx + 1 end
         end
         idx = idx + 1
      end
      idx = idx + 1
      return string.sub(str, start_idx, idx - 2)
   end
   function ret.is_done() return idx > str:len() end
   return ret
end

-- Parse out available IPFIX fields.
local function make_ipfix_element_map()
   local elems = require("apps.ipfix.ipfix_information_elements_inc")
   local parser = string_parser(elems)
   local map = {}
   while not parser.is_done() do
      local id = parser.consume_upto(",")
      local name = parser.consume_upto(",")
      local data_type = parser.consume_upto(",")
      for i=1,8 do parser.consume_upto(",") end
      parser.consume_upto("\n")
      map[name] = { id = id, data_type = data_type }
   end
   return map
end

local ipfix_elements = make_ipfix_element_map()

-- Representations of IPFIX IEs.
local uint8_t = ffi.typeof('uint8_t')
local uint16_t = ffi.typeof('uint16_t')
local uint32_t = ffi.typeof('uint32_t')
local uint64_t = ffi.typeof('uint64_t')
local ipv4_t = ffi.typeof('uint8_t[4]')
local ipv6_t = ffi.typeof('uint8_t[4]')

local data_ctypes =
   { unsigned8 = uint8_t,
     unsigned16 = uint16_t,
     unsigned32 = uint32_t,
     unsigned64 = uint64_t,
     ipv4Address = ipv4_t,
     ipv6Address = ipv6_t,
     dateTimeMilliseconds = uint64_t }

-- Create a table describing the information needed to create
-- flow templates and data records.
local function make_template_info(id, key_fields, record_fields)
   -- the contents of the template records we will send
   -- there is an ID & length for each field
   local length = 2 * (#key_fields + #record_fields)
   local buffer = ffi.new("uint16_t[?]", length)

   -- octets in a data record
   local data_len = 0
   local struct_def = {}
   local types = {}

   local function process_fields(buffer, fields)
      for idx, name in ipairs(fields) do
         local entry = ipfix_elements[name]
         local ctype = assert(data_ctypes[entry.data_type],
                              'unimplemented type: '..entry.data_type)
         data_len = data_len + ffi.sizeof(ctype)
         buffer[2 * (idx - 1)]     = htons(entry.id)
         buffer[2 * (idx - 1) + 1] = htons(ffi.sizeof(ctype))
         table.insert(struct_def, '$ '..name..';')
         table.insert(types, ctype)
      end
   end

   table.insert(struct_def, 'struct {')
   process_fields(buffer, key_fields)
   process_fields(buffer + #key_fields * 2, record_fields)
   table.insert(struct_def, '} __attribute((packed))')
   local struct_t = ffi.typeof(table.concat(struct_def, ' '), unpack(types))
   assert(ffi.sizeof(struct_t) == data_len)

   return { id = id,
            field_count = #key_fields + #record_fields,
            buffer = buffer,
            buffer_len = length * 2,
            data_len = data_len,
            record_t = struct_t,
            record_ptr_t = ptr_to(struct_t) }
end

local template_v4 = make_template_info(256,
   { "sourceIPv4Address",
     "destinationIPv4Address",
     "protocolIdentifier",
     "sourceTransportPort",
     "destinationTransportPort" },
   { "flowStartMilliseconds",
     "flowEndMilliseconds",
     "packetDeltaCount",
     "octetDeltaCount",
     "ingressInterface",
     "egressInterface",
     "bgpPrevAdjacentAsNumber",
     "bgpNextAdjacentAsNumber",
     "tcpControlBits",
     "ipClassOfService" })

local template_v6 = make_template_info(257,
   { "sourceIPv6Address",
     "destinationIPv6Address",
     "protocolIdentifier",
     "sourceTransportPort",
     "destinationTransportPort" },
   { "flowStartMilliseconds",
     "flowEndMilliseconds",
     "packetDeltaCount",
     "octetDeltaCount",
     "ingressInterface",
     "egressInterface",
     "bgpPrevAdjacentAsNumber",
     "bgpNextAdjacentAsNumber",
     "tcpControlBits",
     "ipClassOfService" })

-- RFC5153 recommends a 10-minute template refresh configurable from
-- 1 minute to 1 day (https://tools.ietf.org/html/rfc5153#section-6.2)
local template_interval = 600

FlowExporter = {}

-- periodically refresh the templates on the collector
local function init_refresh_templates()
   local last_time

   return function(self)
      local now = tonumber(engine.now())

      if not last_time or now - last_time >= template_interval then
         self:send_template_record()
         last_time = now
      end
   end
end

function FlowExporter:new(config)
   local o = { cache = assert(config.cache),
               -- sequence number to use for flow packets
               sequence_number = 1,
               boot_time = util.get_timestamp(),
               -- version of IPFIX/Netflow (9 or 10)
               version = assert(config.ipfix_version),
               template_timer = nil,
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

   if o.version == 9 then
      o.header_t = netflow_v9_packet_header_t
   elseif o.version == 10 then
      o.header_t = ipfix_packet_header_t
   else
      error('unsupported ipfix version: '..o.version)
   end
   o.header_ptr_t = ptr_to(o.header_t)
   o.header_size = ffi.sizeof(o.header_t)

   o.refresh_templates = init_refresh_templates()

   return setmetatable(o, { __index = self })
end

function FlowExporter:construct_packet(ptr, len)
   local dgram  = dg:new()

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

   dgram:payload(ptr, len)
   udp_h:length(udp_h:sizeof() + len)
   udp_h:checksum(ptr, len, ip_h)
   dgram:push(udp_h)
   ip_h:total_length(ip_h:sizeof() + udp_h:sizeof() + len)
   ip_h:checksum()
   dgram:push(ip_h)
   dgram:push(eth_h)

   return dgram:packet()
end

local uint8_ptr_t = ffi.typeof('uint8_t*')
local function as_uint8_ptr(x) return ffi.cast(uint8_ptr_t, x) end
local function htonq(v) return bit.bswap(v + 0ULL) end


function FlowExporter:write_header(ptr, count, length)
   local header = ffi.cast(self.header_ptr_t, ptr)

   header.version = htons(self.version)
   if self.version == 9 then
      header.count = htons(count)
      header.uptime = htonl(tonumber(get_timestamp() - self.boot_time))
   elseif self.version == 10 then
      header.byte_length = htons(length)
   end
   header.timestamp = htonl(math.floor(C.get_unix_time()))
   header.sequence_number = htonl(self.sequence_number)
   header.observation_domain = htonl(self.observation_domain)

   self.sequence_number = self.sequence_number + 1
end

-- Send template records/option template records to the collector
-- TODO: only handles template records so far
function FlowExporter:send_template_record()
   local templates = { template_v4, template_v6 }
   local length = self.header_size

   for _, template in ipairs(templates) do
      -- +8 octets for the flow set header / record header
      length = length + template.buffer_len + 8
   end

   local buffer = ffi.new("uint8_t[?]", length)
   self:write_header(buffer, 2, length)

   -- Write the header and then the template record contents for each
   -- template.
   local ptr = buffer + self.header_size
   for _, template in ipairs(templates) do
      local header = ffi.cast(template_header_ptr_t, ptr)
      if self.version == 9 then
         header.set_header.id = htons(V9_TEMPLATE_ID)
      elseif self.version == 10 then
         header.set_header.id = htons(V10_TEMPLATE_ID)
      end
      local length = template.buffer_len + ffi.sizeof(template_header_t)
      header.set_header.length = htons(length)
      header.template_id = htons(template.id)
      header.field_count = htons(template.field_count)
      ptr = ptr + ffi.sizeof(template_header_t)
      
      ffi.copy(ptr, template.buffer, template.buffer_len)
      ptr = ptr + template.buffer_len
   end

   local pkt = self:construct_packet(as_uint8_ptr(buffer), length)

   link.transmit(self.output.output, pkt)

   if debug then
      util.fe_debug("sent template packet, seq#: %d octets: %d",
                    self.sequence_number - 1, length)
   end
end

-- Given a flow exporter & an array of ctable entries, construct flow
-- record packet(s) and transmit them
function FlowExporter:export_ipv4_records(entries)
   -- length of header + flow set ID/length
   local header_len  = self.header_size + 4
   local record_len  = template_v4.data_len
   -- 4 is the max padding, so account for that conservatively to
   -- figure out how many records we can fit in the MTU
   local max_records = math.floor((self.mtu - header_len - 4 - 28) / record_len)

   local record_idx  = 1
   while record_idx <= #entries do
      local num_to_take = math.min(max_records, #entries - record_idx + 1)
      local data_len    = header_len + (record_len * num_to_take)
      local padding     = (4 - (data_len % 4)) % 4
      local length      = data_len + padding
      local buffer      = ffi.new("uint8_t[?]", length)
      self:write_header(buffer, num_to_take, length)

      local set_header = ffi.cast(set_header_ptr_t, buffer + self.header_size)
      set_header.id = htons(template_v4.id)
      set_header.length = htons(length - self.header_size)
      local records = ffi.cast(template_v4.record_ptr_t, buffer + self.header_size)

      for idx = 0, num_to_take - 1 do
         local key    = entries[record_idx + idx].key
         local value  = entries[record_idx + idx].value
         local record = records[idx]

         -- Should we somehow line up the key/value representation in
         -- the ctable with the actual binary data that we export?
         record.sourceIPv4Address = key.src_ip
         record.destinationIPv4Address = key.dst_ip
         record.protocolIdentifier = key.protocol
         record.sourceTransportPort = key.src_port
         record.destinationTransportPort = key.dst_port

         record.flowStartMilliseconds = htonq(value.start_time)
         record.flowEndMilliseconds = htonq(value.end_time)
         record.packetDeltaCount = htonq(value.pkt_count)
         record.octetDeltaCount = htonq(value.octet_count)

         record.ingressInterface = value.ingress
         record.egressInterface = value.egress
         record.bgpPrevAdjacentAsNumber = value.src_peer_as
         record.bgpNextAdjacentAsNumber = value.dst_peer_as
         record.tcpControlBits = value.tcp_control
         record.ipClassOfService = value.tos
      end

      local pkt = self:construct_packet(buffer, length)

      link.transmit(self.output.output, pkt)

      record_idx = record_idx + num_to_take

      if debug then
         util.fe_debug("sent data packet, seq#: %d octets: %d",
                       self.sequence_number - 1, length)
      end
   end
end

function FlowExporter:push()
   assert(self.output.output, "missing output link")

   self:refresh_templates()

   local expired = self.cache.v4:get_expired()
   if #expired > 0 then
      self:export_ipv4_flow_records(expired)
      self.cache.v4:clear_expired()
   end

   local expired = self.cache.v6:get_expired()
   if #expired > 0 then
      self:export_ipv6_flow_records(expired)
      self.cache.v6:clear_expired()
   end
end

function selftest()
   local pf    = require("pf")
   local cache = require("apps.ipfix.cache")

   local flows = cache.FlowCache:new({})
   local conf = { cache = flows,
                  ipfix_version = 10,
                  exporter_mac = "00:11:22:33:44:55",
                  exporter_ip = "192.168.1.2",
                  collector_mac = "55:44:33:22:11:00",
                  collector_ip = "192.168.1.1",
                  collector_port = 4739 }
   local exporter = FlowExporter:new(conf)

   local key = flows.v4.preallocated_key
   key.src_ip = ipv4:pton("192.168.1.1")
   key.dst_ip = ipv4:pton("192.168.1.25")
   key.protocol = 17
   key.src_port = htons(9999)
   key.dst_port = htons(80)

   local value = flows.v4.preallocated_value
   value.start_time = get_timestamp()
   value.end_time = value.start_time + 30
   value.pkt_count = 5
   value.octet_count = 15

   -- mock transmit function and output link
   local packet
   exporter.output = { output = {} }
   link.transmit = function(link, pkt) packet = pkt end
   exporter:export_ipv4_records({ { key = key, value = value } })

   local filter = pf.compile_filter([[
      udp and dst port 4739 and src net 192.168.1.2 and
      dst net 192.168.1.1]])

   assert(filter(packet.data, packet.length), "pf filter failed")

   print("selftest ok")
end

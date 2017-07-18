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
local function htonq(v) return bit.bswap(v + 0ULL) end

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

local swap_fn_env = { htons = htons, htonl = htonl, htonq = htonq }

-- Create a table describing the information needed to create
-- flow templates and data records.
local function make_template_info(spec)
   -- Representations of IPFIX IEs.
   local ctypes =
      { unsigned8 = 'uint8_t', unsigned16 = 'uint16_t',
        unsigned32 = 'uint32_t', unsigned64 = 'uint64_t',
        ipv4Address = 'uint8_t[4]', ipv6Address = 'uint8_t[16]',
        dateTimeMilliseconds = 'uint64_t' }
   local bswap = { uint16_t='htons', uint32_t='htonl', uint64_t='htonq' }
   -- the contents of the template records we will send
   -- there is an ID & length for each field
   local length = 2 * (#spec.keys + #spec.values)
   local buffer = ffi.new("uint16_t[?]", length)

   -- octets in a data record
   local data_len = 0
   local swap_fn = {}

   local function process_fields(buffer, fields, struct_def, types, swap_tmpl)
      for idx, name in ipairs(fields) do
         local entry = ipfix_elements[name]
         local ctype = assert(ctypes[entry.data_type],
                              'unimplemented: '..entry.data_type)
         data_len = data_len + ffi.sizeof(ctype)
         buffer[2 * (idx - 1)]     = htons(entry.id)
         buffer[2 * (idx - 1) + 1] = htons(ffi.sizeof(ctype))
         table.insert(struct_def, '$ '..name..';')
         table.insert(types, ffi.typeof(ctype))
         if bswap[ctype] then
            table.insert(swap_fn, swap_tmpl:format(name, bswap[ctype], name))
         end
      end
   end

   table.insert(swap_fn, 'return function(o)')
   local key_struct_def = { 'struct {' }
   local key_types = {}
   process_fields(buffer, spec.keys, key_struct_def, key_types,
                  'o.key.%s = %s(o.key.%s)')
   table.insert(key_struct_def, '} __attribute__((packed))')
   local value_struct_def = { 'struct {' }
   local value_types = {}
   process_fields(buffer + #spec.keys * 2, spec.values, value_struct_def,
                  value_types, 'o.value.%s = %s(o.value.%s)')
   table.insert(value_struct_def, '} __attribute__((packed))')
   table.insert(swap_fn, 'end')
   local key_t = ffi.typeof(table.concat(key_struct_def, ' '),
                            unpack(key_types))
   local value_t = ffi.typeof(table.concat(value_struct_def, ' '),
                              unpack(value_types))
   local record_t = ffi.typeof(
      'struct { $ key; $ value; } __attribute__((packed))', key_t, value_t)
   gen_swap_fn = loadstring(table.concat(swap_fn, '\n'))
   setfenv(gen_swap_fn, swap_fn_env)

   assert(ffi.sizeof(record_t) == data_len)

   return { id = spec.id,
            field_count = #spec.keys + #spec.values,
            buffer = buffer,
            buffer_len = length * 2,
            data_len = data_len,
            key_t = key_t,
            value_t = value_t,
            record_t = record_t,
            record_ptr_t = ptr_to(record_t),
            swap_fn = gen_swap_fn()
          }
end

local template_v4 = make_template_info {
   id     = 256,
   keys   = { "sourceIPv4Address",
              "destinationIPv4Address",
              "protocolIdentifier",
              "sourceTransportPort",
              "destinationTransportPort" },
   values = { "flowStartMilliseconds",
              "flowEndMilliseconds",
              "packetDeltaCount",
              "octetDeltaCount",
              "ingressInterface",
              "egressInterface",
              "bgpPrevAdjacentAsNumber",
              "bgpNextAdjacentAsNumber",
              "tcpControlBits",
              "ipClassOfService" }
}

local template_v6 = make_template_info {
   id     = 257,
   keys   = { "sourceIPv6Address",
              "destinationIPv6Address",
              "protocolIdentifier",
              "sourceTransportPort",
              "destinationTransportPort" },
   values = { "flowStartMilliseconds",
              "flowEndMilliseconds",
              "packetDeltaCount",
              "octetDeltaCount",
              "ingressInterface",
              "egressInterface",
              "bgpPrevAdjacentAsNumber",
              "bgpNextAdjacentAsNumber",
              "tcpControlBits",
              "ipClassOfService" }
}

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
-- Exporter will append the record count, and then the FlowExporter
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

Exporter = {}

function Exporter:new (template, mtu, version)
   local o = {template=template}
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

   return setmetatable(o, { __index = self })
end

function Exporter:append_template_record(pkt)
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
function Exporter:add_data_record(record, out)
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

function Exporter:flush_data_records(out)
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

FlowExporter = {}

function FlowExporter:new(config)
   local o = { cache = assert(config.cache),
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
   o.export_v4 = Exporter:new(template_v4, payload_mtu, o.version)
   o.export_v6 = Exporter:new(template_v6, payload_mtu, o.version)

   self.outgoing_messages = link.new_anonymous()

   return setmetatable(o, { __index = self })
end

function FlowExporter:send_template_records(out)
   local pkt = packet.allocate()
   pkt = self.export_v4:append_template_record(pkt)
   pkt = self.export_v6:append_template_record(pkt)
   add_record_count(pkt, 2)
   link.transmit(out, pkt)
end

function FlowExporter:add_ipfix_header(pkt, count)
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

function FlowExporter:add_transport_headers (pkt)
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

   local dgram = dg:new(pkt)
   dgram:push(udp_h)
   dgram:push(ip_h)
   dgram:push(eth_h)
   return dgram:packet()
end

function FlowExporter:pull ()
   assert(self.output.output, "missing output link")

   local outgoing = self.outgoing_messages

   if self.next_template_refresh < engine.now() then
      self.next_template_refresh = engine.now() + template_interval
      self:send_template_records(outgoing)
   end

   for _, record in ipairs(self.cache.v4:get_expired()) do
      self.export_v4:add_data_record(record, outgoing)
   end
   self.export_v4:flush_data_records(outgoing)

   for _, record in ipairs(self.cache.v6:get_expired()) do
      self.export_v6:add_data_record(record, outgoing)
   end
   self.export_v6:flush_data_records(outgoing)

   for i=1,link.nreadable(outgoing) do
      local pkt = link.receive(outgoing)
      pkt = self:add_ipfix_header(pkt, remove_record_count(pkt))
      pkt = self:add_transport_headers(pkt)
      link.transmit(self.output.output, pkt)
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
   key.src_port = 9999
   key.dst_port = 80

   local value = flows.v4.preallocated_value
   value.start_time = get_timestamp()
   value.end_time = value.start_time + 30
   value.pkt_count = 5
   value.octet_count = 15

   -- FIXME: Remove this impedance matching.
   key = ffi.cast(ptr_to(exporter.export_v4.template.key_t), key)[0]
   value = ffi.cast(ptr_to(exporter.export_v4.template.value_t), value)[0]
   local record = exporter.export_v4.template.record_t(key, value)
   -- Mock expiry.
   function exporter.cache.v4:get_expired()
      return { record }
   end

   -- Mock output.
   local test_link = link.new_anonymous()
   exporter.output = { output = test_link }

   exporter:pull()
   -- Template message and data message.
   assert(link.nreadable(test_link) == 2)

   local filter = pf.compile_filter([[
      udp and dst port 4739 and src net 192.168.1.2 and
      dst net 192.168.1.1]])

   for i=1,link.nreadable(test_link) do
      local p = link.receive(test_link)
      assert(filter(p.data, p.length), "pf filter failed")
      packet.free(p)
   end
   exporter.output = {}

   print("selftest ok")
end

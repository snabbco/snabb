-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local util   = require("apps.ipfix.util")
local consts = require("apps.lwaftr.constants")
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

local Cache = {}

function Cache:new(config, key_t, value_t)
   assert(config, "expected configuration table")

   local o = { -- TODO: compute the default cache value
               --       based on expected flow amounts?
               cache_size = config.cache_size or 20000,
               -- expired flows go into this array
               -- TODO: perhaps a ring buffer is a better idea here
               expired = {} }

   -- how much of the cache to traverse when iterating
   o.stride = math.ceil(o.cache_size / 1000)

   local params = {
      key_type = key_t,
      value_type = value_t,
      max_occupancy_rate = 0.4,
      initial_size = math.ceil(o.cache_size / 0.4),
   }

   o.preallocated_key = key_t()
   o.preallocated_value = value_t()
   o.table = ctable.new(params)

   return setmetatable(o, { __index = self })
end

function Cache:iterate()
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

function Cache:remove(flow_key)
   self.table:remove(flow_key)
end

function Cache:expire_record(key, record, active)
   -- for active expiry, we keep the record around in the cache
   -- so we need a copy that won't be modified
   if active then
      -- FIXME
      local copied_record = ffi.new("struct flow_record")
      ffi.copy(copied_record, record, ffi.sizeof("struct flow_record"))
      table.insert(self.expired, {key = key, value = copied_record})
   else
      table.insert(self.expired, {key = key, value = record})
   end
end

function Cache:get_expired()
   local ret = self.expired
   self.expired = {}
   return ret
end

FlowCache = {}

function FlowCache:new(config)
   assert(config, "expected configuration table")
   local o = {}
   o.v4 = Cache:new(config, template_v4.key_t, template_v4.value_t)
   o.v6 = Cache:new(config, template_v6.key_t, template_v6.value_t)
   return setmetatable(o, { __index = self })
end

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

IPFIX = {}

function IPFIX:new(config)
   local o = { flows = assert(config.cache),
               export_timer = nil,
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
   o.export_v4 = Exporter:new(template_v4, payload_mtu, o.version)
   o.export_v6 = Exporter:new(template_v6, payload_mtu, o.version)

   self.outgoing_messages = link.new_anonymous()

   return setmetatable(o, { __index = self })
end

function IPFIX:send_template_records(out)
   local pkt = packet.allocate()
   pkt = self.export_v4:append_template_record(pkt)
   pkt = self.export_v6:append_template_record(pkt)
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

function IPFIX:process_flow(flows, flow_key, flow_record, l4_header)
   -- TCP, UDP, SCTP all have the ports in the same header location
   if (flow_key.protocolIdentifier == IP_PROTO_TCP
       or flow_key.protocolIdentifier == IP_PROTO_UDP
       or flow_key.protocolIdentifier == IP_PROTO_SCTP) then
      -- FIXME: Use host endianness.
      flow_key.sourceTransportPort = ntohs(ffi.cast("uint16_t*", l4_header)[0])
      flow_key.destinationTransportPort = ntohs(ffi.cast("uint16_t*", l4_header)[1])
   else
      flow_key.sourceTransportPort = 0
      flow_key.destinationTransportPort = 0
   end

   local lookup_result = flows.table:lookup_ptr(flow_key)

   if lookup_result == nil then
      flow_record.flowStartMilliseconds  = flow_record.flowEndMilliseconds
      flow_record.packetDeltaCount   = 1ULL
      if flow_key.protocolIdentifier == IP_PROTO_TCP then
         local ptr = l4_header + TCP_CONTROL_BITS_OFFSET
         flow_record.tcpControlBits = ntohs(ffi.cast("uint16_t*", ptr)[0])
      else
         flow_record.tcpControlBits = 0
      end

      flows.table:add(flow_key, flow_record)
   else
      local timestamp, bytes = flow_record.flowEndMilliseconds, flow_record.octetDeltaCount
      local flow_record = lookup_result.value

      -- otherwise just update the counters and timestamps
      flow_record.flowEndMilliseconds    = timestamp
      flow_record.packetDeltaCount   = flow_record.packetDeltaCount + 1ULL
      flow_record.octetDeltaCount = flow_record.octetDeltaCount + bytes
   end
end

function IPFIX:process_ipv6_packet(pkt, timestamp)
   local l2_header = pkt.data
   -- We could warn here.
   if get_ethernet_n_ethertype(l2_header) ~= n_ethertype_ipv6 then return end

   local flows = self.flows.v6
   local flow_key = flows.preallocated_key
   local flow_record = flows.preallocated_value
   local l3_header = l2_header + ethernet_header_size
   flow_key.protocolIdentifier = get_ipv6_next_header(l3_header)
   ffi.copy(flow_key.sourceIPv6Address, get_ipv6_src_addr_ptr(l3_header), 16)
   ffi.copy(flow_key.destinationIPv6Address, get_ipv6_dst_addr_ptr(l3_header), 16)

   flow_record.flowEndMilliseconds = timestamp
   -- Measure bytes starting with the IP header.
   flow_record.octetDeltaCount = pkt.length - ethernet_header_size
   flow_record.ipClassOfService = get_ipv6_traffic_class(l3_header)

   -- TODO: handle chained headers
   local l4_header = l3_header + ipv6_fixed_header_size

   IPFIX:process_flow(flows, flow_key, flow_record, l4_header)
end

function IPFIX:process_ipv4_packet(pkt, timestamp)
   local l2_header = pkt.data
   -- We could warn here.
   if get_ethernet_n_ethertype(l2_header) ~= n_ethertype_ipv4 then return end

   local flows = self.flows.v4
   local flow_key = flows.preallocated_key
   local flow_record = flows.preallocated_value
   local l3_header = l2_header + ethernet_header_size
   flow_key.protocolIdentifier = get_ipv4_protocol(l3_header)
   ffi.copy(flow_key.sourceIPv4Address, get_ipv4_src_addr_ptr(l3_header), 4)
   ffi.copy(flow_key.destinationIPv4Address, get_ipv4_dst_addr_ptr(l3_header), 4)

   flow_record.flowEndMilliseconds = timestamp
   -- Measure bytes starting with the IP header.
   flow_record.octetDeltaCount = pkt.length - ethernet_header_size
   -- Simpler than combining ip_header:dscp() and ip_header:ecn().
   flow_record.ipClassOfService = l3_header[1]

   local ihl = get_ipv4_ihl(l3_header)
   local l4_header = l3_header + ihl * 4

   IPFIX:process_flow(flows, flow_key, flow_record, l4_header)
end

-- print debugging messages for flow expiration
function IPFIX:debug_expire(entry, timestamp, msg)
   local ipv4 = require("lib.protocol.ipv4")
   local ipv6 = require("lib.protocol.ipv6")

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

-- Walk through flow cache to see if flow records need to be expired.
-- Collect expired records and export them to the collector.
function IPFIX:expire_records()
   for _,proto in ipairs({'v4', 'v6'}) do
      local timestamp = get_timestamp()
      local keys_to_remove = {}
      local timeout_records = {}
      local to_export = {}
      local flows = self.flows[proto]
      for entry in flows:iterate() do
         local record = entry.value

         if timestamp - record.flowEndMilliseconds > self.idle_timeout then
            self:debug_expire(entry, timestamp, "idle")
            table.insert(keys_to_remove, entry.key)
            flows:expire_record(entry.key, record, false)
         elseif timestamp - record.flowStartMilliseconds > self.active_timeout then
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
         record.flowStartMilliseconds = timestamp
         record.flowEndMilliseconds = timestamp
         record.packetDeltaCount = 0
         record.octetDeltaCount = 0
      end
   end
end

function IPFIX:push()
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

   assert(self.output.output, "missing output link")

   local outgoing = self.outgoing_messages

   if self.next_template_refresh < engine.now() then
      self.next_template_refresh = engine.now() + template_interval
      self:send_template_records(outgoing)
   end

   for _, record in ipairs(self.flows.v4:get_expired()) do
      self.export_v4:add_data_record(record, outgoing)
   end
   self.export_v4:flush_data_records(outgoing)

   for _, record in ipairs(self.flows.v6:get_expired()) do
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
   print('selftest: apps.ipfix.ipfix')
   local flows = FlowCache:new({})
   local ipfix = IPFIX:new({ cache = flows,
                             ipfix_version = 10,
                             exporter_mac = "00:11:22:33:44:55",
                             exporter_ip = "192.168.1.2",
                             collector_mac = "55:44:33:22:11:00",
                             collector_ip = "192.168.1.1",
                             collector_port = 4739 })

   -- Mock input and output.
   ipfix.input = { v4 = link.new_anonymous(), v6 = link.new_anonymous() }
   ipfix.output = { output = link.new_anonymous() }

   -- Test helper that supplies a packet with some given fields.
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

      local input = is_ipv6 and ipfix.input.v6 or ipfix.input.v4
      link.transmit(input, dg:packet())
      ipfix:push()
   end

   -- Populate with some known flows.
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
   key.sourceIPv4Address = ipv4:pton("192.168.1.1")
   key.destinationIPv4Address = ipv4:pton("192.168.1.25")
   key.protocolIdentifier = IP_PROTO_UDP
   key.sourceTransportPort = 9999
   key.destinationTransportPort = 80

   local result = flows.v4.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.packetDeltaCount == 1)

   -- make sure the count is incremented on the same flow
   test_packet(false, "192.168.1.1", "192.168.1.25", 9999, 80)
   assert(result.value.packetDeltaCount == 2,
          string.format("wrong count: %d", tonumber(result.value.packetDeltaCount)))

   -- check the IPv6 key too
   local key = flows.v6.preallocated_key
   key.sourceIPv6Address = ipv6:pton("2001:4860:4860::8888")
   key.destinationIPv6Address = ipv6:pton("2001:db8::ff00:42:8329")
   key.protocolIdentifier = IP_PROTO_UDP
   key.sourceTransportPort = 53
   key.destinationTransportPort = 57777

   local result = flows.v6.table:lookup_ptr(key)
   assert(result, "key not found")
   assert(result.value.packetDeltaCount == 1)

   -- sanity check
   flows.v4.table:selfcheck()
   flows.v6.table:selfcheck()

   local key = flows.v4.preallocated_key
   key.sourceIPv4Address = ipv4:pton("192.168.1.1")
   key.destinationIPv4Address = ipv4:pton("192.168.1.25")
   key.protocolIdentifier = 17
   key.sourceTransportPort = 9999
   key.destinationTransportPort = 80

   local value = flows.v4.preallocated_value
   value.flowStartMilliseconds = get_timestamp()
   value.flowEndMilliseconds = value.flowStartMilliseconds + 30
   value.packetDeltaCount = 5
   value.octetDeltaCount = 15

   local record = ipfix.export_v4.template.record_t(key, value)
   -- Mock expiry.
   function ipfix.flows.v4:get_expired()
      return { record }
   end

   -- Template message; no data yet.
   assert(link.nreadable(ipfix.output.output) == 1)
   ipfix:push()
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

-- This module implements functions for exporting flow information as
-- IPFIX or Netflow V9 packets to a flow collector.
--
-- See RFC 3954 (https://tools.ietf.org/html/rfc3954)

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local util   = require("apps.flow_export.util")
local lib    = require("core.lib")
local link   = require("core.link")
local dg     = require("lib.protocol.datagram")
local ether  = require("lib.protocol.ethernet")
local ipv4   = require("lib.protocol.ipv4")
local ipv6   = require("lib.protocol.ipv6")
local udp    = require("lib.protocol.udp")
local C      = ffi.C

local htonl, htons = lib.htonl, lib.htons

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

-- various constants
local V9_HEADER_SIZE  = 20
local V10_HEADER_SIZE = 16
local V9_TEMPLATE_ID  = 0
local V10_TEMPLATE_ID = 2

-- initialize a table describing the ids & field sizes for IPFIX fields
local function make_ipfix_element_map()
   local ipfix_elems =
      require("apps.flow_export.ipfix_information_elements_inc")
   local map = {}
   local idx = 1

   while idx <= ipfix_elems:len() do
      local comma = (","):byte()
      local quote = ('"'):byte()
      local newline = ("\n"):byte()
      local function consume_until_char(char)
         local start_idx = idx

         while ipfix_elems:byte(idx) ~= char do
            if ipfix_elems:byte(idx) == quote then
               idx = idx + 1
               while ipfix_elems:byte(idx) ~= quote do
                  idx = idx + 1
               end
            end
            idx = idx + 1
         end
         idx = idx + 1

         return string.sub(ipfix_elems, start_idx, idx - 2)
      end

      local id = consume_until_char(comma)
      local name = consume_until_char(comma)
      local data_type = consume_until_char(comma)
      for i=1,8 do
         consume_until_char(comma)
      end
      consume_until_char(newline)

      map[name] = { id = id, data_type = data_type }
   end

   return map
end

local ipfix_elements = make_ipfix_element_map()

-- Describes the sizes (in octets) of IPFIX IEs
-- TODO: fill in others as needed
local data_size_map =
   { unsigned8 = 1,
     unsigned16 = 2,
     unsigned32 = 4,
     unsigned64 = 8,
     ipv4Address = 4,
     ipv6Address = 16,
     dateTimeMilliseconds = 8 }

-- create a table describing the information needed to create
-- flow templates and data records
local function make_template_info(id, key_fields, record_fields)
   -- the contents of the template records we will send
   -- there is an ID & length for each field
   local length = 2 * (#key_fields + #record_fields)
   local buffer = ffi.new("uint16_t[?]", length)

   -- octets in a data record
   local data_len = 0

   local function process_fields(buffer, fields)
      for idx, name in ipairs(fields) do
         local entry = ipfix_elements[name]
         local size  = assert(data_size_map[entry.data_type])
         data_len = data_len + size
         buffer[2 * (idx - 1)]     = htons(entry.id)
         buffer[2 * (idx - 1) + 1] = htons(size)
      end
   end

   process_fields(buffer, key_fields)
   process_fields(buffer + #key_fields * 2, record_fields)

   return { id = id,
            field_count = #key_fields + #record_fields,
            buffer = buffer,
            buffer_len = length * 2,
            data_len = data_len }
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

Exporter = {}

function Exporter:new(config)
   local o = { -- sequence number to use for flow packets
               sequence_number = 1,
               boot_time = config.boot_time,
               -- version of IPFIX/Netflow (9 or 10)
               version = config.version,
               mtu = config.mtu,
               observation_domain = config.observation_domain,
               exporter_mac = config.exporter_mac,
               exporter_ip = config.exporter_ip,
               collector_mac = config.collector_mac,
               collector_ip = config.collector_ip,
               collector_port = config.collector_port }

   if o.version == 9 then
      o.header_size = V9_HEADER_SIZE
   elseif o.version == 10 then
      o.header_size = V10_HEADER_SIZE
   end

   return setmetatable(o, { __index = self })
end

function Exporter:construct_packet(ptr, len)
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
   local udp_h = udp:new({ src_port = math.random(49152, 65535),
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

local function get_timestamp()
   return C.get_unix_time() * 1000ULL
end

-- Write an IPFIX header into the given buffer
--
-- v9 header is 20 bytes, starting with
--   * version number (09)
--   * count of records
--   * uptime (seconds)
--
-- a v10 header is 16 bytes, starting with
--   * a version number (10)
--   * total length in octets
--
-- both headers end with
--
--   * unix timestamp
--   * sequence number
--   * source ID
function Exporter:write_header(ptr, count, length)
   local uptime = tonumber(get_timestamp() - self.boot_time)

   ffi.cast("uint16_t*", ptr)[0] = htons(self.version)

   if self.version == 9 then
      ffi.cast("uint16_t*", ptr + 2)[0]  = htons(count)
      ffi.cast("uint32_t*", ptr + 4)[0]  = htonl(uptime)
      ffi.cast("uint32_t*", ptr + 8)[0]  = htonl(math.floor(C.get_unix_time()))
      ffi.cast("uint32_t*", ptr + 12)[0] = htonl(self.sequence_number)
      ffi.cast("uint32_t*", ptr + 16)[0] = htonl(self.observation_domain)
   elseif self.version == 10 then
      ffi.cast("uint16_t*", ptr + 2)[0]  = htons(length)
      ffi.cast("uint32_t*", ptr + 4)[0]  = htonl(math.floor(C.get_unix_time()))
      ffi.cast("uint32_t*", ptr + 8)[0]  = htonl(self.sequence_number)
      ffi.cast("uint32_t*", ptr + 12)[0] = htonl(self.observation_domain)
   end

   self.sequence_number = self.sequence_number + 1
end

-- Send template records/option template records to the collector
-- TODO: only handles template records so far
function Exporter:send_template_record(output_link)
   local templates = { template_v4, template_v6 }
   local length = self.header_size

   for _, template in ipairs(templates) do
      -- +8 octets for the flow set header
      length = length + template.buffer_len + 8
   end

   local buffer = ffi.new("uint8_t[?]", length)
   self:write_header(buffer, 2, length)

   -- write the header and then the template record contents for each template
   -- note that the ptr is incrementing by 16 octets but the buffer lengths are
   -- in octets
   local ptr = ffi.cast("uint16_t*", buffer + self.header_size)
   for _, template in ipairs(templates) do
      if self.version == 9 then
         ptr[0] = htons(V9_TEMPLATE_ID)
      elseif self.version == 10 then
         ptr[0] = htons(V10_TEMPLATE_ID)
      end

      ptr[1] = htons(template.buffer_len + 8)
      ptr[2] = htons(template.id)
      ptr[3] = htons(template.field_count)

      ffi.copy(ptr + 4, template.buffer, template.buffer_len)

      ptr = ptr + template.buffer_len / 2 + 4
   end

   local pkt = self:construct_packet(ffi.cast("uint8_t*", buffer), length)

   link.transmit(output_link, pkt)

   if debug then
      util.fe_debug("sent template packet, seq#: %d octets: %d",
                    self.sequence_number - 1, length)
   end
end

-- Helper function to write a 64-bit record field in network-order
-- TODO: don't just assume host is little-endian
local function write64(record, field, ptr, idx)
   local off = ffi.offsetof(record, field)
   local rp  = ffi.cast("uint8_t*", record)
   local fp  = ffi.cast("uint32_t*", rp + off)
   local dst = ffi.cast("uint32_t*", ptr + idx)

   dst[0] = htonl(fp[1])
   dst[1] = htonl(fp[0])
end

-- Given a flow exporter & an array of ctable entries, construct flow
-- record packet(s) and transmit them
function Exporter:export_records(output_link, entries)
   -- length of v9 header + flow set ID/length
   local header_len  = self.header_size + 4
   -- TODO: handle IPv6
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

      -- flow set ID and length
      ffi.cast("uint16_t*", buffer + self.header_size)[0]
         = htons(256)
      ffi.cast("uint16_t*", buffer + self.header_size + 2)[0]
         = htons(length - self.header_size)

      for idx = record_idx, record_idx + num_to_take - 1 do
         local key    = entries[idx].key
         local record = entries[idx].value
         local ptr    =
            buffer + self.header_size + 4 + (record_len * (idx - record_idx))

         if key.is_ipv6 == 0 then
            local field_ptr =
               ffi.cast("uint8_t*", key) + ffi.offsetof(key, "src_ipv4")
            ffi.copy(ptr, field_ptr, 4)
            ffi.copy(ptr + 4, field_ptr + 4, 4)
         else
            local field_ptr =
               ffi.cast("uint8_t*", key) + ffi.offsetof(key, "src_ipv6_1")
            ffi.copy(ptr, field_ptr, 16)
            ffi.copy(ptr + 16, field_ptr + 16, 16)
         end
         ffi.cast("uint8_t*", ptr + 8)[0]  = key.protocol
         ffi.cast("uint16_t*", ptr + 9)[0]  = key.src_port
         ffi.cast("uint16_t*", ptr + 11)[0] = key.dst_port

         write64(record, "start_time", ptr, 13)
         write64(record, "end_time", ptr, 21)
         write64(record, "pkt_count", ptr, 29)
         write64(record, "octet_count", ptr, 37)

         ffi.cast("uint32_t*", ptr + 45)[0] = record.ingress
         ffi.cast("uint32_t*", ptr + 49)[0] = record.egress
         ffi.cast("uint32_t*", ptr + 53)[0] = record.src_peer_as
         ffi.cast("uint32_t*", ptr + 57)[0] = record.dst_peer_as
         ffi.cast("uint8_t*", ptr + 61)[0]  = record.tos
         -- in V9 this is 1 octet, in IPFIX it's 2 octets
         ffi.cast("uint8_t*", ptr + 62)[0]  = record.tcp_control
      end

      local pkt = self:construct_packet(buffer, length)

      link.transmit(output_link, pkt)

      record_idx = record_idx + num_to_take

      if debug then
         util.fe_debug("sent data packet, seq#: %d octets: %d",
                       self.sequence_number - 1, length)
      end
   end
end

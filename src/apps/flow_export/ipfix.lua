-- This module implements functions for exporting flow information as
-- IPFIX or Netflow V9 packets to a flow collector.
--
-- See RFC 3954 (https://tools.ietf.org/html/rfc3954)

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local lib    = require("core.lib")
local link   = require("core.link")
local dg     = require("lib.protocol.datagram")
local ether  = require("lib.protocol.ethernet")
local ipv4   = require("lib.protocol.ipv4")
local ipv6   = require("lib.protocol.ipv6")
local udp    = require("lib.protocol.udp")
local C      = ffi.C

local htonl, htons = lib.htonl, lib.htons

-- Constants for field types
local IN_BYTES                     = 1
local IN_PKTS                      = 2
local FLOWS                        = 3
local PROTOCOL                     = 4
local TOS                          = 5
local TCP_FLAGS                    = 6
local L4_SRC_PORT                  = 7
local IPV4_SRC_ADDR                = 8
local SRC_MASK                     = 9
local INPUT_SNMP                   = 10
local L4_DST_PORT                  = 11
local IPV4_DST_ADDR                = 12
local DST_MASK                     = 13
local OUTPUT_SNMP                  = 14
local IPV4_NEXT_HOP                = 15
local SRC_AS                       = 16
local DST_AS                       = 17
local BGP_IPV4_NEXT_HOP            = 18
local MUL_DST_PKTS                 = 19
local MUL_DST_BYTES                = 20
local LAST_SWITCHED                = 21
local FIRST_SWITCHED               = 22
local OUT_BYTES                    = 23
local OUT_PKTS                     = 24
local IPV6_SRC_ADDR                = 27
local IPV6_DST_ADDR                = 28
local IPV6_SRC_MASK                = 29
local IPV6_DST_MASK                = 30
local IPV6_FLOW_LABEL              = 31
local ICMP_TYPE                    = 32
local MUL_IGMP_TYPE                = 33
local SAMPLING_INTERVAL            = 34
local SAMPLING_ALGORITHM           = 35
local FLOW_ACTIVE_TIMEOUT          = 36
local FLOW_INACTIVE_TIMEOUT        = 37
local ENGINE_TYPE                  = 38
local ENGINE_ID                    = 39
local TOTAL_BYTES_EXP              = 40
local TOTAL_PKTS_EXP               = 41
local TOTAL_FLOWS_EXP              = 42
local MPLS_TOP_LABEL_TYPE          = 46
local MPLS_TOP_LABEL_IP_ADDR       = 47
local FLOW_SAMPLER_ID              = 48
local FLOW_SAMPLER_MODE            = 49
local FLOW_SAMPLER_RANDOM_INTERVAL = 50
local DST_TOS                      = 55
local SRC_MAC                      = 56
local DST_MAC                      = 57
local SRC_VLAN                     = 58
local DST_VLAN                     = 59
local IP_PROTOCOL_VERSION          = 60
local DIRECTION                    = 61
local IPV6_NEXT_HOP                = 62
local BGP_IPV6_NEXT_HOP            = 63
local IPV6_OPTION_HEADERS          = 64
local MPLS_LABEL_1                 = 70
local MPLS_LABEL_2                 = 71
local MPLS_LABEL_3                 = 72
local MPLS_LABEL_4                 = 73
local MPLS_LABEL_5                 = 74
local MPLS_LABEL_6                 = 75
local MPLS_LABEL_7                 = 76
local MPLS_LABEL_8                 = 77
local MPLS_LABEL_9                 = 78
local MPLS_LABEL_10                = 79
-- end of Netflow V9 field types, the rest are IPFIX
local bgpNextAdjacentAsNumber      = 128
local bgpPrevAdjacentAsNumber      = 129
local flowStartMilliseconds        = 152
local flowEndMilliseconds          = 153

local sequence_number = 1

local function construct_packet(exporter, ptr, len)
   local dgram  = dg:new()

   -- TODO: support IPv6, also obtain the MAC of the dst via ARP
   --       and use the correct src MAC (this is ok for use on the
   --       loopback device for now).
   local eth_h = ether:new({ src = ether:pton(exporter.exporter_mac),
                             dst = ether:pton(exporter.collector_mac),
                             type = 0x0800 })
   local ip_h  = ipv4:new({ src = ipv4:pton(exporter.exporter_ip),
                            dst = ipv4:pton(exporter.collector_ip),
                            protocol = 17,
                            ttl = 64,
                            flags = 0x02 })
   local udp_h = udp:new({ src_port = math.random(49152, 65535),
                           dst_port = exporter.collector_port })

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
   return C.get_time_ns() / 1000000ULL
end

-- Write an IPFIX header into the given buffer
--
-- v9 header is 20 bytes, consisting of
--   * version number (09)
--   * count
--   * uptime (seconds)
--   * unix timestamp
--   * sequence number
--   * source ID
local function write_header(ptr, count, boot_time)
   local uptime = tonumber(get_timestamp() - boot_time)

   ffi.cast("uint16_t*", ptr)[0]      = htons(9)
   ffi.cast("uint16_t*", ptr + 2)[0]  = htons(count)
   ffi.cast("uint32_t*", ptr + 4)[0]  = htonl(uptime)
   ffi.cast("uint32_t*", ptr + 8)[0]  = htonl(math.floor(C.get_unix_time()))
   ffi.cast("uint32_t*", ptr + 12)[0] = htonl(sequence_number)
   -- TODO: make source ID configurable
   ffi.cast("uint32_t*", ptr + 16)[0] = htonl(1)

   sequence_number = sequence_number + 1
end

-- Send template records/option template records to the collector
-- TODO: the RFC requires the exporter to periodically resend these
--       in order to refresh the collector (& should be configurable)
function send_template_record(exporter)
   local buffer = ffi.new("uint8_t[88]")
   write_header(buffer, 1, exporter.boot_time)

   local template = ffi.cast("uint16_t*", buffer + 20)
   local length   = 68

   -- flow-set id = 0
   template[0] = 0
   -- length of flowset in octets
   template[1] = htons(length)
   -- template id, starts at 256
   template[2] = htons(256)
   -- field count
   template[3] = htons(15)

   -- flow record fields, hardcoded for now
   template[4]  = htons(IPV4_SRC_ADDR)
   template[5]  = htons(4)
   template[6]  = htons(IPV4_DST_ADDR)
   template[7]  = htons(4)
   template[8]  = htons(L4_SRC_PORT)
   template[9]  = htons(2)
   template[10] = htons(L4_DST_PORT)
   template[11] = htons(2)
   template[12] = htons(PROTOCOL)
   template[13] = htons(1)
   template[14] = htons(flowStartMilliseconds)
   template[15] = htons(8)
   template[16] = htons(flowEndMilliseconds)
   template[17] = htons(8)
   template[18] = htons(IN_PKTS)
   template[19] = htons(8)
   template[20] = htons(IN_BYTES)
   template[21] = htons(8)
   template[22] = htons(TOS)
   template[23] = htons(1)
   template[24] = htons(TCP_FLAGS)
   template[25] = htons(1)
   template[26] = htons(INPUT_SNMP)
   template[27] = htons(4)
   template[28] = htons(OUTPUT_SNMP)
   template[29] = htons(4)
   template[30] = htons(bgpPrevAdjacentAsNumber)
   template[31] = htons(4)
   template[32] = htons(bgpNextAdjacentAsNumber)
   template[33] = htons(4)

   local pkt = construct_packet(exporter, ffi.cast("uint8_t*", buffer), 88)

   link.transmit(exporter.output.output, pkt)
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

-- Given a flow exporter & an array of records, construct flow record
-- packet(s) and transmit them
function export_records(exporter, records)
   local mtu         = exporter.mtu_to_collector
   -- length of v9 header + flow set ID/length
   local header_len  = 24
   local record_len  = 63
   -- 4 is the max padding, so account for that conservatively to
   -- figure out how many records we can fit in the MTU
   local max_records = math.floor((mtu - header_len - 4 - 28) / record_len)

   local record_idx  = 1
   while record_idx <= #records do
      local num_to_take = math.min(max_records, #records - record_idx + 1)
      local data_len    = 24 + (record_len * num_to_take)
      local padding     = 4 - (data_len % 4)
      local length      = data_len + padding
      local buffer      = ffi.new("uint8_t[?]", length)
      write_header(buffer, num_to_take, exporter.boot_time)

      -- flow set ID and length
      ffi.cast("uint16_t*", buffer + 20)[0] = htons(256)
      ffi.cast("uint16_t*", buffer + 22)[0] = htons(length - 20)

      for idx = record_idx, record_idx + num_to_take - 1 do
         local record = records[idx]
         local ptr    = buffer + 24 + (63 * (idx - record_idx))

         ffi.copy(ptr, record.key.src_ip, 4)
         ffi.copy(ptr + 4, record.key.dst_ip, 4)
         ffi.cast("uint16_t*", ptr + 8)[0]  = record.key.src_port
         ffi.cast("uint16_t*", ptr + 10)[0] = record.key.dst_port
         ffi.cast("uint8_t*", ptr + 12)[0]  = record.key.protocol

         write64(record, "start_time", ptr, 13)
         write64(record, "end_time", ptr, 21)
         write64(record, "pkt_count", ptr, 29)
         write64(record, "octet_count", ptr, 37)

         ffi.cast("uint8_t*", ptr + 45)[0]  = record.tos
         -- in V9 this is 1 octet, in IPFIX it's 2 octets
         ffi.cast("uint8_t*", ptr + 46)[0]  = record.tcp_control
         ffi.cast("uint32_t*", ptr + 47)[0] = record.ingress
         ffi.cast("uint32_t*", ptr + 51)[0] = record.egress
         ffi.cast("uint32_t*", ptr + 55)[0] = record.src_peer_as
         ffi.cast("uint32_t*", ptr + 59)[0] = record.dst_peer_as
      end

      local pkt = construct_packet(exporter, buffer, length)

      link.transmit(exporter.output.output, pkt)

      record_idx = record_idx + num_to_take
   end
end
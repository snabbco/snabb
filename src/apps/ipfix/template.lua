-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local bit      = require("bit")
local ffi      = require("ffi")
local pf       = require("pf")
local consts   = require("apps.lwaftr.constants")
local lib      = require("core.lib")
local counter  = require("core.counter")
local ethernet = require("lib.protocol.ethernet")
local ipv4     = require("lib.protocol.ipv4")
local ipv6     = require("lib.protocol.ipv6")
local metadata = require("apps.rss.metadata")
local strings  = require("apps.ipfix.strings")
local dns      = require("apps.ipfix.dns")
local S        = require("syscall")

local ntohs  = lib.ntohs
local htonl, htons = lib.htonl, lib.htons
local function htonq(v) return bit.bswap(v + 0ULL) end
local metadata_get = metadata.get
local ether_header_ptr_t = metadata.ether_header_ptr_t

local function ptr_to(ctype) return ffi.typeof('$*', ctype) end

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local IP_PROTO_ICMP  = 1
local IP_PROTO_TCP  = 6
local IP_PROTO_UDP  = 17
local IP_PROTO_ICMP6  = 58
local IP_PROTO_SCTP = 132
-- A protocol's predicate whether it is a transport protocol is
-- encoded in this table to implement a check as a single table lookup
-- instead of a conditional with logical operators that can lead to
-- multiple levels of side-traces
local transport_proto_p = {
   [IP_PROTO_TCP] = true,
   [IP_PROTO_UDP] = true,
   [IP_PROTO_SCTP] = true
}

-- These constants are taken from the lwaftr constants module, which
-- is maybe a bad dependency but sharing code is good
-- TODO: move constants somewhere else? lib?
local o_ipv4_dscp_and_ecn    = consts.o_ipv4_dscp_and_ecn
local o_ipv4_proto           = consts.o_ipv4_proto
local o_ipv4_src_addr        = consts.o_ipv4_src_addr
local o_ipv4_dst_addr        = consts.o_ipv4_dst_addr
local o_icmpv4_msg_type      = consts.o_icmpv4_msg_type
local o_icmpv4_msg_code      = consts.o_icmpv4_msg_code
local o_ipv6_src_addr        = consts.o_ipv6_src_addr
local o_ipv6_dst_addr        = consts.o_ipv6_dst_addr
local o_icmpv6_msg_type      = consts.o_icmpv6_msg_type
local o_icmpv6_msg_code      = consts.o_icmpv6_msg_code

local function string_parser(str)
   local idx = 1
   local quote = ('"'):byte()
   local ret = {}
   function ret.consume_upto(char)
      local start_idx = idx
      local byte = char:byte()
      while str:byte(idx) ~= byte and idx <= str:len() do
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
local function make_ipfix_element_map(names)
   local map = {}
   for _, name in ipairs(names) do
      local elems = require("apps.ipfix."..name.."_inc")
      local parser = string_parser(elems)
      while not parser.is_done() do
         local id = parser.consume_upto(",")
         local name = parser.consume_upto(",")
         local data_type = parser.consume_upto(",")
         for i=1,8 do parser.consume_upto(",") end
         parser.consume_upto("\n")
         map[name] = { id = id, data_type = data_type }
         local pen, id = id:match("(%d+):(%d+)")
         if pen then
            -- Private Enterprise Number
            map[name].id = tonumber(bit.bor(id, 0x8000))
            map[name].pen = pen
         end
      end
   end
   return map
end

local ipfix_elements =
   make_ipfix_element_map({ 'ipfix_information_elements',
                            'ipfix_information_elements_local' })

local swap_fn_env = { htons = htons, htonl = htonl, htonq = htonq }

local aggregate_info = {
   v4 = {
      key_type = ffi.typeof([[
         struct {
            uint32_t addr;
         } __attribute__((packed))
      ]]),
      mk_fns = function(plen_v4, plen_v6)
         local plen = plen_v4
         local mask = 0
         if plen > 0 then
            mask = bit.bnot(bit.lshift(1, 32-plen) - 1)
         end
         return
            function (flow_key, rate_key)
               rate_key.addr = htonl(
                  bit.band(
                     htonl(ffi.cast("uint32_t *",
                                    flow_key.sourceIPv4Address)[0]),
                     mask))
            end,
         function(rate_key)
            return ipv4:ntop(ffi.cast("uint8_t*", rate_key)).."/"..plen
         end
      end
   },
   v6 = {
      key_type = ffi.typeof([[
         struct {
            uint64_t addr[2];
         } __attribute__((packed))
      ]]),
      mk_fns = function(plen_v4, plen_v6)
         local plen = plen_v6

         local function plen2mask(plen)
            local mask = 0ULL
            if plen > 0 then
               mask = bit.bnot(bit.lshift(1ULL, 64-plen) - 1)
            end
            return mask
         end

         mask_low = plen2mask(plen > 64 and plen - 64 or 0)
         mask_high = plen2mask(plen >= 64 and 64 or plen)
         return
            function (flow_key, rate_key)
               local addr = ffi.cast("uint64_t *", flow_key.sourceIPv6Address)
               rate_key.addr[0] = htonq(
                  bit.band(
                     htonq(ffi.cast("uint64_t *",
                                    flow_key.sourceIPv6Address)[0]),
                     mask_high))
               rate_key.addr[1] = htonq(
                  bit.band(
                     htonq(ffi.cast("uint64_t *",
                                    flow_key.sourceIPv6Address)[1]),
                     mask_low))
            end,
         function(rate_key)
            return ipv6:ntop(ffi.cast("uint8_t*", rate_key)).."/"..plen
         end
      end
   }
}

-- Create a table describing the information needed to create
-- flow templates and data records.
function make_template_info(spec)
   -- Representations of IPFIX IEs.
   local ctypes =
      { unsigned8 = 'uint8_t', unsigned16 = 'uint16_t',
        unsigned32 = 'uint32_t', unsigned64 = 'uint64_t',
        string = 'uint8_t[?]', octetArray = 'uint8_t[?]',
        ipv4Address = 'uint8_t[4]', ipv6Address = 'uint8_t[16]',
        macAddress = 'uint8_t[6]', dateTimeMilliseconds = 'uint64_t' }
   local bswap = { uint16_t='htons', uint32_t='htonl', uint64_t='htonq' }
   -- The contents of the template records we will send. There is an
   -- ID & length (2 bytes each) for each field as well as possibly a
   -- PEN (4 bytes).  We pre-allocate a buffer of the maximum possible
   -- size.
   local length = 4 * (#spec.keys + #spec.values)
   local buffer = ffi.new("uint16_t[?]", length)

   -- octets in a data record
   local data_len = 0
   local swap_fn = {}

   local function process_fields(buffer, fields, struct_def, types, swap_tmpl)
      local idx = 0
      for _, name in ipairs(fields) do
         local _name, size = name:match("(%w+)=(%d+)")
         if _name then
            name = _name
         end
         local entry = ipfix_elements[name]
         local ctype = assert(ctypes[entry.data_type],
                              name..': unimplemented data type '
                                 ..entry.data_type)
         if size then
            size = tonumber(size)
            assert(entry.data_type == 'string' or entry.data_type == 'octetArray',
                   name..': length parameter given for fixed-length data type '
                      ..entry.data_type)
            ctype = ctype:gsub('%?', size)
         else
            assert(entry.data_type ~= 'string' and entry.data_type ~= 'octetArray',
                   name..': length parameter required for data type '
                      ..entry.data_type)
         end
         data_len = data_len + ffi.sizeof(ctype)
         buffer[idx]     = htons(entry.id)
         buffer[idx + 1] = htons(ffi.sizeof(ctype))
         idx = idx + 2
         if entry.pen then
            ffi.cast("uint32_t*", buffer + idx)[0] = htonl(entry.pen)
            idx = idx + 2
         end
         table.insert(struct_def, '$ '..name..';')
         table.insert(types, ffi.typeof(ctype))
         if bswap[ctype] then
            table.insert(swap_fn, swap_tmpl:format(name, bswap[ctype], name))
         end
      end
      return idx
   end

   table.insert(swap_fn, 'return function(o)')
   local key_struct_def = { 'struct {' }
   local key_types = {}
   local length = process_fields(buffer, spec.keys, key_struct_def, key_types,
                                 'o.key.%s = %s(o.key.%s)')
   table.insert(key_struct_def, '} __attribute__((packed))')
   local value_struct_def = { 'struct {' }
   local value_types = {}
   length = length + process_fields(buffer + length, spec.values, value_struct_def,
                                    value_types, 'o.value.%s = %s(o.value.%s)')
   if spec.state_t then
      table.insert(value_struct_def, "$ state;")
      table.insert(value_types, spec.state_t)
   end
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

   -- State data, if present, is part of the value but must not be
   -- included in export records.
   assert(ffi.sizeof(record_t) - ffi.sizeof(spec.state_t or 'char [0]') == data_len)

   local counters_names = {}
   if spec.counters then
      for name, _ in pairs(spec.counters) do
         table.insert(counters_names, name)
      end
   end
   return { id = spec.id,
            field_count = #spec.keys + #spec.values,
            buffer = buffer,
            buffer_len = length * 2,
            data_len = data_len,
            key_t = key_t,
            value_t = value_t,
            record_t = record_t,
            record_ptr_t = ptr_to(record_t),
            swap_fn = gen_swap_fn(),
            match = pf.compile_filter(spec.filter),
            counters = spec.counters,
            counters_names = counters_names,
            extract = spec.extract,
            accumulate = spec.accumulate,
            require_maps = spec.require_maps or {},
            aggregate_info = aggregate_info[spec.aggregation_type]
          }
end

local uint16_ptr_t = ffi.typeof('uint16_t *')

local function get_ipv4_tos(l3) return l3[o_ipv4_dscp_and_ecn] end
local function get_ipv6_tc(l3)
   -- Version, traffic class and first part of flow label
   local v_tc_fl = ntohs(ffi.cast(uint16_ptr_t, l3)[0])
   -- Traffic class is bits 4-11 (MSB to LSB)
   return (bit.rshift(bit.band(0x0FF0, v_tc_fl), 4))
end

local function get_icmp_typecode(l4)
   return ntohs(ffi.cast(uint16_ptr_t, l4+o_icmpv4_msg_type)[0])
end

local function get_ipv4_src_addr_ptr(l3) return l3 + o_ipv4_src_addr end
local function get_ipv4_dst_addr_ptr(l3) return l3 + o_ipv4_dst_addr end

local function get_ipv6_src_addr_ptr(l3) return l3 + o_ipv6_src_addr end
local function get_ipv6_dst_addr_ptr(l3) return l3 + o_ipv6_dst_addr end

local function read_ipv4_src_address(l3, dst)
   ffi.copy(dst, get_ipv4_src_addr_ptr(l3), 4)
end
local function read_ipv4_dst_address(l3, dst)
   ffi.copy(dst, get_ipv4_dst_addr_ptr(l3), 4)
end
local function read_ipv6_src_address(l3, dst)
   ffi.copy(dst, get_ipv6_src_addr_ptr(l3), 16)
end
local function read_ipv6_dst_address(l3, dst)
   ffi.copy(dst, get_ipv6_dst_addr_ptr(l3), 16)
end

local function get_transport_src_port(l4)
   return ntohs(ffi.cast(uint16_ptr_t, l4)[0])
end
local function get_transport_dst_port(l4)
   return ntohs(ffi.cast(uint16_ptr_t, l4)[1])
end

local function get_tcp_flags(l4)
   return ntohs(ffi.cast(uint16_ptr_t, l4)[6])
end

-- Address-family dependent extractors

local function extract_v4_addr(l3, entry)
   read_ipv4_src_address(l3, entry.key.sourceIPv4Address)
   read_ipv4_dst_address(l3, entry.key.destinationIPv4Address)
end

local function extract_v6_addr(l3, entry)
   read_ipv6_src_address(l3, entry.key.sourceIPv6Address)
   read_ipv6_dst_address(l3, entry.key.destinationIPv6Address)
end

-- Address-family independent extract/accumulate functions

local function extract_transport_key(l4, entry)
   entry.key.sourceTransportPort = get_transport_src_port(l4)
   entry.key.destinationTransportPort = get_transport_dst_port(l4)
end

local function extract_tcp_flags(l4, entry)
   -- Mask off data offset bits
   entry.value.tcpControlBits = bit.band(0xFFF, get_tcp_flags(l4))
end

local function accumulate_tcp_flags(dst, new)
   dst.value.tcpControlBits = bit.bor(dst.value.tcpControlBits,
                                      new.value.tcpControlBits)
end

local function extract_tcp_flags_reduced(l4, entry)
   entry.value.tcpControlBitsReduced = bit.band(0xFF, get_tcp_flags(l4))
end

local function accumulate_tcp_flags_reduced(dst, new)
   dst.value.tcpControlBitsReduced =
      bit.bor(dst.value.tcpControlBitsReduced,
              new.value.tcpControlBitsReduced)
end

-- Clear key and value, extract the 3-tuple, fill in flow start/end
-- times and packet/octet counters.  This is the bare minimum any
-- template will need.
local function extract_3_tuple(pkt, timestamp, entry, md, extract_addr_fn)
   ffi.fill(entry.key, ffi.sizeof(entry.key))
   ffi.fill(entry.value, ffi.sizeof(entry.value))

   extract_addr_fn(md.l3, entry)
   entry.key.protocolIdentifier = md.proto

   entry.value.flowStartMilliseconds = timestamp
   entry.value.flowEndMilliseconds = timestamp
   entry.value.packetDeltaCount = 1
   entry.value.octetDeltaCount = md.total_length
end

local function extract_5_tuple(pkt, timestamp, entry, md, extract_addr_fn)
   extract_3_tuple(pkt, timestamp, entry, md, extract_addr_fn)
   if transport_proto_p[md.proto] and md.frag_offset == 0 then
      extract_transport_key(md.l4, entry)
   end
end

local function accumulate_generic(dst, new)
   -- If dst is a flow entry which has been cleared after an active
   -- timeout and this is the first packet received since then,
   -- flowStartMilliseconds is the time at which the flow was last
   -- exported rather than the time at which the flow actually started
   -- in the new active window.
   if dst.value.packetDeltaCount == 0 then
      dst.value.flowStartMilliseconds = new.value.flowStartMilliseconds
   end
   dst.value.flowEndMilliseconds = new.value.flowEndMilliseconds
   dst.value.packetDeltaCount = dst.value.packetDeltaCount + 1
   dst.value.octetDeltaCount =
      dst.value.octetDeltaCount + new.value.octetDeltaCount
end

local function v4_extract (self, pkt, timestamp, entry)
   local md = metadata_get(pkt)
   extract_5_tuple(pkt, timestamp, entry, md, extract_v4_addr)
   if md.proto == IP_PROTO_TCP and md.frag_offset == 0 then
      extract_tcp_flags_reduced(md.l4, entry)
   end
end

local function v6_extract (self, pkt, timestamp, entry)
   local md = metadata_get(pkt)
   extract_5_tuple(pkt, timestamp, entry, md, extract_v6_addr)
   if md.proto == IP_PROTO_TCP and md.frag_offset == 0 then
      extract_tcp_flags_reduced(md.l4, entry)
   end
end

--- Helper functions for HTTP templates

-- We want to be able to find a "Host:" header even if it is not in
-- the same TCP segment as the GET request, which requires to keep
-- state.
local HTTP_state_t = ffi.typeof([[
   struct {
      uint8_t have_GET;
      uint8_t have_host;
      uint8_t examined;
   } __attribute__((packed))
]])
-- The number of TCP segments to scan for the first GET request
-- (including the SYN segment, which is skipped). Most requests are
-- found in the first non-handshake packet (segment #3 from the
-- client). Empirical evidence shows a strong peak there with a long
-- tail.  A cutoff of 10 is expected to find at least 80% of the GET
-- requests.
local HTTP_scan_threshold = 10
-- HTTP-specific statistics counters
local function HTTP_counters()
   return {
      HTTP_flows_examined = 0,
      HTTP_GET_matches = 0,
      HTTP_host_matches = 0
   }
end

local HTTP_strings = strings.strings_to_buf({
      GET = 'GET ',
      Host = 'Host:'
})

local HTTP_ct = strings.ct_t()

local function HTTP_accumulate(self, dst, new, pkt)
   local md = metadata_get(pkt)
   if ((dst.value.packetDeltaCount >= HTTP_scan_threshold or
           -- TCP SYN
        bit.band(new.value.tcpControlBitsReduced, 0x02) == 0x02)) then
      return
   end
   local state = dst.value.state
   if state.examined == 0 then
      self.counters.HTTP_flows_examined =
         self.counters.HTTP_flows_examined + 1
      state.examined = 1
   end
   strings.ct_init(HTTP_ct, pkt.data, pkt.length, md.l4 - pkt.data)
   if (state.have_GET == 0 and
       strings.search(HTTP_strings.GET, HTTP_ct, true)) then
      ffi.copy(dst.value.httpRequestMethod, 'GET')
      state.have_GET = 1
      strings.skip_space(HTTP_ct)
      local start = strings.ct_at(HTTP_ct)
      local _, length = strings.upto_space_or_cr(HTTP_ct)
      length = math.min(length, ffi.sizeof(dst.value.httpRequestTarget) - 1)
      ffi.copy(dst.value.httpRequestTarget, start, length)
      self.counters.HTTP_GET_matches = self.counters.HTTP_GET_matches + 1
   end
   if (state.have_GET == 1 and state.have_host == 0 and
       strings.search(HTTP_strings.Host, HTTP_ct, true)) then
      state.have_host = 1
      strings.skip_space(HTTP_ct)
      local start = strings.ct_at(HTTP_ct)
      local _, length = strings.upto_space_or_cr(HTTP_ct)
      length = math.min(length, ffi.sizeof(dst.value.httpRequestHost) - 1)
      ffi.copy(dst.value.httpRequestHost, start, length)
      self.counters.HTTP_host_matches = self.counters.HTTP_host_matches + 1
   end
end

local function DNS_extract(self, pkt, timestamp, entry, extract_addr_fn)
   local md = metadata_get(pkt)
   extract_5_tuple(pkt, timestamp, entry, md, extract_addr_fn)
   if md.length_delta == 0 and md.frag_offset == 0 then
      local dns_hdr = md.l4 + 8
      local msg_size = pkt.data + pkt.length - dns_hdr
      dns.extract(dns_hdr, msg_size, entry)
   end
end

local function DNS_accumulate(self, dst, new)
   accumulate_generic(dst, new)
end

local function can_log(logger)
   return logger and logger:can_log()
end

local function extended_extract(self, pkt, md, timestamp, entry, extract_addr_fn)
   extract_5_tuple(pkt, timestamp, entry, md, extract_addr_fn)
   local eth_hdr = ffi.cast(ether_header_ptr_t, pkt.data)

   ffi.copy(entry.value.sourceMacAddress, eth_hdr.shost, 6)
   ffi.copy(entry.value.postDestinationMacAddress, eth_hdr.dhost, 6)
   local mac_to_as = self.maps.mac_to_as
   local result = mac_to_as.map:lookup_ptr(eth_hdr.shost)
   if result then
      entry.value.bgpPrevAdjacentAsNumber = result.value
   elseif can_log(mac_to_as.logger) then
      mac_to_as.logger:log("unknown source MAC "
                              ..ethernet:ntop(eth_hdr.shost))
   end
   if not ethernet:is_mcast(eth_hdr.dhost) then
      local result = mac_to_as.map:lookup_ptr(eth_hdr.dhost)
      if result then
         entry.value.bgpNextAdjacentAsNumber = result.value
      elseif can_log(mac_to_as.logger) then
         mac_to_as.logger:log("unknown destination MAC "
                                 ..ethernet:ntop(eth_hdr.dhost))
      end
   end

   local vlan = md.vlan
   entry.value.vlanId = vlan
   if vlan ~= 0 then
      local vlan_to_ifindex = self.maps.vlan_to_ifindex
      local result = vlan_to_ifindex.map[vlan]
      if result then
         entry.value.ingressInterface = result.ingress
         entry.value.egressInterface = result.egress
      elseif can_log(vlan_to_ifindex.logger) then
         vlan_to_ifindex.logger:log("unknown vlan "..vlan)
      end
   end

   if md.proto == IP_PROTO_TCP and md.frag_offset == 0 then
      extract_tcp_flags_reduced(md.l4, entry)
   end
end

local asn = ffi.new([[
   union {
     char     array[4];
     uint32_t number;
   }
]])
local function v4_extended_extract (self, pkt, timestamp, entry)
   local md = metadata_get(pkt)
   extended_extract(self, pkt, md, timestamp, entry, extract_v4_addr)

   local pfx_to_as = self.maps.pfx4_to_as
   local asn = pfx_to_as.map:search_bytes(entry.key.sourceIPv4Address)
   if asn then
      entry.value.bgpSourceAsNumber = asn
   elseif can_log(pfx_to_as.logger) then
      pfx_to_as.logger:log("missing AS for source "
                              ..ipv4:ntop(entry.key.sourceIPv4Address))
   end
   local asn = pfx_to_as.map:search_bytes(entry.key.destinationIPv4Address)
   if asn then
      entry.value.bgpDestinationAsNumber = asn
   elseif can_log(pfx_to_as.logger) then
      pfx_to_as.logger:log("missing AS for destination "
                              ..ipv4:ntop(entry.key.destinationIPv4Address))
   end

   entry.value.ipClassOfService = get_ipv4_tos(md.l3)
   if md.proto == IP_PROTO_ICMP and md.frag_offset == 0 then
      entry.value.icmpTypeCodeIPv4 = get_icmp_typecode(md.l4)
   end
end

local function v4_extended_accumulate (self, dst, new)
   accumulate_generic(dst, new)
   if dst.key.protocolIdentifier == IP_PROTO_TCP then
      accumulate_tcp_flags_reduced(dst, new)
   end
end

local function v6_extended_extract (self, pkt, timestamp, entry)
   local md = metadata_get(pkt)
   extended_extract(self, pkt, md, timestamp, entry, extract_v6_addr)

   local pfx_to_as = self.maps.pfx6_to_as
   local asn = pfx_to_as.map:search_bytes(entry.key.sourceIPv6Address)
   if asn then
      entry.value.bgpSourceAsNumber = asn
   elseif can_log(pfx_to_as.logger) then
      pfx_to_as.logger:log("missing AS for source "
                              ..ipv6:ntop(entry.key.sourceIPv6Address))
   end
   local asn = pfx_to_as.map:search_bytes(entry.key.destinationIPv6Address)
   if asn then
      entry.value.bgpDestinationAsNumber = asn
   elseif can_log(pfx_to_as.logger) then
      pfx_to_as.logger:log("missing AS for destination "
                              ..ipv6:ntop(entry.key.destinationIPv6Address))
   end

   entry.value.ipClassOfService = get_ipv6_tc(md.l3)
   if md.proto == IP_PROTO_ICMP6 and md.frag_offset == 0 then
      entry.value.icmpTypeCodeIPv6 = get_icmp_typecode(md.l4)
         end
end

local function v6_extended_accumulate (self, dst, new)
   accumulate_generic(dst, new)
   if dst.key.protocolIdentifier == IP_PROTO_TCP then
      accumulate_tcp_flags_reduced(dst, new)
   end
end

templates = {
   v4 = {
      id     = 256,
      filter = "ip",
      aggregation_type = 'v4',
      keys   = { "sourceIPv4Address",
                 "destinationIPv4Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount",
                 "tcpControlBitsReduced" },
      extract = v4_extract,
      accumulate = function (self, dst, new)
         accumulate_generic(dst, new)
         if dst.key.protocolIdentifier == IP_PROTO_TCP then
            accumulate_tcp_flags_reduced(dst, new)
         end
      end,
      tostring = function (entry)
         local ipv4   = require("lib.protocol.ipv4")
         local key = entry.key
         local protos =
            { [IP_PROTO_TCP]='TCP', [IP_PROTO_UDP]='UDP', [IP_PROTO_SCTP]='SCTP' }
         return string.format(
            "%s (%d) -> %s (%d) [%s]",
            ipv4:ntop(key.sourceIPv4Address), key.sourceTransportPort,
            ipv4:ntop(key.destinationIPv4Address), key.destinationTransportPort,
            protos[key.protocolIdentifier] or tostring(key.protocolIdentifier))
      end
   },
   v4_HTTP = {
      id     = 257,
      filter = "ip and tcp dst port 80",
      aggregation_type = 'v4',
      keys   = { "sourceIPv4Address",
                 "destinationIPv4Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount",
                 "tcpControlBitsReduced",
                 "httpRequestMethod=8",
                 "httpRequestHost=32",
                 "httpRequestTarget=64" },
      state_t = HTTP_state_t,
      counters = HTTP_counters(),
      extract = v4_extract,
      accumulate = function (self, dst, new, pkt)
         accumulate_generic(dst, new)
         accumulate_tcp_flags_reduced(dst, new)
         HTTP_accumulate(self, dst, new, pkt)
      end
   },
   v4_DNS = {
      id     = 258,
      filter = "ip and udp port 53",
      aggregation_type = 'v4',
      keys   = { "sourceIPv4Address",
                 "destinationIPv4Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort",
                 "dnsFlagsCodes",
                 "dnsQuestionCount",
                 "dnsAnswerCount",
                 "dnsQuestionName=64",
                 "dnsQuestionType",
                 "dnsQuestionClass",
                 "dnsAnswerName=64",
                 "dnsAnswerType",
                 "dnsAnswerClass",
                 "dnsAnswerTtl",
                 "dnsAnswerRdata=64",
                 "dnsAnswerRdataLen" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount" },
      extract = function (self, pkt, timestamp, entry)
         DNS_extract(self, pkt, timestamp, entry, extract_v4_addr)
      end,
      accumulate = DNS_accumulate
   },
   v4_extended = {
      id     = 1256,
      filter = "ip",
      aggregation_type = 'v4',
      keys   = { "sourceIPv4Address",
                 "destinationIPv4Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount",
                 "sourceMacAddress",
                 -- This is destinationMacAddress per NetFlowV9
                 "postDestinationMacAddress",
                 "vlanId",
                 "ipClassOfService",
                 "bgpSourceAsNumber",
                 "bgpDestinationAsNumber",
                 "bgpPrevAdjacentAsNumber",
                 "bgpNextAdjacentAsNumber",
                 "tcpControlBitsReduced",
                 "icmpTypeCodeIPv4",
                 "ingressInterface",
                 "egressInterface" },
      require_maps = { 'mac_to_as', 'vlan_to_ifindex', 'pfx4_to_as' },
      extract = v4_extended_extract,
      accumulate = v4_extended_accumulate
   },
   v6 = {
      id     = 512,
      filter = "ip6",
      aggregation_type = 'v6',
      keys   = { "sourceIPv6Address",
                 "destinationIPv6Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount",
                 "tcpControlBitsReduced" },
      extract = v6_extract,
      accumulate = function (self, dst, new)
         accumulate_generic(dst, new)
         if dst.key.protocolIdentifier == IP_PROTO_TCP then
            accumulate_tcp_flags_reduced(dst, new)
         end
      end,
      tostring = function (entry)
         local ipv6 = require("lib.protocol.ipv6")
         local key = entry.key
         local protos =
            { [IP_PROTO_TCP]='TCP', [IP_PROTO_UDP]='UDP', [IP_PROTO_SCTP]='SCTP' }
         return string.format(
            "%s (%d) -> %s (%d) [%s]",
            ipv6:ntop(key.sourceIPv6Address), key.sourceTransportPort,
            ipv6:ntop(key.destinationIPv6Address), key.destinationTransportPort,
            protos[key.protocolIdentifier] or tostring(key.protocolIdentifier))
      end
   },
   v6_HTTP = {
      id     = 513,
      filter = "ip6 and tcp dst port 80",
      aggregation_type = 'v6',
      keys   = { "sourceIPv6Address",
                 "destinationIPv6Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount",
                 "tcpControlBitsReduced",
                 "httpRequestMethod=8",
                 "httpRequestHost=32",
                 "httpRequestTarget=64" },
      state_t = HTTP_state_t,
      counters = HTTP_counters(),
      extract = v6_extract,
      accumulate = function (self, dst, new, pkt)
         accumulate_generic(dst, new)
         accumulate_tcp_flags_reduced(dst, new)
         HTTP_accumulate(self, dst, new, pkt)
      end
   },
   v6_DNS = {
      id     = 514,
      filter = "ip6 and udp port 53",
      aggregation_type = 'v6',
      keys   = { "sourceIPv6Address",
                 "destinationIPv6Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort",
                 "dnsFlagsCodes",
                 "dnsQuestionCount",
                 "dnsAnswerCount",
                 "dnsQuestionName=64",
                 "dnsQuestionType",
                 "dnsQuestionClass",
                 "dnsAnswerName=64",
                 "dnsAnswerType",
                 "dnsAnswerClass",
                 "dnsAnswerTtl",
                 "dnsAnswerRdata=64",
                 "dnsAnswerRdataLen" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount" },
      extract = function (self, pkt, timestamp, entry)
         DNS_extract(self, pkt, timestamp, entry, extract_v6_addr)
      end,
      accumulate = DNS_accumulate
   },
   v6_extended = {
      id     = 1512,
      filter = "ip6",
      aggregation_type = 'v6',
      keys   = { "sourceIPv6Address",
                 "destinationIPv6Address",
                 "protocolIdentifier",
                 "sourceTransportPort",
                 "destinationTransportPort" },
      values = { "flowStartMilliseconds",
                 "flowEndMilliseconds",
                 "packetDeltaCount",
                 "octetDeltaCount",
                 "sourceMacAddress",
                 -- This is destinationMacAddress per NetFlowV9
                 "postDestinationMacAddress",
                 "vlanId",
                 "ipClassOfService",
                 "bgpSourceAsNumber",
                 "bgpDestinationAsNumber",
                 "bgpNextAdjacentAsNumber",
                 "bgpPrevAdjacentAsNumber",
                 "tcpControlBitsReduced",
                 "icmpTypeCodeIPv6",
                 "ingressInterface",
                 "egressInterface" },
      require_maps = { 'mac_to_as', 'vlan_to_ifindex', 'pfx6_to_as' },
      extract = v6_extended_extract,
      accumulate = v6_extended_accumulate,
   },
}

local templates_legend = [[
- `value=n` means the value stores up to *n* bytes.
- `tcpControlBitsReduced` are the `tcpControlBits` defined in [RFC 5102](https://datatracker.ietf.org/doc/html/rfc5102#section-5.8.7)
- The `dns*` keys are private enterprise extensions courtesy by SWITCH
]]

-- sudo ./snabb snsh -e 'require("apps.ipfix.template").templatesMarkdown()' > apps/ipfix/README.templates.md
function templatesMarkdown (out)
   out = out or io.stdout
   local names = {}
   for name in pairs(templates) do
      table.insert(names, name)
   end
   table.sort(names)
   out:write([[<!--- DO NOT EDIT, this file is generated via 
   sudo ./snabb snsh -e 'require("apps.ipfix.template").templatesMarkdown()' > apps/ipfix/README.templates.md
   --->
   
   ]])
   out:write("## IPFIX templates (apps.ipfix.template)\n\n")
   out:write(templates_legend.."\n")
   out:write("| Name | Id | Type | Filter | Keys | Values | Required Maps\n")
   out:write("| --- | --- | --- | --- | --- | --- | ---\n")
   local function listCell (xs)
      out:write("| ")
      if not xs then return end
      for i, x in ipairs(xs) do
         if i < #xs then
            out:write(("`%s`, "):format(x))
         else
            out:write(("`%s` "):format(x))
         end
      end
   end
   for _, name in ipairs(names) do
      local t = templates[name]
      out:write(("| %s | %d | %s | %s "):format(
         name, t.id, t.aggregation_type, t.filter))
      listCell(t.keys)
      listCell(t.values)
      listCell(t.require_maps)
      out:write("\n")
   end
end

function selftest()
   print('selftest: apps.ipfix.template')
   local datagram = require("lib.protocol.datagram")
   local ether  = require("lib.protocol.ethernet")
   local ipv4   = require("lib.protocol.ipv4")
   local ipv6   = require("lib.protocol.ipv6")
   local udp    = require("lib.protocol.udp")
   local packet = require("core.packet")

   local function test(src_ip, dst_ip, src_port, dst_port)
      local is_ipv6 = not not src_ip:match(':')
      local proto = is_ipv6 and consts.ethertype_ipv6 or
         consts.ethertype_ipv4
      local eth = ether:new({ src = ether:pton("00:11:22:33:44:55"),
                              dst = ether:pton("55:44:33:22:11:00"),
                              type = proto })
      local ip

      if is_ipv6 then
         ip = ipv6:new({ src = ipv6:pton(src_ip), dst = ipv6:pton(dst_ip),
                         next_header = IP_PROTO_UDP, ttl = 64 })
         ip:payload_length(udp:sizeof())
      else
         ip = ipv4:new({ src = ipv4:pton(src_ip), dst = ipv4:pton(dst_ip),
                         protocol = IP_PROTO_UDP, ttl = 64 })
         ip:total_length(ip:total_length() + udp:sizeof())
      end
      local udp = udp:new({ src_port = src_port, dst_port = dst_port })
      local dg = datagram:new()

      dg:push(udp)
      dg:push(ip)
      dg:push(eth)

      local pkt = dg:packet()
      metadata.add(pkt)
      
      local v4 = make_template_info(templates.v4)
      local v6 = make_template_info(templates.v6)
      assert(v4.match(pkt.data, pkt.length) == not is_ipv6)
      assert(v6.match(pkt.data, pkt.length) == is_ipv6)
      local templ = is_ipv6 and v6 or v4
      local entry = templ.record_t()
      local timestamp = 13
      templ.extract(templ, pkt, 13, entry)
      if is_ipv6 then
         assert(ip:src_eq(entry.key.sourceIPv6Address))
         assert(ip:dst_eq(entry.key.destinationIPv6Address))
      else
         assert(ip:src_eq(entry.key.sourceIPv4Address))
         assert(ip:dst_eq(entry.key.destinationIPv4Address))
      end
      assert(entry.key.protocolIdentifier == IP_PROTO_UDP)
      assert(entry.key.sourceTransportPort == src_port)
      assert(entry.key.destinationTransportPort == dst_port)
      assert(entry.value.flowStartMilliseconds == timestamp)
      assert(entry.value.flowEndMilliseconds == timestamp)
      assert(entry.value.packetDeltaCount == 1)
      assert(entry.value.octetDeltaCount == pkt.length - consts.ethernet_header_size)

      packet.free(pkt)
   end

   for i=1, 100 do
      local src_ip, dst_ip
      if math.random(1,2) == 1 then
         src_ip = string.format("192.168.1.%d", math.random(1, 254))
         dst_ip = string.format("10.0.0.%d", math.random(1, 254))
      else
         src_ip = string.format("2001:4860:4860::%d", math.random(1000, 9999))
         dst_ip = string.format("2001:db8::ff00:42:%d", math.random(1000, 9999))
      end
      local src_port, dst_port = math.random(1, 65535), math.random(1, 65535)
      test(src_ip, dst_ip, src_port, dst_port)
   end

   print("selftest ok")
end

-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local bit      = require("bit")
local ffi      = require("ffi")
local pf       = require("pf")
local consts   = require("apps.lwaftr.constants")
local lib      = require("core.lib")
local ctable   = require("lib.ctable")
local ethernet = require("lib.protocol.ethernet")
local ipv4     = require("lib.protocol.ipv4")
local metadata = require("apps.ipfix.packet_metadata")

local ntohs  = lib.ntohs
local htonl, htons = lib.htonl, lib.htons
local function htonq(v) return bit.bswap(v + 0ULL) end
local metadata_get = metadata.get

local function ptr_to(ctype) return ffi.typeof('$*', ctype) end

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local IP_PROTO_TCP  = 6
local IP_PROTO_UDP  = 17
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

-- Create a table describing the information needed to create
-- flow templates and data records.
local function make_template_info(spec)
   -- Representations of IPFIX IEs.
   local ctypes =
      { unsigned8 = 'uint8_t', unsigned16 = 'uint16_t',
        unsigned32 = 'uint32_t', unsigned64 = 'uint64_t',
        string = 'uint8_t[?]', octetArray = 'uint8_t[?]',
        ipv4Address = 'uint8_t[4]', ipv6Address = 'uint8_t[16]',
        dateTimeMilliseconds = 'uint64_t' }
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
            swap_fn = gen_swap_fn(),
            match = pf.compile_filter(spec.filter),
            logger = lib.logger_new({ module = "IPFIX template #"..spec.id })
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
   dst.value.flowEndMilliseconds = new.value.flowEndMilliseconds
   dst.value.packetDeltaCount = dst.value.packetDeltaCount + 1
   dst.value.octetDeltaCount =
      dst.value.octetDeltaCount + new.value.octetDeltaCount
end

v4 = make_template_info {
   id     = 256,
   filter = "ip",
   keys   = { "sourceIPv4Address",
              "destinationIPv4Address",
              "protocolIdentifier",
              "sourceTransportPort",
              "destinationTransportPort" },
   values = { "flowStartMilliseconds",
              "flowEndMilliseconds",
              "packetDeltaCount",
              "octetDeltaCount",
              "tcpControlBitsReduced" }
}

function v4.extract(pkt, timestamp, entry)
   local md = metadata_get(pkt)
   extract_5_tuple(pkt, timestamp, entry, md, extract_v4_addr)
   if md.proto == IP_PROTO_TCP and md.frag_offset == 0 then
      extract_tcp_flags_reduced(md.l4, entry)
   end
end

function v4.accumulate(dst, new)
   accumulate_generic(dst, new)
   if dst.key.protocolIdentifier == IP_PROTO_TCP then
      accumulate_tcp_flags_reduced(dst, new)
   end
end

function v4.tostring(entry)
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

v6 = make_template_info {
   id     = 257,
   filter = "ip6",
   keys   = { "sourceIPv6Address",
              "destinationIPv6Address",
              "protocolIdentifier",
              "sourceTransportPort",
              "destinationTransportPort" },
   values = { "flowStartMilliseconds",
              "flowEndMilliseconds",
              "packetDeltaCount",
              "octetDeltaCount",
              "tcpControlBitsReduced" }
}

function v6.extract(pkt, timestamp, entry)
   local md = metadata_get(pkt)
   extract_5_tuple(pkt, timestamp, entry, md, extract_v6_addr)
   if md.proto == IP_PROTO_TCP and md.frag_offset == 0 then
      extract_tcp_flags_reduced(md.l4, entry)
   end
end

function v6.accumulate(dst, new)
   accumulate_generic(dst, new)
   if dst.key.protocolIdentifier == IP_PROTO_TCP then
      accumulate_tcp_flags_reduced(dst, new)
   end
end

function v6.tostring(entry)
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

      local pkt = dg:packet()
      
      assert(v4.match(pkt.data, pkt.length) == not is_ipv6)
      assert(v6.match(pkt.data, pkt.length) == is_ipv6)
      local templ = is_ipv6 and v6 or v4
      local entry = templ.record_t()
      local timestamp = 13
      templ.extract(pkt, 13, entry)
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
      assert(entry.value.octetDeltaCount == pkt.length - ethernet_header_size)

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

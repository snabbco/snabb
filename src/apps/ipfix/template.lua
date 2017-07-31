-- This module implements the flow metering app, which records
-- IP flows as part of an IP flow export program.

module(..., package.seeall)

local bit    = require("bit")
local ffi    = require("ffi")
local pf     = require("pf")
local consts = require("apps.lwaftr.constants")
local lib    = require("core.lib")

local ntohs  = lib.ntohs
local htonl, htons = lib.htonl, lib.htons
local function htonq(v) return bit.bswap(v + 0ULL) end

local function ptr_to(ctype) return ffi.typeof('$*', ctype) end

local debug = lib.getenv("FLOW_EXPORT_DEBUG")

local IP_PROTO_TCP  = 6
local IP_PROTO_UDP  = 17
local IP_PROTO_SCTP = 132

-- These constants are taken from the lwaftr constants module, which
-- is maybe a bad dependency but sharing code is good
-- TODO: move constants somewhere else? lib?
local ethertype_ipv4         = consts.ethertype_ipv4
local ethertype_ipv6         = consts.ethertype_ipv6
local ethernet_header_size   = consts.ethernet_header_size
local ipv6_fixed_header_size = consts.ipv6_fixed_header_size
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
            swap_fn = gen_swap_fn(),
            match = pf.compile_filter(spec.filter)
          }
end

local uint16_ptr_t = ffi.typeof('uint16_t *')

local function get_ipv4_ihl(l3)
   return bit.band((l3 + o_ipv4_ver_and_ihl)[0], 0x0f)
end

local function get_ipv4_protocol(l3)    return l3[o_ipv4_proto] end
local function get_ipv6_next_header(l3) return l3[o_ipv6_next_header] end

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

local function get_tcp_src_port(l4)
   return ntohs(ffi.cast(uint16_ptr_t, l4)[0])
end
local function get_tcp_dst_port(l4)
   return ntohs(ffi.cast(uint16_ptr_t, l4)[1])
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
              "octetDeltaCount"}
}

function v4.extract(pkt, timestamp, entry)
   local l2 = pkt.data
   local l3 = l2 + ethernet_header_size
   local ihl = get_ipv4_ihl(l3)
   local l4 = l3 + ihl * 4

   -- Fill key.
   -- FIXME: Try using normal Lua assignment.
   read_ipv4_src_address(l3, entry.key.sourceIPv4Address)
   read_ipv4_dst_address(l3, entry.key.destinationIPv4Address)
   local prot = get_ipv4_protocol(l3)
   entry.key.protocolIdentifier = prot
   if prot == IP_PROTO_TCP or prot == IP_PROTO_UDP or prot == IP_PROTO_SCTP then
      entry.key.sourceTransportPort = get_tcp_src_port(l4)
      entry.key.destinationTransportPort = get_tcp_dst_port(l4)
   else
      entry.key.sourceTransportPort = 0
      entry.key.destinationTransportPort = 0
   end

   -- Fill value.
   entry.value.flowStartMilliseconds = timestamp
   entry.value.flowEndMilliseconds = timestamp
   entry.value.packetDeltaCount = 1
   -- Measure bytes starting with the IP header.
   entry.value.octetDeltaCount = pkt.length - ethernet_header_size
end

function v4.accumulate(dst, new)
   dst.value.flowEndMilliseconds = new.value.flowEndMilliseconds
   dst.value.packetDeltaCount = dst.value.packetDeltaCount + 1
   dst.value.octetDeltaCount =
      dst.value.octetDeltaCount + new.value.octetDeltaCount
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
              "octetDeltaCount" }
}

function v6.extract(pkt, timestamp, entry)
   local l2 = pkt.data
   local l3 = l2 + ethernet_header_size
   -- TODO: handle chained headers
   local l4 = l3 + ipv6_fixed_header_size

   -- Fill key.
   -- FIXME: Try using normal Lua assignment.
   read_ipv6_src_address(l3, entry.key.sourceIPv6Address)
   read_ipv6_dst_address(l3, entry.key.destinationIPv6Address)
   local prot = get_ipv6_next_header(l3)
   entry.key.protocolIdentifier = prot
   if prot == IP_PROTO_TCP or prot == IP_PROTO_UDP or prot == IP_PROTO_SCTP then
      entry.key.sourceTransportPort = get_tcp_src_port(l4)
      entry.key.destinationTransportPort = get_tcp_dst_port(l4)
   else
      entry.key.sourceTransportPort = 0
      entry.key.destinationTransportPort = 0
   end

   -- Fill value.
   entry.value.flowStartMilliseconds = timestamp
   entry.value.flowEndMilliseconds = timestamp
   entry.value.packetDeltaCount = 1
   -- Measure bytes starting with the IP header.
   entry.value.octetDeltaCount = pkt.length - ethernet_header_size
end

function v6.accumulate(dst, new)
   dst.value.flowEndMilliseconds = new.value.flowEndMilliseconds
   dst.value.packetDeltaCount = dst.value.packetDeltaCount + 1
   dst.value.octetDeltaCount =
      dst.value.octetDeltaCount + new.value.octetDeltaCount
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

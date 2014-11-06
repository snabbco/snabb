module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")
local buffer = require("core.buffer")
local config = require("core.config")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

local verbose = false

assert(ffi.abi("le"), "support only little endian architecture at the moment")
assert(ffi.abi("64bit"), "support only 64 bit architecture at the moment")

-- TODO: generalize
local AF_INET = 2
local AF_INET6 = 10

-- http://en.wikipedia.org/wiki/EtherType
-- http://en.wikipedia.org/wiki/IPv6_packet
-- http://en.wikipedia.org/wiki/IPv4_packet#Packet_structure
-- http://en.wikipedia.org/wiki/List_of_IP_protocol_numbers
-- http://en.wikipedia.org/wiki/User_Datagram_Protocol
-- http://en.wikipedia.org/wiki/Tcp_protocol
-- http://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing

-- in network order already
local ETHERTYPE_IPV6 = "0xDD86"
local ETHERTYPE_IPV4 = "0x0008"

local IP_UDP = 0x11
local IP_TCP = 6
local IP_ICMP = 1
local IPV6_ICMP = 0x3a

local ETHERTYPE_OFFSET = 12

local IPV4_SOURCE_OFFSET = 26
local IPV4_DEST_OFFSET = 30
local IPV4_PROTOCOL_OFFSET = 23
local IPV4_SOURCE_PORT_OFFSET = 34
local IPV4_DEST_PORT_OFFSET = 36

local IPV6_SOURCE_OFFSET = 22
local IPV6_DEST_OFFSET = 38
local IPV6_NEXT_HEADER_OFFSET = 20 -- protocol
local IPV6_SOURCE_PORT_OFFSET = 54
local IPV6_DEST_PORT_OFFSET = 56

local PORT_LEN = 2
local IPV4_ADDRESS_LEN = 4
local IPV6_ADDRESS_LEN = 16

local min_packet_sizes =
{
   ipv4 =
   {
      icmp = IPV4_DEST_OFFSET + IPV4_ADDRESS_LEN, -- IPv4 header is enough
      tcp  = IPV4_DEST_PORT_OFFSET + PORT_LEN, -- at least ports must be there
      udp  = IPV4_DEST_PORT_OFFSET + PORT_LEN, -- at least ports must be there
   },
   ipv6 =
   {
      icmp = IPV6_DEST_OFFSET + IPV6_ADDRESS_LEN, -- IPv6 header is enough
      tcp  = IPV6_DEST_PORT_OFFSET + PORT_LEN, -- at least ports must be there
      udp  = IPV6_DEST_PORT_OFFSET + PORT_LEN, -- at least ports must be there
   }
}

local make_code_concatter
do
   local mt = { }

   mt.indent = function(self)
      self.level_ = self.level_ + 1
   end

   mt.unindent = function(self)
      self.level_ = self.level_ - 1
      assert(self.level_ >= 0)
   end

   mt.cat = function(self, ...)
      for i = 1, self.level_ do
         self.buf_[#self.buf_ + 1] = "  "
      end
      for i = 1, select("#", ...) do
         self.buf_[#self.buf_ + 1] = tostring( (select(i, ...)) )
      end
      self.buf_[#self.buf_ + 1] = "\n"
      return self
   end

   mt.concat = function(self)
      local result = table.concat(self.buf_)
      self.level_ = 0
      self.buf_ = { }
      return result
   end

   mt.__call = mt.cat
   mt.__index = mt

   make_code_concatter = function()
         return setmetatable(
         {
            level_ = 0;
            buf_ = { };
         },
         mt
      )
   end
end

local function parse_cidr_ipv4 (cidr)
   local address, prefix_size =  string.match(cidr, "^(.+)/(%d+)$")

   if not ( address and prefix_size ) then
      return false, "malformed IPv4 CIDR: " .. tostring(cidr)
   end
   prefix_size = tonumber(prefix_size)
   if prefix_size > 32 then
      return false, "IPv6 CIDR mask is too big: " .. prefix_size
   end
   if prefix_size == 0 then
      return true -- any IP
   end

   local in_addr  = ffi.new("int32_t[1]")
   local result = C.inet_pton(AF_INET, address, in_addr)
   if result ~= 1 then
      return false, "malformed IPv4 address: " .. address
   end

   if prefix_size == 32 then
      -- single IP address
      return true, in_addr[0]
   end

   local mask = bit.bswap(bit.bnot(bit.rshift(bit.bnot(0), prefix_size)))
   return true, bit.band(in_addr[0], mask), mask
end

local function parse_cidr_ipv6 (cidr)
   local address, prefix_size = string.match(cidr, "^(.+)/(%d+)$")

   if not ( address and prefix_size ) then
      return false, "malformed IPv6 CIDR: " .. tostring(cidr)
   end

   prefix_size = tonumber(prefix_size)

   if prefix_size > 128 then
      return false, "IPv6 CIDR mask is too big: " .. prefix_size
   end
   if prefix_size == 0 then
      return true -- any IP
   end

   local in6_addr  = ffi.new("uint64_t[2]")
   local result = C.inet_pton(AF_INET6, address, in6_addr)
   if result ~= 1 then
      return false, "malformed IPv6 address: " .. address
   end

   if prefix_size < 64 then
      local mask =
         bit.bswap(bit.bnot(bit.rshift(bit.bnot(0ULL), prefix_size)))
      return true, bit.band(in6_addr[0], mask), nil, mask
   end
   if prefix_size == 64 then
      return true, in6_addr[0]
   end
   if prefix_size < 128 then
      local mask =
         bit.bswap(bit.bnot(bit.rshift(bit.bnot(0ULL), prefix_size - 64)))
      return true, in6_addr[0], bit.band(in6_addr[1], mask), mask
   end
   -- prefix_size == 128
   return true, in6_addr[0], in6_addr[1]
end

-- used for source/destination adresses matching
local function generateIpv4CidrMatch(T, cidr, offset, name)
   local ok, prefix, mask = assert(parse_cidr_ipv4(cidr))

   if not prefix then
      -- any address
      return
   end

   prefix = bit.tohex(prefix)
   T("local ",name," = ffi.cast(\"uint32_t*\", buffer + ",offset,")")
   if mask then
      T("if bit.band(",mask,", ",name,"[0]) ~= 0x",prefix," then break end")
   else
      -- single IP address
      T("if ",name,"[0] ~= 0x",prefix," then break end")
   end
end

local function generateIpv6CidrMatch(T, cidr, offset, name)
   local ok, prefix1, prefix2, mask = assert(parse_cidr_ipv6(cidr))

   if not prefix1 then
      -- any address
      return
   end

   T("local ",name," = ffi.cast(\"uint64_t*\", buffer + ",offset,")")

   if not prefix2 and mask then
      T("if 0x", bit.tohex(prefix1),"ULL ~= bit.band(0x",bit.tohex(mask),"ULL, ",name,"[0]) then break end")
      return
   end

   T("if ",name,"[0] ~= 0x",bit.tohex(prefix1),"ULL then break end")
   if not prefix2 and not mask then
      return
   end

   if prefix2 and not mask then
      T("if ",name,"[1] ~= 0x", bit.tohex(prefix2),"ULL  then break end")
      return
   end

   -- prefix1 and prefix2 and mask
   T("if 0x", bit.tohex(prefix2),"ULL ~= bit.band(0x",bit.tohex(mask),"ULL, ",name,"[1]) then break end")
end

local function generateProtocolMatch(T, protocol, offset)
   T("if buffer[",offset,"] ~= ",protocol," then break end")
end

local function generatePortMatch(T, offset, port_min, port_max, name)
   if port_min == port_max then
      -- specialization for single port matching
      -- avoid conversion to host order on runtime
      local port_network_order = lib.htons(port_min)

      T("local ",name," = ffi.cast(\"uint16_t*\", buffer + ",offset,")")
      T("if ",name,"[0] ~= ",port_network_order," then break end")
      return
   end
   T("local ",name," = buffer[",offset,"] * 0x100 + buffer[",offset+1,"]")
   T("if ",name," < ",port_min," or ",name," > ",port_max," then break end")
end

local function generateRule(
      T,
      rule,
      generateIpMatch,
      source_ip_offset,
      dest_ip_offset,
      protocol_offset,
      icmp_type,
      source_port_offset,
      dest_port_offset
   )
   T"repeat"
   T:indent()

   assert(rule.ethertype)
   T("local ethertype = ffi.cast(\"uint16_t*\", buffer + ",ETHERTYPE_OFFSET,")")
   local ethertype
   if rule.ethertype == "ipv4" then
      ethertype = ETHERTYPE_IPV4
   elseif rule.ethertype == "ipv6" then
      ethertype = ETHERTYPE_IPV6
   else
      error("unknown ethertype")
   end
   local min_header_size = assert(
         min_packet_sizes[rule.ethertype][rule.protocol],
         "unknown min packet size"
      )
   T("if size < ",min_header_size," then break end")
   T("if ethertype[0] ~= ",ethertype," then break end")

   if rule.source_cidr then
      generateIpMatch(T, rule.source_cidr, source_ip_offset, "source_ip")
   end
   if rule.dest_cidr then
      generateIpMatch(T, rule.dest_cidr, dest_ip_offset, "dest_ip")
   end
   if rule.protocol then
      if rule.protocol == "tcp" then
         generateProtocolMatch(T, IP_TCP, protocol_offset)
      elseif rule.protocol == "udp" then
         generateProtocolMatch(T, IP_UDP, protocol_offset)
      elseif rule.protocol == "icmp" then
         generateProtocolMatch(T, icmp_type, protocol_offset)
      else
         error("unknown protocol")
      end
      if rule.protocol == "tcp" or rule.protocol == "udp" then
         if rule.source_port_min then
            if not rule.source_port_max then
               rule.source_port_max = rule.source_port_min
            end
            generatePortMatch(
                  T,
                  source_port_offset,
                  rule.source_port_min,
                  rule.source_port_max,
                  "source_port"
               )
         end
         if rule.dest_port_min then
            if not rule.dest_port_max then
               rule.dest_port_max = rule.dest_port_min
            end
            generatePortMatch(
                  T,
                  dest_port_offset,
                  rule.dest_port_min,
                  rule.dest_port_max,
                  "dest_port"
               )
         end
      end
   end
   T"return true"
   T:unindent()
   T"until false"
end

local function generateConformFunctionString(rules)
   local T = make_code_concatter()
   T"local ffi = require(\"ffi\")"
   T"local bit = require(\"bit\")"
   T"return function(buffer, size)"
   T:indent()

   for i = 1, #rules do
      if rules[i].ethertype == "ipv4" then
         generateRule(
               T,
               rules[i],
               generateIpv4CidrMatch,
               IPV4_SOURCE_OFFSET,
               IPV4_DEST_OFFSET,
               IPV4_PROTOCOL_OFFSET,
               IP_ICMP,
               IPV4_SOURCE_PORT_OFFSET,
               IPV4_DEST_PORT_OFFSET
            )

      elseif rules[i].ethertype == "ipv6" then
         generateRule(
               T,
               rules[i],
               generateIpv6CidrMatch,
               IPV6_SOURCE_OFFSET,
               IPV6_DEST_OFFSET,
               IPV6_NEXT_HEADER_OFFSET,
               IPV6_ICMP,
               IPV6_SOURCE_PORT_OFFSET,
               IPV6_DEST_PORT_OFFSET
            )
      else
         error("unknown ethertype")
      end
   end
   T"return false"
   T:unindent()
   T"end"
   local ret = T:concat()
   if verbose then print(ret) end
   return ret
end

PacketFilter = {}

function PacketFilter:new (arg)
   local rules = arg and config.parse_app_arg(arg) or {}
   assert(rules)
   assert(#rules > 0)

   local o =
   {
      conform = assert(loadstring(
            generateConformFunctionString(rules)
         ))()
   }
   return setmetatable(o, {__index = PacketFilter})
end

function PacketFilter:push ()
   local i = assert(self.input.input or self.input.rx, "input port not found")
   local o = assert(self.output.output or self.output.tx, "output port not found")

   local packets_tx = 0
   local max_packets_to_send = link.nwritable(o)
   if max_packets_to_send == 0 then
      return
   end

   local nreadable = link.nreadable(i)
   for n = 1, nreadable do
      local p = link.receive(i)
      -- support the whole IP header in one iovec at the moment

      if self.conform(
            p.iovecs[0].buffer.pointer + p.iovecs[0].offset,
            p.iovecs[0].length
         )
      then
         link.transmit(o, p)
      else
         -- discard packet
         packet.deref(p)
      end
   end
end

function selftest ()
   -- Temporarily disabled:
   --   Packet filter selftest is failing in.
   -- enable verbose logging for selftest
   verbose = true
   buffer.preallocate(10000)

   local V6_RULE_ICMP_PACKETS = 3 -- packets within v6.pcap
   local V6_RULE_DNS_PACKETS =  3 -- packets within v6.pcap
      
   local v6_rules = {
   {
      ethertype = "ipv6",
      protocol = "icmp",
      source_cidr = "3ffe:501:0:1001::2/128", -- single IP, match 128bit
      dest_cidr =
         "3ffe:507:0:1:200:86ff:fe05:8000/116", -- match first 64bit and mask next 52 bit
   },
   {
      ethertype = "ipv6",
      protocol = "udp",
      source_cidr = "3ffe:507:0:1:200:86ff::/28", -- mask first 28 bit
      dest_cidr = "3ffe:501:4819::/64",           -- match first 64bit
      source_port_min = 2397, -- port range, in v6.pcap there are values on
      source_port_max = 2399, -- both borders and in the middle
      dest_port_min = 53,     -- single port match
      dest_port_max = 53,
   }}

   local c = config.new()
   config.app(
         c,
         "source1",
         pcap.PcapReader,
         "apps/packet_filter/samples/v6.pcap"
      )
   config.app(c,
         "packet_filter1",
         PacketFilter,
         v6_rules
      )
   config.app(c, "sink1", basic_apps.Sink )
   config.link(c, "source1.output -> packet_filter1.input")
   config.link(c, "packet_filter1.output -> sink1.input")

   local V4_RULE_DNS_PACKETS = 1 -- packets within v4.pcap
   local V4_RULE_TCP_PACKETS = 18 -- packets within v4.pcap

   local v4_rules = {
   {
      ethertype = "ipv4",
      protocol = "udp",
      dest_port_min = 53,     -- single port match, DNS
      dest_port_max = 53,
   },
   {
      ethertype = "ipv4",
      protocol = "tcp",
      source_cidr = "65.208.228.223/32", -- match 32bit
      dest_cidr = "145.240.0.0/12",      -- mask 12bit
      source_port_min = 80, -- our port (80) is on the border of range
      source_port_max = 81,
      dest_port_min = 3371, -- our port (3372) is in the middle of range
      dest_port_max = 3373,
   }}

   config.app(
         c,
         "source2",
         pcap.PcapReader,
         "apps/packet_filter/samples/v4.pcap"
      )
   config.app(c,
         "packet_filter2",
         PacketFilter,
         v4_rules
      )
   config.app(c, "sink2", basic_apps.Sink )
   config.link(c, "source2.output -> packet_filter2.input")
   config.link(c, "packet_filter2.output -> sink2.input")

   app.configure(c)

   -- v4.pcap contains 43 packets
   -- v6.pcap contains 161 packets
   -- one breathe is enough
   app.breathe()

   app.report()

   local packet_filter1_passed =
      app.app_table.packet_filter1.output.output.stats.txpackets
   local packet_filter2_passed =
      app.app_table.packet_filter2.output.output.stats.txpackets
   local ok = true

   if packet_filter1_passed ~= V6_RULE_ICMP_PACKETS + V6_RULE_DNS_PACKETS
   then
      ok = false
      print("IPv6 test failed")
   end
   if packet_filter2_passed ~= V4_RULE_DNS_PACKETS + V4_RULE_TCP_PACKETS
   then
      ok = false
      print("IPv4 test failed")
   end
   if not ok then
      print("selftest failed")
      os.exit(1)
   end
   print("selftest passed")
end

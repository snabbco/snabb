local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")

local ntohs = lib.ntohs

local verbose = false

assert(ffi.abi("le"), "support only little endian architecture at the moment")
assert(ffi.abi("64bit"), "support only 64 bit architecture at the moment")

-- TODO: generalize
local AF_INET = 2
local AF_INET6 = 10

local ETHERTYPE_IPV6 = 0xDD86
local ETHERTYPE_IPV4 = 0x0008
local ETHERTYPE_ARP  = 0x0608

local IP_UDP = 0x11
local IP_TCP = 6
local IP_ICMP = 1
local IPV6_ICMP = 0x3a

local ETHERTYPE_OFFSET = 12

local IPV4_SOURCE_OFFSET = 26
local IPV4_PROTOCOL_OFFSET = 23
local IPV4_SOURCE_PORT_OFFSET = 34

local IPV6_SOURCE_OFFSET = 22
local IPV6_NEXT_HEADER_OFFSET = 20 -- protocol
local IPV6_SOURCE_PORT_OFFSET = 54


ffi.cdef [[
   typedef struct {
      uint32_t src_ip, dst_ip;
      uint16_t src_port, dst_port;
      uint8_t protocol;
   } __attribute__((packed)) conn_spec_ipv4;

   typedef struct {
      uint64_t a, b;
   } __attribute__((packed)) ipv6_addr;

   typedef struct {
      ipv6_addr src_ip, dst_ip;
      uint16_t src_port, dst_port;
      uint8_t protocol;
   } __attribute__((packed)) conn_spec_ipv6;
]]


----
local conntrack
do
   local conntracks = {}
   local counts = {}
   local time = engine.now
   local function new(t) return {{}, {}, (time() or 0)+t} end
   local function put(p, k, v)
      local isnew = p[1][k] == nil
      p[1][k] = v
      return isnew
   end
   local function get(p, k) return p[1][k] or p[2][k] end
   local function age(p, t)
      if time() > p[3] then
         p[1], p[2], p[3] = {}, p[1], time()+t
         return true
      end
   end

   conntrack = {
      define = function (name, agestep)
         conntracks[name] = conntracks[name] or new(agestep or 7200)
         counts[name] = counts[name] or 0
      end,

      track = function (name, key, revkey, limit)
         limit = limit or 1000
         if counts[name] > limit then return end
         local p = conntracks[name]
         if put(p, key, true) then
            counts[name] = counts[name] + 1
         end
         put(p, revkey, true)
      end,

      check = function (name, key)
         return key and get(conntracks[name], key)
      end,

      age = function(name, t)
         if age(conntracks[name], t) then
            counts[name] = 0
         end
      end,

      clear = function ()
         for name, p in pairs(conntracks) do
            p[1], p[2], p[3] = {}, {}, time()+7200
         end
         conntracks = {}
      end,
   }
end

----


local spec_v4 = ffi.typeof('conn_spec_ipv4')
local ipv4 = {}
ipv4.__index = ipv4


function ipv4:fill(b)
   do
      local hdr_ips = ffi.cast('uint32_t*', b+IPV4_SOURCE_OFFSET)
      self.src_ip = hdr_ips[0]
      self.dst_ip = hdr_ips[1]
   end
   self.protocol = b[IPV4_PROTOCOL_OFFSET]
   if self.protocol == IP_TCP or self.protocol == IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+IPV4_SOURCE_PORT_OFFSET)
      self.src_port = ntohs(hdr_ports[0])
      self.dst_port = ntohs(hdr_ports[1])
   else
      self.src_port, self.dst_port = 0, 0
   end
   return self
end


function ipv4:reverse(o)
   if o then
      o.protocol = self.protocol
   else
      o = self
   end
   o.src_ip, o.dst_ip = self.dst_ip, self.src_ip
   o.src_port, o.dst_port = self.dst_port, self.src_port
   return o
end


function ipv4:__tostring()
   return ffi.string(self, ffi.sizeof(spec_v4))
end


do
   local s2 = nil
   function ipv4:track(trackname)
      if s2 == nil then s2 = spec_v4() end
      return conntrack.track(trackname, self:__tostring(), self:reverse(s2):__tostring())
   end
end


function ipv4:check(trackname)
   return conntrack.check(trackname, self:__tostring())
end


spec_v4 = ffi.metatype(spec_v4, ipv4)

-------

local spec_v6 = ffi.typeof('conn_spec_ipv6')
local ipv6 = {}
ipv6.__index = ipv6

function ipv6:fill(b)
   do
      local hdr_ips = ffi.cast('ipv6_addr*', b+IPV6_SOURCE_OFFSET)
      self.src_ip = hdr_ips[0]
      self.dst_ip = hdr_ips[1]
   end
   self.protocol = b[IPV6_NEXT_HEADER_OFFSET]
   if self.protocol == IP_TCP or self.protocol == IP_UDP then
      local hdr_ports = ffi.cast('uint16_t*', b+IPV6_SOURCE_PORT_OFFSET)
      self.src_port = ntohs(hdr_ports[0])
      self.dst_port = ntohs(hdr_ports[1])
   else
      self.src_port, self.dst_port = 0, 0
   end
   return self
end


function ipv6:reverse(o)
   if o then
      o.protocol = self.protocol
   else
      o = self
   end
   o.src_ip.a, o.dst_ip.a = self.dst_ip.a, self.src_ip.a
   o.src_ip.b, o.dst_ip.b = self.dst_ip.b, self.src_ip.b
   o.src_port, o.dst_port = self.dst_port, self.src_port
   return o
end


function ipv6:__tostring()
   return ffi.string(self, ffi.sizeof(spec_v6))
end


do
   local s2 = nil
   function ipv6:track(trackname)
      if s2 == nil then s2 = spec_v6() end
      return conntrack.track(trackname, self:__tostring(), self:reverse(s2):__tostring())
   end
end


function ipv6:check(trackname)
   return conntrack.check(trackname, self:__tostring())
end


spec_v6 = ffi.metatype(spec_v6, ipv6)

------

local new_spec=nil
do
   local specv4 = spec_v4()
   local specv6 = spec_v6()
   new_spec = function (b)
      if not b then return nil end
      local ethertype = ffi.cast('uint16_t*', b+ETHERTYPE_OFFSET)[0]
      if ethertype == ETHERTYPE_IPV4 then
         return specv4:fill(b), ethertype
      end
      if ethertype == ETHERTYPE_IPV6 then
         return specv6:fill(b), ethertype
      end
   end
end

------


local function hex64(x)
   return '0x'..bit.tohex(x, -16)..'ULL'
end


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


local function preprocess_rules(options)
   if not options.rules then return end
   for _, in_rule in ipairs(options.rules) do

      if in_rule.ethertype == 'ipv4' then
         options.rules_ipv4 = options.rules_ipv4 or {}
         local out_rule = {}

         if in_rule.protocol == 'icmp' then
            out_rule.protocol = IP_ICMP
         elseif in_rule.protocol == 'udp' then
            out_rule.protocol = IP_UDP
         elseif in_rule.protocol == 'tcp' then
            out_rule.protocol = IP_TCP
         end

         if in_rule.source_cidr then
            local ok, prefix, mask = assert(parse_cidr_ipv4(in_rule.source_cidr))
            if ok then
               out_rule.source_prefix = prefix and '0x'..bit.tohex(prefix, -8)
               out_rule.source_mask = mask and '0x'..bit.tohex(mask, -8)
            end
         end

         if in_rule.dest_cidr then
            local ok, prefix, mask = assert(parse_cidr_ipv4(in_rule.dest_cidr))
            if ok then
               out_rule.dest_prefix = prefix and '0x'..bit.tohex(prefix, -8)
               out_rule.dest_mask = mask and '0x'..bit.tohex(mask, -8)
            end
         end

         out_rule.source_port_min = in_rule.source_port_min and tostring(in_rule.source_port_min)
         out_rule.source_port_max = in_rule.source_port_max and tostring(in_rule.source_port_max)
         out_rule.dest_port_min = in_rule.dest_port_min and tostring(in_rule.dest_port_min)
         out_rule.dest_port_max = in_rule.dest_port_max and tostring(in_rule.dest_port_max)
         out_rule.state_check = in_rule.state_check
         out_rule.state_track = in_rule.state_track

         options.rules_ipv4[#options.rules_ipv4+1] = out_rule
      end

      if in_rule.ethertype == 'ipv6' then
         options.rules_ipv6 = options.rules_ipv6 or {}
         local out_rule = {}

         if in_rule.protocol == 'icmp' then
            out_rule.protocol = IPV6_ICMP
         elseif in_rule.protocol == 'udp' then
            out_rule.protocol = IP_UDP
         elseif in_rule.protocol == 'tcp' then
            out_rule.protocol = IP_TCP
         end

         if in_rule.source_cidr then
            local ok, prefix1, prefix2, mask = assert(parse_cidr_ipv6(in_rule.source_cidr))
            if ok then
               out_rule.source_cidr = {
                  prefix1 = prefix1,
                  prefix2 = prefix2,
                  mask = mask,
               }
            end
         end

         if in_rule.dest_cidr then
            local ok, prefix1, prefix2, mask = assert(parse_cidr_ipv6(in_rule.dest_cidr))
            if ok then
               out_rule.dest_cidr = {
                  prefix1 = prefix1,
                  prefix2 = prefix2,
                  mask = mask,
               }
            end
         end

         out_rule.source_port_min = in_rule.source_port_min and tostring(in_rule.source_port_min)
         out_rule.source_port_max = in_rule.source_port_max and tostring(in_rule.source_port_max)
         out_rule.dest_port_min = in_rule.dest_port_min and tostring(in_rule.dest_port_min)
         out_rule.dest_port_max = in_rule.dest_port_max and tostring(in_rule.dest_port_max)
         out_rule.state_check = in_rule.state_check
         out_rule.state_track = in_rule.state_track

         options.rules_ipv6[#options.rules_ipv6+1] = out_rule
      end
   end
end

------

local function protocol_and_ports(rule, conds)
   if rule.protocol then
      conds[#conds+1] = 'spec.protocol == '..rule.protocol

      if rule.source_port_min then
         if rule.source_port_max and rule.source_port_max ~= rule.source_port_min then
            conds[#conds+1] = 'spec.src_port >= '..rule.source_port_min
            conds[#conds+1] = 'spec.src_port <= '..rule.source_port_max
         else
            conds[#conds+1] = 'spec.src_port == '..rule.source_port_min
         end
      end

      if rule.dest_port_min then
         if rule.dest_port_max and rule.dest_port_max ~= rule.dest_port_min then
            conds[#conds+1] = 'spec.dst_port >= '..rule.dest_port_min
            conds[#conds+1] = 'spec.dst_port <= '..rule.dest_port_max
         else
            conds[#conds+1] = 'spec.dst_port == '..rule.dest_port_min
         end
      end
   end
end

local function ipv4_conds(rule, conds)
   conds = conds or {}
   if rule.state_check then
      conds[#conds+1] = string.format('spec:check(%q)', rule.state_check)
   end

   if rule.source_prefix then
      if rule.source_mask then
         conds[#conds+1] = 'band(spec.src_ip, '..rule.source_mask..') == '..rule.source_prefix
      else
         conds[#conds+1] = 'spec.src_ip == '..rule.source_prefix
      end
   end

   if rule.dest_prefix then
      if rule.dest_mask then
         conds[#conds+1] = 'band(spec.dst_ip, '..rule.dest_mask..') == '..rule.dest_prefix
      else
         conds[#conds+1] = 'spec.dst_ip == '..rule.dest_prefix
      end
   end

   protocol_and_ports(rule, conds)
   return conds
end


local function ipv6_ip_match(cidr, fldn, conds)
   if not cidr then return end
   local prefix1, prefix2, mask = cidr.prefix1, cidr.prefix2, cidr.mask
   if prefix1 then
      -- size > 0
      if mask and not prefix2 then
         -- size < 64
         conds[#conds+1] = 'band('..fldn..'.a, '..hex64(mask)..') == '..hex64(prefix1)
      else
         -- size >= 64
         conds[#conds+1] = fldn..'.a == '..hex64(prefix1)
         if prefix2 then
            -- size > 64
            if mask then
               -- size < 128
               conds[#conds+1] = 'band('..fldn..'.b, '..hex64(mask)..') == '..hex64(prefix2)
            else
               -- size == 128
               conds[#conds+1] = fldn..'.b == '..hex64(prefix2)
            end
         end
      end
   end
end


local function ipv6_conds(rule, conds)
   conds = conds or {}
   if rule.state_check then
      conds[#conds+1] = string.format('spec:check(%q)', rule.state_check)
   end

   ipv6_ip_match(rule.source_cidr, 'spec.src_ip', conds)
   ipv6_ip_match(rule.dest_cidr, 'spec.dst_ip', conds)

   protocol_and_ports(rule, conds)
   return conds
end


local function build_test(T, conds, ...)
   if #conds > 0 then
      T("if ", table.concat(conds, ' and '), " then")
      T:indent()
         for i = 1, select("#", ...) do
            local tracktable = select(i, ...)
            if tracktable then
               conntrack.define(tracktable)
               T(string.format('spec:track(%q)', tracktable))
            end
         end
         T'return true'
      T:unindent()
      T'end'
   end
end


local function generate_conform(options, T)
   T"return function(buffer, size)"
   T:indent()

   T"local spec, ethertype = new_spec(buffer)"
   T"if not spec then return false end"

   if options.state_check then
      T(string.format("if spec:check(%q) then", options.state_check))
      T:indent()
      if options.state_track then
         T(string.format('spec:track(%q)', options.state_track))
      end
      T'return true'
      T:unindent()
      T'end'
   end

   if options.rules_ipv4 then
      T('-- pass ARP packets')
      T("if ethertype == 0x", bit.tohex(ETHERTYPE_ARP, -4)," then return true end")
      T('-- IPv4 rules')
      T("if ethertype == 0x", bit.tohex(ETHERTYPE_IPV4, -4), " then")
      T:indent()

      for _, rule in ipairs(options.rules_ipv4) do
         local conds = ipv4_conds(rule)
         build_test(T, conds, rule.state_track, options.state_track)
      end
      T:unindent()
      T"end"
   end

   if options.rules_ipv6 then
      T('-- IPv6 rules')
      T("if ethertype == 0x", bit.tohex(ETHERTYPE_IPV6, -4), " then")
      T:indent()

      for _, rule in ipairs(options.rules_ipv6) do
         local conds = ipv6_conds(rule)
         build_test(T, conds, rule.state_track, options.state_track)
      end

      T:unindent()
      T"end"
   end

   T'return false'
   T:unindent()
   T'end'
end


local function conform_function(options)
   preprocess_rules(options)

   local T = make_code_concatter()
   T"local ffi = require('ffi')"
   T"local bit = require('bit')"
   T"local band = bit.band"
--    T"local conntrack = require('apps.packet_filter.conntrack')"
   T"local PacketFilter = require('apps.packet_filter.packet_filter')"
   T"local new_spec = PacketFilter.new_spec"
--    T"local track = conntrack.track"
--    T"local state_pass = conntrack.check"
--    T"local ffi_cast = ffi.cast"
   T""

   generate_conform(options, T)

   local ret = T:concat()
   if verbose then print(ret) end
   return assert(loadstring(ret))()
end

------

local PacketFilter = { zone = 'PacketFilter' }
PacketFilter.__index = PacketFilter


function PacketFilter:new (options)
   options = config.parse_app_arg(options)

   return setmetatable({
      conform = conform_function(options),
   }, self)
end


function PacketFilter:push ()
   local lreceive, ltransmit = link.receive, link.transmit
   local pfree = packet.free
   local l_in = assert(self.input.input or self.input.rx, "input port not found")
   local l_out = assert(self.output.output or self.output.tx, "output port not found")

   while not link.empty(l_in) and not link.full(l_out) do
      local p = lreceive(l_in)

      if self.conform(p.data, p.length) then
         ltransmit(l_out, p)
      else
         -- discard packet
         pfree(p)
      end
   end
end



local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

function selftest ()
--    do
--       microbench()
--       simplebench()
--       return
--    end
   -- Temporarily disabled:
   --   Packet filter selftest is failing in.
   -- enable verbose logging for selftest
--    verbose = false

   local V6_RULE_ICMP_PACKETS = 3 -- packets within v6.pcap
   local V6_RULE_DNS_PACKETS =  3 -- packets within v6.pcap

   local v6_rules = {
      rules = {
         {
            ethertype = "ipv6",
            protocol = "icmp",
            source_cidr = "3ffe:501:0:1001::2/128", -- single IP, match 128bit
            dest_cidr =
               "3ffe:507:0:1:200:86ff:fe05:8000/116", -- match first 64bit and mask next 52 bit
            state_track = 'icmp6',
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
            state_track = 'dns_v6',
         },
      },
      state_track = 'app_v6',
   }

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
      rules = {
         {
            ethertype = "ipv4",
            protocol = "udp",
            dest_port_min = 53,     -- single port match, DNS
            dest_port_max = 53,
            state_track = 'dns',
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
            state_track = 'web',
         },
      },
      state_track = 'app_v4',
   }

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

   engine.configure(c)

   -- v4.pcap contains 43 packets
   -- v6.pcap contains 161 packets
   -- one breathe is enough
   engine.breathe()

   engine.report()
--    if verbose then print (conntrack.dump()) end

   local packet_filter1_passed =
      engine.app_table.packet_filter1.output.output.stats.txpackets
   local packet_filter2_passed =
      engine.app_table.packet_filter2.output.output.stats.txpackets
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


   --- second part:
   engine.configure(config.new())

   c = config.new()
   --- check a rule's tracked state
   config.app(c, "source1", pcap.PcapReader, "apps/packet_filter/samples/v6.pcap")
   config.app(c, "statefull_pass1", PacketFilter, {
      rules = {
         {
            ethertype = "ipv6",
            state_check = 'dns_v6',
            protocol = "udp",
         },
      },
   })
   config.app(c, "sink1", basic_apps.Sink )
   config.link(c, "source1.output -> statefull_pass1.input")
   config.link(c, "statefull_pass1.output -> sink1.input")

   -- checks a whole app's tracked state
   config.app(c, "source2", pcap.PcapReader, "apps/packet_filter/samples/v4.pcap")
   config.app(c, "statefull_pass2", PacketFilter, { state_check = 'app_v4' })
   config.app(c, "sink2", basic_apps.Sink )
   config.link(c, "source2.output -> statefull_pass2.input")
   config.link(c, "statefull_pass2.output -> sink2.input")
   engine.configure(c)

   engine.breathe()
   engine.report()
--    print (conntrack.dump())

   if engine.app_table.statefull_pass1.output.output.stats.txpackets ~= 6 then
      ok = false
      print ("state dns_v6 failed")
   end
   if engine.app_table.statefull_pass2.output.output.stats.txpackets ~= 36 then
      ok = false
      print ("state app_v4 failed")
   end

   -- part 3:
   engine.configure(config.new())
   c = config.new()

   config.app(c, "source1", pcap.PcapReader, "apps/packet_filter/samples/v4-tcp-udp.pcap")
   config.app(c, "stateless_pass1", PacketFilter, {
      rules = {
         {
            ethertype = "ipv4",
            dest_port_min = 12345,
            protocol = "tcp",
         },
      },
   })
   config.app(c, "sink1", basic_apps.Sink )
   config.link(c, "source1.output -> stateless_pass1.input")
   config.link(c, "stateless_pass1.output -> sink1.input")

   engine.configure(c)
   engine.breathe()
   engine.report()

   if engine.app_table.stateless_pass1.output.output.stats.txpackets ~= 1 then
      ok = false
      print ("stateless tcp failed")
   end

   engine.configure(config.new())
   c = config.new()

   config.app(c, "source1", pcap.PcapReader, "apps/packet_filter/samples/v6-tcp-udp.pcap")
   config.app(c, "stateless_pass1", PacketFilter, {
      rules = {
         {
            ethertype = "ipv6",
            dest_port_min = 1022,
            protocol = "tcp",
         },
      },
   })
   config.app(c, "sink1", basic_apps.Sink )
   config.link(c, "source1.output -> stateless_pass1.input")
   config.link(c, "stateless_pass1.output -> sink1.input")

   engine.configure(c)
   engine.breathe()
   engine.report()

   if engine.app_table.stateless_pass1.output.output.stats.txpackets ~= 1 then
      ok = false
      print ("stateless v6 tcp failed")
   end


   if not ok then
      print("selftest failed")
      os.exit(1)
   end
   print("selftest passed")
end


function microbench()
   math.randomseed(os.time())
   local tab = {}
   local count = 0
   local function set(spec)
      if count > 1e6 then return end
      local k = conntrack.spec_tostring(spec)
      if tab[k] == nil then count = count+1 end
      tab[k] = true
   end
   local function work(n)
      local spec = conntrack.randspec()
      local t = C.get_time_ns()
      for i = 1, n do
         set(spec)
         spec = conntrack.randspec(spec)
      end
--       collectgarbage('step')
      t = C.get_time_ns() - t
      return 1000*n/tonumber(t)
   end

   for i=1,100 do
      print (string.format('base time %d: %g M/s (n=%d)', i, work(1e5), count))
   end
end

function simplebench()
   math.randomseed(os.time())
   local p1 = packet.from_string(lib.hexundump ([[
      52:54:00:02:02:02 52:54:00:01:01:01 08 00 45 00
      00 54 c3 cd 40 00 40 17 f3 23 c0 a8 01 66 c0 a8
      01 01 00 35 00 35 61 1a 00 06 5c ba 16 53 00 00
      00 00 04 15 09 00 00 00 00 00 10 11 12 13 14 15
      16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25
      26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35
      36 37
   ]], 98))

   local function randpackt(p1)
      local ips = ffi.cast('uint32_t*', p1.data+IPV4_SOURCE_OFFSET)
      ips[0] = math.random(2000) --2^32)
      ips[1] = math.random(2000) --2^32)
      local ports = ffi.cast('uint16_t*', p1.data+IPV4_SOURCE_PORT_OFFSET)
      ports[0] = math.random(2^16)
      ports[1] = math.random(2^16)
      return ffi.string(p1.data, p1.length)
   end
   conntrack.define('bench')
   local function work(n)
      local t = C.get_time_ns()
      for i = 1, n do
         randpackt(p1)
         conntrack.track('bench', p1.data)
      end
--       collectgarbage('step')
      t = C.get_time_ns() - t
      return 1000*n/tonumber(t)
   end
   for i=1,100 do
      print (string.format('packet base time %d: %g M/s (n=%d)', i, work(1e5), conntrack.count('bench')))
   end
end


return {
   PacketFilter = PacketFilter,
   new_spec = new_spec,
   selftest = selftest,
}

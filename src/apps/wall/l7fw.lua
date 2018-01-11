module(..., package.seeall)

-- This module implements a level 7 firewall app that consumes the result
-- of DPI scanning done by l7spy.
--
-- The firewall rules are a table mapping protocol names to either
--   * a simple action ("drop", "reject", "accept")
--   * a pfmatch expression

local bit      = require("bit")
local ffi      = require("ffi")
local link     = require("core.link")
local packet   = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ether    = require("lib.protocol.ethernet")
local icmp     = require("lib.protocol.icmp.header")
local ipv4     = require("lib.protocol.ipv4")
local ipv6     = require("lib.protocol.ipv6")
local tcp      = require("lib.protocol.tcp")
local match    = require("pf.match")

ffi.cdef[[
  void syslog(int priority, const char*format, ...);
]]

-- constants from <syslog.h> for syslog priority argument
local LOG_USER = 8
local LOG_INFO = 6

-- network constants
local ETHER_PROTO_IPV4 = 0x0800
local ETHER_PROTO_IPV6 = 0x86dd

local IP_PROTO_ICMPV4 = 1
local IP_PROTO_TCP    = 6
local IP_PROTO_ICMPV6 = 58

L7Fw = {}
L7Fw.__index = L7Fw

-- create a new firewall app object given an instance of Scanner
-- and firewall rules
function L7Fw:new(config)
   local obj = { local_ipv4 = config.local_ipv4,
                 local_ipv6 = config.local_ipv6,
                 local_macaddr = config.local_macaddr,
                 scanner = config.scanner,
                 rules = config.rules,
                 -- this map tracks flows to compiled pfmatch functions
                 -- so that we only compile them once per flow
                 handler_map = {},
                 -- log level for logging filtered packets
                 logging = config.logging or "off",
                 -- for stats
                 accepted = 0,
                 rejected = 0,
                 dropped = 0,
                 total = 0 }
   assert(obj.logging == "on" or obj.logging == "off",
          ("invalid log level: %s"):format(obj.logging))
   return setmetatable(obj, self)
end

-- called by pfmatch handlers, just drop the packet on the floor
function L7Fw:drop(pkt, len)
   if self.logging == "on" then
      self:log_packet("DROP")
   end

   packet.free(self.current_packet)
   self.dropped = self.dropped + 1
end

-- called by pfmatch handler, handle rejection response
function L7Fw:reject(pkt, len)
   link.transmit(self.output.reject, self:make_reject_response())
   self.rejected = self.rejected + 1

   if self.logging == "on" then
      self:log_packet("REJECT")
   end

   packet.free(self.current_packet)
end

-- called by pfmatch handler, forward packet
function L7Fw:accept(pkt, len)
   link.transmit(self.output.output, self.current_packet)
   self.accepted = self.accepted + 1
end

function L7Fw:push()
   local i       = assert(self.input.input, "input port not found")
   local o       = assert(self.output.output, "output port not found")
   local rules   = self.rules
   local scanner = self.scanner

   assert(self.output.reject, "output port for reject policy not found")

   while not link.empty(i) do
      local pkt  = link.receive(i)
      local flow = scanner:get_flow(pkt)

      -- so that pfmatch handler methods can access the original packet
      self.current_packet = pkt

      self.total = self.total + 1

      if flow then
         local name   = scanner:protocol_name(flow.protocol)
         local policy = rules[name] or rules["default"]

         self.current_protocol = name

         if policy == "accept" then
            self:accept(pkt.data, pkt.length)
         elseif policy == "drop" then
            self:drop(pkt.data, pkt.length)
         elseif policy == "reject" then
            self:reject(pkt.data, pkt.length)
         -- handle a pfmatch string case
         elseif type(policy) == "string" then
            if self.handler_map[policy] then
               -- we've already compiled a matcher for this policy
               self.handler_map[policy](self, pkt.data, pkt.length, flow.packets)
            else
               local opts    = { extra_args = { "flow_count" } }
               local handler = match.compile(policy, opts)
               self.handler_map[policy] = handler
               handler(self, pkt.data, pkt.length, flow.packets)
            end
         -- TODO: what should the default policy be if there is none specified?
         else
            self:accept(pkt.data, pkt.length)
         end
      else
         -- TODO: we may wish to have a default policy for packets
         --       without detected flows instead of just forwarding
         self:accept(pkt.data, pkt.length)
      end
   end
end

function L7Fw:report()
   local accepted, rejected, dropped =
      self.accepted, self.rejected, self.dropped
   local total = self.total
   local a_pct = math.ceil((accepted / total) * 100)
   local r_pct = math.ceil((rejected / total) * 100)
   local d_pct = math.ceil((dropped / total) * 100)
   print(("Accepted packets: %d (%d%%)"):format(accepted, a_pct))
   print(("Rejected packets: %d (%d%%)"):format(rejected, r_pct))
   print(("Dropped packets:  %d (%d%%)"):format(dropped, d_pct))
end

local logging_priority = bit.bor(LOG_USER, LOG_INFO)

function L7Fw:log_packet(type)
   local pkt      = self.current_packet
   local protocol = self.current_protocol
   local eth_h    = assert(ether:new_from_mem(pkt.data, pkt.length))
   local ip_h

   if eth_h:type() == ETHER_PROTO_IPV4 then
      ip_h = ipv4:new_from_mem(pkt.data + eth_h:sizeof(),
                               pkt.length - eth_h:sizeof())
   elseif eth_h:type() == ETHER_PROTO_IPV6 then
      ip_h = ipv6:new_from_mem(pkt.data + eth_h:sizeof(),
                               pkt.length - eth_h:sizeof())
   end
   assert(ip_h)

   local msg = string.format("[Snabbwall %s] PROTOCOL=%s MAC=%s SRC=%s DST=%s",
                             type, protocol,
                             ether:ntop(eth_h:src()),
                             ip_h:ntop(ip_h:src()),
                             ip_h:ntop(ip_h:dst()))
   ffi.C.syslog(logging_priority, msg)
end

-- create either an ICMP port unreachable packet or a TCP RST to
-- send in case of a reject policy
function L7Fw:make_reject_response()
   local pkt        = self.current_packet
   local ether_orig = assert(ether:new_from_mem(pkt.data, pkt.length))
   local ip_orig

   if ether_orig:type() == ETHER_PROTO_IPV4 then
      ip_orig = ipv4:new_from_mem(pkt.data + ether_orig:sizeof(),
                                  pkt.length - ether_orig:sizeof())
   elseif ether_orig:type() == ETHER_PROTO_IPV6 then
      ip_orig = ipv6:new_from_mem(pkt.data + ether_orig:sizeof(),
                                  pkt.length - ether_orig:sizeof())
   else
      -- no responses to non-IP packes
      return
   end
   assert(ip_orig)

   local is_tcp  = false
   local ip_protocol

   if ip_orig:version() == 4 then
      if ip_orig:protocol() == 6 then
         is_tcp = true
         ip_protocol = IP_PROTO_TCP
      else
         ip_protocol = IP_PROTO_ICMPV4
      end
   else
      if ip_orig:next_header() == 6 then
         is_tcp = true
         ip_protocol = IP_PROTO_TCP
      else
         ip_protocol = IP_PROTO_ICMPV6
      end
   end

   local dgram = datagram:new()
   local ether_h, ip_h

   if ip_orig:version() == 4 then
      ether_h = ether:new({ dst = ether_orig:src(),
                            src = self.local_macaddr,
                            type = ETHER_PROTO_IPV4 })
      assert(self.local_ipv4, "config is missing local_ipv4")
      ip_h = ipv4:new({ dst = ip_orig:src(),
                        src = ipv4:pton(self.local_ipv4),
                        protocol = ip_protocol,
                        ttl = 64 })
   else
      ether_h = ether:new({ dst = ether_orig:src(),
                            src = self.local_macaddr,
                            type = ETHER_PROTO_IPV6 })
      assert(self.local_ipv6, "config is missing local_ipv6")
      ip_h = ipv6:new({ dst = ip_orig:src(),
                        src = ipv6:pton(self.local_ipv6),
                        next_header = ip_protocol,
                        ttl = 64 })
   end

   if is_tcp then
      local tcp_orig = tcp:new_from_mem(pkt.data + ether_orig:sizeof() +
                                        ip_orig:sizeof(),
                                        pkt.length - ether_orig:sizeof() -
                                        ip_orig:sizeof())
      assert(tcp_orig)
      local tcp_h    = tcp:new({src_port = tcp_orig:dst_port(),
                                dst_port = tcp_orig:src_port(),
                                seq_num  = tcp_orig:seq_num() + 1,
                                ack_num  = tcp_orig:ack_num() + 1,
                                ack      = 1,
                                rst      = 1,
                                -- minimum TCP header size is 5 words
                                offset   = 5 })

      -- checksum needs a non-nil first argument, but we have zero payload bytes
      -- so give a bogus value
      tcp_h:checksum(ffi.new("uint8_t[0]"), 0)
      dgram:push(tcp_h)
      if ip_h:version() == 4 then
         ip_h:total_length(ip_h:sizeof() + tcp_h:sizeof())
      else
         ip_h:payload_length(ip_h:sizeof() + tcp_h:sizeof())
      end
   else
      local icmp_h

      if ip_h:version() == 4 then
         -- ICMPv4 code & type for "port unreachable"
         icmp_h = icmp:new(3, 3)
      else
         -- ICMPv6 code & type for "administratively prohibited"
         icmp_h = icmp:new(1, 1)
      end

      dgram:payload(ffi.new("uint8_t [4]"), 4)

      if ip_h:version() == 4 then
         dgram:payload(ip_orig:header(), ip_orig:sizeof())
         -- ICMPv4 port unreachable errors come with the original IPv4
         -- header and 8 bytes of the original payload
         dgram:payload(pkt.data + ether_orig:sizeof() + ip_orig:sizeof(), 8)

         icmp_h:checksum(dgram:payload())
         dgram:push(icmp_h)

         ip_h:total_length(ip_h:sizeof() + icmp_h:sizeof() +
                           4 + -- extra zero bytes
                           ip_orig:sizeof() + 8)
      else
         -- ICMPv6 destination unreachable packets contain up to 1232 bytes
         -- of the original packet
         -- (the minimum MTU 1280 - IPv6 header length - ICMPv6 header)
         local payload_len =
            math.min(1232, pkt.length - ether_orig:sizeof() - ip_orig:sizeof())
         dgram:payload(ip_orig:header(), ip_orig:sizeof())
         dgram:payload(pkt.data + ether_orig:sizeof() + ip_orig:sizeof(),
                       payload_len)

         local mem, len = dgram:payload()
         icmp_h:checksum(mem, len, ip_h)
         dgram:push(icmp_h)

         ip_h:payload_length(icmp_h:sizeof() +
                             4 + -- extra zero bytes
                             ip_orig:sizeof() + payload_len)
      end
   end

   dgram:push(ip_h)
   dgram:push(ether_h)

   return dgram:packet()
end

function selftest()
   local savefile = require("pf.savefile")
   local pflua    = require("pf")

   local function test(name, packet, pflang)
      local fake_self = { local_ipv4 = "192.168.42.42",
                          local_ipv6 = "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
                          local_macaddr = "01:23:45:67:89:ab",
                          current_packet = { data = packet.packet,
                                             length = packet.len } }
      local response  = L7Fw.make_reject_response(fake_self)
      local pred      = pf.compile_filter(pflang)

      assert(pred(response.data, response.length),
             string.format("test %s failed", name))
   end

   local base_dir = "./program/wall/tests/data/"
   local dhcp     = savefile.load_packets(base_dir .. "dhcp.pcap")
   local dhcpv6   = savefile.load_packets(base_dir .. "dhcpv6.pcap")
   local v4http   = savefile.load_packets(base_dir .. "http.cap")
   local v6http   = savefile.load_packets(base_dir .. "v6-http.cap")

   test("icmpv4-1", dhcp[2], [[ether proto ip]])
   test("icmpv4-2", dhcp[2], [[ip proto icmp]])
   test("icmpv4-3", dhcp[2], [[icmp and dst net 192.168.0.1]])
   test("icmpv4-3", dhcp[2], [[icmp[icmptype] = 3 and icmp[icmpcode] = 3]])

   test("icmpv6-1", dhcpv6[1], [[ether proto ip6]])
   -- TODO: ip6 protochain is not implemented in pflang
   --test("icmpv6-2", dhcpv6[1], [[ip6 protochain 58]])
   -- it would be nice to test the icmp type & code here, but pflang
   -- does not have good support for dereferencing ip6 protocols
   test("icmpv6-3", dhcpv6[1], [[icmp6 and dst net fe80::a00:27ff:fefe:8f95]])

   test("tcpv4-1", v4http[5], [[ether proto ip]])
   test("tcpv4-2", v4http[5], [[tcp and tcp[tcpflags] & (tcp-rst|tcp-ack) != 0]])

   test("tcpv6-1", v6http[50], [[ether proto ip6]])
   test("tcpv6-2", v6http[50], [[tcp]])

   print("selftest ok")
end

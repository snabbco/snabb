module(..., package.seeall)

-- This module implements a level 7 firewall app that consumes the result
-- of DPI scanning done by l7spy.
--
-- The firewall rules are a table mapping protocol names to either
--   * a simple action ("drop", "reject", "accept")
--   * a pfmatch expression

local ffi      = require("ffi")
local link     = require("core.link")
local packet   = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ether    = require("lib.protocol.ethernet")
local icmp     = require("lib.protocol.icmp.header")
local ipv4     = require("lib.protocol.ipv4")
local tcp      = require("lib.protocol.tcp")
local match    = require("pf.match")

L7Fw = {}
L7Fw.__index = L7Fw

-- create a new firewall app object given an instance of Scanner
-- and firewall rules
function L7Fw:new(config)
   local obj = { local_ip = config.local_ip,
                 local_macaddr = config.local_macaddr,
                 scanner = config.scanner,
                 rules = config.rules,
                 -- this map tracks flows to compiled pfmatch functions
                 -- so that we only compile them once per flow
                 handler_map = {} }
   return setmetatable(obj, self)
end

-- called by pfmatch handlers, just drop the packet on the floor
function L7Fw:drop(pkt, len)
   packet.free(self.current_packet)
   return
end

-- called by pfmatch handler, handle rejection response
function L7Fw:reject(pkt, len)
   if self.local_ip and self.local_macaddr then
      link.transmit(assert(self.output.reject,
                           "output port for reject policy not found"),
                    self:make_reject_response())
   end
   packet.free(self.current_packet)
end

-- called by pfmatch handler, forward packet
function L7Fw:accept(pkt, len)
   link.transmit(self.output.output, self.current_packet)
end

function L7Fw:push()
   local i       = assert(self.input.input, "input port not found")
   local o       = assert(self.output.output, "output port not found")
   local rules   = self.rules
   local scanner = self.scanner

   while not link.empty(i) do
      local pkt  = link.receive(i)
      local flow = scanner:get_flow(pkt)

      -- so that pfmatch handler methods can access the original packet
      self.current_packet = pkt

      if flow then
         local name   = scanner:protocol_name(flow.protocol)
         local policy = rules[name] or rules["default"]

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
         link.transmit(o, pkt)
      end
   end
end

-- create either an ICMP port unreachable packet or a TCP RST to
-- send in case of a reject policy
function L7Fw:make_reject_response()
   local pkt        = self.current_packet
   local ether_orig = ether:new_from_mem(pkt.data, pkt.length)
   local ipv4_orig  = ipv4:new_from_mem(pkt.data + ether_orig:sizeof(),
                                        pkt.length - ether_orig:sizeof())

   local is_tcp = false
   local ip_protocol

   if ipv4_orig:protocol() == 6 then
      is_tcp = true
      ip_protocol = 6
   else
      ip_protocol = 1 -- ICMPv4
   end

   local dgram   = datagram:new()
   local ether_h = ether:new({ dst = ether_orig:src(),
                               src = self.local_macaddr,
                               type = 0x0800 })
   local ipv4_h  = ipv4:new({ dst = ipv4_orig:src(),
                              src = ipv4:pton(self.local_ip),
                              protocol = ip_protocol,
                              ttl = 64 })

   if is_tcp then
      local tcp_orig = tcp:new_from_mem(pkt.data + ether_orig:sizeof() +
                                        ipv4_orig:sizeof(),
                                        pkt.length - ether_orig:sizeof() -
                                        ipv4_orig:sizeof())
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
      ipv4_h:total_length(ipv4_h:sizeof() + tcp_h:sizeof())
   else
      local icmp_h  = icmp:new(3, 3)

      dgram:payload(ffi.new("uint8_t [4]"), 4)
      dgram:payload(ipv4_orig:header(), ipv4_orig:sizeof())
      dgram:payload(pkt.data + ether_orig:sizeof() + ipv4_orig:sizeof(), 8)

      icmp_h:checksum(dgram:payload())
      dgram:push(icmp_h)
      ipv4_h:total_length(ipv4_h:sizeof() + icmp_h:sizeof() +
                          4 + -- extra zero bytes
                          ipv4_orig:sizeof() + 8)
   end

   dgram:push(ipv4_h)
   dgram:push(ether_h)

   return dgram:packet()
end

-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This app acts as a responder for neighbor solicitaions for a
-- specific target address and as a relay for all other packets.  It
-- has two ports, north and south.  The south port attaches to a port
-- on which NS messages are expected.  Non-NS packets are sent on
-- north.  All packets received on the north port are passed south.

module(..., package.seeall)
local ffi = require("ffi")
local app = require("core.app")
local link = require("core.link")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local icmp = require("lib.protocol.icmp.header")
local ns = require("lib.protocol.icmp.nd.ns")
local filter = require("lib.pcap.filter")

ns_responder = subClass(nil)
ns_responder._name = "ipv6 neighbor solicitation responder"

function ns_responder:new(config)
   local o = ns_responder:superClass().new(self)
   o._config = config
   o._match_ns = function(ns)
                    return(ns:target_eq(config.local_ip))
                 end
   local filter, errmsg = filter:new("icmp6 and ip6[40] = 135")
   assert(filter, errmsg and ffi.string(errmsg))
   o._filter = filter
   o._dgram = datagram:new()
   packet.free(o._dgram:packet())
   return o
end

local function process (self, p)
   if not self._filter:match(p.data, p.length) then
      return false
   end
   local dgram = self._dgram:new(p, ethernet)
   -- Parse the ethernet, ipv6 amd icmp headers
   dgram:parse_n(3)
   local eth, ipv6, icmp = unpack(dgram:stack())
   local payload, length = dgram:payload()
   if not icmp:checksum_check(payload, length, ipv6) then
      print(self:name()..": bad icmp checksum")
      return nil
   end
   -- Parse the neighbor solicitation and check if it contains our own
   -- address as target
   local ns = dgram:parse_match(nil, self._match_ns)
   if not ns then
      return nil
   end
   local option = ns:options(dgram:payload())
   if not (#option == 1 and option[1]:type() == 1) then
      -- Invalid NS, ignore
      return nil
   end
   -- Turn this message into a solicited neighbor
   -- advertisement with target ll addr option

   -- Ethernet
   eth:swap()
   eth:src(self._config.local_mac)

   -- IPv6
   ipv6:dst(ipv6:src())
   ipv6:src(self._config.local_ip)

   -- ICMP
   option[1]:type(2)
   option[1]:option():addr(self._config.local_mac)
   icmp:type(136)
   -- Undo/redo icmp and ns headers to get
   -- payload and set solicited flag
   dgram:unparse(2)
   dgram:parse() -- icmp
   local payload, length = dgram:payload()
   dgram:parse():solicited(1)
   icmp:checksum(payload, length, ipv6)
   return true
end

function ns_responder:push()
   local l_in = self.input.north
   local l_out = self.output.south
   if l_in and l_out then
      while not link.empty(l_in) do
         -- Pass everything on north -> south
         link.transmit(l_out, link.receive(l_in))
      end
   end
   l_in = self.input.south
   l_out = self.output.north
   local l_reply = self.output.south
   while not link.empty(l_in) do
      local p = link.receive(l_in)
      local status = process(self, p)
      if status == nil then
         -- Discard
         packet.free(p)
      elseif status == true then
         -- Send NA back south
         link.transmit(l_reply, p)
      else
         -- Send transit traffic up north
         link.transmit(l_out, p)
      end
   end
end

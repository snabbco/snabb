-- This app acts as a responder for neighbor solicitaions for a
-- specific target address and as a relay for all other packets.  It
-- has two ports, north and south.  The south port attaches to a port
-- on which NS messages are expected.  Non-NS packets are sent on
-- north.  All packets received on the north port are passed south.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local app = require("core.app")
local link = require("core.link")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local icmp = require("lib.protocol.icmp.header")
local ns = require("lib.protocol.icmp.nd.ns")
local matcher = require("lib.protocol.matcher")

local ns_responder = subClass(nil)

function ns_responder:new(config)
   local o = ns_responder:superClass().new(self)
   o._config = config
   o._match_ns = function(ns)
		    return(ns:target_eq(config.local_ip))
		 end
   o._matcher = matcher:new()
   o._matcher:add(12, 2, ffi.new("uint16_t[1]", ffi.C.htons(0x86dd))) -- ipv6
   o._matcher:add(20, 1, ffi.new("uint8_t[1]", 58)) -- icmp
   o._matcher:add(54, 1, ffi.new("uint8_t[1]", 135)) -- neighbor solicitation
   return o
end

local function process(self, dgram)
   if not self._matcher:compare(dgram:payload()) then
      return false
   end
   -- Parse the ethernet, ipv6 amd icmp headers
   --dgram:parse_n(3)
   dgram:parse_seq({ {}, {}, {} })
   local eth, ipv6, icmp = unpack(dgram:stack())
   -- Parse the neighbor solicitation and check if it contains our own
   -- address as target
   local ns = dgram:parse(nil, self._match_ns)
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
   assert(l_in and l_out)
   while not link.empty(l_in) and not link.full(l_out) do
      -- Pass everything on north -> south
      link.transmit(l_out, link.receive(l_in))
   end
   l_in = self.input.south
   l_out = self.output.north
   local l_reply = self.output.south
   while not link.empty(l_in) and not link.full(l_out) do
      local p = link.receive(l_in)
      local datagram = datagram:new(p, ethernet)
      local status = process(self, datagram)
      if status == nil then
	 -- Discard
	 packet.deref(p)
      elseif status == true then
	 -- Send NA back south
	 link.transmit(l_reply, p)
      else
	 -- Send transit traffic up north
	 link.transmit(l_out, p)
      end
      datagram:free()
   end
end

return ns_responder

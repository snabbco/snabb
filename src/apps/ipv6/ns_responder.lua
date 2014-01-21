-- This app acts as a responder for neighbor solicitaions for a
-- specific target address and as a relay for all other packets.  It
-- has two ports, north and south.  The south port attaches to a port
-- on which NS messages are expected.  Non-NS packets are sent on
-- north.  All packets received on the north port are passed south.

require("class")
local ffi = require("ffi")
local app = require("core.app")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local icmp = require("lib.protocol.icmp.header")
local ns = require("lib.protocol.icmp.nd.ns")

local ns_responder = subClass(nil)

function ns_responder:_init_new(target, lladdr)
   self._target = target
   self._lladdr = lladdr
end

local function process(self, dgram)
   if dgram:parse(
      { { ethernet },
	{ ipv6 },
	{ icmp },
	{ ns,
	  function(ns)
	     return(ns:target_eq(self._target))
	  end } }) then
      local eth, ipv6, icmp, ns = unpack(dgram:stack())
      local option = ns:options(dgram:payload())
      if not (#option == 1 and option[1]:type() == 1) then
	 -- Invalid NS, ignore
	 return nil
      end
      -- Turn this message into a solicited neighbor
      -- advertisement with target ll addr option
      
      -- Ethernet
      eth:swap()
      eth:src(self._lladdr)
      
      -- IPv6
      ipv6:dst(ipv6:src())
      ipv6:src(self._target)
      
      -- ICMP
      option[1]:type(2)
      option[1]:option():addr(self._lladdr)
      icmp:type(136)
      -- Undo/redo icmp and ns headers to obtain
      dgram:unparse(2)
      dgram:parse() -- icmp
      local payload, length = dgram:payload()
      dgram:parse():solicited(1)
      icmp:checksum(payload, length, ipv6)
      return true
   end
   return false
end

function ns_responder:push()
   local l_in = self.input.north
   local l_out = self.output.south
   assert(l_in and l_out)
   while not app.empty(l_in) and not app.full(l_out) do
      -- Pass everything on north -> south
      app.transmit(l_out, app.receive(l_in))
   end
   l_in = self.input.south
   l_out = self.output.north
   local l_reply = self.output.south
   while not app.empty(l_in) and not app.full(l_out) do
      local p = app.receive(l_in)
      local datagram = datagram:new(p, ethernet)
      local status = process(self, datagram)
      if status == nil then
	 -- Discard
	 packet.deref(p)
      elseif status == true then
	 -- Send NA back south
	 app.transmit(l_reply, p)
      else
	 -- Send transit traffic up north
	 app.transmit(l_out, p)
      end
   end
end

return ns_responder

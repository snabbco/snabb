-- This class derives from lib.bridge.base and implements the simplest
-- possible bridge, which floods a packet arriving on a port to all
-- destination ports within its scope according to the split-horizon
-- topology.

module(..., package.seeall)

local bridge_base = require("apps.bridge.base").bridge
local packet = require("core.packet")
local link = require("core.link")
local empty, receive, transmit = link.empty, link.receive, link.transmit
local clone = packet.clone

bridge = subClass(bridge_base)
bridge._name = "flooding bridge"

function bridge:new (arg)
   return bridge:superClass().new(self, arg)
end

function bridge:push()
   local src_ports = self._src_ports
   local dst_ports = self._dst_ports
   local output = self.output
   local i = 1
   while src_ports[i] do
      local src_port = src_ports[i]
      local l_in = self.input[src_port]
      while not empty(l_in) do
	 local ports = dst_ports[src_port]
	 local p = receive(l_in)
	 transmit(output[ports[1]], p)
	 local j = 2
	 while ports[j] do
	    transmit(output[ports[j]], clone(p))
	    j = j + 1
	 end
      end
      i = i + 1
   end
end

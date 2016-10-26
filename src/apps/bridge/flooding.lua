-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

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
   local ports = self._ports
   local dst_ports = self._dst_ports
   local i = 1
   while ports[i] do
      local l_in = ports[i].l_in
      while not empty(l_in) do
         local dst = dst_ports[i]
         local p = receive(l_in)
         transmit(ports[dst[1]].l_out, p)
         local j = 2
         while dst[j] do
            transmit(ports[dst[j]].l_out, clone(p))
            j = j + 1
         end
      end
      i = i + 1
   end
end

-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- This app relays packets between its "nort" and "south" links and
-- copies fixed src and dst MAC addresses to the Ethernet header of
-- all packets coming in from "north".

module(..., package.seeall)
local ffi = require("ffi")
local link = require("core.link")
local ethernet = require("lib.protocol.ethernet")

nd_static = subClass(nil)
nd_static._name = "static ND"

function _new (self, config)
   assert(config and config.local_mac and config.remote_mac)
   self._eth:src(config.local_mac)
   self._eth:dst(config.remote_mac)
   return self
end

function nd_static:new (config)
   local o = nd_static:superClass().new(self)
   o._eth = ethernet:new({ type = 0x86dd })
   o._header = o._eth:header()
   return _new(o, config)
end

function nd_static:reconfig (config)
   return _new(self, config)
end

local empty, receive, transmit = link.empty, link.receive, link.transmit
function nd_static:push()
   local l_in = self.input.north
   local l_out = self.output.south
   if l_in and l_out then
      while not empty(l_in) do
         -- Insert the static Ethernet header
         local p = receive(l_in)
         ffi.copy(p.data, self._header, 14)
         transmit(l_out, p)
      end
   end
   l_in = self.input.south
   l_out = self.output.north
   while not empty(l_in) do
      -- Pass all packets unchanged souh -> north 
      transmit(l_out, receive(l_in))
   end
end

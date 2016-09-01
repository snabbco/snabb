-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ethernet = require("lib.protocol.ethernet")
local C = require("ffi").C

MacFilter = {}

local ADDRESS_SIZE = 6
local SRC_OFFSET = ADDRESS_SIZE
local ETHERNET_SIZE = ethernet:sizeof()

function MacFilter:new (mac)
   return setmetatable({mac=ethernet:pton(mac)}, {__index=MacFilter})
end

function MacFilter:push ()
   local mac = self.mac
   local l_in  = assert(self.input.south,  "No input link on south.")
   local l_out = assert(self.output.north, "No output link on north.")
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      if p.length < ETHERNET_SIZE
         or C.memcmp(mac, p.data, ADDRESS_SIZE) ~= 0 then
         packet.free(p)
      else
         link.transmit(l_out, p)
      end
   end
   local l_in  = assert(self.input.north,  "No input link on north.")
   local l_out = assert(self.output.south, "No output link on south.")
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      if p.length < ETHERNET_SIZE
         or C.memcmp(dmac, p.data+SRC_OFFSET, ADDRESS_SIZE) ~= 0 then
         packet.free(p)
      else
         link.transmit(l_out, p)
      end
   end
end

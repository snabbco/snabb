-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local counter = require("core.counter")
local bridge_base = require("apps.bridge.base").bridge

local ffi = require("ffi")
local ethernet = require("lib.protocol.ethernet")
local eth_ptr_t = ffi.typeof("$*", ethernet:ctype())

local nreadable, receive, transmit = link.nreadable, link.receive, link.transmit

bridge = subClass(bridge_base)
bridge._name = "flooding bridge"
bridge.shm = {
   ["packets-flooded"] = { counter },
   ["packets-discarded"] = { counter },
}

function bridge:new (conf)
   return bridge:superClass().new(self, conf)
end

function bridge:push(link, port)
   for _ = 1, nreadable(link) do
      -- Use a box to transport the packet into the inner loop when it
      -- gets compiled first to avoid garbage
      self.box[0] = receive(link)
      transmit(port.egress[0], self.box[0])
      for index = 1, self.max_index do
         transmit(port.egress[index], packet.clone(self.box[0]))
      end
      counter.add(self.shm["packets-flooded"])
   end

   for _ = 1, nreadable(self.discard) do
      packet.free(receive(self.discard))
      counter.add(self.shm["packets-discarded"])
   end
end

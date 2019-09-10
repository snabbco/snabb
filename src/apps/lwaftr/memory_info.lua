-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local counter = require("core.counter")
local lib = require("core.lib")

MemoryCounter = {
   config = {
      update_interval = {default=1}, -- 1 second
   },
   shm = {
      bytes_in_use = {counter}
   }
}

function MemoryCounter:new (conf)
   local self = {}
   self.pdp_timer = lib.throttle(conf.update_interval)
   return setmetatable(self, {__index=MemoryCounter})
end

function MemoryCounter:pull ()
   if self.pdp_timer() then
      counter.set(self.shm.bytes_in_use, math.floor(collectgarbage('count')*1024))
   end
end

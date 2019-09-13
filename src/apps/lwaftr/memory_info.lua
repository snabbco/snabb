-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local gauge = require("lib.gauge")
local lib = require("core.lib")

-- MemoryGauge: an app that does nothing except expose a gauge to reflect the
-- current memory use of the executing process.

MemoryGauge = {
   config = {
      update_interval = {default=1}, -- 1 second
   },
   shm = {
      kbytes_in_use = {gauge}
   }
}

function MemoryGauge:new (conf)
   local self = {}
   self.pdp_timer = lib.throttle(conf.update_interval)
   return setmetatable(self, {__index=MemoryGauge})
end

function MemoryGauge:pull ()
   if self.pdp_timer() then
      gauge.set(self.shm.kbytes_in_use, collectgarbage('count'))
   end
end

-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local rrd = require("lib.rrd")
local shm = require("core.shm")
local lib = require("core.lib")

MemoryLog = {
   config = {
      rrd_name = {default="memory_log.rrd"},
      pdp_interval = {default=1}, -- 1 second
      archive_duration = {default=5*60*60} -- 5 hours
   }
}

function MemoryLog:new (conf)
   local self = {}
   self.pdp_timer = lib.throttle(conf.pdp_interval)
   self.rrd = rrd.create_shm(conf.rrd_name, {
      base_interval = ("%ds"):format(conf.pdp_interval),
      sources = {
         {
            name = 'kbytes-in-use',
            type = 'gauge',
            interval = ("%ds"):format(conf.pdp_interval*2),
            min = 0.0
         }
      },
      archives = {
         {
            cf = 'last',
            duration = ("%ds"):format(conf.archive_duration),
            interval = ("%ds"):format(conf.pdp_interval)
         }
      }
   })
   return setmetatable(self, {__index=MemoryLog})
end

function MemoryLog:pull ()
   if self.pdp_timer() then
      self.rrd:add{ ['kbytes-in-use'] = collectgarbage('count') }
   end
end

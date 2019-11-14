-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- HeapSizeMonitor: periodically update a gauge to reflect the current
-- memory use of the executing process.

local gauge = require("lib.gauge")
local lib = require("core.lib")
local shm = require("core.shm")

local params = {
   path={default='engine/memory_gc_heap_bytes'},
}

HeapSizeMonitor = {}

-- Once per second.
local default_interval = 1e9

function HeapSizeMonitor.new(args)
   args = lib.parse(args, params);
   if not args.path:match(".gauge") then
      args.path = args.path..".gauge"
   end
   
   local self = {}
   if not shm.exists(args.path) then
      self.heap_size = gauge.create(args.path)
   else
      self.heap_size = gauge.open(args.path)
   end

   return setmetatable(self, {__index=HeapSizeMonitor})
end

function HeapSizeMonitor:sample ()
   -- collectgarbage('count') returns a value in kilobytes; convert to
   -- bytes.
   gauge.set(self.heap_size, collectgarbage('count') * 1024)
end

function HeapSizeMonitor:timer(interval)
   return timer.new("heap size monitor",
                    function () self:sample() end,
                    interval or default_interval,
                    "repeating")
end

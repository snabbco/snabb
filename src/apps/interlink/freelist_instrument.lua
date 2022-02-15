-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local histogram = require("core.histogram")
local rdtsc = require("lib.tsc").rdtsc

function instrument_freelist ()
   local rebalance_latency = histogram.create('engine/rebalance_latency.histogram', 1, 1e9)
   local allocate_latency = histogram.create('engine/allocate_latency.histogram', 1, 1e9)
   
   local rebalance_freelists, allocate = packet.rebalance_freelists, packet.allocate
   packet.rebalance_freelists = function ()
      local start = rdtsc()
      rebalance_freelists()
      rebalance_latency:add(tonumber(rdtsc()-start))
   end
   packet.allocate = function ()
      local start = rdtsc()
      local p = allocate()
      allocate_latency:add(tonumber(rdtsc()-start))
      return p
   end
   
   return rebalance_latency, allocate_latency
end

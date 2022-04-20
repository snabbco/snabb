-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local histogram = require("core.histogram")
local tsc = require("lib.tsc")

function instrument_freelist ()
   local ts = tsc.new()
   local rebalance_latency = histogram.create('engine/rebalance_latency.histogram', 1, 100e6)
   local reclaim_latency = histogram.create('engine/reclaim_latency.histogram', 1, 100e6)
   
   local rebalance_step, reclaim_step = packet.rebalance_step, packet.reclaim_step
   packet.rebalance_step = function ()
      local start = ts:stamp()
      rebalance_step()
      rebalance_latency:add(tonumber(ts:to_ns(ts:stamp()-start)))
   end
   packet.reclaim_step = function ()
      local start = ts:stamp()
      reclaim_step()
      reclaim_latency:add(tonumber(ts:to_ns(ts:stamp()-start)))
   end
   
   return rebalance_latency, reclaim_latency
end

function histogram_csv_header (out)
   out = out or io.stdout
   out:write("histogram,lo,hi,count\n")
end

function histogram_csv (histogram, name, out)
   out = out or io.stdout
   name = name or 'untitled'
   for count, lo, hi in histogram:iterate() do
      out:write(("%s,%f,%f,%d\n"):format(name, lo, hi, tonumber(count)))
      out:flush()
   end
end
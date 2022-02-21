-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local Receiver = require("apps.interlink.receiver")
local Sink = require("apps.basic.basic_apps").Sink
local lib = require("core.lib")
local numa = require("lib.numa")

function configure (c, name)
   config.app(c, name, Receiver)
   config.app(c, "sink", Sink)
   config.link(c, name..".output -> sink.input")
end

function start (name, duration)
   local c = config.new()
   configure(c, name)
   engine.configure(c)
   engine.main{duration=duration}
end

local instr = require("apps.interlink.freelist_instrument")

function start_instrument (name, duration, core)
   numa.bind_to_cpu(core, 'skip')
   local rebalance_latency = instr.instrument_freelist()
   start(name, duration)
   instr.histogram_csv(rebalance_latency, "rebalance")
   local min, avg, max = rebalance_latency:summarize()
   io.stderr:write(("(%d) rebalance latency (ns)    min:%16s    avg:%16s    max:%16s\n")
      :format(core,
              lib.comma_value(math.floor(min)),
              lib.comma_value(math.floor(avg)),
              lib.comma_value(math.floor(max))))
   io.stderr:flush()
end


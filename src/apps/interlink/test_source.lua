-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local Transmitter = require("apps.interlink.transmitter")
local Source = require("apps.basic.basic_apps").Source
local lib = require("core.lib")
local numa = require("lib.numa")

function configure (c, name)
   config.app(c, name, Transmitter)
   config.app(c, "source", Source)
   config.link(c, "source."..name.." -> "..name..".input")
end

function start (name, duration)
   local c = config.new()
   configure(c, name)
   engine.configure(c)
   engine.main{duration=duration}
end

function startn (name, duration, n, core)
   numa.bind_to_cpu(core, 'skip')
   local c = config.new()
   for i=1,n do
      configure(c, name..i)
   end
   engine.configure(c)
   engine.main{duration=duration}
   local txpackets = txpackets()
   engine.main{duration=1, no_report=true}
   io.stderr:write(("%.3f Mpps\n"):format(txpackets / 1e6 / duration))
   io.stderr:flush()
   --engine.report_links()
end

function txpackets ()
   local txpackets = 0
   for _, output in ipairs(engine.app_table["source"].output) do
      txpackets = txpackets + link.stats(output).rxpackets
   end
   return txpackets
end

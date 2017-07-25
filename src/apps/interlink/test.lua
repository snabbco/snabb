-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

local worker = require("core.worker")
local interlink = require("lib.interlink")
local Receiver = require("apps.interlink.receiver")
local Sink = require("apps.basic.basic_apps").Sink

interlink.create("group/test.mcp")

worker.start("source",
             [[require("apps.interlink.test_source").start("group/test.mcp")]])

local c = config.new()

config.app(c, "rx", Receiver, {name="group/test.mcp"})
config.app(c, "sink", Sink)
config.link(c, "rx.output->sink.input")

engine.configure(c)
engine.main({duration=10, report={showlinks=true}})

for w, s in pairs(worker.status()) do
   print(("worker %s: pid=%s alive=%s status=%s"):format(
         w, s.pid, s.alive, s.status))
end
local stats = link.stats(engine.app_table["sink"].input.input)
print(stats.txpackets / 1e6 / 10 .. " Mpps")

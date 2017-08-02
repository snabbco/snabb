-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

local worker = require("core.worker")
local shm = require("core.shm")
local Sink = require("apps.basic.basic_apps").Sink

local c = config.new()
config.app(c, "sink", Sink)
engine.configure(c)

local l = link.new("test")
shm.alias("group/test.link", "links/test")

engine.attach_input("sink", "input", "group/test.link")

worker.start("source", [[
local Source = require("apps.basic.basic_apps").Source

local c = config.new()
config.app(c, "source", Source)
engine.configure(c)

engine.attach_output("source", "output", "group/test.link")

engine.busywait = true
engine.main()
]])

engine.busywait = true
engine.main({duration=10, report={showlinks=true}})

for w, s in pairs(worker.status()) do
   print(("worker %s: pid=%s alive=%s status=%s"):format(
         w, s.pid, s.alive, s.status))
end
local stats = link.stats(l)
print(stats.txpackets / 1e6 / 10 .. " Mpps")

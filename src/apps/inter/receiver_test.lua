-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

local Receiver = require("apps.inter.receiver")
local Sink = require("apps.basic.basic_apps").Sink

local c = config.new()

config.app(c, "rx", Receiver, {name="/inter_test.mcp", create=true})
config.app(c, "sink", Sink)
config.link(c, "rx.output->sink.input")

engine.configure(c)
engine.main({duration=10, report={showlinks=true}})

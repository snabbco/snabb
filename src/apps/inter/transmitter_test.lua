-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

local Transmitter = require("apps.inter.transmitter")
local Source = require("apps.basic.basic_apps").Source

local c = config.new()

config.app(c, "tx", Transmitter, {name="/inter_test.mcp"})
config.app(c, "source", Source)
config.link(c, "source.output->tx.input")

engine.configure(c)
engine.main({duration=10, report={showlinks=true}})

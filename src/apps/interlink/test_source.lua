-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local Transmitter = require("apps.interlink.transmitter")
local Source = require("apps.basic.basic_apps").Source

function start (name)
   local c = config.new()
   config.app(c, name, Transmitter)
   config.app(c, "source", Source)
   config.link(c, "source.output -> "..name..".input")
   engine.configure(c)
   engine.main()
end

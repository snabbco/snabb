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

function start (name, duration, core)
   numa.bind_to_cpu(core, 'skip')
   local c = config.new()
   configure(c, name)
   engine.configure(c)
   engine.main{duration=duration}
end

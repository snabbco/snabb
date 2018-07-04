-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local socket = require("apps.socket.raw")
local pingecho = require("program.ping.pingecho")

function run (parameters)
   if not (#parameters == 1) then
      print("Usage: ping <if>")
      main.exit(1)
   end
   local interface = parameters[1]

   local c = config.new()
   config.app(c, "raw", socket.RawSocket, interface)
   config.app(c, "pingecho", pingecho.PingEcho)

   config.link(c, "raw.tx -> pingecho.input")
   config.link(c, "pingecho.output -> raw.rx")

   engine.configure(c)
   engine.main({duration=2, report = {showlinks=true}})
end

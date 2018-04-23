-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)


local synfld = require("program.synflood.syn_flood")

local raw = require("apps.socket.raw")


function run (parameters)
   if not (#parameters == 1) then
      print("Usage: synflood <interface>")
      main.exit(1)
   end
   local interface = parameters[1]

   local c = config.new()
   config.app(c, "synfld", synfld.Synfld, synfld.config)
   config.app(c, "playback", raw.RawSocket, interface)

   config.link(c, "synfld.output -> playback.rx")

   engine.configure(c)
   engine.main({report = {showlinks=true}})
end

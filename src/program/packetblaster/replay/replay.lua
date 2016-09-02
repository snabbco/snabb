-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local config     = require("core.config")
local basic_apps = require("apps.basic.basic_apps")
local main       = require("core.main")
local PcapReader = require("apps.pcap.pcap").PcapReader
local lib        = require("core.lib")

local packetblaster = require("program.packetblaster.packetblaster")

local long_opts = {
   duration     = "D",
   help         = "h"
}

local function show_usage (code)
   print(require("program.packetblaster.replay.README_inc"))
   main.exit(code)
end

function run (args)
   local opt = {}
   local duration
   local c = config.new()
   function opt.D (arg)
      duration = assert(tonumber(arg), "duration is not a number!")
   end
   function opt.h ()
      show_usage(0)
   end

   args = lib.dogetopt(args, opt, "hD:", long_opts)
   if #args < 2 then show_usage(1) end
   local filename = table.remove(args, 1)
   print (string.format("filename=%s", filename))
   config.app(c, "pcap", PcapReader, filename)
   config.app(c, "loop", basic_apps.Repeater)
   config.app(c, "source", basic_apps.Tee)
   config.link(c, "pcap.output -> loop.input")
   config.link(c, "loop.output -> source.input")
   packetblaster.run_loadgen(c, args, duration)
end

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
   help         = "h",
   ["no-loop"]  = 0,
}

local function show_usage (code)
   print(require("program.packetblaster.replay.README_inc"))
   main.exit(code)
end

function run (args)
   local c = config.new()
   local handlers = {}
   local opts = { loop = true }
   function handlers.D (arg)
      opts.duration = assert(tonumber(arg), "duration is not a number!")
   end
   function handlers.h ()
      show_usage(0)
   end
   handlers["no-loop"] = function ()
      opts.loop = false
   end

   args = lib.dogetopt(args, handlers, "hD:", long_opts)
   if #args < 2 then show_usage(1) end
   local filename = table.remove(args, 1)
   print (string.format("filename=%s", filename))
   config.app(c, "pcap", PcapReader, filename)
   config.app(c, "source", basic_apps.Tee)
   if opts.loop then
      config.app(c, "loop", basic_apps.Repeater)
      config.link(c, "pcap.output -> loop.input")
      config.link(c, "loop.output -> source.input")
   else
      config.link(c, "pcap.output -> source.input")
      if not opts.duration then opts.duration = 1 end
   end
   packetblaster.run_loadgen(c, args, opts)
end

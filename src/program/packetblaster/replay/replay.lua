-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local config     = require("core.config")
local basic_apps = require("apps.basic.basic_apps")
local main       = require("core.main")
local PcapReader = require("apps.pcap.pcap").PcapReader
local lib        = require("core.lib")

local packetblaster = require("program.packetblaster.packetblaster")
local usage = require("program.packetblaster.replay.README_inc")

local long_opts = {
   duration     = "D",
   help         = "h"
}

function run (args)
   local opt = {}
   local duration
   local c = config.new()
   function opt.D (arg) 
      duration = assert(tonumber(arg), "duration is not a number!")  
   end
   function opt.h (arg)
      print(usage)
      main.exit(1)
   end

   args = lib.dogetopt(args, opt, "hD:", long_opts)
   local filename = table.remove(args, 1)
   print (string.format("filename=%s", filename))
   config.app(c, "pcap", PcapReader, filename)
   config.app(c, "loop", basic_apps.Repeater)
   config.app(c, "source", basic_apps.Tee)
   config.link(c, "pcap.output -> loop.input")
   config.link(c, "loop.output -> source.input")
   packetblaster.run_loadgen(c, args, duration)
end

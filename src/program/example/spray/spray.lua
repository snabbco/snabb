module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local sprayer = require("program.example.spray.sprayer")
local usage = require("program.example.spray.README_inc")

function run (parameters)
   if not (#parameters == 2) then print(usage) main.exit(1) end
   local input = parameters[1]
   local output = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, input)
   config.app(c, "spray_app", sprayer.Sprayer)
   config.app(c, "output_file", pcap.PcapWriter, output)

   config.link(c, "capture.output -> spray_app.input")
   config.link(c, "spray_app.output -> output_file.input")

   app.configure(c)
   app.main({duration=1, report = {showlinks=true}})
end

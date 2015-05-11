module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local sprayer = require("program.example-spray.sprayer")

function run (parameters)
   if not (#parameters == 2) then
      print("Usage: example-spray <input> <output>")
      main.exit(1)
   end
   local input = parameters[1]
   local output = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, input)
   config.app(c, "spray_app", sprayer.Sprayer)
   config.app(c, "output_file", pcap.PcapWriter, output)

   config.link(c, "capture.output -> spray_app.input")
   config.link(c, "spray_app.output -> output_file.input")

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end

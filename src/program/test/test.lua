-- run:
--  sudo ./snabb test program/example_replay/input.pcap  out.pcap

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local tester = require("program.test.tester")

function run (parameters)
   if not (#parameters == 2) then
      print("Usage: test <input> <output>")
      main.exit(1)
   end
   local input = parameters[1]
   local output = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, input)
   config.app(c, "tester_app", tester.tester)
   config.app(c, "output_file", pcap.PcapWriter, output)

   config.link(c, "capture.output -> tester_app.input")
   config.link(c, "tester_app.output -> output_file.input")

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end

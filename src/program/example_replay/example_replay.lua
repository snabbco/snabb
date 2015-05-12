module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")

function run (parameters)
   if not (#parameters == 2) then
      print("Usage: example_replay <pcap-file> <interface>")
      main.exit(1)
   end
   local pcap_file = parameters[1]
   local interface = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, pcap_file)
   config.app(c, "playback", raw.RawSocket, interface)

   config.link(c, "capture.output -> playback.rx")

   engine.configure(c)
   engine.main({duration=1, report = {showlinks=true}})
end

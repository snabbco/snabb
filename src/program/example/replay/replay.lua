module(..., package.seeall)

local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")
local usage = require("program.example.replay.README_inc")

function run (parameters)
   if not (#parameters == 2) then print(usage) main.exit(1) end
   local pcap_file = parameters[1]
   local interface = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, pcap_file)
   config.app(c, "playback", raw.RawSocket, interface)

   config.link(c, "capture.output -> playback.rx")

   app.configure(c)
   app.main({duration=1, report = {showlinks=true}})
end

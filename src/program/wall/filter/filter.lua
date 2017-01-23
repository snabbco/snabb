module(..., package.seeall)

local fw   = require("apps.wall.l7fw")
local pcap = require("apps.pcap.pcap")

function run (args)
   if #args ~= 2 then
      print("TODO instructions")
      main.exit(1)
   end

   -- TODO: baking in pcap file for now in for now, allow
   --       other sources later?
   local in_file  = args[1]
   local out_file = args[2]
   local scanner  = require("apps.wall.scanner.ndpi"):new()

   local c = config.new()
   config.app(c, "source", pcap.PcapReader, in_file)
   config.app(c, "l7spy", require("apps.wall.l7spy").L7Spy, { scanner = scanner })
   config.app(c, "sink", pcap.PcapWriter, out_file)
   -- TODO: hardcoded some rules here for this experiment
   local rules = { RTP = [[match { udp => accept; otherwise => drop }]],
                   DNS = [[match { $flow_count > 2 => accept; otherwise => drop }]],
                   default = "drop" }
   config.app(c, "l7fw", require("apps.wall.l7fw").L7Fw, { scanner = scanner, rules = rules })
   config.link(c, "source.output -> l7spy.south")
   config.link(c, "l7spy.north -> l7fw.input")
   config.link(c, "l7fw.output -> sink.input")

   engine.configure(c)
   engine.main({duration = 0.1, report = {showlinks = true}})
end

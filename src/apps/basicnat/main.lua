local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local basicnat = require("apps.basicnat.basicnat")
--local usage = require("program.example.replay.README_inc") -- TODO
local usage="thisapp in.pcap out.pcap" -- TODO

function run (parameters)
   if not (#parameters == 2) then print(usage) main.exit(1) end
   local in_pcap = parameters[1]
   local out_pcap = parameters[2]

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, in_pcap)
   config.app(c, "basicnat_app", basicnat.BasicNAT)
   config.app(c, "output_file", pcap.PcapWriter, out_pcap)

   config.link(c, "capture.output -> basicnat_app.input")
   config.link(c, "basicnat_app.output -> output_file.input")

   app.configure(c)
   --app.main({duration=1, report = {showlinks=true}})
   app.main({duration=1})
end

run(main.parameters)

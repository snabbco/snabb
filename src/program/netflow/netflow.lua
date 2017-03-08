-- This module implements the `snabb netflow` command

module(..., package.seeall)

-- basic module imports
local raw     = require("apps.socket.raw")
local pcap    = require("apps.pcap.pcap")
local netflow = require("apps.netflow.netflow")

function run (args)
   local c = config.new()

   --config.app(c, "source", raw.RawSocket, args[1])
   config.app(c, "source", pcap.PcapReader, args[1])
   config.app(c, "exporter", netflow.NetflowExporter, {})

   config.link(c, "source.output -> exporter.input")

   engine.configure(c)

   engine.main({ duration=5, report = { showapps=true, showlinks=true } })
end

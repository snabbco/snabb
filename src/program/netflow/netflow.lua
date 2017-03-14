-- This module implements the `snabb netflow` command

module(..., package.seeall)

-- basic module imports
local raw     = require("apps.socket.raw")
local pcap    = require("apps.pcap.pcap")
local netflow = require("apps.netflow.netflow")

function run (args)
   local c = config.new()

   -- TODO: use cmdline flags
   local exporter_config = { exporter_mac = args[3],
                             exporter_ip = args[4],
                             collector_mac = args[5],
                             collector_ip = args[6],
                             collector_port = args[7] }

   config.app(c, "source", raw.RawSocket, args[1])
   config.app(c, "sink", raw.RawSocket, args[2])
   config.app(c, "exporter", netflow.NetflowExporter, exporter_config)

   config.link(c, "source.tx -> exporter.input")
   config.link(c, "exporter.output -> sink.rx")

   engine.configure(c)

   engine.main({ duration=80, report = { showapps=true, showlinks=true } })
end

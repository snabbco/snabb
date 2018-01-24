-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local pcap = require("apps.pcap.pcap")
local raw = require("apps.socket.raw")
local pcap_filter = require("apps.packet_filter.pcap_filter")



function run (parameters)
   if not (#parameters == 1) then
      -- dump
      print("Usage: zweig <interface>")
      main.exit(1)
   end
   -- local pcap_file = parameters[1]
   local interface = parameters[1]
   local c = config.new()

   config.app(c, "capture", raw.RawSocket, interface)
   local v4_rules =
   [[
      (udp and (dst port 5005))
   ]]
   config.app(c,"pcap_filter", pcap_filter.PcapFilter,
      {filter=v4_rules})

   config.app(c, "dump", pcap.StdOutput, {})
   -- config.app(c, "dump", pcap.PcapWriter, {'1.pcap'})

   config.link(c, "capture.tx -> pcap_filter.input")
   config.link(c, "pcap_filter.output -> dump.input")
   -- config.link(c, "capture.tx -> dump.input")

   engine.configure(c)
   engine.main({report = {showlinks=true}})

end

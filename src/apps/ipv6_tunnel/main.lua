local app = require("core.app")
local config = require("core.config")
local pcap = require("apps.pcap.pcap")
local ipv6_tunnel = require("apps.ipv6_tunnel.ipv6_tunnel")
local ipv6 = require("lib.protocol.ipv6")

local usage="thisapp in.pcap out.pcap ipv6_src ipv6_dst"

function run (parameters)
   if not (#parameters == 4) then print(usage) main.exit(1) end
   local in_pcap = parameters[1]
   local out_pcap = parameters[2]
   local ipv6_src = ipv6:pton(parameters[3])
   local ipv6_dst = ipv6:pton(parameters[4])

   local c = config.new()
   config.app(c, "capture", pcap.PcapReader, in_pcap)
   config.app(c, "ipv6_tunnel", ipv6_tunnel.IPv6Tunnel,
                  {ipv6_src = ipv6_src, ipv6_dst = ipv6_dst})
   config.app(c, "output_file", pcap.PcapWriter, out_pcap)

   config.link(c, "capture.output -> ipv6_tunnel.input")
   config.link(c, "ipv6_tunnel.output -> output_file.input")

   app.configure(c)
   app.main({duration=1})
end

run(main.parameters)

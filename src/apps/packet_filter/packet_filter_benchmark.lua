module(...,package.seeall)

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local config = require("core.config")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

function selftest ()

   local packet_filter
   local v6_rules
   if _G.pflua then
      packet_filter = require("apps.packet_filter.packet_filter_pflua")
      v6_rules = {
         [[
            icmp6 and
            src net 3ffe:501:0:1001::2/128 and
            dst net 3ffe:507:0:1:200:86ff:fe05:8000/116
         ]],
         [[
            ip6 and udp and
            src net 3ffe:500::/28 and
            dst net 3ffe:0501:4819::/64 and
            src portrange 2397-2399 and
            dst port 53
         ]],
      }
   else
      packet_filter = require("apps.packet_filter.packet_filter")
      v6_rules = {
      {
         ethertype = "ipv6",
         protocol = "icmp",
         source_cidr = "3ffe:501:0:1001::2/128", -- single IP, match 128bit
         dest_cidr =
            "3ffe:507:0:1:200:86ff:fe05:8000/116", -- match first 64bit and mask next 52 bit
      },
      {
         ethertype = "ipv6",
         protocol = "udp",
         source_cidr = "3ffe:507:0:1:200:86ff::/28", -- mask first 28 bit
         dest_cidr = "3ffe:501:4819::/64",           -- match first 64bit
         source_port_min = 2397, -- port range, in v6.pcap there are values on
         source_port_max = 2399, -- both borders and in the middle
         dest_port_min = 53,     -- single port match
         dest_port_max = 53,
      }}
   end

   local c = config.new()
   config.app(
         c,
         "source",
         pcap.PcapReader,
         "apps/packet_filter/samples/v6.pcap"
      )
   config.app(c, "repeater", basic_apps.Repeater )
   config.app(c,
         "packet_filter",
         packet_filter.PacketFilter,
         v6_rules
      )
   config.app(c, "sink", basic_apps.Sink )

   config.link(c, "source.output -> repeater.input")
   config.link(c, "repeater.output -> packet_filter.input")
   config.link(c, "packet_filter.output -> sink.input")
   app.configure(c)

   print("Run for 1 second ...")

   local deadline = lib.timer(1e9)
   repeat app.breathe() until deadline()
   
   print("done")

   app.report()
end

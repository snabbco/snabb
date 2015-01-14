module(...,package.seeall)

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local config = require("core.config")
local buffer = require("core.buffer")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")
local packet_filter = require("apps.pflua_packet_filter.packet_filter")

function selftest ()
   buffer.preallocate(100000)

   local v6_rules = {
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

   local c = config.new()
   config.app(
      c,
      "source",
      pcap.PcapReader,
      "apps/packet_filter/samples/v6.pcap"
   )
   config.app(c, "repeater", basic_apps.FastRepeater)
   config.app(c,
      "packet_filter",
      packet_filter,
      v6_rules
   )
   config.app(c, "sink", basic_apps.FastSink)

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

module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local bit = require("bit")

local app = require("core.app")
local link = require("core.link")
local lib = require("core.lib")
local packet = require("core.packet")
local config = require("core.config")

local pcap = require("apps.pcap.pcap")
local basic_apps = require("apps.basic.basic_apps")

local verbose = false

assert(ffi.abi("le"), "support only little endian architecture at the moment")
assert(ffi.abi("64bit"), "support only 64 bit architecture at the moment")

function selftest ()
   -- Temporarily disabled:
   --   Packet filter selftest is failing in.
   -- enable verbose logging for selftest
   verbose = true

   local V6_RULE_ICMP_PACKETS = 3 -- packets within v6.pcap
   local V6_RULE_DNS_PACKETS =  3 -- packets within v6.pcap
      
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
         udp and
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
         "source1",
         pcap.PcapReader,
         "apps/packet_filter/samples/v6.pcap"
      )
   config.app(c,
         "packet_filter1",
         packet_filter.PacketFilter,
         v6_rules
      )
   config.app(c, "sink1", basic_apps.Sink )
   config.link(c, "source1.output -> packet_filter1.input")
   config.link(c, "packet_filter1.output -> sink1.input")

   local V4_RULE_DNS_PACKETS = 1 -- packets within v4.pcap
   local V4_RULE_TCP_PACKETS = 18 -- packets within v4.pcap

   local v4_rules
   if _G.pflua then
      v4_rules = {
      [[
         udp and
         dst port 53
      ]],
      [[
         tcp and
         src host 65.208.228.223 and
         src portrange 80-81 and
         dst net 145.240.0.0/12 and
         dst portrange 3371-3373
      ]],
      }
   else
      v4_rules = {
      {
         ethertype = "ipv4",
         protocol = "udp",
         dest_port_min = 53,     -- single port match, DNS
         dest_port_max = 53,
      },
      {
         ethertype = "ipv4",
         protocol = "tcp",
         source_cidr = "65.208.228.223/32", -- match 32bit
         dest_cidr = "145.240.0.0/12",      -- mask 12bit
         source_port_min = 80, -- our port (80) is on the border of range
         source_port_max = 81,
         dest_port_min = 3371, -- our port (3372) is in the middle of range
         dest_port_max = 3373,
      }}
   end

   config.app(
         c,
         "source2",
         pcap.PcapReader,
         "apps/packet_filter/samples/v4.pcap"
      )
   config.app(c,
         "packet_filter2",
         packet_filter.PacketFilter,
         v4_rules
      )
   config.app(c, "sink2", basic_apps.Sink )
   config.link(c, "source2.output -> packet_filter2.input")
   config.link(c, "packet_filter2.output -> sink2.input")

   app.configure(c)

   -- v4.pcap contains 43 packets
   -- v6.pcap contains 161 packets
   -- one breathe is enough
   app.breathe()

   app.report()

   local packet_filter1_passed =
      app.app_table.packet_filter1.output.output.stats.txpackets
   local packet_filter2_passed =
      app.app_table.packet_filter2.output.output.stats.txpackets
   local ok = true

   if packet_filter1_passed ~= V6_RULE_ICMP_PACKETS + V6_RULE_DNS_PACKETS
   then
      ok = false
      print("IPv6 test failed")
   end
   if packet_filter2_passed ~= V4_RULE_DNS_PACKETS + V4_RULE_TCP_PACKETS
   then
      ok = false
      print("IPv4 test failed")
   end
   if not ok then
      print("selftest failed")
      os.exit(1)
   end
   print("selftest passed")
end

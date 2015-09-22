-- Captured packets -> NIC

local Intel82599 = require("apps.intel.intel_app").Intel82599
local PcapReader = require("apps.pcap.pcap").PcapReader
local basic_apps = require("apps.basic.basic_apps")
local C          = require("ffi").C

local function print_stats(app_name, channel, direction, elapsed)
   local stats = link.stats(engine.app_table[app_name][channel][direction])
   print(string.format('%s.%s.%s: %.3f MPPS, %.3f Gbps.',
                       app_name, channel, direction,
		       stats.txpackets / elapsed / 1e6,
		       stats.txbytes * 8 / 1e9 / elapsed))
end

-- e.g. ./snabb snsh apps/lwaftr/loadgen.lua ../tests/apps/lwaftr/benchdata/ipv4-0550.pcap 0000:04:00.0 44:44:44:44:44:00 10 ../tests/apps/lwaftr/benchdata/ipv6-0550.pcap 0000:04:00.1 44:44:44:44:44:01 2
local function loadgen(params)
   if #params ~= 8 then
      print("Usage: loadgen.lua IPV4-PACKETS.PCAP IPV4-PCI-ADDR IPV4-MAC-ADDR IPV4-GBPS IPV6-PACKETS.PCAP IPV6-PCI-ADDR IPV6-MAC-ADDR IPV6-GBPS")
      os.exit()
   end
   local ipv4_packet_file, ipv4_pci_addr, ipv4_mac_addr, ipv4_gbps, ipv6_packet_file, ipv6_pci_addr, ipv6_mac_addr, ipv6_gbps = unpack(params)
   local ipv4_gbps = assert(tonumber(ipv4_gbps), 'IPv4 Gbps must be a number')
   local ipv6_gbps = assert(tonumber(ipv6_gbps), 'IPv6 Gbps must be a number')
   local ipv4_byte_rate = ipv4_gbps * 1e9 / 8
   local ipv6_byte_rate = ipv6_gbps * 1e9 / 8

   local c = config.new()
   config.app(c, 'ipv4_tx_packets', PcapReader, ipv4_packet_file)
   config.app(c, 'ipv4_tx_repeater', basic_apps.RateLimitedRepeater,
              { rate = ipv4_byte_rate })
   config.app(c, 'ipv4_tx_statistics', basic_apps.Statistics)

   config.app(c, 'ipv4', Intel82599, { pciaddr = ipv4_pci_addr, macaddr = ipv4_mac_addr })

   config.app(c, 'ipv4_rx_statistics', basic_apps.Statistics)
   config.app(c, 'ipv4_rx_sink', basic_apps.Sink)

   config.link(c, 'ipv4_tx_packets.output    -> ipv4_tx_repeater.input')
   config.link(c, 'ipv4_tx_repeater.output   -> ipv4_tx_statistics.input')
   config.link(c, 'ipv4_tx_statistics.output -> ipv4.rx')

   config.link(c, 'ipv4.tx               -> ipv4_rx_statistics.input')
   config.link(c, 'ipv4_rx_statistics.output -> ipv4_rx_sink.input')

   config.app(c, 'ipv6_tx_packets', PcapReader, ipv6_packet_file)
   config.app(c, 'ipv6_tx_repeater', basic_apps.RateLimitedRepeater,
              { rate = ipv6_byte_rate })
   config.app(c, 'ipv6_tx_statistics', basic_apps.Statistics)

   config.app(c, 'ipv6', Intel82599, { pciaddr = ipv6_pci_addr, macaddr = ipv6_mac_addr })

   config.app(c, 'ipv6_rx_statistics', basic_apps.Statistics)
   config.app(c, 'ipv6_rx_sink', basic_apps.Sink)

   config.link(c, 'ipv6_tx_packets.output    -> ipv6_tx_repeater.input')
   config.link(c, 'ipv6_tx_repeater.output   -> ipv6_tx_statistics.input')
   config.link(c, 'ipv6_tx_statistics.output -> ipv6.rx')

   config.link(c, 'ipv6.tx               -> ipv6_rx_statistics.input')
   config.link(c, 'ipv6_rx_statistics.output -> ipv6_rx_sink.input')


   engine.configure(c)

   local start = C.get_monotonic_time()
   engine.main({report={showlinks=true}})
   local elapsed = C.get_monotonic_time() - start
   print_stats('ipv4', 'input', 'rx', elapsed)
   print_stats('ipv4', 'output', 'tx', elapsed)
   print_stats('ipv6', 'input', 'rx', elapsed)
   print_stats('ipv6', 'output', 'tx', elapsed)
end

loadgen(main.parameters)

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

-- e.g. ./snabb snsh apps/lwaftr/loadgen.lua ../tests/apps/lwaftr/data/tcp-frominet-bound-550.pcap 0000:05:00.0 44:44:44:44:44:44 2
local function loadgen(params)
   if #params ~= 4 then
      print("Usage: loadgen.lua PACKETS.PCAP PCI-ADDR MAC-ADDR GBPS")
      os.exit()
   end
   local packet_file, pci_addr, mac_addr, gbps = unpack(params)
   local gbps = tonumber(gbps) or 10
   local byte_rate = gbps * 1e9 / 8

   local c = config.new()
   config.app(c, 'tx_packets', PcapReader, packet_file)
   config.app(c, 'tx_repeater', basic_apps.RateLimitedRepeater,
              { rate = byte_rate })
   config.app(c, 'tx_statistics', basic_apps.Statistics)

   config.app(c, 'nic', Intel82599, { pciaddr = pci_addr, macaddr = mac_addr })

   config.app(c, 'rx_statistics', basic_apps.Statistics)
   config.app(c, 'rx_sink', basic_apps.Sink)

   config.link(c, 'tx_packets.output    -> tx_repeater.input')
   config.link(c, 'tx_repeater.output   -> tx_statistics.input')
   config.link(c, 'tx_statistics.output -> nic.rx')

   config.link(c, 'nic.tx               -> rx_statistics.input')
   config.link(c, 'rx_statistics.output -> rx_sink.input')

   engine.configure(c)

   local start = C.get_monotonic_time()
   engine.main({report={showlinks=true}})
   local elapsed = C.get_monotonic_time() - start
   print_stats('nic', 'input', 'rx', elapsed)
   print_stats('nic', 'output', 'tx', elapsed)
end

loadgen(main.parameters)

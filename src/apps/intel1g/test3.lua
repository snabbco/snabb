#!../../snabb snsh
local intel     = require("apps.intel1g.intel1g")
local pcap      = require("apps.pcap.pcap")
local delay     = require("apps.test.delayed_start")
local counter   = require("core.counter")
local basic     = require("apps.basic.basic_apps")

local pci0 = os.getenv("SNABB_PCI_INTEL1G0")
local pci1 = os.getenv("SNABB_PCI_INTEL1G1")
local c = config.new()
engine.busywait = 1
config.app(c, "source0", pcap.PcapReader, "source.pcap")
config.app(c, "delay", delay.Delayed_start, 5)
config.app(c, "tee", basic.Tee)
config.app(c, "nic10", intel.Intel1g, {pciaddr=pci0, rxq = 0 })
config.app(c, "nic0", intel.Intel1g, {pciaddr=pci1, txq = 0})
config.app(c, "nic1", intel.Intel1g, {pciaddr=pci1, txq = 1})
config.app(c, "nic2", intel.Intel1g, {pciaddr=pci1, txq = 2})
config.app(c, "nic3", intel.Intel1g, {pciaddr=pci1, txq = 3})
config.app(c, "dest0", basic.Sink)

config.link(c, "source0.output -> delay.input")
config.link(c, "delay.output -> tee.input")
config.link(c, "tee.output0 -> nic0.input")
config.link(c, "tee.output1 -> nic1.input")
config.link(c, "tee.output2 -> nic2.input")
config.link(c, "tee.output3 -> nic3.input")
config.link(c, "nic10.output -> dest0.input")
engine.configure(c)
engine.main({ duration = 10 })
local slink = counter.read(engine.app_table.source0.output.output.stats.txpackets)
local olink = counter.read(engine.app_table.dest0.input.input.stats.txpackets)
if 4 * slink == olink then
  os.exit(0)
else
  print("sent = " .. tostring(slink) .. ", received = " .. tostring(olink))
  os.exit(-1)
end

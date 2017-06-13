#!../../snabb snsh

-- Snabb test script for mirroring rules in VMDq mode

local basic_apps = require("apps.basic.basic_apps")
local intel      = require("apps.intel_mp.intel_mp")
local pcap       = require("apps.pcap.pcap")
local lib        = require("core.lib")

local pciaddr0 = lib.getenv("SNABB_PCI_INTEL0")
local pciaddr1 = lib.getenv("SNABB_PCI_INTEL1")

local c = config.new()

-- send packets on nic0
config.app(c, "nic0", intel.Intel,
           { pciaddr = pciaddr0,
             txq = 0,
             wait_for_link = true })

-- nic1 with three pools with several mirror configs
config.app(c, "nic1p0", intel.Intel,
           { pciaddr = pciaddr1,
             vmdq = true,
             poolnum = 0,
             macaddr = "90:72:82:78:c9:7a",
             rxq = 0,
             wait_for_link = true })

config.app(c, "nic1p1", intel.Intel,
           { pciaddr = pciaddr1,
             vmdq = true,
             poolnum = 1,
             mirror = { pool = { 0 } },
             macaddr = "12:34:56:78:9a:bc",
             rxq = 4,
             wait_for_link = true })

config.app(c, "nic1p2", intel.Intel,
           { pciaddr = pciaddr1,
             vmdq = true,
             poolnum = 2,
             mirror = { pool = true },
             macaddr = "aa:aa:aa:aa:aa:aa",
             rxq = 8,
             wait_for_link = true })

config.app(c, "pcap", pcap.PcapReader, "source2.pcap")
config.app(c, 'sink', basic_apps.Sink)

config.link(c, "pcap.output -> nic0.input")
config.link(c, "nic1p0.output -> sink.input0")
config.link(c, "nic1p1.output -> sink.input1")
config.link(c, "nic1p2.output -> sink.input2")

engine.configure(c)
engine.main({ duration = 1 })

assert(link.stats(engine.app_table.sink.input.input0).rxpackets == 51,
       "wrong number of packets received on pool 0")
assert(link.stats(engine.app_table.sink.input.input1).rxpackets == 102,
       "wrong number of packets received on pool 1")
assert(link.stats(engine.app_table.sink.input.input2).rxpackets == 102,
       "wrong number of packets received on pool 2")

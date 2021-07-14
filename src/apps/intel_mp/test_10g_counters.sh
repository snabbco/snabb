#!../../snabb snsh

-- Snabb test script for testing that retrieving queue stats on
-- a process that isn't the stats-syncing process works

local basic_apps = require("apps.basic.basic_apps")
local intel      = require("apps.intel_mp.intel_mp")
local pcap       = require("apps.pcap.pcap")
local counter    = require("core.counter")
local lib        = require("core.lib")
local shm        = require("core.shm")
local worker     = require("core.worker")
local pci        = require("lib.hardware.pci")

local pciaddr0 = pci.canonical(lib.getenv("SNABB_PCI_INTEL0"))
local pciaddr1 = pci.canonical(lib.getenv("SNABB_PCI_INTEL1"))

local function make_worker(pci, rxq, rxc)
   local code = string.format([[
      local basic_apps = require("apps.basic.basic_apps")
      local intel      = require("apps.intel_mp.intel_mp")

      local c = config.new()
      config.app(c, "sink", basic_apps.Sink)
      config.app(c, "nic", intel.Intel,
                 { pciaddr = "%s",
                   master_stats = false,
                   run_stats = true,
                   rxq = %d,
                   rxcounter = %d,
                   wait_for_link = true })
      config.link(c, "nic.output -> sink.input")
      engine.configure(c)
      engine.main()
      ]], pci, rxq, rxc)

   worker.start("worker"..rxq, code)
end

-- Make a worker that syncs stats and uses queue 0, counter 1
make_worker(pciaddr1, 0, 1)

local c = config.new()

-- send packets on nic0
config.app(c, "nic0", intel.Intel,
           { pciaddr = pciaddr0,
             -- disable rxq
             rxq = false,
             txq = 0,
             wait_for_link = true })

-- The test process makes its own RSS app too
config.app(c, "nic1", intel.Intel,
           { pciaddr = pciaddr1,
             master_stats = false,
             run_stats = false,
             rxq = 1,
             rxcounter = 2,
             wait_for_link = true })

config.app(c, "source", pcap.PcapReader, "source.pcap")
config.app(c, 'sink', basic_apps.Sink)
config.app(c, "repeat", basic_apps.Repeater)
config.link(c, "source.output -> repeat.input")
config.link(c, "repeat.output -> nic0.input")
config.link(c, "nic1.output -> sink.input")

engine.configure(c)
engine.main({ duration = 1 })

-- make sure this process can read its own queue stats synced by the worker
-- and that the worker's queue counter can be read via shm
local pkts = engine.app_table.nic1:get_rxstats().packets
assert(pkts > 0, "get_rxstats failed")

local status = worker.status()
local pid = status.worker0.pid
local ct = counter.open("/"..pid.."/apps/nic/pci/"..pciaddr1.."/q1_rxbytes.counter")
assert(counter.read(ct) > 0, "failed to read worker queue counter")

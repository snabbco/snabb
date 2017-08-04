#!../../snabb snsh

-- Snabb test script for testing Tx rate limits

local basic_apps = require("apps.basic.basic_apps")
local intel      = require("apps.intel_mp.intel_mp")
local lib        = require("core.lib")

local pciaddr0 = lib.getenv("SNABB_PCI_INTEL0")
local pciaddr1 = lib.getenv("SNABB_PCI_INTEL1")

local c = config.new()

-- send packets on nic0
config.app(c, "nic0", intel.driver,
           { pciaddr = pciaddr0,
             txq = 0,
             -- minimum possible rate of 10Mbps
             rate_limit = 10,
             wait_for_link = true })

-- receive nic
config.app(c, "nic1", intel.driver,
           { pciaddr = pciaddr1,
             rxq = 0,
             rxcounter = 1,
             wait_for_link = true })

-- send 1KB packets repeatedly
config.app(c, "source", basic_apps.Source, 1024)
config.app(c, 'sink', basic_apps.Sink)

config.link(c, "source.output -> nic0.input")
config.link(c, "nic1.output -> sink.input")

engine.configure(c)
engine.main({ duration = 1 })

-- check that the stats show within 10% of 10Mb
local rxbytes = engine.app_table.nic1:get_rxstats().bytes
local target  = 2^17 * 10
assert(rxbytes > target * 0.90 and rxbytes < target * 1.10,
       "expected about 1310720 bytes (10Mb), got " .. tonumber(rxbytes) .. " bytes")

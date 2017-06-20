#!../../snabb snsh

-- Test to make sure the app shuts down propertly on reconfiguration

local intel      = require("apps.intel_mp.intel_mp")
local lib        = require("core.lib")

local pciaddr0 = lib.getenv("SNABB_PCI_INTEL0")
local pciaddr1 = lib.getenv("SNABB_PCI_INTEL1")

local c = config.new()

config.app(c, "n1", intel.Intel,
           { pciaddr = pciaddr1,
             rxq = 0,
             txq = 0,
             wait_for_link = true })

engine.configure(c)
engine.main({ duration = 1 })

local c2 = config.new()
engine.configure(c2)
engine.main({ duration = 1 })

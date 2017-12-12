#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

local ffi      = require("ffi")
local app      = require("core.app")
local lib      = require("core.lib")
local packet   = require("core.packet")
local pci      = require("lib.hardware.pci")

local c = config.new()

local e0, e1 = pci.device_info("01:00.0"), pci.device_info("03:00.0")

config.app(c, "e0", require(e0.driver).driver, {
	pciaddr = e0.pciaddress,
	macaddr = "00:00:00:00:01:01",
})

config.app(c, "e1", require(e1.driver).driver, {
	pciaddr = e1.pciaddress,
	macaddr = "00:00:00:00:01:02",
})

config.link(c, "e0."..e0.tx.." -> e1."..e1.rx)
config.link(c, "e1."..e1.tx.." -> e0."..e0.rx)

engine.configure(c)
engine.main({report = {showlinks=true}})

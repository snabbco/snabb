#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

local ffi      = require("ffi")
local app      = require("core.app")
local lib      = require("core.lib")
local packet   = require("core.packet")
local intel    = require("apps.intel.intel_app")

local c = config.new()

config.app(c, "e0", intel.Intel82599, {
	pciaddr = "0000:01:00.0",
	macaddr = "00:00:00:00:01:01",
})

config.app(c, "e1", intel.Intel82599, {
	pciaddr = "0000:03:00.0",
	macaddr = "00:00:00:00:01:02",
})

config.link(c, "e0.tx -> e1.rx")
config.link(c, "e1.tx -> e0.rx")

engine.configure(c)
engine.main({report = {showlinks=true}})

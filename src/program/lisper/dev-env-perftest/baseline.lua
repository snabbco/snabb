#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

local ffi      = require("ffi")
local app      = require("core.app")
local lib      = require("core.lib")
local packet   = require("core.packet")
local Intel82599 = require("apps.intel_mp.intel_mp").Intel82599

local c = config.new()

config.app(c, "e0", Intel82599, {
	pciaddr = "0000:01:00.0",
	macaddr = "00:00:00:00:01:01",
})

config.app(c, "e1", Intel82599, {
	pciaddr = "0000:03:00.0",
	macaddr = "00:00:00:00:01:02",
})

config.link(c, "e0.output -> e1.input")
config.link(c, "e1.output -> e0.input")

engine.configure(c)
engine.main({report = {showlinks=true}})

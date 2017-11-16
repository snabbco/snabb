#!snabb/src/snabb snsh
io.stdout:setvbuf'no'
io.stderr:setvbuf'no'

local ffi      = require("ffi")
local app      = require("core.app")
local lib      = require("core.lib")
local packet   = require("core.packet")
local pci      = require("lib.hardware.pci")

_NAME = ""
local Counter = {}

local n = 0

function Counter:new()
	timer.activate(
		timer.new("counting",
			function(t)
				print(string.format("Speed: %4.2f M/s", n/1024/1024))
				n = 0
			end, 1*1e9, "repeating"))
	return setmetatable({}, {__index = self})
end

function Counter:push()
	local rx = self.input.rx
	if rx == nil then return end
	while not link.empty(rx) do 
		local p = link.receive(rx)
		n = n + p.length
		packet.free(p)
	end
end

local c = config.new()

config.app(c, "count", Counter)

local eth = pci.device_info("03:00.1")

config.app(c, "eth", require(eth.driver).driver, {
	pciaddr = eth.pciaddress,
	macaddr = "00:00:00:00:02:02",
})

config.link(c, "eth."..eth.tx.." -> count.rx")

engine.configure(c)
engine.main({report = {showlinks=true}})

#!../../snabb snsh

local args = main.parameters
-- delay nic queue pcap
assert(#args == 4, "testsend.lua delay pciaddr queueno pcap")
local intel = require("apps.intel1g.intel1g")
local pcap = require("apps.pcap.pcap")
local delay = require("apps.test.delayed_start")

local c = config.new()
config.app(c, "pcap", pcap.PcapReader, args[4])
config.app(c, "delay", delay.Delayed_start, tonumber(args[1]))
config.app(c, "nic", intel.Intel1g, {pciaddr=args[2], txq = tonumber(args[3])})

config.link(c, "pcap.output -> delay.input")
config.link(c, "delay.output -> nic.input")
engine.configure(c)
engine.main({duration = tonumber(args[1]) + 3})
os.exit(0)

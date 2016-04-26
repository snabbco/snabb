#!../../snabb snsh

local args = main.parameters
-- time nic queue
assert(#args == 3)
local intel = require("apps.intel1g.intel1g")
local basic = require("apps.basic.basic_apps")
local counter = require("core.counter")
local S = require("syscall")
local lib = require("core.lib")

local c = config.new()
config.app(c, "nic", intel.Intel1g, {pciaddr=args[2], rxq = tonumber(args[3])})
config.app(c, "sink", basic.Sink)
config.link(c, "nic.output -> sink.input")
engine.configure(c)
engine.main({duration = tonumber(args[1])})
local slink = counter.read(engine.app_table.sink.input.input.stats.txpackets)
lib.writefile("results." .. tostring(S.getpid()), tostring(tonumber(slink)))
os.exit(0)

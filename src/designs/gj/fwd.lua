#!/usr/bin/env snabb

local Intel82599 = require("apps.intel.intel_app").Intel82599

local c = config.new()

config.app(c, "nic_port8", Intel82599, [[{pciaddr = "0000:83:00.0"}]])
config.app(c, "nic_port9", Intel82599, [[{pciaddr = "0000:83:00.1"}]])

config.link(c, "nic_port8.tx -> nic_port9.rx");
config.link(c, "nic_port9.tx -> nic_port8.rx");

engine.configure(c)
buffer.preallocate(10000)

engine.main({duration=40})
engine.report()
main.exit(0)

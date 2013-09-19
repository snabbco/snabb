module(...,package.seeall)

require("core.memory").selftest()
require("lib.hardware.pci").selftest()
require("apps.vhost.vhost").selftest()



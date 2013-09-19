module(...,package.seeall)

require("core.memory").selftest()
require("lib.virtio.virtio").selftest()
require("lib.hardware.pci").selftest()



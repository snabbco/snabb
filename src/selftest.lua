module(...,package.seeall)

require("memory").selftest()
require("virtio").selftest()
require("pci").selftest()



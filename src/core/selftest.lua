-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

require("core.memory").selftest()
require("lib.hardware.pci").selftest()
require("apps.vhost.vhost").selftest()



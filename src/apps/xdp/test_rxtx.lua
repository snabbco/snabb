module(...,package.seeall)

local xdp = require("apps.xdp.xdp")

function selftest ()
   print("selftest: apps.xdp.test_rxtx")
   local xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues = xdp.selftest_init()
   print("test: rxtx")
   xdp.selftest_rxtx(xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues)
   print("test: duplex")
   xdp.selftest_duplex(xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues)
   print("selftest ok")
end
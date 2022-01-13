module(...,package.seeall)

local xdp = require("apps.xdp.xdp")

function selftest ()
   print("selftest: apps.xdp.test_share")
   local xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues = xdp.selftest_init()
   if nqueues <= 1 then
      os.exit(engine.test_skipped_code)
   end
   print("test: share_interface")
   xdp.selftest_share_interface(xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues)
   print("selftest ok")
end
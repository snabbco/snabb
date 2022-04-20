module(...,package.seeall)

local xdp = require("apps.xdp.xdp")

function selftest ()
   print("selftest: apps.xdp.test_filter_pass")
   local xdpdeva, xdpmaca, xdpdevb, xdpmacb, nqueues = xdp.selftest_init()
   if nqueues > 1 then
      os.exit(engine.test_skipped_code)
   end
   print("test: rxtx_match_filter_pass")
   xdp.selftest_rxtx_match_filter_pass(xdpdeva, xdpmaca, xdpdevb, xdpmacb)
   print("selftest ok")
end
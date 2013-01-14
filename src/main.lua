module(...,package.seeall)

function main ()
   require "strict"

--   local jit_dump = require "jit.dump"
--   local jit_v = require "jit.v"

--   jit_dump.start("", "snabbswitch-jit-dump.txt")

   -- Register the available drivers by the PCI vendor and device.
   local pci = require("pci")
   pci.register('0x8086', '0x10d3', 'intel')
   pci.register('0x8086', '0x105e', 'intel_82571')

   require "selftest"

end

function handler (reason)
   print(reason)
   print(debug.traceback())
   -- debug.debug()
   os.exit(1)
end

xpcall(main, handler)


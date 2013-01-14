module(...,package.seeall)

function main ()
   require "strict"

--   local jit_dump = require "jit.dump"
--   local jit_v = require "jit.v"

--   jit_dump.start("", "snabbswitch-jit-dump.txt")

   require "selftest"

end

function handler (reason)
   print(reason)
   print(debug.traceback())
   -- debug.debug()
   os.exit(1)
end

xpcall(main, handler)


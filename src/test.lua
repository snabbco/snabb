module(...,package.seeall)

local C = require("ffi").C

function waitfor(name, test, attempts, interval)
   io.write("Waiting for "..name..".")
   for count = 1,attempts do
      if test() then
	 print(" ok")
	 return
      end
      C.usleep(interval)
      io.write(".")
      io.flush()
   end
   print("")
   error("timeout waiting for " .. name)
end


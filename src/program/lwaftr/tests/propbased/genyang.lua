module(..., package.seeall)

--local S = require("syscall")
--local snabb_cmd = ("/proc/%d/exe"):format(S.getpid())

function generate_yang(pid)
   return string.format("./snabb config get %s /", pid)
end

function run_yang(yang_cmd)
   local f = io.popen(yang_cmd)
   local result = f:read("*a")
   f:close()
   return result
end

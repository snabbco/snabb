module(..., package.seeall)

--local S = require("syscall")
--local snabb_cmd = ("/proc/%d/exe"):format(S.getpid())

function generate_yang(pid)
   return string.format("./snabb config get %s /", pid)
end

function run_yang(yang_cmd)
   return io.popen(yang_cmd):read("*a")
end

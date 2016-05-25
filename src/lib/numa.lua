module(..., package.seeall)

local S = require("syscall")

function set_cpu (cpu)
   local cpu_set = S.sched_getaffinity()
   cpu_set:zero()
   cpu_set:set(cpu)
   S.sched_setaffinity(0, cpu_set)

   local policy = S.get_mempolicy()
   mask:zero()
   mask:set(cpu) -- fixme should be numa node
   S.set_mempolicy(policy.mode, policy.mask)
   if not S.sched_setscheduler(0, "fifo", 1) then
      fatal('Failed to enable real-time scheduling.  Try running as root.')
   end
end

function selftest ()
   print(S.sched_getaffinity())
   print(S.get_mempolicy().mask)
end

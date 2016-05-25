module(..., package.seeall)

local S = require("syscall")

function cpu_get_numa_node (cpu)
   local node = 0
   while true do
      local node_dir = S.open('/sys/devices/system/node/node'..node,
                              'rdonly, directory')
      if not node_dir then return end
      local found = S.readlinkat(node_dir, 'cpu'..cpu)
      node_dir:close()
      if found then return node end
      node = node + 1
   end
end

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
   print(cpu_get_numa_node(0))
   print(S.sched_getaffinity())
   print(S.get_mempolicy().mask)
end

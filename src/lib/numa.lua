module(..., package.seeall)

local S = require("syscall")
local pci = require("lib.hardware.pci")

local bound_cpu
local bound_numa_node

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

function pci_get_numa_node (addr)
   addr = pci.qualified(addr)
   local file = assert(io.open('/sys/bus/pci/devices/'..addr..'/numa_node'))
   local node = assert(tonumber(file:read()))
   -- node can be -1.
   if node >= 0 then return node end
end

function choose_numa_node_for_pci_addresses (addrs, require_affinity)
   local chosen_node, chosen_because_of_addr
   for _, addr in ipairs(addrs) do
      local node = pci_get_numa_node(addr)
      if not node or node == chosen_node then
         -- Keep trucking.
      elseif not chosen_node then
         chosen_node = node
         chosen_because_of_addr = addr
      else
         local msg = string.format(
            "PCI devices %s and %s have different NUMA node affinities",
            chosen_because_of_addr, addr)
         if require_affinity then error(msg) else print('Warning: '..msg) end
      end
   end
   return chosen_node
end

function unbind_cpu ()
   local cpu_set = S.sched_getaffinity()
   cpu_set:zero()
   for i = 0, 1023 do cpu_set:set(i) end
   assert(S.sched_setaffinity(0, cpu_set))
   bound_cpu = nil
end

function bind_to_cpu (cpu)
   if cpu == bound_cpu then return end
   if not cpu then return unbind_cpu() end
   assert(not bound_cpu, "already bound")

   assert(S.sched_setaffinity(0, cpu))
   local cpu_and_node = S.getcpu()
   assert(cpu_and_node.cpu == cpu)
   bound_cpu = cpu

   bind_to_numa_node (cpu_and_node.node)
end

function unbind_numa_node ()
   assert(S.set_mempolicy('default'))
   bound_numa_node = nil
end

function bind_to_numa_node (node)
   if node == bound_numa_node then return end
   if not node then return unbind_numa_node() end
   assert(not bound_numa_node, "already bound")

   assert(S.set_mempolicy('bind', node))
   bound_numa_node = node
end

function prevent_preemption(priority)
   if not S.sched_setscheduler(0, "fifo", priority or 1) then
      fatal('Failed to enable real-time scheduling.  Try running as root.')
   end
end

function selftest ()
   print('selftest: numa')
   bind_to_cpu(0)
   assert(bound_cpu == 0)
   assert(bound_numa_node == 0)
   assert(S.getcpu().cpu == 0)
   assert(S.getcpu().node == 0)
   bind_to_cpu(nil)
   assert(bound_cpu == nil)
   assert(bound_numa_node == 0)
   assert(S.getcpu().node == 0)
   bind_to_numa_node(nil)
   assert(bound_cpu == nil)
   assert(bound_numa_node == nil)
   print('selftest: numa: ok')
end

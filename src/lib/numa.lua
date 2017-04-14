-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- Call bind_to_cpu(1) to bind the current Snabb process to CPU 1 (for
-- example), to bind its memory to the corresponding NUMA node, to
-- migrate mapped pages to that NUMA node, and to arrange to warn if
-- you use a PCI device from a remote NUMA node.  See README.numa.md
-- for full API documentation.

local S = require("syscall")
local pci = require("lib.hardware.pci")

local bound_cpu
local bound_numa_node

local node_path = '/sys/devices/system/node/node'
local MAX_CPU = 1023

function cpu_get_numa_node (cpu)
   local node = 0
   while true do
      local node_dir = S.open(node_path..node, 'rdonly, directory')
      if not node_dir then return end
      local found = S.readlinkat(node_dir, 'cpu'..cpu)
      node_dir:close()
      if found then return node end
      node = node + 1
   end
end

function has_numa ()
   local node1 = S.open(node_path..tostring(1), 'rdonly, directory')
   if not node1 then return false end
   node1:close()
   return true
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

function check_affinity_for_pci_addresses (addrs)
   local policy = S.get_mempolicy()
   if policy.mode == S.c.MPOL_MODE['default'] then
      if has_numa() then
         print('Warning: No NUMA memory affinity.')
         print('Pass --cpu to bind to a CPU and its NUMA node.')
      end
   elseif policy.mode ~= S.c.MPOL_MODE['bind'] then
      print("Warning: NUMA memory policy already in effect, but it's not --membind.")
   else
      local node = S.getcpu().node
      local node_for_pci = choose_numa_node_for_pci_addresses(addrs)
      if node_for_pci and node ~= node_for_pci then
         print("Warning: Bound NUMA node does not have affinity with PCI devices.")
      end
   end
end

function unbind_cpu ()
   local cpu_set = S.sched_getaffinity()
   cpu_set:zero()
   for i = 0, MAX_CPU do cpu_set:set(i) end
   assert(S.sched_setaffinity(0, cpu_set))
   bound_cpu = nil
end

function bind_to_cpu (cpu)
   if cpu == bound_cpu then return end
   if not cpu then return unbind_cpu() end
   assert(not bound_cpu, "already bound")

   assert(S.sched_setaffinity(0, cpu),
      ("Couldn't set affinity for cpu %s"):format(cpu))
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

   -- Migrate any pages that might have the wrong affinity.
   local from_mask = assert(S.get_mempolicy(nil, nil, nil, 'mems_allowed')).mask
   assert(S.migrate_pages(0, from_mask, node))

   bound_numa_node = node
end

function prevent_preemption(priority)
   assert(S.sched_setscheduler(0, "fifo", priority or 1),
      'Failed to enable real-time scheduling.  Try running as root.')
end

function selftest ()

   function test_cpu(cpu)
      local node = cpu_get_numa_node(cpu)
      bind_to_cpu(cpu)
      assert(bound_cpu == cpu)
      assert(bound_numa_node == node)
      assert(S.getcpu().cpu == cpu)
      assert(S.getcpu().node == node)
      bind_to_cpu(nil)
      assert(bound_cpu == nil)
      assert(bound_numa_node == node)
      assert(S.getcpu().node == node)
      bind_to_numa_node(nil)
      assert(bound_cpu == nil)
      assert(bound_numa_node == nil)
   end

   print('selftest: numa')
   local cpu_set = S.sched_getaffinity()
   for cpuid = 0, MAX_CPU do
      if cpu_set:get(cpuid) then
         test_cpu(cpuid)
      end
   end
   print('selftest: numa: ok')
end

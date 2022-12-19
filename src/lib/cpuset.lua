-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local numa = require('lib.numa')
local S = require('syscall')

local CPUSet = {}

function new()
   return setmetatable({by_node={}}, {__index=CPUSet})
end

do
   local cpuset = false
   function global_cpuset()
      if not cpuset then cpuset = new() end
      return cpuset
   end
end

local function available_cpus (node)
   local function subtract (s, t)
      local ret = {}
      for k,_ in pairs(s) do
         if not t[k] then table.insert(ret, k) end
      end
      table.sort(ret)
      return ret
   end
   -- XXX: Add sched_getaffinity cpus.
   return subtract(numa.node_cpus(node), numa.isolated_cpus())
end

function CPUSet:bind_to_numa_node()
   local nodes = {}
   for node, _ in pairs(self.by_node) do table.insert(nodes, node) end
   if #nodes == 0 then
      print("No CPUs available; not binding to any NUMA node.")
   elseif #nodes == 1 then
      numa.bind_to_numa_node(nodes[1])
      local cpus = available_cpus(nodes[1])
      assert(#cpus > 0, 'Not available CPUs')
      numa.bind_to_cpu(cpus, 'skip-perf-checks')
      print(("Bound main process to NUMA node: %s (CPU %s)"):format(nodes[1], cpus[1]))
   else
      print("CPUs available from multiple NUMA nodes: "..table.concat(nodes, ","))
      print("Not binding to any NUMA node.")
   end
end

function CPUSet:add_from_string(cpus)
   for cpu,_ in pairs(numa.parse_cpuset(cpus)) do
      self:add(cpu)
   end
end

function CPUSet:add(cpu)
   local node = numa.cpu_get_numa_node(cpu)
   assert(node ~= nil, 'Failed to get NUMA node for CPU: '..cpu)
   if self.by_node[node] == nil then self.by_node[node] = {} end
   assert(self.by_node[node][cpu] == nil, 'CPU already in set: '..cpu)
   self.by_node[node][cpu] = true
end

function CPUSet:contains(cpu)
   local node = numa.cpu_get_numa_node(cpu)
   assert(node ~= nil, 'Failed to get NUMA node for CPU: '..cpu)
   return self.by_node[node] and (self.by_node[node][cpu] ~= nil)
end

function CPUSet:remove (cpu)
   assert(self:contains(cpu), 'CPU not in set: '..cpu)
   local node = numa.cpu_get_numa_node(cpu)
   if self.by_node[node][cpu] == false then
      print("Warning: removing bound CPU from set: "..cpu)
   end
   self.by_node[node][cpu] = nil
end

function CPUSet:list ()
   local list = {}
   for node, cpus in pairs(self.by_node) do
      for cpu in pairs(cpus) do
         table.insert(list, cpu)
      end
   end
   return list
end

function CPUSet:acquire_for_pci_addresses(addrs, worker)
   return self:acquire(numa.choose_numa_node_for_pci_addresses(addrs), worker)
end

function CPUSet:acquire(on_node, worker)
   for node, cpus in pairs(self.by_node) do
      if on_node == nil or on_node == node then
         for cpu, avail in pairs(cpus) do
            if avail then
               cpus[cpu] = false
               return cpu
            end
         end
      end
   end
   if on_node ~= nil then
      for node, cpus in pairs(self.by_node) do
         for cpu, avail in pairs(cpus) do
            if avail then
               print("Warning: No CPU available on local NUMA node "..on_node)
               print("Warning: Assigning CPU "..cpu.." from remote node "..node)
               cpus[cpu] = false
               return cpu
            end
         end
      end
   end
   for node, cpus in pairs(self.by_node) do
      print(("Warning: All assignable CPUs in use; "..
             "leaving data-plane worker '%s' without assigned CPU."):format(worker))
      return
   end
   print(("Warning: No assignable CPUs declared; "..
         "leaving data-plane worker '%s' without assigned CPU."):format(worker))
end

function CPUSet:release(cpu)
   local node = numa.cpu_get_numa_node(cpu)
   assert(node ~= nil, 'Failed to get NUMA node for CPU: '..cpu)
   for x, avail in pairs(self.by_node[node]) do
      if x == cpu then
         assert(self.by_node[node][cpu] == false)
         self.by_node[node][cpu] = true
         return
      end
   end
   error('CPU not found on NUMA node: '..cpu..', '..node)
end

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

local function trim (str)
   return str:gsub("^%s", ""):gsub("%s$", "")
end

local function parse_cpulist (cpus)
   local ret = {}
   cpus = trim(cpus)
   if #cpus == 0 then return ret end
   for range in cpus:split(',') do
      local lo, hi = range:match("^%s*([^%-]*)%s*-%s*([^%-%s]*)%s*$")
      if lo == nil then lo = range:match("^%s*([^%-]*)%s*$") end
      assert(lo ~= nil, 'invalid range: '..range)
      lo = assert(tonumber(lo), 'invalid range begin: '..lo)
      assert(lo == math.floor(lo), 'invalid range begin: '..lo)
      if hi ~= nil then
         hi = assert(tonumber(hi), 'invalid range end: '..hi)
         assert(hi == math.floor(hi), 'invalid range end: '..hi)
         assert(lo < hi, 'invalid range: '..range)
      else
         hi = lo
      end
      for cpu=lo,hi do table.insert(ret, cpu) end
   end
   return ret
end

local function parse_cpulist_from_file (path)
   local fd = assert(io.open(path))
   if not fd then return {} end
   local ret = parse_cpulist(fd:read("*all"))
   fd:close()
   return ret
end

local function available_cpus (node)
   local function set (t)
      local ret = {}
      for _,v in pairs(t) do ret[tostring(v)] = true end
      return ret
   end
   local function cpus_in_node (node)
      local node_path = '/sys/devices/system/node/node'..node
      return set(parse_cpulist_from_file(node_path..'/cpulist'))
   end
   local function isolated_cpus ()
      return set(parse_cpulist_from_file('/sys/devices/system/cpu/isolated'))
   end
   local function subtract (s, t)
      local ret = {}
      for k,_ in pairs(s) do
         if not t[k] then table.insert(ret, k) end
      end
      table.sort(ret)
      return ret
   end
   -- XXX: Add sched_getaffinity cpus.
   return subtract(cpus_in_node(node), isolated_cpus())
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
      numa.bind_to_cpu(cpus)
      print(("Bound main process to NUMA node: %s (CPU %s)"):format(nodes[1], cpus[1]))
   else
      print("CPUs available from multiple NUMA nodes: "..table.concat(nodes, ","))
      print("Not binding to any NUMA node.")
   end
end

function CPUSet:add_from_string(cpus)
   for _, cpu in ipairs(parse_cpulist(cpus)) do
      self:add(cpu)
   end
end

function CPUSet:add(cpu)
   local node = numa.cpu_get_numa_node(cpu)
   assert(node ~= nil, 'Failed to get NUMA node for CPU: '..cpu)
   if self.by_node[node] == nil then self.by_node[node] = {} end
   assert(self.by_node[cpu] == nil, 'CPU already in set: '..cpu)
   self.by_node[node][cpu] = true
end

function CPUSet:acquire_for_pci_addresses(addrs)
   return self:acquire(numa.choose_numa_node_for_pci_addresses(addrs))
end

function CPUSet:acquire(on_node)
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
             "leaving data-plane PID %d without assigned CPU."):format(S.getpid()))
      return
   end
   print(("Warning: No assignable CPUs declared; "..
         "leaving data-plane PID %d without assigned CPU."):format(S.getpid()))
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

function selftest ()
   print('selftest: cpuset')
   local cpus = parse_cpulist("0-5,7")
   assert(#cpus == 7 and cpus[6] == 5 and cpus[7] == 7)
   cpus = parse_cpulist("1")
   assert(#cpus == 1 and cpus[1] == 1)
   assert(#parse_cpulist("\n") == 0)
   assert(#parse_cpulist("") == 0)
   print('selftest: ok')
end

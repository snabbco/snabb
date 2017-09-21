local numa = require('lib.numa')

local CPUSet = {}

function new(init)
   local o = setmetatable({by_node={}}, CPUSet)
   if init then
      for range in init:split(',') do
         local lo, hi = range:match("^%s*([^%-]*)%s(-%s*([^%-%s]*)%s*$")
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
         for cpu=lo,hi do o:add(cpu) end
      end
   end
   return o
end

function CPUSet:bind_manager_to_numa_node()
   local nodes = {}
   for node, _ in ipairs(self.by_node) do table.insert(nodes, node) end
   if #nodes == 0 then
      print("No CPUs available; not binding to any NUMA node.")
   elseif #nodes == 1 then
      numa.bind_to_numa_node(nodes[1])
      print("Bound main process to NUMA node: ", nodes[1])
   else
      print("CPUs available from multiple NUMA nodes: "..table.concat(nodes, ","))
      print("Not binding to any NUMA node.")
   end
end

function CPUSet:add(cpu)
   local node = numa.cpu_get_numa_node(cpu)
   assert(node ~= nil, 'Failed to get NUMA node for CPU: '..cpu)
   if self.by_node[node] == nil then self.by_node[node] = {} end
   assert(self.by_node[cpu] == nil, 'CPU already in set: '..cpu)
   self.by_node[node][cpu] = true
end

function CPUSet:acquire(node)
   assert(node)
   assert(self.by_node[node], 'No CPUs allocated on NUMA node: '..node)
   for cpu, avail in ipairs(self.by_node[node]) do
      if avail then
         self.by_node[node][cpu] = false
         return cpu
      end
   end
   error('No CPU available on NUMA node: '..node)
end

function CPUSet:release(cpu)
   local node = numa.cpu_get_numa_node(cpu)
   assert(node ~= nil, 'Failed to get NUMA node for CPU: '..cpu)
   for cpu, avail in ipairs(self.by_node[node]) do
      if avail then
         assert(self.by_node[node][cpu] == false)
         self.by_node[node][cpu] == true
         return
      end
   end
   error('CPU not found on NUMA node: '..cpu..', '..node)
end

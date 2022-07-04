-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

-- Call bind_to_cpu(1) to bind the current Snabb process to CPU 1 (for
-- example), to bind its memory to the corresponding NUMA node, to
-- migrate mapped pages to that NUMA node, and to arrange to warn if
-- you use a PCI device from a remote NUMA node.  See README.numa.md
-- for full API documentation.

local S = require("syscall")
local pci = require("lib.hardware.pci")
local lib = require("core.lib")

local bound_cpu
local bound_numa_node

local node_path = '/sys/devices/system/node/node'
local MAX_CPU = 1023

local function warn(fmt, ...)
   io.stderr:write(string.format("Warning: ".. fmt .. "\n", ...))
   io.stderr:flush()
end

local function die(fmt, ...)
   error(string.format(fmt, ...))
end

local function trim (str)
   return str:gsub("^%s", ""):gsub("%s$", "")
end

function parse_cpuset (cpus)
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
   return lib.set(unpack(ret))
end

local function parse_cpuset_from_file (path)
   local fd = assert(io.open(path))
   if not fd then return {} end
   local ret = parse_cpuset(fd:read("*all"))
   fd:close()
   return ret
end

function node_cpus (node)
   return parse_cpuset_from_file(node_path..node..'/cpulist')
end

function isolated_cpus (node)
   return parse_cpuset_from_file('/sys/devices/system/cpu/isolated')
end

function cpu_get_numa_node (cpu)
   local node = 0
   while true do
      local node_dir = S.open(node_path..node, 'rdonly, directory')
      if not node_dir then return 0 end -- default NUMA node
      local found = S.readlinkat(node_dir, 'cpu'..cpu)
      node_dir:close()
      if found then return node end
      node = node + 1
   end
end

local function supports_numa ()
   local node0 = S.open(node_path..tostring(0), 'rdonly, directory')
   if not node0 then return false end
   node0:close()
   return true
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
   return math.max(0, node)
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
         local warn = warn
         if require_affinity then warn = die end
         warn("PCI devices %s and %s have different NUMA node affinities",
              chosen_because_of_addr, addr)
      end
   end
   return chosen_node
end

function check_affinity_for_pci_addresses (addrs)
   local policy = S.get_mempolicy()
   if policy.mode == S.c.MPOL_MODE['default'] then
      if has_numa() then
         warn('No NUMA memory affinity.\n'..
                 'Pass --cpu to bind to a CPU and its NUMA node.')
      end
   elseif (policy.mode ~= S.c.MPOL_MODE['bind'] and
           policy.mode ~= S.c.MPOL_MODE['preferred']) then
      warn("NUMA memory policy already in effect, but it's not --membind or --preferred.")
   else
      local node = S.getcpu().node
      local node_for_pci = choose_numa_node_for_pci_addresses(addrs)
      if node_for_pci and node ~= node_for_pci then
         warn("Bound NUMA node does not have affinity with PCI devices.")
      end
   end
end

local irqbalanced_checked = false
local function assert_irqbalanced_disabled (warn)
   if irqbalanced_checked then return end
   irqbalanced_checked = true
   local env_path = os.getenv('PATH')
   if not env_path then return end
   for path in env_path:split(':') do
      if S.stat(path..'/irqbalance') then
         if S.stat('/etc/default/irqbalance') then
            for line in io.lines('/etc/default/irqbalance') do
               if line:match('^ENABLED=0') then return end
            end
         end
         warn('Irqbalanced detected; this will hurt performance!  %s',
              'Consider uninstalling via "sudo apt-get remove irqbalance" and rebooting.')
      end
   end
end

local function read_cpu_performance_governor (cpu)
   local path = '/sys/devices/system/cpu/cpu'..cpu..'/cpufreq/scaling_governor'
   local f = io.open(path)
   if not f then return "unknown" end
   local gov = f:read()
   f:close()
   return gov
end

local function check_cpu_performance_tuning (cpu, strict)
   local warn = warn
   if strict then warn = die end
   assert_irqbalanced_disabled(warn)
   local gov = read_cpu_performance_governor(cpu)
   if not gov:match('performance') then
      warn('Expected performance scaling governor for CPU %s, but got "%s"',
           cpu, gov)
   end

   if not isolated_cpus()[cpu] then
      warn('Expected dedicated core, but CPU %s is not in isolcpus set', cpu)
   end
end

function unbind_cpu ()
   local cpu_set = S.sched_getaffinity()
   cpu_set:zero()
   for i = 0, MAX_CPU do cpu_set:set(i) end
   assert(S.sched_setaffinity(0, cpu_set))
   bound_cpu = nil
end

function bind_to_cpu (cpu, skip_perf_checks)
   local function contains (t, e)
      for k,v in ipairs(t) do
         if tonumber(v) == tonumber(e) then return true end
      end
      return false
   end
   if not cpu then return unbind_cpu() end
   if cpu == bound_cpu then return end
   assert(not bound_cpu, "already bound")

   if type(cpu) ~= 'table' then cpu = {cpu} end
   assert(S.sched_setaffinity(0, cpu),
      ("Couldn't set affinity for cpuset %s"):format(table.concat(cpu, ',')))
   local cpu_and_node = S.getcpu()
   assert(contains(cpu, cpu_and_node.cpu))
   bound_cpu = cpu_and_node.cpu

   bind_to_numa_node (cpu_and_node.node)

   if not skip_perf_checks then check_cpu_performance_tuning(bound_cpu) end
end

function unbind_numa_node ()
   if has_numa() then
      assert(S.set_mempolicy('default'))
   end
   bound_numa_node = nil
end

function bind_to_numa_node (node, policy)
   if node == bound_numa_node then return end
   if not node then return unbind_numa_node() end
   assert(not bound_numa_node, "already bound")

   if has_numa() then
      assert(S.set_mempolicy(policy or 'preferred', node))

      -- Migrate any pages that might have the wrong affinity.
      local from_mask = assert(S.get_mempolicy(nil, nil, nil, 'mems_allowed')).mask
      from_mask[node] = false
      local ok, err = S.migrate_pages(0, from_mask, node)
      if not ok then
         warn("Failed to migrate pages to NUMA node %d: %s\n",
              node, tostring(err))
      end
   end

   bound_numa_node = node
end

function prevent_preemption(priority)
   assert(S.sched_setscheduler(0, "fifo", priority or 1),
      'Failed to enable real-time scheduling.  Try running as root.')
end

function selftest ()

   local cpus = parse_cpuset("0-5,7")
   for i=0,5 do assert(cpus[i]) end
   assert(not cpus[6])
   assert(cpus[7])
   do
      local count = 0
      for k,v in pairs(cpus) do count = count + 1 end
      assert(count == 7)
   end
   assert(parse_cpuset("1")[1])

   function test_cpu(cpu)
      local node = cpu_get_numa_node(cpu)
      bind_to_cpu(cpu, 'skip-perf-checks')
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

   function test_pci_affinity (pciaddr)
      check_affinity_for_pci_addresses({pciaddr})
      local node = choose_numa_node_for_pci_addresses({pciaddr}, true)
      bind_to_numa_node(node)
      assert(bound_numa_node == node)
      check_affinity_for_pci_addresses({pciaddr})
      bind_to_numa_node(nil)
      assert(bound_numa_node == nil)
   end

   print('selftest: numa')
   local cpu_set = S.sched_getaffinity()
   for cpuid = 0, MAX_CPU do
      if cpu_set:get(cpuid) then
         test_cpu(cpuid)
      end
   end
   local pciaddr = os.getenv("SNABB_PCI0")
   if pciaddr then
      test_pci_affinity(pciaddr)
   end

   print('selftest: numa: ok')
end

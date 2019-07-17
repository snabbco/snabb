-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- pmu.lua: Lua interface to the CPU Performance Monitoring Unit
module(..., package.seeall)

-- See README.pmu.md for API and examples.

local pmu_cpu = require("lib.pmu_cpu")
local pmu_x86 = require("lib.pmu_x86")
local ffi = require("ffi")
local lib = require("core.lib")

local S = require("syscall")

-- defs: counter definitions
--   nil => not initialized
--   false => none available
--   table => name->code mappings
local defs = nil

-- enabled: array of names of the enabled counters
local enabled = nil

-- Scan the counter definitions for the set of counters that are
-- available on the running CPU.
local function scan_available_counters ()
   if defs then return defs end
   defs = {}
   for i, set in ipairs(pmu_cpu) do
      local cpu, version, kind, list = unpack(set)
      -- XXX Only supporting "core" counters at present i.e. the
      -- counters built into the CPU core.
      if cpu == pmu_x86.cpu_model and kind == 'core' then
         defs = defs
         for k, v in pairs(list) do defs[k] = v end
      end
   end
end

-- Return an array containing the CPUs that we have affinity with.
local function cpu_set ()
   local t = {}
   local set = S.sched_getaffinity()
   for i = 0, 63 do
      if set:get(i) then table.insert(t, i) end
   end
   return t
end

-- Return true if PMU functionality is available. 
-- Otherwise return false and a string explaining why.
function is_available ()
   if #cpu_set() ~= 1 then
      return false, "single core cpu affinity required" 
   end
   if not pmu_x86.enable_msr() then
      return false, "requires /dev/cpu/*/msr (Linux 'msr' module)"
   end
   if not (pmu_x86.ncounters > 0) then
      return false, "CPU not supported: " .. pmu_x86.cpu_model
   end
   scan_available_counters()
   return true
end

counter_set_t = ffi.typeof("int64_t [$]", pmu_x86.ncounters)

function new_counter_set ()
   return ffi.new(counter_set_t)
end

function to_table (set)
   local t = {}
   for i = 1, #enabled do t[enabled[i]] = tonumber(set[i-1]) end
   return t
end

local current_counter_set = nil
local base_counters = ffi.new(counter_set_t)
local tmp_counters = ffi.new(counter_set_t)

function switch_to (set)
   -- Credit the previous counter set for its events
   if current_counter_set then
      pmu_x86.rdpmc_multi(tmp_counters)
      for i = 0, pmu_x86.ncounters-1 do
         local v = tmp_counters[i] - base_counters[i]
         -- Account for wrap-around of the 40-bit counter value.
         if v < 0 then v = v + bit.lshift(1, 40) end
         current_counter_set[i] = current_counter_set[i] + v
      end
   end
   -- Switch_To to the new set and "start the clock"
   current_counter_set = set
   pmu_x86.rdpmc_multi(base_counters)
end

-- API function (see above)
function setup (patterns)
   local avail, err = is_available()
   if not avail then
      error("PMU not available: " .. err)
   end
   pmu_x86.enable_rdpmc()
   local set = {}
   for event in pairs(defs) do
      for _, pattern in pairs(patterns or {}) do
         if event:match(pattern) then 
            table.insert(set, event) 
         end
      end
   end
   -- Allow selecting events by raw code
   for _, pattern in pairs(patterns or {}) do
      if pattern:match("^0x") then
         table.insert(set, pattern) 
      end
   end
   table.sort(set)
   local ndropped = math.max(0, #set - pmu_x86.ngeneral)
   while (#set - pmu_x86.ngeneral) > 0 do table.remove(set) end
   local cpu = cpu_set()[1]
   local used
   enabled, used = pmu_x86.init_events(cpu, #set)
   for n = 0, #set-1 do
      local code = defs[set[n+1]] or tonumber(set[n+1])
      pmu_x86.enable_event(cpu, n+used, code)
   end
   for i = 1, #set do table.insert(enabled, set[i]) end
   return ndropped
end

-- API function (see above)
function report (tab, aux)
   aux = aux or {}
   local data = {}
   for k,v in pairs(tab) do  table.insert(data, {k=k,v=v})  end
   -- Sort fixed-purpose counters to come first in definite order
   local fixed = {cycles='0000', ref_cycles='0001', instructions='0002'}
   table.sort(data, function(x,y)
                       return (fixed[x.k] or x.k) < (fixed[y.k] or y.k)
                    end)
   local auxnames, auxvalues = {}, {}
   for k,v in pairs(aux) do 
      table.insert(auxnames,k) 
      table.insert(auxvalues,v) 
   end
   -- print titles
   io.write(("%-40s %14s"):format("EVENT", "TOTAL"))
   for i = 1, #auxnames do
      io.write(("%12s"):format("/"..auxnames[i]))
   end
   print()
   -- include aux values in results
   for i = 1, #auxnames do
      table.insert(data, {k=auxnames[i], v=auxvalues[i]})
   end
   -- print values
   for i = 1, #data do
      io.write(("%-40s %14s"):format(data[i].k, core.lib.comma_value(data[i].v)))
      for j = 1, #auxnames do
         io.write(("%12.3f"):format(tonumber(data[i].v/auxvalues[j])))
      end
      print()
   end
end

-- API function (see above)
function measure (f,  events, aux)
   setup(events)
   local set = new_counter_set()
   switch_to(set)
   local res = f()
   switch_to(nil)
   return res, to_table(set)
end

-- API function (see above)
function profile (f,  events, aux, quiet)
   setup(events)
   local set = new_counter_set()
   switch_to(set)
   local res = f()
   switch_to(nil)
   if not quiet then report(to_table(set), aux) end
   return res
end

function selftest ()
   print("selftest: pmu")
   local avail, err = is_available()
   if not avail then
      print("PMU not available:")
      print("  "..err)
      print("selftest skipped")
      os.exit(engine.test_skipped_code)
   end
   local n = 0
   if type(defs) == 'table' then 
      for k,v in pairs(defs) do n=n+1 end   
   end
   print(tostring(n).." counters found for CPU model "..pmu_x86.cpu_model)
   local nloop = 123456
   local set = new_counter_set()
   local f = function ()
      local acc = 0
      for i = 0, nloop do acc = acc + 1 end
      return 42
   end
   local events = {"uops_issued.any",
                   "uops_retired.all",
                   "br_inst_retired.conditional",
                   "br_misp_retired.all_branches"}
   local aux = {packet = nloop, breath = math.floor(nloop/128)}
   print("testing profile()")
   assert(profile(f, events, aux) == 42, "profile return value")
   print("testing measure()")
   local val, tab = measure(f)
   assert(val == 42, "measure return value")
   local n = 0
   for k, v in pairs(tab) do
      print('', k, v)
      n = n + 1
   end
   assert(n >= 2)
   print("selftest ok")
end


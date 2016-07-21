-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local shm = require("core.shm")
local counter = require("core.counter")
local S = require("syscall")
local histogram = require("core.histogram")
local usage = require("program.top.README_inc")

local long_opts = {
   help = "h", list = "l"
}

function clearterm () io.write('\027[2J') end

function run (args)
   local opt = {}
   local object = nil
   function opt.h (arg) print(usage) main.exit(1) end
   function opt.l (arg) object = arg              end
   args = lib.dogetopt(args, opt, "hl:", long_opts)

   if #args > 1 then print(usage) main.exit(1) end
   local target_pid = select_snabb_instance(args[1])

   if     object then list_shm(target_pid, object)
   else               top(target_pid) end
end

function select_snabb_instance (pid)
   local instances = shm.children("/")
   if pid then
      -- Try to use given pid
      for _, instance in ipairs(instances) do
         if instance == pid then return pid end
      end
      print("No such Snabb instance: "..pid)
   elseif #instances == 2 then
      -- Two means one is us, so we pick the other.
      local own_pid = tostring(S.getpid())
      if instances[1] == own_pid then return instances[2]
      else                            return instances[1] end
   elseif #instances == 1 then print("No Snabb instance found.")
   else print("Multple Snabb instances found. Select one.") end
   os.exit(1)
end

function list_shm (pid, object)
   local frame = shm.open_frame("/"..pid.."/"..object)
   local sorted = {}
   for name, _ in pairs(frame) do table.insert(sorted, name) end
   table.sort(sorted)
   for _, name in ipairs(sorted) do
      if name ~= 'path' and name ~= 'specs' and  name ~= 'readonly' then
         print_row({30, 30}, {name, tostring(frame[name])})
      end
   end
   shm.delete_frame(frame)
end

function top (instance_pid)
   local instance_tree = "/"..instance_pid
   local counters = open_counters(instance_tree)
   local configs = 0
   local last_stats = nil
   while (true) do
      if configs < counter.read(counters.engine.configs) then
         -- If a (new) config is loaded we (re)open the link counters.
         open_link_counters(counters, instance_tree)
      end
      local new_stats = get_stats(counters)
      if last_stats then
         clearterm()
         print_global_metrics(new_stats, last_stats)
         io.write("\n")
         print_latency_metrics(new_stats, last_stats)
         print_link_metrics(new_stats, last_stats)
         io.flush()
      end
      last_stats = new_stats
      C.sleep(1)
   end
end

function open_counters (tree)
   local counters = {}
   counters.engine = shm.open_frame(tree.."/engine")
   counters.links = {} -- These will be populated on demand.
   return counters
end

function open_link_counters (counters, tree)
   -- Unmap and clear existing link counters.
   for _, link_frame in pairs(counters.links) do
      shm.delete_frame(link_frame)
   end
   counters.links = {}
   -- Open current link counters.
   for _, linkspec in ipairs(shm.children(tree.."/links")) do
      counters.links[linkspec] = shm.open_frame(tree.."/links/"..linkspec)
   end
end

function get_stats (counters)
   local new_stats = {}
   for _, name in ipairs({"configs", "breaths", "frees", "freebytes"}) do
      new_stats[name] = counter.read(counters.engine[name])
   end
   if counters.engine.latency then
      new_stats.latency = counters.engine.latency:snapshot()
   end
   new_stats.links = {}
   for linkspec, link in pairs(counters.links) do
      new_stats.links[linkspec] = {}
      for _, name
      in ipairs({"rxpackets", "txpackets", "rxbytes", "txbytes", "txdrop" }) do
         new_stats.links[linkspec][name] = counter.read(link[name])
      end
   end
   return new_stats
end

local global_metrics_row = {15, 15, 15}
function print_global_metrics (new_stats, last_stats)
   local frees = tonumber(new_stats.frees - last_stats.frees)
   local bytes = tonumber(new_stats.freebytes - last_stats.freebytes)
   local breaths = tonumber(new_stats.breaths - last_stats.breaths)
   print_row(global_metrics_row, {"Kfrees/s", "freeGbytes/s", "breaths/s"})
   print_row(global_metrics_row,
             {float_s(frees / 1000), float_s(bytes / (1000^3)), tostring(breaths)})
end

function summarize_latency (histogram, prev)
   local total = histogram.total
   if prev then total = total - prev.total end
   if total == 0 then return 0, 0, 0 end
   local min, max, cumulative = nil, 0, 0
   for count, lo, hi in histogram:iterate(prev) do
      if count ~= 0 then
	 if not min then min = lo end
	 max = hi
	 cumulative = cumulative + (lo + hi) / 2 * tonumber(count)
      end
   end
   return min, cumulative / tonumber(total), max
end

function print_latency_metrics (new_stats, last_stats)
   local cur, prev = new_stats.latency, last_stats.latency
   if not cur then return end
   local min, avg, max = summarize_latency(cur, prev)
   print_row(global_metrics_row,
             {"Min breath (us)", "Average", "Maximum"})
   print_row(global_metrics_row,
             {float_s(min*1e6), float_s(avg*1e6), float_s(max*1e6)})
   print("\n")
end

local link_metrics_row = {31, 7, 7, 7, 7, 7}
function print_link_metrics (new_stats, last_stats)
   print_row(link_metrics_row,
             {"Links (rx/tx/txdrop in Mpps)", "rx", "tx", "rxGb", "txGb", "txdrop"})
   for linkspec, link in pairs(new_stats.links) do
      if last_stats.links[linkspec] then
         local rx = tonumber(new_stats.links[linkspec].rxpackets - last_stats.links[linkspec].rxpackets)
         local tx = tonumber(new_stats.links[linkspec].txpackets - last_stats.links[linkspec].txpackets)
         local rxbytes = tonumber(new_stats.links[linkspec].rxbytes - last_stats.links[linkspec].rxbytes)
         local txbytes = tonumber(new_stats.links[linkspec].txbytes - last_stats.links[linkspec].txbytes)
         local drop = tonumber(new_stats.links[linkspec].txdrop - last_stats.links[linkspec].txdrop)
         print_row(link_metrics_row,
                   {linkspec,
                    float_s(rx / 1e6), float_s(tx / 1e6),
                    float_s(rxbytes / (1000^3)), float_s(txbytes / (1000^3)),
                    float_s(drop / 1e6)})
      end
   end
end

function pad_str (s, n)
   local padding = math.max(n - s:len(), 0)
   return ("%s%s"):format(s:sub(1, n), (" "):rep(padding))
end

function print_row (spec, args)
   for i, s in ipairs(args) do
      io.write((" %s"):format(pad_str(s, spec[i])))
   end
   io.write("\n")
end

function float_s (n)
   return ("%.2f"):format(n)
end

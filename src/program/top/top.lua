-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local shm = require("core.shm")
local counter = require("core.counter")
local S = require("syscall")
local histogram = require("core.histogram")
local json = require("lib.json")
local macaddress = require("lib.macaddress")
local usage = require("program.top.README_inc")

local long_opts = {
   help = "h", counters = "c", yang = "y"
}

function clearterm () io.write('\027[2J') end

function run (args)
   local opt = {}
   local object = nil
   local yang = false
   function opt.h (arg) print(usage) main.exit(1) end
   function opt.c (arg) object = arg              end
   function opt.y ()    yang = true               end
   args = lib.dogetopt(args, opt, "hc:y", long_opts)

   if #args > 1 then print(usage) main.exit(1) end
   local target_pid = select_snabb_instance(args[1])

   if     object then list_counters(target_pid, object)
   elseif yang   then dump_yang(target_pid)
   else               top(target_pid) end
   ordered_exit(0)
end

function select_snabb_instance (pid)
   local instances = shm.children("//")
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
   ordered_exit(1)
end

function ordered_exit (value)
   shm.unlink("//"..S.getpid()) -- Unlink own shm tree to avoid clutter
   os.exit(value)
end

function read_counter (name, path)
   if path then name = path.."/"..name end
   local value = counter.read(counter.open(name, 'readonly'))
   counter.delete(name)
   return value
end

function list_counters (pid, object)
   local path = "//"..pid.."/counters/"..object
   local cnames = shm.children(path)
   table.sort(cnames, function (a, b) return a < b end)
   for _, cname in ipairs(cnames) do
      print_row({30, 30}, {cname, lib.comma_value(read_counter(cname, path))})
   end
end

function dump_yang (instance_pid)
   local instance_tree = "//"..instance_pid
   local interface_state = {}
   local types = { [0x1000] = 'hardware',
                   [0x1001] = 'virtual',
                   [0x1002] = 'link' }

   for _, link in ipairs(shm.children(instance_tree.."/links")) do
      local counters = instance_tree.."/counters/"..link
      local statistics = {}
      statistics['discontinuity-time'] =
         totime(read_counter('discontinuity-time', counters))
      statistics['in-octets'] =
         tohex64(read_counter('rxbytes', counters))
      statistics['out-octets'] =
         tohex64(read_counter('txbytes', counters))
      statistics['out-discards'] =
         truncate32(tonumber(read_counter('txdrop', counters)))
      table.insert(interface_state, { name = link,
                                      type = types[0x1002],
                                      statistics = statistics })
   end

   for _, name in ipairs(shm.children(instance_tree.."/counters")) do
      local counters = instance_tree.."/counters/"..name
      local exists = {}
      for _, c in ipairs(shm.children(counters)) do exists[c] = true end
      local type = nil
      if exists['type'] then
         type = types[tonumber(read_counter('type', counters))]
      end
      if type then
         local statistics = {}
         statistics['discontinuity-time'] =
            totime(read_counter('discontinuity-time', counters))
         for _, c in ipairs({'in-octets', 'in-unicast',
                             'in-broadcast', 'in-multicast',
                             'out-octets', 'out-unicast',
                             'out-broadcast', 'out-multicast'}) do
            if exists[c] then
               statistics[c] = tohex64(read_counter(c, counters))
            end
         end
         for _, c in ipairs({'in-discards', 'out-discards'}) do
            if exists[c] then
               statistics[c] = truncate32(read_counter(c, counters))
            end
         end
         local interface = { name = name, type = type, statistics = statistics}
         if exists['phys-address'] then
            interface['phys-address'] =
               tomac(read_counter('phys-address', counters))
         end
         table.insert(interface_state, interface)
      end
   end

   print(json.encode({['interface-state'] = interface_state}))
end

function tomac (n)
   return tostring(macaddress:new(n))
end

function totime (n)
   return os.date("!%FT%TZ", tonumber(n))
end

function truncate32 (n)
   local box = ffi.new("union { uint64_t i64; uint32_t i32[2]; }")
   box.i64 = n
   if ffi.abi("le") then return tonumber(box.i32[0])
   elseif ffi.abi("be") then return tonumber(box.i32[1]) end
end

function tohex64 (n)
   local box = ffi.new("uint64_t[1]")
   box[0] = n
   local s = ffi.string(box, 8)
   if ffi.abi("le") then s = s:reverse() end
   return string.format("0x%02X%02X%02X%02X%02X%02X%02X%02X", s:byte(1, 8))
end


function top (instance_pid)
   local instance_tree = "//"..instance_pid
   local counters = open_counters(instance_tree)
   local configs = 0
   local last_stats = nil
   while (true) do
      if configs < counter.read(counters.configs) then
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
   for _, name in ipairs({"configs", "breaths", "frees", "freebytes"}) do
      counters[name] = counter.open(tree.."/engine/"..name, 'readonly')
   end
   local success, latency = pcall(histogram.open, tree..'/engine/latency')
   if success then counters.latency = latency end
   counters.links = {} -- These will be populated on demand.
   return counters
end

function open_link_counters (counters, tree)
   -- Unmap and clear existing link counters.
   for linkspec, _ in pairs(counters.links) do
      for _, name
      in ipairs({"rxpackets", "txpackets", "rxbytes", "txbytes", "txdrop"}) do
         counter.delete(tree.."/counters/"..linkspec.."/"..name)
      end
   end
   counters.links = {}
   -- Open current link counters.
   for _, linkspec in ipairs(shm.children(tree.."/links")) do
      counters.links[linkspec] = {}
      for _, name
      in ipairs({"rxpackets", "txpackets", "rxbytes", "txbytes", "txdrop"}) do
         counters.links[linkspec][name] =
            counter.open(tree.."/counters/"..linkspec.."/"..name, 'readonly')
      end
   end
end

function get_stats (counters)
   local new_stats = {}
   for _, name in ipairs({"configs", "breaths", "frees", "freebytes"}) do
      new_stats[name] = counter.read(counters[name])
   end
   if counters.latency then new_stats.latency = counters.latency:snapshot() end
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

function summarize_latency(histogram, prev)
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

module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local top = require("lib.ipc.shmem.top")
local fs = require("lib.ipc.fs")
local usage = require("program.top.README_inc")

function clearterm () io.write('\027[2J') end

function run (args)
   if #args > 1 then print(usage) main.exit(1) end
   local target_pid = args[1]

   local instance_fs = fs:new(select_snabb_instance(target_pid))
   local shmem_stats = top:attach(instance_fs:resource("core-stats"))

   local last_stats = nil
   while (true) do
      local new_stats = get_stats(shmem_stats)
      if last_stats then
         clearterm()
         print_global_metrics(new_stats, last_stats)
         io.write("\n")
         print_link_metrics(new_stats, last_stats)
         io.flush()
      end
      last_stats = new_stats
      C.sleep(1)
   end
end

function select_snabb_instance (pid)
   if pid then
      -- Try to use given pid
      if fs:exists(pid) then return pid
      else error("No such Snabb Switch instance: "..pid) end
   else
      -- Try to automatically select pid
      local instances = fs:instances()
      if #instances == 1 then return instances[1]
      elseif #instances == 0 then error("No Snabb Switch instance found.")
      else error("Multple Snabb Switch instances found. Select one.") end
   end
end

function get_stats (shmem_stats)
   local new_stats = {}
   new_stats.frees = shmem_stats:get("frees")
   new_stats.bytes = shmem_stats:get("bytes")
   new_stats.breaths = shmem_stats:get("breaths")
   new_stats.links = {}
   for i = 1, shmem_stats:n_links() do
      new_stats.links[i] = shmem_stats:get_link(i-1)
   end
   return new_stats
end

local global_metrics_row = {15, 15, 15}
function print_global_metrics (new_stats, last_stats)
   local frees = tonumber(new_stats.frees - last_stats.frees)
   local bytes = tonumber(new_stats.bytes - last_stats.bytes)
   local breaths = tonumber(new_stats.breaths - last_stats.breaths)
   print_row(global_metrics_row, {"Kfrees/s", "freeGbytes/s", "breaths/s"})
   print_row(global_metrics_row,
             {float_s(frees / 1000), float_s(bytes / (1000^3)), tostring(breaths)})
end

local link_metrics_row = {31, 7, 7, 7, 7, 7}
function print_link_metrics (new_stats, last_stats)
   print_row(link_metrics_row,
             {"Links (rx/tx/txdrop in Mpps)", "rx", "tx", "rxGb", "txGb", "txdrop"})
   for i = 1, #new_stats.links do
      if last_stats.links[i] and new_stats.links[i].name == last_stats.links[i].name then
         local name = new_stats.links[i].name
         local rx = tonumber(new_stats.links[i].rxpackets - last_stats.links[i].rxpackets)
         local tx = tonumber(new_stats.links[i].txpackets - last_stats.links[i].txpackets)
         local rxbytes = tonumber(new_stats.links[i].rxbytes - last_stats.links[i].rxbytes)
         local txbytes = tonumber(new_stats.links[i].txbytes - last_stats.links[i].txbytes)
         local drop = tonumber(new_stats.links[i].txdrop - last_stats.links[i].txdrop)
            print_row(link_metrics_row,
                      {name,
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

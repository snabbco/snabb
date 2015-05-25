module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local top = require("lib.ipc.shmem.top")
local usage = require("program.top.README_inc")

function clearterm () io.write('\027[2J') end

function run (args)
   if not #args == 0 then print(usage) main.exit(1) end

   local shmem_stats = shmem_connect()

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

function shmem_connect ()
   local connected, shmem_stats
   print("Connecting...")
   while not connected do
      connected, shmem_stats = pcall(top.attach, top)
      if not connected then C.sleep(1) end
   end
   return shmem_stats
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

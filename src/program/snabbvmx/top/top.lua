module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local shm = require("core.shm")
local syscall = require("syscall")
local counter = require("core.counter")
local S = require("syscall")
local usage = require("program.snabbvmx.top.README_inc")

local long_opts = {
   help = "h"
}

local ifInDiscards_start

function clearterm () io.write('\027[2J') end

function run (args)
   local opt = {}
   function opt.h (arg) print(usage) main.exit(1) end
   args = lib.dogetopt(args, opt, "h", long_opts)

   if #args > 1 then print(usage) main.exit(1) end
   local target_pid = args[1]

   -- Unlink stale snabb resources.
   for _, pid in ipairs(shm.children("//")) do
     if not syscall.kill(tonumber(pid), 0) then
       shm.unlink("//"..pid)
     end
   end
      
   local instance_tree = "//"..(select_snabb_instance(target_pid))
   local counters = open_counters(instance_tree)
   local configs = 0
   local last_stats = nil
   local last_time = nil
   while (true) do
      local new_stats = get_stats(counters)
      local time = tonumber(C.get_time_ns())
      if last_stats then
         clearterm()
         print_lwaftr_metrics(new_stats, last_stats, (time - last_time)/1000)
         io.flush()
      end
      last_stats = new_stats
      last_time = time
      C.sleep(1)
   end
end

function select_snabb_instance (pid)
   local instances = shm.children("//")
   if pid then
      -- Try to use given pid
      for _, instance in ipairs(instances) do
         if instance == pid then return pid end
      end
      print("No such Snabb Switch instance: "..pid)
   elseif #instances == 2 then
      -- Two means one is us, so we pick the other.
      local own_pid = tostring(S.getpid())
      if instances[1] == own_pid then return instances[2]
      else                            return instances[1] end
   elseif #instances == 1 then print("No Snabb Switch instance found.")
   else print("Multple Snabb Switch instances found. Select one.") end
   os.exit(1)
end

function open_counters (tree)
  local counters = {}
   counters.lwaftr = {}
   for _,lwaftrspec in pairs({"lwaftr_v6", "lwaftr_v4", "nic"}) do
      counters.lwaftr[lwaftrspec] = {}
      if lwaftrspec == "nic" then
        name = "ifInDiscards"
        counters.lwaftr[lwaftrspec][name] =
        counter.open(tree .. "/nic/ifInDiscards", 'readonly')
        ifInDiscards_start = counter.read(counters.lwaftr[lwaftrspec][name])
      else
        for _, name
          in ipairs({"rcvdPacket", "sentPacket", "rcvdByte", "sentByte", "droppedPacket",
          "reassemble_ok", "reassemble_invalid", "fragment_ok", "fragment_forbidden"}) do
          counters.lwaftr[lwaftrspec][name] =
          counter.open(tree .."/" .. lwaftrspec .. "/" .. name, 'readonly')
        end
      end
   end
   return counters
end

function get_stats (counters)
   local new_stats = {}
   new_stats.lwaftr = {}
   for lwaftrspec, lwaftr in pairs(counters.lwaftr) do
      new_stats.lwaftr[lwaftrspec] = {}
      if lwaftrspec == "nic" then
        name = "ifInDiscards"
        new_stats.lwaftr[lwaftrspec][name] = counter.read(lwaftr[name])
      else
        for _, name
          in ipairs({"rcvdPacket", "sentPacket", "rcvdByte", "sentByte", "droppedPacket",
          "reassemble_ok", "reassemble_invalid", "fragment_ok", "fragment_forbidden"}) do
          new_stats.lwaftr[lwaftrspec][name] = counter.read(lwaftr[name])
        end
      end
   end
   return new_stats
end

local lwaftr_metrics_row = {31, 7, 7, 7, 7, 11}
function print_lwaftr_metrics (new_stats, last_stats, time_delta)
   print_row(lwaftr_metrics_row,
             {"lwaftr (rx/tx/txdrop in Mpps)", "rx", "tx", "rxGb", "txGb", "txdrop"})
   for lwaftrspec, lwaftr in pairs(new_stats.lwaftr) do
     if lwaftrspec ~= "nic" then
      if last_stats.lwaftr[lwaftrspec] then
         local rx = tonumber(new_stats.lwaftr[lwaftrspec].rcvdPacket - last_stats.lwaftr[lwaftrspec].rcvdPacket)
         local tx = tonumber(new_stats.lwaftr[lwaftrspec].sentPacket - last_stats.lwaftr[lwaftrspec].sentPacket)
         local rxbytes = tonumber(new_stats.lwaftr[lwaftrspec].rcvdByte - last_stats.lwaftr[lwaftrspec].rcvdByte)
         local txbytes = tonumber(new_stats.lwaftr[lwaftrspec].sentByte - last_stats.lwaftr[lwaftrspec].sentByte)
         local drop = tonumber(new_stats.lwaftr[lwaftrspec].droppedPacket - last_stats.lwaftr[lwaftrspec].droppedPacket)
         print_row(lwaftr_metrics_row,
                   {lwaftrspec,
                    float_s(rx / time_delta), float_s(tx / time_delta),
                    float_s(rxbytes / time_delta / 1000 *8), float_s(txbytes / time_delta / 1000 *8),
                    float_l(drop / time_delta)})
      end
     end
   end

   local metrics_row = {30, 20, 20}
   for lwaftrspec, lwaftr in pairs(new_stats.lwaftr) do
     if last_stats.lwaftr[lwaftrspec] then
        io.write(("\n%30s  %20s %20s\n"):format("", "Total", "per second"))
        if lwaftrspec == "nic" then
          name = "ifInDiscards"
          local delta = tonumber(new_stats.lwaftr[lwaftrspec][name] - last_stats.lwaftr[lwaftrspec][name])
            print_row(metrics_row, {lwaftrspec .. " " .. name,
            int_s(new_stats.lwaftr[lwaftrspec][name] - ifInDiscards_start), int_s(delta)})
        else
          for _, name
            in ipairs({"rcvdPacket", "sentPacket", "rcvdByte", "sentByte", "droppedPacket",
            "reassemble_ok", "reassemble_invalid", "fragment_ok", "fragment_forbidden"}) do
            local delta = tonumber(new_stats.lwaftr[lwaftrspec][name] - last_stats.lwaftr[lwaftrspec][name])
            print_row(metrics_row, {lwaftrspec .. " " .. name,
            int_s(new_stats.lwaftr[lwaftrspec][name]), int_s(delta)})

          end
        end
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

function int_s (n)
   return ("%20d"):format(tonumber(n))
end

function float_s (n)
   return ("%.2f"):format(n)
end

function float_l (n)
   return ("%.6f"):format(n)
end

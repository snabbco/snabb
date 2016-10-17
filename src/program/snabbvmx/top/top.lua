module(..., package.seeall)

local counter = require("core.counter")
local ffi = require("ffi")
local lib = require("core.lib")
local lwcounter = require("apps.lwaftr.lwcounter")
local lwutil = require("apps.lwaftr.lwutil")
local lwtypes = require("apps.lwaftr.lwtypes")
local shm = require("core.shm")
local top = require("program.top.top")

local C = ffi.C
local fatal = lwutil.fatal

local long_opts = {
   help = "h"
}

local function clearterm () io.write('\027[2J') end

local function select_snabb_instance_by_id (target_id)
   local pids = shm.children("/")
   for _, pid in ipairs(pids) do
      local path = "/"..pid.."/nic/id"
      if shm.exists(path) then
         local lwaftr_id = shm.open(path, lwtypes.lwaftr_id_type)
         if ffi.string(lwaftr_id.value) == target_id then
            return pid
         end
      end
   end
   print(("Couldn't find instance with id '%s'"):format(target_id))
   main.exit(1)
end

local function select_snabb_instance (id)
   if not id or tonumber(id) then
      return top.select_snabb_instance(id)
   else
      return select_snabb_instance_by_id(id)
   end
end

local counter_names = (function ()
   local counters = {
      "in-%s-packets",                     -- rcvdPacket
      "in-%s-bytes",                       -- rcvdByte
      "out-%s-packets",                    -- sentPacket
      "out-%s-bytes",                      -- sentByte
      "drop-all-%s-iface-packets",         -- droppedPacket
      "in-%s-frag-reassembled",            -- reassemble_ok
      "drop-%s-frag-invalid-reassembly",   -- reassemble_invalid
      "out-%s-frag",                       -- fragment_ok
      "out-%s-frag-not",                   -- fragment_forbidden
   }
   local ipv4_counters = {}
   for i, name in ipairs(counters) do
      ipv4_counters[i] = name:format("ipv4")
   end
   local ipv6_counters = {}
   for i, name in ipairs(counters) do
      ipv6_counters[i] = name:format("ipv6")
   end
   return function (key)
      assert(key == "lwaftr_v4" or key == "lwaftr_v6", "Invalid key: "..key)
      return key == "lwaftr_v4" and ipv4_counters or ipv6_counters
   end
end)()

local function has_lwaftr_app (tree)
   return shm.exists(tree.."/"..lwcounter.counters_dir)
end

local function open_counters (tree)
   local function open_counter (name)
      return counter.open(tree.."/"..lwcounter.counters_dir..name..".counter", 'readonly')
   end
   local function open_counter_list (t)
      local ret = {}
      for _, name in ipairs(t) do
         ret[name] = open_counter(name)
      end
      return ret
   end
   local counters = {}
   counters.lwaftr = {}
   counters.lwaftr["lwaftr_v4"] = open_counter_list(counter_names("lwaftr_v4"))
   counters.lwaftr["lwaftr_v6"] = open_counter_list(counter_names("lwaftr_v6"))
   counters.lwaftr["nic"] = { ifInDiscards = open_counter("ingress-packet-drops") }
   return counters
end

local function get_stats (counters)
   local function read_counters (t)
      local ret = {}
      for k, v in pairs(t) do
         ret[k] = counter.read(v)
      end
      return ret
   end
   local stats = {}
   stats.lwaftr = {}
   for k, v in pairs(counters.lwaftr) do
      stats.lwaftr[k] = read_counters(v)
   end
   return stats
end

local function pad_str (s, n)
   local padding = math.max(n - s:len(), 0)
   return ("%s%s"):format(s:sub(1, n), (" "):rep(padding))
end

local function print_row (spec, args)
   for i, s in ipairs(args) do
      io.write((" %s"):format(pad_str(s, spec[i])))
   end
   io.write("\n")
end

local function int_s (n)
   local val = lib.comma_value(n)
   return (" "):rep(20 - #val)..val
end

local function float_s (n)
   return ("%.2f"):format(n)
end

local function float_l (n)
   return ("%.6f"):format(n)
end

local lwaftr_metrics_row = {51, 7, 7, 7, 7, 11}
local function print_lwaftr_metrics (new_stats, last_stats, time_delta)
   local function delta(t, s, name)
      assert(t[name] and s[name])
      return tonumber(t[name] - s[name])
   end
   local function delta_v6 (t, s)
      local rx = delta(t, s, "in-ipv6-packets")
      local tx = delta(t, s, "out-ipv6-packets")
      local rxbytes = delta(t, s, "in-ipv6-bytes")
      local txbytes = delta(t, s, "out-ipv6-bytes")
      local drop = delta(t, s, "drop-all-ipv6-iface-packets")
      return rx, tx, rxbytes, txbytes, drop
   end
   local function delta_v4 (t, s)
      local rx = delta(t, s, "in-ipv4-packets")
      local tx = delta(t, s, "out-ipv4-packets")
      local rxbytes = delta(t, s, "in-ipv4-bytes")
      local txbytes = delta(t, s, "out-ipv4-bytes")
      local drop = delta(t, s, "drop-all-ipv4-iface-packets")
      return rx, tx, rxbytes, txbytes, drop
   end
   print_row(lwaftr_metrics_row, {
      "lwaftr (rx/tx/txdrop in Mpps)", "rx", "tx", "rxGb", "txGb", "txdrop"
   })
   for lwaftrspec, _ in pairs(new_stats.lwaftr) do
      if lwaftrspec == "nic" then goto continue end
      if last_stats.lwaftr[lwaftrspec] then
         local t = new_stats.lwaftr[lwaftrspec]
         local s = last_stats.lwaftr[lwaftrspec]
         local rx, tx, rxbytes, txbytes, drop
         if lwaftrspec == "lwaftr_v6" then
            rx, tx, rxbytes, txbytes, drop = delta_v6(t, s)
         else
            rx, tx, rxbytes, txbytes, drop = delta_v4(t, s)
         end
         print_row(lwaftr_metrics_row, { lwaftrspec,
            float_s(rx / time_delta),
            float_s(tx / time_delta),
            float_s(rxbytes / time_delta / 1000 *8),
            float_s(txbytes / time_delta / 1000 *8),
            float_l(drop / time_delta)
         })
      end
      ::continue::
   end

   local metrics_row = {50, 20, 20}
   for lwaftrspec, _ in pairs(new_stats.lwaftr) do
      if last_stats.lwaftr[lwaftrspec] then
         io.write(("\n%50s  %20s %20s\n"):format("", "Total", "per second"))
         local t = new_stats.lwaftr[lwaftrspec]
         local s = last_stats.lwaftr[lwaftrspec]
         if lwaftrspec == "nic" then
            local name = "ifInDiscards"
            local diff = delta(t, s, name)
            print_row(metrics_row, { lwaftrspec .. " " .. name,
               int_s(t[name]), int_s(diff)})
         else
            for _, name in ipairs(counter_names(lwaftrspec)) do
               local diff = delta(t, s, name)
               print_row(metrics_row, { lwaftrspec .. " " .. name,
                  int_s(t[name]), int_s(diff)})
            end
         end
      end
   end
end

local function show_usage (code)
   print(require("program.snabbvmx.top.README_inc"))
   main.exit(code)
end

local function parse_args (args)
   local handlers = {}
   function handlers.h ()
      show_usage(0)
   end
   args = lib.dogetopt(args, handlers, "h", long_opts)
   if #args > 1 then show_usage(1) end
   return args[1]
end

function run (args)
   local target_pid = parse_args(args)
   local instance_tree = "/"..select_snabb_instance(target_pid)
   if not has_lwaftr_app(instance_tree) then
      fatal("Selected instance doesn't include lwaftr app")
   end
   local counters = open_counters(instance_tree)
   local last_stats = nil
   local last_time = nil
   while true do
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

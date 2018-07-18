-- This module implements the `snabb flow_export` command

module(..., package.seeall)

local lib    = require("core.lib")
local worker = require("core.worker")
local probe  = require("program.ipfix.lib")
local S      = require("syscall")

local long_opts = {
   help = "h",
   jit = "j",
   duration = "D",
   port = "p",
   transport = 1,
   ["host-ip"] = "a",
   ["input-type"] = "i",
   ["output-type"] = "o",
   ["mtu"] = 1,
   ["rss-queues"] = 1,
   ["netflow-v9"] = 0,
   ["ipfix"] = 0,
   ["active-timeout"] = 1,
   ["idle-timeout"] = 1,
   ["observation-domain"] = 1,
   ["template-refresh"] = 1,
   ["flush-timeout"] = 1,
   ["cache-size"] = 1,
   ["scan-time"] = 1,
   ["pfx-to-as"] = 1,
   ["maps-log"] = 1,
   ["vlan-to-ifindex"] = 1,
   ["mac-to-as"] = 1,
   ["cpu"] = 1,
   ["busy-wait"] = "b"
}

function run (args)
   local duration
   local busywait = false
   local jit = { opts = {} }

   local input_type, output_type = "pci", "pci"

   local host_mac
   local host_ip = '10.0.0.1' -- Just to have a default.
   local collector_ip = '10.0.0.2' -- Likewise.
   local port = 4739
   local mtu = 1514
   local nqueues = 1

   local active_timeout, idle_timeout, flush_timeout, scan_time
   local observation_domain, template_refresh_interval
   local cache_size
   local ipfix_version = 10
   local templates = {}
   local maps = {}
   local maps_logfile

   local pfx_to_as, vlan_to_ifindex, mac_to_as

   local cpu

   -- TODO: better input validation
   local opt = {
      h = function (arg)
         print(require("program.ipfix.probe.README_inc"))
         main.exit(0)
      end,
      D = function (arg)
         duration = assert(tonumber(arg), "expected number for duration")
      end,
      i = function (arg)
         input_type = arg
      end,
      o = function (arg)
         output_type = arg
      end,
      p = function (arg)
         port = assert(tonumber(arg), "expected number for port")
      end,
      m = function (arg)
         host_mac = arg
      end,
      a = function (arg)
         host_ip = arg
      end,
      c = function (arg)
         collector_ip = arg
      end,
      b = function (arg)
         busywait = true
      end,
      ["active-timeout"] = function (arg)
         active_timeout =
            assert(tonumber(arg), "expected number for active timeout")
      end,
      ["idle-timeout"] = function (arg)
         idle_timeout =
            assert(tonumber(arg), "expected number for idle timeout")
      end,
      ["flush-timeout"] = function (arg)
         flush_timeout =
            assert(tonumber(arg), "expected number for flush timeout")
      end,
      ["scan-time"] = function (arg)
         scan_time =
            assert(tonumber(arg), "expected number for scan time")
      end,
      ["observation-domain"] = function (arg)
         observation_domain =
            assert(tonumber(arg), "expected number for observation domain")
      end,
      ["template-refresh"] = function (arg)
         template_refresh_interval =
            assert(tonumber(arg), "expected number for template refresh interval")
      end,
      ["cache-size"] = function (arg)
         cache_size =
            assert(tonumber(arg), "expected number for cache size")
      end,
      ["pfx-to-as"] = function (arg)
         if arg then
            maps.pfx_to_as = arg
         end
      end,
      ["vlan-to-ifindex"] = function (arg)
         if arg then
            maps.vlan_to_ifindex = arg
         end
      end,
      ["mac-to-as"] = function (arg)
         if arg then
            maps.mac_to_as = arg
         end
      end,
      ["maps-log"] = function (arg)
         if arg ~= "" then
            maps_logfile = arg
         end
      end,
      ipfix = function (arg)
         ipfix_version = 10
      end,
      ["netflow-v9"] = function (arg)
         ipfix_version = 9
      end,
      ["mtu"] = function (arg)
         mtu = tonumber(arg)
      end,
      ["rss-queues"] = function (arg)
         nqueues = tonumber(arg)
      end,
      -- TODO: not implemented
      ["transport"] = function (arg) end,
      ["cpu"] = function (arg)
         cpu = tonumber(arg)
      end,
      j = require("program.ipfix.lib").parse_jit_option_fn(jit)
   }

   args = lib.dogetopt(args, opt, "hD:i:o:p:m:a:c:j:b", long_opts)
   if #args < 2 then
      print(require("program.ipfix.probe.README_inc"))
      main.exit(1)
   elseif #args == 2 then
      table.insert(args, 'v4')
      table.insert(args, 'v6')
   end

   local input, output = args[1], args[2]

   for i = 3, #args do
      table.insert(templates, args[i])
   end

   local probe_config = {
      active_timeout = active_timeout,
      idle_timeout = idle_timeout,
      flush_timeout = flush_timeout,
      cache_size = cache_size,
      scan_time = scan_time,
      observation_domain = observation_domain,
      template_refresh_interval = template_refresh_interval,
      ipfix_version = ipfix_version,
      exporter_ip = host_ip,
      exporter_mac = host_mac,
      collector_ip = collector_ip,
      collector_port = port,
      mtu = mtu,
      templates = templates,
      maps = maps,
      maps_logfile = maps_logfile,
      output_type = output_type,
      output = output,
      input_type = input_type,
      input = input
   }

   if input_type == "pci" and nqueues > 1 then
      for rssq = 0, nqueues - 1 do

         -- Create unique identifiers for config options that need to
         -- be unique per instance
         probe_config.input = input.."/"..rssq
         probe_config.observation_domain = observation_domain + rssq
         if output_type == "tap_routed" then
            probe_config.output = output..probe_config.observation_domain
         end
         local jit_c = lib.deepcopy(jit)
         if jit_c.dump and #jit_c.dump == 2 then
            jit_c.dump[2] = jit_c.dump[2]..rssq
         end

         local worker_expr = string.format(
            'require("program.ipfix.lib").run(%s, %s, %s, nil, %s)',
            probe.value_to_string(probe_config), tostring(duration),
            tostring(busywait), probe.value_to_string(jit_c)
         )
         local child_pid = worker.start("ipfix"..rssq, worker_expr)
         print("Launched IPFIX worker process #"..child_pid)
      end

      if duration then
         S.sleep(duration)
         print("Waiting for workers to finish")
         local alive
         repeat
            alive = false
            for _, s in pairs(worker.status()) do
               if s.alive then alive = true end
            end
         until not alive
         print("Done")
      else
         S.pause()
      end
   else
      require("program.ipfix.lib").run(probe_config, duration, busywait, cpu, jit)
   end
end

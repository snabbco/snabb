module(...,package.seeall)

local S           = require("syscall")
local lib         = require("core.lib")
local app_graph   = require("core.config")
local worker      = require("core.worker")
local shm         = require("core.shm")
local timer       = require("core.timer")
local pci         = require("lib.hardware.pci")
local logger      = require("lib.logger")
local numa        = require("lib.numa")
local probe       = require("program.ipfix.lib")

local main_config = {
   interfaces = { required = true },
   hw_rss_scaling = { default = 1 },
   rss = { required = true },
   cpu_pool = { default = {} },
   rss_pin_cpu = { default = false },
   rss_jit = { default = nil },
   ipfix = { required = true }
}
local interface_config = {
   device = { required = true },
   name = { default = nil},
   description = { default = nil },
   tag = { default = nil },
   config = { default = {} }
}
local ipfix_config = {
   default = { default = {} },
   collector_pools = { default = {} },
   maps = { default = {} },
   observation_domain_base = { default = 256 },
   exporters = { required = true }
}
local collector_pool_config = {
   ip = { required = true },
   port = { required = true }
}
local maps_config = {
   pfx_to_as = { default = nil },
   vlan_to_ifindex = { default = nil },
   mac_to_as = { default = nil }
}
local exporter_config = {
   templates = { required = true },
   rss_class = { default = "default" },
   collector_pool = { default = nil },
   use_maps = { default = false },
   maps_log_dir = { default = nil },
   instances = { default = {} }
}
local instance_config = {
   embed = { default = true },
   weight = { default = 1 },
   jit = { default = nil },
   busywait = { default = nil },
   pin_cpu = { default = false },
}
local jit_config = {
   v = { default = nil },
   p = { default = {} },
   dump = { default = {} },
   opts = { default = {} },
   traceprof = { default = false }
}
local ipfix_default_config = lib.deepcopy(probe.probe_config)
for _, key in ipairs({
      "collector_ip",
      "collector_port",
      "observation_domain",
      "exporter_mac",
      "templates",
      "output_type",
      "output",
      "input_type",
      "input",
      "instance"
}) do
   ipfix_default_config[key] = nil
end

local function override_jit(default, config_in, dump_suffix)
   local jit = lib.deepcopy(default)
   if config_in then
      local config = lib.parse(config_in, jit_config)
      if config.opts then
         jit.opts = config.opts
      end
      if config.dump then
         local dump = lib.deepcopy(config.dump)
         local file = dump[2]
         if file then
            file = file.."_"..dump_suffix
            dump[2] = file
         end
         jit.dump = dump
      end
   end
   return jit
end

local function create_workers (probe_config, duration, busywait, jit, logger, log_date)
   local main = lib.parse(probe_config, main_config)
   local maps = lib.parse(main.ipfix.maps, maps_config)
   local ipfix = lib.parse(main.ipfix, ipfix_config)
   local ipfix_default = lib.parse(ipfix.default, ipfix_default_config)
   local collector_pools = {}
   for name, list in pairs(ipfix.collector_pools) do
      pool = {}
      for _, member in ipairs(list) do
         table.insert(pool, lib.parse(member, collector_pool_config))
      end
      collector_pools[name] = pool
   end

   local function merge_with_default (config)
      local merged = lib.deepcopy(ipfix_default)
      for _, key in ipairs({ "collector_pool", "templates" }) do
         if config[key] then
            merged[key] = config[key]
         end
      end
      return merged
   end

   local classes = {}
   local function rss_link_name (class, weight)
      if not classes[class] then
         classes[class] = 0
      end
      local instance = classes[class] + 1
      classes[class] = instance
      return class.."_"..instance..(weight > 1 and "_"..weight or '')
   end

   local workers = {}
   local function add_worker (name, expr, create_fn, remove_fn)
      table.insert(workers,
                   {
                      name = name,
                      expr = expr,
                      create_fn = create_fn,
                      remove_fn = remove_fn,
                      restarts = 0
                   }
      )
   end

   assert(type(main.interfaces) == "table")

   local mellanox = {}
   local observation_domain = ipfix.observation_domain_base

   -- Determine NUMA affinity for the input interfaces
   local pci_addrs = {}
   for _, interface in ipairs(main.interfaces) do
      local input = lib.parse(interface, interface_config)
      table.insert(pci_addrs, input.device)
   end
   local node = numa.choose_numa_node_for_pci_addresses(pci_addrs)
   local cpu_pool_size = #main.cpu_pool
   local function cpu_for_node (activate)
      if not activate then return nil end
      for n, cpu in ipairs(main.cpu_pool) do
         local cpu_node =  numa.cpu_get_numa_node(cpu)
         if cpu_node == node then
            return table.remove(main.cpu_pool, n)
         end
      end
      return nil
   end
   local function log_cpu_choice (pid, cpu, activate)
      if cpu_pool_size == 0 or not activate then return end
      if cpu then
         logger:log(string.format("Binding #%d to CPU %d, "
                                     .."NUMA node %d",
                                  pid, cpu, node))
      else
         logger:log(string.format("Not binding #%d to any CPU "
                                  .."(no match found in pool for "
                                     .."NUMA node %d)", pid, node))
      end
   end

   for rssq = 0, main.hw_rss_scaling - 1 do
      local inputs, outputs = {}, {}
      for i, interface in ipairs(main.interfaces) do
         local input = lib.parse(interface, interface_config)
         input.rxq = rssq
         table.insert(inputs, input)

         -- The mellanox driver requires a master process that sets up
         -- all queues for the interface. We collect all queues per
         -- device of this type here.
         local device_info = pci.device_info(input.device)
         if device_info.driver == 'apps.mellanox.connectx4' then
            local spec = mellanox[input.device]
            if not spec then
               spec = { ifName = input.name,
                        ifAlias = input.description,
                        queues = {},
                        recvq_size = input.config.recvq_size or 8192 }
               mellanox[input.device] = spec
            end
            table.insert(spec.queues, { id = rssq })
         end
      end

      local embedded_instance = 1
      for _, exporter in ipairs(main.ipfix.exporters) do
         local exporter = lib.parse(exporter, exporter_config)
         local config = merge_with_default(exporter)

         config.output_type = "tap_routed"
         config.instance = nil
         config.add_packet_metadata = false
         if exporter.use_maps then
            config.maps = maps
         end

         for i, instance in ipairs(exporter.instances) do
            -- Create a clone of the configuration for parameters
            -- specific to the instance
            local iconfig = lib.deepcopy(config)
            local instance = lib.parse(instance, instance_config)
            local rss_link = rss_link_name(exporter.rss_class, instance.weight)
            local od = observation_domain

            -- Select the collector ip and port from the front of the
            -- pool and rotate the pool's elements by one
            local pool = config.collector_pool
            assert(collector_pools[pool] and #collector_pools[pool] > 0,
                   "Undefined or empty collector pool: "..pool)
            collector = table.remove(collector_pools[pool], 1)
            table.insert(collector_pools[pool], collector)
            iconfig.collector_ip = collector.ip
            iconfig.collector_port = collector.port
            iconfig.collector_pool = nil

            iconfig.log_date = log_date
            observation_domain = observation_domain + 1
            iconfig.observation_domain = od
            iconfig.output = "ipfixexport"..od
            if exporter.maps_log_dir then
               iconfig.maps_logfile =
                  exporter.maps_log_dir.."/"..od..".log"
            end

            -- Scale the scan protection parameters by the number of
            -- ipfix instances in this RSS class
            iconfig.scan_protection = lib.deepcopy(config.scan_protection)
            local scale_factor = main.hw_rss_scaling * #exporter.instances
            for _, field in ipairs({ "threshold_rate", "export_rate" }) do
               iconfig.scan_protection[field] =
                  iconfig.scan_protection[field]/scale_factor
            end

            local output
            if instance.embed then
               output = {
                  link_name = rss_link,
                  args = iconfig,
                  instance = embedded_instance
               }
               embedded_instance = embedded_instance + 1
            else
               output = { type = "interlink", link_name = rss_link }
               iconfig.input_type = "interlink"
               iconfig.input = rss_link

               local jit =  override_jit(jit, instance.jit, od)

               local cpu = cpu_for_node(instance.pin_cpu)
               local worker_expr = string.format(
                  'require("program.ipfix.lib").run(%s, %s, %s, %s, %s)',
                  probe.value_to_string(iconfig), tostring(duration),
                  tostring(instance.busywait), tostring(cpu),
                  probe.value_to_string(jit)
               )
               add_worker(rss_link, worker_expr,
                          function(pid)
                             logger:log(string.format("Launched IPFIX worker process #%d, "..
                                                         "observation domain %d",
                                                      pid, od))
                             logger:log(string.format("Selected collector %s:%d from pool %s "
                                                      .."for process #%d ",
                                                      collector.ip, collector.port, pool,
                                                      pid))
                             log_cpu_choice(pid, cpu, instance.pin_cpu)
                             shm.create("ipfix_workers/"..pid, "uint64_t")
                          end,
                          function(pid)
                             shm.unlink("ipfix_workers/"..pid)
                          end
               )
            end
            table.insert(outputs, output)
         end
      end

      local cpu = cpu_for_node(main.rss_pin_cpu)
      local worker_expr = string.format(
         'require("program.ipfix.lib").run_rss(%s, %s, %s, %s, %s, %s, %s)',
         probe.value_to_string(main.rss), probe.value_to_string(inputs),
         probe.value_to_string(outputs), tostring(duration),
         tostring(busywait), tostring(cpu),
         probe.value_to_string(override_jit(jit, main.rss_jit, rssq)),
         log_date
      )
      add_worker("rss"..rssq, worker_expr,
                 function(pid)
                    logger:log(string.format("Launched RSS worker process #%d",
                                             pid))
                    log_cpu_choice(pid, cpu, main.rss_pin_cpu)
                    shm.create("rss_workers/"..pid, "uint64_t")
                 end,
                 function(pid)
                    shm.unlink("rss_workers/"..pid)
                 end
      )

   end

   -- Create a trivial app graph that only contains the control apps
   -- for the Mellanox driver, which sets up the queues and
   -- maintains interface counters.
   local ctrl_graph = app_graph.new()
   for device, spec in pairs(mellanox) do
      local conf = {
         pciaddress = device,
         queues = spec.queues,
         recvq_size = spec.recvq_size
      }
      local driver = pci.device_info(device).driver
      app_graph.app(ctrl_graph, "ctrl_"..device,
                    require(driver).ConnectX4, conf)
   end

   for _, spec in ipairs(workers) do
      local child_pid = worker.start(spec.name, spec.expr)
      spec.create_fn(child_pid)
   end

   return workers, ctrl_graph, mellanox
end

local long_opts = {
   duration = "D",
   debug = "d",
   jit = "j",
   help = "h",
   ["busy-wait"] = "b",
   ["log-date"] = 'L',
   ["worker-check-interval"] = 'c'
}

local function usage(exit_code)
   print(require("program.ipfix.probe_rss.README_inc"))
   main.exit(exit_code)
end

function run (parameters)
   -- Limit for the number of restarts of a worker.  If exceeded, the
   -- entire probe is terminated.  Currently not configurable.
   local restart_limit = 5

   local duration
   local busywait = false
   local log_date = false
   local worker_check_interval = 5
   local profiling, traceprofiling
   local jit = { opts = {} }
   local log_pid = string.format("[%5d]", S.getpid())
   local opt = {
      D = function (arg)
         if arg:match("^[0-9]+$") then
            duration = tonumber(arg)
         else
            usage(1)
         end
      end,
      h = function (arg) usage(0) end,
      d = function (arg) _G.developer_debug = true end,
      b = function (arg)
         busywait = true
      end,
      j = probe.parse_jit_option_fn(jit),
      L = function(arg)
         log_date = true
      end,
      c = function(arg)
         if arg:match("^[0-9]+$") then
            worker_check_interval = tonumber(arg)
         end
      end
   }

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hdj:D:l:bLc:", long_opts)
   if #parameters ~= 1 then usage (1) end

   local logger = logger.new({ rate = 30, date = log_date,
                               module = log_pid.." RSS master" })
   local file = table.remove(parameters, 1)
   local probe_config = assert(loadfile(file))()
   local workers, ctrl_graph, mellanox =
      create_workers(probe_config, duration, busywait, jit, logger, log_date)

   if worker_check_interval > 0 then
      local workers_by_name = {}
      for _, spec in ipairs(workers) do
         workers_by_name[spec.name] = spec
      end

      local worker_check = function()
         for n, s in pairs(worker.status()) do
            if not s.alive then
               logger:log(string.format("Worker process %d died (status %d)",
                                        s.pid, s.status))
               local spec = workers_by_name[n]
               spec.restarts = spec.restarts + 1
               if spec.restarts > restart_limit then
                  logger:log(string.format("Too many restarts (>%d), "
                                              .."terminating", restart_limit))
                  S.exit(1)
               end
               logger:log(string.format("Restarting process (attempt #%d)",
                                        spec.restarts))
               spec.remove_fn(s.pid)
               local new_pid = worker.start(n, spec.expr)
               spec.create_fn(new_pid)
            else
               workers_by_name[n].restarts = 0
            end
         end
      end
      timer.activate(timer.new("workermon", worker_check,
                               worker_check_interval * 10e8, "repeating"))
   end

   engine.busywait = false
   engine.Hz = 10
   engine.configure(ctrl_graph)

   for device, spec in pairs(mellanox) do
      probe.create_ifmib(engine.app_table["ctrl_"..device].stats,
                         spec.ifName, spec.ifAlias, log_date)
   end

   engine.main({ duration = duration })

   logger:log("waiting for workers to finish")
   local alive
   repeat
      alive = false
      for _, s in pairs(worker.status()) do
         if s.alive then alive = true end
      end
   until not alive
   logger:log("done")
end

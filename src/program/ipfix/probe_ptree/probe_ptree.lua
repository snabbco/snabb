module(..., package.seeall)

local yang = require("lib.yang.yang")
local yang_util = require("lib.yang.util")
local ptree = require("lib.ptree.ptree")
local cpuset = require("lib.cpuset")
local pci = require("lib.hardware.pci")
local lib = require("core.lib")
local app_graph = require("core.config")

local probe = require("program.ipfix.lib")

local probe_schema = 'snabb-snabbflow-v1'

local probe_cpuset = cpuset.new()

function setup_ipfix (conf)
   -- yang.print_config_for_schema_by_name(probe_schema, conf, io.stdout)
   return setup_workers(conf)
end

function start (name, confpath)
   local conf = yang.load_configuration(confpath, {schema_name=probe_schema})
   update_cpuset(conf.snabbflow_config.rss.cpu_pool)
   return ptree.new_manager{
      log_level = 'INFO',
      setup_fn = setup_ipfix,
      initial_configuration = conf,
      schema_name = probe_schema,
      cpuset = probe_cpuset,
      name = name
   }
end

function run (args)
   local name = assert(args[1])
   local confpath = assert(args[2])
   -- print("Confpath is:", confpath)
   local manager = start(name, confpath)
   manager:main()
end

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

function update_cpuset (cpu_pool)
   local cpu_set = {}
   if cpu_pool then
      for _, cpu in ipairs(cpu_pool.cpu) do
         if not probe_cpuset:contains(cpu) then
            probe_cpuset:add(cpu)
         end
         cpu_set[cpu] = true
      end
      for _, cpu in ipairs(probe_cpuset:list()) do
         if not cpu_set[cpu] then
            probe_cpuset:remove(cpu)
         end
      end
   end
end

function setup_workers (config)
   local main = config.snabbflow_config
   local interfaces = main.interface
   local ipfix = main.ipfix
   local rss = main.rss

   local collector_pools = {}
   for name, p in pairs(ipfix.collector_pool) do
      local collectors = {}
      for entry in p.collector:iterate() do
         table.insert(collectors, {
            ip = yang_util.ipv4_ntop(entry.key.ip),
            port = entry.key.port
         })
      end
      collector_pools[name] = collectors
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
   local worker_opts = {}

   local mellanox = {}
   local observation_domain = ipfix.observation_domain_base

   update_cpuset(rss.cpu_pool)

   for rssq = 0, rss.hardware_scaling-1 do
      local inputs, outputs = {}, {}
      for device, opt in pairs(interfaces) do
         local input = lib.deepcopy(opt)
         input.device = device
         input.rxq = rssq
         table.insert(inputs, input)

         -- The mellanox driver requires a master process that sets up
         -- all queues for the interface. We collect all queues per
         -- device of this type here.
         local device_info = pci.device_info(device)
         if device_info.driver == 'apps.mellanox.connectx' then
            local spec = mellanox[device]
            if not spec then
               spec = { ifName = input.name,
                        ifAlias = input.description,
                        queues = {},
                        recvq_size = input.receive_queue_size }
               mellanox[device] = spec
            end
            table.insert(spec.queues, { id = rssq })
         else
            -- Silently truncate receive-queue-size for other drivers.
            -- (We are not sure what they can handle.)
            input.receive_queue_size = math.min(input.receive_queue_size, 8192)
         end
      end

      local embedded_instance = 1
      for name, exporter in pairs(ipfix.exporter) do
         local config = {}
         for key in pairs(ipfix_default_config) do
            config[key] = ipfix[key]
         end
         config.exporter_ip = yang_util.ipv4_ntop(ipfix.exporter_ip)

         config.collector_pool = exporter.collector_pool
         config.templates = exporter.template

         config.output_type = "tap_routed"
         config.instance = nil
         config.add_packet_metadata = false

         if true then -- use_maps=true
            local maps = {}
            for name, map in pairs(ipfix.maps) do
               maps[name] = map.file
            end
            config.maps = maps
         end

         local num_instances = 0
         for _ in pairs(exporter.instance) do
            num_instances = num_instances + 1
         end
         for id, instance in pairs(exporter.instance) do
            -- Create a clone of the configuration for parameters
            -- specific to the instance
            local iconfig = lib.deepcopy(config)
            local rss_link = rss_link_name(exporter.rss_class, 1)
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

            iconfig.log_date = ipfix.log_date
            observation_domain = observation_domain + 1
            iconfig.observation_domain = od
            iconfig.output = "ipfixexport"..od
            if ipfix.maps.log_directory then
               iconfig.maps_logfile =
                  ipfix.maps.log_directory.."/"..od..".log"
            end

            -- Scale the scan protection parameters by the number of
            -- ipfix instances in this RSS class
            local scale_factor = rss.hardware_scaling * num_instances
            iconfig.scan_protection = {
               enable = ipfix.scan_protection.enable,
               threshold_rate = ipfix.scan_protection.threshold_rate / scale_factor,
               export_rate = ipfix.scan_protection.export_rate / scale_factor,
            }

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

               workers[rss_link] = probe.configure_graph(iconfig)
               -- Dedicated exporter processes are restartable
               worker_opts[rss_link] = {
                  restart_intensity = exporter.restart.intensity,
                  restart_period = exporter.restart.period
               }
            end
            table.insert(outputs, output)
         end
      end

      -- local cpu = cpu_for_node(rss.pin_cpu) -- XXX not honored
      local rss_config = {
         default_class = rss.software_scaling.default_class,
         classes = {},
         remove_extension_headers = rss.software_scaling.remove_extension_headers
      }
      for key, class in pairs(rss.software_scaling.class or {}) do
         table.insert(rss_config.classes, {
            name = key.name,
            order = key.order,
            filter = class.filter,
            continue = class.continue
         })
      end
      table.sort(rss_config.classes, function (a,b) return a.order < b.order end)
      for _, class in ipairs(rss_config.classes) do
         class.order = nil
         --print(class.name, class.filter, "continue="..tostring(class.continue))
      end
      workers["rss"..rssq] = probe.configure_rss_graph(rss_config, inputs, outputs, ipfix.log_date)
   end

   -- for k,v in pairs(mellanox) do
   --    print(k)
   --    for _, q in ipairs(v.queues) do
   --       print("", q.id)
   --    end
   -- end

   -- Create a trivial app graph that only contains the control apps
   -- for the Mellanox driver, which sets up the queues and
   -- maintains interface counters.
   local ctrl_graph, need_ctrl = probe.configure_mlx_ctrl_graph(mellanox, ipfix.log_date)

   if need_ctrl then
      workers["mlx_ctrl"] = ctrl_graph
   end

   for name, graph in pairs(workers) do
      print("worker", name)
      print("", "apps:")
      for name, _ in pairs(graph.apps) do
         print("", "", name)
      end
      print("", "links:")
      for spec in pairs(graph.links) do
         print("", "", spec)
      end
   end

   return workers, worker_opts
end
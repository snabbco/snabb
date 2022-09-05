module(..., package.seeall)

local yang = require("lib.yang.yang")
local yang_util = require("lib.yang.util")
local path_data = require("lib.yang.path_data")
local mem = require("lib.stream.mem")
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
      name = name,
      worker_default_scheduling = {
         busywait = false,
         jit_opt = {
            sizemcode=256,
            maxmcode=8192,
            maxtrace=8000,
            maxrecord=50000,
            maxsnap=20000,
            maxside=10000
         }
      },
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

local software_scaling_parser = path_data.parser_for_schema_by_name(
   probe_schema, '/snabbflow-config/rss/software-scaling/exporter[name=""]'
)
local default_software_scaling =
   software_scaling_parser(mem.open_input_string(''))

function setup_workers (config)
   local interfaces = config.snabbflow_config.interface
   local rss = config.snabbflow_config.rss
   local flow_director = config.snabbflow_config.flow_director
   local ipfix = config.snabbflow_config.ipfix

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

   local function select_collector (pool)
      -- Select the collector ip and port from the front of the
      -- pool and rotate the pool's elements by one
      assert(collector_pools[pool] and #collector_pools[pool] > 0,
               "Undefined or empty collector pool: "..pool)
      local collector = table.remove(collector_pools[pool], 1)
      table.insert(collector_pools[pool], collector)
      return collector
   end

   if flow_director.default_class.exporter then
      assert(not flow_director.class[flow_director.default_class.exporter],
         "Exporter for the default traffic class can not be the exporter for a defined class.")
   end

   local class_order = {}
   for exporter in pairs(flow_director.class) do
      table.insert(class_order, exporter)
   end
   table.sort(class_order, function (x, y)
      return flow_director.class[x].order < flow_director.class[y].order
   end)

   local function class_name (exporter, class)
      -- Including order in name to avoid name collision with 'default' class
      return ("%s_%d"):format(exporter, class.order)
   end

   local rss_links = {}
   local function rss_link_name (class)
      if not rss_links[class] then
         rss_links[class] = 0
      end
      local qno = rss_links[class] + 1
      rss_links[class] = qno
      return class.."_"..qno
   end

   local observation_domain = ipfix.observation_domain_base
   local function next_observation_domain ()
      local ret = observation_domain
      observation_domain = observation_domain + 1
      return ret
   end
   
   local workers = {}
   local worker_opts = {}

   local mellanox = {}

   update_cpuset(rss.cpu_pool)

   for rss_group = 1, rss.hardware_scaling.rss_groups do
      local inputs, outputs = {}, {}
      for device, opt in pairs(interfaces) do
         local input = lib.deepcopy(opt)
         input.device = device
         input.rxq = rss_group - 1
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
            table.insert(spec.queues, { id = input.rxq })
         else
            -- Silently truncate receive-queue-size for other drivers.
            -- (We are not sure what they can handle.)
            input.receive_queue_size = math.min(input.receive_queue_size, 8192)
         end
      end

      for name, exporter in pairs(ipfix.exporter) do
         local config = {}
         for key in pairs(ipfix_default_config) do
            config[key] = ipfix[key]
         end
         config.exporter_ip = yang_util.ipv4_ntop(ipfix.exporter_ip)

         config.collector_pool = exporter.collector_pool
         config.templates = exporter.template

         config.output_type = "tap_routed"
         config.add_packet_metadata = false

         config.maps = {}
         for name, map in pairs(ipfix.maps) do
            config.maps[name] = map.file
         end

         local software_scaling = (rss.software_scaling.exporter and
                                    rss.software_scaling.exporter[name])
                               or default_software_scaling
         local num_instances = 1
         if not software_scaling.embed then
            num_instances = software_scaling.instances
         end
         for i = 1, num_instances do
            -- Create a clone of the configuration for parameters
            -- specific to the instance
            local iconfig = lib.deepcopy(config)

            -- This is used to disambiguate multiple instances of the
            -- ipfix app (possibly using multiple instances of the same
            -- template) within a single worker.
            iconfig.instance = name.."_"..i

            local rss_link
            local class = flow_director.class[name]
            if class then
               rss_link = rss_link_name(class_name(name, class))
            elseif name == flow_director.default_class.exporter then
               rss_link = rss_link_name('default')
            else
               -- No traffic class configured for exporter, do not create
               -- instances.
               break
            end

            local collector = select_collector(config.collector_pool)
            iconfig.collector_ip = collector.ip
            iconfig.collector_port = collector.port
            iconfig.collector_pool = nil

            iconfig.log_date = ipfix.log_date
            local od = next_observation_domain()
            iconfig.observation_domain = od
            iconfig.output = "ipfixexport"..od
            if ipfix.maps.log_directory then
               iconfig.maps_logfile =
                  ipfix.maps.log_directory.."/"..od..".log"
            end

            -- Scale the scan protection parameters by the number of
            -- ipfix instances in this RSS class
            local scale_factor = rss.hardware_scaling.rss_groups * num_instances
            iconfig.scan_protection = {
               enable = ipfix.scan_protection.enable,
               threshold_rate = ipfix.scan_protection.threshold_rate / scale_factor,
               export_rate = ipfix.scan_protection.export_rate / scale_factor,
            }

            local output
            if software_scaling.embed then
               output = {
                  link_name = rss_link,
                  args = iconfig
               }
            else
               output = { type = "interlink", link_name = rss_link }
               iconfig.input_type = "interlink"
               iconfig.input = rss_link
               

               workers[rss_link] = probe.configure_graph(iconfig)
               -- Dedicated exporter processes are restartable
               worker_opts[rss_link] = {
                  restart_intensity = software_scaling.restart.intensity,
                  restart_period = software_scaling.restart.period
               }
            end
            table.insert(outputs, output)
         end
      end

      local rss_config = {
         default_class = flow_director.default_class.exporter ~= nil,
         classes = {},
         remove_extension_headers = flow_director.remove_ipv6_extension_headers
      }
      for _, exporter in ipairs(class_order) do
         local class = flow_director.class[exporter]
         table.insert(rss_config.classes, {
            name = class_name(exporter, class),
            filter = class.filter,
            continue = class.continue
         })
      end
      workers["rss"..rss_group] = probe.configure_rss_graph(
         rss_config, inputs, outputs, ipfix.log_date, rss_group
      )
   end

   -- Create a trivial app graph that only contains the control apps
   -- for the Mellanox driver, which sets up the queues and
   -- maintains interface counters.
   local ctrl_graph, need_ctrl = probe.configure_mlx_ctrl_graph(mellanox, ipfix.log_date)

   if need_ctrl then
      workers["mlx_ctrl"] = ctrl_graph
      worker_opts["mlx_ctrl"] = {acquire_cpu=false}
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
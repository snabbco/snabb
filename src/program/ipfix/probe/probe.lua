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

local ipfix = require("apps.ipfix.ipfix")
local probe = require("program.ipfix.lib")

local probe_schema = 'snabb-snabbflow-v1'

local usage = require("program.ipfix.probe.README_inc")

local long_opts = {
   help = "h",
   name = "n",
   busywait ="b",
   ["real-time"] = "r",
   ["no-profile"] = "p",
   ["test-pcap"] = "T"
}
local opt = "hn:brpT:"
local opt_handler = {}
local name
local busywait, real_time, profile = false, false, true
function opt_handler.h () print(usage) main.exit(0) end
function opt_handler.n (arg) name = arg end
function opt_handler.b () busywait = true end
function opt_handler.r () real_time = true end
function opt_handler.p () profile = false end
local pcap_input
function opt_handler.T (arg) pcap_input = arg end

function run (args)
   args = lib.dogetopt(args, opt_handler, opt, long_opts)
   if #args ~= 1 then
      print(usage)
      main.exit(1)
   end
   local confpath = args[1]
   local manager = start(name, confpath)
   manager:main()
end

local probe_cpuset = cpuset.new()

local function update_cpuset (cpu_pool)
   local cpu_set = {}
   if cpu_pool then
      for _, cpu in ipairs(cpu_pool.cpu or {}) do
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

local probe_group_freelist_size

local function update_group_freelist_size (nchunks)
   if not probe_group_freelist_size then
      probe_group_freelist_size = nchunks
   elseif probe_group_freelist_size ~= nchunks then
      error("Can not change group-freelist-size after probe has started.")
   end
   return probe_group_freelist_size
end

local function warn (msg, ...)
   io.stderr:write("Warning: "..msg:format(...).."\n")
   io.stderr:flush()
end

function start (name, confpath)
   local conf = yang.load_configuration(confpath, {schema_name=probe_schema})
   update_cpuset(conf.snabbflow_config.rss.cpu_pool)
   return ptree.new_manager{
      log_level = 'INFO',
      setup_fn = setup_workers,
      initial_configuration = conf,
      schema_name = probe_schema,
      cpuset = probe_cpuset,
      name = name,
      worker_default_scheduling = {
         busywait = busywait,
         real_time = real_time,
         profile = profile,
         group_freelist_size = update_group_freelist_size(
            conf.snabbflow_config.rss.software_scaling.group_freelist_size
         ),
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

local ipfix_default_config = lib.deepcopy(ipfix.IPFIX.config)
for _, key in ipairs({
      "collector_ip",
      "collector_port",
      "observation_domain",
      "exporter_mac",
      "templates",
      "instance"
}) do
   ipfix_default_config[key] = nil
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

   update_group_freelist_size(rss.software_scaling.group_freelist_size)

   local collector_pools = {}
   for name, p in pairs(ipfix.collector_pool) do
      local collectors = {}
      for _, entry in ipairs(p.collector) do
         table.insert(collectors, {
            ip = yang_util.ipv4_ntop(entry.ip),
            port = entry.port
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

   local function ensure_device_unique (device, interfaces)
      for other in pairs(interfaces) do
         if device ~= other then
            if pci.qualified(device) == pci.qualified(other) then
               error("Duplicate interfaces: "..device..", "..other..
                     "\nNot applying configuration. Remove one of them via"..
                     ("\n  snabb config remove <snabbflow> /snabbflow-config/interface[device=%q]")
                        :format(other))
            end
         end
      end
   end

   for rss_group = 1, rss.hardware_scaling.rss_groups do
      local inputs, outputs = {}, {}
      for device, opt in pairs(interfaces) do

         ensure_device_unique(device, interfaces)
         local input = lib.deepcopy(opt)
         input.device = device
         input.rxq = rss_group - 1
         input.log_date = ipfix.log_date
         table.insert(inputs, input)

         -- The mellanox driver requires a master process that sets up
         -- all queues for the interface. We collect all queues per
         -- device of this type here.
         local device_info = pci.device_info(device)
         if device_info.driver == 'apps.mellanox.connectx' then
            local spec = mellanox[device]
            if not spec then
               spec = { name = input.name,
                        alias = input.description,
                        queues = {},
                        recvq_size = input.receive_queue_size,
                        log_date = ipfix.log_date }
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
               rss_link = rss_link_name('class_'..name)
            elseif name == flow_director.default_class.exporter then
               rss_link = rss_link_name('default')
            else
               -- No traffic class configured for exporter, do not create
               -- instances.
               warn("No traffic class configured for exporter '%s'.", name)
               break
            end

            local collector = select_collector(config.collector_pool)
            iconfig.collector_ip = collector.ip
            iconfig.collector_port = collector.port
            iconfig.collector_pool = nil

            iconfig.log_date = ipfix.log_date
            local od = next_observation_domain()
            iconfig.observation_domain = od
            if ipfix.maps.log_directory then
               iconfig.maps_logfile =
                  ipfix.maps.log_directory.."/"..od..".log"
            end

            -- Subtract Ethernet and VLAN overhead from MTU
            iconfig.mtu = iconfig.mtu - 14

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
               output = {
                  type = "interlink",
                  link_name = rss_link,
                  link_size = rss.software_scaling.interlink_size
               }
               workers[rss_link] =
                  probe.configure_interlink_ipfix_tap_instance(
                     rss_link, output.link_size, iconfig
                  )
               -- Dedicated exporter processes are restartable
               worker_opts[rss_link] = {
                  restart_intensity = software_scaling.restart.intensity,
                  restart_period = software_scaling.restart.period,
                  acquire_cpu = software_scaling.acquire_cpu
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
      for i, class in ipairs(flow_director.class) do
         if not ipfix.exporter[class.exporter] then
            error(("Exporter '%s' referenced in traffic class #%d is not defined.")
               :format(class.exporter, i))
         end
         table.insert(rss_config.classes, {
            name = 'class_'..class.exporter,
            filter = class.filter,
            continue = class.continue
         })
      end
      if #outputs == 1 and outputs[1].type ~= 'interlink' then
         -- We have a single output within a single process
         -- (no flow director classes, and a single embedded exporer instance.)
         -- This is the simple case: omit creating a software RSS app.
         -- NB: IPFIX app has to extract metadata as software RSS app is not present.
         local config = outputs[1].args
         config.add_packet_metadata = true
         if pcap_input then
            workers["rss"..rss_group] = probe.configure_pcap_ipfix_tap_instance(
               config, pcap_input, rss_group
            )
         else
            workers["rss"..rss_group] = probe.configure_pci_ipfix_tap_instance(
               config, inputs, rss_group
            )
         end
      else
         -- Otherwise we have the general case: configure a software RSS app to
         -- distribute inputs over flow director classes and exporter instances.
         if pcap_input then
            workers["rss"..rss_group] = probe.configure_pcap_rss_tap_instances(
               rss_config, pcap_input, outputs, rss_group
            )
         else
            workers["rss"..rss_group] = probe.configure_pci_rss_tap_instances(
               rss_config, inputs, outputs, rss_group
            )
         end
      end
   end

   -- Create a trivial app graph that only contains the control apps
   -- for the Mellanox driver, which sets up the queues and
   -- maintains interface counters.
   local ctrl_graph, need_ctrl = probe.configure_mlx_controller(mellanox)

   if need_ctrl then
      workers["mlx_ctrl"] = ctrl_graph
      worker_opts["mlx_ctrl"] = {acquire_cpu=false}
   end

   if false then -- enable to debug
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
   end

   return workers, worker_opts
end

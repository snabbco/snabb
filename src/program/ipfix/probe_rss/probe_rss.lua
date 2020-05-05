module(...,package.seeall)

local S           = require("syscall")
local lib         = require("core.lib")
local app_graph   = require("core.config")
local worker      = require("core.worker")
local shm         = require("core.shm")
local pci         = require("lib.hardware.pci")
local logger      = require("lib.logger")
local probe       = require("program.ipfix.lib")

local main_config = {
   interfaces = { required = true },
   hw_rss_scaling = { default = 1 },
   rss = { required = true },
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
   busywait = { default = nil }
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

local function create_workers (probe_config, duration, busywait, jit, logger)
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

   assert(type(main.interfaces) == "table")

   local mellanox = {}
   local rss_workers = {}
   local observation_domain = ipfix.observation_domain_base

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

            observation_domain = observation_domain + 1
            iconfig.observation_domain = od
            iconfig.output = "ipfixexport"..od
            if exporter.maps_log_dir then
               iconfig.maps_logfile =
                  exporter.maps_log_dir.."/"..od..".log"
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

               local worker_expr = string.format(
                  'require("program.ipfix.lib").run(%s, %s, %s, nil, %s)',
                  probe.value_to_string(iconfig), tostring(duration),
                  tostring(instance.busywait), probe.value_to_string(jit)
               )
               local child_pid = worker.start(rss_link, worker_expr)
               logger:log("Launched IPFIX worker process #"..child_pid)
               logger:log(string.format("Selected collector %s:%d from pool %s "
                                        .."for process #%d ",
                                        collector.ip, collector.port, pool, child_pid))
               shm.create("ipfix_workers/"..child_pid, "uint64_t")
            end
            table.insert(outputs, output)
         end
      end

      local worker_expr = string.format(
         'require("program.ipfix.lib").run_rss(%s, %s, %s, %s, %s, nil, %s)',
         probe.value_to_string(main.rss), probe.value_to_string(inputs),
         probe.value_to_string(outputs), tostring(duration),
         tostring(busywait), probe.value_to_string(override_jit(jit, main.rss_jit, rssq))
      )
      rss_workers["rss"..rssq] = worker_expr

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

   for name, expr in pairs(rss_workers) do
      local child_pid = worker.start(name, expr)
      logger:log("Launched RSS worker process #"..child_pid)
      shm.create("rss_workers/"..child_pid, "uint64_t")
   end

   return ctrl_graph, mellanox
end

local long_opts = {
   duration = "D",
   debug = "d",
   jit = "j",
   help = "h",
   ["busy-wait"] = "b"
}

function run (parameters)
   local duration
   local busywait = false
   local profiling, traceprofiling
   local jit = { opts = {} }
   local log_pid = string.format("[%5d]", S.getpid())
   local logger = logger.new({ rate = 30, module = log_pid.." RSS master" })
   local opt = {
      D = function (arg)
         if arg:match("^[0-9]+$") then
            duration = tonumber(arg)
         else
            usage()
         end
      end,
      h = function (arg) usage() end,
      d = function (arg) _G.developer_debug = true end,
      b = function (arg)
         busywait = true
      end,
      j = probe.parse_jit_option_fn(jit)
   }

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hdj:D:l:b", long_opts)
   if #parameters ~= 1 then usage () end

   local file = table.remove(parameters, 1)
   local probe_config = assert(loadfile(file))()
   local ctrl_graph, mellanox =
      create_workers(probe_config, duration, busywait, jit, logger)

   engine.busywait = false
   engine.Hz = 10
   engine.configure(ctrl_graph)

   for device, spec in pairs(mellanox) do
      probe.create_ifmib(engine.app_table["ctrl_"..device].stats,
                         spec.ifName, spec.ifAlias)
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

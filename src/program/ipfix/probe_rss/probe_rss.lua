module(...,package.seeall)

local lib         = require("core.lib")
local app_graph   = require("core.config")
local worker      = require("core.worker")
local pci         = require("lib.hardware.pci")
local probe       = require("program.ipfix.lib")
local Transmitter = require("apps.interlink.transmitter")

local long_opts = {
   duration = "D",
   logfile = "l",
   debug = "d",
   jit = "j",
   help = "h",
   ["busy-wait"] = "b"
}

function run (parameters)
   local duration = 0
   local busywait = false
   local profiling, traceprofiling
   local jit_opts = {}
   local opt = {
      D = function (arg)
         if arg:match("^[0-9]+$") then
            duration = tonumber(arg)
         else
            usage()
         end
      end,
      l = function (arg)
         local logfh = assert(io.open(arg, "a"))
         lib.logger_default.fh = logfh
      end,
      h = function (arg) usage() end,
      d = function (arg) _G.developer_debug = true end,
      b = function (arg)
         busywait = true
      end,
      j = function (arg)
         if arg:match("^v") then
            local file = arg:match("^v=(.*)")
            if file == '' then file = nil end
            require("jit.v").start(file)
         elseif arg:match("^p") then
            local opts, file = arg:match("^p=([^,]*),?(.*)")
            if file == '' then file = nil end
            require("jit.p").start(opts, file)
            profiling = true
         elseif arg:match("^dump") then
            local opts, file = arg:match("^dump=([^,]*),?(.*)")
            if file == '' then file = nil end
            require("jit.dump").on(opts, file)
         elseif arg:match("^opt") then
            local opt = arg:match("^opt=(.*)")
            table.insert(jit_opts, opt)
         elseif arg:match("^tprof") then
            require("lib.traceprof.traceprof").start()
            traceprofiling = true
         end
      end
   }

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hdj:D:l:b", long_opts)

   -- Defaults: sizemcode=32, maxmcode=512
   require("jit.opt").start('sizemcode=256', 'maxmcode=2048')
   if #jit_opts then
      require("jit.opt").start(unpack(jit_opts))
   end
   if #parameters ~= 1 then usage () end

   local file = table.remove(parameters, 1)

   local engine_opts = { no_report = true, measure_latency = false }
   if duration ~= 0 then engine_opts.duration = duration end

   local probe_config = assert(loadfile(file))()
   engine.configure(create_app_graph(probe_config, busywait))
   jit.flush()
   engine.busywait = busywait
   engine.main(engine_opts)

   if profiling then
      require("jit.p").stop()
   end
   if traceprofiling then
      require("lib.traceprof.traceprof").stop()
   end

end

local main_config = {
   interfaces = { required = true },
   rss = { required = true },
   ipfix = { required = true }
}
local interface_config = {
   device = { required = true },
   tag = { default = nil },
   config = { default = {} }
}
local ipfix_config = {
   default = { default = {} },
   maps = { default = {} },
   exporters = { required = true }
}
local maps_config = {
   pfx_to_as = { default = nil },
   vlan_to_ifindex = { default = nil },
   mac_to_as = { default = nil }
}
local exporter_config = {
   templates = { required = true },
   rss_class = { default = "default" },
   collector_ip = { default = nil },
   collector_port = { default = nil },
   use_maps = { default = false },
   maps_log_dir = { default = nil },
   instances = { default = {} }
}
local instance_config = {
   observation_domain = { required = true },
   embed = { default = true },
   weight = { default = 1 },
   jit = { default = {} },
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

local function value_to_string (value, string)
   string = string or ''
   local type = type(value)
   if type == 'table'  then
      string = string.."{ "
      if #value == 0 then
         for key, value in pairs(value) do
            string = string..key.." = "
            string = value_to_string(value, string)..", "
         end
      else
         for _, value in ipairs(value) do
            string = value_to_string(value, string)..", "
         end
      end
      string = string.." }"
   elseif type == 'string' then
      string = string..("%q"):format(value)
   else
      string = string..("%s"):format(value)
   end
   return string
end

function create_app_graph (probe_config, busywait)
   local main = lib.parse(probe_config, main_config)
   assert(type(main.interfaces) == "table")

   local graph = app_graph.new()

   app_graph.app(graph, "rss", require("apps.rss.rss").rss,
                 main.rss)

   local tags = {}
   for i, interface in ipairs(main.interfaces) do
      local interface = lib.parse(interface, interface_config)
      local suffix = #main.interfaces > 1 and i or ''
      local input_name = "input"..suffix
      local device_info = pci.device_info(interface.device)
      interface.config.pciaddr = interface.device
      app_graph.app(graph, input_name,
                    require(device_info.driver).driver,
                    interface.config)
      local link_name = "input"..suffix
      if interface.tag then
         local tag = interface.tag
         assert(not(tags[tag]), "Tag not unique: "..tag)
         link_name = "vlan"..tag
      end
      app_graph.link(graph, input_name.."."..device_info.tx
                        .." -> rss."..link_name)
   end

   local maps = lib.parse(main.ipfix.maps, maps_config)

   local ipfix_config = lib.parse(main.ipfix.default, ipfix_default_config)
   local function merge_with_default (config)
      local merged = lib.deepcopy(ipfix_config)
      for _, key in ipairs({ "collector_ip", "collector_port", "templates" }) do
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

   local embedded_instance = 1
   local observation_domains = {}
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
         local instance = lib.parse(instance, instance_config)
         local rss_link = rss_link_name(exporter.rss_class, instance.weight)
         local od = instance.observation_domain
         assert(not observation_domains[od],
                "Observation domain not unique: "..od)
         observation_domains[od] = true
         config.observation_domain = od
         config.output = "ipfixexport"..od
         if exporter.maps_log_dir then
            config.maps_log_file =
               exporter.maps_log_dir.."/"..od..".log"
         end
         if instance.embed then
            config.instance = embedded_instance
            probe.configure_graph(config, graph)
            app_graph.link(graph, "rss."..rss_link
                              .." -> ipfix"..embedded_instance..".input")
            embedded_instance = embedded_instance + 1
         else
            config.input_type = "interlink"
            config.input = rss_link
            local jit = lib.parse(instance.jit, jit_config)
            if instance.busywait == nil then
               instance.busywait = busywait
            end
            local worker_expr = string.format(
               'require("program.ipfix.lib").run(%s, nil, %s, nil, %s)',
               value_to_string(config), tostring(instance.busywait),
               value_to_string(jit)
            )
            local child_pid = worker.start(rss_link, worker_expr)
            print("Launched worker process #"..child_pid)
            -- The stats program uses the PID encoded in the name of
            -- the transmitter app to find the receiving IPFIX
            -- process.
            app_graph.app(graph, rss_link, Transmitter)
            app_graph.link(graph, "rss."..rss_link.." -> "..rss_link..".input")
         end
      end
   end
   return graph
end

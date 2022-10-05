module(..., package.seeall)

local now        = require("core.app").now
local lib        = require("core.lib")
local counter    = require("core.counter")
local app_graph  = require("core.config")
local link       = require("core.link")
local pci        = require("lib.hardware.pci")
local numa       = require("lib.numa")
local ipv4       = require("lib.protocol.ipv4")
local ethernet   = require("lib.protocol.ethernet")
local S          = require("syscall")
local basic      = require("apps.basic.basic_apps")
local arp        = require("apps.ipv4.arp")
local ipfix      = require("apps.ipfix.ipfix")
local template   = require("apps.ipfix.template")
local rss        = require("apps.rss.rss")
local iftable    = require("apps.snmp.iftable")
local Transmitter = require("apps.interlink.transmitter")


-- apps that can be used as an input or output for the exporter
local in_apps, out_apps = {}, {}

local function parse_spec (spec, delimiter)
   local t = {}
   for s in spec:split(delimiter or ':') do
      table.insert(t, s)
   end
   return t
end

local function normalize_pci_name (device)
   return pci.qualified(device):gsub("[:%.]", "_")
end

function in_apps.pcap (path)
   return { input = "input",
            output = "output" },
          { require("apps.pcap.pcap").PcapReader, path }
end

function out_apps.pcap (path)
   return { input = "input",
            output = "output" },
          { require("apps.pcap.pcap").PcapWriter, path }
end

function out_apps.tap_routed (device)
   return { input = "input",
            output = "output" },
          { require("apps.tap.tap").Tap, { name = device } }
end

function in_apps.raw (device)
   return { input = "rx",
            output = "tx" },
          { require("apps.socket.raw").RawSocket, device }
end
out_apps.raw = in_apps.raw

function in_apps.tap (device)
   return { input = "input",
            output = "output" },
          { require("apps.tap.tap").Tap, device }
end
out_apps.tap = in_apps.tap

function in_apps.interlink (name)
   return { input = nil,
            output = "output" },
   { require("apps.interlink.receiver"), nil }
end

function in_apps.pci (input)
   local device, rxq = input.device, input.rxq or 0
   local device_info = pci.device_info(device)
   local conf = { pciaddr = device }
   if device_info.driver == 'apps.intel_mp.intel_mp' then
      conf.rxq = rxq
      conf.rxcounter = rxq
      conf.ring_buffer_size = input.receive_queue_size
   elseif device_info.driver == 'apps.mellanox.connectx' then
      conf = {
         pciaddress = device,
         queue = rxq
      }
   end
   return { input = device_info.rx, output = device_info.tx },
          { require(device_info.driver).driver, conf }
end
out_apps.pci = in_apps.pci

probe_config = {
   -- Probe-specific
   output_type = {required = true},
   output = { required = true },
   input_type = { default = nil },
   input = { default = nil },
   exporter_mac = { default = nil },
   -- Passed on to IPFIX app
   active_timeout = { default = nil },
   idle_timeout = { default = nil },
   flush_timeout = { default = nil },
   cache_size = { default = nil },
   max_load_factor = { default = nil },
   scan_time = { default = nil },
   observation_domain = { default = nil },
   template_refresh_interval = { default = nil },
   ipfix_version = { default = nil },
   exporter_ip = { required = true },
   collector_ip = { required = true },
   collector_port = { required = true },
   mtu = { default = nil },
   templates = { required = true },
   maps = { default = {} },
   maps_logfile = { default = nil },
   instance = { default = 1 },
   add_packet_metadata = { default = true },
   log_date = { default = false },
   scan_protection = { default = {} }
}

local function mk_ipfix_config (config)
   return { active_timeout = config.active_timeout,
            idle_timeout = config.idle_timeout,
            flush_timeout = config.flush_timeout,
            cache_size = config.cache_size,
            max_load_factor = config.max_load_factor,
            scan_time = config.scan_time,
            observation_domain = config.observation_domain,
            template_refresh_interval =
               config.template_refresh_interval,
            ipfix_version = config.ipfix_version,
            exporter_ip = config.exporter_ip,
            collector_ip = config.collector_ip,
            collector_port = config.collector_port,
            mtu = config.mtu - 14,
            templates = config.templates,
            maps = config.maps,
            maps_logfile = config.maps_logfile,
            instance = config.instance,
            add_packet_metadata = config.add_packet_metadata,
            log_date = config.log_date,
            scan_protection = config.scan_protection }
end

function configure_graph (arg, in_graph)
   local config = lib.parse(arg, probe_config)

   local in_link, in_app
   if config.input_type then
      assert(in_apps[config.input_type],
             "unknown input type: "..config.input_type)
      assert(config.input, "Missing input parameter")
      in_link, in_app = in_apps[config.input_type](config.input)
   end
   assert(out_apps[config.output_type],
          "unknown output type: "..config.output_type)
   local out_link, out_app = out_apps[config.output_type](config.output)

   if config.output_type == "tap_routed" then
      local tap_config = out_app[2]
      tap_config.mtu = config.mtu
      tap_config.overwrite_dst_mac = true
      tap_config.forwarding = true
   end

   local ipfix_config = mk_ipfix_config(config)
   local ipfix_name = "ipfix_"..config.instance
   local out_name = "out_"..config.instance
   local sink_name = "sink_"..config.instance

   local graph = in_graph or app_graph.new()
   if config.input then
      local in_name = "in"
      if config.input_type == "interlink" then
         in_name = config.input
      end
      app_graph.app(graph, in_name, unpack(in_app))
      app_graph.link(graph, in_name ..".".. in_link.output .. " -> "
                        ..ipfix_name..".input")
   end
   app_graph.app(graph, ipfix_name, ipfix.IPFIX, ipfix_config)
   app_graph.app(graph, out_name, unpack(out_app))

   -- use ARP for link-layer concerns unless the output is connected
   -- to a pcap writer or a routed tap interface
   if (config.output_type ~= "pcap" and
       config.output_type ~= "tap_routed") then
      local arp_name = "arp_"..config.instance
      local arp_config    = { self_mac = config.exporter_mac and
                                 ethernet:pton(config.exporter_mac),
                              self_ip = ipv4:pton(config.exporter_ip),
                              next_ip = ipv4:pton(config.collector_ip) }
      app_graph.app(graph, arp_name, arp.ARP, arp_config)
      app_graph.app(graph, sink_name, basic.Sink)

      app_graph.link(graph, out_name.."."..out_link.output.." -> "
                     ..arp_name..".south")

      -- with UDP, ipfix doesn't need to handle packets from the collector
      app_graph.link(graph, arp_name..".north -> "..sink_name..".input")

      app_graph.link(graph, ipfix_name..".output -> "..arp_name..".north")
      app_graph.link(graph, arp_name..".south -> "
                        ..out_name.."."..out_link.input)
   else
      app_graph.link(graph, ipfix_name..".output -> "
                        ..out_name.."."..out_link.input)
      app_graph.app(graph, sink_name, basic.Sink)
      app_graph.link(graph, out_name.."."..out_link.output.." -> "
                     ..sink_name..".input")
   end

   if config.input_type and config.input_type == "pci" then
      local pciaddr = unpack(parse_spec(config.input, '/'))
      app_graph.app(graph, "nic_ifmib", iftable.MIB, {
         target_app = "in", stats = 'stats',
         ifname = normalize_pci_name(pciaddr),
         log_date = config.log_date
      })
   end
   if config.output_type == "tap_routed" then
      app_graph.app(graph, "tap_ifmib_"..config.instance, iftable.MIB, {
         target_app = out_name,
         ifname = config.output,
         ifalias = "IPFIX Observation Domain "..config.observation_domain,
         log_date = config.log_date
      })
   end

   return graph, config
end

function configure_rss_graph (config, inputs, outputs, log_date, rss_group, input_type)
   input_type = input_type or 'pci'
   local graph = app_graph.new()

   local rss_name = "rss"..(rss_group or '')
   app_graph.app(graph, rss_name, rss.rss, config)

   -- An input describes a physical interface
   local tags, in_app_specs = {}, {}
   for n, input in ipairs(inputs) do
      local input_name, link_name, in_link, in_app
      if input_type == 'pci' then
         local pci_name = normalize_pci_name(input.device)
         input_name, link_name = "input_"..pci_name, pci_name
         in_link, in_app = in_apps.pci(input)
         table.insert(in_app_specs,
                      { pciaddr = input.device,
                        name = input_name,
                        ifname = input.name or pci_name,
                        ifalias = input.description })
      elseif input_type == 'pcap' then
         input_name, link_name = 'pcap', 'pcap'
         in_link, in_app = in_apps.pcap(input)
      else
         error("Unsupported input_type: "..input_type)
      end
      app_graph.app(graph, input_name, unpack(in_app))
      if input.tag then
         local tag = input.tag
         assert(not(tags[tag]), "Tag not unique: "..tag)
         link_name = "vlan"..tag
      end
      app_graph.link(graph, input_name.."."..in_link.output
                        .." -> "..rss_name.."."..link_name)
   end

   -- An output describes either an interlink or a complete ipfix app
   for _, output in ipairs(outputs) do
      if output.type == 'interlink' then
         -- Keys
         --   link_name  name of the link
         app_graph.app(graph, output.link_name, Transmitter)
         app_graph.link(graph, rss_name.."."..output.link_name.." -> "
                           ..output.link_name..".input")
      else
         -- Keys
         --   link_name  name of the link
         --   args       probe configuration
         --   instance   # of embedded instance
         output.args.instance = output.instance or output.args.instance
         local graph = configure_graph(output.args, graph)
         app_graph.link(graph, rss_name.."."..output.link_name
                           .." -> ipfix_"..output.args.instance..".input")
      end
   end

   for _, spec in ipairs(in_app_specs) do
      app_graph.app(graph, "nic_ifmib_"..spec.name, iftable.MIB, {
         target_app = spec.name, stats = 'stats',
         ifname = spec.ifname,
         ifalias = spec.ifalias,
         log_date = log_date
      })
   end
   
   return graph
end

function configure_mlx_ctrl_graph (mellanox, log_date)
   -- Create a trivial app graph that only contains the control apps
   -- for the Mellanox driver, which sets up the queues and
   -- maintains interface counters.
   local ctrl_graph, need_ctrl = app_graph.new(), false
   for device, spec in pairs(mellanox) do
      local conf = {
         pciaddress = device,
         queues = spec.queues,
         recvq_size = spec.recvq_size
      }
      local pci_name = normalize_pci_name(device)
      local driver = pci.device_info(device).driver
      app_graph.app(ctrl_graph, "ctrl_"..pci_name,
                    require(driver).ConnectX, conf)
      app_graph.app(ctrl_graph, "nic_ifmib_"..pci_name, iftable.MIB, {
         target_app = "ctrl_"..pci_name, stats = 'stats',
         ifname = spec.ifName or pci_name,
         ifalias = spec.ifAlias,
         log_date = log_date
      })
      need_ctrl = true
   end
   return ctrl_graph, need_ctrl
end
module(..., package.seeall)

local lib         = require("core.lib")
local app_graph   = require("core.config")
local pci         = require("lib.hardware.pci")
local ipv4        = require("lib.protocol.ipv4")
local ethernet    = require("lib.protocol.ethernet")
local basic       = require("apps.basic.basic_apps")
local ipfix       = require("apps.ipfix.ipfix")
local tap         = require("apps.tap.tap")
local rss         = require("apps.rss.rss")
local iftable     = require("apps.snmp.iftable")
local Receiver    = require("apps.interlink.receiver")
local Transmitter = require("apps.interlink.transmitter")
local pcap        = require("apps.pcap.pcap")

local function normalize_pci_name (device)
   return pci.qualified(device):gsub("[:%.]", "_")
end

local function configure_ipfix_instance (config, in_graph)
   local graph = in_graph or app_graph.new()

   local ipfix_name = "ipfix_"..assert(config.instance)

   app_graph.app(graph, ipfix_name, ipfix.IPFIX, config)

   return graph, {name=ipfix_name, output='output', input='input'}
end

local function configure_tap_output (config, in_graph)
   config = lib.parse(config, {
      instance={required=true},
      observation_domain={required=true},
      mtu={required=true},
      log_date={required=true}
   })
   local graph = in_graph or app_graph.new()

   local device = "ipfixexport"..config.observation_domain

   local tap_config = {
      name = device,
      mtu = config.mtu,
      overwrite_dst_mac = true,
      forwarding = true
   }
   local tap_name = "out_"..config.instance
   local sink_name = "sink_"..config.instance

   -- with UDP, ipfix doesn't need to handle packets from the collector
   -- (hence, discard packets incoming from the tap interface to sink)
   app_graph.app(graph, tap_name, tap.Tap, tap_config)
   app_graph.app(graph, sink_name, basic.Sink)   
   app_graph.link(graph, tap_name..".output -> "..sink_name..".input")
   app_graph.app(graph, "tap_ifmib_"..config.instance, iftable.MIB, {
      target_app = tap_name,
      ifname = device,
      ifalias = "IPFIX Observation Domain "..config.observation_domain,
      log_date = config.log_date
   })

   return graph, {name=tap_name, input='input'}
end

local function configure_interlink_input (config, in_graph)
   config = lib.parse(config, {
      name={required=true},
      size={required=true}
   })
   local graph = in_graph or app_graph.new()

   local in_name = config.name

   app_graph.app(graph, in_name, Receiver, { size = config.size })

   return graph, {name=in_name, output='output'}
end

local function configure_interlink_output (config, in_graph)
   config = lib.parse(config, {
      name={required=true},
      size={required=true}
   })
   local graph = in_graph or app_graph.new()

   local out_name = config.name

   app_graph.app(graph, out_name, Transmitter, { size = config.size })

   return graph, {name=out_name, input='input'}
end

local function configure_pci_input (config, in_graph)
   config = lib.parse(config, {
      device={required=true},
      rxq={required=true},
      receive_queue_size={required=true},
      log_date={required=true},
      vlan_tag={},
      name={},
      description={}
   })
   local graph = in_graph or app_graph.new()

   local pci_name = normalize_pci_name(config.device)
   local in_name = "input_"..pci_name
   local device_info = pci.device_info(config.device)
   assert(device_info.usable == "yes",
          ("Unsupported device %s (%x:%x)"):format(config.device,
                                                   device_info.vendor,
                                                   device_info.device))
   local driver = require(device_info.driver).driver
   local conf
   if device_info.driver == 'apps.intel_mp.intel_mp' then
      conf = {
         pciaddr = config.device,
         rxq = config.rxq,
         rxcounter = config.rxq,
         ring_buffer_size = config.receive_queue_size
      }
   elseif device_info.driver == 'apps.mellanox.connectx' then
      conf = {
         pciaddress = config.device,
         queue = config.rxq
      }
   end

   app_graph.app(graph, in_name, driver, conf)
   app_graph.app(graph, "nic_ifmib_"..in_name, iftable.MIB, {
      target_app = in_name, stats = 'stats',
      ifname = config.name or pci_name,
      ifalias = config.description,
      log_date = config.log_date
   })

   local nic = {name=in_name, input=device_info.rx, output=device_info.tx}
   local link_name = nic.name
   if conf.vlan_tag then
      link_name = "vlan"..conf.vlan_tag
   end

   return graph, nic, link_name
end

local function configure_pcap_input (config, in_graph)
   config = lib.parse(config, {
      path={required=true},
      name={default='pcap'}
   })
   local graph = in_graph or app_graph.new()

   local in_name = config.name

   app_graph.app(graph, in_name, pcap.PcapReader, config.path)

   return graph, {name=in_name, output='output'}
end

local function link (graph, from, to)
   assert(from.name, "missing name in 'from'")
   assert(from.output, "missing output in 'from': "..from.name)
   assert(to.name, "missing name in 'to'")
   assert(to.input, "missing input in 'to': "..to.name)
   app_graph.link(
      graph, from.name.."."..from.output.."->"..to.name.."."..to.input
   )
end

local function configure_ipfix_tap_instance (config, in_graph)
   local graph = in_graph or app_graph.new()
   local _, ipfix = configure_ipfix_instance(config, graph)
   local tap_args = {
      instance = config.instance,
      observation_domain = config.observation_domain,
      mtu = config.mtu,
      log_date = config.log_date
   }
   local _, tap = configure_tap_output(tap_args, graph)
   link(graph, ipfix, tap)
   return graph, ipfix
end

function configure_interlink_ipfix_tap_instance (in_name, link_size, config)
   local graph = app_graph.new()
   local _, receiver = configure_interlink_input({name=in_name, size=link_size}, graph)
   local _, ipfix = configure_ipfix_tap_instance(config, graph)
   link(graph, receiver, ipfix)

   return graph
end

function configure_pci_ipfix_tap_instance (config, inputs, rss_group)
   local graph = app_graph.new()

   local rss_name = "rss"..assert(rss_group)

   local rss = {name=rss_name, output='output'}
   app_graph.app(graph, rss_name, basic.Join)

   local links = {}
   for _, pci in ipairs(inputs) do
      local _, nic, link_name = configure_pci_input(pci, graph)
      links[link_name] = assert(not links[link_name],
         "input link not unique: "..link_name)
      link(graph, nic, {name=rss.name, input=link_name})
   end
   local _, ipfix = configure_ipfix_tap_instance(config, graph)
   link(graph, rss, ipfix)

   return graph
end

function configure_pcap_ipfix_tap_instance (config, pcap_path, rss_group)
   local graph = app_graph.new()

   local rss_name = "rss"..assert(rss_group)

   local _, pcap = configure_pcap_input({name=rss_name, path=pcap_path}, graph)
   local _, ipfix = configure_ipfix_tap_instance(config, graph)
   link(graph, pcap, ipfix)

   return graph
end

local function configure_rss_tap_instances (config, outputs, rss_group, in_graph)
   local graph = in_graph or app_graph.new()

   local rss_name = "rss"..assert(rss_group)
   
   app_graph.app(graph, rss_name, rss.rss, config)

   for _, output in ipairs(outputs) do
      local rss = {name=rss_name, output=output.link_name}
      if output.type == 'interlink' then
         -- Keys
         --   link_name  name of the link
         local _, transmitter = configure_interlink_output(
            {name=output.link_name, size=output.link_size}, graph
         )
         link(graph, rss, transmitter)
      else
         -- Keys
         --   link_name  name of the link
         --   args       probe configuration
         --   instance   # of embedded instance
         output.args.instance = output.instance or output.args.instance
         local _, ipfix = configure_ipfix_tap_instance(output.args, graph)
         link(graph, rss, ipfix)
      end
   end

   return graph, {name=rss_name}
end

function configure_pci_rss_tap_instances (config, inputs, outputs, rss_group)
   local graph = app_graph.new()

   local _, rss = configure_rss_tap_instances(config, outputs, rss_group, graph)
   local links = {}
   for _, pci in ipairs(inputs) do
      local _, nic, link_name = configure_pci_input(pci, graph)
      links[link_name] = assert(not links[link_name],
         "input link not unique: "..link_name)
      link(graph, nic, {name=rss.name, input=link_name})
   end

   return graph
end

function configure_pcap_rss_tap_instances(config, pcap_path, outputs, rss_group)
   local graph = app_graph.new()

   local _, rss = configure_rss_tap_instances(config, outputs, rss_group, graph)
   local _, pcap = configure_pcap_input({path=pcap_path}, graph)
   link(graph, pcap, {name=rss.name, input='pcap'})

   return graph
end

function configure_mlx_controller (devices)
   -- Create a trivial app graph that only contains the control apps
   -- for the Mellanox driver, which sets up the queues and
   -- maintains interface counters.
   local ctrl_graph, need_ctrl = app_graph.new(), false
   for device, spec in pairs(devices) do
      spec = lib.parse(spec, {
         queues={required=true},
         recvq_size={required=true},
         log_date={required=true},
         name={},
         alias={}
      })
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
         ifname = spec.name or pci_name,
         ifalias = spec.alias,
         log_date = spec.log_date
      })
      need_ctrl = true
   end
   return ctrl_graph, need_ctrl
end

module(..., package.seeall)

local now        = require("core.app").now
local lib        = require("core.lib")
local shm        = require("core.shm")
local counter    = require("core.counter")
local app_graph  = require("core.config")
local link       = require("core.link")
local pci        = require("lib.hardware.pci")
local numa       = require("lib.numa")
local ipv4       = require("lib.protocol.ipv4")
local ethernet   = require("lib.protocol.ethernet")
local macaddress = require("lib.macaddress")
local S          = require("syscall")
local basic      = require("apps.basic.basic_apps")
local arp        = require("apps.ipv4.arp")
local ipfix      = require("apps.ipfix.ipfix")
local template   = require("apps.ipfix.template")
local ifmib      = require("lib.ipc.shmem.iftable_mib")

local ifmib_dir = '/ifmib'

-- apps that can be used as an input or output for the exporter
local in_apps, out_apps = {}, {}

local function parse_spec (spec, delimiter)
   local t = {}
   for s in spec:split(delimiter or ':') do
      table.insert(t, s)
   end
   return t
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
   { require("apps.interlink.receiver"), {} }
end

function in_apps.pci (spec)
   local device, rxq = unpack(parse_spec(spec, '/'))
   local device_info = pci.device_info(device)
   local conf = { pciaddr = device }
   if device_info.driver == 'apps.intel_mp.intel_mp' then
      local rxq = (rxq and tonumber(rxq)) or 0
      conf.rxq = rxq
      conf.rxcounter = rxq
      conf.ring_buffer_size = 32768
   end
   return { input = device_info.rx, output = device_info.tx },
          { require(device_info.driver).driver, conf }
end
out_apps.pci = in_apps.pci

function create_ifmib(stats, ifname, ifalias)
   -- stats can be nil in case this process is not the master
   -- of the device
   if not stats then return end
   if not shm.exists(ifmib_dir) then
      shm.mkdir(ifmib_dir)
   end
   ifmib.init_snmp( { ifDescr = ifname,
                      ifName = ifname,
                      ifAlias = ifalias or "NetFlow input", },
      ifname:gsub('/', '-'), stats,
      shm.root..ifmib_dir, 5)
end

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
   add_packet_metadata = { default = true }
}

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
   end

   local function mk_ipfix_config()
      return { active_timeout = config.active_timeout,
               idle_timeout = config.idle_timeout,
               flush_timeout = config.flush_timeout,
               cache_size = config.cache_size,
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
               maps_log_fh = config.maps_logfile and
                  assert(io.open(config.maps_logfile, "a")) or nil,
               instance = config.instance,
               add_packet_metadata = config.add_packet_metadata }
   end

   local ipfix_config = mk_ipfix_config()
   local ipfix_name = "ipfix"..config.instance
   local out_name = "out"..config.instance
   local sink_name = "sink"..config.instance

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
      local arp_name = "arp"..config.instance
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

   engine.configure(graph)

   if config.input_type and config.input_type == "pci" then
      local pciaddr = unpack(parse_spec(config.input, '/'))
      create_ifmib(engine.app_table['in'].stats, (pciaddr:gsub("[:%.]", "_")))
   end

   if config.output_type == "tap_routed" then
      local tap_config = out_app[2]
      local name = tap_config.name
      local tap_sysctl_base = "net/ipv4/conf/"..name
      assert(S.sysctl(tap_sysctl_base.."/rp_filter", '0'))
      assert(S.sysctl(tap_sysctl_base.."/accept_local", '1'))
      assert(S.sysctl(tap_sysctl_base.."/forwarding", '1'))
      local out_stats = engine.app_table[out_name].shm
      local ipfix_config = mk_ipfix_config()
      ipfix_config.exporter_eth_dst =
         tostring(macaddress:new(counter.read(out_stats.macaddr)))
      app_graph.app(graph, ipfix_name, ipfix.IPFIX, ipfix_config)
      engine.configure(graph)
   end

   return config, graph
end

function run (arg, duration, busywait, cpu, jit)
   local config = configure_graph(arg)

   if jit then
      if jit.v then
         require("jit.v").start(jit.v)
      end
      if jit.p and #jit.p > 0 then
         require("jit.p").start(unpack(jit.p))
      end
      if jit.traceprof then
         require("lib.traceprof.traceprof").start()
      end
      if jit.dump and #jit.dump > 0 then
         require("jit.dump").on(unpack(jit.dump))
      end
      if jit.opts and #jit.opts > 0 then
         require("jit.opt").start(unpack(jit.opts))
      end
   end

   local done
   if not duration and config.input_type == "pcap" then
      done = function ()
         return engine.app_table['in'].done
      end
   end

   local t1 = now()
   if cpu then numa.bind_to_cpu(cpu) end

   engine.busywait = busywait
   engine.main({ duration = duration, done = done, measure_latency = false })

   if jit then
      if jit.dump then
         require("jit.dump").off()
      end
      if jit.traceprof then
         require("lib.traceprof.traceprof").stop()
      end
      if jit.p then
         require("jit.p").stop()
      end
      if jit.v then
         require("jit.v").stop()
      end
   end

   local t2 = now()
   local stats = link.stats(engine.app_table.ipfix.input.input)
   print("IPFIX probe stats:")
   local comma = lib.comma_value
   print(string.format("bytes: %s packets: %s bps: %s Mpps: %s",
                       comma(stats.rxbytes),
                       comma(stats.rxpackets),
                       comma(math.floor((stats.rxbytes * 8) / (t2 - t1))),
                       comma(stats.rxpackets / ((t2 - t1) * 1000000))))

end

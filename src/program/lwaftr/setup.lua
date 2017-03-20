module(..., package.seeall)

local config     = require("core.config")
local worker     = require("core.worker")
local leader     = require("apps.config.leader")
local follower   = require("apps.config.follower")
local Intel82599 = require("apps.intel.intel_app").Intel82599
local PcapFilter = require("apps.packet_filter.pcap_filter").PcapFilter
local V4V6       = require("apps.lwaftr.V4V6").V4V6
local VirtioNet  = require("apps.virtio_net.virtio_net").VirtioNet
local lwaftr     = require("apps.lwaftr.lwaftr")
local lwcounter  = require("apps.lwaftr.lwcounter")
local basic_apps = require("apps.basic.basic_apps")
local pcap       = require("apps.pcap.pcap")
local ipv4_apps  = require("apps.lwaftr.ipv4_apps")
local ipv6_apps  = require("apps.lwaftr.ipv6_apps")
local vlan       = require("apps.vlan.vlan")
local numa       = require("lib.numa")
local ipv4       = require("lib.protocol.ipv4")
local ethernet   = require("lib.protocol.ethernet")
local ipv4_ntop  = require("lib.yang.util").ipv4_ntop
local S          = require("syscall")
local engine     = require("core.app")

local capabilities = {['ietf-softwire']={feature={'binding', 'br'}}}
require('lib.yang.schema').set_default_capabilities(capabilities)

local function convert_ipv4(addr)
   if addr ~= nil then return ipv4:pton(ipv4_ntop(addr)) end
end

function lwaftr_app(c, conf)
   assert(type(conf) == 'table')
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface
   local function append(t, elem) table.insert(t, elem) end
   local function prepend(t, elem) table.insert(t, 1, elem) end

   -- Claim the name if one is defined.
   local function switch_names(config)
      local currentname = engine.program_name
      local name = config.softwire_config.name
      -- Don't do anything if the name isn't set.
      if name == nil then
         return
      end

      local success, err = pcall(engine.claim_name, name)
      if success == false then
         -- Restore the previous name.
         config.softwire_config.name = currentname
         assert(success, err)
      end
   end
   switch_names(conf)

   -- Verify either or both of next-hop value's are specified (can't be done in YANG)
   if internal_interface.next_hop == nil then
      error("One or both of the 'next_hop' values must be specified")
   end

   config.app(c, "reassemblerv4", ipv4_apps.Reassembler,
              { max_ipv4_reassembly_packets =
                   external_interface.reassembly.max_packets,
                max_fragments_per_reassembly_packet =
                   external_interface.reassembly.max_fragments_per_packet })
   config.app(c, "reassemblerv6", ipv6_apps.ReassembleV6,
              { max_ipv6_reassembly_packets =
                   internal_interface.reassembly.max_packets,
                max_fragments_per_reassembly_packet =
                   internal_interface.reassembly.max_fragments_per_packet })
   config.app(c, "icmpechov4", ipv4_apps.ICMPEcho,
              { address = convert_ipv4(external_interface.ip) })
   config.app(c, "icmpechov6", ipv6_apps.ICMPEcho,
              { address = internal_interface.ip })
   config.app(c, 'lwaftr', lwaftr.LwAftr, conf)
   config.app(c, "fragmenterv4", ipv4_apps.Fragmenter,
              { mtu=external_interface.mtu })
   config.app(c, "fragmenterv6", ipv6_apps.Fragmenter,
              { mtu=internal_interface.mtu })
   config.app(c, "ndp", ipv6_apps.NDP,
              { src_ipv6 = internal_interface.ip,
                src_eth = internal_interface.mac,
                dst_eth = internal_interface.next_hop.mac,
                dst_ipv6 = internal_interface.next_hop.ip })
   config.app(c, "arp", ipv4_apps.ARP,
              { src_ipv4 = convert_ipv4(external_interface.ip),
                src_eth = external_interface.mac,
                dst_eth = external_interface.next_hop.mac,
                dst_ipv4 = convert_ipv4(external_interface.next_hop.ip) })

   local preprocessing_apps_v4  = { "reassemblerv4" }
   local preprocessing_apps_v6  = { "reassemblerv6" }
   local postprocessing_apps_v4  = { "fragmenterv4" }
   local postprocessing_apps_v6  = { "fragmenterv6" }

   if external_interface.ingress_filter then
      config.app(c, "ingress_filterv4", PcapFilter,
                 { filter = external_interface.ingress_filter })
      append(preprocessing_apps_v4, "ingress_filterv4")
   end
   if internal_interface.ingress_filter then
      config.app(c, "ingress_filterv6", PcapFilter,
                 { filter = internal_interface.ingress_filter })
      append(preprocessing_apps_v6, "ingress_filterv6")
   end
   if external_interface.egress_filter then
      config.app(c, "egress_filterv4", PcapFilter,
                 { filter = external_interface.egress_filter })
      prepend(postprocessing_apps_v4, "egress_filterv4")
   end
   if internal_interface.egress_filter then
      config.app(c, "egress_filterv6", PcapFilter,
                 { filter = internal_interface.egress_filter })
      prepend(postprocessing_apps_v6, "egress_filterv6")
   end

   -- Add a special hairpinning queue to the lwaftr app.
   config.link(c, "lwaftr.hairpin_out -> lwaftr.hairpin_in")

   append(preprocessing_apps_v4,   { name = "arp",        input = "south", output = "north" })
   append(preprocessing_apps_v4,   { name = "icmpechov4", input = "south", output = "north" })
   prepend(postprocessing_apps_v4, { name = "icmpechov4", input = "north", output = "south" })
   prepend(postprocessing_apps_v4, { name = "arp",        input = "north", output = "south" })

   append(preprocessing_apps_v6,   { name = "ndp",        input = "south", output = "north" })
   append(preprocessing_apps_v6,   { name = "icmpechov6", input = "south", output = "north" })
   prepend(postprocessing_apps_v6, { name = "icmpechov6", input = "north", output = "south" })
   prepend(postprocessing_apps_v6, { name = "ndp",        input = "north", output = "south" })

   set_preprocessors(c, preprocessing_apps_v4, "lwaftr.v4")
   set_preprocessors(c, preprocessing_apps_v6, "lwaftr.v6")
   set_postprocessors(c, "lwaftr.v6", postprocessing_apps_v6)
   set_postprocessors(c, "lwaftr.v4", postprocessing_apps_v4)
end

local function link_apps(c, apps)
   for i=1, #apps - 1 do
      local output, input = "output", "input"
      local src, dst = apps[i], apps[i+1]
      if type(src) == "table" then
         src, output = src["name"], src["output"]
      end
      if type(dst) == "table" then
         dst, input = dst["name"], dst["input"]
      end
      config.link(c, ("%s.%s -> %s.%s"):format(src, output, dst, input))
   end
end

function set_preprocessors(c, apps, dst)
   assert(type(apps) == "table")
   link_apps(c, apps)
   local last_app, output = apps[#apps], "output"
   if type(last_app) == "table" then
      last_app, output = last_app.name, last_app.output
   end
   config.link(c, ("%s.%s -> %s"):format(last_app, output, dst))
end

function set_postprocessors(c, src, apps)
   assert(type(apps) == "table")
   local first_app, input = apps[1], "input"
   if type(first_app) == "table" then
      first_app, input = first_app.name, first_app.input
   end
   config.link(c, ("%s -> %s.%s"):format(src, first_app, input))
   link_apps(c, apps)
end

local function link_source(c, v4_in, v6_in)
   config.link(c, v4_in..' -> reassemblerv4.input')
   config.link(c, v6_in..' -> reassemblerv6.input')
end

local function link_sink(c, v4_out, v6_out)
   config.link(c, 'fragmenterv4.output -> '..v4_out)
   config.link(c, 'fragmenterv6.output -> '..v6_out)
end

function load_phy(c, conf, v4_nic_name, v4_nic_pci, v6_nic_name, v6_nic_pci)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, v4_nic_name, Intel82599, {
      pciaddr=v4_nic_pci,
      vmdq=external_interface.vlan_tag,
      vlan=external_interface.vlan_tag,
      rxcounter=1,
      macaddr=ethernet:ntop(external_interface.mac)})
   config.app(c, v6_nic_name, Intel82599, {
      pciaddr=v6_nic_pci,
      vmdq=internal_interface.vlan_tag,
      vlan=internal_interface.vlan_tag,
      rxcounter=1,
      macaddr = ethernet:ntop(internal_interface.mac)})

   link_source(c, v4_nic_name..'.tx', v6_nic_name..'.tx')
   link_sink(c, v4_nic_name..'.rx', v6_nic_name..'.rx')
end

function load_on_a_stick(c, conf, args)
   lwaftr_app(c, conf)
   local v4_nic_name, v6_nic_name, v4v6, pciaddr, mirror = args.v4_nic_name,
      args.v6_nic_name, args.v4v6, args.pciaddr, args.mirror
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   if v4v6 then
      config.app(c, 'nic', Intel82599, {
         pciaddr = pciaddr,
         vmdq=external_interface.vlan_tag,
         vlan=external_interface.vlan_tag,
         macaddr = ethernet:ntop(external_interface.mac)})
      if mirror then
         local Tap = require("apps.tap.tap").Tap
         local ifname = mirror
         config.app(c, 'tap', Tap, ifname)
         config.app(c, v4v6, V4V6, {
            mirror = true
         })
         config.link(c, v4v6..'.mirror -> tap.input')
      else
         config.app(c, v4v6, V4V6)
      end
      config.link(c, 'nic.tx -> '..v4v6..'.input')
      config.link(c, v4v6..'.output -> nic.rx')

      link_source(c, v4v6..'.v4', v4v6..'.v6')
      link_sink(c, v4v6..'.v4', v4v6..'.v6')
   else
      config.app(c, v4_nic_name, Intel82599, {
         pciaddr = pciaddr,
         vmdq=external_interface.vlan_tag,
         vlan=external_interface.vlan_tag,
         macaddr = ethernet:ntop(external_interface.mac)})
      config.app(c, v6_nic_name, Intel82599, {
         pciaddr = pciaddr,
         vmdq=internal_interface.vlan_tag,
         vlan=internal_interface.vlan_tag,
         macaddr = ethernet:ntop(internal_interface.mac)})

      link_source(c, v4_nic_name..'.tx', v6_nic_name..'.tx')
      link_sink(c, v4_nic_name..'.rx', v6_nic_name..'.rx')
   end
end

function load_virt(c, conf, v4_nic_name, v4_nic_pci, v6_nic_name, v6_nic_pci)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, v4_nic_name, VirtioNet, {
      pciaddr=v4_nic_pci,
      vlan=external_interface.vlan_tag,
      macaddr=ethernet:ntop(external_interface.mac)})
   config.app(c, v6_nic_name, VirtioNet, {
      pciaddr=v6_nic_pci,
      vlan=internal_interface.vlan_tag,
      macaddr = ethernet:ntop(internal_interface.mac)})

   link_source(c, v4_nic_name..'.tx', v6_nic_name..'.tx')
   link_sink(c, v4_nic_name..'.rx', v6_nic_name..'.rx')
end

function load_bench(c, conf, v4_pcap, v6_pcap, v4_sink, v6_sink)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, "capturev4", pcap.PcapReader, v4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, v6_pcap)
   config.app(c, "repeaterv4", basic_apps.Repeater)
   config.app(c, "repeaterv6", basic_apps.Repeater)
   if external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=external_interface.vlan_tag })
   end
   if internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=internal_interface.vlan_tag })
   end
   config.app(c, v4_sink, basic_apps.Sink)
   config.app(c, v6_sink, basic_apps.Sink)

   config.link(c, "capturev4.output -> repeaterv4.input")
   config.link(c, "capturev6.output -> repeaterv6.input")

   local v4_src, v6_src = 'repeaterv4.output', 'repeaterv6.output'
   if external_interface.vlan_tag then
      config.link(c, v4_src.." -> untagv4.input")
      v4_src = "untagv4.output"
   end
   if internal_interface.vlan_tag then
      config.link(c, v6_src.." -> untagv6.input")
      v6_src = "untagv6.output"
   end
   link_source(c, v4_src, v6_src)
   link_sink(c, v4_sink..'.input', v6_sink..'.input')
end

function load_check_on_a_stick (c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)
   if external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=external_interface.vlan_tag })
   end
   if internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=internal_interface.vlan_tag })
   end

   config.app(c, 'v4v6', V4V6)
   config.app(c, 'splitter', V4V6)
   config.app(c, 'join', basic_apps.Join)

   local sources = { "v4v6.v4", "v4v6.v6" }
   local sinks = { "v4v6.v4", "v4v6.v6" }

   if external_interface.vlan_tag then
      config.link(c, "capturev4.output -> untagv4.input")
      config.link(c, "capturev6.output -> untagv6.input")
      config.link(c, "untagv4.output -> join.in1")
      config.link(c, "untagv6.output -> join.in2")
      config.link(c, "join.output -> v4v6.input")
      config.link(c, "v4v6.output -> splitter.input")
      config.link(c, "splitter.v4 -> tagv4.input")
      config.link(c, "splitter.v6 -> tagv6.input")
      config.link(c, "tagv4.output -> output_filev4.input")
      config.link(c, "tagv6.output -> output_filev6.input")
   else
      config.link(c, "capturev4.output -> join.in1")
      config.link(c, "capturev6.output -> join.in2")
      config.link(c, "join.output -> v4v6.input")
      config.link(c, "v4v6.output -> splitter.input")
      config.link(c, "splitter.v4 -> output_filev4.input")
      config.link(c, "splitter.v6 -> output_filev6.input")
   end

   link_source(c, unpack(sources))
   link_sink(c, unpack(sinks))
end

function load_check(c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)
   if external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=external_interface.vlan_tag })
   end
   if internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=internal_interface.vlan_tag })
   end

   local sources = { "capturev4.output", "capturev6.output" }
   local sinks = { "output_filev4.input", "output_filev6.input" }

   if external_interface.vlan_tag then
      sources = { "untagv4.output", "untagv6.output" }
      sinks = { "tagv4.input", "tagv6.input" }

      config.link(c, "capturev4.output -> untagv4.input")
      config.link(c, "capturev6.output -> untagv6.input")
      config.link(c, "tagv4.output -> output_filev4.input")
      config.link(c, "tagv6.output -> output_filev6.input")
   end

   link_source(c, unpack(sources))
   link_sink(c, unpack(sinks))
end

function load_soak_test(c, conf, inv4_pcap, inv6_pcap)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "loop_v4", basic_apps.Repeater)
   config.app(c, "loop_v6", basic_apps.Repeater)
   config.app(c, "sink", basic_apps.Sink)
   if external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=external_interface.vlan_tag })
   end
   if internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=internal_interface.vlan_tag })
   end

   local sources = { "loop_v4.output", "loop_v6.output" }
   local sinks = { "sink.v4", "sink.v6" }

   config.link(c, "capturev4.output -> loop_v4.input")
   config.link(c, "capturev6.output -> loop_v6.input")

   if external_interface.vlan_tag then
      sources = { "untagv4.output", "untagv6.output" }
      sinks = { "tagv4.input", "tagv6.input" }

      config.link(c, "loop_v4.output -> untagv4.input")
      config.link(c, "loop_v6.output -> untagv6.input")
      config.link(c, "tagv4.output -> sink.v4")
      config.link(c, "tagv6.output -> sink.v6")
   end

   link_source(c, unpack(sources))
   link_sink(c, unpack(sinks))
end

function load_soak_test_on_a_stick (c, conf, inv4_pcap, inv6_pcap)
   lwaftr_app(c, conf)
   local external_interface = conf.softwire_config.external_interface
   local internal_interface = conf.softwire_config.internal_interface

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "loop_v4", basic_apps.Repeater)
   config.app(c, "loop_v6", basic_apps.Repeater)
   config.app(c, "sink", basic_apps.Sink)
   if external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=external_interface.vlan_tag })
   end
   if internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=internal_interface.vlan_tag })
   end

   config.app(c, 'v4v6', V4V6)
   config.app(c, 'splitter', V4V6)
   config.app(c, 'join', basic_apps.Join)

   local sources = { "v4v6.v4", "v4v6.v6" }
   local sinks = { "v4v6.v4", "v4v6.v6" }

   config.link(c, "capturev4.output -> loop_v4.input")
   config.link(c, "capturev6.output -> loop_v6.input")

   if external_interface.vlan_tag then
      config.link(c, "loop_v4.output -> untagv4.input")
      config.link(c, "loop_v6.output -> untagv6.input")
      config.link(c, "untagv4.output -> join.in1")
      config.link(c, "untagv6.output -> join.in2")
      config.link(c, "join.output -> v4v6.input")
      config.link(c, "v4v6.output -> splitter.input")
      config.link(c, "splitter.v4 -> tagv4.input")
      config.link(c, "splitter.v6 -> tagv6.input")
      config.link(c, "tagv4.output -> sink.in1")
      config.link(c, "tagv6.output -> sink.in2")
   else
      config.link(c, "loop_v4.output -> join.in1")
      config.link(c, "loop_v6.output -> join.in2")
      config.link(c, "join.output -> v4v6.input")
      config.link(c, "v4v6.output -> splitter.input")
      config.link(c, "splitter.v4 -> sink.in1")
      config.link(c, "splitter.v6 -> sink.in2")
   end

   link_source(c, unpack(sources))
   link_sink(c, unpack(sinks))
end

local apply_scheduling_opts = {
   cpu = { required=false },
   pci_addrs = { default={} },
   real_time = { default=false },
   ingress_drop_monitor = { default='flush' }
}
function apply_scheduling(opts)
   local lib = require("core.lib")
   local ingress_drop_monitor = require("lib.timers.ingress_drop_monitor")
   local fatal = require("apps.lwaftr.lwutil").fatal

   opts = lib.parse(opts, apply_scheduling_opts)
   if opts.cpu then
      local success, err = pcall(numa.bind_to_cpu, opts.cpu)
      if not success then fatal(err) end
      print("Bound data plane to CPU:", opts.cpu)
   end
   numa.check_affinity_for_pci_addresses(opts.pci_addrs)
   if opts.ingress_drop_monitor then
      local mon = ingress_drop_monitor.new({action=opts.ingress_drop_monitor})
      timer.activate(mon:timer())
   end
   if opts.real_time then
      if not S.sched_setscheduler(0, "fifo", 1) then
         fatal('Failed to enable real-time scheduling.  Try running as root.')
      end
   end
end

function run_worker(scheduling)
   local app = require("core.app")
   apply_scheduling(scheduling)
   local myconf = config.new()
   config.app(myconf, "follower", follower.Follower, {})
   app.configure(myconf)
   app.busywait = true
   app.main({})
end

local function stringify(x)
   if type(x) == 'string' then return string.format('%q', x) end
   if type(x) == 'number' then return tostring(x) end
   if type(x) == 'boolean' then return x and 'true' or 'false' end
   assert(type(x) == 'table')
   local ret = {"{"}
   local first = true
   for k,v in pairs(x) do
      if first then first = false else table.insert(ret, ",") end
      table.insert(ret, string.format('[%s]=%s', stringify(k), stringify(v)))
   end
   table.insert(ret, "}")
   return table.concat(ret)
end

function reconfigurable(scheduling, f, graph, conf, ...)
   local args = {...}

   local function setup_fn(conf)
      local graph = config.new()
      f(graph, conf, unpack(args))
      return graph
   end

   if scheduling.cpu then
      local wanted_node = numa.cpu_get_numa_node(scheduling.cpu)
      numa.bind_to_numa_node(wanted_node)
      print("Bound main process to NUMA node: ", wanted_node)
   end

   local worker_code = "require('program.lwaftr.setup').run_worker(%s)"
   worker_code = worker_code:format(stringify(scheduling))

   local follower_pid = worker.start("follower", worker_code)

   config.app(graph, 'leader', leader.Leader,
              { setup_fn = setup_fn, initial_configuration = conf,
                follower_pids = { follower_pid },
                schema_name = 'snabb-softwire-v1'})
end

module(..., package.seeall)

local config     = require("core.config")
local leader     = require("apps.config.leader")
local follower   = require("apps.config.follower")
local PcapFilter = require("apps.packet_filter.pcap_filter").PcapFilter
local V4V6       = require("apps.lwaftr.V4V6").V4V6
local VirtioNet  = require("apps.virtio_net.virtio_net").VirtioNet
local lwaftr     = require("apps.lwaftr.lwaftr")
local lwutil     = require("apps.lwaftr.lwutil")
local basic_apps = require("apps.basic.basic_apps")
local pcap       = require("apps.pcap.pcap")
local ipv4_echo  = require("apps.ipv4.echo")
local ipv4_fragment   = require("apps.ipv4.fragment")
local ipv4_reassemble = require("apps.ipv4.reassemble")
local arp        = require("apps.ipv4.arp")
local ipv6_echo  = require("apps.ipv6.echo")
local ipv6_fragment   = require("apps.ipv6.fragment")
local ipv6_reassemble = require("apps.ipv6.reassemble")
local ndp        = require("apps.lwaftr.ndp")
local vlan       = require("apps.vlan.vlan")
local pci        = require("lib.hardware.pci")
local numa       = require("lib.numa")
local cltable    = require("lib.cltable")
local ipv4       = require("lib.protocol.ipv4")
local ethernet   = require("lib.protocol.ethernet")
local ipv4_ntop  = require("lib.yang.util").ipv4_ntop
local binary     = require("lib.yang.binary")
local cltable    = require("lib.cltable")
local S          = require("syscall")
local engine     = require("core.app")
local lib        = require("core.lib")
local shm        = require("core.shm")
local yang       = require("lib.yang.yang")

local alarm_notification = false

local capabilities = {
   ['ietf-softwire']={feature={'binding', 'br'}},
   ['ietf-alarms']={feature={'operator-actions', 'alarm-shelving', 'alarm-history'}},
}
require('lib.yang.schema').set_default_capabilities(capabilities)

function read_config(filename)
   return yang.load_configuration(filename,
                                  {schema_name=lwaftr.LwAftr.yang_schema})
end

local function convert_ipv4(addr)
   if addr ~= nil then return ipv4:pton(ipv4_ntop(addr)) end
end

-- Checks the existance and NUMA affinity of PCI devices
-- NB: "nil" can be passed in and will be siliently ignored.
local function validate_pci_devices(devices)
   numa.check_affinity_for_pci_addresses(devices)
   for _, address in pairs(devices) do
      assert(lwutil.nic_exists(address),
             ("Could not locate PCI device '%s'"):format(address))
   end
end

-- Return device PCI address, queue ID, and queue configuration.
local function parse_instance(conf)
   local device, instance
   for k, v in pairs(conf.softwire_config.instance) do
      assert(device == nil, "configuration has more than one instance")
      device, instance = k, v
   end
   assert(device ~= nil, "configuration has no instance")
   local id, queue
   for k, v in cltable.pairs(instance.queue) do
      assert(id == nil, "configuration has more than one RSS queue")
      id, queue = k.id, v
   end
   assert(id ~= nil, "configuration has no RSS queues")
   return device, id, queue
end

function lwaftr_app(c, conf)
   assert(type(conf) == 'table')

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

   local device, id, queue = parse_instance(conf)

   -- Global interfaces
   local gexternal_interface = conf.softwire_config.external_interface
   local ginternal_interface = conf.softwire_config.internal_interface

   -- Instance specific interfaces
   local iexternal_interface = queue.external_interface
   local iinternal_interface = queue.internal_interface

   config.app(c, "reassemblerv4", ipv4_reassemble.Reassembler,
              { max_concurrent_reassemblies =
                   gexternal_interface.reassembly.max_packets,
                max_fragments_per_reassembly =
                   gexternal_interface.reassembly.max_fragments_per_packet })
   config.app(c, "reassemblerv6", ipv6_reassemble.Reassembler,
              { max_concurrent_reassemblies =
                   ginternal_interface.reassembly.max_packets,
                max_fragments_per_reassembly =
                   ginternal_interface.reassembly.max_fragments_per_packet })
   config.app(c, "icmpechov4", ipv4_echo.ICMPEcho,
              { address = convert_ipv4(iexternal_interface.ip) })
   config.app(c, "icmpechov6", ipv6_echo.ICMPEcho,
              { address = iinternal_interface.ip })
   config.app(c, "lwaftr", lwaftr.LwAftr, conf)
   config.app(c, "fragmenterv4", ipv4_fragment.Fragmenter,
              { mtu=gexternal_interface.mtu })
   config.app(c, "fragmenterv6", ipv6_fragment.Fragmenter,
              { mtu=ginternal_interface.mtu })
   config.app(c, "ndp", ndp.NDP,
              { self_ip = iinternal_interface.ip,
                self_mac = iinternal_interface.mac,
                next_mac = iinternal_interface.next_hop.mac,
                next_ip = iinternal_interface.next_hop.ip,
                alarm_notification = conf.alarm_notification })
   config.app(c, "arp", arp.ARP,
              { self_ip = convert_ipv4(iexternal_interface.ip),
                self_mac = iexternal_interface.mac,
                next_mac = iexternal_interface.next_hop.mac,
                next_ip = convert_ipv4(iexternal_interface.next_hop.ip),
                alarm_notification = conf.alarm_notification })

   if conf.alarm_notification then
      require('program.lwaftr.alarms')
   end

   local preprocessing_apps_v4  = { "reassemblerv4" }
   local preprocessing_apps_v6  = { "reassemblerv6" }
   local postprocessing_apps_v4  = { "fragmenterv4" }
   local postprocessing_apps_v6  = { "fragmenterv6" }

   if gexternal_interface.ingress_filter then
      config.app(c, "ingress_filterv4", PcapFilter,
                 { filter = gexternal_interface.ingress_filter })
      append(preprocessing_apps_v4, "ingress_filterv4")
   end
   if ginternal_interface.ingress_filter then
      config.app(c, "ingress_filterv6", PcapFilter,
                 { filter = ginternal_interface.ingress_filter })
      append(preprocessing_apps_v6, "ingress_filterv6")
   end
   if gexternal_interface.egress_filter then
      config.app(c, "egress_filterv4", PcapFilter,
                 { filter = gexternal_interface.egress_filter })
      prepend(postprocessing_apps_v4, "egress_filterv4")
   end
   if ginternal_interface.egress_filter then
      config.app(c, "egress_filterv6", PcapFilter,
                 { filter = ginternal_interface.egress_filter })
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

function load_phy(c, conf, v4_nic_name, v6_nic_name, ring_buffer_size)
   local v4_pci, id, queue = parse_instance(conf)
   local v6_pci = queue.external_interface.device
   local v4_info = pci.device_info(v4_pci)
   local v6_info = pci.device_info(v6_pci)
   validate_pci_devices({v4_pci, v6_pci})
   lwaftr_app(c, conf, v4_pci)

   config.app(c, v4_nic_name, require(v4_info.driver).driver, {
      pciaddr=v4_pci,
      vmdq=true, -- Needed to enable MAC filtering/stamping.
      rxq=id,
      txq=id,
      vlan=queue.external_interface.vlan_tag,
      rxcounter=1,
      ring_buffer_size=ring_buffer_size,
      macaddr=ethernet:ntop(queue.external_interface.mac)})
   config.app(c, v6_nic_name, require(v6_info.driver).driver, {
      pciaddr=v6_pci,
      vmdq=true, -- Needed to enable MAC filtering/stamping.
      rxq=id,
      txq=id,
      vlan=queue.internal_interface.vlan_tag,
      rxcounter=1,
      ring_buffer_size=ring_buffer_size,
      macaddr = ethernet:ntop(queue.internal_interface.mac)})

   link_source(c, v4_nic_name..'.'..v4_info.tx, v6_nic_name..'.'..v6_info.tx)
   link_sink(c,   v4_nic_name..'.'..v4_info.rx, v6_nic_name..'.'..v6_info.rx)
end

function load_on_a_stick(c, conf, args)
   local pciaddr, id, queue = parse_instance(conf)
   local device = pci.device_info(pciaddr)
   local driver = require(device.driver).driver
   validate_pci_devices({pciaddr})
   lwaftr_app(c, conf, pciaddr)
   local v4_nic_name, v6_nic_name, v4v6, mirror = args.v4_nic_name,
      args.v6_nic_name, args.v4v6, args.mirror

   if v4v6 then
      assert(queue.external_interface.vlan_tag == queue.internal_interface.vlan_tag)
      config.app(c, 'nic', driver, {
         pciaddr = pciaddr,
         vmdq=true, -- Needed to enable MAC filtering/stamping.
         rxq=id,
         txq=id,
         vlan=queue.external_interface.vlan_tag,
         ring_buffer_size=args.ring_buffer_size,
         macaddr = ethernet:ntop(queue.external_interface.mac)})
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
      config.link(c, 'nic.'..device.tx..' -> '..v4v6..'.input')
      config.link(c, v4v6..'.output -> nic.'..device.rx)

      link_source(c, v4v6..'.v4', v4v6..'.v6')
      link_sink(c, v4v6..'.v4', v4v6..'.v6')
   else
      config.app(c, v4_nic_name, driver, {
         pciaddr = pciaddr,
         vmdq=true, -- Needed to enable MAC filtering/stamping.
         rxq=id,
         txq=id,
         vlan=queue.external_interface.vlan_tag,
         ring_buffer_size=args.ring_buffer_size,
         macaddr = ethernet:ntop(queue.external_interface.mac)})
      config.app(c, v6_nic_name, driver, {
         pciaddr = pciaddr,
         vmdq=true, -- Needed to enable MAC filtering/stamping.
         rxq=id,
         txq=id,
         vlan=queue.internal_interface.vlan_tag,
         ring_buffer_size=args.ring_buffer_size,
         macaddr = ethernet:ntop(queue.internal_interface.mac)})

      link_source(c, v4_nic_name..'.'..device.tx, v6_nic_name..'.'..device.tx)
      link_sink(c,   v4_nic_name..'.'..device.rx, v6_nic_name..'.'..device.rx)
   end
end

function load_virt(c, conf, v4_nic_name, v6_nic_name)
   local v4_pci, id, queue = parse_instance(conf)
   local v6_pci = queue.external_device.device
   lwaftr_app(c, conf, device)

   validate_pci_devices({v4_pci, v6_pci})
   config.app(c, v4_nic_name, VirtioNet, {
      pciaddr=v4_pci,
      vlan=queue.external_interface.vlan_tag,
      macaddr=ethernet:ntop(queue.external_interface.mac)})
   config.app(c, v6_nic_name, VirtioNet, {
      pciaddr=v6_pci,
      vlan=queue.internal_interface.vlan_tag,
      macaddr = ethernet:ntop(queue.internal_interface.mac)})

   link_source(c, v4_nic_name..'.tx', v6_nic_name..'.tx')
   link_sink(c, v4_nic_name..'.rx', v6_nic_name..'.rx')
end

function load_bench(c, conf, v4_pcap, v6_pcap, v4_sink, v6_sink)
   local device, id, queue = parse_instance(conf)
   lwaftr_app(c, conf, device)

   config.app(c, "capturev4", pcap.PcapReader, v4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, v6_pcap)
   config.app(c, "repeaterv4", basic_apps.Repeater)
   config.app(c, "repeaterv6", basic_apps.Repeater)
   if queue.external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=queue.external_interface.vlan_tag })
   end
   if queue.internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=queue.internal_interface.vlan_tag })
   end
   config.app(c, v4_sink, basic_apps.Sink)
   config.app(c, v6_sink, basic_apps.Sink)

   config.link(c, "capturev4.output -> repeaterv4.input")
   config.link(c, "capturev6.output -> repeaterv6.input")

   local v4_src, v6_src = 'repeaterv4.output', 'repeaterv6.output'
   if queue.external_interface.vlan_tag then
      config.link(c, v4_src.." -> untagv4.input")
      v4_src = "untagv4.output"
   end
   if queue.internal_interface.vlan_tag then
      config.link(c, v6_src.." -> untagv6.input")
      v6_src = "untagv6.output"
   end
   link_source(c, v4_src, v6_src)
   link_sink(c, v4_sink..'.input', v6_sink..'.input')
end

function load_check_on_a_stick (c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   local device, id, queue = parse_instance(conf)
   lwaftr_app(c, conf, device)

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)
   if queue.external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=queue.external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=queue.external_interface.vlan_tag })
   end
   if queue.internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=queue.internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=queue.internal_interface.vlan_tag })
   end

   config.app(c, 'v4v6', V4V6)
   config.app(c, 'splitter', V4V6)
   config.app(c, 'join', basic_apps.Join)

   local sources = { "v4v6.v4", "v4v6.v6" }
   local sinks = { "v4v6.v4", "v4v6.v6" }

   if queue.external_interface.vlan_tag then
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
   local device, id, queue = parse_instance(conf)
   lwaftr_app(c, conf, device)

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)
   if queue.external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=queue.external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=queue.external_interface.vlan_tag })
   end
   if queue.internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=queue.internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=queue.internal_interface.vlan_tag })
   end

   local sources = { "capturev4.output", "capturev6.output" }
   local sinks = { "output_filev4.input", "output_filev6.input" }

   if queue.external_interface.vlan_tag then
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
   local device, id, queue = parse_instance(conf)
   lwaftr_app(c, conf, device)

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "loop_v4", basic_apps.Repeater)
   config.app(c, "loop_v6", basic_apps.Repeater)
   config.app(c, "sink", basic_apps.Sink)
   if queue.external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=queue.external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=queue.external_interface.vlan_tag })
   end
   if queue.internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=queue.internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=queue.internal_interface.vlan_tag })
   end

   local sources = { "loop_v4.output", "loop_v6.output" }
   local sinks = { "sink.v4", "sink.v6" }

   config.link(c, "capturev4.output -> loop_v4.input")
   config.link(c, "capturev6.output -> loop_v6.input")

   if queue.external_interface.vlan_tag then
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
   local device, id, queue = parse_instance(conf)
   lwaftr_app(c, conf, device)

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "loop_v4", basic_apps.Repeater)
   config.app(c, "loop_v6", basic_apps.Repeater)
   config.app(c, "sink", basic_apps.Sink)
   if queue.external_interface.vlan_tag then
      config.app(c, "untagv4", vlan.Untagger,
                 { tag=queue.external_interface.vlan_tag })
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=queue.external_interface.vlan_tag })
   end
   if queue.internal_interface.vlan_tag then
      config.app(c, "untagv6", vlan.Untagger,
                 { tag=queue.internal_interface.vlan_tag })
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=queue.internal_interface.vlan_tag })
   end

   config.app(c, 'v4v6', V4V6)
   config.app(c, 'splitter', V4V6)
   config.app(c, 'join', basic_apps.Join)

   local sources = { "v4v6.v4", "v4v6.v6" }
   local sinks = { "v4v6.v4", "v4v6.v6" }

   config.link(c, "capturev4.output -> loop_v4.input")
   config.link(c, "capturev6.output -> loop_v6.input")

   if queue.external_interface.vlan_tag then
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
   pci_addrs = { default={} },
   real_time = { default=false },
   ingress_drop_monitor = { default='flush' },
   j = {}
}
function apply_scheduling(opts)
   local lib = require("core.lib")
   local ingress_drop_monitor = require("lib.timers.ingress_drop_monitor")
   local fatal = lwutil.fatal

   opts = lib.parse(opts, apply_scheduling_opts)
   if opts.ingress_drop_monitor then
      local mon = ingress_drop_monitor.new({action=opts.ingress_drop_monitor})
      timer.activate(mon:timer())
   end
   if opts.real_time then
      if not S.sched_setscheduler(0, "fifo", 1) then
         fatal('Failed to enable real-time scheduling.  Try running as root.')
      end
   end
   if opts.j then
      local arg = opts.j
      if arg:match("^v") then
         local file = arg:match("^v=(.*)")
         if file == '' then file = nil end
         require("jit.v").start(file)
      elseif arg:match("^p") then
         local opts, file = arg:match("^p=([^,]*),?(.*)")
         if file == '' then file = nil end
         local prof = require('jit.p')
         prof.start(opts, file)
         local function report() prof.stop(); prof.start(opts, file) end
         timer.activate(timer.new('p', report, 10e9, 'repeating'))
      elseif arg:match("^dump") then
         local opts, file = arg:match("^dump=([^,]*),?(.*)")
         if file == '' then file = nil end
         require("jit.dump").on(opts, file)
      elseif arg:match("^tprof") then
         local prof = require('lib.traceprof.traceprof')
         prof.start()
         local function report() prof.stop(); prof.start() end
         timer.activate(timer.new('tprof', report, 10e9, 'repeating'))
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

-- Takes a function (which takes a follower PID) and starts sampling
--
-- The function searches for followers of the leader and when a new one
-- appears it calls the sampling function (passed in) with the follower
-- PID to begin the sampling. The sampling function should look like:
--    function(pid, write_header)
-- If write_header is false it should not write a new header.
function start_sampling(sample_fn)
   local header_written = false
   local followers = {}
   local function find_followers()
      local ret = {}
      local mypid = S.getpid()
      for _, name in ipairs(shm.children("/")) do
         local pid = tonumber(name)
         if pid ~= nil and shm.exists("/"..pid.."/group") then
            local path = S.readlink(shm.root.."/"..pid.."/group")
            local parent = tonumber(lib.basename(lib.dirname(path)))
            if parent == mypid then
               ret[pid] = true
            end
         end
      end
      return ret
   end

   local function sample_for_new_followers()
      local new_followers = find_followers()
      for pid, _ in pairs(new_followers) do
         if followers[pid] == nil then
            if not pcall(sample_fn, pid, (not header_written)) then
               new_followers[pid] = nil
               io.stderr:write("Waiting on follower "..pid..
                  " to start ".."before recording statistics...\n")
            else
               header_written = true
            end
         end
      end
      followers = new_followers
   end
   timer.activate(timer.new('start_sampling', sample_for_new_followers,
      1e9, 'repeating'))
end

-- Produces configuration for each worker.  Each queue on each device
-- will get its own worker process.
local function compute_worker_configs(conf)
   local ret = {}
   local copier = binary.config_copier_for_schema_by_name('snabb-softwire-v2')
   local make_copy = copier(conf)
   for device, queues in pairs(conf.softwire_config.instance) do
      for id, _ in cltable.pairs(queues.queue) do
         local worker_config = make_copy()
         local instance = worker_config.softwire_config.instance
         for other_device, queues in pairs(conf.softwire_config.instance) do
            if other_device ~= device then
               instance[other_device] = nil
            else
               for other_id, _ in cltable.pairs(queues.queue) do
                  if other_id ~= id then
                     instance[device].queue[other_id] = nil
                  end
               end
            end
         end
         local worker_id = string.format('%s/%s', device, id)
         ret[worker_id] = worker_config
      end
   end
   return ret
end

function reconfigurable(scheduling, f, graph, conf)
   -- Always enabled in reconfigurable mode.
   alarm_notification = true

   local function setup_fn(conf)
      local worker_app_graphs = {}
      for worker_id, worker_config in pairs(compute_worker_configs(conf)) do
         local app_graph = config.new()
         f(app_graph, worker_config)
         worker_app_graphs[worker_id] = app_graph
      end
      return worker_app_graphs
   end

   local worker_code = "require('program.lwaftr.setup').run_worker(%s)"
   worker_code = worker_code:format(stringify(scheduling))

   config.app(graph, 'leader', leader.Leader,
              { setup_fn = setup_fn, initial_configuration = conf,
                worker_start_code = worker_code,
                schema_name = 'snabb-softwire-v2'})
end

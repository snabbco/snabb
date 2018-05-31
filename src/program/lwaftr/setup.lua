module(..., package.seeall)

local config     = require("core.config")
local manager    = require("lib.ptree.ptree")
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
local cltable    = require("lib.cltable")
local ipv4       = require("lib.protocol.ipv4")
local ethernet   = require("lib.protocol.ethernet")
local ipv4_ntop  = require("lib.yang.util").ipv4_ntop
local binary     = require("lib.yang.binary")
local S          = require("syscall")
local engine     = require("core.app")
local lib        = require("core.lib")
local shm        = require("core.shm")
local yang       = require("lib.yang.yang")
local alarms     = require("lib.yang.alarms")

local alarm_notification = false

local capabilities = {
   ['ietf-softwire-br']={feature={'binding'}},
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

-- Checks the existence of PCI devices.
local function validate_pci_devices(devices)
   for _, address in pairs(devices) do
      assert(lwutil.nic_exists(address),
             ("Could not locate PCI device '%s'"):format(address))
   end
end

function lwaftr_app(c, conf)
   assert(type(conf) == 'table')

   local function append(t, elem) table.insert(t, elem) end
   local function prepend(t, elem) table.insert(t, 1, elem) end

   local device, id, queue = lwutil.parse_instance(conf)

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
                shared_next_mac_key = "group/"..device.."-ipv6-next-mac",
                next_ip = iinternal_interface.next_hop.ip,
                alarm_notification = conf.alarm_notification })
   config.app(c, "arp", arp.ARP,
              { self_ip = convert_ipv4(iexternal_interface.ip),
                self_mac = iexternal_interface.mac,
                next_mac = iexternal_interface.next_hop.mac,
                shared_next_mac_key = "group/"..device.."-ipv4-next-mac",
                next_ip = convert_ipv4(iexternal_interface.next_hop.ip),
                alarm_notification = conf.alarm_notification })

   if conf.alarm_notification then
      local lwaftr = require('program.lwaftr.alarms')
      alarms.default_alarms(lwaftr.alarms)
   end

   local preprocessing_apps_v4  = { "reassemblerv4" }
   local preprocessing_apps_v6  = { "reassemblerv6" }
   local postprocessing_apps_v4  = { "fragmenterv4" }
   local postprocessing_apps_v6  = { "fragmenterv6" }

   if gexternal_interface.ingress_filter then
      config.app(c, "ingress_filterv4", PcapFilter,
                 { filter = gexternal_interface.ingress_filter,
                   alarm_type_qualifier='ingress-v4'})
      append(preprocessing_apps_v4, "ingress_filterv4")
   end
   if ginternal_interface.ingress_filter then
      config.app(c, "ingress_filterv6", PcapFilter,
                 { filter = ginternal_interface.ingress_filter,
                   alarm_type_qualifier='ingress-v6'})
      append(preprocessing_apps_v6, "ingress_filterv6")
   end
   if gexternal_interface.egress_filter then
      config.app(c, "egress_filterv4", PcapFilter,
                 { filter = gexternal_interface.egress_filter,
                   alarm_type_qualifier='egress-v4'})
      prepend(postprocessing_apps_v4, "egress_filterv4")
   end
   if ginternal_interface.egress_filter then
      config.app(c, "egress_filterv6", PcapFilter,
                 { filter = ginternal_interface.egress_filter,
                   alarm_type_qualifier='egress-v6'})
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

function load_kernel_iface (c, conf, v4_nic_name, v6_nic_name)
   local RawSocket = require("apps.socket.raw").RawSocket
   local v4_iface, id, queue = lwutil.parse_instance(conf)
   local v6_iface = queue.external_interface.dev_info
   local dev_info = {rx = "rx", tx = "tx"}

   lwaftr_app(c, conf, v6_iface)

   config.app(c, v4_nic_name, RawSocket, v4_iface)
   config.app(c, v6_nic_name, RawSocket, v6_iface)

   link_source(c, v4_nic_name..'.'..dev_info.tx, v6_nic_name..'.'..dev_info.tx)
   link_sink(c,   v4_nic_name..'.'..dev_info.rx, v6_nic_name..'.'..dev_info.rx)
end

function load_phy(c, conf, v4_nic_name, v6_nic_name, ring_buffer_size)
   local v4_pci, id, queue = lwutil.parse_instance(conf)
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
      poolnum=0,
      vlan=queue.external_interface.vlan_tag,
      rxcounter=1,
      ring_buffer_size=ring_buffer_size,
      macaddr=ethernet:ntop(queue.external_interface.mac)})
   config.app(c, v6_nic_name, require(v6_info.driver).driver, {
      pciaddr=v6_pci,
      vmdq=true, -- Needed to enable MAC filtering/stamping.
      rxq=id,
      txq=id,
      poolnum=0,
      vlan=queue.internal_interface.vlan_tag,
      rxcounter=1,
      ring_buffer_size=ring_buffer_size,
      macaddr = ethernet:ntop(queue.internal_interface.mac)})

   link_source(c, v4_nic_name..'.'..v4_info.tx, v6_nic_name..'.'..v6_info.tx)
   link_sink(c,   v4_nic_name..'.'..v4_info.rx, v6_nic_name..'.'..v6_info.rx)
end

function load_on_a_stick_kernel_iface (c, conf, args)
   local RawSocket = require("apps.socket.raw").RawSocket
   local iface, id, queue = lwutil.parse_instance(conf)
   local device = {tx = 'tx', rx = 'rx'}

   lwaftr_app(c, conf, iface)

   local v4_nic_name, v6_nic_name = args.v4_nic_name, args.v6_nic_name
   local v4v6, mirror = args.v4v6, args.mirror

   if v4v6 then
      assert(queue.external_interface.vlan_tag == queue.internal_interface.vlan_tag)
      config.app(c, 'nic', RawSocket, iface)
      if mirror then
         local Tap = require("apps.tap.tap").Tap
         config.app(c, 'mirror', Tap, {name=mirror})
         config.app(c, v4v6, V4V6, {mirror=true})
         config.link(c, v4v6..'.mirror -> mirror.input')
      else
         config.app(c, v4v6, V4V6)
      end
      config.link(c, 'nic.'..device.tx..' -> '..v4v6..'.input')
      config.link(c, v4v6..'.output -> nic.'..device.rx)

      link_source(c, v4v6..'.v4', v4v6..'.v6')
      link_sink(c, v4v6..'.v4', v4v6..'.v6')
   else
      config.app(c, v4_nic_name, RawSocket, iface)
      config.app(c, v6_nic_name, RawSocket, iface)

      link_source(c, v4_nic_name..'.'..device.tx, v6_nic_name..'.'..device.tx)
      link_sink(c,   v4_nic_name..'.'..device.rx, v6_nic_name..'.'..device.rx)
   end
end

function load_on_a_stick(c, conf, args)
   local pciaddr, id, queue = lwutil.parse_instance(conf)
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
         poolnum=0,
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
         poolnum=0,
         vlan=queue.external_interface.vlan_tag,
         ring_buffer_size=args.ring_buffer_size,
         macaddr = ethernet:ntop(queue.external_interface.mac)})
      config.app(c, v6_nic_name, driver, {
         pciaddr = pciaddr,
         vmdq=true, -- Needed to enable MAC filtering/stamping.
         rxq=id,
         txq=id,
         poolnum=1,
         vlan=queue.internal_interface.vlan_tag,
         ring_buffer_size=args.ring_buffer_size,
         macaddr = ethernet:ntop(queue.internal_interface.mac)})

      link_source(c, v4_nic_name..'.'..device.tx, v6_nic_name..'.'..device.tx)
      link_sink(c,   v4_nic_name..'.'..device.rx, v6_nic_name..'.'..device.rx)
   end
end

function load_virt(c, conf, v4_nic_name, v6_nic_name)
   local v4_pci, id, queue = lwutil.parse_instance(conf)
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
   local device, id, queue = lwutil.parse_instance(conf)
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
   local device, id, queue = lwutil.parse_instance(conf)
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
   local device, id, queue = lwutil.parse_instance(conf)
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
   local device, id, queue = lwutil.parse_instance(conf)
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
   local device, id, queue = lwutil.parse_instance(conf)
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

-- Produces configuration for each worker.  Each queue on each device
-- will get its own worker process.
local function compute_worker_configs(conf)
   local ret = {}
   local copier = binary.config_copier_for_schema_by_name('snabb-softwire-v2')
   local make_copy = copier(conf)
   for device, queues in pairs(conf.softwire_config.instance) do
      for k, _ in cltable.pairs(queues.queue) do
         local worker_id = string.format('%s/%s', device, k.id)
         local worker_config = make_copy()
         local instance = worker_config.softwire_config.instance
         for other_device, queues in pairs(conf.softwire_config.instance) do
            if other_device ~= device then
               instance[other_device] = nil
            else
               for other_k, _ in cltable.pairs(queues.queue) do
                  if other_k.id ~= k.id then
                     instance[device].queue[other_k] = nil
                  end
               end
            end
         end
         ret[worker_id] = worker_config
      end
   end
   return ret
end

function ptree_manager(f, conf, manager_opts)
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

   local function setup_fn(conf)
      switch_names(conf)
      local worker_app_graphs = {}
      for worker_id, worker_config in pairs(compute_worker_configs(conf)) do
         local app_graph = config.new()
         worker_config.alarm_notification = true
         f(app_graph, worker_config)
         worker_app_graphs[worker_id] = app_graph
      end
      return worker_app_graphs
   end

   local initargs = {
      setup_fn = setup_fn,
      initial_configuration = conf,
      schema_name = 'snabb-softwire-v2',
      default_schema = 'ietf-softwire-br',
      -- log_level="DEBUG"
   }
   for k, v in pairs(manager_opts or {}) do
      assert(not initargs[k])
      initargs[k] = v
   end

   return manager.new_manager(initargs)
end

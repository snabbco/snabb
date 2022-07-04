module(..., package.seeall)

local PcapFilter = require("apps.packet_filter.pcap_filter").PcapFilter
local V4V6 = require("apps.lwaftr.V4V6").V4V6
local VhostUser = require("apps.vhost.vhost_user").VhostUser
local basic_apps = require("apps.basic.basic_apps")
local bt = require("apps.lwaftr.binding_table")
local config = require("core.config")
local ethernet = require("lib.protocol.ethernet")
local ipv4_echo = require("apps.ipv4.echo")
local ipv4_fragment = require("apps.ipv4.fragment")
local ipv4_reassemble = require("apps.ipv4.reassemble")
local ipv6_echo = require("apps.ipv6.echo")
local ipv6_fragment = require("apps.ipv6.fragment")
local ipv6_reassemble = require("apps.ipv6.reassemble")
local lib = require("core.lib")
local lwaftr = require("apps.lwaftr.lwaftr")
local lwutil = require("apps.lwaftr.lwutil")
local constants = require("apps.lwaftr.constants")
local nh_fwd = require("apps.lwaftr.nh_fwd")
local pci = require("lib.hardware.pci")
local raw = require("apps.socket.raw")
local tap = require("apps.tap.tap")
local pcap = require("apps.pcap.pcap")
local yang = require("lib.yang.yang")

local fatal, file_exists = lwutil.fatal, lwutil.file_exists
local dir_exists, nic_exists = lwutil.dir_exists, lwutil.nic_exists
local yesno = lib.yesno

local function net_exists (pci_addr)
   local devices="/sys/class/net"
   return dir_exists(("%s/%s"):format(devices, pci_addr))
end

local function subset (keys, conf)
   local ret = {}
   for k,_ in pairs(keys) do ret[k] = conf[k] end
   return ret
end

local function load_driver (pciaddr)
   local device_info = pci.device_info(pciaddr)
   return require(device_info.driver).driver, device_info.rx, device_info.tx
end

local function load_virt (c, nic_id, lwconf, interface)
   -- Validate the lwaftr and split the interfaces into global and instance.
   local device, id, queue = lwutil.parse_instance(lwconf)

   local gexternal_interface = lwconf.softwire_config.external_interface
   local ginternal_interface = lwconf.softwire_config.internal_interface
   local iexternal_interface = queue.external_interface
   local iinternal_interface = queue.internal_interface

   assert(type(interface) == 'table')
   assert(nic_exists(interface.pci), "Couldn't find NIC: "..interface.pci)
   local driver, rx, tx = assert(load_driver(interface.pci))

   print("Different VLAN tags: load two virtual interfaces")
   print(("%s ether %s"):format(nic_id, interface.mac_address))

   local v4_nic_name, v6_nic_name = nic_id..'_v4', nic_id..'v6'
   local v4_mtu = external_interface.mtu + constants.ethernet_header_size
   if iexternal_interface.vlan_tag then
     v4_mtu = v4_mtu + 4
   end
   print(("Setting %s interface MTU to %d"):format(v4_nic_name, v4_mtu))
   config.app(c, v4_nic_name, driver, {
      pciaddr = interface.pci,
      vmdq = true, -- Needed to enable MAC filtering/stamping.
      vlan = interface.vlan and interface.vlan.v4_vlan_tag,
      macaddr = ethernet:ntop(iexternal_interface.mac),
      ring_buffer_size = interface.ring_buffer_size,
      mtu = v4_mtu })
   local v6_mtu = ginternal_interface.mtu + constants.ethernet_header_size
   if iinternal_interface.vlan_tag then
     v6_mtu = v6_mtu + 4
   end
   print(("Setting %s interface MTU to %d"):format(v6_nic_name, v6_mtu))
   config.app(c, v6_nic_name, driver, {
      pciaddr = interface.pci,
      vmdq = true, -- Needed to enable MAC filtering/stamping.
      vlan = interface.vlan and interface.vlan.v6_vlan_tag,
      macaddr = ethernet:ntop(iinternal_interface.mac),
      ring_buffer_size = interface.ring_buffer_size,
      mtu = v6_mtu})

   local v4_in, v4_out = v4_nic_name.."."..rx, v4_nic_name.."."..tx
   local v6_in, v6_out = v6_nic_name.."."..rx, v6_nic_name.."."..tx
   return v4_in, v4_out, v6_in, v6_out
end

local function load_phy (c, nic_id, interface)
   assert(type(interface) == 'table')
   local vlan = interface.vlan and tonumber(interface.vlan)
   local chain_input, chain_output

   if nic_exists(interface.pci) then
      local driver, rx, tx = load_driver(interface.pci)
      vlan = interface.vlan and tonumber(interface.vlan)
      print(("%s network ether %s mtu %d"):format(nic_id, interface.mac_address, interface.mtu))
      if vlan then
         print(("%s vlan %d"):format(nic_id, vlan))
      end
      config.app(c, nic_id, driver, {
         pciaddr = interface.pci,
         vmdq = true, -- Needed to enable MAC filtering/stamping.
         vlan = vlan,
         macaddr = interface.mac_address,
         ring_buffer_size = interface.ring_buffer_size,
         mtu = interface.mtu})
      chain_input, chain_output = nic_id.."."..rx, nic_id.."."..tx
   elseif net_exists(interface.pci) then
      print(("%s network interface %s mtu %d"):format(nic_id, interface.pci, interface.mtu))
      if vlan then
         print(("WARNING: VLAN not supported over %s. %s vlan %d"):format(interface.pci, nic_id, vlan))
      end
      config.app(c, nic_id, raw.RawSocket, interface.pci)
      chain_input, chain_output = nic_id .. ".rx", nic_id .. ".tx"
   else
      print(("Couldn't find device info for PCI address '%s'"):format(interface.pci))
      if not interface.mirror_id then
         fatal("Neither PCI nor tap interface given")
      end
      print(("Using tap interface '%s' instead"):format(interface.mirror_id))
      config.app(c, nic_id, tap.Tap, interface.mirror_id)
      print(("Running VM via tap interface '%s'"):format(interface.mirror_id))
      interface.mirror_id = nil   -- Hack to avoid opening again as mirror port.
      print(("SUCCESS %s"):format(chain_input))
      chain_input, chain_output = nic_id .. ".input", nic_id .. ".output"
   end
   return chain_input, chain_output
end

local function requires_splitter (internal_interface, external_interface)
   if not internal_interface.vlan_tag then return true end
   return internal_interface.vlan_tag == external_interface.vlan_tag
end

function lwaftr_app(c, conf, lwconf, sock_path)
   assert(type(conf) == 'table')
   assert(type(lwconf) == 'table')

   -- Validate the lwaftr and split the interfaces into global and instance.
   local device, id, queue = lwutil.parse_instance(lwconf)

   local gexternal_interface = lwconf.softwire_config.external_interface
   local ginternal_interface = lwconf.softwire_config.internal_interface
   local iexternal_interface = queue.external_interface
   local iinternal_interface = queue.internal_interface

   local external_interface = lwconf.softwire_config.external_interface
   local internal_interface = lwconf.softwire_config.internal_interface

   print(("Hairpinning: %s"):format(yesno(ginternal_interface.hairpinning)))
   local virt_id = "vm_" .. conf.interface.id
   local phy_id = "nic_" .. conf.interface.id

   local chain_input, chain_output
   local v4_input, v4_output, v6_input, v6_output

   local use_splitter = requires_splitter(iinternal_interface, iexternal_interface)
   if not use_splitter then
      v4_input, v4_output, v6_input, v6_output =
         load_virt(c, phy_id, lwconf, conf.interface)
   else
      chain_input, chain_output = load_phy(c, phy_id, conf.interface)
   end

   if conf.ipv4_interface or conf.ipv6_interface then
      if use_splitter then
         local mirror_id = conf.interface.mirror_id
         if mirror_id then
            print(("Mirror port %s found"):format(mirror_id))
            config.app(c, "Mirror", tap.Tap, mirror_id)
            config.app(c, "Sink", basic_apps.Sink)
            config.link(c, "nic_v4v6.mirror -> Mirror.input")
            config.link(c, "Mirror.output -> Sink.input")
         end
         config.app(c, "nic_v4v6", V4V6, { description = "nic_v4v6",
                                           mirror = mirror_id and true or false})
         config.link(c, chain_output .. " -> nic_v4v6.input")
         config.link(c, "nic_v4v6.output -> " .. chain_input)

         v4_output, v6_output = "nic_v4v6.v4", "nic_v4v6.v6"
         v4_input, v6_input   = "nic_v4v6.v4", "nic_v4v6.v6"
      end
   end

   if conf.ipv6_interface then
      conf.ipv6_interface.mac_address = conf.interface.mac_address
      print(("IPv6 fragmentation and reassembly: %s"):format(yesno(
             conf.ipv6_interface.fragmentation)))
      if conf.ipv6_interface.fragmentation then
         local mtu = conf.ipv6_interface.mtu or internal_interface.mtu
         config.app(c, "reassemblerv6", ipv6_reassemble.Reassembler, {
            max_concurrent_reassemblies =
               ginternal_interface.reassembly.max_packets,
            max_fragments_per_reassembly =
               ginternal_interface.reassembly.max_fragments_per_packet
         })
         config.app(c, "fragmenterv6", ipv6_fragment.Fragmenter, {
            mtu = mtu,
         })
         config.link(c, v6_output .. " -> reassemblerv6.input")
         config.link(c, "fragmenterv6.output -> " .. v6_input)
         v6_input, v6_output  = "fragmenterv6.input", "reassemblerv6.output"
      end
      if conf.ipv6_interface.ipv6_ingress_filter then
         local filter = conf.ipv6_interface.ipv6_ingress_filter
         print(("IPv6 ingress filter: '%s'"):format(filter))
         config.app(c, "ingress_filterv6", PcapFilter, { filter = filter })
         config.link(c, v6_output .. " -> ingress_filterv6.input")
         v6_output = "ingress_filterv6.output"
      end
      if conf.ipv6_interface.ipv6_egress_filter then
         local filter = conf.ipv6_interface.ipv6_egress_filter
         print(("IPv6 egress filter: '%s'"):format(filter))
         config.app(c, "egress_filterv6", PcapFilter, { filter = filter })
         config.link(c, "egress_filterv6.output -> " .. v6_input)
         v6_input = "egress_filterv6.input"
      end
   end

   if conf.ipv4_interface then
      conf.ipv4_interface.mac_address = conf.interface.mac_address
      print(("IPv4 fragmentation and reassembly: %s"):format(yesno(
             conf.ipv4_interface.fragmentation)))
      if conf.ipv4_interface.fragmentation then
         local mtu = conf.ipv4_interface.mtu or gexternal_interface.mtu
         config.app(c, "reassemblerv4", ipv4_reassemble.Reassembler, {
            max_concurrent_reassemblies =
               gexternal_interface.reassembly.max_packets,
            max_fragments_per_reassembly =
               gexternal_interface.reassembly.max_fragments_per_packet
         })
         config.app(c, "fragmenterv4", ipv4_fragment.Fragmenter, {
            mtu = mtu
         })
         config.link(c, v4_output .. " -> reassemblerv4.input")
         config.link(c, "fragmenterv4.output -> " .. v4_input)
         v4_input, v4_output  = "fragmenterv4.input", "reassemblerv4.output"
      end
      if conf.ipv4_interface.ipv4_ingress_filter then
         local filter = conf.ipv4_interface.ipv4_ingress_filter
         print(("IPv4 ingress filter: '%s'"):format(filter))
         config.app(c, "ingress_filterv4", PcapFilter, { filter = filter })
         config.link(c, v4_output .. " -> ingress_filterv4.input")
         v4_output = "ingress_filterv4.output"
      end
      if conf.ipv4_interface.ipv4_egress_filter then
         local filter = conf.ipv4_interface.ipv4_egress_filter
         print(("IPv4 egress filter: '%s'"):format(filter))
         config.app(c, "egress_filterv4", PcapFilter, { filter = filter })
         config.link(c, "egress_filterv4.output -> " .. v4_input)
         v4_input = "egress_filterv4.input"
      end
   end

   if conf.ipv4_interface and conf.ipv6_interface then
      print("lwAFTR service: enabled")
      config.app(c, "nh_fwd6", nh_fwd.nh_fwd6,
                 subset(nh_fwd.nh_fwd6.config, conf.ipv6_interface))
      config.link(c, v6_output .. " -> nh_fwd6.wire")
      config.link(c, "nh_fwd6.wire -> " .. v6_input)
      v6_input, v6_output = "nh_fwd6.vm", "nh_fwd6.vm"

      config.app(c, "nh_fwd4", nh_fwd.nh_fwd4,
                 subset(nh_fwd.nh_fwd4.config, conf.ipv4_interface))
      config.link(c, v4_output .. " -> nh_fwd4.wire")
      config.link(c, "nh_fwd4.wire -> " .. v4_input)
      v4_input, v4_output = "nh_fwd4.vm", "nh_fwd4.vm"

      config.app(c, "lwaftr", lwaftr.LwAftr, lwconf)
      config.link(c, "nh_fwd6.service -> lwaftr.v6")
      config.link(c, "lwaftr.v6 -> nh_fwd6.service")
      config.link(c, "nh_fwd4.service -> lwaftr.v4")
      config.link(c, "lwaftr.v4 -> nh_fwd4.service")

      -- Add a special hairpinning queue to the lwaftr app.
      config.link(c, "lwaftr.hairpin_out -> lwaftr.hairpin_in")
   else
      print("lwAFTR service: disabled (v6 or v4 interface config missing)")
   end

   if conf.ipv4_interface or conf.ipv6_interface then
      config.app(c, "vm_v4v6", V4V6, { description = "vm_v4v6",
                                       mirror = false })
      config.link(c, v6_output .. " -> vm_v4v6.v6")
      config.link(c, "vm_v4v6.v6 -> " .. v6_input)
      config.link(c, v4_output .. " -> vm_v4v6.v4")
      config.link(c, "vm_v4v6.v4 -> " .. v4_input)
      chain_input, chain_output = "vm_v4v6.input", "vm_v4v6.output"
   end

   if sock_path then
      local socket_path = sock_path:format(conf.interface.id)
      config.app(c, virt_id, VhostUser, { socket_path = socket_path })
      config.link(c, virt_id .. ".tx -> " .. chain_input)
      config.link(c, chain_output .. " -> " .. virt_id  .. ".rx")
   else
      config.app(c, "DummyVhost", basic_apps.Sink)
      config.link(c, "DummyVhost" .. ".tx -> " .. chain_input)
      config.link(c, chain_output .. " -> " .. "DummyVhost"  .. ".rx")
      print("Running without VM (no vHostUser sock_path set)")
   end
end

function passthrough(c, conf, sock_path)
   assert(type(conf) == 'table')

   io.write("lwAFTR service: disabled ")
   print("(either empty binding_table or v6 or v4 interface config missing)")

   local virt_id = "vm_" .. conf.interface.id
   local phy_id = "nic_" .. conf.interface.id
   local chain_input, chain_output = load_phy(c, phy_id, conf.interface)

   if sock_path then
      local socket_path = sock_path:format(conf.interface.id)
      config.app(c, virt_id, VhostUser, { socket_path = socket_path })
      config.link(c, virt_id .. ".tx -> " .. chain_input)
      config.link(c, chain_output .. " -> " .. virt_id  .. ".rx")
   else
      config.app(c, "DummyVhost", basic_apps.Sink)
      config.link(c, "DummyVhost" .. ".tx -> " .. chain_input)
      config.link(c, chain_output .. " -> " .. "DummyVhost"  .. ".rx")
      print("Running without VM (no vHostUser sock_path set)")
   end
end

function load_conf (conf_filename)
   local function load_lwaftr_config (conf, conf_filename)
      local filename = conf.lwaftr
      if not file_exists(filename) then
         filename = lib.dirname(conf_filename).."/"..filename
      end
      return yang.load_configuration(filename,
                                     {schema_name=lwaftr.LwAftr.yang_schema})
   end
   local conf = dofile(conf_filename)
   return conf, load_lwaftr_config(conf, conf_filename)
end

local function lwaftr_app_check (c, conf, lwconf, sources, sinks)
   assert(type(conf) == "table")
   assert(type(lwconf) == "table")
   local external_interface = lwconf.softwire_config.external_interface
   local internal_interface = lwconf.softwire_config.internal_interface

   local v4_src, v6_src = unpack(sources)
   local v4_sink, v6_sink = unpack(sinks)

   if conf.ipv6_interface then
      if conf.ipv6_interface.fragmentation then
         local mtu = conf.ipv6_interface.mtu or internal_interface.mtu
         config.app(c, "reassemblerv6", ipv6_reassemble.Reassembler, {
            max_concurrent_reassemblies =
               internal_interface.reassembly.max_packets,
            max_fragments_per_reassembly =
               internal_interface.reassembly.max_fragments_per_packet
         })
         config.app(c, "fragmenterv6", ipv6_fragment.Fragmenter, {
            mtu = mtu,
         })
         config.link(c, v6_src .. " -> reassemblerv6.input")
         config.link(c, "fragmenterv6.output -> " .. v6_sink)
         v6_src, v6_sink  = "reassemblerv6.output", "fragmenterv6.input"
      end
      if conf.ipv6_interface.ipv6_ingress_filter then
         local filter = conf.ipv6_interface.ipv6_ingress_filter
         config.app(c, "ingress_filterv6", PcapFilter, { filter = filter })
         config.link(c, v6_src .. " -> ingress_filterv6.input")
         v6_src = "ingress_filterv6.output"
      end
      if conf.ipv6_interface.ipv6_egress_filter then
         local filter = conf.ipv6_interface.ipv6_egress_filter
         config.app(c, "egress_filterv6", PcapFilter, { filter = filter })
         config.link(c, "egress_filterv6.output -> " .. v6_sink)
         v6_sink = "egress_filterv6.input"
      end
   end

   if conf.ipv4_interface then
      if conf.ipv4_interface.fragmentation then
         local mtu = conf.ipv4_interface.mtu or external_interface.mtu
         config.app(c, "reassemblerv4", ipv4_reassemble.Reassembler, {
            max_concurrent_reassemblies =
               external_interface.reassembly.max_packets,
            max_fragments_per_reassembly =
               external_interface.reassembly.max_fragments_per_packet
         })
         config.app(c, "fragmenterv4", ipv4_fragment.Fragmenter, {
            mtu = mtu
         })
         config.link(c, v4_src .. " -> reassemblerv4.input")
         config.link(c, "fragmenterv4.output -> " .. v4_sink)
         v4_src, v4_sink  = "reassemblerv4.output", "fragmenterv4.input"
      end
      if conf.ipv4_interface.ipv4_ingress_filter then
         local filter = conf.ipv4_interface.ipv4_ingress_filter
         config.app(c, "ingress_filterv4", PcapFilter, { filter = filter })
         config.link(c, v4_src .. " -> ingress_filterv4.input")
         v4_src = "ingress_filterv4.output"
      end
      if conf.ipv4_interface.ipv4_egress_filter then
         local filter = conf.ipv4_interface.ipv4_egress_filter
         config.app(c, "egress_filterv4", PcapFilter, { filter = filter })
         config.link(c, "egress_filterv4.output -> " .. v4_sink)
         v4_sink = "egress_filterv4.input"
      end
   end

   if conf.ipv4_interface and conf.ipv6_interface then
      config.app(c, "nh_fwd6", nh_fwd.nh_fwd6,
                 subset(nh_fwd.nh_fwd6.config, conf.ipv6_interface))
      config.link(c, v6_src.." -> nh_fwd6.wire")
      config.link(c, "nh_fwd6.wire -> "..v6_sink)

      config.app(c, "nh_fwd4", nh_fwd.nh_fwd4,
                 subset(nh_fwd.nh_fwd4.config, conf.ipv4_interface))
      config.link(c, v4_src.."-> nh_fwd4.wire")
      config.link(c, "nh_fwd4.wire -> "..v4_sink)

      config.app(c, "lwaftr", lwaftr.LwAftr, lwconf)
      config.link(c, "nh_fwd6.service -> lwaftr.v6")
      config.link(c, "lwaftr.v6 -> nh_fwd6.service")
      config.link(c, "nh_fwd4.service -> lwaftr.v4")
      config.link(c, "lwaftr.v4 -> nh_fwd4.service")

      -- Add a special hairpinning queue to the lwaftr app.
      config.link(c, "lwaftr.hairpin_out -> lwaftr.hairpin_in")

      config.app(c, "vm_v4v6", V4V6, { description = "vm_v4v6",
                                       mirror = false })
      config.app(c, "nh_fwd6_join", basic_apps.Join)
      config.link(c, "nh_fwd6.vm -> vm_v4v6.v6")
      config.link(c, "vm_v4v6.v6 -> nh_fwd6_join.vm1")
      config.link(c, "nh_fwd4.vm -> vm_v4v6.v4")
      config.link(c, "vm_v4v6.v4 -> nh_fwd6_join.vm2")
      config.link(c, "nh_fwd6_join.output -> nh_fwd6.vm")

      config.app(c, "DummyVhost", basic_apps.Sink)
      config.link(c, "DummyVhost.tx -> vm_v4v6.input")
      config.link(c, "vm_v4v6.output -> DummyVhost.rx")
   end
end

function load_check(c, conf_filename, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   local conf, lwconf = load_conf(conf_filename)

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)
   if conf.vlan_tagging then
      config.app(c, "untagv4", vlan.Untagger, { tag=conf.v4_vlan_tag })
      config.app(c, "untagv6", vlan.Untagger, { tag=conf.v6_vlan_tag })
      config.app(c, "tagv4", vlan.Tagger, { tag=conf.v4_vlan_tag })
      config.app(c, "tagv6", vlan.Tagger, { tag=conf.v6_vlan_tag })
   end

   local sources = { "capturev4.output", "capturev6.output" }
   local sinks = { "output_filev4.input", "output_filev6.input" }

   if conf.vlan_tagging then
      sources = { "untagv4.output", "untagv6.output" }
      sinks = { "tagv4.input", "tagv6.input" }

      config.link(c, "capturev4.output -> untagv4.input")
      config.link(c, "capturev6.output -> untagv6.input")
      config.link(c, "tagv4.output -> output_filev4.input")
      config.link(c, "tagv6.output -> output_filev6.input")
   end

   lwaftr_app_check(c, conf, lwconf, sources, sinks)
end

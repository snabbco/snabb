module(..., package.seeall)

local PcapFilter = require("apps.packet_filter.pcap_filter").PcapFilter
local S = require("syscall")
local V4V6 = require("apps.lwaftr.V4V6").V4V6
local VhostUser = require("apps.vhost.vhost_user").VhostUser
local basic_apps = require("apps.basic.basic_apps")
local bt = require("apps.lwaftr.binding_table")
local config = require("core.config")
local ipv4_apps = require("apps.lwaftr.ipv4_apps")
local ipv6_apps = require("apps.lwaftr.ipv6_apps")
local lib = require("core.lib")
local lwaftr = require("apps.lwaftr.lwaftr")
local lwcounter = require("apps.lwaftr.lwcounter")
local nh_fwd = require("apps.nh_fwd.nh_fwd")
local pci = require("lib.hardware.pci")
local tap = require("apps.tap.tap")

local yesno = lib.yesno

-- TODO redundant function dir_exists also in lwaftr.lua
local function dir_exists (path)
   local stat = S.stat(path)
   return stat and stat.isdir
end

local function nic_exists (pci_addr)
   local devices="/sys/bus/pci/devices"
   return dir_exists(("%s/%s"):format(devices, pci_addr)) or
      dir_exists(("%s/0000:%s"):format(devices, pci_addr))
end

local function fatal (msg)
   print(msg)
   main.exit(1)
end

local function load_phy (c, nic_id, interface)
   assert(type(interface) == 'table')
   local vlan = interface.vlan and tonumber(interface.vlan)
   local chain_input, chain_output

   if nic_exists(interface.pci) then
      local device_info = pci.device_info(interface.pci)
      print(("%s ether %s"):format(nic_id, interface.mac_address))
      if vlan then
         print(("%s vlan %d"):format(nic_id, vlan))
      end
      local driver = require(device_info.driver).driver
      config.app(c, nic_id, driver, { pciaddr = interface.pci,
                                      vmdq = true,
                                      vlan = vlan,
                                      qprdc = {
                                         discard_check_timer = interface.discard_check_timer,
                                         discard_wait = interface.discard_wait,
                                         discard_threshold = interface.discard_threshold,
                                      },
                                      macaddr = interface.mac_address, mtu = interface.mtu })
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
      chain_input, chain_output = nic_id .. ".input", nic_id .. ".output"
      print(("SUCCESS %s"):format(chain_input))
   end
   return chain_input, chain_output
end

function lwaftr_app(c, conf, lwconf, sock_path)
   assert(type(conf) == 'table')
   assert(type(lwconf) == 'table')

   if lwconf.binding_table then
      conf.preloaded_binding_table = bt.load(lwconf.binding_table)
   end

   local virt_id = "vm_" .. conf.interface.id
   local phy_id = "nic_" .. conf.interface.id

   local chain_input, chain_output = load_phy(c, phy_id, conf.interface)
   local v4_input, v4_output, v6_input, v6_output

   print(("Hairpinning: %s"):format(yesno(lwconf.hairpinning)))
   local counters = lwcounter.init_counters()

   if conf.ipv4_interface or conf.ipv6_interface then
      local mirror = false
      local mirror_id = conf.interface.mirror_id
      if mirror_id then
         mirror = true
         config.app(c, "Mirror", tap.Tap, mirror_id)
         config.app(c, "Sink", basic_apps.Sink)
         config.link(c, "Mirror.output -> Sink.input")
         config.link(c, "nic_v4v6.mirror -> Mirror.input")
         print(("Mirror port %s found"):format(mirror_id))
      end
      config.app(c, "nic_v4v6", V4V6, { description = "nic_v4v6",
                                        mirror = mirror })
      config.link(c, chain_output .. " -> nic_v4v6.input")
      config.link(c, "nic_v4v6.output -> " .. chain_input)
      v4_output, v6_output = "nic_v4v6.v4", "nic_v4v6.v6"
      v4_input, v6_input   = "nic_v4v6.v4", "nic_v4v6.v6"
   end

   if conf.ipv6_interface then
      conf.ipv6_interface.mac_address = conf.interface.mac_address
      print(("IPv6 fragmentation and reassembly: %s"):format(yesno(
             conf.ipv6_interface.fragmentation)))
      if conf.ipv6_interface.fragmentation then
         local mtu = conf.ipv6_interface.mtu or lwconf.ipv6_mtu
         config.app(c, "reassemblerv6", ipv6_apps.ReassembleV6, {
            counters = counters,
            max_ipv6_reassembly_packets = lwconf.max_ipv6_reassembly_packets,
            max_fragments_per_reassembly_packet = lwconf.max_fragments_per_reassembly_packet,
         })
         config.app(c, "fragmenterv6", ipv6_apps.Fragmenter, {
            counters = counters,
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
         local mtu = conf.ipv4_interface.mtu or lwconf.ipv4_mtu
         config.app(c, "reassemblerv4", ipv4_apps.Reassembler, {
            counters = counters,
            max_ipv4_reassembly_packets = lwconf.max_ipv4_reassembly_packets,
            max_fragments_per_reassembly_packet = lwconf.max_fragments_per_reassembly_packet,
         })
         config.app(c, "fragmenterv4", ipv4_apps.Fragmenter, {
            counters = counters,
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

   if conf.ipv4_interface and conf.ipv6_interface and conf.preloaded_binding_table then
      print("lwAFTR service: enabled")
      config.app(c, "nh_fwd6", nh_fwd.nh_fwd6, conf.ipv6_interface)
      config.link(c, v6_output .. " -> nh_fwd6.wire")
      config.link(c, "nh_fwd6.wire -> " .. v6_input)
      v6_input, v6_output = "nh_fwd6.vm", "nh_fwd6.vm"

      config.app(c, "nh_fwd4", nh_fwd.nh_fwd4, conf.ipv4_interface)
      config.link(c, v4_output .. " -> nh_fwd4.wire")
      config.link(c, "nh_fwd4.wire -> " .. v4_input)
      v4_input, v4_output = "nh_fwd4.vm", "nh_fwd4.vm"

      lwconf.counters = counters
      config.app(c, "lwaftr", lwaftr.LwAftr, lwconf)
      config.link(c, "nh_fwd6.service -> lwaftr.v6")
      config.link(c, "lwaftr.v6 -> nh_fwd6.service")
      config.link(c, "nh_fwd4.service -> lwaftr.v4")
      config.link(c, "lwaftr.v4 -> nh_fwd4.service")
   else
      io.write("lwAFTR service: disabled ")
      print("(either empty binding_table or v6 or v4 interface config missing)")
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

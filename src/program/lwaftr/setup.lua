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
local ipv4       = require("lib.protocol.ipv4")
local ipv6       = require("lib.protocol.ipv6")
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
   ['ietf-softwire-br']={feature={'binding-mode'}},
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
   config.app(c, "lwaftr", lwaftr.LwAftr, lwutil.select_instance(conf))
   config.app(c, "fragmenterv4", ipv4_fragment.Fragmenter,
              { mtu=gexternal_interface.mtu })
   config.app(c, "fragmenterv6", ipv6_fragment.Fragmenter,
              { mtu=ginternal_interface.mtu })
   config.app(c, "ndp", ndp.NDP,
              { self_ip = iinternal_interface.ip,
                self_mac = iinternal_interface.mac,
                next_mac = iinternal_interface.next_hop.mac,
                shared_next_mac_key = ("group/%s-ipv6-next-mac-%d"):format(
                   device, iinternal_interface.vlan_tag or 0),
                next_ip = iinternal_interface.next_hop.ip,
                alarm_notification = conf.alarm_notification })
   config.app(c, "arp", arp.ARP,
              { self_ip = convert_ipv4(iexternal_interface.ip),
                self_mac = iexternal_interface.mac,
                next_mac = iexternal_interface.next_hop.mac,
                shared_next_mac_key = ("group/%s-ipv4-next-mac-%d"):format(
                   device, iexternal_interface.vlan_tag or 0),
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
   local v6_iface, id, queue = lwutil.parse_instance(conf)
   local v4_iface = conf.softwire_config.instance[v6_iface].external_device
   local dev_info = {rx = "rx", tx = "tx"}

   lwaftr_app(c, conf, v6_iface)

   config.app(c, v4_nic_name, RawSocket, v4_iface)
   config.app(c, v6_nic_name, RawSocket, v6_iface)

   link_source(c, v4_nic_name..'.'..dev_info.tx, v6_nic_name..'.'..dev_info.tx)
   link_sink(c,   v4_nic_name..'.'..dev_info.rx, v6_nic_name..'.'..dev_info.rx)
end

local intel_mp = require("apps.intel_mp.intel_mp")
local connectx = require("apps.mellanox.connectx")
local intel_avf = require("apps.intel_avf.intel_avf")

local function cmd(...)
   local cmd
   for _, part in ipairs({...}) do
      if not cmd then cmd = part
      else            cmd = cmd.." "..part end
   end
   print("shell:", cmd)
   local status = os.execute(cmd)
   assert(status == 0, ("Command failed with return code %d"):format(status))
end

function config_intel_mp(c, name, opt)
   config.app(c, name, intel_mp.driver, {
      pciaddr=opt.pci,
      vmdq=true, -- Needed to enable MAC filtering/stamping.
      rxq=opt.queue,
      txq=opt.queue,
      poolnum=0,
      macaddr=ethernet:ntop(opt.mac),
      vlan=opt.vlan,
      rxcounter=opt.queue,
      txcounter=opt.queue,
      ring_buffer_size=opt.ring_buffer_size
   })
   return name..'.input', name..'.output'
end

function config_connectx(c, name, opt, lwconfig)
   local function queue_id (opt, queue)
      return ("%s.%s.%s"):format(ethernet:ntop(opt.mac),
                                 opt.vlan or opt.vlan_tag,
                                 queue or opt.queue)
   end
   local device = lwutil.parse_instance(lwconfig)
   local queues = {}
   local queue_counters, queue_counters_max = 0, 24
   for id, queue in pairs(lwconfig.softwire_config.instance[device].queue) do
      queue_counters = queue_counters + 2
      queues[#queues+1] = {
         id = queue_id(queue.external_interface, id),
         mac = ethernet:ntop(queue.external_interface.mac),
         vlan = queue.external_interface.vlan_tag,
         enable_counters = queue_counters <= queue_counters_max
      }
      queues[#queues+1] = {
         id = queue_id(queue.internal_interface, id),
         mac = ethernet:ntop(queue.internal_interface.mac),
         vlan = queue.internal_interface.vlan_tag,
         enable_counters = queue_counters <= queue_counters_max
      }
   end
   if lwutil.is_lowest_queue(lwconfig) then
      config.app(c, "ConnectX_"..opt.pci:gsub("[%.:]", "_"), connectx.ConnectX, {
         pciaddress = opt.pci,
         queues = queues,
         sendq_size = 4096,
         recvq_size = 4096,
         fc_rx_enable = false,
         fc_tx_enable = false
      })
   end
   config.app(c, name, connectx.IO, {
      pciaddress = opt.pci,
      queue = queue_id(opt)
   })
   local input, output = name..'.input', name..'.output'
   if opt.vlan then
      config.app(c, name.."_tag", vlan.Tagger, { tag=opt.vlan })
      config.link(c, name.."_tag.output -> "..input)
      config.app(c, name.."_untag", vlan.Untagger, { tag=opt.vlan })
      config.link(c, output.." -> "..name.."_untag.input")
      input, output = name.."_tag.input", name.."_untag.output"
   end
   return input, output
end

function config_intel_avf(c, name, opt, lwconfig)
   local nqueues = lwutil.num_queues(lwconfig)
   if lwutil.is_lowest_queue(lwconfig) then
      local _, _, queue = lwutil.parse_instance(lwconfig)
      local v6_mcast = ipv6:solicited_node_mcast(queue.internal_interface.ip)
      local mac_mcast = ethernet:ipv6_mcast(v6_mcast)
      config.app(c, "IntelAVF_"..opt.pci:gsub("[%.:]", "_"), intel_avf.Intel_avf, {
         pciaddr = opt.pci,
         vlan = opt.vlan,
         nqueues = nqueues,
         macs = {mac_mcast}
      })
   end
   config.app(c, name, intel_avf.IO, {
      pciaddr = opt.pci,
      queue = opt.queue
   })
   return name..'.input', name..'.output'
end

function config_intel_avf_pf(c, name, opt, lwconfig)
   local path = "/sys/bus/pci/devices/"..pci.qualified(opt.pci)
   local ifname = lib.firstfile(path.."/net")
   assert(ifname and lib.can_write(path.."/sriov_numvfs"),
          "Unsupported device: "..opt.pci)
   local vf = 0    -- which vf should this interface be on?
   local numvf = 1 -- how many vfs do we need to create on the pf?
   local vfmac = {} -- MACs to assign to vfs
   local device, _, queue = lwutil.parse_instance(lwconfig)
   if lwutil.is_on_a_stick(lwconfig, device) then
      numvf = 2
      vfmac[0] = queue.external_interface.mac
      vfmac[1] = queue.internal_interface.mac
      if ethernet:ntop(opt.mac) == ethernet:ntop(queue.internal_interface.mac) then
         vf = 1
      end
   else
      vfmac[0] = opt.mac
   end
   if lwutil.is_lowest_queue(lwconfig) then
      print("Setting "..path.."/sriov_numvfs = "..numvf)
      assert(lib.writefile(path.."/sriov_numvfs", numvf),
             "Failed to allocate VFs.")
      cmd('ip link set up', 'dev', ifname)
      cmd('ip link set', ifname, 'vf', 0, 'mac', ethernet:ntop(vfmac[0]))
      cmd('ip link set', ifname, 'vf', 0, 'spoofchk off')
      pcall(cmd, 'ip link set', ifname, 'vf', 0, 'trust on')
      if numvf == 2 then
         cmd('ip link set', ifname, 'vf', 1, 'mac', ethernet:ntop(vfmac[1]))
         cmd('ip link set', ifname, 'vf', 1, 'spoofchk off')
         pcall(cmd, 'ip link set', ifname, 'vf', 1, 'trust on')
      end
   end
   local vfpci = lib.basename(lib.readlink(path.."/virtfn"..vf))
   local avf_opt = {
      pci = vfpci,
      queue = opt.queue,
      vlan = opt.vlan,
      ring_buffer_size = opt.ring_buffer_size
   }
   return config_intel_avf(c, name, avf_opt, lwconfig)
end

function config_nic(c, name, driver, opt, lwconfig)
   local config_fn = { [intel_mp.driver] = config_intel_mp,
                       [connectx.driver] = config_connectx,
                       [intel_avf.driver] = config_intel_avf,
                       ['maybe_avf?']     = config_intel_avf_pf}
   local f = assert(config_fn[(driver and require(driver).driver) or 'maybe_avf?'],
                    "Unsupported device: "..opt.pci)
   return f(c, name, opt, lwconfig)
end

function load_phy(c, conf, v4_nic_name, v6_nic_name, ring_buffer_size)
   local v6_pci, id, queue = lwutil.parse_instance(conf)
   local v4_pci = conf.softwire_config.instance[v6_pci].external_device
   local v4_info = pci.device_info(v4_pci)
   local v6_info = pci.device_info(v6_pci)
   validate_pci_devices({v4_pci, v6_pci})
   lwaftr_app(c, conf, v4_pci)

   local v4_nic_opt = {
      pci = v4_pci,
      queue = id,
      mac = queue.external_interface.mac,
      vlan = queue.external_interface.vlan_tag,
      ring_buffer_size = ring_buffer_size
   }
   local v4_input, v4_output =
      config_nic(c, v4_nic_name, v4_info.driver, v4_nic_opt, conf)
   
   local v6_nic_opt = {
      pci = v6_pci,
      queue = id,
      mac = queue.internal_interface.mac,
      vlan = queue.internal_interface.vlan_tag,
      ring_buffer_size = ring_buffer_size
   }
   local v6_input, v6_output =
      config_nic(c, v6_nic_name, v6_info.driver, v6_nic_opt, conf)

   link_source(c, v4_output, v6_output)
   link_sink(c,   v4_input, v6_input)
end

function load_xdp(c, conf, v4_nic_name, v6_nic_name, ring_buffer_size)
   local v6_device, id, queue = lwutil.parse_instance(conf)
   local v4_device = conf.softwire_config.instance[v6_device].external_device
   assert(lib.is_iface(v4_device), v4_nic_name..": "..v4_device.." is not a Linux interface")
   assert(lib.is_iface(v6_device), v6_nic_name..": "..v6_device.." is not a Linux interface")
   assert(not lwutil.is_on_a_stick(conf, v6_device),
          "--xdp does not support on-a-stick configuration")
          
   lwaftr_app(c, conf)

   config.app(c, v4_nic_name, require("apps.xdp.xdp").driver, {
      ifname=v4_device,
      queue=id})
   config.app(c, v6_nic_name, require("apps.xdp.xdp").driver, {
      ifname=v6_device,
      queue=id})

   local v4_src, v6_src = v4_nic_name..'.output', v6_nic_name..'.output'
   local v4_sink, v6_sink = v4_nic_name..'.input', v6_nic_name..'.input'

   -- Linux removes VLAN tag, but we have to tag outgoing packets
   if queue.external_interface.vlan_tag then
      config.app(c, "tagv4", vlan.Tagger,
                 { tag=queue.external_interface.vlan_tag })
      config.link(c, "tagv4.output -> "..v4_sink)
      v4_sink = "tagv4.input"
   end
   if queue.internal_interface.vlan_tag then
      config.app(c, "tagv6", vlan.Tagger,
                 { tag=queue.internal_interface.vlan_tag })
      config.link(c, "tagv6.output -> "..v6_sink)
      v6_sink = "tagv6.input"
   end

   link_source(c, v4_src, v6_src)
   link_sink(c, v4_sink, v6_sink)
end

function xdp_ifsetup(conf)
   for idevice, instance in pairs(conf.softwire_config.instance) do
      local edevice = instance.external_device
      local icfg, ecfg
      local nqueues = 0
      for _, queue in pairs(instance.queue) do
         nqueues = nqueues + 1
         if not icfg then icfg = queue.internal_interface
         else assert(lib.equal(icfg, queue.internal_interface)) end
         if not ecfg then ecfg = queue.external_interface
         else assert(lib.equal(ecfg, queue.external_interface)) end
      end
      for qid in pairs(instance.queue) do
         assert(qid < nqueues)
      end
      local function ifsetup(ifname, cfg, opts, ip_ntop)
         cmd('ip link set down', 'dev', ifname)
         cmd('ip address flush', 'dev', ifname)
         cmd('ip link set address', ethernet:ntop(cfg.mac), 'dev', ifname)
         cmd('ip link set arp off', 'dev', ifname)
         cmd('ip link set broadcast', "ff:ff:ff:ff:ff:ff", 'dev', ifname)
         cmd('ip link set multicast on', 'dev', ifname)
         cmd('ip link set mtu', opts.mtu, 'dev', ifname)
         cmd('ip address add', ip_ntop(cfg.ip),  'dev', ifname)
         cmd('ethtool --set-channels', ifname,  'combined', nqueues)
         cmd('ip link set up', 'dev', ifname)
      end
      print("Configuring internal interface for XDP...")
      ifsetup(idevice, icfg, conf.softwire_config.internal_interface,
              function (ip) return ipv6:ntop(ip) end)
      print("Configuring external interface for XDP...")
      ifsetup(edevice, ecfg, conf.softwire_config.external_interface,
              ipv4_ntop)
   end
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
   local driver = device.driver
   validate_pci_devices({pciaddr})
   lwaftr_app(c, conf, pciaddr)
   local v4_nic_name, v6_nic_name, v4v6, mirror = args.v4_nic_name,
      args.v6_nic_name, args.v4v6, args.mirror

   local ext = queue.external_interface
   local int = queue.internal_interface
   if ext.vlan_tag ~= int.vlan_tag then
      assert(ethernet:ntop(ext.mac) ~= ethernet:ntop(int.mac),
             "When using different VLAN tags, external and internal MAC "..
                "addresses must be different too")
   end

   if v4v6 then
      assert(queue.external_interface.vlan_tag == queue.internal_interface.vlan_tag)
      assert(ethernet:ntop(queue.external_interface.mac) ==
                ethernet:ntop(queue.internal_interface.mac))
      
      local v4v6_nic_opt = {
         pci = pciaddr,
         queue = id,
         mac = queue.external_interface.mac,
         vlan = queue.internal_interface.vlan_tag,
         ring_buffer_size = args.ring_buffer_size
      }
      local v4v6_input, v4v6_output =
         config_nic(c, 'nic', driver, v4v6_nic_opt, conf)

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
      config.link(c, v4v6_output..' -> '..v4v6..'.input')
      config.link(c, v4v6..'.output -> '..v4v6_input)

      link_source(c, v4v6..'.v4', v4v6..'.v6')
      link_sink(c, v4v6..'.v4', v4v6..'.v6')
   else
      local v4_nic_opt = {
         pci = pciaddr,
         queue = id,
         mac = queue.external_interface.mac,
         vlan = queue.external_interface.vlan_tag,
         ring_buffer_size = args.ring_buffer_size
      }
      local v4_input, v4_output =
         config_nic(c, v4_nic_name, driver, v4_nic_opt, conf)
      local v6_nic_opt = {
         pci = pciaddr,
         queue = id,
         mac = queue.internal_interface.mac,
         vlan = queue.internal_interface.vlan_tag,
         ring_buffer_size = args.ring_buffer_size
      }
      local v6_input, v6_output =
         config_nic(c, v6_nic_name, driver, v6_nic_opt, conf)

      link_source(c, v4_output, v6_output)
      link_sink(c,   v4_input, v6_input)
   end
end

function load_virt(c, conf, v4_nic_name, v6_nic_name)
   local v6_pci, id, queue = lwutil.parse_instance(conf)
   local v4_pci = conf.softwire_config.instance[v6_pci].external_device
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
   local copier = binary.config_copier_for_schema_by_name('snabb-softwire-v3')
   local make_copy = copier(conf)
   for device, queues in pairs(conf.softwire_config.instance) do
      for id, _ in pairs(queues.queue) do
         local worker_id = string.format('%s/%s', device, id)
         local worker_config = make_copy()
         local meta = {worker_config = {device=device, queue_id=id}}
         ret[worker_id] = setmetatable(worker_config, {__index=meta})
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
      schema_name = 'snabb-softwire-v3',
      default_schema = 'ietf-softwire-br',
      -- log_level="DEBUG"
   }
   for k, v in pairs(manager_opts or {}) do
      assert(not initargs[k])
      initargs[k] = v
   end

   return manager.new_manager(initargs)
end

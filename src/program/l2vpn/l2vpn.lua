-- This program provisions a complete endpoint for one or more L2 VPNs.
--
-- Each VPN provides essentially a multi-point L2 VPN over IPv6 or
-- IPv4, a.k.a. Virtual Private LAN Service (VPLS). A point-to-point
-- VPN, a.k.a. Virtual Private Wire Service (VPWS) is provided as a
-- degenerate case of a VPLS with exactly two endpoints (i.e. a single
-- pseudowire).  The general framework is described in RFC4664.
--
-- The configuration is split into two parts.  The first part defines
-- the interfaces which are available for uplinks and attachment
-- circuits as well as their L2 and L3 properties.
--
-- The second part defines the actual VPN endpoints which contain
-- references to the interfaces defined in the first part.
--
-- See the README.md for details about the configuration.
--
-- The module constructs a network of apps from such a specification
-- as follows.
--
-- For each interface, the corresponding driver is instantiated with
-- the given configuration.  In non-trunking mode and without a L3
-- configuration, initialization is finished and other apps can link
-- directly to the driver.  For a L3 interface, traffic is spearated
-- by address family and a neighbor discovery app and a
-- fragmentation/reassembly app for PMTUD are added for each
-- configured family.
--
-- If the interface is in trunking mode, an instance of the VlanMux
-- app from apps.vlan.vlan is instantiated and its "trunk" port is
-- connected to the interface.  For each sub-interface that contains a
-- L3 configuration, an instance of the nd_light app is attached to
-- the appropriate "vlan" link of the VlanMux app (for vlan = 0, the
-- corresponding VlanMux link is called "native").
--
-- Each pseudowire is uniquely identified by the triple (source
-- address, destination address, VC ID).  The multiplexing is handled
-- in three stages.  In the first stage, a "dispatcher" is connected
-- to the L3 interface and partitions the packets according to the
-- tuple (source address, destination address), leaving the packet
-- untouched.  In the second stage, the IP (v4 or v6) header is
-- removed and the packets are further partitioned according to the
-- "upper layer" protocol, i.e. the encapsulation.  In the third step,
-- the encapsulation header is removed and the packet is assigned to a
-- pseudowire endpoint based on an element specific to the
-- encapsulation mechanism (e.g. the "key" field of a GRE header).
-- This is also where the control channel is separated from the data
-- plane.
--
-- An instance of apps.bridge.learning or apps.bridge.flooding is
-- created for every VPLS, depending on the selected bridge type.  The
-- bridge connects all pseudowires and attachment circuits of the
-- VPLS.  The pseudowires are assigned to a split horizon group,
-- i.e. packets arriving on any of those links are only forwarded to
-- the attachment circuits and not to any of the other pseudowires
-- (this is a consequence of the full-mesh topology of the pseudowires
-- of a VPLS).  All attachment circuits defined for a VPLS must
-- reference a L2 interface or sub-interface.  In non-trunking mode,
-- the interface driver is connected directly to the bridge module.
-- In trunking mode, the corresponding "vlan" links of the VlanMux app
-- are connected to the bridge instead.
--
-- If a VPLS consists of a single PW and a single AC, the resulting
-- two-port bridge is optimized away by creating a direct link between
-- the two.  The VPLS thus turns into a VPWS.
module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local usage_msg = require("program.l2vpn.README_inc")
local lib = require("core.lib")
local yang = require("lib.yang.yang")
local ptree = require("lib.ptree.ptree")
local counter = require("core.counter")
local macaddress = require("lib.macaddress")
local shm = require("core.shm")
local const = require("syscall.linux.constants")
local S = require("syscall")
local app_graph = require("core.config")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local ipv4 = require("lib.protocol.ipv4")
local Tap = require("apps.tap.tap").Tap
local Tee = require("apps.basic.basic_apps").Tee
local PcapWriter = require("apps.pcap.pcap").PcapWriter
local Sink = require("apps.basic.basic_apps").Sink
local VlanMux = require("apps.vlan.vlan").VlanMux
local nd_light = require("apps.ipv6.nd_light").nd_light
local arp = require("apps.ipv4.arp").ARP
local af_mux = require("program.l2vpn.af_mux").af_mux
local ifmib = require("lib.ipc.shmem.iftable_mib")
local frag_ipv6 = require("apps.ipv6.fragment").Fragmenter
local reass_ipv6 = require("apps.ipv6.reassemble").Reassembler
local frag_ipv4 = require("apps.ipv4.fragment").Fragmenter
local reass_ipv4 = require("apps.ipv4.reassemble").Reassembler
local Receiver = require("apps.interlink.receiver").Receiver
local Transmitter = require("apps.interlink.transmitter").Transmitter
local l2vpn_lib = require("program.l2vpn.lib")

local tlen = l2vpn_lib.tlen
local singleton = l2vpn_lib.singleton

local initial_state
local worker_pid

local bridge_types = { flooding = true, learning = true }

function usage ()
   print(usage_msg)
   main.exit(0)
end

local Graph = {}
function Graph:new ()
   return setmetatable(
      {
         _apps = {},
         _links ={},
      }, { __index = Graph })
end

function Graph:apps ()
   return self._apps
end

function Graph:links ()
   return self._links
end

function Graph:add_app (app, name)
   assert(not self._apps[name], "Duplicate app "..name)
   self._apps[name] = app
end

function Graph:connect (from, to)
   assert(not from.connected_out)
   assert(not to.connected_in)
   from.connected_out = true
   to.connected_in = true
   table.insert(self._links, from.output()..' -> '..to.input())
end

function Graph:connect_duplex (from, to)
   self:connect(from, to)
   self:connect(to, from)
end

function Graph:app_graph ()
   local graph = app_graph.new()
   for name, app in pairs(self:apps()) do
      -- Copy arg to allow app reconfiguration
      app_graph.app(graph, app:name(), app:class(), lib.deepcopy(app:arg()))
   end
   for _, linkspec in ipairs(self:links()) do
      app_graph.link(graph, linkspec)
   end
   return graph
end

local App = {}
function App:new (graph, name, class, initial_arg)
   local self = setmetatable({}, { __index = App })
   self._name = name
   self._class = class
   self:arg(initial_arg)
   graph:add_app(self, name)
   return self
end

function App:name ()
   return self._name
end

function App:class ()
   return self._class
end

function App:arg (arg)
   if arg == nil then return self._arg end
   self._arg = arg
end

function socket (app_in, input, app_out, output)
   assert(input)
   local output = output or input
   return {
      input = function ()
         return app_in:name()..'.'..input
      end,
      output = function ()
         return app_out:name()..'.'..output
      end
   }
end

function App:socket (input, output)
   return socket(self, input, self, output)
end

local function normalize_name (name)
   return string.gsub(name, '[/%.]', '_')
end

-- Helper functions to abstract from driver-specific behaviour.  The
-- key into this table is the full path to the module used to create
-- the driver object. For each driver, the following functions must be
-- defined
--   link_names ()
--     Return the name of the links used for input and ouput
--   stats_path (driver)
--     This function is called after the driver has been created
--     and receives the driver object as input.  It returns the
--     path to the shm frame where the driver stores its stats counters.
--   config ()
--     return a table with driver-specific configuration
local driver_helpers = {
   ['apps.intel_mp.intel_mp.Intel'] = {
      link_names = function ()
         return 'input', 'output'
      end,
      stats_path = function (intf)
         return 'pci/'..intf.pci_address
      end,
      config = function ()
         return { use_alarms = false }
      end
   },
   ['apps.tap.tap.Tap'] = {
      link_names = function ()
         return 'input', 'output'
      end,
      stats_path = function (intf)
         return 'apps/'..intf.app:name()
      end,
      config = function () return {} end
   },
}

-- Mapping of address family identifiers to classes
af_classes = {
   ipv4 = ipv4,
   ipv6 = ipv6,
}

local function src_dst_pair (af, src, dst)
   local af = af_classes[af]
   local function maybe_convert(addr)
      if type(addr) == "string" then
         return assert(af:pton(addr))
      else
         return addr
      end
   end
   return string.format("%s%s", af:ntop(maybe_convert(src)),
                        af:ntop(maybe_convert(dst)))
end

-- The yang module converts IP addresses to their numeric
-- representation.  Revert to the printable representation.
local function ntop (afi, addr)
   assert(addr)
   if afi == "ipv4" then
      return require("lib.yang.util").ipv4_ntop(addr)
   else
      return ipv6:ntop(addr)
   end
end

function parse_intf(state, name, config)
   local data_plane = state.data_plane

   print("Setting up interface "..name)
   print("  Description: "..(config.description or "<none>"))
   local intf = {
      description = config.description,
      name = name,
      -- The normalized name is used in app and link names
      nname = normalize_name(name),
   }

   -- NIC driver
   -- YANG BUG: the peers container should be mandatory, because it
   -- contains mandatory items (lists with min-elements > 0).  Work
   -- around it with an explicit check.
   assert(config.driver, 'Missing mandatory container "driver"')
   local drv_c = config.driver
   local drv_config = l2vpn_lib.eval(drv_c.config, " in driver configuration")
   local driver_helper = assert(driver_helpers[drv_c.path.."."..drv_c.name],
                                "unsupported driver: "..drv_c.path.."."..drv_c.name)

   if type(drv_config) == "table" then
      if (drv_config.pciaddr) then
         print("  PCI address: "..drv_config.pciaddr)
	 intf.pci_address = drv_config.pciaddr
      end
      drv_config.mtu = config.mtu
      l2vpn_lib.merge(drv_config, driver_helper.config())
      if drv_c.extra_config then

         -- If present, extra_config must evaluate to a table, whose
         -- elements are merged with the regular config.  This feature
         -- allows for more flexibility when the configuration is
         -- created by a Lua-agnostic layer on top, e.g. by a NixOS
         -- module
         local extra_config = l2vpn_lib.eval(drv_c.extra_config,
                                             "in driver extra configuration")
         assert(type(extra_config) == "table",
                "Driver extra configuration must be a table")
         for k, v in pairs(extra_config) do
            drv_config[k] = v
         end
      end
   end
   intf.app = App:new(data_plane, 'intf_'..intf.nname,
                      require(drv_c.path)[drv_c.name], drv_config)
   assert(driver_helper,
          "Unsupported driver (missing driver helper)"
             ..drv_c.path.."."..drv_c.name)
   intf.driver_helper = driver_helper
   local intf_socket = intf.app:socket(driver_helper.link_names())
   intf.l2_socket = { input = intf_socket.input, output = intf_socket.output }

   -- L2 configuration
   print("  L2 configuration")
   print("    MTU: "..config.mtu)
   intf.mtu = config.mtu

   -- Port mirror configuration
   if config.mirror then
      local mirror = config.mirror
      local mtype = mirror.type
      for _, dir in ipairs({ 'rx', 'tx' }) do
         local mirror_socket
         if mirror[dir] then
            if mtype == "pcap" then
               local file
               if mirror.name then
                  file = mirror.name.."_"..dir
               else
                  file = '/tmp/'..string.gsub(intf.name, "/", "-")
                     .."_"..dir..".pcap"
               end
               local mirror = App:new(data_plane,
                                      'tap_'..intf.nname..'_pcap_'..dir,
                                      PcapWriter, file)
               mirror_socket = mirror:socket('input')
               print("    "..dir.." port-mirror on pcap file "..file)
            elseif mtype == "tap" then
               local tap_name
               if mirror.name then
                  tap_name = mirror.name.."_"..dir
               else
                  tap_name = string.gsub(intf.name, "/", "-")
                  tap_name = string.sub(tap_name, 0, const.IFNAMSIZ-3).."_"..dir
               end
               local mirror = App:new(data_plane, 'tap_'..intf.nname..'_'..dir,
                                      Tap, { name = tap_name, mtu = config.mtu})
               mirror_socket = mirror:socket('input', 'output')
               local sink = App:new(data_plane, 'sink_'..intf.nname..'_tap_'..dir,
                                    Sink)
               data_plane:connect(mirror_socket, sink:socket('input'))
               print("    "..dir.." port-mirror on tap interface "..tap_name)
            else
               error("Illegal mirror type: "..mtype)
            end
            local tee = App:new(data_plane, 'tee_'..intf.nname..'_'..dir, Tee)
            data_plane:connect(tee:socket('mirror'), mirror_socket)
            if dir == "rx" then
               data_plane:connect(intf_socket, tee:socket('input'))
               intf.l2_socket.output = tee:socket('pass').output
            else
               data_plane:connect(tee:socket('pass'), intf_socket)
               intf.l2_socket.input = tee:socket('input').input
            end
         end
      end
   end

   local function vid_suffix (vid)
      return (vid and "_"..vid) or ''
   end

   local afs_procs = {
      ipv6 = function (config, vid, socket_in, indent)
         -- YANG BUG: address and next_hop should be marked mandatory
         -- in the schema (also see comment in the schema)
         assert(config.address, "Missing address")
         assert(config.next_hop, "Missing next-hop")
         local address = ntop("ipv6", config.address)
         local next_hop = ntop("ipv6", config.next_hop)
         -- FIXME: check fo uniqueness of subnet
         print(indent.."    Address: "..address.."/64")
         print(indent.."    Next-Hop: "..next_hop)
         if config.next_hop_mac then
            print(indent.."    Next-Hop MAC address: "
                     ..config.next_hop_mac)
         end

         local nd = App:new(data_plane, 'nd_'..intf.nname..vid_suffix(vid),
                            nd_light,
                            { local_ip  = ipv6:pton(address),
                              local_mac = ethernet:pton("00:00:00:00:00:00"),
                              remote_mac = config.next_hop_mac,
                              next_hop = ipv6:pton(next_hop),
                              quiet = true })
         state.nds[nd:name()] = { app = nd, intf = intf }
         data_plane:connect_duplex(nd:socket('south'), socket_in)

         fragmenter = App:new(data_plane,
                              'frag_v6_'..intf.nname..vid_suffix(vid),
                              frag_ipv6,
                              { mtu = intf.mtu - 14, pmtud = true,
                                pmtu_local_addresses = {},
                                use_alarms = false })
         local reassembler = App:new(data_plane,
                                     'reass_v6_'..intf.nname..vid_suffix(vid),
                                     reass_ipv6,
                                     { use_alarms = false })
         local nd_north = nd:socket('north')
         data_plane:connect(nd_north, fragmenter:socket('south'))
         data_plane:connect(fragmenter:socket('output'), nd_north)
         data_plane:connect(fragmenter:socket('north'),
                 reassembler:socket('input'))
         return socket(fragmenter, 'input', reassembler, 'output'), fragmenter
      end,

      ipv4 = function (config, vid, socket_in, indent)
         -- YANG BUG: address and next_hop should be marked mandatory
         -- in the schema (also see comment in the schema)
         assert(config.address, "Missing address")
         assert(config.next_hop, "Missing next-hop")
         local address = ntop("ipv4", config.address)
         local next_hop = ntop("ipv4", config.next_hop)
         -- FIXME: check fo uniqueness of subnet
         print(indent.."    Address: "..address.."/24")
         print(indent.."    Next-Hop: "..next_hop)
         if config.next_hop_mac then
            print(indent.."    Next-Hop MAC address: "
                     ..config.next_hop_mac)
         end

         local arp = App:new(data_plane, 'arp_'..intf.nname..vid_suffix(vid),
                             arp,
                             { self_ip  = ipv4:pton(address),
                               self_mac = ethernet:pton("00:00:00:00:00:00"),
                               next_mac = config.next_hop_mac and
                                  ethernet:pton(config.next_hop_mac or nil),
                               next_ip = ipv4:pton(next_hop) })
         state.arps[arp:name()] = { app = arp, intf = intf }
         data_plane:connect_duplex(arp:socket('south'), socket_in)

         fragmenter = App:new(data_plane,
                              'frag_v4_'..intf.nname..vid_suffix(vid),
                              frag_ipv4,
                              { mtu = intf.mtu - 14, pmtud = true,
                                pmtu_local_addresses = {},
                                use_alarms = false })
         local reassembler = App:new(data_plane,
                                     'reass_v4_'..intf.nname..vid_suffix(vid),
                                     reass_ipv4,
                                     { use_alarms = false })
         local arp_north = arp:socket('north')
         data_plane:connect(arp_north, fragmenter:socket('south'))
         data_plane:connect(fragmenter:socket('output'), arp_north)
         data_plane:connect(fragmenter:socket('north'),
                 reassembler:socket('input'))
         return socket(fragmenter, 'input', reassembler, 'output'), fragmenter
      end
   }

   local function process_afs (af_configs, vid, socket, indent)
      print(indent.."  Address family configuration")
      local afs = {
         ipv4 = {
            name = 'IPv4',
            socket_in = socket,
            configured = false,
         },
         ipv6 = {
            name = 'IPv6',
            socket_in = socket,
            configured = false,
         }
      }

      if tlen(af_configs) > 1 then
         -- Add a demultiplexer for IPv4/IPv6
         local afd = App:new(data_plane, 'af_mux_'..intf.nname..vid_suffix(vid),
                             af_mux)
         data_plane:connect_duplex(afd:socket('south'), socket)
         for _, afi in ipairs({ 'ipv4', 'ipv6' }) do
            afs[afi].socket_in = afd:socket(afi)
         end
      end
      for afi, config in pairs(af_configs) do
         local af = afs[afi]
         assert(af, "Unsupported address family "..afi)
         print(indent.."    "..af.name)
         af.socket_out, af.fragmenter =
            afs_procs[afi](config, vid, af.socket_in, indent.."  ")
         af.configured = true
      end
      return afs
   end

   local trunk = config.trunk or { enable = false }
   assert(type(trunk) == "table", "Trunk configuration must be a table")
   if trunk.enable then
      -- The interface is configured as a VLAN trunk. Attach an
      -- instance of the VLAN multiplexer.
      print("    Trunking mode: enabled")
      intf.subintfs = {}
      assert(l2vpn_lib.nil_or_empty_p(config.address_families),
             "Address family configuration not allowed in trunking mode")
      local encap = trunk.encapsulation
      if encap == "raw" then
         encap = assert(trunk.tpid,
                        "tpid required for raw mode encapsulation")
      end
      print("      Encapsulation "..
               (type(encap) == "string" and encap
                   or string.format("ether-type 0x%04x", encap)))
      local vmux = App:new(data_plane, 'vmux_'..intf.nname, VlanMux,
                           { encapsulation = encap })
      data_plane:connect_duplex(vmux:socket('trunk'), intf.l2_socket)

      -- Process VLANs and create sub-interfaces
      print("  Sub-Interfaces")
      local sub_intf_id = 0
      -- YANG BUG: {min,max}-elements checks NYI
      assert(tlen(trunk.vlan) > 0,
             "At least one VLAN required")
      for vid, vlan in pairs(trunk.vlan) do
         assert(type(vid) == "number" and vid >= 0 and vid < 4095,
                "Invalid VLAN ID "..vid.." for sub-interface #"..sub_intf_id)
         sub_intf_id = sub_intf_id + 1
         local name = intf.name..'.'..vid
         assert(not intf.subintfs[name], "Duplicate VID: "..vid)

         local mtu = vlan.mtu or intf.mtu
         assert(mtu <= intf.mtu,
                string.format("MTU %d on sub-interface %s "
                                 .."exceeds MTU %d of physical interface",
                              mtu, name, intf.mtu))
         local subintf = {
            name = name,
            -- The normalized name is used in app and link names
            nname = normalize_name(name),
            description = vlan.description,
            vlan = true,
            phys_intf = intf,
            mtu = mtu,
         }
         intf.subintfs[name] = subintf
         print("    "..intf.name.."."..vid)
         print("      Description: "..(vlan.description or '<none>'))
         print("      L2 configuration")
         print("        VLAN ID: "..(vid > 0 and vid or "<untagged>"))
         print("        MTU: "..subintf.mtu)
         local socket = vmux:socket((vid == 0 and 'native') or 'vlan'..vid)
         if not l2vpn_lib.nil_or_empty_p(vlan.address_families) then
            subintf.l3 = process_afs(vlan.address_families, vid,
                                     socket, "    ")
         else
            subintf.l2_socket = socket
         end

         -- Store a copy of the vmux socket to find the proper shm
         -- frame for the interface counters later on
         subintf.vmux_socket = socket
      end
   else
      print("    Trunking mode: disabled")
      if not l2vpn_lib.nil_or_empty_p(config.address_families) then
         intf.l3 = process_afs(config.address_families, nil, intf.l2_socket, "")
      end
   end

   return intf
end

function parse_config (main_config)
   local state = {
      data_plane = Graph:new(),
      ctrl_plane = Graph:new(),
      intfs = {},
      nds = {},
      arps = {},
   }
   local intfs = state.intfs
   local data_plane, ctrl_plane = state.data_plane, state.ctrl_plane

   for name, config in pairs(main_config.interface) do
      local intf = parse_intf(state, name, config)
      assert(not intfs[intf.name], "Duplicate interface name: "..intf.name)
      intfs[intf.name] = intf
      for name, subintf in pairs(intf.subintfs or {}) do
         intfs[name] = subintf
      end
   end

   -- A pseudowire is uniquely identified by the triple (source,
   -- destination, vcid).  If a tunnel protocol does not support a VC
   -- ID, the vcid is set to 0 and the identifier is effectively the
   -- pair (source, destination). An integer called the sd_index is
   -- assigned to each (source, destination) pair to identify it
   -- uniquely.
   local transports = {}
   local dispatchers = { ipv4 = {}, ipv6 = {} }
   local function add_pw (transport, intf, uplink, vc_id, type, config)
      local afi = transport.afi
      local af = af_classes[afi]
      local local_addr = af:pton(transport.local_address)
      local remote_addr = af:pton(transport.remote_address)

      local dispatch = dispatchers[afi][uplink]
      if not dispatch then
         dispatch = App:new(data_plane,
                            'disp_'..normalize_name(uplink).."_"..afi,
                            require("program.l2vpn.dispatch").dispatch,
                            { afi = afi, links = {} })
         data_plane:connect_duplex(dispatch:socket('south'),
                                   intf.l3[afi].socket_out)
         dispatchers[afi][uplink] = dispatch
      end

      local tunnel_class = require("program.l2vpn.tunnels."..type).tunnel
      local tunnel_info = tunnel_class:info()
      assert(tunnel_info.afs[afi],
             "Tunnel type "..type.." not supported for "
                .."address family "..afi)
      if not tunnel_info.vc_id_max then
         assert(vc_id == 0, "VC ID must be 0 for tunnel type "..type)
      else
         assert(vc_id > 0 and vc_id <= tunnel_info.vc_id_max,
                "Invalid VC ID "..vc_id
                   .." (range 1.."..tunnel_info.vc_id_max..")")
      end

      assert(not transport.vc_ids[vc_id],
             ("Non-unique pseudowire: %s <-> %s VC ID %d"):
                format(af:ntop(remote_addr),
                       af:ntop(local_addr), vc_id))
      transport.vc_ids[vc_id] = type

      local ipsec = transport.ipsec
      if ipsec.enable then
         print("      IPsec: "..ipsec.encryption_algorithm)
      else
         print("      IPsec: disabled")
      end
      if not transport.protomux then
         local index = transport.index

         local socket = dispatch:socket('tp_'..index)
         if ipsec.enable then
            local esp_module = afi == "ipv4" and "Transport4_IKE" or
               "Transport6_IKE"
            local ipsec = App:new(data_plane, 'ipsec_'..afi.."_"..index,
                                  require("apps.ipsec.esp")[esp_module],
                                  {
                                     aead = ipsec.encryption_algorithm,
                                     auditing = true,
                                     local_address = transport.local_address,
                                     remote_address = transport.remote_address_nat or
                                        transport.remote_address })
            data_plane:connect_duplex(dispatch:socket('tp_'..index),
                                      ipsec:socket('encapsulated'))
            socket = ipsec:socket('decapsulated')
         end

         -- Each transport connects to a dedicated protocol
         -- multiplexer.
         local protomux = App:new(data_plane, 'pmux_'..index,
                                  require("program.l2vpn.transports."..afi).transport,
                                  { src = local_addr, dst = remote_addr, links = {} })
         dispatch:arg().links['tp_'..index] = { src = remote_addr,
                                                dst = local_addr }
         data_plane:connect_duplex(socket, protomux:socket('south'))
         transport.protomux = protomux
      end

      local tunnel = transport.tunnels[type]
      if not tunnel then
         tunnel = App:new(data_plane, type.."_"..transport.index,
                          tunnel_class,
                          { ancillary_data = {
                               remote_addr = af:ntop(remote_addr),
                               local_addr = af:ntop(local_addr) } })
         transport.tunnels[type] = tunnel
         transport.protomux:arg().links[type] = { proto = tunnel_info.proto }
         data_plane:connect_duplex(transport.protomux:socket(type),
                                   tunnel:socket('south'))
      end

      local vcs = {}
      for vc_id, _type in pairs(transport.vc_ids) do
         if _type == type then
            local vc_set = tunnel_info.mk_vc_config_fn(vc_id,
                                                       vc_id + 0x8000,
                                                       config)
            for vc, arg in pairs(vc_set) do
               vcs[vc] = arg
            end
         end
      end
      tunnel:arg().vcs = vcs

      return tunnel:socket(('vc_%d'):format(vc_id)), tunnel:socket(('vc_%d'):format(vc_id + 0x8000))
   end

   local index, sd_pairs = 1, {}
   -- YANG BUG: the peers container should be mandatory, because it
   -- contains mandatory items (lists with min-elements > 0).
   assert(main_config.peers, 'Missing mandatory "peers" container')

   -- YANG BUG: {min,max}-elements checks NYI
   local nlpeers = tlen(main_config.peers['local'] or {})
   assert(nlpeers == 1, "Exactly one local peer required, got "..nlpeers)
   local nrpeers = tlen(main_config.peers.remote or {})
   assert(nrpeers >= 1, "At least one remote peer required, got "..nrpeers)
   for name, transport in pairs(main_config.transport) do
      local function check(arg, fmt, ...)
         assert(arg, ("Transport %s: %s"):format(name, fmt):format(...))
         return arg
      end

      local function address (type)
         local function check2(arg, fmt, ...)
            return check(arg, ("%s endpoint: %s"):format(type, fmt), ...)
         end

         local t = check2(transport[type], "missing")
         local peer = check2(main_config.peers[type][t.peer],
                             "undefined peer %s", t.peer)
         local ep = check2(peer.endpoint[t.endpoint],
                           "undefinde endpoint %s for peer %s",
                           t.endpoint, t.peer)
         -- YANG BUG: the peers container should be mandatory, because
         -- it contains mandatory items.
         check2(ep.address, "missing address for endpoint %s of peer %s", t.endpoint, t.peer)
         local afi, addr = singleton(ep.address)
         check2(afi == transport.address_family, "address family mismatch for "..
                   "endpoint %s of peer %s", t.endpoint, t.peer)

         -- Special handling for remote peers behind a NAT.  This is
         -- only relevant for IPv4 and if IPsec is enabled for the
         -- transport
         local nat_inside
         if (type == "remote" and afi == "ipv4"
             and ep.address_NAT_inside) then
            nat_inside = ntop(afi, ep.address_NAT_inside)
         end

         return ntop(afi, addr), nat_inside
      end

      local lcl_addr, _  = address('local')
      local rmt_addr, rmt_addr_nat = address('remote')
      sd_pair = src_dst_pair(transport.address_family, lcl_addr, rmt_addr)
      check(not sd_pairs[sd_pair], "endpoints already defined in "..
               "transport %s", sd_pairs[sd_pair])
      sd_pairs[sd_pair] = name
      transports[name] = {
         index = index,
         afi = transport.address_family,
         local_address = lcl_addr,
         remote_address = rmt_addr,
         remote_address_nat = rmt_addr_nat,
         vc_ids = {},
         tunnels = {},
         ipsec = transport.ipsec or { enable = false }
      }
      index = index + 1
   end

   local bridge_groups = {}
   local local_addresses = { ipv4 = {}, ipv6 = {} }
   for vpls_name, vpls in pairs(main_config.vpls) do
      local function assert_vpls (cond, msg)
         assert(cond, "VPLS "..vpls_name..": "..msg)
      end

      if not vpls.enable then
         print("Disabled VPLS instance "..vpls_name
                  .." ("..(vpls.description or "<no description>")..")")
         goto vpls_skip
      end

      print("Creating VPLS instance "..vpls_name
            .." ("..(vpls.description or "<no description>")..")")
      print("  MTU: "..vpls.mtu)

      local uplink = vpls.uplink
      assert(type(uplink) == "string",
             "Uplink interface specifier must be a string")
      local intf = intfs[uplink]
      assert_vpls(intf, "Uplink interface "..uplink.." does not exist")
      assert_vpls(intf.l3, "Uplink interface "..uplink
                     .." is L2 when L3 is expected")
      print("  Uplink is on "..uplink)

      assert(vpls.bridge, "Missing bridge configuration")
      local bridge_type, bridge_config = singleton(vpls.bridge)
      local bridge_group = {
         type = bridge_type,
         config = bridge_config,
         pws = {},
         acs = {}
      }
      bridge_groups[vpls_name] = bridge_group

      print("  Creating pseudowires")
      assert(tlen(vpls.pseudowire) > 0,
             "At least one pseudowire required")
      for name, pw in pairs(vpls.pseudowire) do
         print("    "..name)
         local transport = assert(transports[pw.transport],
                                  ("Undefined transport: %s"):
                                     format(pw.transport))
         local afi = transport.afi
         assert(intf.l3[afi].configured,
                "Address family "..afi.." not enabled on uplink")
         print("      AFI: "..afi)
         print("      Local address: "..transport.local_address)
         print("      Remote address: "..transport.remote_address)
         if transport.remote_address_nat then
            print("      Remote NAT inside address: "..transport.remote_address_nat)
         end
         print("      VC ID: "..pw.vc_id)

         -- YANG BUG: the peers container should be mandatory, because
         -- it contains mandatory items.
         assert(pw.tunnel, "Tunnel configuration missing")
         local tunnel_type, tunnel_config = singleton(pw.tunnel)
         local cc = pw.control_channel
         print("      Encapsulation: "..tunnel_type)
         print("      Control-channel: "..(cc.enable and 'enabled' or 'disabled'))

         local socket, cc_socket =
            add_pw(transport, intf, uplink, pw.vc_id,
                   tunnel_type, tunnel_config)
         local cc_app
         if cc_socket then
            local qname = main_config.instance_name..'_'..vpls_name..'_'..name
            cc_app = App:new(ctrl_plane, 'cc_'..qname,
                             require("program.l2vpn.control_channel").control_channel,
                             {
                                enable = cc.enable,
                                heartbeat = cc.heartbeat,
                                dead_factor = cc.dead_factor,
                                name = qname,
                                description = vpls.description or '',
                                mtu = vpls.mtu,
                                vc_id = pw.vc_id,
                                afi = afi,
                                peer_addr = transport.remote_address })
            local ctrl_ilink_rx = App:new(ctrl_plane, 'ilink_to_cc_'..qname,
                                          Receiver)
            ctrl_plane:connect(ctrl_ilink_rx:socket('output'), cc_app:socket('south'))
            local ctrl_ilink_tx = App:new(ctrl_plane, 'ilink_from_cc_'..qname,
                                          Transmitter)
            ctrl_plane:connect(cc_app:socket('south'), ctrl_ilink_tx:socket('input'))

            local data_ilink_rx = App:new(data_plane, 'ilink_from_cc_'..qname,
                                          Receiver)
            data_plane:connect(data_ilink_rx:socket('output'), cc_socket)
            local data_ilink_tx = App:new(data_plane, 'ilink_to_cc_'..qname,
                                          Transmitter)
            data_plane:connect(cc_socket, data_ilink_tx:socket('input'))
         end
         table.insert(bridge_group.pws,
                      { name = vpls_name..'_'..name,
                        socket = socket,
                        cc_app = cc_app,
                        cc_socket = cc_socket })

         if not local_addresses[afi][transport.local_address] then
            table.insert(intf.l3[afi].fragmenter:arg().pmtu_local_addresses,
                         transport.local_address)
            local_addresses[afi][transport.local_address] = true
         end
      end

      print("  Creating attachment circuits")
      assert(tlen(vpls.attachment_circuit) > 0,
             "At least one attachment circuit required")
      for name, t in pairs(vpls.attachment_circuit) do
         local ac = t.interface
         print("    "..name)
         assert(type(ac) == "string",
                "AC interface specifier must be a string")
         print("      Interface: "..ac)
         local intf = intfs[ac]
         assert_vpls(intf, "AC interface "..ac.." does not exist")
         assert_vpls(not intf.l3, "AC interface "..ac
                        .." is L3 when L2 is expected")
         assert_vpls(not intf.vpls, "AC interface "..ac.." already "
                        .."assigned to VPLS instance "..(intf.vpls or ''))
         table.insert(bridge_group.acs, intf)
         intf.vpls = vpls_name
         -- Note: if the AC is the native VLAN on a trunk, the actual packets
         -- can carry frames which exceed the nominal MTU by 4 bytes.
         local eff_mtu = intf.mtu
         if intf.vlan then
            -- Subtract size of service-delimiting tag
            eff_mtu = eff_mtu - 4
         end
         assert(vpls.mtu == eff_mtu, "MTU mismatch between "
                   .."VPLS ("..vpls.mtu..") and interface "
                   ..ac.." ("..eff_mtu..")")
      end
      ::vpls_skip::
   end

   for vpls_name, bridge_group in pairs(bridge_groups) do
      if #bridge_group.pws == 1 and #bridge_group.acs == 1 then
         -- No bridge needed for a p2p VPN
         local pw, ac = bridge_group.pws[1], bridge_group.acs[1]
         data_plane:connect_duplex(pw.socket, ac.l2_socket)
         -- For a p2p VPN, pass the name and description of the AC
         -- interface so the PW module can set up the proper
         -- service-specific MIB
         bridge_group.pws[1].cc_app:arg().local_if_name =
            bridge_group.acs[1].name
         bridge_group.pws[1].cc_app:arg().local_if_alias =
            bridge_group.acs[1].description
      else
         if bridge_group.type == "learning" then
            -- The YANG parser transforms the mac_table config
            -- into a FFI struct :(  We need to transform it back
            -- into a table
            local from = bridge_group.config.mac_table
            local to = {
               size = from.size,
               timeout = from.timeout,
               verbose = from.verbose,
               max_occupy = from.max_occupy,
            }
            bridge_group.config.mac_table = to
         end
         local bridge =
            App:new(data_plane, 'bridge_'..vpls_name,
                    require("apps.bridge."..bridge_group.type).bridge,
                    { ports = {},
                      split_horizon_groups = { pw = {} },
                      config = bridge_group.config })
         for _, pw in ipairs(bridge_group.pws) do
            data_plane:connect_duplex(pw.socket, bridge:socket(pw.name))
            table.insert(bridge:arg().split_horizon_groups.pw, pw.name)
         end
         for _, ac in ipairs(bridge_group.acs) do
            local ac_name = normalize_name(ac.name)
            data_plane:connect_duplex(ac.l2_socket,
                                      bridge:socket(ac_name))
            table.insert(bridge:arg().ports, ac_name)
         end
      end
   end

   -- Create sinks for interfaces not connected to any VPLS
   for name, intf in pairs(intfs) do
      if intf.l2_socket and not intf.l2_socket.connected_out then
         local sink = App:new(data_plane, 'sink_'..intf.nname,
                              Sink, {})
         data_plane:connect_duplex(intf.l2_socket, sink:socket('input'))
      elseif intf.l3 then
         for afi, state in pairs(intf.l3) do
            local socket = state.socket_out
            if socket and not socket.connected_out then
               local sink = App:new(data_plane, 'sink_'..intf.nname..'_'..afi,
                                    Sink, {})
               data_plane:connect_duplex(state.socket_out, sink:socket('input'))
            end
         end
      end
   end

   return state
end

local function maybe_create_stats_frame (intf, pid)
   if not intf.vlan and not intf.stats then
      local stats_path = '/'..pid..'/'
         ..intf.driver_helper.stats_path(intf)
      intf.stats = shm.open_frame(stats_path)
      counter.commit()
   end
end

local function find_linkspecs (intf, links)
   local function find_linkspec (pattern)
      pattern = string.gsub(pattern, '%.', '%%.')
      for _, linkspec in ipairs(links) do
         if string.match(linkspec, pattern) then
            return linkspec
         end
      end
      error("No links match pattern: "..pattern)
   end
   return find_linkspec('^'..intf.vmux_socket.output()),
   find_linkspec(intf.vmux_socket.input()..'$')
end

local function setup_snmp_for_interface (state, name, intf, interval, pid)
   local shm_subdir = 'snmp'
   local shm_dir = shm.root.."/"..shm_subdir
   shm.mkdir(shm_subdir)
   local normalized_name = string.gsub(name, '/', '-')

   if not intf.vlan then
      -- Physical interface
      maybe_create_stats_frame(intf, pid)
      if intf.stats then
         intf.stats_timer =
            ifmib.init_snmp( { ifDescr = name,
                               ifName = name,
                               ifAlias = intf.description, },
               normalized_name, intf.stats,
               shm_dir, interval or 5)
      else
         print("Can't enable SNMP for interface "..name
                  ..": no statistics counters available")
      end
   else
      -- Sub-interface
      counter_t = ffi.typeof("struct counter")
      local counters = {}
      local function map (c)
         return (c and ffi.cast("struct counter *", c)) or nil
      end
      counters.type = counter_t()
      if intf.l3 then
         counters.type.c = 0x1003ULL -- l3ipvlan
      else
         counters.type.c = 0x1002ULL -- l2vlan
      end
      -- Inherit the operational status, MAC address, MTU, speed
      -- from the physical interface
      maybe_create_stats_frame(intf.phys_intf, pid)
      local stats = intf.phys_intf.stats
      counters.status = map(stats.status)
      counters.macaddr = map(stats.macaddr)
      counters.mtu = map(stats.mtu)
      counters.speed = map(stats.speed)

      -- Create mappings to the counters of the relevant VMUX
      -- link. The VMUX app replaces the physical network for a
      -- sub-interface.  Hence, its output is what the
      -- sub-interface receives and its input is what the
      -- sub-interface transmits to the "virtual wire".
      local path_prefix = '/'..pid..'/'
      local spec_tx, spec_rx = find_linkspecs(intf, state.data_plane:links())
      local tstats = shm.open_frame(path_prefix..'links/'..spec_tx)
      local rstats = shm.open_frame(path_prefix..'links/'..spec_rx)
      intf.tstats, intf.rstats = tstats, rstats
      intf.link_spec = spec_tx..spec_rx

      counters.rxpackets = map(tstats.txpackets)
      counters.rxbytes = map(tstats.txbytes)
      counters.rxdrop = map(tstats.txdrop)
      counters.txpackets = map(rstats.rxpackets)
      counters.txbytes = map(rstats.rxbytes)
      intf.stats_timer =
         ifmib.init_snmp({ ifDescr = name,
                           ifName = name,
                           ifAlias = intf.description, },
            normalized_name, counters,
            shm_dir, interval or 5)
   end
end

local old_intfs = {}
local function setup_l2vpn (config)
   local state = parse_config(config.l2vpn_config)
   -- Used by initialization code before the main loop is entered
   initial_state = initial_state or state

   -- Interface changes require re-mapping of the statistics counters
   -- for SNMP.  Unmapping can be done here, but new mappings must be
   -- scheduled through a one-shot timer because the new configuration
   -- has not yet been instantiated in the worker process when we get
   -- here.
   --
   -- Sub-interfaces are particularly annoying.  They may get
   -- re-connected from a bridge to a sink if no active VPLS connects
   -- to them.  The link specs for that connection is saved to detect
   -- this.
   local snmp = config.l2vpn_config.snmp
   for name, old_intf in pairs(old_intfs) do
      local new_intf = state.intfs[name]
      if (not new_intf or
             (old_intf.vlan and old_intf.link_spec ~=
                 table.concat({find_linkspecs(new_intf,
                                              state.data_plane:links())},
                    ""))) then

         -- The interface has either gone away or it's a sub-interface
         -- with changed link specs, remove all shm segments and stats
         -- timers.
         if not old_intf.vlan then
            assert(old_intf.stats)
            shm.delete_frame(old_intf.stats)
         else
            assert(old_intf.tstats)
            assert(old_intf.rstats)
            shm.delete_frame(old_intf.tstats)
            shm.delete_frame(old_intf.rstats)
         end
         timer.cancel(old_intf.stats_timer)
      elseif new_intf then
         for _, k in ipairs({ 'stats', 'tstats', 'rstats',
                              'stats_timer', 'link_spec' }) do
            new_intf[k] = old_intf[k]
         end
      end
   end

   for name, intf in pairs(state.intfs) do
      if not intf.stats_timer and snmp.enable and worker_pid then
         -- Schedule a one-shot timer to set up SNMP for this
         -- interface
         timer.activate(timer.new("Interface "..name.." SNMP setup",
                                  function ()
                                     setup_snmp_for_interface(state, name, intf,
                                                              snmp.interval,
                                                              worker_pid)
                                  end, 1e9 * 5))
      elseif intf.stats_timer and not snmp.enable then
         timer.cancel(intf.stats_timer)
         intf.stats_timer = nil
      end
   end

   old_intfs = state.intfs

   return { data_plane = state.data_plane:app_graph(),
            control_plane = state.ctrl_plane:app_graph() }
end

local function do_ipsec_hash (parameters)
   local siphash = require("lib.hash.siphash")

   local hash_buf = {
      ipv6 = ffi.new[[
             struct {
                uint8_t remote[16];
                uint8_t local[16];
             } __attribute__ ((__packed__))
          ]],
      ipv4 = ffi.new[[
             struct {
                uint8_t remote[4];
                uint8_t local[4];
             } __attribute__ ((__packed__))
          ]],
   }

   assert(#parameters == 3)
   local afi, loc, rem = unpack(parameters)
   local af = require("lib.protocol."..afi)
   local hash_buf = hash_buf[afi]

   hash_buf['local']  = af:pton(loc)
   hash_buf.remote  = af:pton(rem)
   local key = ffi.new("uint8_t[16]", 0, 1, 2, 3, 4, 5, 6, 7,
                       8, 9, 10, 11, 12, 13, 14, 15)
   local hash_fn = siphash.make_hash({ size = ffi.sizeof(hash_buf),
                                       standard = true, key = key })
   local hash = hash_fn(hash_buf)
   print("/ipsec/"..bit.tohex(hash))
end

local long_opts = {
   duration = "D",
   ["busy-wait"] = "b",
   debug = "d",
   jit = "j",
   ipsec = "i",
   help = "h",
}

function run (parameters)
   local duration = 0
   local busywait = false
   local jit_conf = {}
   local jit_opts = {}
   local opt = {}
   local ipsec_hash = false
   function opt.D (arg)
      if arg:match("^[0-9]+$") then
         duration = tonumber(arg)
      else
         usage()
      end
   end
   function opt.h (arg) usage() end
   function opt.i (arg)
      ipsec_hash = true
   end
   function opt.b (arg)
      busywait = true
   end
   function opt.d (arg) _G.developer_debug = true end
   function opt.j (arg)
      if arg:match("^v") then
         local file = arg:match("^v=(.*)")
         if file == '' then file = nil end
         require("jit.v").start(file)
      elseif arg:match("^p") then
         jit_conf.p = {}
         local p = jit_conf.p
         p.opts, p.file = arg:match("^p=([^,]*),?(.*)")
         if p.file == '' then p.file = nil end
      elseif arg:match("^dump") then
         jit_conf.dump = {}
         local dump = jit_conf.dump
         dump.opts, dump.file = arg:match("^dump=([^,]*),?(.*)")
         if dump.file == '' then dump.file = nil end
      elseif arg:match("^opt") then
         local opt = arg:match("^opt=(.*)")
         table.insert(jit_opts, opt)
      end
   end

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hbdij:D:", long_opts)

   if ipsec_hash then
      do_ipsec_hash(parameters)
      os.exit(0)
   end

   if #jit_opts then
      require("jit.opt").start(unpack(jit_opts))
   end

   if #parameters < 1 or #parameters > 2 then usage () end
   local config_file, state_dir = unpack(parameters)

   if jit_conf.p then
      require("jit.p").start(jit_conf.p.opts, jit_conf.p.file)
   end
   if jit_conf.dump then
      require("jit.dump").start(jit_conf.dump.opts, jit_conf.dump.file)
   end
   local initial_config =
      yang.load_configuration(config_file,
                              {  schema_name = "snabb-l2vpn-v1",
                                 verbose = true })

   local jit_config = initial_config.l2vpn_config.luajit
   local manager = ptree.new_manager(
      { schema_name = "snabb-l2vpn-v1",
        setup_fn = setup_l2vpn,
        log_level = "INFO",
        initial_configuration = initial_config,
        worker_default_scheduling = {
           busywait = busywait
        },
        worker_opts = {
           duration = duration ~= 0 and duration or nil,
           measure_latency = false,
           jit_opts = jit_config.option,
           jit_dump = jit_config.dump and jit_config.dump.enable and
              jit_config.dump
        },
        exit_after_worker_dies = true
   })

   manager:main(5)
   worker_pid = manager.workers.data_plane.pid
   if state_dir then
      local function write_pid (pid, file)
         local f = assert(io.open(state_dir.."/"..file, "w"))
         assert(f:write(("%d"):format(pid)))
         assert(f:close())
      end
      write_pid(S.getpid(), 'master.pid')
      write_pid(worker_pid, 'data.pid')
      write_pid(manager.workers.control_plane.pid, 'ctrl.pid')
   end

   -- Map stats for initial physical (non-vlan) interfaces
   for name, intf in pairs(initial_state.intfs) do
      maybe_create_stats_frame(intf, worker_pid)
   end
   local snmp = initial_config.l2vpn_config.snmp
   if snmp.enable then
      for name, intf in pairs(initial_state.intfs) do
         setup_snmp_for_interface(initial_state, name, intf,
                                  snmp.interval, worker_pid)
      end
   end

   for name, nd in pairs(initial_state.nds) do
      local mac = macaddress:new(counter.read(nd.intf.stats.macaddr))
      nd.app:arg().local_mac = ethernet:pton(ethernet:ntop(mac.bytes))
   end
   for name, arp in pairs(initial_state.arps) do
      local mac = macaddress:new(counter.read(arp.intf.stats.macaddr))
      arp.app:arg().self_mac = ethernet:pton(ethernet:ntop(mac.bytes))
   end
   manager:update_worker_graph('data_plane', initial_state.data_plane:app_graph())
   manager:main(duration ~= 0 and (duration + 5) or nil)
end

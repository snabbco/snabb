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

local bridge_types = { flooding = true, learning = true }

function usage ()
   print(usage_msg)
   main.exit(0)
end

local function merge (a, b)
   for k, v in pairs(b) do
      a[k] = v
   end
end

local state
local function clear_state ()
   state =  {
      apps = {},
      links = {},
      intfs = {},
      nds = {},
      arps = {},
   }
end

local App = {}
function App:new (name, class, initial_arg)
   assert(not state.apps[name], "Duplicate app "..name)
   local self = setmetatable({}, { __index = App })
   state.apps[name] = self
   self._name = name
   self._class = class
   self:arg(initial_arg)
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

local function connect (from, to)
   table.insert(state.links, from.output()..' -> '..to.input())
end

local function connect_duplex (from, to)
   connect(from, to)
   connect(to, from)
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

local function check_af (afi)
   return assert(af_classes[afi], "Invalid address family identifier: "..afi)
end

local function src_dst_pair (af, src, dst)
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

local function nil_or_empty_p (t)
   if not t then return true end
   assert(type(t) == "table", type(t))
   for _, _ in pairs(t) do
      return(false)
   end
   return(true)
end

local function eval (expr, msg)
   local result, err = loadstring("return ("..expr..")")
   assert(result, "Invalid Lua expression"..msg..": "
             ..expr..": "..(err or ''))
   return result()
end

-- Return the key and value of a table with a single entry
local function singleton (t)
   local iter, state = pairs(t)
   return iter(state)
end

function parse_intf(name, config)
   print("Setting up interface "..name)
   print("  Description: "..(config.description or "<none>"))
   local intf = {
      description = config.description,
      name = name,
      -- The normalized name is used in app and link names
      nname = normalize_name(name),
   }

   -- NIC driver
   local drv_c = config.driver
   local drv_config = eval(drv_c.config, " in driver configuration")
   local driver_helper = driver_helpers[drv_c.path.."."..drv_c.name]

   if type(drv_config) == "table" then
      if (drv_config.pciaddr) then
         print("  PCI address: "..drv_config.pciaddr)
	 intf.pci_address = drv_config.pciaddr
      end
      drv_config.mtu = config.mtu
      merge(drv_config, driver_helper.config())
      if drv_c.extra_config then

         -- If present, extra_config must evaluate to a table, whose
         -- elements are merged with the regular config.  This feature
         -- allows for more flexibility when the configuration is
         -- created by a Lua-agnostic layer on top, e.g. by a NixOS
         -- module
         local extra_config = eval(drv_c.extra_config, "in driver extra configuration")
         assert(type(extra_config) == "table",
                "Driver extra configuration must be a table")
         for k, v in pairs(extra_config) do
            drv_config[k] = v
         end
      end
   end
   intf.app = App:new('intf_'..intf.nname,
                      require(drv_c.path)[drv_c.name], drv_config)
   assert(driver_helper,
          "Unsupported driver (missing driver helper)"
             ..drv_c.path.."."..drv_c.name)
   intf.driver_helper = driver_helper
   intf.l2 = intf.app:socket(driver_helper.link_names())

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
               local mirror = App:new('tap_'..intf.nname..'_pcap_'..dir,
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
               local mirror = App:new('tap_'..intf.nname..'_'..dir,
                                      Tap, { name = tap_name, mtu = config.mtu})
               mirror_socket = mirror:socket('input', 'output')
               local sink = App:new('sink_'..intf.nname..'_tap_'..dir,
                                    Sink)
               connect(mirror_socket, sink:socket('input'))
               print("    "..dir.." port-mirror on tap interface "..tap_name)
            else
               error("Illegal mirror type: "..mtype)
            end
            local tee = App:new('tee_'..intf.nname..'_'..dir, Tee)
            connect(tee:socket('mirror'), mirror_socket)
            if dir == "rx" then
               connect(intf.l2, tee:socket('input'))
               intf.l2.output = tee:socket('pass').output
            else
               connect(tee:socket('pass'), intf.l2)
               intf.l2.input = tee:socket('input').input
            end
         end
      end
   end

   local function vid_suffix (vid)
      return (vid and "_"..vid) or ''
   end

   local afs_procs = {
      ipv6 = function (config, vid, socket_in, indent)
         -- FIXME: check fo uniqueness of subnet
         print(indent.."    Address: "..config.address.."/64")
         print(indent.."    Next-Hop: "..config.next_hop)
         if config.next_hop_mac then
            print(indent.."    Next-Hop MAC address: "
                     ..config.next_hop_mac)
         end

         local nd = App:new('nd_'..intf.nname..vid_suffix(vid),
                            nd_light,
                            { local_ip  = ipv6:pton(config.address),
                              local_mac = ethernet:pton("00:00:00:00:00:00"),
                              remote_mac = config.next_hop_mac,
                              next_hop = ipv6:pton(config.next_hop),
                              quiet = true })
         state.nds[nd:name()] = { app = nd, intf = intf }
         connect_duplex(nd:socket('south'), socket_in)

         fragmenter = App:new('frag_v6_'..intf.nname..vid_suffix(vid),
                              frag_ipv6,
                              { mtu = intf.mtu - 14, pmtud = true,
                                pmtu_local_addresses = {},
                                use_alarms = false })
         local reassembler = App:new('reass_v6_'..intf.nname..vid_suffix(vid),
                                     reass_ipv6,
                                     { use_alarms = false })
         local nd_north = nd:socket('north')
         connect(nd_north, fragmenter:socket('south'))
         connect(fragmenter:socket('output'), nd_north)
         connect(fragmenter:socket('north'),
                 reassembler:socket('input'))
         return socket(fragmenter, 'input', reassembler, 'output'), fragmenter
      end,

      ipv4 = function (config, vid, socket_in, indent)
         -- FIXME: check fo uniqueness of subnet
         print(indent.."    Address: "..config.address.."/24")
         print(indent.."    Next-Hop: "..config.next_hop)
         if config.next_hop_mac then
            print(indent.."    Next-Hop MAC address: "
                     ..config.next_hop_mac)
         end

         local arp = App:new('arp_'..intf.nname..vid_suffix(vid),
                             arp,
                             { self_ip  = ipv4:pton(config.address),
                               self_mac = ethernet:pton("00:00:00:00:00:00"),
                               next_mac = config.next_hop_mac and
                                  ethernet:pton(config.next_hop_mac or nil),
                               next_ip = ipv4:pton(config.next_hop) })
         state.arps[arp:name()] = { app = arp, intf = intf }
         connect_duplex(arp:socket('south'), socket_in)

         fragmenter = App:new('frag_v4_'..intf.nname..vid_suffix(vid),
                              frag_ipv4,
                              { mtu = intf.mtu - 14, pmtud = true,
                                pmtu_local_addresses = {},
                                use_alarms = false })
         local reassembler = App:new('reass_v4_'..intf.nname..vid_suffix(vid),
                                     reass_ipv4,
                                     { use_alarms = false })
         local arp_north = arp:socket('north')
         connect(arp_north, fragmenter:socket('south'))
         connect(fragmenter:socket('output'), arp_north)
         connect(fragmenter:socket('north'),
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

      if af_configs.ipv4 and af_configs.ipv6 then
         -- Add a demultiplexer for IPv4/IPv6
         local afd = App:new('af_mux_'..intf.nname..vid_suffix(vid),
                             af_mux)
         connect_duplex(afd:socket('south'), socket)
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
      assert(nil_or_empty_p(config.address_families),
             "Address family configuration not allowed in trunking mode")
      local encap = trunk.encapsulation or "dot1q"
      assert(encap == "dot1q" or encap == "dot1ad" or
                (type(encap) == "number"),
             "Illegal encapsulation mode "..encap)
      print("      Encapsulation "..
               (type(encap) == "string" and encap
                   or string.format("ether-type 0x%04x", encap)))
      local vmux = App:new('vmux_'..intf.nname, VlanMux,
                           { encapsulation = encap })
      connect_duplex(vmux:socket('trunk'), intf.l2)

      -- Process VLANs and create sub-interfaces
      print("  Sub-Interfaces")
      local sub_intf_id = 0
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
         if not nil_or_empty_p(vlan.address_families) then
            subintf.l3 = process_afs(vlan.address_families, vid,
                                     socket, "    ")
         else
            subintf.l2 = socket
         end

         -- Store a copy of the vmux socket to find the proper shm
         -- frame for the interface counters later on
         subintf.vmux_socket = socket
      end
   else
      print("    Trunking mode: disabled")
      if not nil_or_empty_p(config.address_families) then
         intf.l3 = process_afs(config.address_families, nil, intf.l2, "")
      end
   end

   return intf
end

function parse_config (main_config)
   local intfs = state.intfs
   for name, config in pairs(main_config.interface) do
      local intf = parse_intf(name, config)
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
   local pws = {}
   local dispatchers = { ipv4 = {}, ipv6 = {} }
   local tunnel_infos = {
      l2tpv3 = {
         class = require("program.l2vpn.tunnels.l2tpv3").tunnel,
         params = {
            local_cookie = { required = true },
            remote_cookie = { required = true }
         },
         proto = 115,
         mk_vc_config_fn = function (vc_id, cc_vc_id, tunnel_config)
            local function maybe_eval_cookie(name)
               local s = tunnel_config[name]
               if s then
                  tunnel_config[name] = eval("'"..s.."'",'')
               end
            end
            for _, cookie in ipairs({ 'local_cookie', 'remote_cookie' }) do
               maybe_eval_cookie(cookie)
            end
            return {
               [vc_id] = tunnel_config,
               [cc_vc_id] = {
                   local_session = 0xFFFFFFFE,
                   remote_session = 0xFFFFFFFE,
                   local_cookie = '\x00\x00\x00\x00\x00\x00\x00\x00',
                   remote_cookie = '\x00\x00\x00\x00\x00\x00\x00\x00',
               }
            }
         end,
         afs = {
            ipv6 = true
         }
      },
      gre = {
         class = require("program.l2vpn.tunnels.gre").tunnel,
         params = {},
         proto = 47,
         mk_vc_config_fn = function (vc_id, cc_vc_id, tunnel_config)
            return {
               [vc_id] = {},
               [cc_vc_id] = {}
            }
         end,
         vc_id_max = 0xFFFFFFFF,
         afs = {
            ipv4 = true,
            ipv6 = true
         }
      }
   }
   local function add_pw (afi, intf, uplink, local_addr, remote_addr,
                          vc_id, type, config, ipsec_assocs)
      local dispatch = dispatchers[afi][uplink]
      if not dispatch then
         dispatch = App:new('disp_'..normalize_name(uplink).."_"..afi,
                            require("program.l2vpn.dispatch").dispatch,
                            { afi = afi, links = {} })
         connect_duplex(dispatch:socket('south'),
                        intf.l3[afi].socket_out)
         intf.l3[afi].used = true
         dispatchers[afi][uplink] = dispatch
      end

      local tunnel_info = assert(tunnel_infos[type],
                                 "Unsupported tunnel type :"..type)
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

      local af = check_af(afi)
      local sd_pair = src_dst_pair(af, remote_addr, local_addr)
      local sd_entry
      for index, entry in ipairs(pws) do
         if entry.sd_pair == sd_pair then
            assert(not entry.vc_ids[vc_id],
                   "Non-unique pseudowire: ", af:ntop(remote_addr),
                   af:ntop(local_addr), vc_id)
            entry.vc_ids[vc_id] = vc_id
            sd_entry = entry
            break
         end
      end
      if not sd_entry then
         local index = #pws + 1

         -- Insert an IPsec app if the SD pair is part of a configured
         -- association
         local assoc = ipsec_assocs[sd_pair]
         local socket
         if assoc then
            print("      IPsec: "..assoc.aead)
            local esp_module = afi == "ipv4" and "Transport4_IKE" or
               "Transport6_IKE"
            local ipsec = App:new('ipsec_'..afi.."_"..index,
                                  require("apps.ipsec.esp")[esp_module],
                                  assoc)
            connect_duplex(dispatch:socket('sd_'..index),
                           ipsec:socket('encapsulated'))
            socket = ipsec:socket('decapsulated')
         else
            print("      IPsec: disabled")
            socket = dispatch:socket('sd_'..index)
         end

         -- Each (source, destination) pair connects to a dedicated
         -- protocol multiplexer.
         local protomux = App:new('pmux_'..index,
                                  require("program.l2vpn.transports."..afi).transport,
                                  { src = local_addr, dst = remote_addr, links = {} })
         dispatch:arg().links['sd_'..index] = { src = remote_addr,
                                                dst = local_addr }
         connect_duplex(socket, protomux:socket('south'))
         sd_entry = { sd_pair = sd_pair,
                      index = index,
                      protomux = protomux,
                      tunnels = {},
                      vc_ids = { vc_id = true } }
         table.insert(pws, sd_entry)
      end

      local tunnel = sd_entry.tunnels[type]
      if not tunnel then
         tunnel = App:new(type.."_"..sd_entry.index,
                          tunnel_info.class,
                          { vcs =
                               tunnel_info.mk_vc_config_fn(vc_id,
                                                           vc_id + 0x8000,
                                                           config),
                            ancillary_data = {
                               remote_addr = af:ntop(remote_addr),
                               local_addr = af:ntop(local_addr) } })
         sd_entry.protomux:arg().links[type] = { proto = tunnel_info.proto }
         connect_duplex(sd_entry.protomux:socket(type),
                        tunnel:socket('south'))
      end

      return tunnel:socket(('vc_%d'):format(vc_id)), tunnel:socket(('vc_%d'):format(vc_id + 0x8000))
   end

   local ipsec_assocs = {}
   for _, config in pairs(main_config.ipsec) do
      local afi, addrs = singleton(config.endpoints)
      local af = check_af(afi)
      local sd_pair = src_dst_pair(af, addrs.remote_address, addrs.local_address)
      assert(not ipsec_assocs[sd_pair],
             ("Multiple definitions for IPsec association %s<->%s"):format(
                config.remote_address, config.local_address))
      local assoc = { aead = config.encryption_algorithm, auditing = true }
      for _, k in ipairs({ 'local_address', 'remote_address' }) do
         assoc[k] = addrs[k]
      end
      ipsec_assocs[sd_pair] = assoc
   end

   local bridge_groups = {}
   for vpls_name, vpls in pairs(main_config.vpls) do
      local function assert_vpls (cond, msg)
         assert(cond, "VPLS "..vpls_name..": "..msg)
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
      intf.used = true

      local bridge_type, bridge_config = singleton(vpls.bridge)
      local bridge_group = {
         type = bridge_type,
         config = bridge_config,
         pws = {},
         acs = {}
      }
      bridge_groups[vpls_name] = bridge_group

      local local_addresses = { ipv4 = {}, ipv6 = {} }
      print("  Creating pseudowires")
      for name, pw in pairs(vpls.pseudowire) do
         print("    "..name)
         assert(pw.transport, "Transport configuration missing")
         local afi, transport = singleton(pw.transport)
         local af = af_classes[afi]
         assert(intf.l3[afi].configured,
                "Address family "..afi.." not enabled on uplink")
         assert(af:pton(transport.local_address),
                "Invalid local "..afi.." address "..transport.local_address)
         assert(af:pton(transport.remote_address),
                "Invalid remote "..afi.." address "..transport.remote_address)
         print("      AFI: "..afi)
         print("      Local address: "..transport.local_address)
         print("      Remote address: "..transport.remote_address)
         print("      VC ID: "..pw.vc_id)

         assert(pw.tunnel, "Tunnel configuration missing")
         local tunnel_type, tunnel_config = singleton(pw.tunnel)
         local cc = pw.control_channel
         print("      Encapsulation: "..tunnel_type)
         print("      Control-channel: "..(cc.enable and 'enabled' or 'disabled'))

         local socket, cc_socket =
            add_pw(afi, intf, uplink, af:pton(transport.local_address),
                   af:pton(transport.remote_address),
                   pw.vc_id, tunnel_type, tunnel_config, ipsec_assocs)
         local cc_app
         if cc_socket then
            cc_app = App:new('cc_'..vpls_name..'_'..name,
                             require("program.l2vpn.control_channel").control_channel,
                             {
                                enable = cc.enable,
                                heartbeat = cc.heartbeat,
                                dead_factor = cc.dead_factor,
                                name = vpls_name..'_'..name,
                                description = vpls.description,
                                mtu = vpls.mtu,
                                vc_id = pw.vc_id,
                                afi = afi,
                                peer_addr = transport.remote_address })
            connect_duplex(cc_socket, cc_app:socket('south'))
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
         assert_vpls(not intf.used, "AC interface "..ac.." already "
                        .."assigned to another VPLS")
         table.insert(bridge_group.acs, intf)
         intf.used = true
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
   end

   for vpls_name, bridge_group in pairs(bridge_groups) do
      if #bridge_group.pws == 1 and #bridge_group.acs == 1 then
         -- No bridge needed for a p2p VPN
         local pw, ac = bridge_group.pws[1], bridge_group.acs[1]
         connect_duplex(pw.socket, ac.l2)
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
            local from = bridge_group.config
            local to = {
               size = from.size,
               timeout = from.timeout,
               verbose = from.verbose,
               max_occupy = from.max_occupy,
            }
            bridge_group.config = to
         end
         local bridge =
            App:new('bridge_'..vpls_name,
                    require("apps.bridge."..bridge_group.type).bridge,
                    { ports = {},
                      split_horizon_groups = { pw = {} },
                      config = bridge_group.config })
         for _, pw in ipairs(bridge_group.pws) do
            connect_duplex(pw.socket, bridge:socket(pw.name))
            table.insert(bridge:arg().split_horizon_groups.pw, pw.name)
         end
         for _, ac in ipairs(bridge_group.acs) do
            local ac_name = normalize_name(ac.name)
            connect_duplex(ac.l2,
                           bridge:socket(ac_name))
            table.insert(bridge:arg().ports, ac_name)
         end
      end
   end

   -- Create sinks for unused interfaces
   for name, intf in pairs(intfs) do
      if intf.l2 and not intf.used and not intf.subintfs then
         local sink = App:new('sink_'..intf.nname,
                              Sink, {})
         connect_duplex(intf.l2, sink:socket('input'))
      elseif intf.l3 then
         for afi, state in pairs(intf.l3) do
            if state.configured and not state.used then
               -- Create sink for a L3 interface not connected to
               -- a dispatcher
               local sink = App:new('sink_'..intf.nname..'_'..afi,
                                    Sink, {})
               connect_duplex(state.socket_out, sink:socket('input'))
            end
         end
      end
   end
end

local function setup_shm_and_snmp (main_config, pid)
   -- For each interface, attach to the shm frame that stores
   -- the statistics counters
   for _, intf in pairs(state.intfs) do
      if not intf.vlan then
         local stats_path = "/"..pid.."/"..intf.driver_helper.stats_path(intf)
         intf.stats = shm.open_frame(stats_path)
      end
   end
   -- Commit all counters to the backing store to make them available
   -- immediately through the read-only frames we just created
   counter.commit()

   local snmp = main_config.snmp or { enable = false }
   if snmp.enable then
      for name, intf in pairs(state.intfs) do
         if not intf.vlan then
            -- Set up SNMP for physical interfaces
            local stats = intf.stats
            if stats then
               ifmib.init_snmp( { ifDescr = name,
                                  ifName = name,
                                  ifAlias = intf.description, },
                  string.gsub(name, '/', '-'), stats,
                  main_config.shmem_dir, snmp.interval or 5)
            else
               print("Can't enable SNMP for interface "..name
                        ..": no statistics counters available")
            end
         else
            -- Set up SNMP for sub-interfaces
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
            local stats = intf.phys_intf.stats
            counters.status = map(stats.status)
            counters.macaddr = map(stats.macaddr)
            counters.mtu = map(stats.mtu)
            counters.speed = map(stats.speed)

            -- Create mappings to the counters of the relevant VMUX
            -- link The VMUX app replaces the physical network for a
            -- sub-interface.  Hence, its output is what the
            -- sub-interface receives and its input is what the
            -- sub-interface transmits to the "virtual wire".
            local function find_linkspec (pattern)
               pattern = string.gsub(pattern, '%.', '%%.')
               for _, linkspec in ipairs(state.links) do
                  if string.match(linkspec, pattern) then
                     return linkspec
                  end
               end
               error("No links match pattern: "..pattern)
            end
            local tstats = shm.open_frame(
               'links/'..
                  find_linkspec('^'..intf.vmux_socket.output()))
            local rstats = shm.open_frame(
               'links/'..
                  find_linkspec(intf.vmux_socket.input()..'$'))
            counters.rxpackets = map(tstats.txpackets)
            counters.rxbytes = map(tstats.txbytes)
            counters.rxdrop = map(tstats.txdrop)
            counters.txpackets = map(rstats.rxpackets)
            counters.txbytes = map(rstats.rxbytes)
            ifmib.init_snmp( { ifDescr = name,
                               ifName = name,
                               ifAlias = intf.description, },
               string.gsub(name, '/', '-'), counters,
               main_config.shmem_dir, snmp.interval or 5)
         end
      end
   end
end

local function create_app_graph ()
   local graph = app_graph.new()
   for name, app in pairs(state.apps) do
      -- Copy arg to allow app reconfiguration
      app_graph.app(graph, app:name(), app:class(), lib.deepcopy(app:arg()))
   end
   for _, linkspec in ipairs(state.links) do
      app_graph.link(graph, linkspec)
   end
   return graph
end

local function setup_l2vpn (config)
   print("SETUP L2VPN")
   clear_state()
   parse_config(config.l2vpn_config)
   return { l2vpn = create_app_graph() }
end

local long_opts = {
   duration = "D",
   reconfig = "r",
   debug = "d",
   jit = "j",
   help = "h",
}

function run (parameters)
   local duration = 0
   local reconfig = false
   local jit_conf = {}
   local jit_opts = {}
   local opt = {}
   function opt.D (arg)
      if arg:match("^[0-9]+$") then
         duration = tonumber(arg)
      else
         usage()
      end
   end
   function opt.h (arg) usage() end
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
   function opt.r (arg) reconfig = true end

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hdj:D:l:r", long_opts)
   if (reconfig and not (duration > 0)) then
      print("--reconfig requires --duration > 0 to take effect")
      usage()
   end

   -- Defaults: sizemcode=32, maxmcode=512
   require("jit.opt").start('sizemcode=256', 'maxmcode=2048')
   if #jit_opts then
      require("jit.opt").start(unpack(jit_opts))
   end
   if #parameters ~= 1 then usage () end

   local config_file = table.remove(parameters, 1)

   local engine_opts = { no_report = true, measure_latency = false }
   if duration ~= 0 then engine_opts.duration = duration end
   if jit_conf.p then
      require("jit.p").start(jit_conf.p.opts, jit_conf.p.file)
   end
   if jit_conf.dump then
      require("jit.dump").start(jit_conf.dump.opts, jit_conf.dump.file)
   end
   clear_state()
   local initial_config =
      yang.load_configuration(config_file,
                              {  schema_name = "snabb-l2vpn-v1",
                                 verbose = true })

   local manager = ptree.new_manager(
      { schema_name = "snabb-l2vpn-v1",
        setup_fn = setup_l2vpn,
        log_level = "INFO",
        initial_configuration = initial_config,
        worker_opts = {
           jit_opts = jit_opts,
           jit_dump = { jit_conf.dump.opts, jit_conf.dump.file }
        }
   })

   manager:main(5)
   local worker_pid = manager.workers.l2vpn.pid
   setup_shm_and_snmp(initial_config.l2vpn_config, worker_pid)
   for name, nd in pairs(state.nds) do
      local mac = macaddress:new(counter.read(nd.intf.stats.macaddr))
      nd.app:arg().local_mac = ethernet:pton(ethernet:ntop(mac.bytes))
   end
   for name, arp in pairs(state.arps) do
      local mac = macaddress:new(counter.read(arp.intf.stats.macaddr))
      arp.app:arg().self_mac = ethernet:pton(ethernet:ntop(mac.bytes))
   end
   local new_graph = create_app_graph()
   manager:update_worker_graph('l2vpn', new_graph)
   manager:main()
end

-- This program provisions a complete endpoint for one or more L2 VPNs.
--
-- Each VPN provides essentially a multi-point L2 VPN over IPv6,
-- a.k.a. Virtual Private LAN Service (VPLS). A point-to-point VPN,
-- a.k.a. Virtual Private Wire Service (VPWS) is provided as a
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
-- directly to the driver.  For a L3 interface, the nd_light app is
-- attached to the driver and other apps attach to nd_light instead.
--
-- If the interface is in trunking mode, an instance of the VlanMux
-- app from apps.vlan.vlan is instantiated and its "trunk" port is
-- connected to the interface.  For each sub-interface that contains a
-- L3 configuration, an instance of the nd_light app is attached to
-- the appropriate "vlan" link of the VlanMux app (for vlan = 0, the
-- corresponding VlanMux link is called "native").
--
-- Each uplink of the VPLS configuration must reference a
-- L3-(sub-)interface of a previously defined physical interface.  For
-- each VPLS, the "uplink" link of the pseudowire-dispatch app is
-- connected to the "north" link of the ND module of its uplink
-- interface.
--
-- The dispatch app provides the demultiplexing of incoming packets
-- based on the source and destination IPv6 addresses, which uniquely
-- identify a single pseudowire within one of the VPLS instances.
--
-- An instance of apps.bridge.learning or apps.bridge.flooding is
-- created for every VPLS, depending on the selected bridge type.  The
-- bridge connects all pseudowires and attachment circuits of the
-- VPLS.  The pseudowires are assigned to a split horizon group,
-- i.e. packets arriving on any of those links are only forwarded to
-- the attachment circuits and not to any of the other pseudowires
-- (this is a consequence of the full-mesh topology of the pseudowires
-- of a VPLS).  All attachment circuits defined for a VPLS must
-- reference a L2 sub-interface of a physical interface.  In
-- non-trunking mode, the interface driver us connected directly to
-- the bridge module.  In trunking mode, the corresponding "vlan"
-- links of the VlanMux app are connected to the bridge instead.
--
-- Every pseudowire can have its own tunnel configuration or it can
-- inherit a default configuration for the entire VPLS instance.
--
-- Finally, all pseudowires of the VPLS instance are connected to the
-- dispatcher on the "ac" side.
--
-- If a VPLS consists of a single PW and a single AC, the resulting
-- two-port bridge is optimized away by creating a direct link between
-- the two.  The VPLS thus turns into a VPWS.

-- config = {
--   [ shmem_dir = <shmem_dir> , ]
--   [ snmp = { enable = true | false,
--              interval = <interval> }, ]
--   interfaces = {
--     {
--       name = <name>,
--       [ description = <description>, ]
--       driver = {
--         path = <path>,
--         name = <name>,
--         config = {
--           pciaddr = <pciaddress>,
--         },
--         [ extra_config = <extra_config>, ]
--       },
--       mtu = <mtu>,
--       [ -- only allowed if trunk.enable == false
--         afs = {
--           ipv6 = {
--             address = <address>,
--             next_hop = <next_hop>,
--             [ next_hop_mac = <neighbor_mac> ]
--           }
--         }, ]
--       [ trunk = {
--           enable = true | false,
--           encapsulation = "dot1q" | "dot1ad" | <number>,
--           vlans = {
--             {
--               [ description = <description>, ]
--               vid = <vid>,
--               [ afs = {
--                   ipv6 = {
--                     address = <address>,
--                     next_hop = <next_hop>,
--                     [ next_hop_mac = <next_hop_mac> ]
--                   }
--                 } ]
--              },
--              ...
--           }
--         } ]
--     }
--   },
--   vpls = {
--     <vpls1> = {
--       [ description = <description> ,]
--       vc_id = <vc_id>,
--       mtu = <mtu>,
--       address = <ipv6-address>,
--       uplink = <int>,
--       bridge = {
--         type = "flooding"|"learning",
--         [ config = <bridge-config> ]
--       },
--       [ tunnel = <tunnel-config>, ]
--       [ cc = <cc-config>, ]
--       ac = {
--         <ac1> = <int>
--         <ac2> = ...
--       },
--       pw = {
--         <pw1> = {
--            address = <ipv6-address>,
--            [ tunnel = <tunnel-config> ],
--            [ cc = <cc-config> ]
--         },
--         <pw2> = ...
--       },
--     },
--     <vpls2> = ...
--   }
-- }

module(...,package.seeall)
local ffi = require("ffi")
local lib = require("core.lib")
local usage_msg = require("program.l2vpn.README_inc")
local core_config = require("core.config")
local vmux = require("apps.vlan.vlan").VlanMux
local nd_light = require("apps.ipv6.nd_light").nd_light
local ipv6 = require("lib.protocol.ipv6")
local pseudowire = require("program.l2vpn.pseudowire").pseudowire
local dispatch = require("program.l2vpn.dispatch").dispatch
local shm = require("core.shm")
local counter = require("core.counter")
local macaddress = require("lib.macaddress")
local sink = require("apps.basic.basic_apps").Sink
local ifmib = require("lib.ipc.shmem.iftable_mib")
local S = require("syscall")

local bridge_types = { flooding = true, learning = true }

function usage ()
   print(usage_msg)
   main.exit(0)
end

function add_app (c, name, class, arg)
   assert(not c.apps[name], "Duplicate app name "..name)
   c.apps[name] = { class = class, arg = arg }
end

function add_link (c, link_spec)
   table.insert(c.links, link_spec)
end

function create_config (c)
   local cc = core_config.new()
   for name, config in pairs(c.apps) do
      core_config.app(cc, name, config.class, config.arg)
   end
   for _, link_spec in ipairs(c.links) do
      core_config.link(cc, link_spec)
   end
   return cc
end

local function ipv6_pton (addr)
   if type(addr) == "string" then
      return ipv6:pton(addr)
   else
      return addr
   end
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
local driver_helpers = {
   ['apps.intel_mp.intel_mp.Intel'] = {
      link_names = function ()
         return 'input', 'output'
      end,
      stats_path = function (driver)
         return driver.stats.path
      end
   },
   ['apps.tap.tap.Tap'] = {
      link_names = function ()
         return 'input', 'output'
      end,
      stats_path = function (driver)
         return driver.shm.path
      end
   },
}

function parse_if (c, config, app_name)
   assert(config.name, "Missing interface name for interface app"..app_name)
   assert(not c.ifaces[config.name], "Duplicate interface name "..config.name)
   print("Setting up interface "..config.name)
   print("  Description: "..(config.description or "<none>"))
   c.ifaces[config.name] = { app_name = app_name,
                           description = config.description }
   local iface = c.ifaces[config.name]

   -- NIC driver
   assert(config.driver, "Missing driver configuration")
   local drv_c = config.driver
   assert(drv_c.path and drv_c.name and
             drv_c.config, "Incomplete driver configuration")
   if type(drv_c.config) == "table" then
      if (drv_c.config.pciaddr) then
         print("  PCI address: "..drv_c.config.pciaddr)
      end
      drv_c.config.mtu = config.mtu
      if drv_c.extra_config then
         -- If present, extra_config must be a table, whose elements
         -- are merged with the regular config.  This feature allows
         -- for more flexibility when the configuration is created by
         -- a Lua-agnostic layer on top, e.g. by a NixOS module
         assert(type(drv_c.extra_config) == "table",
                "Driver extra configuration must be a table")
         for k, v in pairs(drv_c.extra_config) do
            drv_c.config[k] = v
         end
      end
   end
   add_app(c, app_name, require(drv_c.path)[drv_c.name], drv_c.config)

   local driver_helper = driver_helpers[drv_c.path.."."..drv_c.name]
   assert(driver_helper,
          "Unsupported driver (missing driver helper)"
             ..drv_c.path.."."..drv_c.name)
   iface.driver_helper = driver_helper
   local input, output = driver_helper.link_names()
   local from_if = app_name.."."..output
   local to_if = app_name.."."..input

   -- L2 configuration (MTU, trunk)
   print("  L2 configuration")
   assert(config.mtu, "Missing MTU")
   print("    MTU: "..config.mtu)
   iface.mtu = config.mtu
   local trunk = config.trunk or { enable = false }
   assert(type(trunk) == "table", "Trunk configuration must be a table")

   local afs = {}
   afs.ipv6 = function (config, vid, ports_in, indent)
      assert(config.address, "Missing address")
      assert(config.next_hop, "Missing next-hop")
      -- FIXME: check fo uniqueness of subnet
      print(indent.."    Address: "..config.address.."/64")
      print(indent.."    Next-Hop: "..config.next_hop)
      if config.next_hop_mac then
         print(indent.."    Next-Hop MAC address: "
                  ..config.next_hop_mac)
      end
      local nd_app_name = "nd_"..app_name..((vid and "_"..vid) or '')
      c.nd2if_apps[nd_app_name] = app_name
      add_app(c, nd_app_name, nd_light,
              { local_ip  = config.address,
                local_mac = "00:00:00:00:00:00",
                remote_mac = config.next_hop_mac,
                next_hop = config.next_hop,
                quiet = true })
      local ports_out = {
         input = nd_app_name..".south",
         output = nd_app_name..".south"
      }
      add_link(c, ports_in.output.." -> "..nd_app_name..".south")
      add_link(c, nd_app_name..".south -> "..ports_in.input)
      return {
         input = nd_app_name..".north",
         output = nd_app_name..".north"
      }
   end

   local function process_afs (afs_c, vid, ports, indent)
      print(indent.."  Address family configuration")
      local config = afs_c.ipv6
      assert(config, "IPv6 configuration missing")
      print(indent.."    IPv6")
      return afs.ipv6(config, vid, ports, indent.."  ")
   end

   if trunk.enable then
      -- The interface is configured as a VLAN trunk. Attach an
      -- instance of the VLAN multiplexer.
      print("    Trunking mode: enabled")
      assert(not config.afs,
             "Address family configuration not allowed in trunking mode")
      local encap = trunk.encapsulation or "dot1q"
      assert(encap == "dot1q" or encap == "dot1ad" or
                (type(encap) == "number"),
             "Illegal encapsulation mode "..encap)
      print("      Encapsulation "..
               (type(encap) == "string" and encap
                   or string.format("ether-type 0x%04x", encap)))
      local vmux_app_name = "vmux_"..app_name
      add_app(c, vmux_app_name, vmux, { encapsulation = encap })
      add_link(c, from_if.." -> "..vmux_app_name..".trunk")
      add_link(c, vmux_app_name..".trunk -> "..to_if)

      -- Process VLANs and create sub-interfaces
      iface.vlans = {}
      assert(trunk.vlans, "Missing VLAN configuration on trunk port")
      print("  Sub-Interfaces")
      local vlans = {}
      for n, vlan_c in ipairs(trunk.vlans) do
         local vid = vlan_c.vid
         assert(vid, "Missing VLAN ID for sub-interface #"..n)
         assert(type(vid) == "number" and vid >= 0 and vid < 4095,
                "Invalid VLAN ID "..vid.." for sub-interface #"..n)
         if vlans[vid] then
            error("VLAN ID "..vid.." already assigned to sub-interface #"
                     ..vlans[vid])
         end
         vlans[vid] = n
         print("    "..config.name.."."..vid)
         if vlan_c.description then
            print("      Description: "..vlan_c.description)
         end
         print("      L2 configuration")
         print("        VLAN ID: "..(vid > 0 and vid or "<untagged>"))

         iface.vlans[vid] = {
            description = vlan_c.description,
            vmux_app = vmux_app_name
         }
         local link = (vid == 0 and 'native') or 'vlan'..vid
         local ports = {
            input = vmux_app_name.."."..link,
            output = vmux_app_name.."."..link
         }
         if vlan_c.afs then
            iface.vlans[vid].ports = process_afs(vlan_c.afs, vid, ports, "    ")
            iface.vlans[vid].l3 = true
         else
            iface.vlans[vid].ports = ports
            iface.vlans[vid].l3 = false
         end
      end
   else
      print("    Trunking mode: disabled")
      local ports = {
         input = to_if,
         output = from_if
      }
      if config.afs then
         iface.ports = process_afs(config.afs, nil, ports, "")
         iface.l3 = true
      else
         iface.ports = ports
         iface.l3 = false
      end
   end
end

-- Parse an interface specifier, which must be of the form "<name>" or
-- "<name>.<vid>", where <name> must not contain any dots.  Return the
-- name and VID
function parse_int_spec (spec)
   local name, vid
   if spec:match("%.") then
      name, vid = spec:match("([%w/]+)%.([%d]+)")
      assert(name and vid, "Invalid interface specifier "..spec)
   else
      name = spec
   end
   return name, (vid and tonumber(vid)) or nil
end

function parse_config (c, main_config)
   local interfaces = main_config.interfaces
   assert(interfaces, "Missing interfaces configuration")
   for n, config in ipairs(interfaces) do
      parse_if(c, config, "intf"..n)
   end

   assert(main_config.vpls, "Missing vpls configuration")
   local uplinks = {}
   for vpls, vpls_c in pairs(main_config.vpls) do
      local pws, acs = {}, {}
      print("Creating VPLS instance "..vpls
            .." ("..(vpls_c.description or "<no description>")..")")
      assert(vpls_c.mtu, "Missing MTU")
      print("  MTU: "..vpls_c.mtu)
      assert(vpls_c.vc_id, "Missing VC ID")
      print("  VC ID: "..vpls_c.vc_id)
      assert(vpls_c.address, "Missing address")
      print("  Address: "..vpls_c.address)

      local uplink = vpls_c.uplink
      assert(uplink, "Missing uplink configuarion")
      assert(type(uplink) == "string",
             "Uplink interface specifier must be a string")
      local iface, vid = parse_int_spec(uplink)
      local uplink_iface = c.ifaces[iface]
      assert(uplink_iface, "Interface "..iface.." referenced "
                .."by uplink does not exist")
      print("  Uplink is on "..uplink)
      if not uplinks[uplink] then
         -- The same uplink can be used by multiple VPLS instances.
         -- We only need to do this check once.
         uplinks[uplink] = {}
         if vid then
            assert(uplink_iface.vlans, "Uplink references a sub-interface "
                      .."on a non-trunk port")
            local vlan = uplink_iface.vlans[vid]
            assert(vlan, "Sub-Interface "..vid.." of "..iface..
                      " referenced by uplink does not exist")
            assert(vlan.l3, "Sub-Interafce "..vid.." of "..iface..
                   " is L2 while L3 was expected")
            vlan.used = true
            uplinks[uplink].iface = vlan
            uplinks[uplink].app_name = "dispatcher_"
               ..uplink_iface.app_name.."_vlan"..vid
         else
            assert(uplink_iface.l3 , "Interface "..uplink.." is L2 while "..
                      "L3 was expected")
            uplink_iface.used = true
            uplinks[uplink].iface = uplink_iface
            uplinks[uplink].app_name = "dispatcher_"
               ..uplink_iface.app_name
         end
      end

      local bridge_config = { ports = {},
                              split_horizon_groups = { pw = {} } }
      if (vpls_c.bridge) then
         local bridge = vpls_c.bridge
         if bridge.type then
            assert(bridge_types[bridge.type],
                   "Invalid bridge type: "..bridge.type)
         else
            bridge.type = "flooding"
         end
         bridge_config.config = bridge.config
      end
      assert(vpls_c.address, "Missing address")
      vpls_address = ipv6_pton(vpls_c.address)
      assert(vpls_c.ac, "Missing ac configuration")
      assert(vpls_c.pw, "Missing pseudowire configuration")

      print("  Creating attachment circuits")
      for name, ac_iface_name in pairs(vpls_c.ac) do
         assert(ac_iface_name, "Missing configuration for AC "..name)
         assert(type(ac_iface_name) == "string",
                "AC interface specifier must be a string")
         local ac_name = vpls.."_ac_"..name
         print("    "..ac_name)
         local iface, vid = parse_int_spec(ac_iface_name)
         local ac_iface = c.ifaces[iface]
         assert(ac_iface, "Interface "..iface.." referenced "
                   .."by AC "..name.." does not exist")
         print("      AC is on "..ac_iface_name)
         local ac = { name = ac_name, iface_name = ac_iface_name }
         if vid then
            assert(ac_iface.vlans, "AC references a sub-interface "
                      .."on a non-trunk port")
            local vlan = ac_iface.vlans[vid]
            assert(vlan, "Sub-Interface "..vid.." of "..iface
                      .." referenced by AC "..name.." does not exist")
            assert(not vlan.l3,
                   "Sub-Interface "..vid.." is L3 while "..
                      "L2 was expected")
            vlan.used = true
            ac.iface = vlan
         else
            assert(not ac_iface.l3,
                   "Interface "..iface.." is L3 while "..
                      "L2 was expected")
            ac_iface.used = true
            ac.iface = ac_iface
         end

         -- The effective MTU of the AC must match the MTU of the
         -- VPLS, where the effective MTU is given by
         --
         --   - The actual MTU if the AC is not a trunk
         --   - The actual MTU minus 4 if the AC is a trunk
         --
         -- If the AC is the native VLAN on a trunk, the actual packets
         -- can carry frames which exceed the nominal MTU by 4 bytes.
         local effective_mtu = (ac_iface.vlans and ac_iface.mtu-4) or ac_iface.mtu
         assert(vpls_c.mtu == effective_mtu, "MTU mismatch between "
                   .."VPLS ("..vpls_c.mtu..") and interface "
                   ..iface.." (real: "..ac_iface.mtu..", effective: "
                   ..effective_mtu..")")
         table.insert(bridge_config.ports, ac_name)
         table.insert(acs, ac)
      end

      local npws = 0
      for _, _ in pairs(vpls_c.pw) do
        npws = npws + 1
      end
      print("  Creating pseudowires")
      local tunnel_config = vpls_c.tunnel
      for pw_name, pw_config in pairs(vpls_c.pw) do
         assert(tunnel_config or pw_config.tunnel,
                "Missing tunnel configuration for pseudowire "..pw_name
                   .." and no default specified")
         assert(pw_config.address,
                "Missing remote address configuration for pseudowire "..pw_name)
         pw_address = ipv6_pton(pw_config.address)
         local pw_app_name = vpls..'_pw_'..pw_name
         print("    "..pw_app_name)
         print("      Address: "..pw_config.address)
         add_app(c, pw_app_name, pseudowire,
                 { name = pw_app_name,
                   vc_id = vpls_c.vc_id,
                   mtu = vpls_c.mtu,
                   shmem_dir = main_config.shmem_dir,
                   description = vpls_c.description,
                   -- For a p2p VPN, pass the name of the AC
                   -- interface so the PW module can set up the
                   -- proper service-specific MIB
                   interface = (npws == 1 and #acs == 1 and
                                   acs[1].iface_name) or '',
                   transport = { type = 'ipv6',
                                 src = vpls_address,
                                 dst = pw_address },
                   tunnel = pw_config.tunnel or tunnel_config,
                   cc = pw_config.cc or vpls_c.cc or nil })
         table.insert(pws, pw_app_name)
         table.insert(bridge_config.split_horizon_groups.pw, pw_app_name)
         if not uplinks[uplink].dispatch then
            uplinks[uplink].dispatch = {}
         end
         uplinks[uplink].dispatch[pw_app_name] = { source      = pw_address,
                                                   destination = vpls_address }
      end

      if #pws == 1 and #acs == 1 then
         -- Optimize a two-port bridge as a direct attachment of the
         -- PW and AC
         print("  Short-Circuit "..pws[1].." <-> "..acs[1].name)
         local pw, ac = pws[1], acs[1].iface
         add_link(c, pw..".ac -> "..ac.ports.input)
         add_link(c, ac.ports.output.." -> "..pw..".ac")
      else
         local vpls_bridge = vpls.."_bridge"
         print("  Creating bridge "..vpls_bridge)
         add_app(c, vpls_bridge,
                 require("apps.bridge."..vpls_c.bridge.type).bridge,
                 bridge_config)
         for _, pw in ipairs(pws) do
            add_link(c, pw..".ac -> "..vpls_bridge.."."..pw)
            add_link(c, vpls_bridge.."."..pw.." -> "..pw..".ac")
         end
         for _, ac in ipairs(acs) do
            add_link(c, vpls_bridge.."."..ac.name.." -> "..ac.iface.ports.input)
            add_link(c, ac.iface.ports.output.." -> "..vpls_bridge.."."..ac.name)
         end
      end
   end

   -- Create dispatchers and attach PWs
   for uplink, uplink_c in pairs(uplinks) do
      local app_name = uplink_c.app_name
      add_app(c, app_name, dispatch, uplink_c.dispatch)
      for pw, pw_c in pairs(uplink_c.dispatch) do
         add_link(c, app_name.."."..pw.." -> "..pw..".uplink")
         add_link(c, pw..".uplink -> "..app_name.."."..pw)
      end
      local if_ports = uplink_c.iface.ports
      add_link(c, if_ports.output.." -> "..app_name..".south")
      add_link(c, app_name..".south -> "..if_ports.input)
   end

   -- Attach a sink to unused interfaces.  This discards all packets
   -- coming from the interface and never sends any packets to the
   -- interface, since the Sink app does not use its "input" port for
   -- sending.
   for _, iface in pairs(c.ifaces) do
      local function attach_sink (ports, vid)
         local sink_app = iface.app_name.."_sink_"..(vid or '')
         add_app(c, sink_app, sink)
         add_link(c, ports.output.." -> "..sink_app..".input")
         add_link(c, sink_app..".input -> "..ports.input)
      end
      if iface.vlans then
         for vid, vlan in pairs(iface.vlans) do
            if not vlan.used then
               attach_sink(vlan.ports, vid)
            end
         end
      else
         if not iface.used then
            attach_sink(iface.ports, nil)
         end
      end
   end
end

function instantiate_config (main_config)
   local c = {
      -- Table of parsed interfaces keyed by the names of the interfaces.
      -- Each entry is a table with the keys
      --  app_name
      --  stats
      --  description
      --  ports (nil if trunk)
      --  l3 (nil if trunk)
      --  vlans
      --    description
      --    vmux_app
      --    ports
      --    l3
      --  driver_helper
      --  mtu
      ifaces = {},
      
      -- Mapping of ND app names to the names of the underlying physical
      -- interface apps. Needed to re-configure the proper source MAC
      -- addresses after the interfaces have been configured
      nd2if_apps = {},

      -- This table stores the list of apps that need to be
      -- instantiated. The keys are the names of the apps (as passed to
      -- core.config.app()) and the values are tables with elements "class"
      -- and "arg" as required by core.config.app()
      apps = {},

      -- An array of link specs that can be passed directly to
      -- core.config.link
      links = {},
   }

   parse_config(c, main_config)
   engine.configure(create_config(c))

   -- For each interface, attach to the shm frame that stores
   -- the statistics counters
   for _, iface in pairs(c.ifaces) do
      local app = engine.app_table[iface.app_name]
      iface.stats = shm.open_frame(iface.driver_helper.stats_path(app))
   end
   -- Commit all counters to the backing store to make them available
   -- immediately through the read-only frames we just created
   counter.commit()

   -- The physical MAC addresses of the interfaces are only known
   -- after the drivers have been configured.  We need to reconfigure
   -- all relevant ND apps to use those MAC addresses as their "local"
   -- MAC.
   for nd_app, if_app in pairs(c.nd2if_apps) do
      local stats = engine.app_table[if_app].stats
      c.apps[nd_app].arg.local_mac =
         macaddress:new(counter.read(stats.macaddr)).bytes
   end
   engine.configure(create_config(c))

   local snmp = main_config.snmp or { enable = false }
   if snmp.enable then
      for name, iface in pairs(c.ifaces) do
         -- Set up SNMP for physical interfaces
         local app = engine.app_table[iface.app_name]
         if app == nil then goto continue end
         local stats = iface.stats
         if stats then
            ifmib.init_snmp( { ifDescr = name,
                               ifName = name,
                               ifAlias = iface.description, },
               string.gsub(name, '/', '-'), stats,
               main_config.shmem_dir, snmp.interval or 5)
         else
            print("Can't enable SNMP for interface "..name
                   ..": no statistics counters available")
         end
         for vid, vlan in pairs(iface.vlans or {}) do
            -- Set up SNMP for sub-interfaces
            counter_t = ffi.typeof("struct counter")
            local counters = {}
            local function map (c)
               return (c and ffi.cast("struct counter *", c)) or nil
            end
            counters.type = counter_t()
            if vlan.l3 then
               counters.type.c = 0x1003ULL -- l3ipvlan
            else
               counters.type.c = 0x1002ULL -- l2vlan
            end
            if stats then
               -- Inherit the operational status, MAC address, MTU, speed
               -- from the physical interface
               counters.status = map(stats.status)
               counters.macaddr = map(stats.macaddr)
               counters.mtu = map(stats.mtu)
               counters.speed = map(stats.speed)
            end
            -- Create mappings to the counters of the relevant VMUX link
            local name = name.."."..vid
            local vmux = engine.app_table[vlan.vmux_app]
            local link = (vid == 0 and "native") or "vlan"..vid
            local rx = vmux.input[link]
            local tx = vmux.output[link]
            assert(rx and tx)
            local rstats = rx.stats
            local tstats = tx.stats
            -- The VMUX app replaces the physical network for a
            -- sub-interface.  Hence, its output is what the
            -- sub-interface receives and its input is what the
            -- sub-interface transmits to the "virtual wire".
            counters.rxpackets = map(tstats.txpackets)
            counters.rxbytes = map(tstats.txbytes)
            counters.rxdrop = map(tstats.txdrop)
            counters.txpackets = map(rstats.rxpackets)
            counters.txbytes = map(rstats.rxbytes)
            ifmib.init_snmp( { ifDescr = name,
                               ifName = name,
                               ifAlias = vlan.description, },
               string.gsub(name, '/', '-'), counters,
               main_config.shmem_dir, snmp.interval or 5)
         end
         ::continue::
      end
   end
end

local long_opts = {
   duration = "D",
   reconfig = "r",
   logfile = "l",
   debug = "d",
   jit = "j",
   help = "h",
}

function run (parameters)
   local duration = 0
   local reconfig = false
   local jit_conf = {}
   local opt = {}
   function opt.D (arg)
      if arg:match("^[0-9]+$") then
         duration = tonumber(arg)
      else
         usage()
      end
   end
   function opt.l (arg)
      local logfh = assert(io.open(arg, "a"))
      lib.logger_default.fh = logfh
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
      end
   end
   function opt.r (arg) reconfig = true end

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hdj:D:l:r", long_opts)
   if (reconfig and not (duration > 0)) then
      print("--reconfig requires --duration > 0 to take effect")
      usage()
   end

   -- Defaults: sizemcode=32, macmcode=512
   require("jit.opt").start('sizemcode=128', 'maxmcode=1024')
   if #parameters ~= 1 then usage () end

   local file = table.remove(parameters, 1)

   local engine_opts = { no_report = true }
   if duration ~= 0 then engine_opts.duration = duration end
   if jit_conf.p then
      require("jit.p").start(jit_conf.p.opts, jit_conf.p.file)
   end
   if jit_conf.dump then
      require("jit.dump").start(jit_conf.dump.opts, jit_conf.dump.file)
   end
   local mtime = 0
   local loop = true
   while loop do
      local stat, err = S.stat(file)
      if not stat then
         error("Can't stat "..file..": "..tostring(err))
      end
      if mtime ~= stat.mtime then
         -- This is a very crude and disruptive way to pick up changes
         -- of the configuration while the system is running. It
         -- requires setting -D to a reasonable non-zero value. By
         -- default, the configuration is instantiated only once and
         -- engine.main() runs indefinitely.
         print("Instantiating configuration")
         instantiate_config(assert(loadfile(file))())
         jit.flush()
      end
      mtime = stat.mtime
      engine.main(engine_opts)
      loop = reconfig
   end
   if jit_conf.p then
      require("jit.p").stop()
   end
end

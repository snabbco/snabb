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
-- to the interface via the "rx" and "tx" links of the driver.  For a
-- L3 interface, one of three possible neighbor discovery modules is
-- attached to the "rx" and "tx" links of the driver.  If dynamic ND
-- is selected in both directions, the nd_light module is selected.
-- If a static MAC address for the next-hop is configured and dynamic
-- inbound ND is selected, the ns_responder ND module is selected.  If
-- both sides use static MAC addresses, the nd_static module is
-- selected.  In either case, apps connect to the "north" links of the
-- ND module.
--
-- If the interface is in trunking mode, an instance of the VlanMux
-- app from apps.vlan.vlan is instantiated and its "trunk" port is
-- connected to the interface's "rx" and "tx" links.  For each
-- sub-interface that contains a L3 configuration, a ND module is
-- selected as described above and attached to the appropriate "vlan"
-- link of the VlanMux app (for vlan = 0, the corresponding VlanMux
-- link is called "native").
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
-- non-trunking mode, the interface driver's "rx" and "tx" links are
-- connected directly to the bridge module.  In trunking mode, the
-- corresponding "vlan" links of the VlanMux app are connected to the
-- bridge instead.
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

module(...,package.seeall)
local usage_msg = require("program.l2vpn.README_inc")
local lib = require("core.lib")
local app = require("core.app")
local c_config = require("core.config")
local nd = require("apps.ipv6.nd_light").nd_light
local dispatch = require("program.l2vpn.dispatch").dispatch
local pseudowire = require("program.l2vpn.pseudowire").pseudowire
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local vmux = require("apps.vlan.vlan").VlanMux

-- config = {
--   interfaces = {
--     {
--       name = <name>,
--       [ description = <description>, ]
--       driver = {
--         module = <module>,
--         config = {
--           pciaddr = <pciaddress>,
--           [ snmp = { directory = <snmp_dir> }, ]
--         },
--       },
--       mtu = <mtu>,
--       [ mac = <mac>, ]
--       [ -- only allowed if trunk.enable == false
--         afs = {
--           ipv6 = {
--             address = <address>,
--             next_hop = <next_hop>,
--             [ neighbor_mac = <neighbor_mac>,
--               [ neighbor_nd = true | false, ] ]
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
--                     [ neighbor_mac = <neighbor_mac>,
--                       [ neighbor_nd = true | false, ] ]
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
--       [ shmem_dir = <shmem_dir>, ]
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

local bridge_types = { flooding = true, learning = true }

local function ether_pton (addr)
   if type(addr) == "string" then
      return ethernet:pton(addr)
   else
      return addr
   end
end

local function ipv6_pton (addr)
   if type(addr) == "string" then
      return ipv6:pton(addr)
   else
      return addr
   end
end

local long_opts = {
   duration = "D",
   logfile = "l",
   debug = "d",
   jit = "j",
   help = "h",
}

function usage ()
   print(usage_msg)
   main.exit(0)
end

function parse_int_spec (spec)
   local intf, vid
   if spec:match("%.") then
      intf, vid = spec:match("([%w/]+)%.([%d]+)")
      assert(intf and vid, "Invalid interface specifier "..spec)
   else
      intf = spec
   end
   return intf, vid and tonumber(vid) or nil
end

local configured_ifs = {}
function config_if (c, afs, app_c)
   if not configured_ifs[c.name] then
      -- Physical interface
      c_config.app(app_c, c.name, c.module, c.config)

      -- Multiplexer for VLAN trunk
      if c.vmux then
         local vmux = c.vmux
         c_config.app(app_c, vmux.name, vmux.module, vmux.config)
         c_config.link(app_c, vmux.links[1])
         c_config.link(app_c, vmux.links[2])
      end
      configured_ifs[c.name] = true
   end

   if afs then
      if afs.ipv6 then
         -- ND for L3 (sub-)interfaces
         local nd = afs.ipv6.nd
         c_config.app(app_c, nd.name, nd.module, nd.config)
         c_config.link(app_c, nd.links[1])
         c_config.link(app_c, nd.links[2])
      end
      -- Add IPv4 here
   end
end

function parse_if (if_app_name, config)
   local result = { name = if_app_name, vlans = {} }
   print("Setting up interface "..config.name)
   print("  Description: "..(config.description or "<none>"))

   -- NIC driver
   assert(config.driver, "Missing driver configuration")
   local drv_c = config.driver
   assert(drv_c.module and drv_c.config, "Incomplete driver configuration")
   if (drv_c.config.pciaddr) then
      print("  PCI address: "..drv_c.config.pciaddr)
   end
   drv_c.config.mtu = config.mtu
   if drv_c.config.snmp then
      drv_c.config.snmp.ifAlias = config.description or nil
      drv_c.config.snmp.ifDescr = config.name
   end
   result.module = drv_c.module
   result.config = drv_c.config
   local l3_links = { input = if_app_name..".rx",
                      output = if_app_name..".tx" }

   -- L2 configuration (MTU, MAC, trunk)
   print("  L2 configuration")
   assert(config.mtu, "Missing MTU")
   print("    MTU: "..config.mtu)
   result.mtu = config.mtu
   if config.mac then
      local mac = config.mac
      config.mac = ether_pton(config.mac)
      print("    MAC: "..mac)
   end
   if not config.trunk then
      config.trunk = { enable = false }
   end
   local trunk = config.trunk
   assert(type(trunk) == "table")

   local function setup_ipv6 (ipv6, nd_app_name, mac, l3_links, indent)
      assert(ipv6.address, "Missing address")
      local c = { address = ipv6_pton(ipv6.address),
                  next_hop = ipv6_pton(ipv6.next_hop),
                  neighbor_mac = ipv6.neighbor_mac and
                     ether_pton(ipv6.neighbor_mac) or nil,
                  neighbor_nd = ipv6.neighbor_nd,
                  nd = { name = nd_app_name } }
      -- FIXME: check fo uniqueness of subnet
      print(indent.."    Address: "..ipv6.address.."/64")
      print(indent.."    Next-Hop: "..ipv6.next_hop)
      local nd_c = c.nd
      if c.neighbor_mac then
         print(indent.."    Using static neighbor MAC address "
                  ..ipv6.neighbor_mac)
         if c.neighbor_nd then
            print(indent.."    Using dynamic outbound ND")
            nd_c.module = require("apps.ipv6.ns_responder").ns_responder
            nd_c.config = { local_ip  = c.address,
                            local_mac = mac,
                            remote_mac = c.neighbor_mac }
         else
            print(indent.."    Dynamic outbound ND disabled")
            nd_c.module = require("apps.ipv6.nd_static").nd_static
            nd_c.config = { remote_mac  = c.neighbor_mac,
                            local_mac = mac }
         end
      else
         assert(ipv6.next_hop, "Missing next-hop")
         print(indent.."    Using dynamic ND")
         nd_c.module = nd
         nd_c.config = { local_ip  = ipv6.address,
                         local_mac = mac,
                         next_hop = ipv6.next_hop }
      end
      nd_c.links = { l3_links.output.." -> "..c.nd.name..".south",
                     c.nd.name..".south -> "..l3_links.input }
      return(c)
   end

   function process_afs (afs_c, vid, l3_links, nd_app_name, indent)
      local result = {}
      print(indent.."  Address family configuration")
      local ipv6 = afs_c.ipv6
      assert(ipv6, "Missing IPv6 configuration")
      print(indent.."    IPv6")
      assert(config.mac, "Missing MAC address in l2 configuration")
      result.ipv6 = setup_ipv6(ipv6, nd_app_name, config.mac, l3_links, indent.."  ")
      -- Add ipv4 processing here
      return result
   end

   if trunk.enable then
      -- The interface is configured as a VLAN trunk. Attach an
      -- instance of the VLAN multiplexer.
      print("    Trunking mode: enabled")
      assert(not config.afs,
             "afsAddress family configuration not allowed in trunking mode")
      local encap = trunk.encapsulation or "dot1q"
      assert(encap == "dot1q" or encap == "dot1ad" or
                (type(encap) == "number"),
             "Illegal encapsulation mode "..encap)
      print("      Encapsulation "..
               (type(encap) == "string" and encap
                   or string.format("ether-type 0x%04x", encap)))
      local vmux_app_name = "vmux_"..if_app_name
      result.vmux = {
         name = vmux_app_name,
         module = vmux,
         config = { encapsulation = encap },
         links = { l3_links.output.." -> "..vmux_app_name..".trunk",
                   vmux_app_name..".trunk -> "..l3_links.input }
      }
      -- Process VLANs and create sub-interfaces
      local vlans = trunk.vlans
      assert(vlans, "Missing VLAN configuration")
      print("  Sub-Interfaces")
      local vlans = {}
      for n, vlan_c in ipairs(trunk.vlans) do
         local vid = vlan_c.vid
         assert(vid, "Missing VLAN ID for sub-interface #"..n)
         assert(type(vid) == "number" and vid >= 0 and vid <4094,
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

         if vlan_c.afs then
            local link
            if vid == 0 then
               link = "native"
            else
               link = "vlan"..vid
            end
            result.vlans[vid] = process_afs(vlan_c.afs, vid,
                                           { input = vmux_app_name.."."..link,
                                             output = vmux_app_name.."."..link },
                                           "nd_"..if_app_name.."_"..vid,
                                           "    ")
         else
            result.vlans[vid] = { l2 = true }
         end
      end
   else
      print("    Trunking mode: disabled")
      if config.afs then
         result.afs = process_afs(config.afs, nil, l3_links, "nd_"..if_app_name, "")
      end
   end
   return config.name, result
end

function run (parameters)
   local duration = 0
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

   -- Parse command line arguments
   parameters = lib.dogetopt(parameters, opt, "hdj:D:l:", long_opts)
   -- Defaults: sizemcode=32, macmcode=512
   require("jit.opt").start('sizemcode=128', 'maxmcode=1024')
   if #parameters ~= 1 then usage () end

   local file = table.remove(parameters, 1)
   local conf_f = assert(loadfile(file))
   local config = conf_f()

   local c = c_config.new()
   local intfs = {}
   local interfaces = config.interfaces
   assert(interfaces, "Missing interfaces configuration")
   for n, conf in ipairs(interfaces) do
      assert(conf.name, "Missing interface name for interface #"..n)
      local name, intf = parse_if("int"..n, conf)
      assert(not intfs[name], "Duplicate interface name "..name)
      intfs[name] = intf
   end

   local uplinks = {}
   local vpls_bridges = {}
   assert(config.vpls, "Missing vpls configuration")
   for vpls, vpls_c in pairs(config.vpls) do
      print("Creating VPLS instance "..vpls
            .." ("..(vpls_c.description or "<no description>")..")")
      assert(vpls_c.mtu, "Missing MTU")
      assert(vpls_c.vc_id, "Missing VC ID")
      print("  MTU: "..vpls_c.mtu)
      print("  VC ID: "..vpls_c.vc_id)

      local uplink = vpls_c.uplink
      assert(uplink, "Missing uplink configuarion")
      assert(type(uplink) == "string",
             "Uplink interface specifier must be a string")
      local intf, vid = parse_int_spec(uplink)
      assert(intfs[intf], "Interface "..intf.." referenced "
                .."by uplink does not exist")
      print("  Uplink is on "..uplink)
      local afs
      if vid then
         local vlan = intfs[intf].vlans[vid]
         assert(vlan, "Sub-Interface "..vid.." of "..intf..
                   " referenced by uplink does not exist")
         assert(not vlan.l2, "Sub-Interafce "..vid.." of "..intf..
                " is L2 while L3 was expected")
         afs = vlan
      else
         afs = intfs[intf].afs
         assert(afs, "Interface "..uplink.." is L2 while "..
                   "L3 was expected")
      end
      if not uplinks.uplink then
         uplinks[uplink] = afs
         config_if(intfs[intf], afs, c)
      end

      local bridge_config = { ports = {},
                              split_horizon_groups = { pw = {} } }
      if (vpls_c.bridge) then
         local bridge = vpls_c.bridge
         if bridge.type then
            assert(bridge_types[bridge.type],
                   "invalid bridge type: "..bridge.type)
         else
            bridge.type = "flooding"
         end
         bridge_config.config = bridge.config
      end
      assert(vpls_c.address, "Missing address")
      vpls_c.address = ipv6_pton(vpls_c.address)
      assert(vpls_c.ac, "Missing ac configuration")
      assert(vpls_c.pw, "Missing pseudowire configuration")

      local pws = {}
      local acs = {}
      local tunnel_config = vpls_c.tunnel

      print("  Creating attachment circuits")
      for ac, ac_config in pairs(vpls_c.ac) do
         assert(ac_config, "Missing configuration for AC "..ac)
         assert(type(ac_config) == "string",
                "AC interface specifier must be a string")
         local ac_name = vpls.."_ac_"..ac
         print("    "..ac_name)
         local intf, vid = parse_int_spec(ac_config)
         assert(intfs[intf], "Interface "..intf.." referenced "
                   .."by AC "..ac.." does not exist")
         print("      AC is on "..ac_config)
         local ac_intf = intfs[intf]
         local l2
         if vid then
            local vlan = ac_intf.vlans[vid]
            assert(vlan, "Sub-Interface "..vid.." of "..intf
                   .." referenced by AC "..ac.." does not exist")
            assert(vlan.l2,
                   "Sub-Interface "..vid.." is L3 while "..
                      "L2 was expected")
            l2 = vlan
         else
            l2 = ac_intf
         end
         if l2.ac then
            error("Interface "..ac_config
                     .." already assigned to AC "..vlan.ac.ac
                     .." of VPLS instance "..vlan.ac.vpls)
         end
         l2.ac = { ac = ac, vpls = vpls }

         -- The effective MTU of the AC must match the MTU of the
         -- VPLS, where the effective MTU is given by
         --
         --   - The actual MTU if the AC is not a trunk
         --   - The actual MTU minus 4 if the AC is a trunk
         --
         -- If the AC is the native VLAN on a trunk, the actual packets
         -- can carry frames which exceed the nominal MTU by 4 bytes.
         local effective_mtu = ac_intf.vmux and ac_intf.mtu-4 or ac_intf.mtu
         assert(vpls_c.mtu == effective_mtu, "MTU mismatch between "
                   .."VPLS ("..vpls_c.mtu..") and interface "
                   ..intf.." (real: "..ac_intf.mtu..", effective: "
                   ..effective_mtu..")")
         config_if(ac_intf, nil, c)
         local ac_input, ac_output
         if ac_intf.vmux then
            ac_input = ac_intf.vmux.name..".".."vlan"..vid
            ac_output = ac_intf.vmux.name..".".."vlan"..vid
         else
            ac_input = ac_intf.name..".rx"
            ac_output = ac_intf.name..".tx"
         end
         table.insert(bridge_config.ports, ac_name)
         table.insert(acs, { name = ac_name,
                             intf = ac_intf,
                             input = ac_input,
                             output = ac_output })
      end

      print("  Creating pseudowire instances")
      for pw, pw_config in pairs(vpls_c.pw) do
         assert(tunnel_config or pw_config.tunnel,
                "Missing tunnel configuration for pseudowire "..pw
                   .." and no default specified")
         assert(pw_config.address,
                "Missing remote address configuration for pseudowire "..pw)
         pw_config.address = ipv6_pton(pw_config.address)
         local pw = vpls..'_pw_'..pw
         print("    "..pw)
         c_config.app(c, pw, pseudowire,
                      { name = pw,
                        vc_id = vpls_c.vc_id,
                        mtu = vpls_c.mtu,
                        shmem_dir = vpls_c.shmem_dir or nil,
                        description = vpls_c.description,
                        -- For a p2p VPN, pass the name of the AC
                        -- interface so the PW module can set up the
                        -- proper service-specific MIB
                        interface = (#vpls_c.pw == 1 and
                                        #acs == 1 and
                                        acs[1].intf.config.name) or '',
                        transport = { type = 'ipv6',
                                      src = vpls_c.address,
                                      dst = pw_config.address },
                        tunnel = pw_config.tunnel or tunnel_config,
                        cc = pw_config.cc or vpls_c.cc or nil })
         table.insert(pws, pw)
         table.insert(bridge_config.split_horizon_groups.pw, pw)
         if not uplinks[uplink].dispatch then
            uplinks[uplink].dispatch = {}
         end
         uplinks[uplink].dispatch[pw] = { source      = pw_config.address,
                                          destination = vpls_c.address }
      end

      if #pws == 1 and #acs == 1 then
         -- Optimize a two-port bridge as a direct attachment of the
         -- PW and AC
         print("  Short-Circuit "..pws[1].." <-> "..acs[1].name)
         c_config.link(c, pws[1]..".ac -> "..acs[1].input)
         c_config.link(c, acs[1].output.." -> "..pws[1]..".ac")
      else
         local vpls_bridge = vpls.."_bridge"
         table.insert(vpls_bridges, vpls_bridge)
         print("  Creating bridge "..vpls_bridge)
         c_config.app(c, vpls_bridge,
                      require("apps.bridge."..vpls_c.bridge.type).bridge,
                      bridge_config)
         for _, pw in ipairs(pws) do
            c_config.link(c, pw..".ac -> "..vpls_bridge.."."..pw)
            c_config.link(c, vpls_bridge.."."..pw.." -> "..pw..".ac")
         end
         for _, ac in ipairs(acs) do
            c_config.link(c, vpls_bridge.."."..ac.name.." -> "..ac.input)
            c_config.link(c, ac.output.." -> "..vpls_bridge.."."..ac.name)
         end
      end
   end

   -- Create dispatchers for active uplinks and attach PWs
   for uplink, uplink_c in pairs(uplinks) do
      local intf, vid = parse_int_spec(uplink)
      local dispatcher = "dispatcher_"..intfs[intf].name
      c_config.app(c, dispatcher, dispatch, uplink_c.dispatch)
      for pw, pw_c in pairs(uplink_c.dispatch) do
         c_config.link(c, dispatcher.."."..pw.." -> "..pw..".uplink")
         c_config.link(c, pw..".uplink -> "..dispatcher.."."..pw)
      end
      if uplink_c.ipv6 then
         local nd = uplink_c.ipv6.nd
         c_config.link(c, nd.name..".north -> "..dispatcher..".south")
         c_config.link(c, dispatcher..".south -> "..nd.name..".north")
      end
   end
   engine.configure(c)
   -- Remove when the app link() method lands on the l2vpn branch
   for _, bridge in ipairs(vpls_bridges) do
      engine.app_table[bridge]:post_config()
   end
   for _, intf in pairs(intfs) do
      if intf.vmux and engine.app_table[intf.vmux.name] then
         engine.app_table[intf.vmux.name]:link()
      end
   end

   local engine_opts = {}
   if duration ~= 0 then engine_opts.duration = duration end
   jit.flush()
   if jit_conf.p then
      require("jit.p").start(jit_conf.p.opts, jit_conf.p.file)
   end
   if jit_conf.dump then
      require("jit.dump").start(jit_conf.dump.opts, jit_conf.dump.file)
   end
   engine.main(engine_opts)
   if jit_conf.p then
      require("jit.p").stop()
   end
end

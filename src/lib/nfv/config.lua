module(...,package.seeall)

local Intel82599 = require("apps.intel.intel_app").Intel82599
local VhostUser = require("apps.vhost.vhost_user").VhostUser
local PacketFilter = require("apps.packet_filter.packet_filter").PacketFilter
local RateLimiter = require("apps.rate_limiter.rate_limiter").RateLimiter
local nd_light = require("apps.ipv6.nd_light").nd_light
local L2TPv3 = require("apps.keyed_ipv6_tunnel.tunnel").SimpleKeyedTunnel
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")

-- Return name of port in <port_config>.
function port_name (port_config)
   return port_config.port_id:gsub("-", "_")
end

-- Compile app configuration from <file> for <pciaddr> and vhost_user
-- <socket>. Returns configuration and zerocopy pairs.
function load (file, pciaddr, sockpath)
   local ports = lib.load_conf(file)
   local c = config.new()
   for _,t in ipairs(ports) do
      local vlan, mac_address = t.vlan, t.mac_address
      local name = port_name(t)
      local NIC = "NIC_"..name
      local Virtio = "Virtio_"..name
      config.app(c, NIC, Intel82599, {pciaddr = pciaddr,
                                      vmdq = true,
                                      macaddr = mac_address,
                                      vlan = vlan})
      config.app(c, Virtio, VhostUser, {socket_path=sockpath:format(t.port_id)})
      local VM_rx, VM_tx = Virtio..".rx", Virtio..".tx"
      if t.ingress_filter then
         local Filter = "Filter_in_"..name
         config.app(c, Filter, PacketFilter, t.ingress_filter)
         config.link(c, Filter..".tx -> " .. VM_rx)
         VM_rx = Filter..".rx"
      end
      if t.egress_filter then
         local Filter = 'Filter_out_'..name
         config.app(c, Filter, PacketFilter, t.egress_filter)
         config.link(c, VM_tx..' -> '..Filter..'.rx')
         VM_tx = Filter..'.tx'
      end
      if t.tunnel and t.tunnel.type == "L2TPv3" then
         local Tunnel = "Tunnel_"..name
         local conf = {local_address = t.tunnel.local_ip,
                       remote_address = t.tunnel.remote_ip,
                       local_cookie = t.tunnel.local_cookie,
                       remote_cookie = t.tunnel.remote_cookie,
                       local_session = t.tunnel.session}
         config.app(c, Tunnel, L2TPv3, conf)
         -- Setup IPv6 neighbor discovery/solicitation responder.
         -- This will talk to our local gateway.
         local ND = "ND_"..name
         config.app(c, ND, nd_light,
                    {local_mac = mac_address,
                     local_ip = t.tunnel.local_ip,
                     next_hop = t.tunnel.next_hop})
         -- VM -> Tunnel -> ND <-> Network
         config.link(c, VM_tx.." -> "..Tunnel..".decapsulated")
         config.link(c, Tunnel..".encapsulated -> "..ND..".north")
         -- Network <-> ND -> Tunnel -> VM
         config.link(c, ND..".north -> "..Tunnel..".encapsulated")
         config.link(c, Tunnel..".decapsulated -> "..VM_rx)
         VM_rx, VM_tx = ND..".south", ND..".south"
      end
      if t.rx_police_gbps then
         local QoS = "QoS_"..name
         local rate = t.rx_police_gbps * 1e9 / 8
         config.app(c, QoS, RateLimiter, {rate = rate, bucket_capacity = rate})
         config.link(c, VM_tx.." -> "..QoS..".input")
         VM_tx = QoS..".output"
      end
      config.link(c, NIC..".tx -> "..VM_rx)
      config.link(c, VM_tx.." -> "..NIC..".rx")
   end

   -- Return configuration c, and zerocopy pairs.
   return c
end

-- Apply configuration <c> to engine and reset <zerocopy> buffers.
function apply (c, zerocopy)
--   print(config.graphviz(c))
--   main.exit(0)
   engine.configure(c)
end

function selftest ()
   print("selftest: lib.nfv.config")
   local pcideva = os.getenv("SNABB_TEST_INTEL10G_PCIDEVA")
   if not pcideva then
      print("SNABB_TEST_INTEL10G_PCIDEVA was not set\nTest skipped")
      os.exit(engine.test_skipped_code)
   end
   engine.log = true
   for i, confpath in ipairs({"test_fixtures/nfvconfig/switch_nic/x",
                              "test_fixtures/nfvconfig/switch_filter/x",
                              "test_fixtures/nfvconfig/switch_qos/x",
                              "test_fixtures/nfvconfig/switch_tunnel/x",
                              "test_fixtures/nfvconfig/scale_up/y",
                              "test_fixtures/nfvconfig/scale_up/x",
                              "test_fixtures/nfvconfig/scale_change/x",
                              "test_fixtures/nfvconfig/scale_change/y"})
   do
      print("testing:", confpath)
      apply(load(confpath, pcideva, "/dev/null"))
      engine.main({duration = 0.25})
   end
end

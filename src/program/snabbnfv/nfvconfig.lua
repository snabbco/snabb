module(...,package.seeall)

local VhostUser = require("apps.vhost.vhost_user").VhostUser
local PcapFilter = require("apps.packet_filter.pcap_filter").PcapFilter
local RateLimiter = require("apps.rate_limiter.rate_limiter").RateLimiter
local nd_light = require("apps.ipv6.nd_light").nd_light
local L2TPv3 = require("apps.keyed_ipv6_tunnel.tunnel").SimpleKeyedTunnel
local pci = require("lib.hardware.pci")
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")

-- Return name of port in <port_config>.
function port_name (port_config)
   return port_config.port_id:gsub("-", "_")
end

-- Compile app configuration from <file> for <pciaddr> and vhost_user
-- <socket>. Returns configuration.
function load (file, pciaddr, sockpath)
   local device_info = pci.device_info(pciaddr)
   if not device_info then
      print(format("could not find device information for PCI address %s", pciaddr))
      main.exit(1)
   end

   local ports = lib.load_conf(file)
   local c = config.new()
   for _,t in ipairs(ports) do
      local vlan, mac_address = t.vlan, t.mac_address
      local name = port_name(t)
      local NIC = name.."_NIC"
      local Virtio = name.."_Virtio"
      local vmdq = true
      if not t.mac_address then
         if #ports ~= 1 then
            error("multiple ports defined but promiscuous mode requested for port: "..name)
         end
        vmdq = false
      end
      config.app(c, NIC, require(device_info.driver).driver,
                 {pciaddr = pciaddr,
                  vmdq = vmdq,
                  macaddr = mac_address,
                  vlan = vlan})
      config.app(c, Virtio, VhostUser, {socket_path=sockpath:format(t.port_id)})
      local VM_rx, VM_tx = Virtio..".rx", Virtio..".tx"
      if t.tx_police_gbps then
         local TxLimit = name.."_TxLimit"
         local rate = t.tx_police_gbps * 1e9 / 8
         config.app(c, TxLimit, RateLimiter, {rate = rate, bucket_capacity = rate})
         config.link(c, VM_tx.." -> "..TxLimit..".input")
         VM_tx = TxLimit..".output"
      end
      -- If enabled, track allowed connections statefully on a per-port basis.
      -- (The table tracking connection state is named after the port ID.)
      local pf_state_table = t.stateful_filter and name
      if t.ingress_filter then
         local Filter = name.."_Filter_in"
         config.app(c, Filter, PcapFilter, { filter = t.ingress_filter,
                                             state_table = pf_state_table })
         config.link(c, Filter..".tx -> " .. VM_rx)
         VM_rx = Filter..".rx"
      end
      if t.egress_filter then
         local Filter = name..'_Filter_out'
         config.app(c, Filter, PcapFilter, { filter = t.egress_filter,
                                             state_table = pf_state_table })
         config.link(c, VM_tx..' -> '..Filter..'.rx')
         VM_tx = Filter..'.tx'
      end
      if t.tunnel and t.tunnel.type == "L2TPv3" then
         local Tunnel = name.."_Tunnel"
         local conf = {local_address = t.tunnel.local_ip,
                       remote_address = t.tunnel.remote_ip,
                       local_cookie = t.tunnel.local_cookie,
                       remote_cookie = t.tunnel.remote_cookie,
                       local_session = t.tunnel.session}
         config.app(c, Tunnel, L2TPv3, conf)
         -- Setup IPv6 neighbor discovery/solicitation responder.
         -- This will talk to our local gateway.
         local ND = name.."_ND"
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
         local RxLimit = name.."_RxLimit"
         local rate = t.rx_police_gbps * 1e9 / 8
         config.app(c, RxLimit, RateLimiter, {rate = rate, bucket_capacity = rate})
         config.link(c, RxLimit..".output -> "..VM_rx)
         VM_rx = RxLimit..".input"
      end
      config.link(c, NIC..".tx -> "..VM_rx)
      config.link(c, VM_tx.." -> "..NIC..".rx")
   end

   -- Return configuration c.
   return c
end

function selftest ()
   print("selftest: lib.nfv.config")
   local pcideva = lib.getenv("SNABB_PCI0")
   if not pcideva then
      print("SNABB_PCI0 not set\nTest skipped")
      os.exit(engine.test_skipped_code)
   end
   engine.log = true
   for i, confpath in ipairs({"program/snabbnfv/test_fixtures/nfvconfig/switch_nic/x",
                              "program/snabbnfv/test_fixtures/nfvconfig/switch_filter/x",
                              "program/snabbnfv/test_fixtures/nfvconfig/switch_qos/x",
                              "program/snabbnfv/test_fixtures/nfvconfig/switch_tunnel/x",
                              "program/snabbnfv/test_fixtures/nfvconfig/scale_up/y",
                              "program/snabbnfv/test_fixtures/nfvconfig/scale_up/x",
                              "program/snabbnfv/test_fixtures/nfvconfig/scale_change/x",
                              "program/snabbnfv/test_fixtures/nfvconfig/scale_change/y"})
   do
      print("testing:", confpath)
      engine.configure(load(confpath, pcideva, "/dev/null"))
      engine.main({duration = 0.25})
   end
end

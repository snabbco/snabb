-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local lib  = require("core.lib")
local usage = require("program.snabbnfv.fuzz.README_inc")

function run (args)
   if #args ~= 2 then print(usage) main.exit(1) end
   local spec_path, output_path = unpack(args)
   local conf = fuzz_connective_ports(lib.load_conf(spec_path))
   lib.store_conf(output_path, conf)
end

-- Produces a random config with ports A and B which can communicate with
-- each other over IPv6/TCP based on spec.
function fuzz_connective_ports (spec)
   local vlan = random_vlan()
   local addresses = { "fe80:0:0:0:5054:ff:fe00:0",
                       "fe80:0:0:0:5054:ff:fe00:1" }
   local ports = { { port_id = "A",
                     mac_address = "52:54:00:00:00:00",
                     vlan = vlan },
                   { port_id = "B",
                     mac_address = "52:54:00:00:00:01",
                     vlan = vlan } }
   local function fuzz_filter (n_rules)
      local filter = "(ip6 and tcp) or (icmp6)"

      for i = 1, n_rules do
         filter = filter.." or "..(random_filter_rule())
      end
      return filter
   end
   local function fuzz_tunnel ()
      local cookies = { random_cookie(), random_cookie() }
      return { type = "L2TPv3",
               local_cookie = cookies[1],
               remote_cookie = cookies[2],
               next_hop = addresses[2],
               local_ip = addresses[1],
               remote_ip = addresses[2],
               session = random_session() },
             { type = "L2TPv3",
               local_cookie = cookies[2],
               remote_cookie = cookies[1],
               next_hop = addresses[1],
               local_ip = addresses[2],
               remote_ip = addresses[1],
               session = random_session() }
   end
   if spec.ingress_filter then
      ports[1].ingress_filter = fuzz_filter(spec.ingress_filter)
      ports[2].ingress_filter = fuzz_filter(spec.ingress_filter)
   end
   if spec.egress_filter then 
      ports[1].egress_filter = fuzz_filter(spec.egress_filter)
      ports[2].egress_filter = fuzz_filter(spec.egress_filter)
   end
   if spec.tunnel then
      ports[1].tunnel, ports[2].tunnel = fuzz_tunnel()
   end
   if spec.rx_police then
      ports[1].rx_police = random_gbps(spec.rx_police)
      ports[2].rx_police = random_gbps(spec.rx_police)
   end
   if spec.tx_police then
      ports[1].tx_police = random_gbps(spec.tx_police)
      ports[2].tx_police = random_gbps(spec.tx_police)
   end
   return ports
end

function random_uint (nbits, min)
   return math.random(min or 0, (2^nbits-1))
end

function random_vlan ()
   -- Twelve bit integer, see Intel10G (apps.intel.intel_app)
   return random_uint(12)
end

function random_ip (version)
   local version = version or "ip6"
   local function b4 () return random_uint(8) end
   local function b6 () return ("%X"):format(random_uint(16)) end
   if version == "ip" then
      return b4().."."..b4().."."..b4().."."..b4()
   elseif version == "ip6" then
      return b6()..":"..b6()..":"..b6()..":"..b6()..":"..b6()..":"..b6()..":"..b6()..":"..b6()
   end
end

function random_cidr (version)
   -- This is just lame, should be a "smart" random valid CIDR generator.
   local random_cidr_ip4 = {
      "109.0.0.0/8",
      "109.145.0.0/16",
      "109.145.29.0/24",
--      "109.145.29.1"
   }
   local random_cidr_ip6 = {
      "CB51::0/16",
      "CB51:B2E7::0/32",
      "CB51:B2E7:9711::0/48",
      "CB51:B2E7:9711:C0D3::0/64",
      "CB51:B2E7:9711:C0D3:14BA::0/80",
      "CB51:B2E7:9711:C0D3:14BA:A93E::0/96",
      "CB51:B2E7:9711:C0D3:14BA:A93E:56DE:0/112",
--      "CB51:B2E7:9711:C0D3:14BA:A93E:56DE:1"
   }
   if version == "ip" then
      return random_item(random_cidr_ip4)
   elseif version == "ip6" then
      return random_item(random_cidr_ip6)
   end
end

function random_port (min)
   local min = min or 1024
   return random_uint(16, min)
end

function random_item (array)
   return array[math.random(1, #array)]
end

function random_filter_rule ()
   local options = { ethertype = { "ip", "ip6" },
                     protocol = { "udp", "tcp" } }
   local ethertype = random_item(options.ethertype)
   local source_port_min = random_port()
   local dest_port_min = random_port()
   -- See PcapFilter (apps.packet_filter.pcap_filter)
   return ("(%s and %s and src net %s and dst net %s and src portrange %d-%d and dst portrange %d-%d)"):format(
      ethertype,
      random_item(options.protocol),
      random_cidr(ethertype),
      random_cidr(ethertype),
      source_port_min,
      random_port(source_port_min),
      dest_port_min,
      random_port(dest_port_min))
end

function random_cookie ()
   local function b() return ("%X"):format(random_uint(8)) end
   -- Eight byte hex string, see SimpleKeyedTunnel (apps.keyed_ipv6_tunnel.tunnel)
   return b()..b()..b()..b()..b()..b()..b()..b()
end

function random_session ()
   -- 32 bit uint, see SimpleKeyedTunnel (apps.keyed_ipv6_tunnel.tunnel)
   return random_uint(32)
end

function random_gbps (max_gbps)
   return math.random(1, max_gbps)
end

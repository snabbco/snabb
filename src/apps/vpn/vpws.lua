-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Virtual Private Wire Service (VPWS)
-- Provides a L2 VPN on top of IP (v4/v6) and GRE
--
-- This app has two connections, customer and uplink.  The former
-- transports Ethernet frames while the latter transports Ethernet
-- frames encapsulated in IP/GRE.  The push() method performs the
-- appropriate operation depending on the input port.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local app = require("core.app")
local link = require("core.link")
local config = require("core.config")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local gre = require("lib.protocol.gre")
local packet = require("core.packet")
local filter = require("lib.pcap.filter")
local pcap = require("apps.pcap.pcap")

local vpws = subClass(nil)
local in_to_out = { customer = 'uplink', uplink = 'customer' }

function vpws:new(arg)
   local conf = arg and config.parse_app_arg(arg) or {}
   -- Parse MAC and IP addresses if necessary.
   for _, key in ipairs({'local_mac', 'remote_mac'}) do
      if type(conf[key]) == "string" then
         conf[key] = ethernet:pton(conf[key])
      end
   end
   for _, key in ipairs({'local_vpn_ip', 'remote_vpn_ip'}) do
      if type(conf[key]) == "string" then
         conf[key] = ipv6:pton(conf[key])
      end
   end

   local o = vpws:superClass().new(self)
   o._config = conf
   o._name = conf.name
   o._encap = {
      ipv6  = ipv6:new({ next_header = 47, hop_limit = 64, src = conf.local_vpn_ip,
                         dst = conf.remote_vpn_ip}),
      gre   = gre:new({ protocol = 0x6558, checksum = conf.checksum, key = conf.label })
   }
   -- Use a dummy value for the destination MAC address in case it is
   -- omitted from the configuration.  In this case, the app needs to
   -- be connected to something that performs address resolution and
   -- overwrites the Ethernet header (e.g. the nd_light app)
   -- accordinly.
   o._encap.ether = ethernet:new({ src = conf.local_mac,
                                   dst = conf.remote_mac or ethernet:pton('02:00:00:00:00:00'),
                                   type = 0x86dd })
   -- Pre-computed size of combined Ethernet and IPv6 header
   o._eth_ipv6_size = ethernet:sizeof() + ipv6:sizeof()
   local program = "ip6 and dst host "..ipv6:ntop(conf.local_vpn_ip) .." and ip6 proto 47"
   local filter, errmsg = filter:new(program)
   assert(filter, errmsg and ffi.string(errmsg))
   o._filter = filter
   o._dgram = datagram:new()
   packet.free(o._dgram:packet())
   return o
end

function vpws:push()
   for _, port_in in ipairs({"customer", "uplink"}) do
      local l_in  = self.input[port_in]
      local l_out = self.output[in_to_out[port_in]]
      assert(l_out)
      while not link.empty(l_in) do
         local p = link.receive(l_in)
         local datagram = self._dgram:new(p, ethernet)
         if port_in == 'customer' then
            local encap = self._encap
            -- Encapsulate Ethernet frame coming in on customer port
            -- IPv6 payload length consist of the size of the GRE header plus
            -- the size of the original packet
            encap.ipv6:payload_length(encap.gre:sizeof() + p.length)
            if encap.gre:checksum() then
               encap.gre:checksum(datagram:payload())
            end
            -- Copy the finished headers into the packet
            datagram:push(encap.gre)
            datagram:push(encap.ipv6)
            datagram:push(encap.ether)
         else
            -- Check for encapsulated frame coming in on uplink
            if self._filter:match(datagram:payload()) then
               -- Remove encapsulation to restore the original
               -- Ethernet frame
               datagram:pop_raw(self._eth_ipv6_size, gre)
               local valid = true
               local gre = datagram:parse()
               if gre then
                  if not gre:checksum_check(datagram:payload()) then
                     print(self:name()..": GRE bad checksum")
                     valid = false
                  else
                     local key = gre:key()
                     if ((self._config.label and key and key == self._config.label) or
                      not (self._config.label or key)) then
                        datagram:pop(1)
                     else
                        print(self:name()..": GRE key mismatch: local "
                           ..(self._config.label or 'none')..", remote "..(gre:key() or 'none'))
                        valid = false
                     end
                  end
               else
                 -- Unsupported GRE options or flags
                  valid = false
               end
               if not valid then
                  packet.free(p)
                  p = nil
               end
            else
               -- Packet doesn't belong to VPN, discard
               packet.free(p)
               p = nil
            end
         end
         if p then link.transmit(l_out, p) end
      end
   end
end

function selftest()
   local local_mac     = ethernet:pton("90:e2:ba:62:86:e5")
   local remote_mac    = ethernet:pton("28:94:0f:fd:49:40")
   local local_ip      = ipv6:pton("2001:620:0:C101:0:0:0:2")
   local local_vpn_ip  = ipv6:pton("2001:620:0:C000:0:0:0:FC")
   local remote_vpn_ip = ipv6:pton("2001:620:0:C000:0:0:0:FE")
   local c = config.new()

   config.app(c, "from_uplink", pcap.PcapReader, "apps/vpn/vpws-selftest-uplink.cap.input")
   config.app(c, "from_customer", pcap.PcapReader, "apps/vpn/vpws-selftest-customer.cap.input")
   config.app(c, "to_customer", pcap.PcapWriter, "apps/vpn/vpws-selftest-customer.cap.output")
   config.app(c, "to_uplink", pcap.PcapWriter, "apps/vpn/vpws-selftest-uplink.cap.output")
   config.app(c, "vpntp", vpws, { name          = "vpntp1",
                                  checksum      = true,
                                  label         = 0x12345678,
                                  local_vpn_ip  = local_vpn_ip,
                                  remote_vpn_ip = remote_vpn_ip,
                                  local_ip      = local_ip,
                                  local_mac     = local_mac,
                                  remote_mac    = remote_mac })
   config.link(c, "from_uplink.output -> vpntp.uplink")
   config.link(c, "vpntp.customer -> to_customer.input")
   config.link(c, "from_customer.output -> vpntp.customer")
   config.link(c, "vpntp.uplink -> to_uplink.input")
   app.configure(c)
   app.main({duration = 1})
   if (io.open("apps/vpn/vpws-selftest-customer.cap.output"):read('*a') ~=
 io.open("apps/vpn/vpws-selftest-customer.cap.expect"):read('*a')) then
      print('vpws decapsulation selftest failed.')
      os.exit(1)
   end
   if (io.open("apps/vpn/vpws-selftest-uplink.cap.output"):read('*a') ~=
 io.open("apps/vpn/vpws-selftest-uplink.cap.expect"):read('*a')) then
      print('vpws encapsulation selftest failed.')
      os.exit(1)
   end
end

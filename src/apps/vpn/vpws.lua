-- Virtual Private Wire Service (VPWS)
-- Provides a L2 VPN on top of IP (v4/v6) and GRE
--
-- This app has two connections, customer and uplink.  The former
-- transports Ethernet frames while the latter transports Ethernet
-- frames encapsulated in IP/GRE.  The push() method performs the
-- appropriate operation depending on the input port.

require("class")
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local app = require("core.app")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local gre = require("lib.protocol.gre")
local packet = require("core.packet")

local vpws = subClass(nil)
local in_to_out = { customer = 'uplink', uplink = 'customer' }

function vpws:_init_new(name, label, local_ip, remote_ip, ll,
			src_mac, dst_mac)
   self._name = name
   self._config = { label = label, local_ip = local_ip,
		    ll = ll, src_mac = src_mac }
   self._encap = {
      ether = ethernet:new({ src = src_mac, dst = dst_mac, type = 0x86dd }),
      ipv6  = ipv6:new({ next_header = 47, hop_limit = 64, src = local_ip, dst = remote_ip}),
      gre   = gre:new({ protocol = 0x6558, key = label })
   }
end

function vpws:name()
   return self._name
end

function vpws:push()
   for port_in, l_in in pairs(self.input) do
      local l_out = self.output[in_to_out[port_in]]
      assert(l_out)
      while not app.full(l_out) and not app.empty(l_in) do
	 local p = app.receive(l_in)
	 local datagram = datagram:new(p, ethernet)
	 if port_in == 'customer' then
	    -- Encapsulate Ethernet frame coming in on customer port
	    datagram:push(self._encap.ether:clone())
	    local ipv6 = datagram:push(self._encap.ipv6:clone())
	    local gre = datagram:push(self._encap.gre:clone())
	    -- IPv6 payload length consist of the size of the GRE header plus
	    -- the size of the original packet
	    ipv6:payload_length(gre:sizeof() + p.length)
	    if gre:use_checksum() then
	       gre:checksum(datagram:payload())
	    end
	 else
	    -- Check for encapsulated frame coming in on uplink
	    if datagram:parse(
	       { { ethernet },
		 { ipv6, 
		   function(ipv6) 
		      return(ipv6:dst_eq(self._config.local_ip)) 
		   end }, 
		 { gre,
		   function(gre) 
		      return(not gre:use_key() or gre:key() == self._config.label)
		   end } }) then
	       -- Remove encapsulation to restore the original
	       -- Ethernet frame
	       datagram:pop(3)
	    else
	       -- Packet doesn't belong to VPN, discard
	       packet.deref(p)
	       return
	    end
	 end
	 app.transmit(l_out, p)
      end
   end
end

function vpws.selftest()
   local vpn = vpws:new("myvpn")
   print(vpn:name())
end

return vpws

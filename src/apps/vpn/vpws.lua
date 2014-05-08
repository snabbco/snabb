-- Virtual Private Wire Service (VPWS)
-- Provides a L2 VPN on top of IP (v4/v6) and GRE
--
-- This app has two connections, customer and uplink.  The former
-- transports Ethernet frames while the latter transports Ethernet
-- frames encapsulated in IP/GRE.  The push() method performs the
-- appropriate operation depending on the input port.

module(...,package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local app = require("core.app")
local link = require("core.link")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local gre = require("lib.protocol.gre")
local packet = require("core.packet")

local vpws = subClass(nil)
local in_to_out = { customer = 'uplink', uplink = 'customer' }

--_NAME = nil
function vpws:new(config)
   local o = self:superClass().new(self)
   o._config = config
   o._encap = {
      ether = ethernet:new({ src = config.local_mac, dst = config.remote_mac, type = 0x86dd }),
      ipv6  = ipv6:new({ next_header = 47, hop_limit = 64, src = config.local_vpn_ip,
			 dst = config.remote_vpn_ip}),
      gre   = gre:new({ protocol = 0x6558, key = config.label })
   }
   o._match = { { ethernet },
		   { ipv6, 
		     function(ipv6) 
			return(ipv6:dst_eq(config.local_vpn_ip)) 
		     end }, 
		   { gre,
		     function(gre) 
			return(not gre:use_key() or gre:key() == config.label)
		     end } }
   return o
end

function vpws:name()
   return self.config.name
end

function vpws:push()
   for _, port_in in ipairs({"customer", "uplink"}) do
      local l_in  = self.input[port_in]
      local l_out = self.output[in_to_out[port_in]]
      assert(l_out)
      while not link.full(l_out) and not link.empty(l_in) do
	 local p = link.receive(l_in)
	 local datagram = datagram:new(p, ethernet)
	 if port_in == 'customer' then
	    local encap = self._encap
	    -- Encapsulate Ethernet frame coming in on customer port
	    -- IPv6 payload length consist of the size of the GRE header plus
	    -- the size of the original packet
	    encap.ipv6:payload_length(encap.gre:sizeof() + p.length)
	    if encap.gre:use_checksum() then
	       encap.gre:checksum(datagram:payload())
	    end
	    -- Copy the finished headers into the packet
	    datagram:push(encap.ether)
	    datagram:push(encap.ipv6)
	    datagram:push(encap.gre)
	 else
	    -- Check for encapsulated frame coming in on uplink
	    if datagram:parse(self._match) then
	       -- Remove encapsulation to restore the original
	       -- Ethernet frame
	       datagram:pop(3)
	    else
	       -- Packet doesn't belong to VPN, discard
	       packet.deref(p)
	       p = nil
	    end
	 end
	 if p then link.transmit(l_out, p) end
	 datagram:free()
      end
   end
end

function vpws.selftest()
   print("vpws selftest not implemented")
end

return vpws

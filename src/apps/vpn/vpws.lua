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
local matcher = require("lib.protocol.matcher")

local vpws = subClass(nil)
local in_to_out = { customer = 'uplink', uplink = 'customer' }

function vpws:new(config)
   local o = self:superClass().new(self)
   o._config = config
   o._name = config.name
   o._encap = {
      ether = ethernet:new({ src = config.local_mac, dst = config.remote_mac, type = 0x86dd }),
      ipv6  = ipv6:new({ next_header = 47, hop_limit = 64, src = config.local_vpn_ip,
			 dst = config.remote_vpn_ip}),
      gre   = gre:new({ protocol = 0x6558, checksum = config.checksum, key = config.label })
   }
   o._matcher = matcher:new()
   o._matcher:add(12, 2, ffi.new("uint16_t[1]", C.htons(0x86dd))) -- ipv6
   o._matcher:add(38, 16, config.local_vpn_ip) -- ipv6 destination
   o._matcher:add(20, 1, ffi.new("uint8_t[1]", 47)) -- gre
   return o
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
	    if encap.gre:checksum() then
	       encap.gre:checksum(datagram:payload())
	    end
	    -- Copy the finished headers into the packet
	    datagram:push(encap.ether)
	    datagram:push(encap.ipv6)
	    datagram:push(encap.gre)
	 else
	    -- Check for encapsulated frame coming in on uplink
	    if self._matcher:compare(datagram:payload()) then
	       -- Remove encapsulation to restore the original
	       -- Ethernet frame
	       datagram:pop_raw(ethernet:sizeof())
	       datagram:pop_raw(ipv6:sizeof(), gre)
	       local gre = datagram:parse()
	       local valid = true
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
	       if not valid then
		  packet.deref(p)
		  p = nil
	       end
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

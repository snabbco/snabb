module(..., package.seeall)

local ipv6 = require("lib.protocol.ipv6")

-- TODO: handle fragmentation
--local IPv6HeaderSize = 40 -- bytes
--local IPv6SrcStart = 8
--local IPv6DstStart = 24

IPv6Tunnel = {}

function IPv6Tunnel:new (conf)
   local c = {local_ip = conf.ipv6_src, to_ip = conf.ipv6_dst}
   return setmetatable(c, {__index=IPv6Tunnel})
end

--TODO: is it better to modify or copy pkt?
local function ipv6_encapsulate(pkt, src_ip, dst_ip)
   local next_header_type = 58 -- FIXME
   local ipv6_pkt = ipv6:new({next_header = next_header_type,
                              hop_limit = 255,
                              src = src_ip,
                              dst = dst_ip})
   return ipv6_pkt
end

-- TODO: revisit this and check on performance idioms
function IPv6Tunnel:push ()
   local i, o = self.input.input, self.output.output
   local pkt = link.receive(i)
   print("got a pkt")
   local encap_pkt = ipv6_encapsulate(pkt, self.local_ip, self.to_ip)
   print("encapsulated")
   link.transmit(o, encap_pkt)
end

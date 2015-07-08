module(..., package.seeall)

local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local packet = require("core.packet")

-- TODO: handle fragmentation
--local IPv6HeaderSize = 40 -- bytes
--local IPv6SrcStart = 8
--local IPv6DstStart = 24

IPv6Tunnel = {}

function IPv6Tunnel:new (conf)
   local c = {local_ip = conf.ipv6_src, to_ip = conf.ipv6_dst}
   return setmetatable(c, {__index=IPv6Tunnel})
end

local function print_pkt(pkt)
   local fbytes = {}
   for i=0,pkt.length - 1 do table.insert(fbytes, string.format("0x%x", pkt.data[i])) end
   print(string.format("Len: %i: ", pkt.length) .. table.concat(fbytes, " "))
end

local function pp(t)
   for k,v in pairs(t) do print(k,v) end
end

--TODO: is it better to modify or copy pkt?
local function ipv6_encapsulate(pkt, src_ip, dst_ip)
   local dgram = datagram:new(pkt, ethernet)
   print_pkt(pkt)
   local ethernet_header_size = 14
   -- TODO: verify that the last 2 bytes are 0x0800, IPv4
   dgram:pop_raw(ethernet_header_size)
   -- TODO: decrement the IPv4 ttl as this is part of forwarding
   -- TODO: do not encapsulate if ttl was already 0; send icmp
   local payload_len = pkt.length
   print("popped")
   print_pkt(pkt)
   local next_header_type = 4 -- IPv4
   local ipv6_hdr = ipv6:new({next_header = next_header_type,
                              hop_limit = 255,
                              src = src_ip,
                              dst = dst_ip})
   pp(ipv6_hdr)
 
   local ipv6_ethertype = 0x86dd
   local eth_hdr = ethernet:new({src = ethernet:pton("77:77:77:77:77:77"),
                                 dst = ethernet:pton("66:66:66:66:66:66"),
                                 type = ipv6_ethertype})
   
   print_pkt(pkt)
   print("eth-prepush")
   print_pkt(pkt)
   dgram:push(ipv6_hdr)
   -- The API makes setting the payload length awkward; set it manually
   pkt.data[4] = bit.band(payload_len, 0xff00)
   pkt.data[5] = bit.band(payload_len, 0xff)
   print("ipv6 pushed")
   print_pkt(pkt)
   dgram:push(eth_hdr)
   print("eth-pushed")
   print_pkt(pkt)
   return pkt
end

-- TODO: revisit this and check on performance idioms
function IPv6Tunnel:push ()
   local i, o = self.input.input, self.output.output
   local pkt = link.receive(i)
   print("got a pkt")
   local encap_pkt = ipv6_encapsulate(pkt, self.local_ip, self.to_ip)
   print("encapsulated")
   link.transmit(o, encap_pkt)
   print("tx'd")
end

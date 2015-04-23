module(..., package.seeall)

bit = require("bit")

--- ### `basicnat` app: Implement http://www.ietf.org/rfc/rfc1631.txt Basic NAT

BasicNAT = {}

function BasicNAT:new ()
   return setmetatable({index = 1, packets = {}},
                       {__index=BasicNAT})
end

local function bytes_to_uint32(a, b, c, d)
   return a * 2^24 + b * 2^16 + c * 2^8 + d
end

local function get_src_ip(pkt)
   local d = pkt.data
   return bytes_to_uint32(d[26], d[27], d[28], d[29])
end

local function get_dst_ip(pkt)
   local d = pkt.data
   return bytes_to_uint32(d[30], d[31], d[32], d[33])
end

--local function uint32_to_bytes(u)
--end 

local function str_ip_to_uint32(ip)
   local a, b, c, d = ip:match("([0-9]+).([0-9]+).([0-9]+).([0-9]+)")
   return bytes_to_uint32(tonumber(a), tonumber(b), tonumber(c), tonumber(d))
end

-- TODO: is there something nicer in Hacker's Delight?
local function get_mask_bits(maskbits)
   if maskbits == 0 then return 0 end
   return bit.lshift(0xffffffff, 32 - maskbits) % 2^32
end

local function str_net_to_uint32(ip)
   local base_ip = str_ip_to_uint32(ip:match("^[^/]+"))
   local mask = get_mask_bits(tonumber(ip:match("/([0-9]+)")))
   return bit.band(base_ip, mask) % 2^32, mask
end

local function set_src_ip(pkt, ip)
   return pkt -- TODO
end


local function ip_in_net(ip, net, mask)
  print(ip, net, mask)
  return net == bit.band(ip, mask) % 2^32
end

-- For packets outbound from the
-- private network, the source IP address and related fields such as IP,
-- TCP, UDP and ICMP header checksums are translated. For inbound
-- packets, the destination IP address and the checksums as listed above
-- are translated.
-- TODO: make this able to deal with a range of external IPs, not just one
local function basic_rewrite(external_ip, internal_net, mask, pkt)
   local src_ip, dst_ip = get_src_ip(pkt), get_dst_ip(pkt)
   if ip_in_net(src_ip, internal_net, mask) then
      print("src", src_ip)
   end
   if ip_in_net(dst_ip, internal_net, mask) then
      print("dst", dst_ip)
   end
   return pkt
end

function BasicNAT:push ()
   local i, o = self.input.input, self.output.output
   local pkt = link.receive(i)
   local external_ip = str_ip_to_uint32("10.0.0.1")
   local internal_net, mask = str_net_to_uint32("178.0.0.0/8")
   local natted_pkt = basic_rewrite(external_ip, internal_net, mask, pkt)
   link.transmit(o, natted_pkt)
end

module(..., package.seeall)

bit = require("bit")
ffi = require("ffi")

--- ### `basicnat` app: Implement http://www.ietf.org/rfc/rfc1631.txt Basic NAT

BasicNAT = {}

function BasicNAT:new ()
   return setmetatable({index = 1, packets = {}},
                       {__index=BasicNAT})
end

local function bytes_to_uint32(a, b, c, d)
   return a * 2^24 + b * 2^16 + c * 2^8 + d
end

local ipv4_base = 14 -- Ethernet encapsulated ipv4
local transport_base = 34 -- tranport layer (TCP/UDP/etc) header start
local proto_tcp = 6
local proto_udp = 17

local function uint32_to_bytes(u)
   a = bit.rshift(bit.band(u, 0xff000000) % 2^32, 24)
   b = bit.rshift(bit.band(u, 0x00ff0000), 16)
   c = bit.rshift(bit.band(u, 0x0000ff00), 8)
   d = bit.band(u, 0x000000ff)
   return a, b, c, d
end 

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

local function get_src_ip(pkt)
   local d = pkt.data
   return bytes_to_uint32(d[26], d[27], d[28], d[29])
end

local function get_dst_ip(pkt)
   local d = pkt.data
   return bytes_to_uint32(d[30], d[31], d[32], d[33])
end

local function csum_carry_and_not(checksum)
   while checksum > 0xffff do -- process the carry nibbles
      local carry = bit.rshift(checksum, 16)
      checksum = bit.band(checksum, 0xffff) + carry
   end
   return bit.band(bit.bnot(checksum), 0xffff)
end

local function ipv4_checksum(pkt)
   local checksum = 0
   for i = ipv4_base, ipv4_base + 18, 2 do
      if i ~= ipv4_base + 10 then -- The checksum bytes are assumed to be 0
         checksum = checksum + pkt.data[i] * 0x100 + pkt.data[i+1]
      end
   end
   return csum_carry_and_not(checksum)
end

local function transport_checksum(pkt)
   local checksum = 0
   -- First 64 bytes of the TCP pseudo-header: the ip addresses
   for i = ipv4_base + 12, ipv4_base + 18, 2 do
      checksum = checksum + pkt.data[i] * 0x100 + pkt.data[i+1]
   end
   -- Add the protocol field of the IPv4 header to the checksum
   local protocol = pkt.data[ipv4_base + 9]
   checksum = checksum + protocol
   local tcplen = pkt.data[ipv4_base + 2] * 0x100 + pkt.data[ipv4_base + 3] - 20
   checksum = checksum + tcplen -- end of pseudo-header

   for i = transport_base, transport_base + tcplen - 2, 2 do
      if i ~= transport_base + 16 then -- The checksum bytes are zero
         checksum = checksum + pkt.data[i] * 0x100 + pkt.data[i+1]
      end
   end
   if tcplen % 2 == 1 then
      checksum = checksum + pkt.data[transport_base + tcplen - 1]
   end
   return csum_carry_and_not(checksum)
end


local function fix_checksums(pkt)
   local ipchecksum = ipv4_checksum(pkt)
   pkt.data[ipv4_base + 10] = bit.rshift(ipchecksum, 8)
   pkt.data[ipv4_base + 11] = bit.band(ipchecksum, 0xff)
   local transport_proto = pkt.data[ipv4_base + 9]
   if transport_proto == proto_tcp then
      local transport_checksum = transport_checksum(pkt)
      pkt.data[transport_base + 16] = bit.rshift(transport_checksum, 8)
      pkt.data[transport_base + 17] = bit.band(transport_checksum, 0xff)
      return true
   elseif transport_proto == proto_udp then
      -- ipv4 udp checksums are optional
      pkt.data[transport_base + 6] = 0
      pkt.data[transport_base + 7] = 0
      return true
   else
      return false -- didn't attempt to change a transport-layer checksum
   end
end

-- TODO: fix the checksum
local function set_src_ip(pkt, ip)
   a, b, c, d = uint32_to_bytes(ip)
   pkt.data[ipv4_base + 12] = a
   pkt.data[ipv4_base + 13] = b
   pkt.data[ipv4_base + 14] = c
   pkt.data[ipv4_base + 15] = d
   return pkt
end

-- TODO: fix the checksum
local function set_dst_ip(pkt, ip)
   a, b, c, d = uint32_to_bytes(ip)
   pkt.data[ipv4_base + 16] = a
   pkt.data[ipv4_base + 17] = b
   pkt.data[ipv4_base + 18] = c
   pkt.data[ipv4_base + 19] = d
   return pkt
end

local function ip_in_net(ip, net, mask)
  return net == bit.band(ip, mask) % 2^32
end

-- For packets outbound from the
-- private network, the source IP address and related fields such as IP,
-- TCP, UDP and ICMP header checksums are translated. For inbound
-- packets, the destination IP address and the checksums as listed above
-- are translated.
-- TODO: make this able to deal with a range of external IPs, not just one
local function basic_rewrite(pkt, external_ip, internal_net, mask)
   -- Only attempt to alter ipv4 packets. Assume an Ethernet encapsulation.
   if pkt.data[12] ~= 8 or pkt.data[13] ~= 0 then return pkt end
   local src_ip, dst_ip = get_src_ip(pkt), get_dst_ip(pkt)
   if ip_in_net(src_ip, internal_net, mask) then
      set_src_ip(pkt, external_ip)
   end
   if ip_in_net(dst_ip, internal_net, mask) then
      set_dst_ip(pkt, external_ip)
   end
   fix_checksums(pkt)
   return pkt
end

function BasicNAT:push ()
   local i, o = self.input.input, self.output.output
   local pkt = link.receive(i)
   local external_ip = str_ip_to_uint32("10.0.0.1")
   local internal_net, mask = str_net_to_uint32("178.0.0.0/8")
   local natted_pkt = basic_rewrite(pkt, external_ip, internal_net, mask)
   link.transmit(o, natted_pkt)
end

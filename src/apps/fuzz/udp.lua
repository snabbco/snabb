module(...,package.seeall)

local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local ipv4 = require("lib.protocol.ipv4")
local udp = require("lib.protocol.udp")

local ffi = require("ffi")
local C = ffi.C

-- UDP generator
g_udp = {}
g_udp.__index = g_udp

function g_udp:new (data_list)
   -- should be at least one layer before us
   assert(data_list and #data_list > 0)
   return setmetatable({
      data_list = data_list,
      mss = {
         32, 256, 512, 1024, -- arbitrary
         1472,  -- MSS on 1514 MTU
         2048 -- jumbo
      },
      src_port = 111,
      dst_port = 222,
      match4 = {{ethernet}, {ipv4}, {udp}},
      match6 = {{ethernet}, {ipv6}, {udp}}
   }, g_udp)
end

function g_udp:clone4 (data)
   local new_p = packet.clone(data.dg:packet())
   local d = datagram:new(new_p, ethernet)
   -- ensure the IPv4 packet is of UDP type
   local ip = d:parse({{ethernet}, {ipv4}})
   ip:protocol(17) -- UDP
   d:unparse(2)

   -- start all over again
   d:parse(self.match4)
   local eth, ip, udp = unpack(d:stack())

   udp:src_port(self.src_port)
   udp:dst_port(self.dst_port)
   udp:length(new_p.length - eth:sizeof() - ip:sizeof()) -- the length

   local new_data = {
      dg = d,
      desc = data.desc.." UDP",
      ethernet = eth,
      ipv4 = ip,
      udp = udp,
      match = self.match4,
      valid = true
   }
   self.data_list[#self.data_list + 1] = new_data
   return new_data
end

function g_udp:clone6 (data)
   local new_p = packet.clone(data.dg:packet())
   local d = datagram:new(new_p, ethernet)
   -- ensure the IPv6 packet is of UDP type
   local ip = d:parse({{ethernet}, {ipv6}})
   ip:next_header(17) -- UDP
   d:unparse(2)

   -- start all over again
   d:parse(self.match6)
   local eth, ip, udp = unpack(d:stack())

   udp:src_port(self.src_port)
   udp:dst_port(self.dst_port)
   udp:length(new_p.length - eth:sizeof() - ip:sizeof()) -- the length

   local new_data = {
      dg = d,
      desc = data.desc.." UDP",
      ethernet = eth,
      ipv6 = ip,
      udp = udp,
      match = self.match6,
      valid = true
   }
   self.data_list[#self.data_list + 1] = new_data
   return new_data
end

function g_udp:single (data)

   if data.ipv4 then
      -- generate packets for all supoprted MSS types
      for _,mss in ipairs(self.mss) do
         -- default ipv4 packet
         local new_data = self:clone4 (data)
         local p = new_data.dg:packet()
         local info = p.info

         --checksum
         info.flags = C.PACKET_NEEDS_CSUM
         info.csum_start = new_data.ethernet:sizeof() + new_data.ipv4:sizeof()
         info.csum_offset = 6 -- UDP offset is 6 bytes from the start

         -- segmentation
         info.gso_flags = C.PACKET_GSO_UDPV4
         if new_data.ipv4:ecn() ~= 0 then
            info.gso_flags = info.gso_flags + C.PACKET_GSO_ECN
         end
         info.gso_size = mss -- MSS
         info.hdr_len = new_data.ethernet:sizeof() + new_data.ipv4:sizeof() + new_data.udp:sizeof()
      end
   elseif data.ipv6 then
      -- default ipv6 packet
      local new_data = self:clone6 (data)
      local p = new_data.dg:packet()
      local info = p.info

      --checksum
      info.flags = C.PACKET_NEEDS_CSUM
      info.csum_start = new_data.ethernet:sizeof() + new_data.ipv6:sizeof()
      info.csum_offset = 6 -- UDP offset is 6 bytes from the start
   end
end

function g_udp:generate()
   -- save the origin list to iterate over it
   local origin = {}
   for _, data in pairs(self.data_list) do origin[#origin+1] = data end

   for _, data in pairs(origin) do
      self:single(data)
   end
end

return g_udp

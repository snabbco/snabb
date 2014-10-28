module(...,package.seeall)

local lib = require("core.lib")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")

local ffi = require("ffi")
local C = ffi.C

-- IPv4 generator
g_ipv4 = {}
g_ipv4.__index = g_ipv4

function g_ipv4:new (data_list)
   -- should be at least one layer before us
   assert(data_list and #data_list > 0)
   return setmetatable({
      data_list = data_list,
      src = ipv4:pton("192.168.0.1"),
      dst = ipv4:pton("192.168.0.2"),
      match = {{ethernet}, {ipv4}}
   }, g_ipv4)
end

function g_ipv4:clone (data)
   local new_p = packet.clone(data.dg:packet())
   local d = datagram:new(new_p, ethernet)
   -- ensure the ethernet frame is of IPv4 type
   local eth = d:parse({{ethernet}})
   eth:type(0x0800) -- IPv4
   d:unparse(1)

   -- start all over again
   d:parse(self.match)
   local eth, ip = unpack(d:stack())

   ip:version(4)
   ip:ihl(ip:sizeof() / 4)
   ip:dscp(0)
   ip:ecn(0)
   ip:total_length(new_p.length - eth:sizeof()) -- the length
   ip:id(0)
   ip:flags(0)
   ip:frag_off(0)
   ip:ttl(3) -- arbitrary
   ip:protocol(0xff) -- invalid protocol, upper layers to set
   ip:src(self.src)
   ip:dst(self.dst)
   local new_data = {
      dg = d,
      desc = data.desc.." IPv4",
      ethernet = eth,
      ipv4 = ip,
      match = self.match,
      valid = true
   }
   self.data_list[#self.data_list + 1] = new_data
   return new_data
end

function g_ipv4:single (data)
   -- if ethernet header does not exist, leave
   if not data.ethernet then return end

   -- default ipv4 packet
   local new_data = self:clone (data)

   -- ecn
   new_data = self:clone (data)
   new_data.ipv4:ecn(0x3)
   new_data.desc = new_data.desc.." ecn"

   -- don't fragment
   new_data = self:clone (data)
   new_data.ipv4:flags(0x2)
   new_data.desc = new_data.desc.." df"
end

function g_ipv4:generate()
   local origin = lib.array_copy(self.data_list)
   for i=1,#origin do
      self:single(origin[i])
   end
end

return g_ipv4

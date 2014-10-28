module(...,package.seeall)

local lib = require("core.lib")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

local ffi = require("ffi")
local C = ffi.C

-- IPv6 generator
g_ipv6 = {}
g_ipv6.__index = g_ipv6

function g_ipv6:new (data_list)
   -- should be at least one layer before us
   assert(data_list and #data_list > 0)
   return setmetatable({
      data_list = data_list,
      src = ipv6:pton("0:0:0:0:0:0:0:1"),
      dst = ipv6:pton("0:0:0:0:0:0:0:2"),
      match = {{ethernet}, {ipv6}}
   }, g_ipv6)
end

function g_ipv6:clone (data)
   local new_p = packet.clone(data.dg:packet())
   local d = datagram:new(new_p, ethernet)
   -- ensure the ethernet frame is of IPv6 type
   local eth = d:parse({{ethernet}})
   eth:type(0x86dd) -- IPv6
   d:unparse(1)

   -- start all over again
   d:parse(self.match)
   local eth, ip = unpack(d:stack())

   ip:version(6)
   ip:traffic_class(0)
   ip:flow_label(0)
   ip:payload_length(new_p.length - eth:sizeof() - ip:sizeof())
   ip:next_header(0xff) -- invalid
   ip:hop_limit(3) -- arbitrary
   ip:src(self.src)
   ip:dst(self.dst)
   local new_data = {
      dg = d,
      desc = data.desc.." IPv6",
      ethernet = eth,
      ipv6 = ip,
      match = self.match,
      valid = true
   }
   self.data_list[#self.data_list + 1] = new_data
   return new_data
end

function g_ipv6:single (data)
   -- if ethernet header does not exist,
   -- or IPv4 is already set, leave
   if not data.ethernet or data.ipv4 then return end

   -- default ipv6 packet
   local new_data = self:clone (data)

   -- ecn
   new_data = self:clone (data)
   new_data.ipv6:traffic_class(0x3)
   new_data.desc = new_data.desc.." ecn"

end

function g_ipv6:generate()
   -- save the origin list to iterate over it
   local origin = lib.array_copy(self.data_list)
   for i=1,#origin do
      self:single(origin[i])
   end
end

return g_ipv6

module(...,package.seeall)

local lib = require("core.lib")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local ethernet = require("lib.protocol.ethernet")

local ffi = require("ffi")
local C = ffi.C

-- Ethernet generator
g_ethernet = {}
g_ethernet.__index = g_ethernet

function g_ethernet:new (data_list)
   -- should be at least one layer before us
   assert(data_list and #data_list > 0)
   return setmetatable({
      data_list = data_list,
      src = ethernet:pton("00:00:00:00:00:01"),
      dst = ethernet:pton("00:00:00:00:00:02"),
      match = {{ethernet}}
   }, g_ethernet)
end

function g_ethernet:single (data)
   -- simple Etherent frame - source, destination, type
   local new_p = packet.clone(data.dg:packet())
   local d = datagram:new(new_p, ethernet)
   local eth = d:parse(self.match)

   eth:src(self.src)
   eth:dst(self.dst)
   eth:type(0xFFFF) --invalid

   return {
      dg = d,
      desc = "Ethernet",
      ethernet = eth,
      match = self.match,
      valid = true,
   }
end

function g_ethernet:generate()
   -- save the origin list to iterate over it
   local origin = lib.array_copy(self.data_list)
   local size = #self.data_list
   for i=1,#origin do
      size = size + 1
      self.data_list[size] = self:single(origin[i])
   end
end

return g_ethernet

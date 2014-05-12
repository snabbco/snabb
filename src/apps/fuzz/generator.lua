module(...,package.seeall)

local buffer = require("core.buffer")
local freelist = require("core.freelist")
local lib = require("core.lib")
local packet = require("core.packet")
local datagram = require("lib.protocol.datagram")
local g_ethernet = require("apps.fuzz.ethernet")
local g_ipv4 = require("apps.fuzz.ipv4")
local g_ipv6 = require("apps.fuzz.ipv6")
local g_udp = require("apps.fuzz.udp")
local g_tcp = require("apps.fuzz.tcp")

local ffi = require("ffi")
local C = ffi.C

local uint16_t_size = ffi.sizeof("uint16_t")

-- The raw generator makes datagarams out of thin air
raw = {}
raw.__index = raw

function raw:new (data_list)
   -- we're the first in the chain
   assert(data_list and #data_list == 0)
   return setmetatable({
      data_list = data_list,
      -- sizes explained
      -- 64 - minimum ethernet size
      -- 1514 - max ethernet - no vlan
      -- 1518 - max ethernet
      -- 2048 - jumbo frame
      -- 4096 - jumbo frame - max buffer size we support
      sizes = {64, 128, 256, 512, 1024, 1514, 1518, 2048, 4096}
   }, raw)
end

function raw:single (size)
   local d = datagram:new()
   d:payload(lib.random_data(size), size)
   return d
end

function raw:generate()
   for _, s in ipairs(self.sizes) do
      self.data_list[#self.data_list + 1] = {
         dg = self:single(s),
         desc = " Raw data",
         valid = true
      }
   end
end

all_generators = {raw, g_ethernet, g_ipv4, g_ipv6, g_udp, g_tcp}

generator = {}
generator.__index = generator

function generator:new (generators)
   return setmetatable({
      zone="generator",
      generators = generators or all_generators,
      sg_patterns = {
         -- one jumbo buffer
         {{4096}},
         -- 1 byte | the rest
         {{1}},
         -- 1 byte @ offset 4095 | the rest
         {{1,4095}},
         -- 1 @ 4095 | 1 | the rest
         {{1,4095},{1}},
         -- 1024 | 1 @ 4095 | the rest
         {{1024}, {1,4095}},
         -- 64 | 1024 | the rest
         {{64},{1024}},
         -- 15 (PACKET_IOVEC_MAX-1) times 10 byte chunks | the rest
         {{10},{10},{10},{10},{10},{10},{10},{10},{10},{10},{10},{10},{10},{10},{10}}
      }
   }, generator)
end

function generator:mark (dg, mark)
   local payload, plen = dg:payload()
   local pmark = ffi.cast("uint16_t*",payload + plen - uint16_t_size)
   pmark[0] = C.htons(mark)
end

function generator:scatter (data)
   data.sg = {}
   for _, sg in ipairs(self.sg_patterns) do
      local p = data.dg:packet()
      data.sg[#data.sg + 1] = packet.scatter(p, sg)
   end
end

function generator:reset_list(data_list)
   for _, data in ipairs(data_list) do
      data.received = 0
   end
end

function generator:generate ()
   local data_list = {}
   -- iterate over all registered payload generators
   for _,class in ipairs(self.generators) do
      local g = class:new(data_list)
      g:generate()
   end

   -- mark the generated packets
   for i, data in ipairs(data_list) do
      self:mark(data.dg, i)
   end

   -- make the packet list out of the data list
   for _, data in ipairs(data_list) do
      self:scatter(data)
   end

   self:reset_list(data_list)
   return data_list
end

return generator

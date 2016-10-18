-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local murmur = require("lib.hash.murmur")
local C = require("ffi").C

SoftIO = {}

local ADDRESS_SIZE = 6
local SRC_OFFSET = ADDRESS_SIZE
local MIN_SIZE = ethernet:sizeof() + ipv6:sizeof()
local IP_SRC_DST_OFFSET = ethernet:sizeof() + 8
local IP_SRC_DST_SIZE = 2*16

local hubs = {}

function SoftIO:new (conf)
   local o = {}
   o.hub = conf.hub or 0
   hubs[o.hub] = hubs[o.hub] or {}
   o.id = (conf.vlan or "null").."/"..(conf.macaddr or "null")
   hubs[o.hub][o.id] = hubs[o.hub][o.id] or {}
   if conf.macaddr then
      o.mac = ethernet:pton(conf.macaddr)
   end
   if conf.rxq then
      o.murmur.MurmurHash3_x86_32:new()
      o.queue = conf.rxq + 1
      for i = 1,o.queue do
         hubs[o.hub][o.id][i] = hubs[o.hub][o.id][i] or (i == p.queue)
      end
   end
   return setmetatable(o, {__index=SoftIO})
end

function SoftIO:stop ()
   if self.queue then
      hubs[self.hub][self.id][self.queue] = false
      local i = #hubs[self.hub][self.id]
      while true do
         if not hubs[self.hub][self.id][i] then
            hubs[self.hub][self.id][i] = nil
         else
            return
         end
         i = i - 1
      end
   end
end

function SoftIO:hash (p)
   return self.murmur:hash(p.data+IP_SRC_DST_OFFSET, IP_SRC_DST_SIZE, 0ULL)
end

function SoftIO:push ()
   local mac = self.mac
   local queue, queuemod = self.queue, 1 + #hubs[self.hub][self.id]
   local l_in  = assert(self.input.trunk,  "No input link on trunk.")
   local l_out = assert(self.output.tx, "No output link on tx.")
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      if p.length < MIN_SIZE
         or (mac and C.memcmp(mac, p.data, ADDRESS_SIZE) ~= 0)
         or (queue and self:hash(p) % queuemod ~= queue)
      then
         packet.free(p)
      else
         link.transmit(l_out, p)
      end
   end
   local l_in  = assert(self.input.rx,  "No input link on rx.")
   local l_out = assert(self.output.trunk, "No output link on trunk.")
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      if p.length < MIN_SIZE
         or (mac and C.memcmp(mac, p.data+SRC_OFFSET, ADDRESS_SIZE) ~= 0)
      then
         packet.free(p)
      else
         link.transmit(l_out, p)
      end
   end
end

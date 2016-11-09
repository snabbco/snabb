-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local FloodingBridge = require("apps.bridge.flooding").bridge
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local murmur = require("lib.hash.murmur")
local C = require("ffi").C


control = {
   config = {
      virtual = {},
      queues = {required=true}
   }
}

local bridge = {}; setmetatable(bridge, {__mode="k"}) -- Weak keys

function control:configure (c, name, conf)
   bridge[c] = name
   local ports = {}
   for _, queuespec in ipairs(conf.queues) do
      if not queuespec.buckets or queuespec.buckets == 1 then
         table.insert(ports, queuespec.id)
      else
         for bucket = 1, queuespec.buckets do
            table.insert(ports, queuespec.id.."_"..bucket)
         end
      end
   end
   config.app(c, name, FloodingBridge, {ports=ports})
end


driver = {
   config = {
      queue = {required=true},
      bucket = {default=1},
      buckets = {default=1},
      queueconf = {required=true}
   }
}

Emu = {config = driver.config}

function driver:configure (c, name, conf)
   config.app(c, name, Emu, conf)
   local port
   if conf.buckets == 1 then
      port = conf.queue
   else
      port = conf.queue.."_"..conf.bucket
   end
   config.link(c, name..".trunk -> "..bridge[c].."."..port)
   config.link(c, bridge[c].."."..port.." -> "..name..".trunk")
end

function Emu:new (conf)
   local o = {}
   if conf.macaddr then
      o.mac = ethernet:pton(conf.macaddr)
   end
   if conf.buckets > 1 then
      o.murmur = murmur.MurmurHash3_x86_32:new()
      o.buckets = conf.buckets
      o.bucket = conf.bucket
   end
   return setmetatable(o, {__index=Emu})
end

local ADDRESS_SIZE = 6
local SRC_OFFSET = ADDRESS_SIZE
local MIN_SIZE = ethernet:sizeof() + ipv6:sizeof()
local IP_SRC_DST_OFFSET = ethernet:sizeof() + 8
local IP_SRC_DST_SIZE = 2*16

function Emu:hash (p)
   return self.murmur:hash(p.data+IP_SRC_DST_OFFSET, IP_SRC_DST_SIZE, 0ULL)
end

function Emu:push ()
   local mac, bucket, buckets = self.max, self.bucket, self.buckets
   local l_in  = assert(self.input.trunk,  "No input link on trunk.")
   local l_out = assert(self.output.tx, "No output link on tx.")
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      if p.length < MIN_SIZE
         or (mac and C.memcmp(mac, p.data, ADDRESS_SIZE) ~= 0)
         or (bucket and 1 + (self:hash(p) % buckets) ~= bucket)
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

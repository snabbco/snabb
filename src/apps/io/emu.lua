-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")
local murmur = require("lib.hash.murmur")
local C = require("ffi").C

Emu = {
   config = {
      macaddr = {},
      hash = {default=1},
      mod = {default=1},
   }
}

function Emu:new (conf)
   local o = {}
   if conf.macaddr then
      o.mac = ethernet:pton(conf.macaddr)
   end
   if conf.mod > 1 then
      o.murmur = murmur.MurmurHash3_x86_32:new()
      o.mod = conf.mod
      o.hash = conf.hash
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
   local mac, hash, mod = self.max, self.hash, self.mod
   local l_in  = assert(self.input.trunk,  "No input link on trunk.")
   local l_out = assert(self.output.tx, "No output link on tx.")
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      if p.length < MIN_SIZE
         or (mac and C.memcmp(mac, p.data, ADDRESS_SIZE) ~= 0)
         or (hash and 1 + (self:hash(p) % mod) ~= hash)
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

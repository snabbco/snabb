-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(...,package.seeall)

local murmur = require("lib.hash.murmur")
local ethernet = require("lib.protocol.ethernet")
local ipv6 = require("lib.protocol.ipv6")

Hash = {}

local MIN_SIZE = ethernet:sizeof() + ipv6:sizeof()
local IP_SRC_DST_OFFSET = ethernet:sizeof() + 8
local IP_SRC_DST_SIZE = 2*16

function Hash:new ()
   return setmetatable({murmur=murmur.MurmurHash3_x86_32:new()},
                       {__index=Hash})
end

function Hash:hash (p)
   if p.length < MIN_SIZE then
      return 0
   else
      return self.murmur:hash(p.data+IP_SRC_DST_OFFSET, IP_SRC_DST_SIZE, 0ULL)
   end
end

function Hash:push ()
   local l_in  = assert(self.input.input,  "Need input link.")
   local out = self.output
   local nqueues = #out
   for i = 1, link.nreadable(l_in) do
      local p = link.receive(l_in)
      link.transmit(out[self:hash(p) % nqueues], p)
   end
end

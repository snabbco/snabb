-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local base = require("lib.protocol.icmp.base_type")

local du = subClass(base)

-- Class variables
du._name = "destination unreachable"
du._ulp = { method = nil }
du._code_map = {
   [4] = 2 -- Fragmentation needed and DF set aka Packet Too Big
}

du:init({
      -- The original packet follows the header. Because
      -- it is of variable size, it is considered as
      -- payload rather than part of the ICMP message
      -- so it can be retrieved with the datagram
      -- payload() method.
      [1] = ffi.typeof[[
                           struct {
                              uint32_t unused;
                           } __attribute__((packed))
                     ]],
      -- Packet Too Big
      [2] = ffi.typeof[[
                           struct {
                              uint16_t reserved;
                              uint16_t mtu;
                           } __attribute__((packed))
                     ]]
})

function du:mtu (mtu)
   assert(self._header == self._headers[2])
   if mtu ~= nil then
      self:header().mtu = lib.htons(mtu)
   end
   return lib.ntohs(self:header().mtu)
end

return du

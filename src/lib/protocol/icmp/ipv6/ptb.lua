-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local proto_header = require("lib.protocol.header")

local ptb = subClass(proto_header)

-- Class variables
ptb._name = "packet too big"
ptb._ulp = { method = nil }
proto_header.init(ptb,
                  {
                     -- The original packet follows the mtu. Because
                     -- it is of variable size, it is considered as
                     -- payload rather than part of the ICMP message
                     -- so it can be retrieved with the datagram
                     -- payload() method.
                     [1] = ffi.typeof[[
                           struct {
                              uint32_t mtu;
                           } __attribute__((packed))
                     ]]
                  })

-- Instance methods

function ptb:mtu (mtu)
   if mtu ~= nil then
      self:header().mtu = lib.htonl(mtu)
   end
   return lib.ntohl(self:header().mtu)
end

return ptb

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local nd_header = require("lib.protocol.icmp.nd.header")
local proto_header = require("lib.protocol.header")

local ns = subClass(nd_header)

-- Class variables
ns._name = "neighbor solicitation"
ns._ulp = { method = nil }
proto_header.init(ns,
                  {
                     [1] = ffi.typeof[[
                           struct {
                              uint32_t reserved;
                              uint8_t  target[16];
                           }
                     ]]
                  })

-- Class methods

function ns:new (target)
   local o = ns:superClass().new(self)
   o:target(target)
   return o
end

-- Instance methods

function ns:target (target)
   if target ~= nil then
      ffi.copy(self:header().target, target, 16)
   end
   return self:header().target
end

function ns:target_eq (target)
   return C.memcmp(target, self:header().target, 16) == 0
end

return ns

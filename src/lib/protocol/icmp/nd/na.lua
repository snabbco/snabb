module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local bitfield = require("core.lib").bitfield
local nd_header = require("lib.protocol.icmp.nd.header")
local proto_header = require("lib.protocol.header")

local na = subClass(nd_header)

-- Class variables
na._name = "neighbor advertisement"
na._ulp = { method = nil }
proto_header.init(na,
                  {
                     [1] = ffi.typeof[[
                           struct {
                              uint32_t flags;
                              uint8_t  target[16];
                           } __attribute__((packed))
                     ]]
                  })

-- Class methods

function na:new (target, router, solicited, override)
   local o = na:superClass().new(self)
   o:target(target)
   o:router(router)
   o:solicited(solicited)
   o:override(override)
   return o
end

-- Instance methods

function na:target (target)
   if target ~= nil then
      ffi.copy(self:header().target, target, 16)
   end
   return self:header().target
end

function na:target_eq (target)
   return C.memcmp(target, self:header().target, 16) == 0
end

function na:router (r)
   return bitfield(32, self:header(), 'flags', 0, 1, r)
end

function na:solicited (s)
   return bitfield(32, self:header(), 'flags', 1, 1, s)
end

function na:override (o)
   return bitfield(32, self:header(), 'flags', 2, 1, o)
end

return na

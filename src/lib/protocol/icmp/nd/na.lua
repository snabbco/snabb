module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local nd_header = require("lib.protocol.icmp.nd.header")

local na_t
if ffi.abi("le") then
   na_t = ffi.typeof[[
	 struct {
	    uint32_t reserved:5,
	             override:1,
	             solicited:1,
	             router:1,
	             reserved2:24;
	    uint8_t  target[16];
	 } __attribute__((packed))
   ]]
else
   na_t = ffi.typeof[[
	 struct {
	    uint32_t router:1,
                     solicited:1,
                     override:1,
                     reserved:29;
	    uint8_t  target[16];
	 } __attribute__((packed))
   ]]
end

local na = subClass(nd_header)

-- Class variables
na._name = "neighbor advertisement"
na._header_type = na_t
na._header_ptr_type = ffi.typeof("$*", na_t)
na._ulp = { method = nil }

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
   if r ~= nil then
      self:header().router = r
   end
   return self:header().router
end

function na:solicited (s)
   if s ~= nil then
      self:header().solicited = s
   end
   return self:header().solicited
end

function na:override (o)
   if o ~= nil then
      self:header().override = o
   end
   return self:header().override
end

return na

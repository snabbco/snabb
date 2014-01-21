require("class")
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
	 }
   ]]
end

local na = subClass(nd_header)

-- Class variables
na._name = "neighbor advertisement"
na._header_type = na_t
na._ulp = { method = nil }

-- Class methods

function na:_init_new(target, router, solicited, override)
   self._header = na_t()
   ffi.copy(self._header.target, target, 16)
   self._header.router = router
   self._header.solicited = solicited
   self._header.override = override
end

-- Instance methods

function na:target(target)
   if target ~= nil then
      ffi.copy(self._header.target, target, 16)
   end
   return self._header.target
end

function na:target_eq(target)
   return C.memcmp(target, self._header.target, 16) == 0
end

function na:router(r)
   if r ~= nil then
      self._header.router = r
   end
   return self._header.router
end

function na:solicited(s)
   if s ~= nil then
      self._header.solicited = s
   end
   return self._header.solicited
end

function na:override(o)
   if o ~= nil then
      self._header.override = o
   end
   return self._header.override
end

return na

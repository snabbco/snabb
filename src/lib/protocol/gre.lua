require("class")
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local ethernet = require("lib.protocol.ethernet")

-- Only support minimal header for now
local gre_t = ffi.typeof[[
struct {
   uint16_t filler; // flags, version
   uint16_t protocol;
} __attribute__((packed))
]]

local gre = subClass(header)

-- Class variavbles
gre._name = "gre"
gre._header_type = gre_t
gre._ulp = { 
   class_map = { [0x6558] = "lib.protocol.ethernet" },
   method    = 'protocol' }

-- Class methods

function gre:_init_new(protocol)
   local header = gre_t()
   self._header = header
   self:protocol(protocol)
end

function gre:protocol(protocol)
   if protocol ~= nil then
      self._header.protocol = C.htons(protocol)
   else
      return(C.ntohs(self._header.protocol))
   end
end

return gre

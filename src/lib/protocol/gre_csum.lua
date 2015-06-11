module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local gre = require("lib.protocol.gre")
local lib = require("core.lib")

-- This is a subclass of gre that includes a checksum over
-- the payload.

local gre_csum = subClass(gre)

local gre_csum_t = ffi.typeof[[
      struct {
         uint16_t bits; // Flags, version
         uint16_t protocol;
         uint16_t csum;
         uint16_t reserved1;
      }
]]

-- Class variables
gre_csum._name = "gre_csum"
gre_csum._header_type = gre_csum_t
gre_csum._header_ptr_type = ffi.typeof("$*", gre_csum_t)

-- Class methods

function gre_csum:new (config)
   assert(config and config.checksum)
   local o = gre_csum:superClass():superClass().new(self)
   lib.bitfield(16, o:header(), 'bits', 0, 1, 1)
   self._checksum = true
   return o
end

return gre_csum

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local gre = require("lib.protocol.gre")
local lib = require("core.lib")

-- This subclass of gre includes both, a checksum and key field.

local gre_csum_key = subClass(gre)

local gre_csum_key_t = ffi.typeof[[
      struct {
         uint16_t bits; // Flags, version
         uint16_t protocol;
         uint16_t csum;
         uint16_t reserved1;
         uint32_t key;
      }
]]

-- Class variables
gre_csum_key._name = "gre_csum_key"
gre_csum_key._header_type = gre_csum_key_t
gre_csum_key._header_ptr_type = ffi.typeof("$*", gre_csum_key_t)

-- Class methods

function gre_csum_key:new (config)
   assert(config and config.checksum and config.key)
   local o = gre_csum_key:superClass():superClass().new(self)
   lib.bitfield(16, o:header(), 'bits', 0, 1, 1)
   lib.bitfield(16, o:header(), 'bits', 2, 1, 1)
   self._checksum = true
   self._key = true
   o:key(config.key)
   return o
end

return gre_csum_key

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local gre = require("lib.protocol.gre")
local lib = require("core.lib")

-- This is a subclass of gre that includes a 32-bit key field

local gre_key = subClass(gre)

local gre_key_t = ffi.typeof[[
      struct {
	 uint16_t bits; // Flags, version
	 uint16_t protocol;
	 uint32_t key;
      }
]]

-- Class variables
gre_key._name = "gre_key"
gre_key._header_type = gre_key_t
gre_key._header_ptr_type = ffi.typeof("$*", gre_key_t)

-- Class methods

function gre_key:new (config)
   assert(config and config.key)
   local o = gre_key:superClass():superClass().new(self)
   lib.bitfield(16, o:header(), 'bits', 2, 1, 1)
   self._key = true
   o:key(config.key)
   return o
end

return gre_key

module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")
-- 

-- GRE uses a variable-length header as specified by RFCs 2784 and
-- 2890.  The actual size is determined by flag bits in the base
-- header.  This implementation only supports the checksum and key
-- extensions.  Note that most of the flags specified in the original
-- specification of RFC1701 have been deprecated.

local gre_template = [[
      struct {
	 uint16_t bits; // Flags, version
	 uint16_t protocol;
	 uint8_t  options[$];
      }
]]

-- Three different sizes depending on the options used
local gre_types = { [0] = ffi.typeof(gre_template, 0),
		    [4] = ffi.typeof(gre_template, 4),
		    [8] = ffi.typeof(gre_template, 8), }
local gre_ptr_types = { [0] = ffi.typeof("$*", gre_types[0]),
			[4] = ffi.typeof("$*", gre_types[4]),
			[8] = ffi.typeof("$*", gre_types[8]) }
local gre = subClass(header)

-- Class variables
gre._name = "gre"
gre._header_type = gre_types[0]
gre._header_ptr_type = gre_ptr_types[0]
gre._ulp = { 
   class_map = { [0x6558] = "lib.protocol.ethernet" },
   method    = 'protocol' }

-- Class methods

function gre:new (config)
   local o = gre:superClass().new(self)
   local opt_size = 0
   if config.checksum then
      opt_size = opt_size + 4
      o._checksum = true
   end
   if config.key ~= nil then
      o._key_offset = opt_size
      opt_size = opt_size + 4
   end
   if opt_size > 0 then
      o._header_type = gre_types[opt_size]
      o._header_ptr_type = gre_ptr_types[opt_size]
      o._header = o._header_type()
   end
   if o._checksum then
      lib.bitfield(16, o._header, 'bits', 0, 1, 1)
   end
   if o._key_offset ~= nil then
      lib.bitfield(16, o._header, 'bits', 2, 1, 1)
      o:key(config.key)
   end
   o:protocol(config.protocol)
   return o
end

function gre:new_from_mem (mem, size)
   local o = gre:superClass().new_from_mem(self, mem, size)
   -- Reserved bits and version MUST be zero
   if lib.bitfield(16, o._header, 'bits', 4, 12) ~= 0 then
      o:free()
      return nil
   end
   local opt_size = 0
   if o:use_checksum() then
      opt_size = opt_size + 4
      o._checksum = true
   end
   if o:use_key() then
      o._key_offset = opt_size
      opt_size = opt_size + 4
   end
   if opt_size > 0 then
      o._header_type = gre_types[opt_size]
      o._header_ptr_type = gre_ptr_types[opt_size]
      o._header = ffi.cast(o._header_ptr_type, self._header)[0]
   end
   return o
end

-- Instance methods

function gre:free ()
   -- Make sure that this object uses the base header from the gre
   -- class when it is being recycled
   self._header_type = nil
   self._header_ptr_type = nil
   gre:superClass().free(self)
end

function gre:checksum (payload, length)
   assert(self._checksum)
   local csum_ptr = ffi.cast(ffi.typeof("uint16_t *"),
			    ffi.cast(ffi.typeof("uint8_t*"), self._header)
			    + ffi.offsetof(self._header, 'options'))
   local csum = lib.update_csum(self._header, ffi.sizeof(self._header), 0)
   csum = lib.update_csum(payload, length, csum)
   csum_ptr[0] = C.htons(lib.finish_csum(csum))
end

function gre:use_checksum ()
   return lib.bitfield(16, self._header, 'bits', 0, 1) == 1
end

function gre:key (key)
   if not self._key_offset then
      return nil
   end
   local key_ptr = ffi.cast(ffi.typeof("uint32_t *"),
			    ffi.cast(ffi.typeof("uint8_t*"), self._header)
			    + ffi.offsetof(self._header, 'options')
			 + self._key_offset)
   if key ~= nil then
      key_ptr[0] = C.htonl(key)
   else
      return C.ntohl(key_ptr[0])
   end
end

function gre:use_key ()
   return lib.bitfield(16, self._header, 'bits', 2, 1) == 1
end

function gre:protocol (protocol)
   if protocol ~= nil then
      self._header.protocol = C.htons(protocol)
   end
   return(C.ntohs(self._header.protocol))
end

return gre

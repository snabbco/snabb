require("class")
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")
-- 

local gre_template = [[
      struct {
	 uint16_t bits; // Flags, version
	 uint16_t protocol;
	 uint8_t  options[$];
      }
]]

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

function gre:_init_new(config)
   local opt_size = 0
   if config.checksum then
      opt_size = opt_size + 4
      self._checksum = true
   end
   if config.key ~= nil then
      self._key_offset = opt_size
      opt_size = opt_size + 4
   end
   self._header_type = gre_types[opt_size]
   self._header_ptr_type = gre_ptr_types[opt_size]
   self._header = self._header_type()
   if self._checksum then
      lib.bitfield(16, self._header, 'bits', 0, 1, 1)
   end
   if self._key_offset ~= nil then
      lib.bitfield(16, self._header, 'bits', 2, 1, 1)
      self:key(config.key)
   end
   self:protocol(config.protocol)
end

function gre:_init_new_from_mem(mem, size)
   local sizeof = ffi.sizeof(gre._header_type)
   assert(sizeof <= size)
   local header = ffi.cast(gre._header_ptr_type, mem)[0]
   -- Reserved bits and version MUST be zero
   if lib.bitfield(16, header, 'bits', 4, 12) ~= 0 then
      self = nil
      return
   end
   self._header = header
   local opt_size = 0
   if self:use_checksum() then
      opt_size = opt_size + 4
      self._checksum = true
   end
   if self:use_key() then
      self._key_offset = opt_size
      opt_size = opt_size + 4
   end
   if opt_size > 0 then
      self._header_type = gre_types[opt_size]
      self._header_ptr_type = gre_ptr_types[opt_size]
      self._header = ffi.cast(self._header_ptr_type, self._header)[0]
   end
end

-- Instance methods

function gre:checksum(payload, length)
   assert(self._checksum)
   local csum_ptr = ffi.cast(ffi.typeof("uint16_t *"),
			    ffi.cast(ffi.typeof("uint8_t*"), self._header)
			    + ffi.offsetof(self._header, 'options'))
   local csum = lib.update_csum(self._header, ffi.sizeof(self._header), 0)
   csum = lib.update_csum(payload, length, csum)
   csum_ptr[0] = C.htons(lib.finish_csum(csum))
end

function gre:use_checksum()
   return lib.bitfield(16, self._header, 'bits', 0, 1) == 1
end

function gre:key(key)
   assert(self._key_offset)
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

function gre:use_key()
   return lib.bitfield(16, self._header, 'bits', 2, 1) == 1
end

function gre:protocol(protocol)
   if protocol ~= nil then
      self._header.protocol = C.htons(protocol)
   end
   return(C.ntohs(self._header.protocol))
end

return gre

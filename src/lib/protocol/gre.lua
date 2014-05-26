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

local gre = subClass(header)

-- Four different headers depending on the options used
local gre_types = { base = ffi.typeof[[
			  struct {
			     uint16_t bits; // Flags, version
			     uint16_t protocol;
			  }]],
		    csum = ffi.typeof[[
			  struct {
			     uint16_t bits; // Flags, version
			     uint16_t protocol;
			     uint16_t csum;
			     uint16_t reserved1;
			  }]],
		    key = ffi.typeof[[
			  struct {
			     uint16_t bits; // Flags, version
			     uint16_t protocol;
			     uint32_t key;
			  }]],
		    csum_key = ffi.typeof[[
			  struct {
			     uint16_t bits; // Flags, version
			     uint16_t protocol;
			     uint16_t csum;
			     uint16_t reserved1;
			     uint32_t key;
			  }]],
		 }
local gre_ptr_types = {}
for k, v in pairs(gre_types) do
   gre_ptr_types[k] = ffi.typeof("$*", v)
end

-- Class variables
gre._name = "gre"
gre._header_type = gre_types.base
gre._header_ptr_type = gre_ptr_types.base
gre._ulp = { 
   class_map = { [0x6558] = "lib.protocol.ethernet" },
   method    = 'protocol' }

-- Class methods

function gre:new (config)
   local o = gre:superClass().new(self)
   local type = nil
   if config.checksum then
      o._checksum = true
      type = 'csum'
   else
      o._checksum = false
   end
   if config.key ~= nil then
      o._key = true
      if type then
	 type = 'csum_key'
      else
	 type = 'key'
      end
   else
      o._key = false
   end
   if type then
      o._header_type = gre_types[type]
      o._header_ptr_type = gre_ptr_types[type]
      o._header = o._header_type()
   end
   if o._checksum then
      lib.bitfield(16, o._header, 'bits', 0, 1, 1)
   end
   if o._key then
      lib.bitfield(16, o._header, 'bits', 2, 1, 1)
      o:key(config.key)
   end
   o:protocol(config.protocol)
   return o
end

function gre:new_from_mem (mem, size)
   local o = gre:superClass().new_from_mem(self, mem, size)
   -- Reserved bits and version MUST be zero.  We don't support
   -- the sequence number option, i.e. the 'S' flag (bit 3) must
   -- be cleared as well
   if lib.bitfield(16, o._header, 'bits', 3, 13) ~= 0 then
      o:free()
      return nil
   end
   local type = nil
   if lib.bitfield(16, o._header, 'bits', 0, 1) == 1 then
      o._checksum = true
      type = 'csum'
   else
      o._checksum = false
   end
   if lib.bitfield(16, o._header, 'bits', 2, 1) == 1 then
      o._key = true
      if type then
	 type = 'csum_key'
      else
	 type = 'key'
      end
   else
      o._key = false
   end
   if type then
      o._header_type = gre_types[type]
      o._header_ptr_type = gre_ptr_types[type]
      o._header = ffi.cast(o._header_ptr_type, mem)[0]
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

local function checksum(header, payload, length)
   local csum_in = header.csum;
   header.csum = 0;
   header.reserved1 = 0;
   local csum = lib.finish_csum(lib.update_csum(payload, length,
						lib.update_csum(header, ffi.sizeof(header), 0)))
   header.csum = csum_in
   return csum
end

-- Returns nil if checksumming is disabled.  If payload and length is
-- supplied, the checksum is written to the header and returned to the
-- caller.  With nil arguments, the current checksum is returned.
function gre:checksum (payload, length)
   if not self._checksum then
      return nil
   end
   if payload ~= nil then
      -- Calculate and set the checksum
      self._header.csum = C.htons(checksum(self._header, payload, length))
   end
   return C.ntohs(self._header.csum)
end

function gre:checksum_check (payload, length)
   if not self._checksum then
      return true
   end
   return checksum(self._header, payload, length) == C.ntohs(self._header.csum)
end

-- Returns nil if keying is disabled. Otherwise, the key is set to the
-- given value or the current key is returned if called with a nil
-- argument.
function gre:key (key)
   if not self._key then
      return nil
   end
   if key ~= nil then
      self._header.key = C.htonl(key)
   else
      return C.ntohl(self._header.key)
   end
end

function gre:protocol (protocol)
   if protocol ~= nil then
      self._header.protocol = C.htons(protocol)
   end
   return(C.ntohs(self._header.protocol))
end

return gre

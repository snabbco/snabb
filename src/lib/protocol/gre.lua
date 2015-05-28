module(..., package.seeall)
local ffi = require("ffi")
local C = ffi.C
local header = require("lib.protocol.header")
local lib = require("core.lib")
local bitfield = lib.bitfield
local ipsum = require("lib.checksum").ipsum

-- GRE uses a variable-length header as specified by RFCs 2784 and
-- 2890.  The actual size is determined by flag bits in the base
-- header.  This implementation only supports the checksum and key
-- extensions.  Note that most of the flags specified in the original
-- specification of RFC1701 have been deprecated.
--
-- The gre class implements the base header (without checksum and
-- key).  The combinations with checksum and key are handled by the
-- subclasses gre_csum, gre_key and gre_csum_key

local gre = subClass(header)

local gre_t = ffi.typeof[[
      struct {
	 uint16_t bits; // Flags, version
	 uint16_t protocol;
      }
]]

local subclasses = { csum     = "lib.protocol.gre_csum",
		     key      = "lib.protocol.gre_key",
		     csum_key = "lib.protocol.gre_csum_key" }

-- Class variables
gre._name = "gre"
gre._header_type = gre_t
gre._header_ptr_type = ffi.typeof("$*", gre_t)
gre._ulp = { 
   class_map = { [0x6558] = "lib.protocol.ethernet" },
   method    = 'protocol' }

-- Pre-allocated array for initial parsing in new_from_mem()
local parse_mem = ffi.typeof("$[1]", gre._header_ptr_type)()

-- Class methods

function gre:new (config)
   local type = nil
   if config then
      if config.checksum then
	 type = 'csum'
      end
      if config.key ~= nil then
	 if type then
	    type = 'csum_key'
	 else
	    type = 'key'
	 end
      end
   end

   local o
   if type then
      local subclass = subclasses[type]
      o = (package.loaded[subclass] or require(subclass)):new(config)
   else
      o = gre:superClass().new(self)
   end
   o:protocol(config.protocol)
   return o
end

function gre:new_from_mem (mem, size)
   parse_mem[0] = ffi.cast(self._header_ptr_type, mem)
   -- Reserved bits and version MUST be zero.  We don't support
   -- the sequence number option, i.e. the 'S' flag (bit 3) must
   -- be cleared as well
   if bitfield(16, parse_mem[0], 'bits', 3, 13) ~= 0 then
      return nil
   end
   local type = nil
   local has_csum, has_key = false, false
   if bitfield(16, parse_mem[0], 'bits', 0, 1) == 1 then
      type = 'csum'
      has_csum = true
   end
   if bitfield(16, parse_mem[0], 'bits', 2, 1) == 1 then
      if type then
	 type = 'csum_key'
      else
	 type = 'key'
      end
      has_key = true
   end
   local class = self
   if type then
      local subclass = subclasses[type]
      class = package.loaded[subclass] or require(subclass)
   end
   local o = gre:superClass().new_from_mem(class, mem, size)
   o._checksum = has_csum
   o._key = has_key
   return o
end

-- Instance methods

local function checksum(header, payload, length)
   local csum_in = header.csum;
   header.csum = 0;
   header.reserved1 = 0;
   local csum = ipsum(payload, length,
		      bit.bnot(ipsum(ffi.cast("uint8_t *", header),
				     ffi.sizeof(header), 0)))
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
      self:header().csum = C.htons(checksum(self:header(), payload, length))
   end
   return C.ntohs(self:header().csum)
end

function gre:checksum_check (payload, length)
   if not self._checksum then
      return true
   end
   return checksum(self:header(), payload, length) == C.ntohs(self:header().csum)
end

-- Returns nil if keying is disabled. Otherwise, the key is set to the
-- given value or the current key is returned if called with a nil
-- argument.
function gre:key (key)
   if not self._key then
      return nil
   end
   if key ~= nil then
      self:header().key = C.htonl(key)
   else
      return C.ntohl(self:header().key)
   end
end

function gre:protocol (protocol)
   if protocol ~= nil then
      self:header().protocol = C.htons(protocol)
   end
   return(C.ntohs(self:header().protocol))
end

return gre

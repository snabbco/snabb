-- Subclass of ipc.shmem.shmem that handles data types from the SMIv2
-- specification.
--
-- It defines the name space "MIB", which uses the default index
-- format.  By definition, the object names must be literal OIDs or
-- textual object identifiers that can be directly translated into
-- OIDs through a MIB (e.g. ".1.3.6.1.2.1.1.3" or "sysUpTime").  Names
-- that do not comply to this requirement can be used upon agreement
-- between the producer and consumer of an instance of this class.  By
-- convention, such names must be prefixed with the string'_X_'.  The
-- mib class itself treats the names as opaque objects.
--
-- The intended consumer of this data is an SNMP agent or sub-agent
-- (that necessarily runs on the same host) which is able to serve the
-- sub-trees that cover all of the OIDs in the index to regular SNMP
-- clients (e.g. monitoring stations).  It is recommended that the
-- OIDs do *not* include any indices for conceptual rows of the
-- relevant MIB (this includes the ".0" instance id of scalar
-- objects).  The SNMP (sub-)agent should know the structure of the
-- MIB and construct all indices itself.  This may require the
-- inclusion of non-MIB objects in the data file for MIBs whose
-- specification does not include the index objects themselves (which
-- represents an example of the situation where the consumer and
-- producer will have to agree upon a naming convention beyond the
-- regular name space).
--
-- Usage of the numerical data types is straight forward.  Octet
-- strings are encoded as a sequence of a 2-byte length field (uint16)
-- followed by the indicated number of bytes.  The maximum length is
-- fixed upon creation of the container of the string.  The size of
-- the object (as registered in the index file) is 2+n, where n is the
-- maximum length of the octet string.  This module does not make use
-- of ASN.1 in any form :)
--
module(..., package.seeall)

local ffi = require("ffi")
local bit = require("bit")
local bor, band, lshift, rshift = bit.bor, bit.band, bit.lshift, bit.rshift
local shmem = require("lib.ipc.shmem.shmem")

local mib = subClass(shmem)
mib._name = "MIB shared memory"
mib._namespace = "MIB:1"

local int32_t = ffi.typeof("int32_t")
local uint32_t = ffi.typeof("uint32_t")
local uint64_t = ffi.typeof("uint64_t")
local octetstr_types = {}
local function octetstr_t (length)
   assert(length <= 65535)
   if octetstr_types[length] then
      return octetstr_types[length]
   else
      local type = ffi.typeof(
	 [[
	       struct { uint16_t length; 
			uint8_t data[$]; 
		     } __attribute__((packed))
	 ]], length)
      octetstr_types[length] = type
      return type
   end
end

-- Base types including the BITS construct according to the SMIv2, RFC
-- 2578 (Section 7.1) and their mapping onto the ctypes used to store
-- them in the context of the shmem system. The default 'OctetStr'
-- supports octet strings up to 255 bytes.
local types = { Integer32 = int32_t,
		Unsigned32 = uint32_t,
		OctetStr = octetstr_t(255),
		Counter32 = uint32_t,
		Counter64 = uint64_t,
		Gauge32 = uint32_t,
		TimeTicks = uint32_t,
		Bits = octetstr_t(16),
	     }

-- The 'type' argument of the constructor must either be a string that
-- identifies one of the supported types
--
--  Integer32
--  Unsigned32
--  OctetStr
--  Counter32
--  Counter64
--  Gauge32
--  TimeTicks
--  Bits
--
-- or a table of the form { type = 'OctetStr', length = <length> },
-- where <length> is an integer in the range 0..65535.  The simple
-- type 'OctetStr' is equivalent to the extended OctetStr type with
-- length=255.  An OctetStr can hold any sequence of bytes up to a
-- length of <length>.  The sequence is passed as a Lua string to the
-- register() and set() methods and received as such from the get()
-- method.
--
-- The Bits pseudo-type is mapped to an OctetStr of length 16.  The
-- SMIv2 specifies no maximum number of enumerable bits (except the
-- one implied by the maximum size of an octet string, of course), but
-- also notes that values in excess of 128 bits are likely to cause
-- interoperability problems.  This implementation uses a limit of 128
-- bits, i.e. the underlying OctetStr is of length 16.  To keep things
-- simple, all Bits object use the same size.  Note that if no initial
-- value is specified, the resulting octet string will have length
-- zero.
--
-- The "type" field of the table may also contain any of the other
-- valid types.  In this case, all other fields in the table are
-- ignored and the method behaves as if the type had been passed as a
-- string.
function mib:register (name, type, value)
   assert(name and type)
   local ctype
   local smi_type = type
   if _G.type(type) == 'table' then
      assert(type.type)
      smi_type = type.type
      if type.type == 'OctetStr' then
	 assert(type.length and type.length <= 65535)
	 ctype = octetstr_t(type.length)
      else
	 -- Accept all other legal types
	 type = type.type
      end
   end
   ctype = ctype or types[type]
   if ctype == nil then
      error("illegal SMIv2 type "..type)
   end
   local ptr = mib:superClass().register(self, name, ctype)
   self._objs[name].smi_type = smi_type
   self:set(name, value)
   return ptr
end

-- Extension of the base set() method for objects of type OctetStr and
-- Bits.
--
-- For OctetStr, the value must be a Lua string, which will be
-- stored in the "data" portion of the underlying octet string data
-- type.  The string is truncated to the maximum size of the object.
--
-- For Bits, the value must be an array whose values specify which of
-- the bits in the underlying OctetStr must be set to one according to
-- the enumeration rule of the BITS construct as explained for the
-- get() method.  The length of the octet string is always set to 16
-- bytes for every set() operation.
function mib:set (name, value)
   if value ~= nil then
      local obj = self._objs[name]
      if obj and obj.smi_type == 'OctetStr' then
	 local length = math.min(string.len(value), obj.length - 2)
	 local octet = mib:superClass().get(self, name)
	 octet.length = length
	 ffi.copy(octet.data, value, length)
      elseif obj and obj.smi_type == 'Bits' then
	 local octet = mib:superClass().get(self, name)
	 octet.length = 16
	 ffi.fill(octet.data, 16)
	 local i = 1
	 while value[i] do
	    local bit_n = value[i]
	    local byte = rshift(bit_n, 3)
	    octet.data[byte] = bor(octet.data[byte],
				   lshift(1, 7-band(bit_n, 7)))
	    i = i+1
	 end
      else
	 mib:superClass().set(self, name, value)
      end
   end
end

-- Extension of the base get() method for objects of type OctetStr and
-- Bits.
--
-- For OctetStr, the returned value is the "data" portion of the
-- underlying octet string, converted to a Lua string.
--
-- For Bits, the returned value is an array that contains the numbers
-- of the bits which are set in the underlying OctetStr according to
-- the enumeration rules of the BITS construct, i.e. byte #0 is the
-- first byte in the OctetStr and bit #0 in a byte is the leftmost bit
-- etc.  To avoid a table allocation, the caller may pass a table as
-- the second argument, which will be filled with the result instead.
function mib:get (name, ...)
   local octet = mib:superClass().get(self, name)
   local obj = self._objs[name]
   if obj.smi_type == 'OctetStr' then
      return ffi.string(octet.data, octet.length)
   elseif obj.smi_type == 'Bits' then
      local result = ... or {}
      local index = 1
      for i = 0, 15 do
	 local byte = octet.data[i]
	 for j = 0, 7 do
	    if band(byte, lshift(1, 7-j)) ~= 0 then
	       result[index] = i*8+j
	       index = index+1
	    end
	 end
      end
      result[index] = nil
      return result
   else
      return octet
   end
end

return mib

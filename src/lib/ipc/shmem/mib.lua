-- Subclass of ipc.shmem.shmem that handles data types from the SMIv2
-- specification.
--
-- It defines the name space "MIB", which uses the default index
-- format.  By definition, the object names must be literal OIDs or
-- textual object identifiers that can be directly translated into
-- OIDs through a MIB (e.g. ".1.3.6.1.2.1.1.3" or "sysUpTime").  Names
-- that do not comply to this requirement can be used upon agreement
-- between the producer and consumer of an instance of this class.
--
-- The intended consumer of this data is an SNMP agent or sub-agent
-- that runs on the same host and is able to serve the sub-trees that
-- cover all of the OIDs in the index to regular SNMP clients
-- (e.g. monitoring stations).  It is recommended that the OIDs do
-- *not* include any indices for conceptual rows of the relevant MIB
-- (this includes the ".0" instance id of scalar objects).  The SNMP
-- (sub-)agent should know the structure of the MIB and construct all
-- indices itself.  This may require the inclusion of non-MIB objects
-- in the data file for MIBs whose specification does not include the
-- index objects in the rows itself (which represents an example of
-- the situation where the consumer and producer will have to agree
-- upon a naming convention beyond the regular name space).
--
-- Usage of the numerical data types is straight forward.  Octet
-- strings are encoded as a sequence of a 2-byte length field (uint16)
-- followed by the indicated number of bytes.  The maximum length is
-- fixed upon creation of the container of the string.  The size of
-- the object (as registered in the index file) is 1+n, where n is the
-- maximum length of the octet string.
--
module(..., package.seeall)

local ffi = require("ffi")
local shmem = require("lib.ipc.shmem.shmem")

local mib = subClass(shmem)
mib._name = "MIB shared memory"
mib._namespace = "MIB:1"

local int32_t = ffi.typeof("int32_t")
local uint32_t = ffi.typeof("uint32_t")
local uint64_t = ffi.typeof("uint64_t")
local octetstr_types = {}
local function octetstr_t (size)
   assert(size <= 65535)
   if octetstr_types[size] then
      return octetstr_types[size]
   else
      local type = ffi.typeof(
	 [[
	       struct { uint16_t length; 
			uint8_t data[$]; 
		     } __attribute__((packed))
	 ]], size)
      octetstr_types[size] = type
      return type
   end
end

-- Types according to the SMIv2, RFC 2578 (Section 7.1). The default
-- 'OctetStr' supports octet strings up to 255 bytes.
local types = { Integer32 = int32_t,
		Unsigned32 = uint32_t,
		OctetStr = octetstr_t(255),
		Counter32 = uint32_t,
		Counter64 = uint64_t,
		Gauge32 = uint32_t,
		TimeTicks = uint32_t,
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
--
-- or a table of the form { type = 'OctetStr', length = <length> },
-- where <length> is an integer in the range 0..65535.  The simple
-- type 'OctetStr' is equivalent to the extended OctetStr type with
-- length=255.  An OctetStr can hold any sequence of bytes up to a
-- length of <length>.  The sequence is passed as a Lua string to the
-- register() and set() methods and received as such from the get()
-- method.
--
-- The "type" field of the table may also contain any of the other
-- valid types.  In this case, all other fields in the table are
-- ignored and the method behaves as if the type had been passed as a
-- string.
function mib:register (name, type, value)
   assert(name and type)
   local ctype
   local octetstr_p = false
   if _G.type(type) == 'table' then
      if type.type == 'OctetStr' then
	 assert(type.length and type.length <= 65535)
	 ctype = octetstr_t(type.length)
	 octetstr_p = true
      else
	 -- Accept all other legal types
	 type = type.type
      end
   elseif type == 'OctetStr' then
      octetstr_p = true
   end
   ctype = ctype or types[type]
   if ctype == nil then
      error("illegal SMIv2 type "..type)
   end
   local ptr = mib:superClass().register(self, name, ctype)
   self._objs[name].octetstr_p = octetstr_p
   self:set(name, value)
   return ptr
end

-- Same as the base method, except for objects of type OctetStr.  In
-- this case, the value must be a Lua string, which will be stored in
-- the "data" portion of the underlying octet string data type.  The
-- string is truncated to the maximum size of the object.
function mib:set (name, value)
   local obj = self._objs[name]
   if obj and obj.octetstr_p and value ~= nil then
      local length = math.min(string.len(value), obj.length - 2)
      local octet = mib:superClass().get(self, name)
      octet.length = length
      ffi.copy(octet.data, value, length)
   else
      mib:superClass().set(self, name, value)
   end
end

-- Same as the base method, except for objects of type OctetStr.  In
-- this case, the returned value is the "data" portion of the
-- underlying octet string, converted to a Lua string.
function mib:get (name)
   local octet = mib:superClass().get(self, name)
   local obj = self._objs[name]
   if obj.octetstr_p then
      return ffi.string(octet.data, octet.length)
   else
      return octet
   end
end

return mib

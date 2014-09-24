module(..., package.seeall)
local ffi = require("ffi")

local tlv = subClass(nil)

ffi.cdef[[
      typedef struct {
	 uint8_t type;
	 uint8_t length;
      } tlv_t __attribute__((packed))
]]

local tlv_t = ffi.typeof("tlv_t")

local tlv_ptr_t = ffi.typeof("$ *", tlv_t)
tlv._types = {
   [1] = {
      name  = "src_ll_addr",
      class = "lib.protocol.icmp.nd.options.lladdr"
   },
   [2] = {
      name  = "tgt_ll_addr",
      class = "lib.protocol.icmp.nd.options.lladdr"
   },
}

-- Will be overriden for known types
tlv._name = "unkown"

function tlv:new (type, data)
   assert(tlv._types[type], "tlv: unsupported type")
   local size = ffi.sizeof(tlv_t)+ffi.sizeof(data)
   assert(size%8 == 0)
   local o = tlv:superClass().new(self)
   local tlv = ffi.typeof("struct { tlv_t tlv; uint8_t data[$]; }", ffi.sizeof(data))()
   tlv.tlv.type = type
   tlv.tlv.length = size/8
   ffi.copy(tlv.data, data, ffi.sizeof(data))
   o._tlv = tlv
   o._option = require(o._types[type].class):new_from_mem(tlv.data, ffi.sizeof(data))
   return o
end

function tlv:new_from_mem (mem, size)
   local o = tlv:superClass().new(self)
   local tlv_t_size = ffi.sizeof(tlv_t)
   assert(tlv_t_size <= size)
   local tlv = ffi.cast(tlv_ptr_t, mem) 
   assert(o._types[tlv.type], "tlv: unsupported type")
   o._name = o._types[tlv.type].name
   local class = o._types[tlv.type].class
   o._option = require(class):new_from_mem(mem + tlv_t_size,
					   size - tlv_t_size)
   local t = ffi.typeof("struct { tlv_t tlv; uint8_t data[$]; }", size-tlv_t_size)
   o._tlv = ffi.cast(ffi.typeof("$*", t), mem)
   return o
end

function tlv:name ()
   return self._name
end

function tlv:type (type)
   if type ~= nil then
      assert(self._types[type])
      self._tlv.tlv.type = type
   end
   return self._tlv.tlv.type
end

-- This is in units of 8 bytes
function tlv:length ()
   return self._tlv.tlv.length
end

function tlv:data ()
   return self._tlv.data
end

function tlv:tlv ()
   return self._tlv
end

function tlv:option ()
   return self._option
end

return tlv

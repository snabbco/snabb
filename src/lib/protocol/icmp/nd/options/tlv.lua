local ffi = require("ffi")

local tlv = subClass(nil, 'new_from_mem')

local tlv_t = ffi.typeof[[
      struct {
	 uint8_t type;
	 uint8_t length;
      } __attribute__((packed))
]]

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

function tlv:_init_new(type)
end

function tlv:_init_new_from_mem(mem, size)
   local tlv_t_size = ffi.sizeof(tlv_t)
   assert(tlv_t_size <= size)
   local tlv = ffi.cast(ffi.typeof("$ *", tlv_t), mem) 
   self._tlv = tlv
   local class = self._types[tlv.type].class
   if class ~= nil then
      self._option =
	 require(class):new_from_mem(mem + tlv_t_size,
				     size - tlv_t_size)
      self._name = self._types[tlv.type].name
   end
   return tlv
end

function tlv:name()
   return self._name
end

function tlv:type(type)
   if type ~= nil then
      assert(self._types[type])
      self._tlv.type = type
   end
   return self._tlv.type
end

-- This is in units of 8 bytes
function tlv:length()
   return self._tlv.length
end

function tlv:option()
   return self._option
end

return tlv

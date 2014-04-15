local ffi = require("ffi")

local lladdr = subClass(nil, 'new_from_mem')

local lladdr_t = ffi.typeof[[
      struct {
	 uint8_t lladdr[6];
      }
]]

-- Class variables
lladdr._name = 'll_addr'

-- Class methods
function lladdr:_init_new_from_mem (mem, size)
   assert(size >= ffi.sizeof(lladdr_t))
   self._lladdr = ffi.cast(ffi.typeof("$ *", lladdr_t), mem)
end

-- Instance methods
function lladdr:name ()
   return self._name
end

function lladdr:addr (lladdr)
   if lladdr ~= nil then
      ffi.copy(self._lladdr, lladdr, 6)
   end
   return self._lladdr.lladdr
end

return lladdr

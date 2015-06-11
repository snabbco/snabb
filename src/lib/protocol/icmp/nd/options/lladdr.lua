module(..., package.seeall)
local ffi = require("ffi")

local lladdr = subClass(nil)

local lladdr_t = ffi.typeof[[
      struct {
         uint8_t lladdr[6];
      }
]]

local lladdr_ptr_t = ffi.typeof("$ *", lladdr_t)

-- Class variables
lladdr._name = 'll_addr'

-- Class methods
function lladdr:new (addr)
   local o = lladdr:superClass().new(self)
   o._lladdr = lladdr_t()
   ffi.copy(o._lladdr.lladdr, addr, 6)
   return o
end

function lladdr:new_from_mem (mem, size)
   local o = lladdr:superClass().new(self)
   assert(size >= ffi.sizeof(lladdr_t))
   o._lladdr = ffi.cast(lladdr_ptr_t, mem)
   return o
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

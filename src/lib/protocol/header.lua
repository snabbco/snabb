-- Protocol header base class

require("class")
local ffi = require("ffi")

local header = subClass(nil, 'new_from_mem')

function header:_init_new_from_mem(mem, size)
   assert(ffi.sizeof(self._header_type) <= size)
   self._header = ffi.cast(self._header_ptr_type, mem)[0]
end

function header:header()
   return self._header
end

function header:name()
   return self._name
end

function header:sizeof()
   return ffi.sizeof(self._header)
end

-- Copy the header to some location in memory (usually a packet
-- buffer).  The caller must make sure that there is enough space at
-- the destination.
function header:copy(dst)
   ffi.copy(dst, self._header, ffi.sizeof(self._header))
end

-- Create a new protocol instance that is a copy of this instance.
-- This is horribly inefficient and should not be used in the fast
-- path.
function header:clone()
   local header = self._header_type()
   local sizeof = ffi.sizeof(header)
   ffi.copy(header, self._header, sizeof)
   return self:class():new_from_mem(header, sizeof)
end

-- Return the class that can handle the upper layer protocol or nil if
-- the protocol is not supported or the protocol has no upper-layer.
function header:upper_layer()
   local method = self._ulp.method
   if not method then return nil end
   local class = self._ulp.class_map[self[method](self)]
   if class then
      if package.loaded[class] then
	 return package.loaded[class]
      else
	 return require(class)
      end
   else
      return nil
   end
end

return header

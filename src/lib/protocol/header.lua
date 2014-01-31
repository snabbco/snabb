-- Protocol header base class

require("class")
local ffi = require("ffi")

local header = subClass(nil, 'new_from_mem')

function header:_init_new_from_mem(mem, size)
   assert(ffi.sizeof(self._header_type) <= size)
   self._header = ffi.cast(ffi.typeof("$ *", self._header_type), mem)[0]
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

-- Move the header to a different location.  The caller must make sure
-- that there is enough space at the destination.
function header:moveto(dst)
   ffi.copy(dst, self._header, ffi.sizeof(self._header))
   -- let old data be garbage collected
   self._header = nil
   self._header = ffi.cast(ffi.typeof("$*", self._header_type), dst)[0]
end

-- Return the class that can handle the upper layer protocol or nil if
-- the protocol is not supported or the protocol has no upper-layer.
function header:upper_layer()
   local method = self._ulp.method
   if not method then return nil end
   local class = self._ulp.class_map[self[method](self)]
   if class then
      return require(class)
   else
      return nil
   end
end

function header:clone()
   local header = self._header_type()
   local sizeof = ffi.sizeof(header)
   ffi.copy(header, self._header, sizeof)
   return self:class():new_from_mem(header, sizeof)
end

return header

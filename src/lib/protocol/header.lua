-- Protocol header base class

require("class")
local ffi = require("ffi")

local header = subClass(nil, 'new_from_mem', 'new_clone')

function header:_init_new_from_mem(mem, size)
   assert(self:sizeof() <= size)
   self._header = ffi.cast(self:ptr_typeof(), mem)
end

function header:_init_new_clone(proto)
   self._header = self:typeof()()
   ffi.copy(self._header, proto:header(), proto:sizeof())
end

function header:header()
   return self._header
end

function header:name()
   return(self._name)
end

function header:typeof()
   return(self._header_type)
end

function header:ptr_typeof()
   return(ffi.typeof("$ *", self._header_type))
end

function header:sizeof()
   return(ffi.sizeof(self._header_type))
end

-- Move the header to a different location.  The caller must make sure
-- that there is enough space at the destination.
function header:moveto(dst)
   ffi.copy(dst, self._header, self:sizeof())
   -- let old data be garbage collected
   self._header = nil
   self._header = ffi.cast(self:ptr_typeof(), dst)
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

function header:checksum()
end

return header

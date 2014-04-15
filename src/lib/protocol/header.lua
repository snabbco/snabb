-- Protocol header base class
--
-- This is an abstract class (should not be instantiated)
--
-- Derived classes must implement the following class variables
--
-- _name          a string that describes the header type in a
--                human readable form
--
-- _header_type   a constructor for the C type object that stores
--                the actual header.  Typically the result of
--                ffi.typeof("struct ...")
--
-- _header_ptr_type a C type object for the pointer to the header
--                  type, i.e. ffi/typeof("$*", _header_type)
--                  This is pre-defined here for performance.
--
-- _ulp           a table that holds information about the "upper
--                layer protocols" supported by the header.  It
--                contains two keys
--                  method   the name of the method of the header
--                           class whose result identifies the ULP
--                           and is used as key for the class_map
--                           table
--                  class_map a table whose keys must represent
--                            valid return values of the instance
--                            method given by the 'method' name
--                            above.  The corresponding value must
--                            be the name of the header class that
--                            parses this particular ULP
--
-- For example, an ethernet header could use
--
-- local ether_header_t = ffi.typeof[[
-- struct {
--    uint8_t  ether_dhost[6];
--    uint8_t  ether_shost[6];
--    uint16_t ether_type;
-- } __attribute__((packed))
-- ]]
--
-- ethernet._name = "ethernet"
-- ethernet._header_type = ether_header_t
-- ethernet._header_ptr_type = ffi.typeof("$*", ether_header_t)
-- ethernet._ulp = { 
--    class_map = { [0x86dd] = "lib.protocol.ipv6" },
--    method    = 'type' }
--
-- In this case, the ULP is identified by the "type" method, which
-- would return the value of the ether_type element.  In this example,
-- only the type value 0x86dd is defined, which is mapped to the class
-- that handles IPv6 headers.
--
-- The initializer for the standard constructor new() will typically
-- allocate an instance of _header_type and initialize it, e.g.
--
-- function ethernet:_init_new (config)
--    local header = ether_header_t()
--    ffi.copy(header.ether_dhost, config.dst, 6)
--    ffi.copy(header.ether_shost, config.src, 6)
--    header.ether_type = C.htons(config.type)
--    self._header = header
-- end
--
-- The header class provides an additional constructor called
-- new_from_mem() that interprets a chunk of memory as a protocol
-- header using ffi.cast(). A header that requires more sophisticated
-- initialization (e.g. variably-sized headers whose actual size
-- depends on the contents on the header) must over ride the
-- _init_new_from_mem() method.

local ffi = require("ffi")

local header = subClass(nil, 'new_from_mem')

function header:_init_new_from_mem (mem, size)
   assert(ffi.sizeof(self._header_type) <= size)
   self._header = ffi.cast(self._header_ptr_type, mem)[0]
end

function header:header ()
   return self._header
end

function header:name ()
   return self._name
end

function header:sizeof ()
   return ffi.sizeof(self._header)
end

-- Copy the header to some location in memory (usually a packet
-- buffer).  The caller must make sure that there is enough space at
-- the destination.
function header:copy (dst)
   ffi.copy(dst, self._header, ffi.sizeof(self._header))
end

-- Create a new protocol instance that is a copy of this instance.
-- This is horribly inefficient and should not be used in the fast
-- path.
function header:clone ()
   local header = self._header_type()
   local sizeof = ffi.sizeof(header)
   ffi.copy(header, self._header, sizeof)
   return self:class():new_from_mem(header, sizeof)
end

-- Return the class that can handle the upper layer protocol or nil if
-- the protocol is not supported or the protocol has no upper-layer.
function header:upper_layer ()
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

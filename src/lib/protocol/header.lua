-- Protocol header base class
--
-- This is an abstract class (should not be instantiated)
--
-- Derived classes must implement the following class variables
--
-- _name          a string that describes the header type in a
--                human readable form
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
-- In the simplest case, a protocol header consists of a single data
-- structure of a fixed size, e.g. an untagged Ethernet II header.
-- Such headers are supported by this framework in a straight forward
-- manner.  More complex headers may have representations that differ
-- in size and structure, depending on the use-case, e.g. GRE.
-- Headers of that kind can be supported as long as all variants can
-- be enumerated and represented by a separate fixed-sized data
-- structure.  This requirement is necessary because all data
-- structures must be pre-allocated for performance reasons and to
-- support the instance recycling mechanism of the class framework.
-- Each header is described by a ctype object that serves as a
-- template for the header.
--
-- A protocol header can be created in two different manners.  In the
-- first case (provided by the new() constructor method), the protocol
-- instance contains the header structure itself, where as in the
-- second case (provided by the new_from_mem() constructor), the
-- protocol instance contains a pointer to an arbitrary location in
-- memory where the actual header resides (usually a packet buffer).
-- The pointer is cast to the appropriate ctype to access the fields
-- of the header.
--
-- To support the second mode of creation for protocols with variable
-- header structures, one of the headers must be designated as the
-- "base header".  It must be chosen such that it contains enough
-- information to determine the actual header that is present in
-- memory.
--
-- The constructors in the header base class deal exclusively with the
-- base header, i.e. the instances created by the new() and
-- new_from_mem() methods only provide access to the fields present in
-- the base header.  Protocols that implement variable headers must
-- extend the base methods to select the appropriate header variant.
--
-- The header class uses the following data structures to support this
-- mechanism.  Each header variant is described by a table with the
-- following elements
--
--   t      the ctype that represents the header itself
--   ptr_t  a ctype constructed by ffi.typeof("$*", ctype) used for
--          casting of pointers
--   box_t  a ctype that represents a "box" to store a ptr_t, i.e.
--          ffi.typeof("$[1]", ptr_t)
--
-- These tables are stored as an array in the class variable _headers,
-- where, by definition, the first element designates the base header.
-- 
-- This array is initialized by the class method init(), which must be
-- called by every derived class.
--
-- When a new instance of a protocol class is created, it receives its
-- own, private array of headers stored in the instance variable of
-- the same name.  The elements from the header tables stored in the
-- class are inherited by the instance by means of setmetatable().
-- For each header, one instance of the header itself and one instance
-- of a box are created from the t and box_t ctypes, respectively.
-- These objects are stored in the keys "data" and "box" and are
-- private to the instance.  The following schematic should make the
-- relationship clearer
--
-- class._headers = {
--     [1] = { t     = ...,
--             ptr_t = ...,
--             box_t = ...,
--           }, <---------------+
--     [2] = { t     = ...,     |
--             ptr_t = ...,     |
--             box_t = ...,     |
--           }, <------------+  |
--     ...                   |  |
--   }                       |  |
--                           |  |
-- instance._headers = {     |  |
--     [1] = { data = t(),   |  |
--             box  = box_t()|  |
--           }, ----------------+ metatable
--     [2] = { data = t(),   |
--             box  = box_t()|
--           }, -------------+ metatable
--     ...
--   }
--
-- The constructors of the base class store a reference to the base
-- header (i.e. _headers[1]) in the instance variable _header.  In
-- other words, the box and data can be accessed by dereferencing
-- _header.data and _header.box, respectively.
--
-- This initialization is common to both constructors.  The difference
-- lies in the contents of the pointer stored in the box.  The new()
-- constructor stores a pointer to the data object, i.e.
--
--   _header.box[0] = ffi.cast(_header.ptr_t, _header.data)
--
-- where as the new_from_mem() constructor stores the pointer to the
-- region of memory supplied as argument to the method call, i.e.
--
--   _header.box[0] = ffi.cast(_header.ptr_t, mem)
--
-- In that case, the _header.data object is not used at all.
--
-- When a derived class overrides these constructors, it should first
-- call the construcor of the super class, which will initialize the
-- base header as described above.  An extension of the new() method
-- will replace the reference to the base header stored in _header by
-- a reference to the header variant selected by the configuration
-- passed as arguments to the method, i.e. it will eventually do
--
--   _header = _headers[foo]
--
-- where <foo> is the index of the selected header.
--
-- An extension of the new_from_mem() constructor uses the base header
-- to determine the actual header variant to use and override the base
-- header with it.
--
-- Refer to the lib.protocol.ethernet and lib.protocol.gre classes for
-- examples.
--
-- For convenience, the class variable class._header exists as well
-- and contains a reference to the base header class._headers[1].
-- This promotes the instance methods sizeof() and ctype() to class
-- methods, which will provide the size and ctype of a protocol's base
-- header from the class itself.  For example, the size of an ethernet
-- header can be obtained by
--
--  local ethernet = require("lib.protocol.ethernet")
--  local ether_size = ethernet:sizeof()
--
-- without creating an instance first.

module(..., package.seeall)
local ffi = require("ffi")

local header = subClass(nil)

-- Class methods

-- Initialize a subclass with a set of headers, which must contain at
-- least one element (the base header).
function header:init (headers)
   assert(self and headers and #headers > 0)
   self._singleton_p = #headers == 1
   local _headers = {}
   for i = 1, #headers do
      local header = {}
      local ctype = headers[i]
      header.t = ctype
      header.ptr_t = ffi.typeof("$*", ctype)
      header.box_t = ffi.typeof("$*[1]", ctype)
      header.meta = { __index = header }
      _headers[i] = header
   end
   self._headers = _headers
   self._header = _headers[1]
end

-- Initialize an instance of the class.  If the instance is new (has
-- not been recycled), an instance of each header struct and a box
-- that holds a pointer to it are allocated.  A reference to the base
-- header is installed in the _header instance variable.
local function _new (self)
   local o = header:superClass().new(self)
   if not o._recycled then
      -- Allocate boxes and headers for all variants of the
      -- classe's header structures
      o._headers = {}
      for i = 1, #self._headers do
         -- This code is only executed when a new instance is created
         -- via the class construcor, i.e. self is the class itself
         -- (as opposed to the case when an instance is recycled by
         -- calling the constructor as an instance method, in which
         -- case self would be the instance instead of the class).
         -- This is why it is safe to use self._headers[i].meta as
         -- metatable here.  The effect is that the ctypes are
         -- inherited from the class while the data and box table are
         -- private to the instance.
         local _header = setmetatable({}, self._headers[i].meta)
         _header.data = _header.t()
         _header.box  = _header.box_t()
         o._headers[i] = _header
      end
   end
   -- Make the base header the active header
   o._header = o._headers[1]
   return o
end

-- Initialize the base protocol header with 0 and store a pointer to
-- it in the header box.
function header:new ()
   local o = _new(self)
   local header = o._header
   ffi.fill(header.data, ffi.sizeof(header.t))
   header.box[0] = ffi.cast(header.ptr_t, header.data)
   return o
end

-- This alternative constructor creates a protocol header from a chunk
-- of memory by "overlaying" a header structure.  In this mode, the
-- protocol ctype _header.data is unused and _header.box stores the
-- pointer to the memory location supplied by the caller.
function header:new_from_mem (mem, size)
   local o = _new(self)
   local header = o._header
   assert(ffi.sizeof(header.t) <= size)
   header.box[0] = ffi.cast(header.ptr_t, mem)
   return o
end

-- Instance methods

-- Return a reference to the header
function header:header ()
   return self._header.box[0][0]
end

-- Return a pointer to the header
function header:header_ptr ()
   return self._header.box[0]
end

-- Return the ctype of header
function header:ctype ()
   return self._header.t
end

-- Return the size of the header
function header:sizeof ()
   return ffi.sizeof(self._header.t)
end

-- Return true if <other> is of the same type and contains identical
-- data, false otherwise.
function header:eq (other)
   local ctype = self:ctype()
   local size = self:sizeof()
   local other_ctype = other:ctype()
   return (ctype == other_ctype and
           ffi.string(self:header_ptr(), size) ==
        ffi.string(other:header_ptr(), size))
end

-- Copy the header to some location in memory (usually a packet
-- buffer).  The caller must make sure that there is enough space at
-- the destination.  If relocate is a true value, the copy is promoted
-- to be the active storage of the header.
function header:copy (dst, relocate)
   ffi.copy(dst, self:header_ptr(), self:sizeof())
   if relocate then
      self._header.box[0] = ffi.cast(self._header.ptr_t, dst)
   end
end

-- Create a new protocol instance that is a copy of this instance.
-- This is horribly inefficient and should not be used in the fast
-- path.
function header:clone ()
   local header = self:ctype()()
   local sizeof = ffi.sizeof(header)
   ffi.copy(header, self:header_ptr(), sizeof)
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

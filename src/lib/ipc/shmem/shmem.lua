-- The shmem base class provides a simple IPC mechanism to exchange
-- arbitrary cdata objects with other processes through a file-backed
-- shared memeory region.
--
-- A new empty region is created by calling the constructor with a
-- filename and optional directory, where the file should be created.
--
--  local shmem = require("lib.ipc.shmem.shmem")
--  local foo = shmem:new({ filename = "foo", directory = "/tmp" })
--
-- If omitted, the directory defaults to "/tmp/snabb-shmem".  The
-- constructor creates an empty file called the "data file" with the
-- given name and maps it into the processe's virtual memory.  In
-- addition, it creates an "index file" by appending the suffix
-- ".index" to the data file name.  The first line of the index file
-- contains a string that identifies the name space to which the
-- memory region belongs, followed by a colon, followed by an integer
-- version number.  The name space indicates how the rest of the index
-- file needs to be interpreted.  A name space is tied to the subclass
-- that implements it (but a subclass may inherit the name space of
-- its ancestor class).  The version number allows for changes of the
-- index format within the name space.
--
-- The base class provides the name space "default", i.e. the header
-- line of the index file for version 1 contains the string "default:1".
--
-- The default name space contains a single line in the index file for
-- every object stored in the memory region.  The order of the
-- descriptions must be the same as that of the objects.  A
-- description consists of an arbitrary name, followd by a colon,
-- followed by the length of the corresponding object in bytes.  For
-- example, the index file
--
--   default:1
--   foo:4
--   bar:7
--
-- Describes a memory region of length 11, which contains an object
-- named 'foo' that consists of 4 bytes starting at offset 0 and an
-- object named 'bar' consisting of 7 bytes starting at offset 4.  The
-- type of the object is implied by its name and is not part of the
-- description in the index. Each name must be unique.
--
-- An object is added to the region by calling the method register(),
-- which takes a string, a ctype object and an optional value as
-- arguments.  The ctype must refer to a complete type such that the
-- size of the object is fixed when it is added to the index.  The
-- following example adds an unsigned 32-bit number called "counter"
-- and a struct named "bar":
--
--  local counter_t = ffi.typeof("uint32_t")
--  local bar_t = ffi.typeof("struct { uint8_t x; char string[10]; }")
--  foo:register("counter", counter_t, 42)
--  foo:register("bar", bar_t)
--
-- The index file now contains
--
--  default:1
--  counter:4
--  bar:11
--
-- The contents of the objects can be changed by the set() method
--
--  foo:set("counter", 1)
--  foo:set("bar", bar_t({ x = 1, string = 'bar' }))
--
-- The provided value must be of the correct type or must be
-- convertible to it.  The assignment is performed by de-referencing
-- the address of the object as a pointer, equivalent to (where
-- "ctype" is the ctype object passed to the register() method)
--
--  ffi.cast(ffi.typeof("$*", ctype), address)[0] = value
--
-- The get() method returns just a reference to the object
--
--  ffi.cast(ffi.typeof("$*", ctype), address)[0]
--
-- For certain types, this will result in a Lua object, complex data
-- types are represented as references
--
--  print(type(foo:get("counter")))  --> number
--  print(type(foo:get("bar")))      --> cdata<struct 403 &>: 0x7f2ce4efb004
--
-- Be aware that assignments to the latter will change the underlying
-- object, while simple objects obtained from get() are distinct from
-- the underlying object.
--
-- To manipulate any type of object "in place", one first obtains a
-- pointer to the object by calling the ptr() method and de-references
-- that pointer
--
--  local c = test:ptr("counter")
--  c[0] = 42
--  print(test:get("counter")) --> 42
--
-- When an object is added with register(), the shared memory region
-- is grown by first unmapping the region and then re-mapping it.  The
-- new mapping ist not guaranteed to be at the same virtual address.
-- Therefore, using the address of an object across calls to
-- register() is unsafe.  The dictionary() method can be used to
-- obtain a table of pointers to all currently registered objects for
-- efficient access.
module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C

require("lib.ipc.shmem.shmem_h")

local shmem = subClass(nil)
shmem._name = "shared memory base class"

---- Class variables
-- Should be overridden by derived classes
shmem._namespace = "default:1"
-- The character(s) used as field separator in the index file.  Can be
-- overriden by derived classes.  Object names that contain the field
-- separator are considered illegal by the register() method.  A value
-- of '' suppresses the length field in the index file.
shmem._fs = ':'

local defaults =  {
   directory = '/tmp',
}

---- Class methods

-- Options:
-- { filename = <filename>,
--   [ directory = <directory>, ] Default: /tmp/snabb-shmem
-- }
--
function shmem:new (options)
   assert(options and options.filename) 
   local o = shmem:superClass().new(self)
   local dir = options.directory or defaults.directory
   if dir ~= '' then
      o._data_filename = table.concat({ dir, options.filename}, '/')
   else
      o._data_filename = options.filename
   end
   o._data_fh = assert(io.open(o._data_filename, 'w+'))
   o._index_filename = o._data_filename..".index"
   o._index_fh = assert(io.open(o._index_filename, 'w+'))
   assert(o._index_fh:write(o._namespace, '\n'))
   assert(o._index_fh:flush())
   o._size = 0
   o._base = nil
   o._objs = {}
   o._objs_t = {}
   o._h_to_n = {} -- Maps handle to name
   o._n_to_h = {} -- Maps name to handle
   o._nobjs = 0
   return o
end

---- Instance methods

-- Append an object with the given name and ctype to the shared memory
-- region and add its description to the index file.  If a value is
-- supplied, the object is initialized with it via the set() method.
--
-- The objects are stored in the order in which they are registered.
-- The method returns the position of the object within this sequence,
-- starting with 1 for the first object.  This number can be used with
-- the tables obtained from the dictionary() method for more efficient
-- access to the objects once registration is completed.  The number
-- is also referred to as the "handle" of the object.
--
-- The method aborts if the memeory region can't be grown via
-- munmap()/mmap() or if the updating of the index file fails.
function shmem:register (name, ctype, value)
   assert(name and ctype)
   assert(not self._objs[name], "object already exists: "..name)
   assert(self._fs == '' or not string.find(name, self._fs),
	  "illegal object name: "..name)
   local length = ffi.sizeof(ctype)
   -- Store the location of the object as an offset relative to the
   -- base, because the base may change across calls to shmem_grow()
   -- The object's description is stored in two tables by name and by
   -- handle.
   local obj = { offset    = self._size,
		 ctype     = ctype,
		 ctype_ptr = ffi.typeof("$*", ctype),
		 length    = length }
   self._objs[name] = obj
   local handle = self._nobjs+1
   self._nobjs = handle
   self._objs_t[handle] = obj
   self._h_to_n[handle] = name
   self._n_to_h[name] = handle
   local new_size = self._size + length
   self._base = C.shmem_grow(self._data_fh, self._base,
			    self._size, new_size)
   assert(self._base ~= nil, "mmap failed")
   self._size = new_size
   self:set(name, value)
   local line = name
   if self._fs and self._fs ~= '' then
      line = line..self._fs..length
   end
   assert(self._index_fh:write(line, '\n'))
   assert(self._index_fh:flush())
   return handle
end

-- Return the base address of the mapped memory region.  It is unsafe
-- to use this value across calls to the register() method, because
-- the region may be moved during the munmap()/mmap() procedure.
function shmem:base ()
   return self._base
end

-- Return a table of pointers to all currently registered objects as
-- per the ptr() method, together with a table that contains the
-- mapping from handles to object names and a table that contains the
-- reverse mappings (from names to handles).  An object can then be
-- accessed by dereferencing the pointer at the given slot, e.g.
--
--  register:shmem('foo', ffi.typeof("uint64_t"))
--  local objs, h_to_n, n_to_h = shmem:dictionary()
--  objs[n_to_h.foo][0] = 0xFFULL
--
-- The intended usage is to first register() all objects, then use
-- this method to pre-compute all pointers for efficient access.
function shmem:dictionary()
   local table = {}
   for i = 1, self._nobjs do
      table[i] = self:ptr(self._h_to_n[i])
   end
   return table, self._h_to_n, self._n_to_h
end

local function get_obj(self, name)
   local obj = self._objs[name]
   if obj == nil then
      error("unkown object: "..(name or '<no name>'))
   end
   return obj
end

-- Set a named object to the given value.  
function shmem:set (name, value)
   if value ~= nil then
      local obj = get_obj(self, name)
      ffi.cast(obj.ctype_ptr, self._base + obj.offset)[0] = value
   end
end

-- Return the value of a named object by de-referencing the pointer to
-- its location in memory.  This will trigger conversions to Lua types
-- where applicable.  For more complex cdata objects, the returned
-- value will be a reference to the object.
function shmem:get (name)
   local obj = get_obj(self, name)
   return ffi.cast(obj.ctype_ptr, self._base + obj.offset)[0]
end

-- Return the address of the named object in memory as a pointer to
-- the object's ctype.  The object itself can be accessed by
-- de-referencing this pointer.
function shmem:ptr (name)
   local obj = get_obj(self, name)
   return ffi.cast(obj.ctype_ptr, self._base + obj.offset)
end

-- Return the ctype of the named object as provided by the "ctype"
-- argument to the register() method when the object was created.
function shmem:ctype (name)
   local obj = get_obj(self, name)
   return obj.ctype
end

function selftest ()
   local test = shmem:new({ filename = 'selftest', directory = '' })
   local bar_t = ffi.typeof("struct { uint8_t x; char string[10]; }")
   test:register("counter", ffi.typeof("uint32_t"))
   test:register('bar', bar_t)
   test:set('bar', bar_t({ x = 1, string = 'foo'}))
   local bar = test:get('bar')
   local bar_ptr = test:ptr('bar')
   assert(bar.x == 1)
   assert(ffi.string(bar.string) == 'foo')
   assert(bar_ptr[0].x == 1)
   assert(ffi.string(bar_ptr[0].string) == 'foo')

   local ifile = assert(io.open("selftest.index", "r"))
   local cfile = assert(io.open("selftest", "r"))
   local function fields(fh)
      local next, field = ifile:read('*l'):split(':')
      return next(field), next(field)
   end

   -- Check header
   local namespace, version = fields(ifile)
   assert(namespace == 'default')
   assert(tonumber(version) == 1)

   -- Check names
   local name, len = fields(ifile)
   assert(name == 'counter' and tonumber(len) == 4)
   name, len = fields(ifile)
   assert(name == 'bar' and tonumber(len) == 11)

   -- Check dictionary
   local t, h_to_n, n_to_h = test:dictionary()
   assert(#t == 2)
   assert(h_to_n[1] == 'counter' and n_to_h['counter'] == 1)
   assert(h_to_n[2] == 'bar' and n_to_h['bar'] == 2)
   t[1][0] = 0xdeadbeef
   t[2][0] = bar_t({ x = 2, string = 'bar'})
   assert(test:get('counter') == 0xdeadbeef)
   assert(test:get('bar').x == 2)
   assert(ffi.string(test:get('bar').string) == 'bar')
   os.remove('selftest')
   os.remove('selftest.index')
   print("ok")
end

shmem.selftest = selftest

return shmem

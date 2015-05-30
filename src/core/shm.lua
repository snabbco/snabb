-- shm.lua -- shared memory alternative to ffi.new()

-- Provide a simple API for allocating FFI objects in shared
-- memory. Each object is created with a name and a C type. Objects
-- can be mapped any number of times by any process. The objects are
-- named and allocated using POSIX shared memory (shm_open(3)) so they
-- can be easily accessed from other software too.
--
-- Objects are backed by files on ramdisk. They are freed when they
-- are unlinked from their names and when all mappings have been
-- closed, or at reboot.
--
-- API:
--   create(name, type) -- allocate a shared object
--   unlink(name)       -- unlink an object for automatic deallocation
--   map(name) => ptr   -- map an object into memory for access
--   unmap(ptr)         -- delete a memory mapping (NYI)
--
-- See selftest() method for an example.
--
-- This is intended to support up to thousands of mappings per
-- process. Linux default limits on the number of memory mappings per
-- process is 65530:
--     $ sysctl vm.max_map_count
--     vm.max_map_count = 65530

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local S = require("syscall")

-- Create a new named object with a given type.
--
-- create("test.foo", "uint64_t[1]") creates two files on ram disk:
--   /dev/shm/test.foo.T: contains string "uint64_t[1]\n"
--   /dev/shm/test.foo:   contains the 8-byte value
--
-- Return true on success or otherwise nil and an error.
function create (name, type)
   local ctype = ffi.typeof(type)
   local size = ffi.sizeof(ctype)
   -- Create shared memory object for value
   local fd, err = S.shm_open(name, 'wronly, creat', 'rwxu')
   if not fd then return nil, err end
   assert(fd:ftruncate(size), "ftruncate failed")
   assert(fd:close(), "close failed")
   -- Create shared memory object for type
   local fd, err = S.shm_open(name..".T", 'wronly, creat, trunc', 'rwxu')
   if not fd then return nil, err end
   assert(fd:write(type), "write failed")
   assert(fd:write("\n"), "write failed")
   assert(fd:close(), "close failed")
   return name
end

-- Unlink a shared memory object. The memory for the value will be
-- freed when all mappings are deleted.
--
-- unlink("test.foo") deletes two files:
--   /dev/shm/test.foo.T
--   /dev/shm/test.foo
function unlink (name)
   S.shm_unlink(name)
   S.shm_unlink(name..".T")
end

-- Map the named shared memory object.
-- Return a pointer to the mapped value.
function map (name)
   -- Read type
   local fd, err = S.shm_open(name..".T", 'rdonly')
   if fd == nil then error("shm_open " .. name .. ".T:" .. tostring(err)) end
   local type = fd:read(nil, 10240)
   fd:close()
   local ok, ctype = pcall(ffi.typeof, type)
   if not ok then error("bad type: " .. tostring(type)) end
   -- Map value
   local fd, err = S.shm_open(name, 'rdwr')
   if not fd then error("shm_open " .. name .. ": " .. tostring(err)) end
   local stat = assert(fd:stat(), "stat failed")
   local mem, err = S.mmap(nil, stat.size, "read, write", "shared", fd, 0)
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   return ffi.cast(ffi.typeof("$&", ctype), mem)
end

-- Delete a shared memory mapping.
function unmap (pointer)
   -- Consider implementing this directly in ljsyscall i.e. for mmap()
   -- to return a pointer with an unmap() FFI metamethod that already
   -- knows the correct size (stored in a closure). This could also be
   -- automatically called on GC. 
   --
   -- This idea is already considered in a TODO comment in ljsyscall.
   error("NYI")
end

function selftest ()
   print("selftest: shm")
   print("create shm.selftest")
   create("shm.selftest", "struct { int x, y, z; }")
   local p1 = map("shm.selftest")
   local p2 = map("shm.selftest")
   assert(p1 ~= p2)
   assert(p1.x == p2.x)
   p1.x = 42
   assert(p1.x == p2.x)
   unlink("shm.selftest")
   local ok, err = pcall(map, "shm.selftest")
   assert(not ok, "map() of unlinked object should fail")
   selftest_many_objects(10000)
   print("selftest ok")
end

function selftest_many_objects (n)
   for i = 0, n do create("shm.selftest."..i, "uint64_t[1]") end
   print(n.." objects created")
   for i = 0, n do map("shm.selftest."..i) end
   print(n.." objects mapped")
   for i = 0, n do unlink("shm.selftest."..i) end
   print(n.." objects unlinked")
end


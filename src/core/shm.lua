-- shm.lua -- shared memory alternative to ffi.new()

-- API:
--   shm.map(name, type[, readonly]) => ptr
--     Map a shared object into memory via a heirarchical name.
--   shm.unmap(ptr)
--     Delete a memory mapping.
--   shm.unlink(path)
--     Unlink a subtree of objects from the filesystem.
-- 
-- Example:
--   local freelist = shm.map("engine/freelist/packet", "struct freelist")
-- 
-- This is like ffi.new() except that separate calls to map() for the
-- same name will each return a new mapping of the same shared
-- memory. Different processes can share memory by mapping an object
-- with the same name (and type). Each process can map any object any
-- number of times.
--
-- Mappings are deleted on process termination or with an explicit unmap:
--   shm.unmap(freelist)
--
-- Names are unlinked from objects that are no longer needed:
--   shm.unlink("engine/freelist/packet")
--   shm.unlink("engine")
--
-- Object memory is freed when the name is unlinked and all mappings
-- have been deleted.
--
-- Behind the scenes the objects are backed by files on ram disk:
--   /var/run/engine/freelist/packet
--
-- and accessed with the equivalent of POSIX shared memory (shm_overview(7)).
--
-- The practical limit on the number of objects that can be mapped
-- will depend on the operating system limit for memory mappings.
-- On Linux the default limit is 65,530 mappings:
--     $ sysctl vm.max_map_count
--     vm.max_map_count = 65530

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local S = require("syscall")

-- Root directory where the object tree is created.
local prefix = "/var/run"

-- Table (address->size) of all currently mapped objects.
mappings = {}

-- Map an object into memory.
function map (name, type,  readonly)
   local mapmode = readonly and 'read' or 'read, write'
   local ctype = ffi.typeof(type)
   local size = ffi.sizeof(ctype)
   local stat = S.stat(prefix.."/"..name)
   if stat and stat.size ~= size then
      print(("shm warning: resizing %s from %d to %d bytes")
            :format(name, stat.size, size))
   end
   -- Create the parent directories. If this fails then so will the open().
   mkdir(name)
   local fd, err = S.open(prefix.."/"..name, "creat, rdwr", "rwxu")
   if not fd then error("shm open error ("..name.."):"..tostring(err)) end
   assert(fd:ftruncate(size), "shm: ftruncate failed")
   local mem, err = S.mmap(nil, size, mapmode, "shared", fd, 0)
   fd:close()
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   mappings[pointer_to_number(mem)] = size
   return ffi.cast(ffi.typeof("$&", ctype), mem)
end

-- Make directories needed for a named object.
-- Given the name "foo/bar/baz" create /var/run/foo and /var/run/foo/bar.
function mkdir (name)
   local dir = prefix
   name:gsub("([^/]+)/",
             function (x) dir = dir.."/"..x  S.mkdir(dir, "rwxu") end)
end

-- Delete a shared object memory mapping.
-- The pointer must have been returned by map().
function unmap (ptr)
   local size = mappings[pointer_to_number(ptr)]
   assert(size, "shm mapping not found")
   S.munmap(ptr, size)
   mappings[pointer_to_number(ptr)] = nil
end

function pointer_to_number (ptr)
   return tonumber(ffi.cast("uint64_t", ffi.cast("void*", ptr)))
end

-- Unlink names from their objects.
function unlink (name)
   return S.util.rm(prefix.."/"..name) -- recursive rm of file or directory
end

function selftest ()
   print("selftest: shm")
   local name = "snabb/selftest/obj"
   print("create "..name)
   local p1 = map(name, "struct { int x, y, z; }")
   local p2 = map(name, "struct { int x, y, z; }")
   assert(p1 ~= p2)
   assert(p1.x == p2.x)
   p1.x = 42
   assert(p1.x == p2.x)
   assert(unlink(name))
   unmap(p1)
   unmap(p2)
   -- Test that we can open and cleanup many objects
   local n = 10000
   local objs = {}
   for i = 1, n do
      table.insert(objs, map("snabb/selftest/obj."..i, "uint64_t[1]"))
   end
   print(n.." objects created")
   for i = 1, n do unmap(objs[i]) end
   print(n.." objects unmapped")
   assert(unlink("snabb/selftest"))
   print("selftest ok")
end


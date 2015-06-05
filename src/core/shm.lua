-- shm.lua -- shared memory alternative to ffi.new()

-- API:
--   shm.map(name, type[, readonly]) => ptr
--     Map a shared object into memory via a heirarchical name.
--   shm.unmap(ptr)
--     Delete a memory mapping.
--   shm.unlink(path)
--     Unlink a subtree of objects from the filesystem.
--
-- (See NAME SYNTAX below for recognized name formats.)
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
--   /var/run/snabb/$pid/engine/freelist/packet
--
-- and accessed with the equivalent of POSIX shared memory (shm_overview(7)).
--
-- The practical limit on the number of objects that can be mapped
-- will depend on the operating system limit for memory mappings.
-- On Linux the default limit is 65,530 mappings:
--     $ sysctl vm.max_map_count
--     vm.max_map_count = 65530

-- NAME SYNTAX:
-- 
-- Names can be fully qualified, abbreviated to be within the current
-- process, or further abbreviated to be relative to the current value
-- of the 'path' variable. Here are examples of names and how they are
-- resolved:
--   Fully qualified:
--     //snabb/1234/foo/bar => /var/run/snabb/1234/foo/bar
--   Path qualified:
--     /foo/bar             => /var/run/snabb/$pid/foo/bar
--   Local:
--     bar                  => /var/run/snabb/$pid/$path/bar
-- .. where $pid is the PID of this process and $path is the current
-- value of the 'path' variable in this module.


module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local S = require("syscall")

-- Root directory where the object tree is created.
root = "/var/run/snabb"
path = ""

-- Table (address->size) of all currently mapped objects.
mappings = {}

-- Map an object into memory.
function map (name, type,  readonly)
   local path = resolve(name)
   local mapmode = readonly and 'read' or 'read, write'
   local ctype = ffi.typeof(type)
   local size = ffi.sizeof(ctype)
   local stat = S.stat(root..'/'..path)
   if stat and stat.size ~= size then
      print(("shm warning: resizing %s from %d to %d bytes")
            :format(path, stat.size, size))
   end
   -- Create the parent directories. If this fails then so will the open().
   mkdir(path)
   local fd, err = S.open(root..'/'..path, "creat, rdwr", "rwxu")
   if not fd then error("shm open error ("..path.."):"..tostring(err)) end
   assert(fd:ftruncate(size), "shm: ftruncate failed")
   local mem, err = S.mmap(nil, size, mapmode, "shared", fd, 0)
   fd:close()
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   mappings[pointer_to_number(mem)] = size
   return ffi.cast(ffi.typeof("$&", ctype), mem)
end

function resolve (name)
   local q, p = name:match("^(/*)(.*)") -- split qualifier (/ or //)
   local result = p
   if q == '' and path ~= '' then result = path.."/"..result end
   if q ~= '//'              then result = tostring(S.getpid()).."/"..result end
   return result
end

-- Make directories needed for a named object.
-- Given the name "foo/bar/baz" create /var/run/foo and /var/run/foo/bar.
function mkdir (name)
   local dir = root
   name:gsub("([^/]+)",
             function (x) S.mkdir(dir, "rwxu")  dir = dir.."/"..x end)
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
   local path = resolve(name)
   -- Note: Recursive delete is dangerous, important it is under $root!
   return S.util.rm(root..'/'..path) -- recursive rm of file or directory
end

function selftest ()
   print("selftest: shm")
   print("checking paths..")
   path = 'foo/bar'
   pid = tostring(S.getpid())
   local p1 = resolve("//"..pid.."/foo/bar/baz/beer")
   local p2 = resolve("/foo/bar/baz/beer")
   local p3 = resolve("baz/beer")
   assert(p1 == p2, p1.." ~= "..p2)
   assert(p1 == p3, p1.." ~= "..p3)

   print("checking shared memory..")
   path = 'shm/selftest'
   local name = "obj"
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
   print("checking many objects..")
   path = 'shm/selftest/manyobj'
   local n = 10000
   local objs = {}
   for i = 1, n do
      table.insert(objs, map("obj/"..i, "uint64_t[1]"))
   end
   print(n.." objects created")
   for i = 1, n do unmap(objs[i]) end
   print(n.." objects unmapped")
   assert(unlink("/"))
   print("selftest ok")
end


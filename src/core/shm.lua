-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- shm.lua -- shared memory alternative to ffi.new()

module(..., package.seeall)

local ffi = require("ffi")
local lib = require("core.lib")
local S = require("syscall")
local const = require("syscall.linux.constants")

-- Root directory where the object tree is created.
root = os.getenv("SNABB_SHM_ROOT") or "/var/run/snabb"

-- Table (address->size) of all currently mapped objects.
mappings = {}

-- Map an object into memory.
local function map (name, type, readonly, create)
   local path = resolve(name)
   local mapmode = readonly and 'read' or 'read, write'
   local ctype = ffi.typeof(type)
   local size = ffi.sizeof(ctype)
   local stat = S.stat(root..'/'..path)
   if stat and stat.size ~= size then
      print(("shm warning: resizing %s from %d to %d bytes")
            :format(path, stat.size, size))
   end
   local fd, err
   if create then
      -- Create the parent directories. If this fails then so will the open().
      mkdir(lib.dirname(path))
      fd, err = S.open(root..'/'..path, "creat, rdwr", "rusr, wusr, rgrp, roth")
   else
      fd, err = S.open(root..'/'..path, readonly and "rdonly" or "rdwr")
   end
   if not fd then error("shm open error ("..path.."):"..tostring(err)) end
   if create then
      assert(fd:ftruncate(size), "shm: ftruncate failed")
   else
      assert(fd:fstat().size == size, "shm: unexpected size")
   end
   local mem, err = S.mmap(nil, size, mapmode, "shared", fd, 0)
   fd:close()
   if mem == nil then error("mmap failed: " .. tostring(err)) end
   mappings[pointer_to_number(mem)] = size
   return ffi.cast(ffi.typeof("$&", ctype), mem)
end

function create (name, type)
   return map(name, type, false, true)
end

function open (name, type, readonly)
   return map(name, type, readonly, false)
end

function exists (name)
   local path = resolve(name)
   local fd = S.open(root..'/'..path, "rdonly")
   return fd and fd:close()
end

function alias (name, target)
   mkdir(lib.dirname(resolve(name)))
   assert(S.symlink(root.."/"..resolve(target), root.."/"..resolve(name)))
end

function resolve (name)
   local q, p = name:match("^(/*)(.*)") -- split qualifier (/)
   local result = p
   if q ~= '/' then result = tostring(S.getpid()).."/"..result end
   return result
end

function path (name)
   return root..'/'..resolve(name)
end

-- Make the named subdirectory in the shm folder.
function mkdir (name)
   -- Create root with mode "rwxr-xr-x" if it does not exist yet.
   if not S.stat(root) then
      local mask = S.umask(0)
      local status, err = S.mkdir(root, "00755")
      assert(status or err.errno == const.E.EXIST, ("Unable to create %s: %s"):format(
                root, tostring(err or "unspecified error")))
      S.umask(mask)
   end
   -- Create sub directories
   local dir = root
   name:gsub("([^/]+)",
             function (x)
                dir = dir.."/"..x
                S.mkdir(dir, "rwxu, rgrp, xgrp, roth, xoth")
             end)
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

-- Return an array of objects under the prefix name.
-- The names are returned unqualified e.g. 'x' and not 'foo/bar/x'.
function children (name)
   -- XXX dirtable returns an array but with a special tostring metamethod.
   --     Potentially confusing? (Copy into plain array instead?)
   return S.util.dirtable(root.."/"..resolve(name), true) or {}
end

-- Type registry for modules that implement abstract shm objects.
types = {}
function register (type, module)
   assert(module, "Must supply module")
   assert(not types[type], "Duplicate shm type: "..type)
   types[type] = module
   return type
end

-- Create a directory of shm objects defined by specs under path.
function create_frame (path, specs)
   local frame = {}
   frame.specs = specs
   frame.path = path.."/"
   for name, spec in pairs(specs) do
      assert(frame[name] == nil, "shm: duplicate name: "..name)
      local module = spec[1]
      local initargs = lib.array_copy(spec)
      table.remove(initargs, 1) -- strip type name from spec
      frame[name] = module.create(frame.path..name.."."..module.type,
                                  unpack(initargs))
   end
   return frame
end

-- Open a directory of shm objects for reading, determine their types by file
-- extension.
function open_frame (path)
   local frame = {}
   frame.specs = {}
   frame.path = path.."/"
   frame.readonly = true
   for _, file in ipairs(children(path)) do
      local name, type = file:match("(.*)[.](.*)$")
      local module = types[type]
      if module then
         assert(frame[name] == nil, "shm: duplicate name: "..name)
         frame[name] = module.open(frame.path..file, 'readonly')
         frame.specs[name] = {module}
      end
   end
   return frame
end

-- Delete/unmap a frame of shm objects. The frame's directory is unlinked if
-- the frame was created by create_frame.
function delete_frame (frame)
   for name, spec in pairs(frame.specs) do
      local module = spec[1]
      if rawget(module, 'delete') then
         module.delete(frame.path..name.."."..module.type)
      else
         unmap(frame[name])
      end
   end
   if not frame.readonly then
      unlink(frame.path)
   end
end


function selftest ()
   print("selftest: shm")

   print("checking resolve..")
   pid = tostring(S.getpid())
   local p1 = resolve("/"..pid.."/foo/bar/baz/beer")
   local p2 = resolve("foo/bar/baz/beer")
   assert(p1 == p2, p1.." ~= "..p2)

   print("checking shared memory..")
   local name = "shm/selftest/obj"
   print("create "..name)
   local p1 = create(name, "struct { int x, y, z; }")
   local p2 = create(name, "struct { int x, y, z; }")
   assert(p1 ~= p2)
   assert(p1.x == p2.x)
   p1.x = 42
   assert(p1.x == p2.x)
   assert(unlink(name))
   unmap(p1)
   unmap(p2)

   print("checking exists..")
   assert(not exists(name))
   local p1 = create(name, "struct { int x, y, z; }")
   assert(exists(name))
   assert(unlink(name))
   unmap(p1)
   assert(not exists(name))

   -- Test that we can open and cleanup many objects
   print("checking many objects..")
   local path = 'shm/selftest/manyobj'
   local n = 10000
   local objs = {}
   for i = 1, n do
      table.insert(objs, create(path.."/"..i, "uint64_t[1]"))
   end
   print(n.." objects created")
   for i = 1, n do unmap(objs[i]) end
   print(n.." objects unmapped")
   assert((#children(path)) == n, "child count mismatch")
   assert(unlink("shm"))
   print("selftest ok")
end


-- Snabb Switch filesystem layout for IPC shmem files.

module(...,package.seeall)

local syscall = require("syscall")
local lib = require("core.lib")

local fs = {}
local default_root = "/var/run/snabb"

function fs:instances (root)
   return lib.files_in_directory(root or default_root)
end

function fs:exists (pid, root)
   local root = root or default_root
   return not not syscall.stat(fs_directory(root, pid))
end

function fs:new (pid, root)
   local root = root or default_root
   local pid = pid or syscall.getpid()
   local o = { directory = fs_directory(root, pid) }
   syscall.mkdir(root, "RWXU")
   syscall.mkdir(o.directory, "RWXU")
   return setmetatable(o, {__index = fs})
end

function fs:resource (name)
   return { filename = name, directory = self.directory }
end

function fs:delete ()
   for _, file in ipairs(lib.files_in_directory(self.directory)) do
      syscall_assert(syscall.unlink(self.directory.."/"..file))
   end
   syscall_assert(syscall.rmdir(self.directory))
end

function fs_directory (root, pid)
   return string.format("%s/%s", root, pid)
end

function syscall_assert (status, message)
   assert(status, tostring(message))
end

return fs

module(..., package.seeall)

local lib = require("core.lib")
local fs = require("lib.ipc.fs")
local syscall = require("syscall")
local usage = require("program.gc.README_inc")

local long_opts = {
   help = "h"
}

function run (args)
   local opt = {}
   function opt.h (arg) print(usage) main.exit(1) end
   args = lib.dogetopt(args, opt, "h", long_opts)

   if #args > 1 then print(usage) main.exit(1) end
   local root = args[1]

   for _, pid in ipairs(fs:instances(root)) do
      if not syscall.kill(tonumber(pid), 0) then
         fs:new(pid, root):delete()
      end
   end
end

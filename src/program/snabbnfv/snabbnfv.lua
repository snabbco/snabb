module(..., package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")
local usage = require("program.snabbnfv.README_inc")

function run (args)
   if #args == 0 then print(usage) main.exit(1) end
   local command = string.gsub(table.remove(args, 1), "-", "_")
   local modname = string.format("program.snabbnfv.%s.%s", command, command)
   if not lib.have_module(modname) then
      print(usage) main.exit(1)
   end
   require(modname).run(args)
end

